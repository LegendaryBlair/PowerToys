#requires -Version 7.2
param([Parameter(Mandatory)][string]$Workspace,[Parameter(Mandatory)][long]$SettingsHwnd,
    [Parameter(Mandatory)][long]$QuickAccessHwnd,[Parameter(Mandatory)][long]$ForegroundHwnd)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-shortcut-guide-entrypoints.ps1"
. "$PSScriptRoot\..\pt-directory-snapshot.ps1"
$helpers=Split-Path $PSScriptRoot -Parent
$run=New-PtVerificationRun -Workspace $Workspace -Module 'SG entry-point acceptance' `
    -Bits "Installed PowerToys $((Get-Process PowerToys).FileVersion), immutable; no full Runner restart" -Scenario InfrastructureAcceptance `
    -Items @(
        @{Id='QuickAccess';Description='Enabled, disabled and re-enabled Quick Access entry';Admin='NO';Clarity='CLEAR';UserVisible=$true
            Assertions=@(@{Id='enabled';Description='Enabled tile launches guide'},@{Id='disabled';Description='Disabled tile cannot launch guide'},@{Id='reenabled';Description='Re-enabled tile launches guide'})}
        @{Id='Settings';Description='Rail Settings action reaches the existing window and correct page';Admin='NO';Clarity='CLEAR';UserVisible=$true
            Assertions=@(@{Id='landing';Description='Existing Settings is foreground with SG selected after the click'})}
        @{Id='CustomChord';Description='Custom activation observation after Settings navigation';Admin='NO';Clarity='CLEAR';UserVisible=$true
            Assertions=@(@{Id='open';Description='The actual saved custom chord opens the guide'})}
    ) -Inputs @(@{Name='SKILL.md';Role='Skill';Path="$helpers\..\SKILL.md"}
        @{Name='test.ps1';Role='Checklist';Path=$PSCommandPath}
        foreach($file in @(Get-ChildItem -LiteralPath $helpers -File -Filter '*.ps1'|Where-Object Name -ne pt-session-diagnose.ps1)){
            @{Name=$file.Name;Role='Helper';Path=$file.FullName}
        })
$state=@{BaselineFile=$null;Lifecycle=$null;Shortcut=$null;Guide=$null}
$errors=[Collections.Generic.List[object]]::new()
function Proof($Attempt,[string]$Name,$Value,[string]$Kind='Evidence'){
    $path=New-PtVerificationArtifactPath $Attempt "$Name.json"
    ConvertTo-Json -InputObject $Value -Depth 25|Set-Content -LiteralPath $path
    Add-PtVerificationArtifact $Attempt $path $Kind $Name
}
function SelectSgPage($Target){
    $current=Get-PtSgSettingsLandingState $Target
    if((Test-PtSgEntryForeground $current) -and $current.ShortcutGuideSelected){return}
    Start-Process -FilePath (Get-Process PowerToys).Path -ArgumentList '--open-settings=ShortcutGuide'
    Wait-PtSgEntryState -Description 'SG settings page selection' -Probe {Get-PtSgSettingsLandingState $Target} `
        -Ready {param($s) (Test-PtSgEntryForeground $s) -and $s.ShortcutGuideSelected}|Out-Null
}
function SettleManifestDirectory([string]$Path){
    $previous=@{Signature='';Count=0}
    Wait-PtCondition -Description 'unchanged manifest writer output' -TimeoutSeconds 10 -PollMilliseconds 300 -Probe {
        $snapshot=Get-PtDirectorySnapshot -Path $Path -MaxFiles 1024 -MaxBytes 32MB
        $signature=ConvertTo-Json $snapshot -Depth 8 -Compress
        $previous.Count=if($previous.Signature -ceq $signature){$previous.Count+1}else{1}
        $previous.Signature=$signature
        if($previous.Count -ge 3){$snapshot}
    }
}
try{
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Persist complete scoped baseline' `
        -Command 'Read exact Settings/QA/foreground identity, selected page, module files and manifest bytes before mutation' `
        -ArgumentList @($SettingsHwnd,$QuickAccessHwnd,$ForegroundHwnd,$state) -Action {
            param($attempt,$settingsHandle,$quickHandle,$foregroundHandle,$holder)
            $settings=Get-PtWindowIdentity $settingsHandle;$qa=Get-PtWindowIdentity $quickHandle
            $desktop=Get-PtDesktopSnapshot -WindowHwnd @($settingsHandle,$quickHandle,$foregroundHandle)
            if((Get-PtShortcutGuideHost).Visible){throw 'An already-visible guide is not owned by this acceptance.'}
            Initialize-PtUiAutomation
            $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$settingsHandle)
            $condition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::ListItem)
            $pages=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)|Where-Object {
                $_.Current.AutomationId -like '*NavItem' -and $_.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
            })
            if($pages.Count -ne 1){throw 'Original Settings navigation page is not uniquely observed.'}
            $groups=@(foreach($item in $root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)){
                if($item.Current.AutomationId -notlike '*NavItem'){continue}
                $pattern=$null
                if($item.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$pattern) -and
                    $pattern.Current.ExpandCollapseState -in [Windows.Automation.ExpandCollapseState]::Collapsed,[Windows.Automation.ExpandCollapseState]::Expanded){
                    @{AutomationId=$item.Current.AutomationId;State=[string]$pattern.Current.ExpandCollapseState}
                }
            })
            $runner=Get-Process PowerToys
            $manifestPath=Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\KeyboardShortcuts'
            $installed=Join-Path (Split-Path $runner.Path -Parent) 'WinUI3Apps\Assets\ShortcutGuide\Manifests'
            $baseline=@{Desktop=$desktop;Settings=$settings;QuickAccess=$qa;Foreground=(Get-PtWindowIdentity $foregroundHandle)
                QuickAccessState=(Get-PtSgEntryWindowState $qa);Page=$pages[0].Current.AutomationId;NavigationGroups=$groups;RunnerId=$runner.Id
                Files=@(Get-PtFileSnapshot "$env:LOCALAPPDATA\Microsoft\PowerToys\settings.json";Get-PtFileSnapshot "$env:LOCALAPPDATA\Microsoft\PowerToys\Shortcut Guide\settings.json")
                Directory=(Get-PtDirectorySnapshot -Path $manifestPath -MaxFiles 1024 -MaxBytes 32MB)
                OwnedManifestPaths=@(@(Get-ChildItem -LiteralPath $installed -File -Filter '*.yml'|ForEach-Object Name)+@('index.yml','Microsoft.PowerToys.en-US.yml')|Select-Object -Unique)}
            $proof=Proof $attempt baseline $baseline
            $holder.BaselineFile=Join-Path $attempt.Run.Workspace $proof.Path
        }|Out-Null
    $baseline=Get-Content -LiteralPath $state.BaselineFile -Raw|ConvertFrom-Json -Depth 100
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Select SG configuration page' `
        -Command 'Use the existing Settings window and capture original module enablement' -ArgumentList @($baseline.Settings,$state,$Workspace) -Action {
            param($attempt,$target,$holder,$work)
            SelectSgPage $target
            $holder.Lifecycle=Get-PtModuleLifecycleSnapshot -Profile (Get-PtSgLifecycleProfile) -SettingsTarget $target -Workspace $work
        }|Out-Null
    foreach($mode in 'enabled','disabled','reenabled'){
        try{
            Invoke-PtVerificationCase -Run $run -ItemId QuickAccess -Name "Quick Access $mode" `
                -Command 'Change SG enablement through Settings, signal QA once, wait/capture settled tile, then invoke the actual tile' `
                -ArgumentList @($baseline.Settings,$baseline.QuickAccess,$baseline.RunnerId,$state,$mode,$Workspace) -Action {
                    param($attempt,$settings,$qa,$runnerId,$holder,$phase,$work)
                    SelectSgPage $settings
                    $enabled=$phase -ne 'disabled'
                    Set-PtModuleEnabled $holder.Lifecycle $enabled|Out-Null
                    if($enabled){
                        $hostWindow=Get-PtShortcutGuideHost
                        $initialized=Wait-PtShortcutGuideInitialized -GuideTarget (Get-PtWindowIdentity $hostWindow.Hwnd)
                        Proof $attempt sg-initialized $initialized|Out-Null
                    }
                    Invoke-PtSharedEvent -Name "Local\PowerToysQuickAccess_${runnerId}_Show"|Out-Null
                    Wait-PtShortcutGuideQuickAccess -QuickAccessTarget $qa -Enabled $enabled|Out-Null
                    $photo=Save-PtSgEntryCapture -Attempt $attempt -Name "qa-$phase" -Probe {Get-PtSgQuickAccessState $qa} `
                        -Ready {param($s) Test-PtSgQuickAccessReady $s $enabled}
                    $evidence=@($photo.Screenshot,$photo.StateEvidence)
                    if($enabled){
                        $tile=Resolve-PtUiElement -Hwnd $qa.hwnd -Name 'Shortcut Guide' -ControlType Button
                        $tile.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
                        $hostWindow=Wait-PtShortcutGuideHost
                        $guide=Get-PtWindowIdentity $hostWindow.Hwnd
                        $capture=Save-PtSgEntryCapture -Attempt $attempt -Name "qa-guide-$phase" -Probe {Get-PtShortcutGuidePresentation $guide} `
                            -Ready {param($s) $s.Kind -eq 'FullGuide' -and $s.ForegroundHwnd -eq $s.Target.hwnd}
                        $evidence+=@($capture.Screenshot,$capture.StateEvidence)
                        Invoke-PtWinApp -Arguments @('invoke','CloseButton','-w',"$($guide.hwnd)")|Out-Null
                        Wait-PtCondition -Description 'guide hidden after actual QA launch' -Probe {-not (Get-PtNativeWindow -Hwnd $guide.hwnd).Visible}|Out-Null
                    }
                    Add-PtVerificationAssertion $attempt $phase PASS 'Settled actual entry and destination' "Observed $phase Quick Access behavior." -Evidence $evidence
                }|Out-Null
        }catch{$errors.Add($_);break}
    }
    if(-not $errors.Count){Complete-PtVerificationItem $run QuickAccess -Reason 'All three QA states observed'}
    foreach($scenario in 'Settings','CustomChord'){
        try{
            Invoke-PtVerificationCase -Run $run -ItemId $scenario -Name $scenario `
                -Command 'Open SG once from tracked app; observe actual Settings click landing or configured custom activation; preserve failure before cleanup' `
                -ArgumentList @($baseline.Settings,$baseline.Foreground,$state,$scenario,$Workspace) -Action {
                    param($attempt,$settings,$foreground,$holder,$kind,$work)
                    SelectSgPage $settings
                    Set-PtModuleEnabled $holder.Lifecycle $true|Out-Null
                    if($kind -eq 'CustomChord'){
                        $holder.Shortcut=Get-PtShortcutSnapshot -Hwnd $settings.hwnd -PageAutomationId ShortcutGuideNavItem `
                            -SettingsPath "$env:LOCALAPPDATA\Microsoft\PowerToys\Shortcut Guide\settings.json" `
                            -PropertyPath @('properties','open_shortcutguide') -Workspace $work
                        Set-PtShortcutBinding $holder.Shortcut @{win=$true;ctrl=$true;alt=$false;shift=$true;code=121;key=''}|Out-Null
                    }
                    $holder.Guide=Open-PtShortcutGuide -ForegroundTarget $foreground -Workspace $work -Entry Chord
                    try{
                        if($kind -eq 'Settings'){
                            $landing=Invoke-PtShortcutGuideSettings -Session $holder.Guide -SettingsTarget $settings
                            $capture=Save-PtSgEntryCapture -Attempt $attempt -Name actual-settings-landing -Probe {Get-PtSgSettingsLandingState $settings $holder.Guide.GuideTarget} `
                                -Ready {param($s) (Test-PtSgEntryForeground $s) -and $s.ShortcutGuideSelected}
                            $id='landing'
                        }else{
                            $capture=Save-PtSgEntryCapture -Attempt $attempt -Name custom-guide -Probe {Get-PtShortcutGuidePresentation $holder.Guide.GuideTarget} `
                                -Ready {param($s) $s.Kind -eq 'FullGuide'}
                            $id='open'
                        }
                        Add-PtVerificationAssertion $attempt $id PASS 'Observed destination after one user action' "Observed $kind destination." `
                            -Evidence @($capture.Screenshot,$capture.StateEvidence)
                    }finally{if($holder.Guide){Restore-PtShortcutGuideSession $holder.Guide|Out-Null;$holder.Guide=$null}}
                }|Out-Null
            Complete-PtVerificationItem $run $scenario -Reason 'Requested destination observed'
        }catch{$errors.Add($_)}
    }
}catch{$errors.Add($_)}
finally{
    if($state.BaselineFile){
        try{
            Invoke-PtVerificationCase -Run $run -Context Cleanup -Name 'Complete scoped state restoration' `
                -Command 'Restore captured shortcut and enablement through UI, original module file bytes and manifest directory, Settings page, window placement and desktop' `
                -ArgumentList @($state) -Action {
                    param($attempt,$holder)
                    $original=Get-Content -LiteralPath $holder.BaselineFile -Raw|ConvertFrom-Json -Depth 100
                    $restoration=@{}
                    $restoreErrors=[Collections.Generic.List[string]]::new()
                    foreach($restoreAction in @(
                        {if($holder.Guide){Restore-PtShortcutGuideSession $holder.Guide|Out-Null}}
                        {if($holder.Shortcut){SelectSgPage $original.Settings;Restore-PtShortcutSnapshot $holder.Shortcut|Out-Null}}
                        {if($holder.Lifecycle){SelectSgPage $original.Settings;Restore-PtModuleLifecycleSnapshot $holder.Lifecycle|Out-Null}}
                        {
                            $expected=SettleManifestDirectory $original.Directory.Path
                            $restoration.Directory=Restore-PtDirectorySnapshot -Snapshot $original.Directory -ExpectedState $expected `
                                -OwnedRelativePaths $original.OwnedManifestPaths -MaxFiles 1024 -MaxBytes 32MB
                        }
                        {$restoration.Files=@(foreach($file in $original.Files){Restore-PtFileSnapshot $file})}
                        {
                            $pageName=$original.Page -replace 'NavItem$',''
                            Start-Process -FilePath (Get-Process PowerToys).Path -ArgumentList "--open-settings=$pageName"
                            Wait-PtCondition -Description 'original Settings page restored' -Probe {
                                $page=Resolve-PtUiElement -Hwnd $original.Settings.hwnd -AutomationId $original.Page -ControlType ListItem
                                $page.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
                            }|Out-Null
                        }
                        {
                            $restoration.NavigationGroups=@(foreach($group in $original.NavigationGroups){
                                try{
                                    $item=Resolve-PtUiElement -Hwnd $original.Settings.hwnd -AutomationId $group.AutomationId -ControlType ListItem
                                    $pattern=$item.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern)
                                    if([string]$pattern.Current.ExpandCollapseState -cne $group.State){
                                        if($group.State -ceq 'Collapsed'){$pattern.Collapse()}else{$pattern.Expand()}
                                    }
                                    Wait-PtCondition -Description "original $($group.AutomationId) expansion state" -Probe {
                                        [string]$pattern.Current.ExpandCollapseState -ceq $group.State
                                    }|Out-Null
                                    $group
                                }catch{$restoreErrors.Add($_.Exception.Message)}
                            })
                        }
                        {$restoration.Desktop=Restore-PtDesktopSnapshot $original.Desktop}
                        {
                            $restoration.QuickAccess=Get-PtSgEntryWindowState $original.QuickAccess
                            if($restoration.QuickAccess.Cloaked -ne $original.QuickAccessState.Cloaked){throw 'Quick Access cloak state differs from its original visibility.'}
                        }
                    )){
                        try{& $restoreAction}catch{$restoreErrors.Add($_.Exception.Message)}
                    }
                    $restoration.Errors=$restoreErrors.ToArray()
                    $proof=Proof $attempt restoration $restoration Restoration
                    if($restoreErrors.Count){
                        Add-PtVerificationRestoration $attempt FAIL ($restoreErrors -join '; ') -Evidence @($proof)
                        throw ($restoreErrors -join '; ')
                    }
                    Add-PtVerificationRestoration $attempt PASS 'All captured files, manifest bytes and desktop state restored; process identities may change after enable/disable.' -Evidence @($proof)
                }|Out-Null
        }catch{$errors.Add($_)}
    }
    Set-PtActiveVerificationAttempt -Attempt $null
    ConvertTo-Json -InputObject @($errors|ForEach-Object {$_.Exception.Message})|Set-Content "$Workspace\errors.json"
    ConvertTo-Json -InputObject @($errors|ForEach-Object {@{Message=$_.Exception.Message;Stack=$_.ScriptStackTrace
        EntryStates=$_.Exception.Data['PtSgEntryObservations'];RejectedCaptures=$_.Exception.Data['PtRejectedCaptures']}}) -Depth 20|Set-Content "$Workspace\error-details.json"
    $export=if($errors.Count){Complete-PtVerificationRun $run -Retrospective @(@{Friction=($errors|ForEach-Object {$_.Exception.Message}) -join '; '
        Source='HELPER-FLAW';Severity='HIGH';Cost='Scoped entry acceptance';SuggestedFix='Inspect the recorded action and destination before attributing the failure; retain restoration evidence.'})}
        else{Complete-PtVerificationRun $run -NoFriction}
    Test-PtVerificationArchive -Workspace $Workspace|Out-Null
}
if($errors.Count){throw ($errors|ForEach-Object {$_.Exception.Message}|Out-String)}
"$($export.Signoff): $($export.Report)"
