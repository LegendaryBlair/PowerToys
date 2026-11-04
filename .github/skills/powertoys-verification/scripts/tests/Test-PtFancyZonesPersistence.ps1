#requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-fancyzones-mutation.ps1"
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
$script:signatures=@('before','template-written','default-written','history-written','history-written','history-written')
$script:reads=0
function Get-PtFileSetSnapshot {
    param($Path,$FileNames,$MaxBytes)
    $signature=$script:signatures[[Math]::Min($script:reads,$script:signatures.Count-1)]
    $script:reads++
    [pscustomobject]@{FileState=[pscustomobject]@{Files=@(
        [pscustomobject]@{RelativePath='layout-templates.json';Length=1;Sha256=$signature}
    )}}
}
function Wait-PtCondition {
    param($Description,$TimeoutSeconds,$Probe)
    for($i=0;$i -lt 12;$i++){$result=& $Probe;if($result){return $result}}
    throw 'Timed out before persistence settled'
}
$context=@{ModuleRoot='unused';ExpectedModule=@{FileNames=@('layout-templates.json')}}
$result=Wait-PtFancyZonesPersistence -Context $context -Ready {param($snapshot) $snapshot.FileState.Files[0].Sha256 -ne 'before'}
Require ($result.Samples -eq 6 -and $result.StableSamples -eq 3) 'Delayed dependent writes were mistaken for settled persistence.'
Require ($null -eq $context.ExpectedModule.FileState) 'Readiness adopted a new expected snapshot.'
$script:signatures=@('stable')
$script:reads=0
$result=Wait-PtFancyZonesPersistence -Context $context -Ready {param($snapshot) $script:reads -ge 2}
Require ($result.Samples -eq 4) 'A not-ready sample was counted as confirmed persistence.'
$before=ConvertFrom-PtReportJson '{"default-layouts":[{"monitor-configuration":"horizontal","layout":{"type":"columns","zone-count":3}},{"monitor-configuration":"vertical","layout":{"type":"rows","zone-count":2}}]}'
$predicted=ConvertFrom-PtReportJson '{"default-layouts":[{"monitor-configuration":"horizontal","layout":{"type":"columns","zone-count":5}},{"monitor-configuration":"vertical","layout":{"type":"rows","zone-count":2}}]}'
$scope=[pscustomobject]@{DefaultOrientations=@('horizontal');PredictedDefaults=$predicted}
Require (Test-PtFancyZonesScopedFileChange 'default-layouts.json' $before $predicted $scope) 'Predicted referencing-default write was rejected.'
$unexpected=ConvertFrom-PtReportJson (ConvertTo-Json $predicted -Depth 10)
$unexpected.'default-layouts'[0].layout.type='grid'
Require (-not(Test-PtFancyZonesScopedFileChange 'default-layouts.json' $before $unexpected $scope)) 'Unpredicted field change in the referencing default was adopted.'
$script:reads=0
$errorRecord=$null
try{Wait-PtFancyZonesPersistence -Context $context -Ready {param($snapshot) $false}|Out-Null}catch{$errorRecord=$_}
Require ($null -ne $errorRecord -and $errorRecord.Exception.Data['FancyZonesPersistenceReadiness'].Samples -eq 12) 'Readiness timeout lacks retained observations.'
'PASS: asynchronous dependent writes settle; original expected state remains untouched; exact default prediction and timeout are enforced.'
