#requires -Version 7.2
param([string]$Workspace = (Join-Path $env:TEMP "pt-fancyzones-state-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\pt-fancyzones-state.ps1"
[IO.Directory]::CreateDirectory($Workspace) | Out-Null
$root = Join-Path $Workspace 'owned-files'
if (Test-Path -LiteralPath $root) { throw 'Do not reuse an existing fixture.' }
[IO.Directory]::CreateDirectory($root) | Out-Null
function Require([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Reject([scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return $_
    }
    throw "Expected rejection: $Pattern"
}
$names = @('editor-parameters.json','applied-layouts.json','settings.json','custom-layouts.json')
$oldParameters = '{"process-id":42,"span-zones-across-monitors":false,"monitors":[{"monitor":"left","dpi":144},{"monitor":"right","dpi":144}]}'
$spanParameters = '{"process-id":42,"span-zones-across-monitors":true,"monitors":[{"monitor":"combined","dpi":0,"monitor-width":5120,"work-area-width":3414}]}'
$oldLayouts = '{"applied-layouts":[{"device":"unrelated","layout":"original"}]}'
$newLayouts = '{"applied-layouts":[{"device":"unrelated","layout":"original"},{"device":"combined","layout":"planned"}]}'
$writeFiles = {
    param($Directory, $Parameters, $Layouts)
    [IO.File]::WriteAllText("$Directory\editor-parameters.json", $Parameters)
    [IO.File]::WriteAllText("$Directory\applied-layouts.json", $Layouts)
}
$passed = [Collections.Generic.List[string]]::new()
try {
    & $writeFiles $root $oldParameters $oldLayouts
    [IO.File]::WriteAllText("$root\settings.json", '{"span":false}')
    $baseline = Get-PtFileSetSnapshot -Path $root -FileNames $names
    $baselineJson = $baseline | ConvertTo-Json -Depth 10 -Compress
    $expected = $baseline
    $plan = @{ 'editor-parameters.json' = $spanParameters; 'applied-layouts.json' = $newLayouts }
    $receipt = Invoke-PtFancyZonesFileAction -ExpectedState ([ref]$expected) -Operation EditorOpen -ExpectedJson $plan `
        -Action $writeFiles -ArgumentList @($root, $spanParameters, $newLayouts)
    Require ($receipt.ConfirmedFiles.Count -eq 2) 'Entry must account for both files and the replacement monitor model.'
    Require (($baseline | ConvertTo-Json -Depth 10 -Compress) -ceq $baselineJson) 'Original baseline was mutated.'
    Restore-PtFileSetSnapshot $baseline $expected @('editor-parameters.json','applied-layouts.json') | Out-Null
    $passed.Add('TwoFileEntrySpanningAndOriginalRollback')

    $expected = $baseline
    $plan = @{ 'applied-layouts.json' = '{"applied-layouts":[{"layout":"original","device":"unrelated"}]}' }
    Invoke-PtFancyZonesFileAction -ExpectedState ([ref]$expected) -Operation EditorOpen -ExpectedJson $plan `
        -Action { param($p) [IO.File]::WriteAllText($p, '{ "applied-layouts": [ { "device": "unrelated", "layout": "original" } ] }') } `
        -ArgumentList @("$root\applied-layouts.json") | Out-Null
    Restore-PtFileSetSnapshot $baseline $expected @('applied-layouts.json') | Out-Null
    $passed.Add('SerializationOrderAndWhitespace')

    $expected = $baseline
    $plan = @{ 'editor-parameters.json' = $spanParameters; 'applied-layouts.json' = $newLayouts }
    $failure = Reject {
        Invoke-PtFancyZonesFileAction -ExpectedState ([ref]$expected) -Operation EditorOpen -ExpectedJson $plan `
            -Action $writeFiles -ArgumentList @($root, $spanParameters, '{"applied-layouts":[]}')
    } 'Unconfirmed FancyZones'
    $receipt = $failure.Exception.Data['PtFancyZonesFileActionReceipt']
    Require ($receipt.ConfirmedFiles -ccontains 'editor-parameters.json') 'One conflict discarded an independently confirmed cache update.'
    Require ($receipt.UnconfirmedFiles -ccontains 'applied-layouts.json') 'Unexpected assignment removal was adopted.'
    Reject { Restore-PtFileSetSnapshot $baseline $expected @('applied-layouts.json') } 'conflict; no writes' | Out-Null
    Restore-PtFileSetSnapshot $baseline $expected @('editor-parameters.json') | Out-Null
    Require ([IO.File]::ReadAllText("$root\applied-layouts.json") -ceq '{"applied-layouts":[]}') 'Independent cleanup overwrote conflicted assignments.'
    & $writeFiles $root $oldParameters $oldLayouts
    $passed.Add('PerFileAttributionKeepsConflictGuard')

    $expected = $baseline
    $plan = @{ 'editor-parameters.json' = $spanParameters }
    $failure = Reject {
        Invoke-PtFancyZonesFileAction -ExpectedState ([ref]$expected) -Operation EditorOpen -ExpectedJson $plan `
            -Action { param($p, $json) [IO.File]::WriteAllText($p, $json); throw 'action-failed-after-write' } `
            -ArgumentList @("$root\editor-parameters.json", $spanParameters)
    } 'action-failed-after-write'
    Require (-not $failure.Exception.Data['PtFancyZonesFileActionReceipt'].ActionSucceeded) 'Action failure was swallowed.'
    Restore-PtFileSetSnapshot $baseline $expected @('editor-parameters.json') | Out-Null
    $passed.Add('ActionFailureRetainsConfirmedRecovery')

    $expected = $baseline
    $plan = @{ 'applied-layouts.json' = $newLayouts }
    Reject {
        Invoke-PtFancyZonesFileAction -ExpectedState ([ref]$expected) -Operation EditorOpen -ExpectedJson $plan `
            -Action { param($p, $mutablePlan) $mutablePlan['applied-layouts.json'] = '{"applied-layouts":[]}'; [IO.File]::WriteAllText($p, $mutablePlan['applied-layouts.json']) } `
            -ArgumentList @("$root\applied-layouts.json", $plan)
    } 'Unconfirmed FancyZones' | Out-Null
    & $writeFiles $root $oldParameters $oldLayouts
    Reject {
        Invoke-PtFancyZonesFileAction -ExpectedState ([ref]$expected) -Operation EditorOpen `
            -ExpectedJson @{ 'editor-parameters.json' = $spanParameters } -Action {}
    } 'Unconfirmed FancyZones' | Out-Null
    $passed.Add('FrozenPredictionAndMissingOutput')

    [IO.File]::WriteAllText("$root\applied-layouts.json", '{"concurrent":"edit"}')
    Reject {
        Invoke-PtFancyZonesFileAction -ExpectedState ([ref]$expected) -Operation EditorOpen -ExpectedJson @{} `
            -Action { throw 'action-must-not-run' }
    } 'Pre-action state conflict' | Out-Null
    & $writeFiles $root $oldParameters $oldLayouts
    Reject {
        Invoke-PtFancyZonesFileAction -ExpectedState ([ref]$expected) -Operation EditorOpen `
            -ExpectedJson @{ 'settings.json' = '{}' } -Action { throw 'action-must-not-run' }
    } 'outside the declared' | Out-Null
    $passed.Add('PreActionConflictAndOperationScope')

    $expected = $baseline
    Invoke-PtFancyZonesFileAction -ExpectedState ([ref]$expected) -Operation EditorClose `
        -ExpectedJson @{ 'custom-layouts.json' = '{"custom-layouts":[]}' } `
        -Action { param($p) [IO.File]::WriteAllText($p, '{"custom-layouts":[]}') } `
        -ArgumentList @("$root\custom-layouts.json") | Out-Null
    Restore-PtFileSetSnapshot $baseline $expected @('custom-layouts.json') | Out-Null
    Require (-not (Test-Path -LiteralPath "$root\custom-layouts.json")) 'Originally absent editor file was not removed.'
    $passed.Add('CloseTimeCreationAndOriginalAbsence')

    $expected = $baseline
    Reject {
        Invoke-PtFancyZonesFileAction -ExpectedState ([ref]$expected) -Operation EditorClose `
            -ExpectedJson @{ 'custom-layouts.json' = '{"coordinate":0.1234567890123456789012345678901}' } `
            -Action { param($p) [IO.File]::WriteAllText($p, '{"coordinate":0.1234567890123456789012345678902}') } `
            -ArgumentList @("$root\custom-layouts.json")
    } 'Unconfirmed FancyZones' | Out-Null
    Reject { Restore-PtFileSetSnapshot $baseline $expected @('custom-layouts.json') } 'conflict; no writes' | Out-Null
    $passed.Add('NumericPrecisionDoesNotMaskChanges')
} finally {
    foreach ($name in $names) { [IO.File]::Delete((Join-Path $root $name)) }
    [IO.Directory]::Delete($root, $false)
}
@{ Passed = @($passed); Count = $passed.Count; ProductStateTouched = $false } |
    ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Workspace 'results.json')
"PASS: $($passed.Count) FancyZones state transition groups. $Workspace"
