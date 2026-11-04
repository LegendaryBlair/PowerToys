#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-fz-mutation-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-fancyzones-mutation.ps1"
function Require([bool]$Value,[string]$Message) { if(-not $Value) { throw $Message } }
function Reject($Action,$Pattern) {
    try { & $Action | Out-Null } catch {
        if($_.Exception.Message -notmatch $Pattern) { throw }
        return $_
    }
    throw "Expected rejection: $Pattern"
}
function Json($Text) { ConvertFrom-PtReportJson $Text }
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$root=Join-Path $Workspace 'owned-files'
if(Test-Path $root) { throw 'Do not reuse a live fixture.' }
[IO.Directory]::CreateDirectory($root)|Out-Null
$names=@('editor-parameters.json','applied-layouts.json','custom-layouts.json','app-zone-history.json')
$deviceA=Json '{"monitor":"A","monitor-instance":"one","monitor-number":1,"serial-number":"","virtual-desktop":"{00000000-0000-0000-0000-000000000000}"}'
$deviceB=Json '{"monitor":"B","monitor-instance":"two","monitor-number":2,"serial-number":"","virtual-desktop":"{00000000-0000-0000-0000-000000000000}"}'
$before=[pscustomobject]@{'applied-layouts'=@(
    [pscustomobject]@{device=$deviceA;'applied-layout'=[pscustomobject]@{uuid='{11111111-1111-1111-1111-111111111111}';type='columns';'show-spacing'=$true;spacing=16;'zone-count'=3;'sensitivity-radius'=20}},
    [pscustomobject]@{device=$deviceB;'applied-layout'=[pscustomobject]@{uuid='{22222222-2222-2222-2222-222222222222}';type='rows';'show-spacing'=$true;spacing=16;'zone-count'=2;'sensitivity-radius'=20}}
)}
$oldParameters='{"process-id":42,"span-zones-across-monitors":false,"monitors":[{},{}]}'
$newParameters='{"process-id":42,"span-zones-across-monitors":true,"monitors":[{}]}'
$beforeText=$before|ConvertTo-Json -Depth 20 -Compress
$scope=[pscustomobject]@{WorkAreas=@($deviceA);GeneratedEditorInput=$true;HostProcessId=42;NativeSerialization=$false}
$groups=[Collections.Generic.List[string]]::new()
try {
    [IO.File]::WriteAllText("$root\editor-parameters.json",$oldParameters)
    [IO.File]::WriteAllText("$root\applied-layouts.json",$beforeText)
    $baseline=Get-PtFileSetSnapshot -Path $root -FileNames $names
    $expected=$baseline
    $changed=Json $beforeText
    $changed.'applied-layouts'[0].'applied-layout'.'zone-count'=99
    $receipt=Invoke-PtFancyZonesScopedAction -ExpectedState ([ref]$expected) -Scope $scope `
        -ArgumentList @($root,$newParameters,($changed|ConvertTo-Json -Depth 20 -Compress)) -Action {
            param($directory,$parameters,$layouts)
            [IO.File]::WriteAllText("$directory\editor-parameters.json",$parameters)
            [IO.File]::WriteAllText("$directory\applied-layouts.json",$layouts)
        }
    Require ($receipt.ConfirmedFiles.Count -eq 2) 'A wrong result in an owned record must remain observable and restorable, not become an infrastructure block.'
    Restore-PtFileSetSnapshot $baseline $expected @('editor-parameters.json','applied-layouts.json')|Out-Null
    $groups.Add('OwnedWrongResultRemainsRestorable')

    $expected=$baseline
    $changed.'applied-layouts'[1].'applied-layout'.'zone-count'=88
    Reject {
        Invoke-PtFancyZonesScopedAction -ExpectedState ([ref]$expected) -Scope $scope `
            -ArgumentList @($root,$newParameters,($changed|ConvertTo-Json -Depth 20 -Compress)) -Action {
                param($directory,$parameters,$layouts)
                [IO.File]::WriteAllText("$directory\editor-parameters.json",$parameters)
                [IO.File]::WriteAllText("$directory\applied-layouts.json",$layouts)
            }
    } 'Unattributed.*applied-layouts'|Out-Null
    Restore-PtFileSetSnapshot $baseline $expected @('editor-parameters.json')|Out-Null
    Reject {Restore-PtFileSetSnapshot $baseline $expected @('applied-layouts.json')} 'conflict; no writes'|Out-Null
    [IO.File]::WriteAllText("$root\applied-layouts.json",$beforeText)
    $groups.Add('UnownedAssignmentProtected')

    $expected=$baseline
    $scope=[pscustomobject]@{NewLayoutName='owned-new';NewLayoutType='grid'}
    $custom='{"custom-layouts":[{"uuid":"{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}","name":"owned-new","type":"grid","info":{}}]}'
    Invoke-PtFancyZonesScopedAction -ExpectedState ([ref]$expected) -Scope $scope `
        -ArgumentList @("$root\custom-layouts.json",$custom) -Action {param($path,$json)[IO.File]::WriteAllText($path,$json)}|Out-Null
    $scope=[pscustomobject]@{LayoutIds=@('{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}')}
    Invoke-PtFancyZonesScopedAction -ExpectedState ([ref]$expected) -Scope $scope `
        -ArgumentList @("$root\custom-layouts.json") -Action {param($path)[IO.File]::WriteAllText($path,'{"custom-layouts":[]}')}|Out-Null
    Restore-PtFileSetSnapshot $baseline $expected @('custom-layouts.json')|Out-Null
    $groups.Add('CreatedIdentityAndLastOwnedDeletion')

    $expected=$baseline
    $app=Join-Path $root 'fixture.exe'
    $scope=[pscustomobject]@{ApplicationPaths=@($app)}
    $history=[pscustomobject]@{'app-zone-history'=@([pscustomobject]@{'app-path'=$app;history=@()})}|ConvertTo-Json -Depth 8 -Compress
    Invoke-PtFancyZonesScopedAction -ExpectedState ([ref]$expected) -Scope $scope `
        -ArgumentList @("$root\app-zone-history.json",$history) -Action {param($path,$json)[IO.File]::WriteAllText($path,$json)}|Out-Null
    Restore-PtFileSetSnapshot $baseline $expected @('app-zone-history.json')|Out-Null
    $groups.Add('OriginallyAbsentOwnedHistory')

    $expected=$baseline
    $scope=[pscustomobject]@{WorkAreas=@($deviceA)}
    $changed=Json $beforeText
    $changed.'applied-layouts'[1].'applied-layout'.'zone-count'=88
    Reject {
        Invoke-PtFancyZonesScopedAction -ExpectedState ([ref]$expected) -Scope $scope `
            -ArgumentList @($scope,$deviceB,"$root\applied-layouts.json",($changed|ConvertTo-Json -Depth 20 -Compress)) -Action {
                param($mutable,$other,$path,$json)
                $mutable.WorkAreas+=@($other)
                [IO.File]::WriteAllText($path,$json)
            }
    } 'Unattributed'|Out-Null
    $groups.Add('ScopeFrozenBeforeInput')

    & {
        $flows=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\..\pt-fancyzones-case-flows.ps1",[ref]$null,[ref]$null)
        $definition=$flows.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Apply-PtFancyZonesCaseLayout'},$true)
        . ([scriptblock]::Create($definition.Extent.Text))
        $editorBefore=Json $beforeText
        $duplicate=Json ($editorBefore.'applied-layouts'[0]|ConvertTo-Json -Depth 10)
        $duplicate.device.'monitor-number'=99
        $editorBefore.'applied-layouts'+=@($duplicate)
        $editorAfter=Json ($editorBefore|ConvertTo-Json -Depth 15)
        $editorAfter.'applied-layouts'[0].'applied-layout'.type='custom'
        $editorAfter.'applied-layouts'[0].'applied-layout'.uuid='{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}'
        $global:FzCase=@{Driver=[pscustomobject]@{SelectedMonitorNumber=1;ExpectedModule=$null}}
        function Open-PtFancyZonesEditor {param($Context)}
        function Get-PtFancyZonesSnapshotJson {
            param($Snapshot,$FileName)
            if($FileName -ceq 'editor-parameters.json'){
                [pscustomobject]@{monitors=@([pscustomobject]@{monitor='A';'monitor-instance-id'='one';'monitor-number'=1
                    'monitor-serial-number'='';'virtual-desktop'=[guid]::Empty.ToString('B')})}
            }else{
                [pscustomobject]@{'custom-layouts'=@([pscustomobject]@{name='owned';uuid='{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}'})}
            }
        }
        function New-PtFancyZonesDriverScope {param($Context) [pscustomobject]@{WorkAreas=@($deviceA);NativeSerialization=$false}}
        function Invoke-PtFancyZonesDriverAction {
            param($Context,$Scope,$ArgumentList,$Action)
            Require (Test-PtFancyZonesScopedFileChange applied-layouts.json $editorBefore $editorAfter $Scope) 'Editor application incorrectly required native first-wins serialization.'
        }
        try{Apply-PtFancyZonesCaseLayout -Name owned}finally{$global:FzCase=$null}
    }
    $groups.Add('EditorApplicationPreservesEquivalentHistoricalRecords')
} finally {
    foreach($name in $names) { [IO.File]::Delete((Join-Path $root $name)) }
    [IO.Directory]::Delete($root,$false)
}
@{Passed=@($groups);ProductStateTouched=$false}|ConvertTo-Json|Set-Content (Join-Path $Workspace 'results.json')
"PASS: $($groups.Count) scoped FancyZones mutation groups."
