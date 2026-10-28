#requires -Version 7.2
param(
    [string]$InputLanguage='en-US',
    [string]$Workspace=(Join-Path $env:TEMP "pt-keyboard-fixture-$([guid]::NewGuid().ToString('N'))")
)
$ErrorActionPreference='Stop'
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach($name in 'pt-desktop','pt-uia','pt-ui-observation','pt-sendinput-chord','pt-foreground-guard','pt-state-snapshot','pt-verification-report'){
    . "$skill\scripts\$name.ps1"
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PtFixtureLayoutProbe {
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint thread);
    [DllImport("user32.dll")] public static extern short GetKeyState(int key);
    public static long Layout(long hwnd) { uint pid; return GetKeyboardLayout(GetWindowThreadProcessId((IntPtr)hwnd, out pid)).ToInt64(); }
}
'@
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
if(Test-Path $Workspace){throw 'Use a new fixture-test workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$selected=@([Windows.Forms.InputLanguage]::InstalledInputLanguages|Where-Object {$_.Culture.Name -ceq $InputLanguage})
Require ($selected.Count -eq 1) 'Test requires exactly one already installed requested layout.'
$fixtureScript="$PSScriptRoot\Show-PtDesktopFixture.ps1"
$exe=(Get-Command pwsh).Source
$results=[Collections.Generic.List[object]]::new()
$desktop=Get-PtDesktopSnapshot
$foregroundLayout=[PtFixtureLayoutProbe]::Layout($desktop.foreground.hwnd)
$creation=$null
$main=$null
$run=New-PtVerificationRun -Workspace "$Workspace\run" -Module 'Keyboard input fixture acceptance' `
    -Scenario InfrastructureAcceptance -Bits 'Owned helper windows only; no PowerToys state changes' `
    -Items @(@{Id='fixture';Description='Owned input fixture';Admin='NO';Clarity='CLEAR';UserVisible=$false;Assertions=@(@{Id='delivery';Description='Explicit layout and physical-key delivery'})}) `
    -Inputs @(Get-PtVerificationInputs -Skill $skill -Inputs @(@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath},@{Name='fixture.ps1';Role='Other';Path=$fixtureScript}))
$plan=@{Schema='PtRunResources.v1';Resources=@(@{Id='fixture';Kind='Process';Ownership='Owned';FilePath=$exe;RestoreStep='exit'})}
$session=New-PtResourceSession -Run $run -ResourcePlan $plan
$session.ResourcePlan=$plan;Save-PtResourceSession $session
try{
    $invalid="$Workspace\invalid"
    [IO.Directory]::CreateDirectory($invalid)|Out-Null
    $start=[Diagnostics.ProcessStartInfo]::new($exe)
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-STA','-File',$fixtureScript,'-StateDirectory',$invalid,'-InputLanguage','not-an-installed-layout')){
        $start.ArgumentList.Add($arg)
    }
    $process=[Diagnostics.Process]::Start($start)
    try{
        Require ($process.WaitForExit(15000)) 'Rejected fixture did not exit.'
        $errorText=$process.StandardError.ReadToEnd()
        Require ($process.ExitCode -ne 0 -and $errorText -match 'exactly one already installed') 'Unavailable layout was not rejected explicitly.'
        Require (-not (Test-Path "$invalid\ready.json")) 'Invalid layout reached window readiness.'
    }finally{$process.Dispose()}
    $results.Add(@{Name='Unavailable layout rejected before window creation';Status='PASS'})
    foreach($mode in 'inherited','explicit'){
        $state=Join-Path $Workspace $mode
        [IO.Directory]::CreateDirectory($state)|Out-Null
        $arguments=@('-NoProfile','-STA','-File',"`"$fixtureScript`"",'-StateDirectory',"`"$state`"")
        if($mode -eq 'explicit'){$arguments+=@('-InputLanguage',$InputLanguage)}
        $creation=Start-PtOwnedProcess -FilePath $exe -ArgumentList $arguments
        $ready=Wait-PtCondition -Description 'owned fixture readiness' -TimeoutSeconds 20 -Probe {
            if(Test-Path "$state\ready.json"){ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$state\ready.json"))}
        }
        Require ($ready.processId -eq $creation.ProcessId) 'Fixture identity differs from owned launch.'
        $main=Get-PtWindowIdentity $ready.hwnd
        foreach($window in @(Get-PtNativeWindow -ProcessId $creation.ProcessId)){
            Register-PtCreatedWindow -Identity (Get-PtWindowIdentity $window.Hwnd) -Creation $creation|Out-Null
        }
        if($mode -eq 'inherited'){
            Require ($ready.inputLanguage -eq $ready.originalInputLanguage) 'Default fixture changed its input layout.'
        }else{
            Require ($ready.inputLanguage -eq $selected[0].Handle.ToInt64()) 'Explicit fixture did not select the installed layout.'
            Assert-PtForegroundOrAbort -Hwnd $main.hwnd
            (Resolve-PtUiElement -Hwnd $main.hwnd -AutomationId FixtureInput -ControlType Edit).SetFocus()
            $expected=if(([PtFixtureLayoutProbe]::GetKeyState(0x14) -band 1) -ne 0){'C'}else{'c'}
            Send-PtChord -Hwnd $main.hwnd -Key 0x43 -KeyDownMilliseconds 40|Out-Null
            $events=Wait-PtCondition -Description 'physical key down/up receipt' -TimeoutSeconds 5 -Probe {
                if(Test-Path "$state\keys.jsonl"){
                    $rows=@(Get-Content "$state\keys.jsonl"|ForEach-Object {$_|ConvertFrom-Json})
                    if(@($rows|Where-Object {$_.key -eq 67 -and -not $_.down}).Count){,$rows}
                }
            }
            Require (@($events|Where-Object {$_.key -eq 67 -and $_.down}).Count -eq 1) 'Physical key-down was not delivered.'
            Require ((Get-PtUiObservation -Target $main -AutomationId FixtureInput -ControlType Edit -Property Text).Value -ceq $expected) 'Ordinary physical input did not produce the expected text.'
        }
        Stop-PtOwnedProcess -Creation $creation -RequestExit {param($identity,$window) Close-PtTrackedWindow -Identity $window} -ArgumentList @($main)|Out-Null
        if($mode -eq 'explicit'){
            $restored=ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$state\input-language-restored.json"))
            Require ($restored.original -eq $ready.originalInputLanguage -and $restored.actual -eq $restored.original) 'Fixture did not restore its original thread input layout.'
        }
        $creation=$null;$main=$null
        Restore-PtDesktopSnapshot $desktop|Out-Null
        Require ([PtFixtureLayoutProbe]::Layout($desktop.foreground.hwnd) -eq $foregroundLayout) 'Original foreground application layout changed.'
        $results.Add(@{Name="$mode layout, owned lifetime and original foreground layout";Status='PASS'})
    }
}finally{
    if($creation -and (Get-PtResourceProcessIdentity $creation.ProcessId)){
        if(-not $main){throw 'Fixture startup did not establish a safe close identity.'}
        Stop-PtOwnedProcess -Creation $creation -RequestExit {param($identity,$window) Close-PtTrackedWindow -Identity $window} -ArgumentList @($main)|Out-Null
    }
    Restore-PtDesktopSnapshot $desktop|Out-Null
    $attempt=Start-PtVerificationAttempt -Run $run -Context Cleanup -Kind Normal -Name 'Final fixture absence'
    try{Complete-PtResourceSession -Attempt $attempt|Out-Null}
    finally{Stop-PtVerificationAttempt -Attempt $attempt -Reason 'Owned fixture lifetimes checked'}
    Write-PtReportText "$Workspace\results.json" (ConvertTo-Json $results -Depth 6)
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
}
"PASS: $($results.Count) focused input-fixture groups. $Workspace"
