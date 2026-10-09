# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\pt-environment-variables-state.ps1"
$root = Join-Path $env:TEMP "pt-env-state-test-$([guid]::NewGuid().ToString('N'))"
$subKey = "Software\PowerToysVerificationTests\$([guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($root) | Out-Null
$key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subKey)
$journal = Join-Path $root 'recovery.dpapi'
$present = Join-Path $root 'present.json'
$absent = Join-Path $root 'absent.json'

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $caught = $false
    try { & $Action | Out-Null }
    catch {
        $caught = $true
        if ($_.Exception.Message -notmatch $Pattern) { throw }
    }
    Assert-Condition $caught "Expected error: $Pattern"
}

function Seal([string]$Id) {
    $receipt = Get-PtEnvResourceReceipt $journal $Id
    Set-PtEnvOwnedPostState $journal $Id $receipt.Fingerprint 'Synthetic mechanical test write'
}

try {
    [IO.File]::WriteAllBytes($present, [byte[]]@(0, 1, 2, 13, 10, 255))
    $key.SetValue('Expandable', '%TEMP%\original', [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $key.SetValue('Empty', '', [Microsoft.Win32.RegistryValueKind]::String)
    $key.SetValue('Unsupported', 7, [Microsoft.Win32.RegistryValueKind]::DWord)
    New-PtEnvJournal $journal
    Assert-Throws { New-PtEnvJournal $journal } 'already exists'
    Add-PtEnvTrackedResource $journal 'present' -FilePath $present | Out-Null
    Add-PtEnvTrackedResource $journal 'absent' -FilePath $absent | Out-Null
    foreach ($name in @('Expandable', 'Empty', 'Missing')) {
        Add-PtEnvTrackedResource $journal $name -UserVariableName $name -RegistrySubKey $subKey | Out-Null
    }
    Assert-Throws { Add-PtEnvTrackedResource $journal 'present' -FilePath $present } 'already tracked'
    Assert-Throws { Add-PtEnvTrackedResource $journal 'duplicate' -FilePath $present } 'another ID'
    Assert-Throws {
        Add-PtEnvTrackedResource $journal 'Unsupported' -UserVariableName 'Unsupported' -RegistrySubKey $subKey
    } 'Only String'
    Assert-Condition (-not ([IO.File]::ReadAllText($journal).Contains('Expandable'))) 'Journal must not expose payloads.'

    [IO.File]::WriteAllText($present, 'owned')
    [IO.File]::WriteAllText($absent, 'owned new file')
    $key.SetValue('Expandable', 'owned', [Microsoft.Win32.RegistryValueKind]::String)
    $key.SetValue('Empty', 'owned', [Microsoft.Win32.RegistryValueKind]::String)
    $key.SetValue('Missing', 'owned', [Microsoft.Win32.RegistryValueKind]::String)
    Assert-Throws { Restore-PtEnvJournal $journal } 'conflict'
    Assert-Condition ([IO.File]::ReadAllText($present) -eq 'owned') 'Conflict must not partially restore.'
    Assert-Throws { Set-PtEnvOwnedPostState $journal 'present' ('0' * 64) 'bad receipt' } 'conflict'
    foreach ($id in @('present', 'absent', 'Expandable', 'Empty', 'Missing')) { Seal $id }

    [IO.File]::WriteAllText($absent, 'external change')
    Assert-Throws { Restore-PtEnvJournal $journal } 'conflict'
    Assert-Condition ($key.GetValue('Expandable') -eq 'owned') 'Conflict must preserve other resources.'
    [IO.File]::WriteAllText($absent, 'owned new file')
    $receipts = @(Restore-PtEnvJournal $journal)
    Assert-Condition ($receipts.Count -eq 5) 'Missing restoration receipt.'
    Assert-Condition ([Convert]::ToBase64String([IO.File]::ReadAllBytes($present)) -eq 'AAECDQr/') 'Byte-exact rollback failed.'
    Assert-Condition (-not [IO.File]::Exists($absent)) 'Original file absence was not restored.'
    Assert-Condition ($key.GetValueKind('Expandable') -eq [Microsoft.Win32.RegistryValueKind]::ExpandString) 'Registry kind changed.'
    Assert-Condition ($key.GetValue('Expandable', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -ceq '%TEMP%\original') 'Raw expandable value changed.'
    Assert-Condition ($key.GetValue('Empty') -ceq '') 'Empty string was not restored.'
    Assert-Condition ($key.GetValueNames() -notcontains 'Missing') 'Original variable absence was not restored.'
    Assert-Condition (@(Restore-PtEnvJournal $journal).Count -eq 5) 'Restoration is not idempotent.'
    Assert-Condition ([IO.File]::Exists($journal)) 'Recovery journal was prematurely deleted.'
    $tree = '{"elements":[{"name":"private-name","value":"private-value","slug":"private-slug","selector":"private-selector","automationId":"SafeId","type":"Edit"},{"name":"Add","value":"private-value","slug":"btn-add","selector":"btn-add","type":"Button"},{"name":"private-name","children":[{"name":"PT_EV_test","slug":"owned-row","helpText":"private-help"}]}]}' | ConvertFrom-Json
    $safe = @(ConvertTo-PtEnvSafeUiInventory -Tree $tree -AllowedNames @('Add', 'PT_EV_test') -AllowedAutomationIds @('SafeId'))
    $safeJson = $safe | ConvertTo-Json -Depth 10
    Assert-Condition ($safe.Count -eq 3) 'Safe inventory omitted approved controls.'
    Assert-Condition (-not $safeJson.Contains('private-')) 'Safe inventory disclosed private data.'
    Assert-Condition ($safe[2].IndexPath -ceq '$.elements[2].children[0]') 'Safe inventory lost structural scope.'
    Assert-Condition ($safe[1].selector -ceq 'btn-add') 'Current CLI selector was omitted.'

    $ownedTree = '{"elements":[{"automationId":"UserVariablesExpander","children":[{"className":"SettingsCard","children":[{"type":"Text","name":"Missing"},{"automationId":"VariableOptionsButton","selector":"owned-options"}]},{"className":"SettingsCard","children":[{"type":"Text","name":"TMP"},{"automationId":"VariableOptionsButton","selector":"wrong-last-options"}]}]}]}' | ConvertFrom-Json
    Assert-Condition (@(Get-PtEnvUiNodes -Tree @()).Count -eq 0) 'Empty UI children should be traversable.'
    Assert-Condition ((Get-PtEnvUserVariableOptionsSelector -Tree $ownedTree -JournalPath $journal -ResourceId Missing) -ceq 'owned-options') 'Resolver selected the wrong repeated button.'
    $ownedTree.elements[0].children[1].children[0].name = 'Missing'
    Assert-Throws { Get-PtEnvUserVariableOptionsSelector -Tree $ownedTree -JournalPath $journal -ResourceId Missing } 'one exact owned'
    $ownedTree.elements[0].children[1].children[0].name = 'TMP'
    $ownedTree.elements[0].children[0].children[1].selector = ''
    Assert-Throws { Get-PtEnvUserVariableOptionsSelector -Tree $ownedTree -JournalPath $journal -ResourceId Missing } 'one current options'
    $ownedTree.elements[0].automationId = 'SystemVariablesExpander'
    Assert-Throws { Get-PtEnvUserVariableOptionsSelector -Tree $ownedTree -JournalPath $journal -ResourceId Missing } 'one UserVariablesExpander'

    $script:uiCalls = [Collections.Generic.List[string]]::new()
    $script:observedName = 'Missing'
    $script:switchTargetAfterTyping = $false
    function winapp {
        $verb = $args[1]
        $script:uiCalls.Add($verb)
        $global:LASTEXITCODE = 0
        if ($verb -eq 'get-value') { @{ text = $script:observedName } | ConvertTo-Json -Compress }
        elseif ($verb -eq 'set-value' -and $script:switchTargetAfterTyping) { $script:observedName = 'TMP' }
    }
    Assert-Throws { Set-PtEnvOwnedVariableValue -WindowHandle 1 -JournalPath $journal -ResourceId Missing -Value 'test' } 'Path and TMP'
    Assert-Condition ($script:uiCalls.Count -eq 0) 'Input occurred without safety baseline.'
    foreach ($name in @('Path', 'TMP')) {
        Add-PtEnvTrackedResource -JournalPath $journal -Id "safety-$name" -UserVariableName $name -RegistrySubKey $subKey | Out-Null
    }
    $script:observedName = 'TMP'
    Assert-Throws { Set-PtEnvOwnedVariableValue -WindowHandle 1 -JournalPath $journal -ResourceId Missing -Value 'test' } 'ownership mismatch'
    Assert-Condition (($script:uiCalls -join ',') -ceq 'get-value') 'Wrong dialog received input.'
    $script:uiCalls.Clear()
    $script:observedName = 'Missing'
    $script:switchTargetAfterTyping = $true
    Assert-Throws { Set-PtEnvOwnedVariableValue -WindowHandle 1 -JournalPath $journal -ResourceId Missing -Value 'test' } 'ownership mismatch'
    Assert-Condition (-not $script:uiCalls.Contains('invoke')) 'Stale target was committed.'
    $script:uiCalls.Clear()
    $script:observedName = 'Missing'
    $script:switchTargetAfterTyping = $false
    $editReceipt = Set-PtEnvOwnedVariableValue -WindowHandle 1 -JournalPath $journal -ResourceId Missing -Value 'test'
    Assert-Condition (($script:uiCalls -join ',') -ceq 'get-value,set-value,get-value,invoke') 'Safe edit sequence differs.'
    Assert-Condition $editReceipt.TargetCheckedBeforeSave 'Missing pre-save ownership receipt.'
    'PASS: preservation, privacy projection, scoped repeated controls, mandatory safety snapshots and pre-input/pre-save target guards.'
}
finally {
    Remove-Item Function:\winapp -ErrorAction SilentlyContinue
    $key.Dispose()
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($subKey, $false)
    foreach ($file in @($present, $absent, $journal)) {
        if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) }
    }
    [IO.Directory]::Delete($root, $false)
}
