#requires -Version 7.2
<#
.SYNOPSIS
Exercise resident-process and Runner-hosted lifecycle contracts through installed Settings.
.NOTES
Caller owns Settings window lifetime, original file/directory bytes and final report cleanup.
This performs explicit module enable cycles, including Diagnostic restart; no module hotkeys.
#>
param([Parameter(Mandatory)][string]$Workspace,[Parameter(Mandatory)][long]$SettingsHwnd)
$ErrorActionPreference='Stop'
$helpers=Split-Path $PSScriptRoot -Parent
. "$helpers\pt-module-lifecycle.ps1"
. "$helpers\pt-foreground-guard.ps1"
Initialize-PtUiAutomation
$settings=Get-PtWindowIdentity $SettingsHwnd
$runner=Get-PtLifecycleRunner
$desktop=Get-PtDesktopSnapshot
$profiles=@(
    [pscustomobject]@{Id='find-my-mouse';ModuleKey='FindMyMouse';PageAutomationId='MouseUtilitiesNavItem';ToggleAutomationId='MouseUtils_FindMyMouseToggleId'
        Model='RunnerHosted';WindowClass='FindMyMouse'
        Events=@(@{Name='FindMyMouse.Trigger';WhenEnabled='Present';WhenDisabled='Absent'})}
    [pscustomobject]@{Id='shortcut-guide';ModuleKey='Shortcut Guide';PageAutomationId='ShortcutGuideNavItem';ToggleName='Shortcut Guide'
        Model='Resident';ProcessName='PowerToys.ShortcutGuide';ProcessPath="$env:LOCALAPPDATA\PowerToys\WinUI3Apps\PowerToys.ShortcutGuide.exe"
        WindowClass='WinUIDesktopWin32WindowClass'
        Events=@(@{Name='ShortcutGuide.Trigger';WhenEnabled='Present';WhenDisabled='Ignore'})}
)
$inputs=@(
    @{Name='SKILL.md';Role='Skill';Path="$helpers\..\SKILL.md"}
    @{Name='acceptance.ps1';Role='Checklist';Path=$PSCommandPath}
    foreach($name in 'pt-module-lifecycle','pt-shared-events','pt-uia','pt-desktop','pt-state-snapshot','pt-ui-observation','pt-verification-report','pt-verification-operation','pt-verification-render','pt-foreground-guard'){
        @{Name="$name.ps1";Role='Helper';Path="$helpers\$name.ps1"}
    }
)
$run=New-PtVerificationRun -Workspace $Workspace -Module 'H06 installed lifecycle acceptance' `
    -Bits "Installed PowerToys $((Get-Process -Id $runner.processId).FileVersion); UI-only module transitions, no Runner restart or activation" `
    -Scenario InfrastructureAcceptance -Inputs $inputs -Items @(foreach($profile in $profiles){
        @{Id=$profile.Id;Description="Explicit native lifecycle for $($profile.ModuleKey)";Admin='NO';Clarity='CLEAR';UserVisible=$true
            Assertions=@(@{Id='lifecycle';Description='UI/configuration, native readiness, exit and original enable state agree';Required=$true})}
    })
$desktop|ConvertTo-Json -Depth 12|Set-Content "$Workspace\desktop-before.json"
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Navigate($Profile){
    $page=if($Profile.Id -eq 'find-my-mouse'){'MouseUtils'}else{'ShortcutGuide'}
    $relay=Start-Process $runner.path -ArgumentList "--open-settings=$page" -PassThru
    try{if(-not $relay.WaitForExit(5000)){throw 'Settings navigation relay did not exit; Runner ownership is ambiguous'}}finally{$relay.Dispose()}
    Assert-PtForegroundOrAbort -Hwnd $settings.hwnd
    Wait-PtCondition -Description 'selected lifecycle Settings page' -TimeoutSeconds 5 -Probe {
        $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$settings.hwnd)
        $condition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,$Profile.PageAutomationId)
        $nodes=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition))
        $nodes.Count -eq 1 -and $nodes[0].GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
    }|Out-Null
}
function Evidence($Attempt,$Value,[string]$Name,[string]$Description){
    $path=New-PtVerificationArtifactPath $Attempt $Name
    $Value|ConvertTo-Json -Depth 25|Set-Content $path
    Add-PtVerificationArtifact $Attempt $path Evidence $Description
}
$originalError=$null
try{
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Exact native scope' -Command 'Capture Runner identity and module state before any lifecycle mutation' `
        -ArgumentList @(,$profiles) -Action {
            param($attempt,$moduleProfiles)
            foreach($profile in $moduleProfiles){
                $state=Get-PtModuleLifecycleState $profile
                Require ($state.VisibleWindows.Count -eq 0 -and $state.Status -ne 'Ambiguous') 'Module has unowned visible/ambiguous runtime state'
                Evidence $attempt $state "$($profile.Id)-baseline.json" 'Original native lifecycle state'|Out-Null
            }
        }|Out-Null
    foreach($profile in $profiles){
        Navigate $profile
        $snapshot=Get-PtModuleLifecycleSnapshot $profile $settings $Workspace
        $shared=@{Evidence=[Collections.Generic.List[object]]::new()}
        $normal=Invoke-PtVerificationCase -Run $run -ItemId $profile.Id -Name 'Normal explicit module enable cycle' `
            -OperationKey "lifecycle-$($profile.Id)" -Stage Drive -Command 'Set-PtModuleEnabled false/true using the declared profile; restore original enable state in cleanup' `
            -ArgumentList @($snapshot,$shared) -Action {
                param($attempt,$captured,$facts)
                $initial=Get-PtModuleLifecycleState $captured.Profile
                if($initial.ConfiguredEnabled){
                    $off=Set-PtModuleEnabled $captured $false
                    Require ($off.After.Status -eq 'Disabled') 'Original runtime did not exit'
                    $facts.Evidence.Add((Evidence $attempt $off disabled.json 'Disabled state and surviving/absent event observations'))
                    foreach($window in $initial.Windows){
                        $stale=$false
                        try{Assert-PtWindowIdentity $window.identity}catch{$stale=$true}
                        Require $stale 'A previously tracked module HWND remained valid after disable'
                    }
                }
                $on=Set-PtModuleEnabled $captured $true
                Require ($on.After.RuntimeReady -and $on.After.SatisfiesNativeContract) 'Declared native startup contract did not converge'
                if($captured.Profile.Model -eq 'RunnerHosted'){
                    Require ($on.After.Processes.Count -eq 0 -and $on.After.Windows[0].identity.processId -eq $captured.Runner.processId) 'Runner-hosted module was treated as a dedicated process'
                }elseif($initial.Processes.Count){
                    Require ($on.After.Processes[0].processId -ne $initial.Processes[0].processId -or
                        $on.After.Processes[0].processStartTicks -ne $initial.Processes[0].processStartTicks) 'Resident process identity was reused as if unchanged'
                }
                $noop=Set-PtModuleEnabled $captured $true
                Require (-not $noop.Changed) 'Matching enabled/ready state caused another transition'
                $facts.Evidence.Add((Evidence $attempt $on enabled.json 'Actual model-specific process/window/event readiness'))
                $image=New-PtVerificationArtifactPath $attempt enabled-settings.png
                Save-PtPassiveScreenshot -Path $image|Out-Null
                $facts.Evidence.Add((Add-PtVerificationArtifact $attempt $image Screenshot 'The explicit module toggle is enabled'))
                Add-PtVerificationArtifact $attempt "$image.state.json" Evidence 'Passive capture state comparison'|Out-Null
            } -CleanupArgumentList @($snapshot,$shared) -Cleanup {
                param($captured,$facts)
                $restored=Restore-PtModuleLifecycleSnapshot $captured
                Require ($restored.After.ConfiguredEnabled -eq $captured.OriginalEnabled -and $restored.After.SatisfiesNativeContract) 'Original enable state did not converge'
                $attempt=Get-PtActiveVerificationAttempt
                $facts.Evidence.Add((Evidence $attempt $restored restored.json 'Original configuration and current native lifecycle restored; old PIDs are not recreated'))
            }
        Add-PtVerificationAssertion $normal.Attempt lifecycle PASS 'Explicit UI transition plus native identity/event checks' `
            'Observed startup/exit according to the profile, refreshed runtime identities, and restored original enable state without Runner restart.' -Evidence $shared.Evidence.ToArray()
        Complete-PtVerificationItem $run $profile.Id -Reason 'Normal lifecycle contract observed independently of Diagnostic recovery'
        $diagnostic=Invoke-PtVerificationCase -Run $run -Context Diagnostic -Kind Diagnostic -Name "Explicit $($profile.Id) recovery" `
            -OperationKey "diagnostic-lifecycle-$($profile.Id)" -Stage Drive -Command 'Restart-PtModuleLifecycle in an explicitly Diagnostic context; restore original state afterward' `
            -ArgumentList @($snapshot) -Action {
                param($attempt,$captured)
                if(-not (Get-PtModuleLifecycleState $captured.Profile).ConfiguredEnabled){Set-PtModuleEnabled $captured $true|Out-Null}
                $before=Get-PtModuleLifecycleState $captured.Profile
                $restart=Restart-PtModuleLifecycle $captured -Reason 'H06 explicit recovery contract acceptance, not a replacement Normal result'
                Require ($restart.Disabled.Status -eq 'Disabled' -and $restart.After.RuntimeReady -and -not $restart.RunnerRestarted) 'Explicit restart did not observe both lifecycle phases'
                foreach($window in $before.Windows){
                    $stale=$false
                    try{Assert-PtWindowIdentity $window.identity}catch{$stale=$true}
                    Require $stale 'Old HWND was accepted after the diagnostic cycle'
                }
                Evidence $attempt $restart diagnostic-restart.json 'Diagnostic-only disable/enable cycle with new observations'|Out-Null
            } -CleanupArgumentList @($snapshot) -Cleanup {
                param($captured) Restore-PtModuleLifecycleSnapshot $captured|Out-Null
            }
    }
    Require ((ConvertTo-Json (Get-PtLifecycleRunner) -Compress) -ceq (ConvertTo-Json $runner -Compress)) 'Runner was replaced during module-local testing'
}catch{$originalError=$_}
finally{
    try{Restore-PtDesktopSnapshot $desktop|ConvertTo-Json -Depth 12|Set-Content "$Workspace\desktop-restored.json"}
    catch{
        if($originalError){$originalError.Exception.Data['DesktopRestoreFailure']=$_.Exception.Message}
        else{$originalError=$_}
    }
    Set-PtActiveVerificationAttempt -Attempt $null
}
if($originalError){throw $originalError}
$state=Get-PtReportState $run
if(@($state.Items|Where-Object Verdict -ne PASS).Count -or @($state.Steps|Where-Object Status -ne Completed).Count){throw 'Lifecycle acceptance contains incomplete/error steps'}
"PASS: two installed lifecycle models and explicit Diagnostic restart. Caller must finish file/directory/owned-Settings cleanup before finalizing: $Workspace"
