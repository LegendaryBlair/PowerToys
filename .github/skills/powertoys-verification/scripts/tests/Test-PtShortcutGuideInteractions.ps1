#requires -Version 7.2
param([Parameter(Mandatory)][string]$Workspace,[long]$SettingsHwnd,[switch]$SkipOffline)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-shortcut-guide-flow.ps1"
Initialize-PtUiAutomation
if(Test-Path -LiteralPath $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace});throw}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
if($SkipOffline -and -not $SettingsHwnd){throw 'SkipOffline requires an installed Settings HWND.'}
if(-not $SkipOffline){
Check 'Exact SG CheckBox selector, TogglePattern, actual persistence and no-op round trip' {
    $sgControlFixture=@{Checked=$true;Saved=$true;Toggles=0;Mode=2;Visible=$true;Pending=0;Expanded=$false}
    $target=[pscustomobject]@{hwnd=10}
    function Assert-PtWindowIdentity {param($Identity)}
    function Get-PtNativeWindow {param($Hwnd) [pscustomobject]@{Visible=$sgControlFixture.Visible;Minimized=$false}}
    function Get-PtSgFlowConfiguration {
        if($sgControlFixture.Pending -gt 0){
            $sgControlFixture.Pending--
            if($sgControlFixture.Pending -eq 0){$sgControlFixture.Saved=$sgControlFixture.Checked}
        }
        [pscustomobject]@{HoldAction=$sgControlFixture.Mode;CloseOnRelease=$sgControlFixture.Saved}
    }
    function Get-PtSgHoldExpander {
        param($SettingsTarget)
        $pattern=[pscustomobject]@{State=$sgControlFixture}
        $pattern|Add-Member ScriptProperty Current {
            [pscustomobject]@{ExpandCollapseState=$(if($this.State.Expanded){[Windows.Automation.ExpandCollapseState]::Expanded}else{[Windows.Automation.ExpandCollapseState]::Collapsed})}
        }
        $pattern|Add-Member ScriptMethod Expand {$this.State.Expanded=$true}
        $pattern|Add-Member ScriptMethod Collapse {$this.State.Expanded=$false}
        $pattern
    }
    function Resolve-PtUiElement {
        param($Hwnd,$ControlType,$AutomationId)
        Require ($Hwnd -eq 10 -and $ControlType -ceq 'CheckBox' -and $AutomationId -ceq 'ShortcutGuide_CloseOnWindowsKeyRelease') 'Wrong control contract'
        Require $sgControlFixture.Expanded 'Checkbox queried while its Settings expander is collapsed'
        $pattern=[pscustomobject]@{State=$sgControlFixture}
        $pattern|Add-Member ScriptProperty Current {
            [pscustomobject]@{ToggleState=$(if($this.State.Checked){[Windows.Automation.ToggleState]::On}else{[Windows.Automation.ToggleState]::Off})}
        }
        $pattern|Add-Member ScriptMethod Toggle {$this.State.Toggles++;$this.State.Checked=-not $this.State.Checked;$this.State.Pending=2}
        $control=[pscustomobject]@{Current=[pscustomobject]@{IsEnabled=$true;IsOffscreen=$false};Pattern=$pattern}
        $control|Add-Member ScriptMethod GetCurrentPattern {
            param($requested)
            if($requested -ne [Windows.Automation.TogglePattern]::Pattern){throw 'Wrong UIA pattern'}
            $this.Pattern
        }
        $control
    }
    $same=Set-PtShortcutGuideCloseOnRelease -SettingsTarget $target -Enabled $true
    Require (-not $same.Changed -and $sgControlFixture.Toggles -eq 0) 'No-op toggled the setting'
    $changed=Set-PtShortcutGuideCloseOnRelease -SettingsTarget $target -Enabled $false
    Require ($changed.Before -and -not $changed.Actual -and -not $sgControlFixture.Saved) 'Setter did not wait for persisted false'
    $restored=Set-PtShortcutGuideCloseOnRelease -SettingsTarget $target -Enabled $changed.Before
    Require ($restored.Actual -and $sgControlFixture.Saved -and $sgControlFixture.Toggles -eq 2) 'Original value was not restored'
    Require (-not $sgControlFixture.Expanded) 'Caller-collapsed expander was left open'
    $sgControlFixture.Expanded=$true
    Set-PtShortcutGuideCloseOnRelease -SettingsTarget $target -Enabled $true|Out-Null
    Require $sgControlFixture.Expanded 'Caller-expanded settings were collapsed'
    $sgControlFixture.Mode=1
    Reject {Set-PtShortcutGuideCloseOnRelease -SettingsTarget $target -Enabled $false} 'Select Open Shortcut Guide explicitly'
    $sgControlFixture.Mode=2;$sgControlFixture.Visible=$false
    Reject {Set-PtShortcutGuideCloseOnRelease -SettingsTarget $target -Enabled $false} 'visible'
    $sgControlFixture.Visible=$true;$sgControlFixture.Saved=$false
    Reject {Set-PtShortcutGuideCloseOnRelease -SettingsTarget $target -Enabled $false} 'disagree before mutation'
    Require ($sgControlFixture.Toggles -eq 2) 'A failed precondition still toggled'
}
Check 'Outside click uses full content bounds on either edge, not narrow PaneRoot or element center' {
    $hostRect=@{Left=0;Top=0;Right=2560;Bottom=1380}
    $targetRect=@{Left=200;Top=200;Right=1200;Bottom=700}
    $leftContent=@{X=22;Y=83;Width=731;Height=1275}
    $point=Get-PtSgOutsidePoint $leftContent $hostRect $targetRect
    Require ($point.X -gt 753+15 -and $point.X -lt 1184 -and $point.Y -gt 264 -and $point.Y -lt 684) 'Point is inside guide content or outside the owned interior'
    $rightContent=@{X=1807;Y=83;Width=731;Height=1275}
    $point=Get-PtSgOutsidePoint $rightContent $hostRect $targetRect
    Require ($point.X -lt 1791 -and $point.X -gt 216) 'Right-docked guide has no correct left-side point'
    Reject {Get-PtSgOutsidePoint $leftContent $hostRect @{Left=200;Top=200;Right=700;Bottom=700}} 'no safe point'
    Reject {Get-PtSgOutsidePoint @{X=0;Y=0;Width=0;Height=20} $hostRect $targetRect} 'empty'
    Reject {Get-PtSgOutsidePoint @{X=[double]::NaN;Y=0;Width=700;Height=20} $hostRect $targetRect} 'finite'
    $point=Get-PtSgOutsidePoint @{X=-1900;Y=83;Width=700;Height=900} `
        @{Left=-1920;Top=0;Right=0;Bottom=1080} @{Left=-1500;Top=200;Right=-400;Bottom=700}
    Require ($point.X -gt -1184 -and $point.X -lt -416) 'Negative physical monitor coordinates were mishandled'
}
}
if(-not $SettingsHwnd){"PASS: $($results.Count) offline SG interaction groups. $Workspace";return}
Check 'Installed CheckBox round trip uses owned settings changes and exact rollback' {
    $identity=Get-PtWindowIdentity $SettingsHwnd
    $settingsPath=Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\Shortcut Guide\settings.json'
    $file=Get-PtFileSnapshot $settingsPath
    $desktop=Get-PtDesktopSnapshot -WindowHwnd $SettingsHwnd
    $file|ConvertTo-Json|Set-Content "$Workspace\settings-before.json"
    $desktop|ConvertTo-Json -Depth 12|Set-Content "$Workspace\desktop-before.json"
    $modeControl=Resolve-PtUiElement -Hwnd $SettingsHwnd -ControlType ComboBox -AutomationId ShortcutGuide_WindowsKeyAction
    $mode=@(Get-PtComboBoxSelection $modeControl)
    Require ($mode.Count -eq 1) 'Original hold mode is ambiguous'
    $before=(Get-PtSgFlowConfiguration).CloseOnRelease
    $errorRecord=$null
    try{
        Assert-PtForegroundOrAbort -Hwnd $SettingsHwnd
        Select-PtComboBoxItem -Hwnd $SettingsHwnd -AutomationId ShortcutGuide_WindowsKeyAction -ItemName 'Open Shortcut Guide'|Out-Null
        Wait-PtCondition -Description 'full-guide hold setting saved' -Probe {(Get-PtSgFlowConfiguration).HoldAction -eq 2}|Out-Null
        $changed=Set-PtShortcutGuideCloseOnRelease -SettingsTarget $identity -Enabled (-not $before)
        Require ($changed.Actual -eq (-not $before)) 'Installed changed state not read back'
        Set-PtShortcutGuideCloseOnRelease -SettingsTarget $identity -Enabled $before|Out-Null
        $same=Set-PtShortcutGuideCloseOnRelease -SettingsTarget $identity -Enabled $before
        Require (-not $same.Changed) 'Installed no-op toggled'
        Save-PtPassiveScreenshot -Path "$Workspace\checkbox-restored.png"|Out-Null
    }catch{$errorRecord=$_}
    finally{
        try{
            if((Get-PtSgFlowConfiguration).HoldAction -eq 2 -and (Get-PtSgFlowConfiguration).CloseOnRelease -ne $before){
                Set-PtShortcutGuideCloseOnRelease -SettingsTarget $identity -Enabled $before|Out-Null
            }
            Select-PtComboBoxItem -Hwnd $SettingsHwnd -AutomationId ShortcutGuide_WindowsKeyAction -ItemName $mode[0]|Out-Null
            $originalJson=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($file.base64))|ConvertFrom-Json|ConvertTo-Json -Depth 30 -Compress
            Wait-PtCondition -Description 'original complete settings values' -Probe {
                ((Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json|ConvertTo-Json -Depth 30 -Compress) -ceq $originalJson)
            }|Out-Null
            Restore-PtFileSnapshot $file|Out-Null
            Restore-PtDesktopSnapshot $desktop|ConvertTo-Json -Depth 12|Set-Content "$Workspace\restoration.json"
        }catch{if($errorRecord){$errorRecord.Exception.Data['RestorationFailure']=$_.Exception.Message}else{$errorRecord=$_}}
    }
    if($errorRecord){throw $errorRecord}
}
"PASS: $($results.Count) SG interaction groups. $Workspace"
