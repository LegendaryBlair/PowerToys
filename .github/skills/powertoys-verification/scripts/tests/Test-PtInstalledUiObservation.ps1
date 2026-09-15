#requires -Version 7.0
<#
.SYNOPSIS
H07 acceptance on an existing Settings fixture and a test-opened SG search surface.
.NOTES
No settings edits, module restart, physical shortcut, scrolling, pinning or speech claims.
Settings window lifetime/placement belongs to the caller. SG must initially be hidden.
#>
param([Parameter(Mandatory)][string]$Workspace,[Parameter(Mandatory)][long]$SettingsHwnd)
$ErrorActionPreference='Stop'
$helpers=Split-Path $PSScriptRoot -Parent
foreach($name in 'pt-ui-observation','pt-ui-snapshot','pt-shortcut-guide','pt-shared-events','pt-foreground-guard'){
    . "$helpers\$name.ps1"
}
Initialize-PtUiAutomation
if(Test-Path $Workspace){throw 'Use a new workspace.'}
$settingsTarget=Get-PtWindowIdentity $SettingsHwnd
$hostWindow=Get-PtShortcutGuideHost
if(-not $hostWindow -or $hostWindow.Visible){throw 'This acceptance requires an existing hidden SG host; do not mutate an already-open user surface.'}
$sgTarget=Get-PtWindowIdentity $hostWindow.Hwnd
$desktop=Get-PtDesktopSnapshot
$inputs=@(
    @{Name='SKILL.md';Role='Skill';Path="$helpers\..\SKILL.md"}
    @{Name='acceptance.ps1';Role='Checklist';Path=$PSCommandPath}
    foreach($name in 'pt-ui-observation','pt-ui-snapshot','pt-uia','pt-desktop','pt-state-snapshot','pt-shortcut-guide','pt-shared-events','pt-foreground-guard','pt-verification-report','pt-verification-operation','pt-verification-render'){
        @{Name="$name.ps1";Role='Helper';Path="$helpers\$name.ps1"}
    }
)
$run=New-PtVerificationRun -Workspace $Workspace -Module 'H07 installed observation acceptance' `
    -Bits "Installed PowerToys $((Get-Process PowerToys).FileVersion), immutable; property/snapshot helper acceptance only" `
    -Scenario InfrastructureAcceptance -Inputs $inputs -Items @(
        @{Id='Settings';Description='Empty text, accessible name and numeric Off state are distinct observations';Admin='NO';Clarity='CLEAR';UserVisible=$false
            Assertions=@(@{Id='properties';Description='Exact text source, empty string and native LiveSetting=0'})}
        @{Id='Search';Description='SG search observations remain accurate before, during and after a no-match query';Admin='NO';Clarity='CLEAR';UserVisible=$true
            Assertions=@(@{Id='properties';Description='Actual query/name, selected state, focus and native LiveSetting=1'})}
        @{Id='Structure';Description='Snapshot contract checks structure, not expected business rows';Admin='NO';Clarity='CLEAR';UserVisible=$false
            Assertions=@(@{Id='structure';Description='Normal and no-result trees usable for search/navigation; host-only tree rejected'})}
    )
$desktop|ConvertTo-Json -Depth 12|Set-Content "$Workspace\desktop-before.json"
$originalError=$null
$originalQuery=$null
$opened=$false
$landmarks=@(
    @{Id='search-container';ControlType='Group';AutomationId='ShortcutGuide_SearchBox'}
    @{Id='search-editor';ControlType='Edit';AutomationId='TextBox';WithinAutomationId='ShortcutGuide_SearchBox'}
    @{Id='application-rail';ControlType='Group';AutomationId='MenuItemsHost'}
)
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
try{
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Owned UI boundaries' `
        -Command 'Verify existing Settings identity and initially hidden SG identity; retain native visibility evidence' `
        -ArgumentList @($settingsTarget,$sgTarget) -Action {
            param($attempt,$settings,$guide)
            Assert-PtUiObservationTarget $settings
            Assert-PtUiObservationTarget $guide
            Get-PtNativeWindow -Hwnd $guide.hwnd
        }|Out-Null
    $settingsCase=Invoke-PtVerificationCase -Run $run -ItemId Settings -Name 'Installed Settings property channels' `
        -Stage Observe -Command 'Read actual textbox text, explicit accessible name and native LiveSetting' `
        -ArgumentList @($settingsTarget) -Action {
            param($attempt,$target)
            $text=Get-PtUiObservation -Target $target -Name 'Example: outlook.exe' -ControlType Edit -WithinAutomationId ShortcutGuideDisabledApps -Property Text
            $name=Get-PtUiObservation -Target $target -Name 'Example: outlook.exe' -ControlType Edit -WithinAutomationId ShortcutGuideDisabledApps -Property Name
            $live=Get-PtUiObservation -Target $target -Name 'Example: outlook.exe' -ControlType Edit -WithinAutomationId ShortcutGuideDisabledApps -Property LiveSetting
            $help=Get-PtUiObservation -Target $target -AutomationId EditButton -ControlType Button -Property HelpText
            Require ($text.Value -ceq '' -and $text.Source -eq 'ValuePattern.Value') 'Actual empty settings value was not observed'
            Require ($name.Value -ceq 'Example: outlook.exe' -and $live.Value -eq 0) 'Placeholder name or native Off value was misread'
            Require ($help.Value -is [string] -and $help.Value.Length -gt 0) 'Shortcut HelpText was not observed'
            Add-PtVerificationObservation $attempt properties -Actual 'ValuePattern returned an empty string; Name returned the placeholder; native LiveSetting returned numeric 0.' `
                -Detail @($text,$name,$live,$help)
        }
    Add-PtVerificationAssertion $settingsCase.Attempt properties PASS 'Exact UIA property sources' 'Actual empty input is distinct from its accessible name; native Off=0 was supported.' -ObservationSequence $settingsCase.Output[0]
    Complete-PtVerificationItem $run Settings -Reason 'Read-only installed Settings observations matched'

    $hiddenRaw=Invoke-PtWinApp -Arguments @('inspect','--depth','12','-w',"$($sgTarget.hwnd)",'--json')
    $hiddenRaw|Set-Content "$Workspace\hidden-tree.json"
    Invoke-PtSharedEvent -Name ShortcutGuide.Trigger|Out-Null
    $opened=$true
    $visible=Wait-PtCondition -Description 'owned SG visibility' -TimeoutSeconds 3 -PollMilliseconds 20 -Probe {Get-PtShortcutGuideHost -Visible}
    Assert-PtForegroundOrAbort -Hwnd $visible.Hwnd
    Wait-PtCondition -Description 'SG search structure' -TimeoutSeconds 5 -Probe {
        $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$sgTarget.hwnd)
        $condition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'ShortcutGuide_SearchBox')
        @($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)).Count -eq 1
    }|Out-Null
    $originalQuery=Get-PtUiObservation -Target $sgTarget -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox -Property Text
    $originalQuery|ConvertTo-Json -Depth 12|Set-Content "$Workspace\query-before.json"
    $openRaw=Invoke-PtWinApp -Arguments @('inspect','--depth','14','-w',"$($sgTarget.hwnd)",'--json')
    $openRaw|Set-Content "$Workspace\open-tree.json"
    $facts=@{Query='h07-no-result-bb7c26f1';Evidence=[Collections.Generic.List[object]]::new()}
    $searchCase=Invoke-PtVerificationCase -Run $run -ItemId Search -Name 'SG actual observation channels' `
        -Stage Observe -Command 'Set a disposable query through UIA, read actual text/live/selection/focus properties, then restore the original query' `
        -ArgumentList @($sgTarget,$facts) -Action {
            param($attempt,$target,$sharedFacts)
            $empty=Get-PtUiObservation -Target $target -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox -Property Text
            $name=Get-PtUiObservation -Target $target -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox -Property Name
            Require ($empty.Value -ceq '' -and $name.Value -ceq 'Search shortcuts') 'SG empty query was confused with its placeholder'
            $edit=Resolve-PtUiElement -Hwnd $target.hwnd -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox
            $edit.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($sharedFacts.Query)
            Wait-PtCondition -Description 'actual test query' -TimeoutSeconds 3 -Probe {
                (Get-PtUiObservation -Target $target -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox -Property Text).Value -ceq $sharedFacts.Query
            }|Out-Null
            $live=Get-PtUiObservation -Target $target -AutomationId ShortcutGuide_NoSearchResults -ControlType Text -Property LiveSetting
            Require ($live.Value -eq 1 -and $live.Source.Contains('ignoreDefault=true')) 'Polite live-region property was not read natively'
            $edit.SetFocus()
            $focus=Get-PtUiObservation -Target $target -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox -Property HasKeyboardFocus
            Require ($focus.Value -eq $true) 'Focused edit did not expose its focus state'
            $selection=@(foreach($id in '+WindowsNT.Shell','Microsoft.PowerToys'){
                Get-PtUiObservation -Target $target -AutomationId $id -ControlType ListItem -Property IsSelected
            })
            Require (@($selection|Where-Object {$_.Value -isnot [bool]}).Count -eq 0) 'Selection observation was not Boolean'
            $raw=Invoke-PtWinApp -Arguments @('inspect','--depth','14','-w',"$($target.hwnd)",'--json')
            $treePath=New-PtVerificationArtifactPath $attempt no-results-tree.json
            [IO.File]::WriteAllText($treePath,$raw)
            $treeProof=Add-PtVerificationArtifact $attempt $treePath Evidence 'Original single UIA tree for no-result search state'
            $sharedFacts.NoResultsPath=Join-Path $attempt.Run.Workspace $treeProof.Path
            $image=New-PtVerificationArtifactPath $attempt no-results.png
            Save-PtPassiveScreenshot -Path $image|Out-Null
            $sharedFacts.Evidence.Add((Add-PtVerificationArtifact $attempt $image Screenshot 'SG no-result state; no speech claim'))
            Add-PtVerificationArtifact $attempt "$image.state.json" Evidence 'Passive capture state comparison'|Out-Null
            Add-PtVerificationObservation $attempt properties -Actual 'Real empty and nonempty query values, native Polite=1, Boolean selection and focused=true were observed without Name fallback.' `
                -Detail @($empty,$name,$live,$focus,$selection) -Evidence @($treeProof,$sharedFacts.Evidence[0])
        } -CleanupArgumentList @($sgTarget,$originalQuery.Value) -Cleanup {
            param($target,$value)
            $edit=Resolve-PtUiElement -Hwnd $target.hwnd -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox
            $edit.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($value)
            $actual=Get-PtUiObservation -Target $target -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox -Property Text
            Require ($actual.Value -ceq $value) 'Query cleanup did not restore the observed original'
        }
    Add-PtVerificationAssertion $searchCase.Attempt properties PASS 'Supported UIA patterns and native LiveSetting' 'All requested facts used their declared channels; this does not prove Narrator speech.' -ObservationSequence $searchCase.Output[0]
    Complete-PtVerificationItem $run Search -Reason 'Observed real search properties and restored the original query'
    $structureCase=Invoke-PtVerificationCase -Run $run -ItemId Structure -Name 'Snapshot observation contracts' `
        -Command 'Assess the same search/navigation structural contract against hidden, populated and no-result captures' `
        -ArgumentList @("$Workspace\hidden-tree.json","$Workspace\open-tree.json",$facts.NoResultsPath,$landmarks,$sgTarget.hwnd) -Action {
            param($attempt,$hiddenPath,$openPath,$emptyPath,$contract,$hwnd)
            $a=Test-PtUiSnapshot -Tree (ConvertFrom-PtReportJson ([IO.File]::ReadAllText($hiddenPath))) -RequiredLandmarks $contract -WindowHwnd $hwnd
            $b=Test-PtUiSnapshot -Tree (ConvertFrom-PtReportJson ([IO.File]::ReadAllText($openPath))) -RequiredLandmarks $contract -WindowHwnd $hwnd
            $c=Test-PtUiSnapshot -Tree (ConvertFrom-PtReportJson ([IO.File]::ReadAllText($emptyPath))) -RequiredLandmarks $contract -WindowHwnd $hwnd
            Require (-not $a.usableForContract -and $b.usableForContract -and $c.usableForContract) 'Structural assessment confused unavailable UIA with a valid empty-result state'
            $sources=@(foreach($path in $hiddenPath,$openPath,$emptyPath){Add-PtVerificationArtifact $attempt $path Evidence 'Original input capture for structural assessment'})
            Add-PtVerificationObservation $attempt structure -Actual 'Host-only capture lacks required landmarks; both normal and no-result captures satisfy the same search/navigation contract.' -Detail @($a,$b,$c) -Evidence $sources
        }
    Add-PtVerificationAssertion $structureCase.Attempt structure PASS 'Structural contract without business row predicates' 'No expected rows or no-results message was required as an observation-readiness landmark.' -ObservationSequence $structureCase.Output[0]
    Complete-PtVerificationItem $run Structure -Reason 'Snapshot usability is explicitly limited to the declared search/navigation contract'
}catch{$originalError=$_}
finally{
    $cleanupErrors=[Collections.Generic.List[string]]::new()
    $stillVisible=$false
    if($opened){
        try{$stillVisible=(Get-PtNativeWindow -Hwnd $sgTarget.hwnd).Visible}
        catch{$cleanupErrors.Add($_.Exception.Message)}
    }
    if($stillVisible){
        try{
            if($originalQuery){
                $edit=Resolve-PtUiElement -Hwnd $sgTarget.hwnd -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox
                $edit.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($originalQuery.Value)
                Require ((Get-PtUiObservation -Target $sgTarget -AutomationId TextBox -ControlType Edit -WithinAutomationId ShortcutGuide_SearchBox -Property Text).Value -ceq $originalQuery.Value) 'Final SG query mismatch'
            }
        }catch{$cleanupErrors.Add($_.Exception.Message)}
        try{
            (Resolve-PtUiElement -Hwnd $sgTarget.hwnd -AutomationId CloseButton -ControlType Button).GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
            Wait-PtCondition -Description 'test-opened SG surface hidden' -TimeoutSeconds 3 -Probe {-not (Get-PtNativeWindow -Hwnd $sgTarget.hwnd).Visible}|Out-Null
        }catch{$cleanupErrors.Add($_.Exception.Message)}
    }
    try{Restore-PtDesktopSnapshot $desktop|ConvertTo-Json -Depth 12|Set-Content "$Workspace\desktop-restored.json"}
    catch{$cleanupErrors.Add($_.Exception.Message)}
    Set-PtActiveVerificationAttempt -Attempt $null
    if($cleanupErrors.Count){
        if($originalError){$originalError.Exception.Data['CleanupErrors']=$cleanupErrors.ToArray()}
        else{$originalError=[Management.Automation.ErrorRecord]::new([InvalidOperationException]::new(($cleanupErrors -join '; ')),'H07Cleanup',0,$null)}
    }
}
if($originalError){throw $originalError}
"PASS: installed H07 property and structural observation contracts. Final caller-owned Settings/file cleanup remains: $Workspace"
