#requires -Version 7.2
$ErrorActionPreference='Stop'
Add-Type @'
using System;
public static class PtDesktop {
    public static bool Exists;
    public static bool IsWindow(IntPtr window) { return Exists; }
}
'@
. "$PSScriptRoot\..\pt-shell-transition.ps1"
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject($Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return $_}
    throw "Expected rejection: $Pattern"
}
function Reset-Fixture([string]$Class='XamlExplorerHostIslandWindow'){
    [PtDesktop]::Exists=$false
    $script:f=@{Visible=$true;Class=$Class;Title='Task View';Foreground=10L;Escapes=0;Entries=0
        Reused=$false;ReadError=$false;DisappearDuringRead=$false;EnumerationHidden=$false;MissingForegroundReads=0;Path=(Join-Path $env:WINDIR 'explorer.exe')}
}
function Get-PtNativeWindow {
    param([long]$Hwnd,[switch]$Visible)
    if($Hwnd){
        if($f.DisappearDuringRead){[PtDesktop]::Exists=$false;throw 'Window vanished during read'}
        if($f.ReadError){throw [ComponentModel.Win32Exception]::new(5)}
    }
    if([PtDesktop]::Exists -and (-not $Visible -or ($f.Visible -and -not $f.EnumerationHidden))){
        [pscustomobject]@{Hwnd=20L;ProcessId=30;ClassName=$f.Class;Title=$f.Title;Visible=$f.Visible}
    }
}
function Get-PtResourceProcessIdentity {param($ProcessId) [pscustomobject]@{path=$f.Path}}
function Get-PtWindowIdentity {param($Hwnd) [pscustomobject]@{hwnd=$Hwnd;processId=30;processStartTicks=40L;className=$f.Class}}
function Assert-PtWindowIdentity {param($Identity) if($f.Reused -and $Identity.hwnd -eq 20){throw 'Window identity changed'} }
function Get-PtForegroundWindow {
    if([PtDesktop]::Exists -and $f.MissingForegroundReads -gt 0){
        $f.MissingForegroundReads--
        $error=[InvalidOperationException]::new('No foreground during transition')
        $error.Data['PtDesktopStatus']='NoForeground'
        throw $error
    }
    if($f.Foreground -eq 20){[pscustomobject]@{Hwnd=20L;ProcessId=30;ClassName=$f.Class;Title=$f.Title}}
    else{[pscustomobject]@{Hwnd=10L;ProcessId=31;ClassName='Fixture';Title='Fixture'}}
}
function Assert-PtForegroundOrAbort {param($Hwnd) $f.Foreground=$Hwnd}
function Send-PtChord {
    param($Hwnd,$Mods,$Key)
    if($Key -eq 9){$f.Entries++;[PtDesktop]::Exists=$true;$f.Foreground=20}
    elseif($Key -eq 27){$f.Escapes++;[PtDesktop]::Exists=$false;$f.Foreground=10}
    else{throw 'Unexpected input'}
}
function Wait-PtCondition {
    param($Description,$TimeoutSeconds,$Probe)
    for($i=0;$i -lt 3;$i++){$value=& $Probe;if($value){return $value}}
    throw "Timeout: $Description"
}
$target=[pscustomobject]@{hwnd=10L}
foreach($class in 'MultitaskingViewFrame','XamlExplorerHostIslandWindow'){
    Reset-Fixture $class
    $transition=$null
    Invoke-PtTaskViewScope -TargetIdentity $target -Transition ([ref]$transition) -Action {param($surface) Require ($surface.hwnd -eq 20) 'Wrong surface'}
    Require ($transition.State -ceq 'Closed' -and $f.Escapes -eq 1 -and $f.Foreground -eq 10) 'Task View did not close normally.'
}
Reset-Fixture
$f.EnumerationHidden=$true
$transition=$null
Invoke-PtTaskViewScope $target ([ref]$transition) {}
Require ($transition.State -ceq 'Closed') 'Foreground-only Task View was missed by enumeration.'
Reset-Fixture
$f.MissingForegroundReads=2
$transition=$null
Invoke-PtTaskViewScope $target ([ref]$transition) {}
Require ($transition.State -ceq 'Closed' -and $f.Entries -eq 1) 'Transient absent foreground caused another activation or skipped cleanup.'
Reset-Fixture
[PtDesktop]::Exists=$true
$transition=$null
Reject {Invoke-PtTaskViewScope $target ([ref]$transition) {}} 'already exists'|Out-Null
Require ($f.Entries -eq 0 -and $f.Escapes -eq 0) 'Borrowed Task View received input.'
Reset-Fixture
$transition=$null
Reject {Invoke-PtTaskViewScope $target ([ref]$transition) {throw 'original action error'}} 'original action error'|Out-Null
Require ($transition.State -ceq 'Closed' -and $f.Escapes -eq 1) 'Action failure skipped normal cleanup.'
Reset-Fixture
$transition=$null
Invoke-PtTaskViewScope $target ([ref]$transition) {[PtDesktop]::Exists=$false}
Require ($transition.State -ceq 'Closed' -and $f.Escapes -eq 0) 'Destroyed HWND was read or received Escape.'
Reset-Fixture
[PtDesktop]::Exists=$true
$identity=Get-PtWindowIdentity 20
$f.Visible=$false
Require (Test-PtTrackedWindowClosed $identity -AllowHidden) 'Hidden closure was not accepted explicitly.'
Require (-not(Test-PtTrackedWindowClosed $identity)) 'Hidden window was confused with destruction.'
$f.Visible=$true;$f.DisappearDuringRead=$true
Require (Test-PtTrackedWindowClosed $identity) 'Read/disappearance race did not finish closure.'
[PtDesktop]::Exists=$true;$f.DisappearDuringRead=$false;$f.Reused=$true
Reject {Test-PtTrackedWindowClosed $identity} 'identity changed'|Out-Null
$f.Reused=$false;$f.ReadError=$true
Reject {Test-PtTrackedWindowClosed $identity} 'denied'|Out-Null
Reset-Fixture
$f.Title='Unrelated Shell surface'
$transition=$null
Reject {Invoke-PtTaskViewScope $target ([ref]$transition) {}} 'Timeout'|Out-Null
Require ($f.Escapes -eq 0 -and $transition.State -ceq 'Opening') 'Unknown Shell surface was adopted or dismissed.'
Reset-Fixture
$transition=$null
Reject {Invoke-PtTaskViewScope $target ([ref]$transition) {$f.Title='Unrelated Shell surface'}} 'no longer identifies Task View'|Out-Null
Require ($f.Escapes -eq 0) 'A repurposed Shell surface received Escape.'
'PASS: both Task View classes, pre-existing surface, action failure, destruction, hidden state, read race, reused HWND and denied read.'
