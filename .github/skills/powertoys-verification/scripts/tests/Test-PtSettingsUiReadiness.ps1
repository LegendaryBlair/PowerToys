#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-settings-readiness-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-settings-session.ps1"
Initialize-PtUiAutomation
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected failure: $Pattern"
}
$root=[pscustomobject]@{Calls=0;Deny=$false}
$root|Add-Member ScriptMethod FindAll {param($Scope,$Condition)
    $this.Calls++
    if($this.Deny){throw [UnauthorizedAccessException]::new('Synthetic access denial')}
    if($this.Calls -eq 1){throw [Windows.Automation.ElementNotAvailableException]::new('Synthetic replaced provider')}
    @('synthetic-element')
}
function Get-PtWindowIdentity {param($Hwnd) @{hwnd=$Hwnd}}
function Assert-PtWindowIdentity {param($Identity)}
function Get-PtSettingsAutomationRoot {param($Hwnd) $root}
$elements=@(Get-PtSettingsUiElements 1)
Require ($root.Calls -eq 2 -and $elements[0] -ceq 'synthetic-element') 'Replaced provider was not rebound for observation'
$root.Deny=$true;$root.Calls=0
Reject {Get-PtSettingsUiElements 1} 'Synthetic access denial'
Require ($root.Calls -eq 1) 'Non-stale UIA failure was retried'
$script:queries=0;$script:missing=0
$selection=[pscustomobject]@{Current=[pscustomobject]@{IsSelected=$true}}
$selection|Add-Member ScriptMethod Select {throw 'Already-selected page must not be selected again.'}
$expansion=[pscustomobject]@{Current=[pscustomobject]@{ExpandCollapseState=[Windows.Automation.ExpandCollapseState]::Expanded}}
$expansion|Add-Member ScriptMethod Expand {throw 'Already-expanded group must not be expanded again.'}
$scroll=[pscustomobject]@{Current=[pscustomobject]@{HorizontalScrollPercent=-1.0;VerticalScrollPercent=60.0
    HorizontalViewSize=100.0;VerticalViewSize=40.0};Changes=0}
$scroll|Add-Member ScriptMethod SetScrollPercent {param($horizontal,$vertical) $this.Current.VerticalScrollPercent=$vertical;$this.Changes++}
function Node([string]$Id,[hashtable]$Patterns,[int]$RuntimeId){
    $node=[pscustomobject]@{Current=[pscustomobject]@{AutomationId=$Id;BoundingRectangle=@{Width=100.0;Height=100.0}};Patterns=$Patterns;Runtime=$RuntimeId}
    $node|Add-Member ScriptMethod TryGetCurrentPattern {param($Pattern,$Result)
        if($this.Patterns.ContainsKey($Pattern.Id)){$Result.Value=$this.Patterns[$Pattern.Id];return $true};return $false
    }
    $node|Add-Member ScriptMethod GetCurrentPattern {param($Pattern) $this.Patterns[$Pattern.Id]}
    $node|Add-Member ScriptMethod GetRuntimeId {@(1,$this.Runtime)}
    $node
}
$script:nodes=@(
    (Node 'WorkspacesNavItem' @{([Windows.Automation.SelectionItemPattern]::Pattern.Id)=$selection} 1),
    (Node 'SystemToolsNavItem' @{([Windows.Automation.ExpandCollapsePattern]::Pattern.Id)=$expansion} 2),
    (Node 'MenuItemsScrollViewer' @{([Windows.Automation.ScrollPattern]::Pattern.Id)=$scroll} 3))
function Get-PtSettingsUiElements {
    param($Hwnd)
    $script:queries++
    if($script:queries -le $script:missing){return}
    $script:nodes
}
$script:missing=2
$state=Wait-PtSettingsUiState 1
Require ($script:queries -eq 3 -and $state.PageAutomationId -eq 'WorkspacesNavItem') 'Transient provider absence was not polled'
$script:queries=0;$script:missing=100
Reject {Read-PtSettingsUiState 1} 'found 0'
$script:queries=0;$script:missing=2
$state.Scroll[0].Vertical=0.0
Set-PtSettingsUiState 1 $state
Require ($scroll.Changes -eq 1 -and $scroll.Current.VerticalScrollPercent -eq 0) 'Navigation viewport was not restored once before realizing items'
$script:nodes+=@(Node 'WorkspacesNavItem' @{([Windows.Automation.SelectionItemPattern]::Pattern.Id)=$selection} 4)
Reject {Wait-PtSettingsUiState 1} 'found 2'
$expected=[pscustomobject]@{PageAutomationId='GeneralNavItem';Expansion=@();Scroll=@(@{Id='page';Horizontal=-1.0;Vertical=27.60492298072708})}
$actual=ConvertFrom-PtReportJson (ConvertTo-Json $expected -Depth 8)
$actual.Scroll[0].Vertical=[double][single]$expected.Scroll[0].Vertical
Require (-not(Test-PtSettingsUiStateMatch $expected $actual)) 'Float readback was accepted outside the declared WinUI path'
Require (Test-PtSettingsUiStateMatch $expected $actual -AllowWinUiFloatReadback) 'Exact float32 command readback was rejected'
$actual.Scroll[0].Vertical=27.38364129840492
Require (-not(Test-PtSettingsUiStateMatch $expected $actual -AllowWinUiFloatReadback)) 'Real scroll drift was rounded away'
$actual.Scroll[0].Vertical=$expected.Scroll[0].Vertical+0.00000001
Require (-not(Test-PtSettingsUiStateMatch $expected $actual -AllowWinUiFloatReadback)) 'A nearby but different value was accepted by bucket rounding'
Require ($expected.Scroll[0].Vertical -eq 27.60492298072708) 'Original raw baseline was changed'
$roundingExpected=[pscustomobject]@{PageAutomationId='DashboardNavItem';Expansion=@();Scroll=@(@{Id='MainScrollViewer';Horizontal=-1.0;Vertical=46.52418145916063})}
$roundingActual=ConvertFrom-PtReportJson (ConvertTo-Json $roundingExpected -Depth 8)
$rounded=[double][single]$roundingExpected.Scroll[0].Vertical
$roundingActual.Scroll[0].Vertical=46.524181365966804
Require (-not(Test-PtSettingsUiStateMatch $roundingExpected $roundingActual)) 'Provider arithmetic rounding was accepted without WinUI opt-in'
Require (Test-PtSettingsUiStateMatch $roundingExpected $roundingActual -AllowWinUiFloatReadback) 'Observed WinUI readback one double ULP above float32 was rejected'
$roundingActual.Scroll[0].Vertical=[Math]::BitDecrement($rounded)
Require (Test-PtSettingsUiStateMatch $roundingExpected $roundingActual -AllowWinUiFloatReadback) 'One double ULP below float32 was rejected'
$roundingActual.Scroll[0].Vertical=[Math]::BitIncrement([Math]::BitIncrement($rounded))
Require (-not(Test-PtSettingsUiStateMatch $roundingExpected $roundingActual -AllowWinUiFloatReadback)) 'More than one double ULP was accepted'
$roundingActual.Scroll[0].Vertical=$rounded
$roundingActual.Scroll[0].Horizontal=[Math]::BitIncrement(-1.0)
Require (-not(Test-PtSettingsUiStateMatch $roundingExpected $roundingActual -AllowWinUiFloatReadback)) 'No-scroll sentinel was approximated'
$roundingActual.Scroll[0].Horizontal=-1.0
$roundingActual.PageAutomationId='GeneralNavItem'
Require (-not(Test-PtSettingsUiStateMatch $roundingExpected $roundingActual -AllowWinUiFloatReadback)) 'Rounding allowance hid a changed page'
Require ($roundingExpected.Scroll[0].Vertical -eq 46.52418145916063) 'Rounding comparison changed the original baseline'
$scroll.Changes=0;$scroll.Current.VerticalScrollPercent=0.0
$scroll|Add-Member -Force ScriptMethod SetScrollPercent {
    param($horizontal,$vertical)
    $this.Changes++
    if($this.Changes -eq 1){$this.Current.VerticalViewSize=38.0;$this.Current.VerticalScrollPercent=26.0}
    else{$this.Current.VerticalScrollPercent=$vertical}
}
$script:nodes=@(Node 'page' @{([Windows.Automation.ScrollPattern]::Pattern.Id)=$scroll} 7)
$transitions=@(Set-PtSettingsScrollState -Hwnd 1 -Scroll $expected.Scroll)
Require ($scroll.Changes -eq 2 -and $transitions[0].ReappliedForChangedExtent) 'Observed extent change was not handled explicitly'
$scroll.Changes=0;$scroll.Current.VerticalScrollPercent=0.0
$scroll|Add-Member -Force ScriptMethod SetScrollPercent {param($horizontal,$vertical) $this.Changes++;$this.Current.VerticalScrollPercent=25.0}
$transitions=@(Set-PtSettingsScrollState -Hwnd 1 -Scroll $expected.Scroll)
Require ($scroll.Changes -eq 1 -and -not $transitions[0].ReappliedForChangedExtent -and $transitions[0].Vertical -eq 25.0) 'Unchanged layout triggered a blind retry or a fabricated readback'
$restoreSnapshot=[pscustomobject]@{
    Schema='PtSettingsUi.v1';Identity=@{hwnd=1;className='WinUIDesktopWin32WindowClass'}
    Native=@{visible=$true;placement=@{showCmd=1;Left=0}}
    Ui=@{PageAutomationId='GeneralNavItem';Expansion=@();Scroll=@()}
    Scope=@('SelectedPage');UnsupportedState=@();Path=Join-Path $Workspace 'passive-settings.json'
}
Write-PtReportText $restoreSnapshot.Path (ConvertTo-Json $restoreSnapshot -Depth 20)
$script:restoreNative=ConvertFrom-PtReportJson (ConvertTo-Json $restoreSnapshot.Native -Depth 20)
$script:restoreUi=@{PageAutomationId='AlwaysOnTopNavItem';Expansion=@();Scroll=@()}
$script:restoreCalls=0
function Get-PtActiveResourceSession {}
function Get-PtSettingsRestorationSnapshot {param($Snapshot,$ReplacementIdentity) $Snapshot}
function Get-PtWindowSnapshot {param($Hwnd) $script:restoreNative}
function Restore-PtWindowSnapshot {param($Snapshot) $script:restoreNative}
function Show-PtSettingsForObservation {throw 'Non-activating restoration attempted foreground activation.'}
function Read-PtSettingsUiState {param($Hwnd,[switch]$AllowUnselected) $script:restoreUi}
function Wait-PtSettingsUiState {param($Hwnd) $script:restoreUi}
function Set-PtSettingsUiState {param($Hwnd,$State,[switch]$DeferScroll) $script:restoreUi=$State;$script:restoreCalls++}
function Complete-PtSettingsObligation {param($Snapshot,$ReceiptPath)}
$restored=Restore-PtSettingsUiSnapshot -Snapshot $restoreSnapshot -NoActivate
Require ($restored.Restored -and $script:restoreCalls -eq 1) 'Visible UIA-only restoration did not restore the original page.'
$restoreSnapshot|Add-Member NoteProperty NoActivate $true
$restoreSnapshot.Path=Join-Path $Workspace 'passive-settings-stored.json'
Write-PtReportText $restoreSnapshot.Path (ConvertTo-Json $restoreSnapshot -Depth 20)
$script:restoreUi=@{PageAutomationId='AlwaysOnTopNavItem';Expansion=@();Scroll=@()}
$restored=Restore-PtSettingsUiSnapshot -Snapshot $restoreSnapshot
Require ($restored.Restored -and $script:restoreCalls -eq 2) 'Stored NoActivate was not enforced when the caller omitted the switch.'
$script:restoreNative.placement.Left=10
Reject {Restore-PtSettingsUiSnapshot -Snapshot $restoreSnapshot -NoActivate} 'unchanged visible normal placement'
$script:restoreNative.placement.Left=0;$script:restoreNative.visible=$false
Reject {Restore-PtSettingsUiSnapshot -Snapshot $restoreSnapshot -NoActivate} 'unchanged visible normal placement'
Require ($script:restoreCalls -eq 2) 'Non-activating restoration mutated a moved or hidden window.'
$script:temporaryRestore=$null;$script:hiddenCapture=$false
function Register-PtSettingsObligation {param($Snapshot)}
function Get-PtSettingsCurrentState {
    param($Hwnd,[switch]$AllowTemporaryRestore)
    $script:temporaryRestore=$AllowTemporaryRestore.IsPresent
    if($script:hiddenCapture -and -not $AllowTemporaryRestore){throw 'Hidden baseline was not surfaced.'}
    @{Native=@{visible=$true;placement=@{showCmd=1}};Ui=@{PageAutomationId='GeneralNavItem';Expansion=@();Scroll=@();UnsupportedControls=@()}}
}
$captured=Get-PtSettingsUiSnapshot -Hwnd 1 -Workspace $Workspace -NoActivate
Require ($captured.NoActivate -eq $true -and -not $script:temporaryRestore) 'Passive capture requested temporary activation'
$script:hiddenCapture=$true
Reject {Get-PtSettingsUiSnapshot -Hwnd 1 -Workspace $Workspace -NoActivate} 'Hidden baseline was not surfaced'
$legacy=Get-PtSettingsUiSnapshot -Hwnd 1 -Workspace $Workspace
Require $script:temporaryRestore 'Existing active capture lost explicit temporary-restoration support'
Write-PtReportText "$Workspace\results.json" '{"StaleProviderRebind":"PASS","NonStaleFailurePropagation":"PASS","TransientProviderAbsence":"PASS","StrictBaseline":"PASS","RealizationPolling":"PASS","NoRedundantExpansion":"PASS","NavigationScrollFirst":"PASS","AmbiguousSelectionRefusal":"PASS","ExactWinUiWireReadback":"PASS","WinUiArithmeticRounding":"PASS","RealDriftRejected":"PASS","ObservedExtentChange":"PASS","NoBlindReplay":"PASS"}'
"PASS: Settings readiness and non-activating restoration regressions with synthetic UIA elements only. $Workspace"
