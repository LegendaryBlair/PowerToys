#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-pointer-contract-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
if('PtDesktop' -as [type]){throw 'Run these synthetic native boundaries in a fresh process.'}
Add-Type @'
using System;
public static class PtDesktop {
    public struct POINT { public int X,Y; }
    public static POINT Cursor;
    public static long Foreground=1;
    public static int Moves;
    public static bool ReadFails,MoveFails,SuppressMove;
    public static bool OwnedWindowAlive=true;
    public static bool IsWindow(IntPtr hwnd){return OwnedWindowAlive;}
    public static bool GetCursorPos(out POINT point){point=Cursor;return !ReadFails;}
    public static bool SetCursorPos(int x,int y){
        Moves++;
        if(MoveFails || Foreground==2)return false;
        if(!SuppressMove)Cursor=new POINT{X=x,Y=y};
        return true;
    }
    public static IntPtr GetForegroundWindow(){return new IntPtr(Foreground);}
}
'@
. "$PSScriptRoot\..\pt-state-snapshot.ps1"
function Assert-PtWindowIdentity {param($Identity)}
function Assert-PtForegroundOrAbort {param($Hwnd) [PtDesktop]::Foreground=$Hwnd}
function Get-PtWindowIdentity {param($Hwnd) [pscustomobject]@{hwnd=$Hwnd}}
function Require($condition,$message){if(-not $condition){throw $message}}
function Reject([scriptblock]$Action,[string]$Message){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Message){throw};return}
    throw "Expected rejection: $Message"
}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$point=[pscustomobject]@{X=20;Y=30}
[PtDesktop]::Cursor=[PtDesktop+POINT]@{X=20;Y=30}
[PtDesktop]::Foreground=2
Restore-PtPointerPosition $point|Out-Null
Require ([PtDesktop]::Moves -eq 0) 'Already restored pointer attempted forbidden input under elevated foreground'
$snapshot=[pscustomobject]@{coordinateSpace='Physical';pointer=$point;foreground=@{hwnd=2};windows=@()}
[PtDesktop]::Cursor=[PtDesktop+POINT]@{X=40;Y=50}
[PtDesktop]::Foreground=1
Restore-PtDesktopSnapshot $snapshot|Out-Null
Require ([PtDesktop]::Moves -eq 1 -and [PtDesktop]::Foreground -eq 2 -and [PtDesktop]::Cursor.X -eq 20) 'Pointer was not restored before higher-integrity foreground'
[PtDesktop]::Cursor=[PtDesktop+POINT]@{X=40;Y=50}
Reject {Restore-PtPointerPosition $point} 'SetCursorPos refused'
Require ([PtDesktop]::Cursor.X -eq 40) 'Refused pointer operation was presented as restoration'
[PtDesktop]::Foreground=1;[PtDesktop]::SuppressMove=$true
Reject {Restore-PtPointerPosition $point} 'comparison failed'
[PtDesktop]::SuppressMove=$false;[PtDesktop]::ReadFails=$true
$before=[PtDesktop]::Moves
Reject {Restore-PtPointerPosition $point} 'Cannot read pointer'
Require ([PtDesktop]::Moves -eq $before) 'Read failure still injected pointer movement'
[PtDesktop]::ReadFails=$false
Reject {Restore-PtPointerPosition @{X=20}} 'explicit integer'
Reject {Restore-PtDesktopSnapshot @{pointer=$point;foreground=@{hwnd=2};windows=@()}} 'unspecified coordinate units'
. "$PSScriptRoot\..\pt-owned-fixtures.ps1"
function Initialize-PtOwnedFixtures {}
function Assert-PtWindowIdentity {param($Identity)}
function Get-PtWindowIdentity {param($Hwnd) [pscustomobject]@{hwnd=$Hwnd}}
function Assert-PtForegroundOrAbort {
    param($Hwnd)
    if($Hwnd -eq 3){throw 'Hidden owned Explorer must not be activated for a no-op pointer restore.'}
    [PtDesktop]::Foreground=$Hwnd
}
$id=[guid]::NewGuid().ToString('N')
$folder=Join-Path $Workspace "pt-explorer-$id"
[IO.Directory]::CreateDirectory($folder)|Out-Null
$script:explorer=[pscustomobject]@{HWND=3;Document=[pscustomobject]@{Folder=[pscustomobject]@{Self=[pscustomobject]@{Path=$folder}}}}
$script:explorer|Add-Member ScriptMethod Quit {[PtDesktop]::OwnedWindowAlive=$false}
function Get-PtExplorerFixtureWindows {$script:explorer}
$fixture=[pscustomobject]@{Kind='Explorer';Id=$id;Workspace=$Workspace;Path=$folder
    ReceiptPath=(Join-Path $Workspace "fixture-$id.json");Desktop=$snapshot;Identity=@{hwnd=3;processId=11}
    ContentClosed=$false;Closed=$false}
[PtDesktop]::Cursor=[PtDesktop+POINT]@{X=20;Y=30};[PtDesktop]::Foreground=2
$before=[PtDesktop]::Moves
Remove-PtExplorerFixture $fixture|Out-Null
Require ($fixture.Closed -and -not [PtDesktop]::OwnedWindowAlive -and [PtDesktop]::Moves -eq $before) 'No-op hidden-window cleanup required foreground or pointer input'
[IO.File]::WriteAllText("$Workspace\results.json",'{"IdempotentReadOnlyRestore":"PASS","PointerBeforeForeground":"PASS","RefusalAndComparison":"PASS","InvalidReadAndCoordinates":"PASS","InteractiveDesktopUsed":false}')
"PASS: pointer ordering, no-op restoration and failure contracts; synthetic boundaries only. $Workspace"
