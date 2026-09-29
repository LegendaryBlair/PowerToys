#requires -Version 7.2
<#
.SYNOPSIS
Bounded acceptance against an existing installed Settings window. Never closes it or touches clipboard.
.NOTES
Uses the actual run template/resource plan. No module activation, settings-value writes or process restart.
#>
param([Parameter(Mandatory)][long]$SettingsHwnd,
    [string]$Workspace=(Join-Path $env:TEMP "pt-installed-settings-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach($helper in 'pt-settings-session','pt-verification-report'){. "$skill\scripts\$helper.ps1"}
if(Test-Path $Workspace){throw 'Use a new acceptance workspace.'}
$identity=Get-PtWindowIdentity $SettingsHwnd
$process=Get-Process -Id $identity.processId
if($process.ProcessName -cne 'PowerToys.Settings' -or $process.SessionId -ne [Diagnostics.Process]::GetCurrentProcess().SessionId){
    throw 'Expected the existing PowerToys Settings window in this interactive session.'
}
$settingsRoot=Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
$paths=@('settings.json','language.json','ColorPicker\settings.json','Workspaces\settings.json','Shortcut Guide\settings.json')
$global:PtInstalledSettingsAcceptance=[pscustomobject]@{
    Identity=$identity;Paths=@($paths|ForEach-Object {Join-Path $settingsRoot $_});FileBaseline=@()
    AlternatePage=$null;Mutations=@();Version=$process.FileVersion
}
function Get-PtAcceptanceFileDigests {
    $index=0
    foreach($path in $global:PtInstalledSettingsAcceptance.Paths){
        $index++
        $exists=[IO.File]::Exists($path)
        [pscustomobject]@{Id="file-$index";Exists=$exists;Hash=$(if($exists){Get-PtReportHash (Read-PtSharedFileBytes $path)}else{$null})}
    }
}
$global:PtInstalledSettingsAcceptance.FileBaseline=@(Get-PtAcceptanceFileDigests)
$resources=@(@{Id='settings-ui';Kind='Settings';Hwnd=$SettingsHwnd})
for($index=1;$index -le $paths.Count;$index++){
    $resources+=@(@{Id="file-$index";Kind='File';RestoreStep='unchanged-files'})
}
$cleanup=@(@{Id='unchanged-files';Phase='Verify';DependsOn=@();Action={};Verify={
    (ConvertTo-Json -InputObject @(Get-PtAcceptanceFileDigests) -Compress) -ceq
        (ConvertTo-Json -InputObject $global:PtInstalledSettingsAcceptance.FileBaseline -Compress)
}})
$items=@(@{Id='settings-adapter';Description='Installed Settings navigation, expansion, scroll and native placement round trip without replacing the borrowed window'
    Admin='NO';Clarity='CLEAR';UserVisible=$true;Assertions=@(
        @{Id='navigation';Description='Navigate to another installed Settings page and read its selected state'},
        @{Id='expansion';Description='Change one supported navigation expander and observe the changed state'},
        @{Id='scroll';Description='Change one supported scroll percentage and read it back'},
        @{Id='placement';Description='Change normal placement and minimize/restore the existing window'},
        @{Id='restoration';Description='Restore the same HWND/page/expansion/scroll/full native placement; root/module settings files remain unchanged'})})
$preflight={
    param($attempt)
    $state=$global:PtInstalledSettingsAcceptance
    $snapshot=Get-PtSettingsUiSnapshot $state.Identity.hwnd $attempt.Run.Workspace
    if($snapshot.Ui.UnsupportedControls.Count){throw 'Original Settings has unsupported expansion/scroll state; do not navigate away from an incomplete baseline.'}
    $state.AlternatePage=if($snapshot.Ui.PageAutomationId -eq 'GeneralNavItem'){'DashboardNavItem'}else{'GeneralNavItem'}
    $path=New-PtVerificationArtifactPath $attempt 'initial-ui-state.json'
    Write-PtReportText $path (ConvertTo-Json $snapshot -Depth 20)
    Add-PtVerificationArtifact $attempt $path Evidence 'Exact original Settings baseline before navigation'|Out-Null
    & "$skill\scripts\pt-session-diagnose.ps1"
}
$cases={
    param($run)
    Invoke-PtVerificationCase -Run $run -ItemId settings-adapter -Name 'Installed Settings adapter round trip' `
        -Command 'Reuse the borrowed Settings HWND; navigate, change supported visual state, then restore the captured original' -Action {
            param($attempt)
            $state=$global:PtInstalledSettingsAcceptance;$h=$state.Identity.hwnd
            $snapshot=Get-PtSettingsUiSnapshot $h $attempt.Run.Workspace
            function Proof([string]$Id,$Value,[string]$Reason){
                $file=New-PtVerificationArtifactPath $attempt "$Id.json"
                Write-PtReportText $file (ConvertTo-Json $Value -Depth 20)
                $evidence=Add-PtVerificationArtifact $attempt $file Evidence $Reason
                $proof=@($evidence)
                if($Id -eq 'restoration'){$proof+=@($originalPageImage)}
                Add-PtVerificationAssertion -Attempt $attempt -AssertionId $Id -Verdict PASS -Category 'Installed UI/native readback' -Reason $Reason -Evidence $proof
            }
            [void][PtDesktop]::ShowWindow([IntPtr]$h,9)
            Assert-PtForegroundOrAbort -Hwnd $h
            $tree=Invoke-PtWinApp -Arguments @('inspect','--depth','3','-w',"$h",'--json')
            $treePath=New-PtVerificationArtifactPath $attempt 'installed-window-tree.json'
            Write-PtReportText $treePath ($tree|Out-String)
            Add-PtVerificationArtifact $attempt $treePath Evidence 'Installed UIA landmarks'|Out-Null
            $beforeImage=New-PtVerificationArtifactPath $attempt 'original-page.png'
            Save-PtPassiveScreenshot -Path $beforeImage -WindowIdentity @($state.Identity)|Out-Null
            $originalPageImage=Add-PtVerificationArtifact $attempt $beforeImage Screenshot 'Original page visual context for the final baseline comparison; temporarily surfaced, not a final-state screenshot'

            $target=ConvertFrom-PtReportJson (ConvertTo-Json $snapshot.Ui -Depth 20)
            $target.PageAutomationId=$state.AlternatePage
            Set-PtSettingsUiState $h $target
            $navigated=Read-PtSettingsUiState $h
            if($navigated.PageAutomationId -cne $state.AlternatePage){throw 'Installed Settings navigation did not reach the requested page.'}
            Proof navigation $navigated 'Selected navigation page changed on the original HWND.'

            $scroll=@($navigated.Scroll|Where-Object Vertical -GE 0|Sort-Object Id|Select-Object -First 1)
            if($scroll.Count -ne 1){throw 'No supported vertical scroll surface for this installed acceptance.'}
            $scrollElement=Select-PtUniqueUiElement -Elements @((Get-PtSettingsUiElements $h)|Where-Object {$_.Current.AutomationId -ceq $scroll[0].Id}) -Description 'acceptance scroll surface'
            $percent=if($scroll[0].Vertical -lt 50){60.0}else{0.0}
            $scrollElement.GetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern).SetScrollPercent(-1,$percent)
            $scrolled=Wait-PtCondition -Description 'changed installed Settings scroll offset' -TimeoutSeconds 5 -Probe {
                $current=Read-PtSettingsUiState $h
                $value=@($current.Scroll|Where-Object Id -CEQ $scroll[0].Id)[0].Vertical
                if([Math]::Abs($value-$percent) -lt 1){$current}
            }
            Proof scroll $scrolled 'A supported scroll surface reached the requested changed percentage.'

            $expansion=@($scrolled.Expansion|Where-Object {$_.Id -like '*NavItem' -and $_.State -eq 'Expanded'}|Select-Object -First 1)
            if($expansion.Count -ne 1){throw 'No expanded navigation group available for this installed acceptance.'}
            $element=Select-PtUniqueUiElement -Elements @((Get-PtSettingsUiElements $h)|Where-Object {$_.Current.AutomationId -ceq $expansion[0].Id}) -Description 'acceptance navigation expander'
            $element.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse()
            $collapsed=Read-PtSettingsUiState $h
            if(@($collapsed.Expansion|Where-Object {$_.Id -ceq $expansion[0].Id -and $_.State -eq 'Collapsed'}).Count -ne 1){throw 'Navigation expansion did not change.'}
            Proof expansion $collapsed 'One originally expanded navigation group was observed collapsed.'

            $placement=[PtDesktop]::Placement([IntPtr]$h)
            $rect=$placement.rcNormalPosition
            $placement.rcNormalPosition=[PtDesktop+RECT]@{Left=$rect.Left+8;Top=$rect.Top+8;Right=$rect.Right+8;Bottom=$rect.Bottom+8}
            $placement.showCmd=1;[PtDesktop]::Place([IntPtr]$h,$placement)
            [void][PtDesktop]::ShowWindow([IntPtr]$h,6)
            if(-not [PtDesktop]::IsIconic([IntPtr]$h)){throw 'Settings did not minimize.'}
            [void][PtDesktop]::ShowWindow([IntPtr]$h,9)
            $moved=Get-PtWindowSnapshot $h
            if($moved.placement.rcNormalPosition.Left -ne $rect.Left+8 -or [PtDesktop]::IsIconic([IntPtr]$h)){throw 'Normal placement/minimize round trip did not occur.'}
            Proof placement $moved 'Normal placement moved by eight physical pixels and the same window minimized/restored.'

            Assert-PtForegroundOrAbort -Hwnd $h
            $heading=if($state.AlternatePage -eq 'GeneralNavItem'){'General'}else{'Home'}
            Wait-PtCondition -Description 'Visible page content after restoring the narrower window' -TimeoutSeconds 5 -Probe {
                @((Get-PtSettingsUiElements $h)|Where-Object {
                    $_.Current.ControlType -eq [Windows.Automation.ControlType]::Text -and
                    $_.Current.Name -ceq $heading -and -not $_.Current.IsOffscreen
                }).Count -gt 0
            }|Out-Null
            $image=New-PtVerificationArtifactPath $attempt 'changed-page.png'
            Save-PtPassiveScreenshot -Path $image -WindowIdentity @($state.Identity)|Out-Null
            Add-PtVerificationArtifact $attempt $image Screenshot 'Changed installed Settings page and window state'|Out-Null
            $restored=Restore-PtSettingsUiSnapshot $snapshot
            Assert-PtWindowIdentity $state.Identity
            if((ConvertTo-Json -InputObject @(Get-PtAcceptanceFileDigests) -Compress) -cne
                (ConvertTo-Json -InputObject $state.FileBaseline -Compress)){throw 'A watched Settings file changed; no file writes were authorized.'}
            Proof restoration $restored 'Original supported UI state and full placement restored on the same PID/HWND; watched files unchanged.'
        }|Out-Null
    Complete-PtVerificationItem $run settings-adapter -Reason 'Observed installed Settings adapter round trip; not a module checklist run.'
    $review=Get-PtVerificationReview $run
    if(@($review.Items|Where-Object Verdict -NE PASS).Count){throw 'Installed Settings acceptance has incomplete evidence/coverage; refusing a success message.'}
}
try{
    $output=& "$skill\templates\verification-run.ps1" -Skill $skill -Workspace $Workspace -Module 'Installed Settings adapter acceptance' `
        -Scenario InfrastructureAcceptance -Bits "Installed PowerToys $($process.FileVersion), read-only binaries; no module activation" `
        -Items $items -Inputs @(@{Name='installed-settings-acceptance.ps1';Role='Checklist';Path=$PSCommandPath}) `
        -ResourcePlan @{Schema='PtRunResources.v1';Resources=$resources} -CleanupPlan $cleanup `
        -Preflight $preflight -Cases $cases -NoFriction
    Test-PtVerificationArchive -Workspace $Workspace|Out-Null
    "PASS: installed Settings resource wiring and restoration. $($output.Report)"
}finally{Remove-Variable PtInstalledSettingsAcceptance -Scope Global -ErrorAction SilentlyContinue}
