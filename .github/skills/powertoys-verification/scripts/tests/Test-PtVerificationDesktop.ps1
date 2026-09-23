#Requires -Version 7.4
param([string]$OutputDirectory=(Join-Path $env:TEMP "pt-desktop-tests-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\pt-verification-state.ps1')
. (Join-Path $PSScriptRoot '..\pt-verification-ui.ps1')
if([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'){throw 'Run this test with pwsh -STA.'}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PtFixtureDesktop {
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X,Y; }
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool GetPhysicalCursorPos(out Point point);
    [DllImport("user32.dll")] public static extern bool SetPhysicalCursorPos(int x,int y);
}
'@
$foreground=[PtVerification.Desktop]::GetForegroundWindow().ToInt64()
if(-not $foreground){throw 'Interactive foreground required; no desktop mutation attempted.'}
$originalWindow=Get-PtWindowIdentity $foreground
$pointer=[PtFixtureDesktop+Point]::new()
if(-not [PtFixtureDesktop]::GetPhysicalCursorPos([ref]$pointer)){throw 'Pointer snapshot failed'}
$run=New-PtRecordedRun $OutputDirectory 'owned helper fixtures; installed PowerToys is not modified' @(@{Id='desktop';AssertionIds=@('identity','clipboard','capture','uia')}) -InputPath $PSCommandPath
$root=$run.Workspace
$checks=[Collections.Generic.List[object]]::new()
function Require($Condition,$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern) {
    $errorRecord=$null; try{& $Action|Out-Null}catch{$errorRecord=$_}
    if(-not $errorRecord -or $errorRecord.ToString() -notmatch $Pattern){throw "Expected $Pattern; received $errorRecord"}
}
function Check($Name,[scriptblock]$Action){& $Action;$checks.Add(@{Name=$Name;Passed=$true});Write-Output "PASS $Name"}
$owner=[Windows.Forms.Form]::new()
$ownerHandle=$owner.Handle.ToInt64()
$clipboard=$null
$fixture=$null
$errors=[Collections.Generic.List[Exception]]::new()
$startTicks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
function Write-OwnedClipboard([scriptblock]$Action) {
    $clipboard.AssertUnchanged()
    $beforeSequence=$clipboard.ExpectedSequence
    & $Action
    $null=Register-PtClipboardWrite $clipboard $beforeSequence $PID $startTicks
}
try {
    $clipboard=New-PtClipboardGuard $ownerHandle
    Save-PtRunJson (Join-Path $root 'clipboard-backup.json') @{Formats=$clipboard.FormatCount;BitmapMaterializedFromPng=$clipboard.BitmapFromPng}
    Check 'Image/text/registered formats round-trip under a sequence guard' {
        $bitmap=[Drawing.Bitmap]::new(8,8)
        $bitmap.SetPixel(2,3,[Drawing.Color]::Red)
        $png=[IO.MemoryStream]::new();$bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png)
        $data=[Windows.Forms.DataObject]::new()
        $data.SetImage($bitmap);$data.SetText('fixture unicode')
        $data.SetData('PNG',$false,[IO.MemoryStream]::new($png.ToArray()))
        $data.SetData('HTML Format',$false,'<html><body>fixture</body></html>')
        Write-OwnedClipboard { [Windows.Forms.Clipboard]::SetDataObject($data,$true) }
        $guard=New-PtClipboardGuard $ownerHandle
        try {
            $before=$guard.ExpectedSequence
            Write-OwnedClipboard { [Windows.Forms.Clipboard]::SetText('owned replacement') }
            $null=Register-PtClipboardWrite $guard $before $PID $startTicks
            $outer=$clipboard.ExpectedSequence
            $guard.Restore()
            $null=Register-PtClipboardWrite $clipboard $outer $PID $startTicks
            Require $guard.Restored 'Rich clipboard not verified'
        } finally {$guard.Dispose();$bitmap.Dispose();$png.Dispose()}
    }
    Check 'Unacknowledged clipboard write is retained rather than overwritten' {
        $guard=New-PtClipboardGuard $ownerHandle
        try {
            Write-OwnedClipboard { [Windows.Forms.Clipboard]::SetText('simulated foreign write') }
            Reject { $guard.Restore() } 'conflict'
            Require ([Windows.Forms.Clipboard]::GetText() -ceq 'simulated foreign write') 'Conflict was overwritten'
            Reject { Register-PtClipboardWrite $guard $guard.ExpectedSequence $PID 1 } 'identity changed'
        } finally {$guard.Dispose()}
    }
    $receipt=Join-Path $root 'fixture.json';$stop=Join-Path $root 'stop.fixture'
    $fixture=[Diagnostics.Process]::new()
    $fixture.StartInfo=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    $fixture.StartInfo.UseShellExecute=$false
    foreach($arg in @('-NoProfile','-STA','-File',(Join-Path $PSScriptRoot 'Show-PtVerificationFixture.ps1'),'-Receipt',$receipt,'-StopFile',$stop)){$fixture.StartInfo.ArgumentList.Add($arg)}
    if(-not $fixture.Start()){throw 'Fixture failed to start'}
    $deadline=[DateTime]::UtcNow.AddSeconds(15)
    while(-not(Test-Path -LiteralPath $receipt) -and [DateTime]::UtcNow -lt $deadline) {
        if($fixture.HasExited){throw 'Fixture exited before readiness'}
        Start-Sleep -Milliseconds 100
    }
    if(-not(Test-Path -LiteralPath $receipt)){throw 'No fixture readiness receipt'}
    $info=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
    if($info.ProcessId -ne $fixture.Id){throw 'Fixture process identity mismatch'}
    $main=Get-PtWindowIdentity $info.Main; $popup=Get-PtWindowIdentity $info.Popup
    Check 'Exact identity, stale owner and HWND override guards' {
        Assert-PtWindowIdentity $main -Visible
        $stale=$main.PSObject.Copy();$stale.StartTicks=1
        Reject {Assert-PtWindowIdentity $stale} 'identity changed'
        Reject {Invoke-PtWindowCommand $run $main bad-scope inspect -Arguments @('-w','1')} 'override'
        [void][PtFixtureDesktop]::SetForegroundWindow([IntPtr]$popup.Hwnd)
        Reject {Assert-PtWindowIdentity $main -Foreground} 'not foreground'
    }
    Check 'Real winapp resolves owned edit and records an HWND-scoped value change' {
        $inspection=Invoke-PtWindowCommand $run $main inspect inspect -Arguments @('--depth','6','--json')
        $tree=$inspection.Stdout|ConvertFrom-Json
        $control=Resolve-PtUiControl $tree 'Edit' -AutomationId FixtureInput
        $null=Invoke-PtWindowCommand $run $main set set-value -Arguments @($control.selector,'updated fixture')
        $value=Invoke-PtWindowCommand $run $main read get-value -Arguments @($control.selector,'--json')
        Require (($value.Stdout|ConvertFrom-Json).text -ceq 'updated fixture') 'UIA value mismatch'
        Set-PtRecordedAssertion $run uia PASS 'Owned fixture field changed and read back' @($inspection.EvidencePath,$value.EvidencePath)
    }
    Check 'Passive capture includes live main and popup bounds without stealing focus' {
        $before=[PtVerification.Desktop]::GetForegroundWindow()
        $capture=Save-PtWindowCapture $run @($main,$popup) 'owned main and popup'
        Require ($capture.Valid -and [PtVerification.Desktop]::GetForegroundWindow() -eq $before) 'Capture disturbed focus'
        Set-PtRecordedAssertion $run capture PASS 'Live physical union capture and unchanged identity/state' @($capture.Image,$capture.Observation)
    }
    Check 'UI toggle sets and restores state idempotently' {
        $first=Set-PtScopedToggle $run $main FixtureToggle $true
        $second=Set-PtScopedToggle $run $main FixtureToggle $true
        $restored=Set-PtScopedToggle $run $main FixtureToggle $false
        Require ($first.Changed -and -not $second.Changed -and $restored.Changed) 'Toggle was not idempotent'
    }
    Check 'Guarded lifecycle cleans up real UI toggles and files after action failure' {
        foreach ($initial in @($false,$true)) {
            $null=Set-PtScopedToggle $run $main FixtureToggle $initial
            $file=Join-Path $root "lifecycle-$initial.txt";[IO.File]::WriteAllText($file,'before')
            $snapshot=New-PtFileGuard $file
            $expected=Get-PtFileHashBytes ([Text.Encoding]::UTF8.GetBytes('owned'))
            $read={
                $state=Invoke-PtWindowCommand $run $main lifecycle-read get-value -Arguments @('FixtureToggle','--json')
                $text=($state.Stdout|ConvertFrom-Json).text
                if($text -notin @('On','Off')){throw 'Unknown lifecycle toggle state'}
                $text -eq 'On'
            }
            Reject {
                Invoke-PtRestoredState -ReadEnabled $read -SetEnabled {param($value) Set-PtScopedToggle $run $main FixtureToggle $value|Out-Null} -Action {
                    Set-PtScopedToggle $run $main FixtureToggle (-not $initial)|Out-Null
                    [IO.File]::WriteAllText($file,'owned')
                    throw 'Injected action error'
                } -Quiesce {
                    if(& $read){throw 'Fixture writer flag is not stopped'}
                } -Restore {Restore-PtFileGuard $snapshot $expected|Out-Null} -Verify {
                    [IO.File]::ReadAllText($file) -ceq 'before'
                }
            } 'Injected action error'
            Require ((& $read) -eq $initial -and [IO.File]::ReadAllText($file) -ceq 'before') 'Lifecycle cleanup differs'
        }
    }
    [IO.File]::WriteAllText($stop,'stop')
    if(-not $fixture.WaitForExit(10000)){throw 'Owned fixture did not close'}
    Check 'Exited window identity is rejected' { Reject { Assert-PtWindowIdentity $main } 'no longer exists' }
} catch { $errors.Add($_.Exception) }
finally {
    if($fixture) {
        try {
            if(-not $fixture.HasExited) {
                [IO.File]::WriteAllText((Join-Path $root 'stop.fixture'),'stop')
                if(-not $fixture.WaitForExit(5000)){$fixture.Kill($true);$fixture.WaitForExit()}
            }
        } catch {$errors.Add($_.Exception)}
        $fixture.Dispose()
    }
    if($clipboard) {
        try { $clipboard.Restore(); Require $clipboard.Restored 'Original clipboard restore failed' }
        catch {$errors.Add($_.Exception)}
        finally {$clipboard.Dispose()}
    }
    $owner.Dispose()
    try {
        Assert-PtWindowIdentity $originalWindow
        if(-not [PtFixtureDesktop]::SetForegroundWindow([IntPtr]$foreground)){throw 'Foreground restoration refused'}
        if(-not [PtFixtureDesktop]::SetPhysicalCursorPos($pointer.X,$pointer.Y)){throw 'Pointer restoration failed'}
        Require ([PtVerification.Desktop]::GetForegroundWindow().ToInt64() -eq $foreground) 'Foreground differs'
        $afterPointer=[PtFixtureDesktop+Point]::new()
        if(-not [PtFixtureDesktop]::GetPhysicalCursorPos([ref]$afterPointer)){throw 'Cannot verify restored pointer'}
        Require ($afterPointer.X -eq $pointer.X -and $afterPointer.Y -eq $pointer.Y) 'Restored pointer differs'
    } catch {$errors.Add($_.Exception)}
    Save-PtRunJson (Join-Path $root 'checks.json') @($checks)
    Save-PtRunJson (Join-Path $root 'cleanup-proof.json') @{Restored=($errors.Count -eq 0);Errors=@($errors|ForEach-Object {$_.ToString()})}
}
if($errors.Count){throw [AggregateException]::new('Desktop fixture validation failed; see cleanup-proof.json',$errors.ToArray())}
Set-PtRecordedAssertion $run identity PASS 'Exact identity/stale/closed-window guards exercised' @('checks.json')
Set-PtRecordedAssertion $run clipboard PASS 'Rich formats, conflict refusal and original clipboard restoration exercised' @('checks.json','cleanup-proof.json')
Set-PtRecordedCleanup $run $true 'Original clipboard, foreground and pointer restored; owned fixture exited' @('cleanup-proof.json')
$summary=Complete-PtRecordedRun $run
$null=Test-PtRecordedArchive $root
Write-Output "Passed $($checks.Count) desktop checks. Signoff=$($summary.Signoff). Evidence: $root"
