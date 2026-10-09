# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.

function Get-PtEnvResourceState {
    param([Parameter(Mandatory)]$Resource)

    if ($Resource.Type -eq 'File') {
        try {
            $stream = [IO.File]::Open($Resource.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
                [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        }
        catch [IO.FileNotFoundException] { return @{ Exists = $false } }
        catch [IO.DirectoryNotFoundException] { return @{ Exists = $false } }
        try {
            $memory = [IO.MemoryStream]::new()
            try {
                $stream.CopyTo($memory)
                return @{ Exists = $true; Bytes = [Convert]::ToBase64String($memory.ToArray()) }
            }
            finally { $memory.Dispose() }
        }
        finally { $stream.Dispose() }
    }

    if ($Resource.Type -ne 'UserVariable') { throw 'Unsupported resource type.' }
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Resource.SubKey, $false)
    if ($null -eq $key) { throw 'The tracked registry key no longer exists.' }
    try {
        if ($key.GetValueNames() -notcontains $Resource.Name) { return @{ Exists = $false } }
        $kind = $key.GetValueKind($Resource.Name)
        if ($kind -notin @([Microsoft.Win32.RegistryValueKind]::String, [Microsoft.Win32.RegistryValueKind]::ExpandString)) {
            throw 'Only String and ExpandString environment values can be preserved.'
        }
        return @{
            Exists = $true
            Kind = $kind.ToString()
            Value = $key.GetValue($Resource.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
    }
    finally { $key.Dispose() }
}

function Get-PtEnvStateFingerprint {
    param([Parameter(Mandatory)]$State)
    $canonical = [ordered]@{}
    foreach ($key in @($State.Keys | Sort-Object)) { $canonical[$key] = $State[$key] }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($canonical | ConvertTo-Json -Compress))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash($bytes)) }
    finally { $sha.Dispose() }
}

function Read-PtEnvJournal {
    param([Parameter(Mandatory)][string]$JournalPath)
    $secure = Get-Content -LiteralPath $JournalPath -Raw -ErrorAction Stop | ConvertTo-SecureString -ErrorAction Stop
    $plain = [Net.NetworkCredential]::new('', $secure).Password
    $journal = $plain | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($journal.Version -ne 1) { throw 'Unsupported recovery journal version.' }
    return $journal
}

function Write-PtEnvJournal {
    param([Parameter(Mandatory)][string]$JournalPath, [Parameter(Mandatory)]$Journal)
    $encrypted = ($Journal | ConvertTo-Json -Depth 20 -Compress) |
        ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
    $pending = "$JournalPath.$([guid]::NewGuid().ToString('N')).pending"
    try {
        [IO.File]::WriteAllText($pending, $encrypted)
        [IO.File]::Move($pending, $JournalPath, $true)
    }
    finally {
        if ([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) }
    }
}

function New-PtEnvJournal {
    <#
    .SYNOPSIS
    Create a current-user DPAPI-encrypted recovery journal outside the evidence archive.
    .NOTES
    Requires PowerShell 7 on Windows. Does not mutate product state or create product files.
    #>
    param([Parameter(Mandatory)][string]$JournalPath)
    if (Test-Path -LiteralPath $JournalPath) { throw 'Recovery journal already exists; do not replace its baseline.' }
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $JournalPath) -PathType Container)) {
        throw 'Create a private recovery directory before creating the journal.'
    }
    Write-PtEnvJournal -JournalPath $JournalPath -Journal @{ Version = 1; Resources = @{} }
}

function Add-PtEnvTrackedResource {
    <#
    .SYNOPSIS
    Register a file or named HKCU value before its first mutation; repeat registration is an error.
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory, Position = 0)][string]$JournalPath,
        [Parameter(Mandatory, Position = 1)][string]$Id,
        [Parameter(Mandatory, ParameterSetName = 'File')][string]$FilePath,
        [Parameter(Mandatory, ParameterSetName = 'Variable')][string]$UserVariableName,
        [Parameter(ParameterSetName = 'Variable')][string]$RegistrySubKey = 'Environment'
    )
    $journal = Read-PtEnvJournal $JournalPath
    if ($journal.Resources.ContainsKey($Id)) { throw 'Resource already tracked; retain the original baseline.' }
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        if (-not [IO.Path]::IsPathFullyQualified($FilePath)) { throw 'FilePath must be absolute.' }
        $resource = @{ Type = 'File'; Path = [IO.Path]::GetFullPath($FilePath) }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($UserVariableName) -or $UserVariableName.Contains('=') -or $UserVariableName.Contains([char]0)) {
            throw 'Invalid tracked variable name.'
        }
        $resource = @{ Type = 'UserVariable'; Name = $UserVariableName; SubKey = $RegistrySubKey }
    }
    foreach ($existing in $journal.Resources.Values) {
        if (($resource.Type -eq 'File' -and $existing.Type -eq 'File' -and $resource.Path -eq $existing.Path) -or
            ($resource.Type -eq 'UserVariable' -and $existing.Type -eq 'UserVariable' -and
                $resource.Name -eq $existing.Name -and $resource.SubKey -eq $existing.SubKey)) {
            throw 'The same resource is already registered under another ID.'
        }
    }
    $resource.Baseline = Get-PtEnvResourceState $resource
    $resource.Expected = $resource.Baseline
    $journal.Resources[$Id] = $resource
    Write-PtEnvJournal $JournalPath $journal
    [pscustomobject]@{ Id = $Id; Exists = $resource.Baseline.Exists; Fingerprint = Get-PtEnvStateFingerprint $resource.Baseline }
}

function Get-PtEnvResourceReceipt {
    param([Parameter(Mandatory)][string]$JournalPath, [Parameter(Mandatory)][string]$Id)
    $journal = Read-PtEnvJournal $JournalPath
    if (-not $journal.Resources.ContainsKey($Id)) { throw 'Resource is not registered.' }
    $current = Get-PtEnvResourceState $journal.Resources[$Id]
    [pscustomobject]@{ Id = $Id; Exists = $current.Exists; Fingerprint = Get-PtEnvStateFingerprint $current }
}

function Set-PtEnvOwnedPostState {
    <#
    .SYNOPSIS
    Seal an independently verified owned UI write, not an arbitrary current state.
    .NOTES
    The caller must validate the action's complete semantic diff before passing its receipt.
    This is not an atomic ownership lock. Unknown or intervening writes must not be sealed.
    #>
    param(
        [Parameter(Mandatory)][string]$JournalPath,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Fingerprint,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ActionEvidence
    )
    $journal = Read-PtEnvJournal $JournalPath
    if (-not $journal.Resources.ContainsKey($Id)) { throw 'Resource is not registered.' }
    $resource = $journal.Resources[$Id]
    $current = Get-PtEnvResourceState $resource
    if ((Get-PtEnvStateFingerprint $current) -ne $Fingerprint) { throw "Post-state conflict for resource '$Id'." }
    $resource.Expected = $current
    $resource.ActionEvidence = $ActionEvidence
    Write-PtEnvJournal $JournalPath $journal
}

function Restore-PtEnvJournal {
    <#
    .SYNOPSIS
    Restore only registered resources whose current state equals baseline or sealed owned post-state.
    .NOTES
    Close owned writers first. Conflicts fail before any writes; concurrent changes can still race.
    Restores raw value kinds and file absence. Does not notify running apps, manage processes,
    restore directories/ACLs/timestamps or delete the journal. Verify after the final product writer.
    #>
    param([Parameter(Mandatory)][string]$JournalPath)
    $journal = Read-PtEnvJournal $JournalPath
    foreach ($id in $journal.Resources.Keys) {
        $resource = $journal.Resources[$id]
        $actual = Get-PtEnvStateFingerprint (Get-PtEnvResourceState $resource)
        if ($actual -ne (Get-PtEnvStateFingerprint $resource.Expected) -and
            $actual -ne (Get-PtEnvStateFingerprint $resource.Baseline)) {
            throw "Restoration conflict for resource '$id'; recovery journal retained."
        }
    }

    foreach ($id in $journal.Resources.Keys) {
        $resource = $journal.Resources[$id]
        $actual = Get-PtEnvStateFingerprint (Get-PtEnvResourceState $resource)
        $baseline = $resource.Baseline
        if ($actual -eq (Get-PtEnvStateFingerprint $baseline)) { continue }
        if ($actual -ne (Get-PtEnvStateFingerprint $resource.Expected)) {
            throw "Concurrent restoration conflict for resource '$id'; recovery journal retained."
        }
        if ($resource.Type -eq 'File') {
            if ($baseline.Exists) { [IO.File]::WriteAllBytes($resource.Path, [Convert]::FromBase64String($baseline.Bytes)) }
            else { [IO.File]::Delete($resource.Path) }
        }
        else {
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($resource.SubKey, $true)
            if ($null -eq $key) { throw 'The tracked registry key no longer exists.' }
            try {
                if ($baseline.Exists) {
                    $key.SetValue($resource.Name, $baseline.Value, [Microsoft.Win32.RegistryValueKind]$baseline.Kind)
                }
                else { $key.DeleteValue($resource.Name, $false) }
            }
            finally { $key.Dispose() }
        }
    }
    foreach ($id in $journal.Resources.Keys) {
        $resource = $journal.Resources[$id]
        $actual = Get-PtEnvStateFingerprint (Get-PtEnvResourceState $resource)
        if ($actual -ne (Get-PtEnvStateFingerprint $resource.Baseline)) {
            throw "Final baseline verification failed for resource '$id'; recovery journal retained."
        }
        [pscustomobject]@{ Id = $id; Restored = $true; Fingerprint = $actual }
    }
}

function ConvertTo-PtEnvSafeUiInventory {
    <#
    .SYNOPSIS
    Project a parsed winapp UI tree without disclosing unapproved names or values.
    .NOTES
    Pass only static control names/IDs and exact run-owned synthetic names in the allowlists.
    Slugs are returned only for approved names. Arbitrary value/help/text properties are omitted.
    #>
    param(
        [Parameter(Mandatory)]$Tree,
        [string[]]$AllowedNames = @(),
        [string[]]$AllowedAutomationIds = @()
    )
    function Visit-PtEnvUiNode($Node, [string]$IndexPath) {
        if ($null -eq $Node) { return }
        if ($Node -is [System.Collections.IList]) {
            for ($i = 0; $i -lt $Node.Count; $i++) { Visit-PtEnvUiNode $Node[$i] "$IndexPath[$i]" }
            return
        }
        if ($Node -isnot [pscustomobject]) { return }
        $properties = $Node.PSObject.Properties
        $nameProperty = $properties['name']
        $idProperty = $properties['automationId']
        $allowedName = $null -ne $nameProperty -and $AllowedNames -ccontains [string]$nameProperty.Value
        $allowedId = $null -ne $idProperty -and $AllowedAutomationIds -ccontains [string]$idProperty.Value
        if ($allowedName -or $allowedId) {
            $safe = [ordered]@{ IndexPath = $IndexPath }
            if ($allowedName) { $safe.Name = $nameProperty.Value }
            if ($allowedId) { $safe.AutomationId = $idProperty.Value }
            foreach ($field in @('type', 'controlType', 'isEnabled', 'isOffscreen', 'bounds')) {
                if ($null -ne $properties[$field]) { $safe[$field] = $properties[$field].Value }
            }
            foreach ($field in @('slug', 'selector')) {
                if ($allowedName -and $null -ne $properties[$field]) { $safe[$field] = $properties[$field].Value }
            }
            [pscustomobject]$safe
        }
        foreach ($property in $properties) {
            if ($property.Value -is [pscustomobject] -or $property.Value -is [System.Collections.IList]) {
                Visit-PtEnvUiNode $property.Value "$IndexPath.$($property.Name)"
            }
        }
    }
    Visit-PtEnvUiNode $Tree '$'
}

function Get-PtEnvUiNodes {
    param([Parameter(Mandatory)][AllowEmptyCollection()]$Tree)
    if ($Tree -is [pscustomobject]) {
        $Tree
        foreach ($property in $Tree.PSObject.Properties) {
            if ($property.Value -is [pscustomobject] -or $property.Value -is [System.Collections.IList]) {
                Get-PtEnvUiNodes -Tree $property.Value
            }
        }
    }
    elseif ($Tree -is [System.Collections.IList]) {
        foreach ($node in $Tree) {
            if ($null -ne $node) { Get-PtEnvUiNodes -Tree $node }
        }
    }
}

function Get-PtEnvUserVariableOptionsSelector {
    <#
    .SYNOPSIS
    Resolve one registered variable's options inside the actual User SettingsCard.
    .NOTES
    Pass a fresh parsed tree with UserVariablesExpander expanded. Never choose a flat first/last button.
    #>
    param(
        [Parameter(Mandatory)]$Tree,
        [Parameter(Mandatory)][string]$JournalPath,
        [Parameter(Mandatory)][string]$ResourceId
    )
    $journal = Read-PtEnvJournal $JournalPath
    $resource = $journal.Resources[$ResourceId]
    if ($null -eq $resource -or $resource.Type -ne 'UserVariable') { throw 'Register the owned variable before resolving it.' }
    if (Get-Command Resolve-PtEnvUiRow -ErrorAction Ignore) {
        $row = Resolve-PtEnvUiRow -Tree $Tree -Scope User -Name $resource.Name
        $button = Select-PtEnvUiNode @(Get-PtEnvUiDescendants $row |
            Where-Object automationId -CEQ 'VariableOptionsButton') -Visible
        if ($button.isEnabled -cne $true) { Stop-PtEnvUiOperation Disabled 'Owned variable options unavailable' }
        return [string]$button.selector
    }
    $scopes = @(Get-PtEnvUiNodes $Tree | Where-Object { $_.automationId -ceq 'UserVariablesExpander' })
    if ($scopes.Count -ne 1) { throw 'Expected one UserVariablesExpander; no action is safe.' }
    $cards = @(Get-PtEnvUiNodes $scopes[0] | Where-Object {
        $_.className -ceq 'SettingsCard' -and
        @(Get-PtEnvUiNodes $_ | Where-Object { $_.type -ceq 'Text' -and $_.name -ceq $resource.Name }).Count -eq 1
    })
    if ($cards.Count -ne 1) { throw 'Expected one exact owned variable card; no action is safe.' }
    $buttons = @(Get-PtEnvUiNodes $cards[0] | Where-Object { $_.automationId -ceq 'VariableOptionsButton' })
    if ($buttons.Count -ne 1 -or [string]::IsNullOrWhiteSpace($buttons[0].selector)) {
        throw 'Expected one current options selector within the owned card.'
    }
    return [string]$buttons[0].selector
}

function Set-PtEnvOwnedVariableValue {
    <#
    .SYNOPSIS
    Change a registered variable's value only after checking the open Edit dialog target.
    .NOTES
    Open the menu using Get-PtEnvUserVariableOptionsSelector, then invoke EditVariableMenuItem.
    This function checks ownership before typing and again before Save. It does not seal
    writes or establish product success. The caller must observe both UI surfaces and storage.
    #>
    param(
        [Parameter(Mandatory)][long]$WindowHandle,
        [Parameter(Mandatory)][string]$JournalPath,
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )
    $journal = Read-PtEnvJournal $JournalPath
    $resource = $journal.Resources[$ResourceId]
    if ($null -eq $resource -or $resource.Type -ne 'UserVariable') { throw 'Register the owned variable before editing it.' }
    foreach ($name in @('Path', 'TMP')) {
        if (@($journal.Resources.Values | Where-Object {
            $_.Type -eq 'UserVariable' -and $_.SubKey -eq $resource.SubKey -and $_.Name -ieq $name
        }).Count -ne 1) { throw 'Path and TMP must be snapshotted before editor mutations.' }
    }
    function Assert-PtEnvCurrentDialogTarget {
        $raw = & winapp ui get-value EditVariableDialogNameTxtBox -w $WindowHandle --json 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'Reading the Edit dialog target failed; no further input is safe.' }
        try { $observed = $raw | ConvertFrom-Json -ErrorAction Stop }
        catch { throw 'Edit target read-out was not valid JSON; private raw response withheld.' }
        if ($null -eq $observed.PSObject.Properties['text'] -or $observed.text -cne $resource.Name) {
            throw 'Edit dialog ownership mismatch; cancel the dialog without saving.'
        }
    }
    Assert-PtEnvCurrentDialogTarget
    $output = & winapp ui set-value EditVariableDialogValueTxtBox $Value -w $WindowHandle 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Setting the owned draft value failed; cancel without saving.' }
    Assert-PtEnvCurrentDialogTarget
    $output = & winapp ui invoke PrimaryButton -w $WindowHandle 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Saving the owned variable failed; observe storage before recovery.' }
    [pscustomobject]@{ ResourceId = $ResourceId; TargetCheckedBeforeInput = $true; TargetCheckedBeforeSave = $true; SaveInvoked = $true }
}
