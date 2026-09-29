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
$scroll=[pscustomobject]@{Current=[pscustomobject]@{HorizontalScrollPercent=-1.0;VerticalScrollPercent=60.0};Changes=0}
$scroll|Add-Member ScriptMethod SetScrollPercent {param($horizontal,$vertical) $this.Current.VerticalScrollPercent=$vertical;$this.Changes++}
function Node([string]$Id,[hashtable]$Patterns,[int]$RuntimeId){
    $node=[pscustomobject]@{Current=[pscustomobject]@{AutomationId=$Id};Patterns=$Patterns;Runtime=$RuntimeId}
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
Write-PtReportText "$Workspace\results.json" '{"StaleProviderRebind":"PASS","NonStaleFailurePropagation":"PASS","TransientProviderAbsence":"PASS","StrictBaseline":"PASS","RealizationPolling":"PASS","NoRedundantExpansion":"PASS","NavigationScrollFirst":"PASS","AmbiguousSelectionRefusal":"PASS"}'
"PASS: installed-Settings readiness regressions with synthetic UIA elements only. $Workspace"
