#requires -Version 7.0
<#
.SYNOPSIS
Offline, append-only verification recording and portable report export. Dot-source to load.
.DESCRIPTION
Single writer/runspace per workspace. No desktop, PowerToys, network, or dependency operations.
See ..\references\recording-workflow.md for the public API and recording contract.
#>

function Get-PtReportHash {
    param([byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-', '') } finally { $algorithm.Dispose() }
}

function Get-PtVerificationInputs {
    <#.SYNOPSIS
    Add the actual skill and all top-level loaded PowerShell/native helper sources to explicit run inputs.
    .NOTES
    Does not read product state or infer which checklist/references the caller will use.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Skill, [object[]]$Inputs = @())
    $ErrorActionPreference = 'Stop'
    $root = (Get-Item -LiteralPath $Skill -ErrorAction Stop).FullName
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($inputFile in $Inputs) {
        if (-not $inputFile.Name -or -not $inputFile.Path) { throw 'Each input needs an explicit Name and Path.' }
        if (-not $names.Add($inputFile.Name)) { throw "Duplicate input name: $($inputFile.Name)" }
        $full = (Get-Item -LiteralPath $inputFile.Path -ErrorAction Stop).FullName
        if (-not $paths.Add($full)) { throw "Duplicate input source: $full" }
        $inputFile
    }
    $sources = @((Get-Item -LiteralPath (Join-Path $root 'SKILL.md') -ErrorAction Stop)) +
        @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File |
            Where-Object Extension -In '.ps1','.cs' | Sort-Object Name) +
        @(Get-Item -LiteralPath (Join-Path $root 'scripts\hosts\clipboard-keeper.ps1') -ErrorAction Stop)
    foreach ($file in $sources) {
        if (-not $paths.Add($file.FullName)) { continue }
        $name = "engine-$($file.Name)"
        if (-not $names.Add($name)) { throw "Generated input name conflicts with caller input: $name" }
        @{ Name = $name; Role = $(if ($file.Name -eq 'SKILL.md') { 'Skill' } else { 'Helper' }); Path = $file.FullName }
    }
}

function ConvertFrom-PtReportJson {
    param([string]$Json)
    if ($PSVersionTable.PSVersion -ge [version]'7.5') {
        return ConvertFrom-Json -InputObject $Json -DateKind String -Depth 100
    }
    # JsonElement keeps ISO-looking descriptions as strings on every PowerShell 7 version.
    function ConvertElement([System.Text.Json.JsonElement]$Element) {
        switch ($Element.ValueKind.ToString()) {
            'Object' {
                $value = [ordered]@{}
                foreach ($property in $Element.EnumerateObject()) { $value[$property.Name] = ConvertElement $property.Value }
                [pscustomobject]$value
            }
            'Array' { ,@($Element.EnumerateArray() | ForEach-Object { ConvertElement $_ }) }
            'String' { $Element.GetString() }
            'Number' {
                $integer = 0L
                if ($Element.TryGetInt64([ref]$integer)) { $integer } else { $Element.GetDouble() }
            }
            'True' { $true }
            'False' { $false }
            'Null' { $null }
            default { throw 'Unsupported JSON value.' }
        }
    }
    $document = [System.Text.Json.JsonDocument]::Parse($Json)
    try { ConvertElement $document.RootElement } finally { $document.Dispose() }
}

function Write-PtReportFile {
    param([string]$Path, [byte[]]$Bytes)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}

function Write-PtReportText {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    Write-PtReportFile $Path ([Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Assert-PtReportName {
    param([string]$Name, [int]$MaxLength = 101)
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$' -or $Name.Length -gt $MaxLength -or $Name.Contains('..') -or
        $Name.EndsWith('.') -or $Name -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|$)') {
        throw "Unsafe name: $Name"
    }
}

function Assert-PtReportNoLink {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
            if ([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) {
                if (-not ('PtReportReparse' -as [type])) {
                    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class PtReportReparse {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool DeviceIoControl(SafeFileHandle file, uint control, IntPtr input, uint inputSize,
        byte[] output, uint outputSize, out uint returned, IntPtr overlapped);
    public static uint Tag(string path) {
        if (!path.StartsWith(@"\\?\", StringComparison.Ordinal))
            path = path.StartsWith(@"\\", StringComparison.Ordinal) ? @"\\?\UNC\" + path.Substring(2) : @"\\?\" + path;
        using (var file=CreateFile(path, 0, 7, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero)) {
            if (file.IsInvalid) throw new Win32Exception();
            var buffer=new byte[16384]; uint returned;
            if (!DeviceIoControl(file, 0x900A8, IntPtr.Zero, 0, buffer, (uint)buffer.Length, out returned, IntPtr.Zero))
                throw new Win32Exception();
            if (returned < 4) throw new InvalidOperationException("Incomplete reparse metadata.");
            return BitConverter.ToUInt32(buffer, 0);
        }
    }
}
'@
                }
                # Cloud Files placeholders hydrate in place; symlinks/junctions redirect paths.
                $tag = [PtReportReparse]::Tag($current)
                if (($tag -band 0xFFFF0FFFu) -ne 0x9000001Au) { throw "Redirecting/unsupported reparse point: $current" }
            }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Resolve-PtReportPath {
    param($Run, [string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains('/') -or $RelativePath.Contains(':')) { throw "Unsafe relative path: $RelativePath" }
    foreach ($part in $RelativePath.Split('\')) { Assert-PtReportName $part -MaxLength 200 }
    $path = [IO.Path]::GetFullPath((Join-Path $Run.Workspace $RelativePath))
    if (-not $path.StartsWith($Run.Workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes workspace: $RelativePath"
    }
    Assert-PtReportNoLink $path
    $path
}

function Get-PtReportFileReference {
    param($Run, [string]$RelativePath, [string]$Kind, [string]$Description, [bool]$Synthetic = $false)
    $path = Resolve-PtReportPath $Run $RelativePath
    if (-not [IO.File]::Exists($path)) { throw "Missing evidence file: $RelativePath" }
    $bytes = [IO.File]::ReadAllBytes($path)
    [pscustomobject]@{
        Path = $RelativePath; Sha256 = Get-PtReportHash $bytes; Length = $bytes.LongLength
        Kind = $Kind; Description = $Description; Synthetic = $Synthetic
    }
}

function Assert-PtReportReference {
    param($Run, $Reference)
    $actual = Get-PtReportFileReference $Run $Reference.Path $Reference.Kind $Reference.Description
    if ($actual.Sha256 -cne $Reference.Sha256 -or $actual.Length -ne $Reference.Length) {
        throw "Changed evidence file (SHA256/length mismatch): $($Reference.Path)"
    }
}

function Read-PtReportEvents {
    param($Run, [switch]$Fresh, [switch]$ValidateOnly)
    $journalPath = Resolve-PtReportPath $Run $Run.JournalName
    $journal = [IO.FileInfo]::new($journalPath)
    if (-not $Fresh -and $null -ne $Run.EventCache -and
        $Run.EventCache.Count -eq $Run.Sequence -and $journal.Length -eq $Run.JournalLength -and
        $journal.LastWriteTimeUtc.Ticks -eq $Run.JournalWriteTicks) {
        if (-not $ValidateOnly) { $Run.EventCache.ToArray() }
        return
    }
    $previous = ''
    $sequence = 0
    $cache = [Collections.Generic.List[object]]::new()
    foreach ($line in [IO.File]::ReadAllLines($journalPath)) {
        if (-not $line) { throw 'Corrupt event journal: empty record.' }
        $envelope = ConvertFrom-PtReportJson $line
        $hash = Get-PtReportHash ([Text.Encoding]::UTF8.GetBytes($envelope.Payload))
        if ($hash -cne $envelope.Sha256) { throw 'Corrupt event journal: hash mismatch.' }
        $event = ConvertFrom-PtReportJson $envelope.Payload
        $sequence++
        if ($event.Sequence -ne $sequence -or $event.PreviousHash -cne $previous -or $event.RunId -cne $Run.Id) {
            throw 'Corrupt event journal: missing/reordered event or wrong run.'
        }
        $previous = $hash
        $cache.Add($event)
    }
    if ($sequence -lt $Run.Sequence) { throw 'Corrupt event journal: truncated records.' }
    if ($Run.Sequence -gt 0 -and $sequence -gt $Run.Sequence) { throw 'Stale run handle: reopen the run; concurrent writers are unsupported.' }
    $Run.EventCache = $cache
    $Run.JournalLength = $journal.Length
    $Run.JournalWriteTicks = $journal.LastWriteTimeUtc.Ticks
    $Run.IsCompleted = [bool]@($cache | Where-Object Type -eq 'RunCompleted').Count
    if (-not $ValidateOnly) { $cache.ToArray() }
}

function Add-PtReportEvent {
    param($Run, [string]$Type, $Data, $Attempt = $null, [string]$StepId = '')
    if ($Run.JournalName -ne 'events.jsonl' -or [IO.File]::Exists((Join-Path $Run.Workspace 'artifact-manifest.json'))) {
        throw 'Run is finalized or a read-only export snapshot; start a new run.'
    }
    Read-PtReportEvents $Run -ValidateOnly
    Assert-PtReportNoLink $Run.Workspace
    $event = [ordered]@{
        Sequence = $Run.Sequence + 1; PreviousHash = $Run.LastHash; RunId = $Run.Id
        ItemId = $(if ($Attempt) { $Attempt.ItemId } else { $null })
        AttemptId = $(if ($Attempt) { $Attempt.Id } else { $null })
        Phase = $(if ($Attempt) { $Attempt.Phase } else { 'Run' })
        StepId = $StepId; Type = $Type; Timestamp = [DateTimeOffset]::UtcNow.ToString('o'); Data = $Data
    }
    $payload = ConvertTo-Json -InputObject $event -Depth 40 -Compress
    $hash = Get-PtReportHash ([Text.Encoding]::UTF8.GetBytes($payload))
    $line = ConvertTo-Json -InputObject @{ Payload = $payload; Sha256 = $hash } -Compress
    $stream = [IO.File]::Open((Resolve-PtReportPath $Run 'events.jsonl'), [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($line + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    $Run.Sequence++
    $Run.LastHash = $hash
    $Run.EventCache.Add((ConvertFrom-PtReportJson $payload))
    $journal = [IO.FileInfo]::new((Join-Path $Run.Workspace 'events.jsonl'))
    $Run.JournalLength = $journal.Length
    $Run.JournalWriteTicks = $journal.LastWriteTimeUtc.Ticks
    if ($Type -eq 'RunCompleted') { $Run.IsCompleted = $true }
}

function Assert-PtReportOpen {
    param($Run)
    Read-PtReportEvents $Run -ValidateOnly
    if ($Run.IsCompleted) {
        throw 'Run is completed; only export/validation is allowed.'
    }
}

function New-PtVerificationRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Workspace,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Module,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Bits,
        [Parameter(Mandatory)][ValidateSet('A','B','InfrastructureAcceptance')][string]$Scenario,
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][object[]]$Inputs
    )
    $Scenario = switch ($Scenario) { 'A' { 'A' }; 'B' { 'B' }; default { 'InfrastructureAcceptance' } }
    $root = [IO.Path]::GetFullPath($Workspace).TrimEnd('\')
    Assert-PtReportNoLink $root
    if (Test-Path -LiteralPath $root) { throw 'Workspace must not already exist.' }
    if (-not $Items.Count -or -not $Inputs.Count) { throw 'Explicit item inventory and source inputs are required.' }
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Items) {
        Assert-PtReportName $item.Id
        if (-not $ids.Add($item.Id)) { throw "Duplicate item ID: $($item.Id)" }
        if ($item.UserVisible -isnot [bool] -or [string]::IsNullOrWhiteSpace($item.Description) -or
            $item.Admin -cnotin @('NO','COND','YES') -or $item.Clarity -cnotmatch '^(CLEAR|REWRITTEN|VAGUE-[A-Z0-9-]+)$') {
            throw "Item requires verbatim Description/Admin/Clarity and boolean UserVisible: $($item.Id)"
        }
        $children = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if (-not @($item.Assertions).Count) { throw "Missing subassertions: $($item.Id)" }
        foreach ($child in $item.Assertions) {
            Assert-PtReportName $child.Id
            if (-not $children.Add($child.Id) -or [string]::IsNullOrWhiteSpace($child.Description)) {
                throw "Subassertions require unique IDs and descriptions: $($item.Id)"
            }
            $hasRequired = if ($child -is [Collections.IDictionary]) {
                @($child.Keys | Where-Object { $_ -is [string] -and $_ -ieq 'Required' }).Count -gt 0
            } else { $null -ne $child.PSObject.Properties['Required'] }
            if ($hasRequired) {
                if ($child.Required -isnot [bool]) { throw "Legacy Required must be boolean true or omitted: $($item.Id)/$($child.Id)" }
                if (-not $child.Required) {
                    throw "Optional assertions are not supported: $($item.Id)/$($child.Id). Record a concrete unmet condition or unfinished coverage instead."
                }
            }
        }
    }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($inputFile in $Inputs) {
        Assert-PtReportName $inputFile.Name
        if (-not $names.Add($inputFile.Name)) { throw "Duplicate input name: $($inputFile.Name)" }
        if ($inputFile.Role -cnotin @('Skill','Profile','Checklist','Helper','Other')) { throw 'Unknown input Role.' }
        Assert-PtReportNoLink $inputFile.Path
        if (-not [IO.File]::Exists($inputFile.Path)) { throw "Input must be a real file: $($inputFile.Path)" }
    }
    foreach ($role in 'Skill','Checklist','Helper') {
        if (-not @($Inputs | Where-Object Role -eq $role).Count) { throw "Missing $role input snapshot." }
    }
    [IO.Directory]::CreateDirectory($root) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $root 'inputs')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $root 'attempts')) | Out-Null
    $run = [pscustomobject]@{
        Workspace = $root; Id = [Guid]::NewGuid().ToString('N'); Sequence = 0; LastHash = ''; JournalName = 'events.jsonl'
        EventCache = $null; JournalLength = -1L; JournalWriteTicks = -1L; IsCompleted = $false
    }
    $snapshots = @(
        foreach ($inputFile in $Inputs) {
            $relative = "inputs\$($inputFile.Name)"
            Write-PtReportFile (Resolve-PtReportPath $run $relative) ([IO.File]::ReadAllBytes($inputFile.Path))
            [pscustomobject]@{
                Name = $inputFile.Name; Role = $inputFile.Role; OriginalPath = [IO.Path]::GetFullPath($inputFile.Path)
                File = Get-PtReportFileReference $run $relative 'Input' "Source snapshot: $($inputFile.Role)"
            }
        }
    )
    $metadata = [ordered]@{
        SchemaVersion = 1; RunId = $run.Id; Module = $Module; Bits = $Bits; Scenario = $Scenario
        Created = [DateTimeOffset]::UtcNow.ToString('o'); Items = $Items; Inputs = $snapshots
    }
    Write-PtReportText (Join-Path $root 'run.json') (ConvertTo-Json -InputObject $metadata -Depth 30)
    Write-PtReportText (Join-Path $root 'events.jsonl') ''
    Add-PtReportEvent $run 'RunStarted' @{ Metadata = Get-PtReportFileReference $run 'run.json' 'Inventory' 'Verbatim run inventory and inputs' }
    $run
}

function Open-PtVerificationRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace, [string]$JournalName = 'events.jsonl')
    $root = [IO.Path]::GetFullPath($Workspace).TrimEnd('\')
    Assert-PtReportNoLink $root
    Assert-PtReportName $JournalName
    $metadata = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $root 'run.json')))
    $run = [pscustomobject]@{
        Workspace = $root; Id = $metadata.RunId; Sequence = 0; LastHash = ''; JournalName = $JournalName
        EventCache = $null; JournalLength = -1L; JournalWriteTicks = -1L; IsCompleted = $false
    }
    $events = @(Read-PtReportEvents $run)
    if (-not $events.Count -or $events[0].Type -ne 'RunStarted') { throw 'Missing run initialization event.' }
    $last = ConvertFrom-PtReportJson ([IO.File]::ReadAllLines((Join-Path $root $JournalName))[-1])
    $run.Sequence = $events.Count
    $run.LastHash = $last.Sha256
    Assert-PtReportReference $run $events[0].Data.Metadata
    $run
}

function Get-PtActiveVerificationAttempt {
    [CmdletBinding()]
    param()
    # Global is runspace-local, unlike script scope which changes inside a copied -ScriptFile.
    $value = Get-Variable -Name PtActiveVerificationAttempt -Scope Global -ErrorAction Ignore
    if ($value) { $value.Value }
}

function Set-PtActiveVerificationAttempt {
    [CmdletBinding()]
    param([AllowNull()]$Attempt)
    if ($null -ne $Attempt) { Assert-PtReportAttempt $Attempt }
    $global:PtActiveVerificationAttempt = $Attempt
}

function Assert-PtReportAttempt {
    param($Attempt, [switch]$AllowClosed)
    if (-not $Attempt -or ($Attempt.Closed -and -not $AllowClosed)) { throw 'An open verification attempt is required.' }
    Assert-PtReportOpen $Attempt.Run
}

function Get-PtReportItemCompletion {
    param([object[]]$Events, [string]$ItemId)
    $last = @($Events | Where-Object {
        $_.Type -in 'ItemCompleted','ItemReopened' -and $_.Data.ItemId -ceq $ItemId
    } | Select-Object -Last 1)
    if ($last.Count -and $last[0].Type -eq 'ItemCompleted') { $last[0] }
}

function Reopen-PtVerificationItem {
    <# .SYNOPSIS
    Reopen only one item in an unsealed run. Existing evidence and valid product failures remain.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][string]$ItemId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason)
    Assert-PtReportOpen $Run
    $events = @(Read-PtReportEvents $Run)
    if (-not (Get-PtReportItemCompletion $events $ItemId)) { throw 'Only a completed item can be reopened.' }
    Add-PtReportEvent $Run 'ItemReopened' @{ ItemId = $ItemId; Reason = $Reason }
}

function Start-PtVerificationAttempt {
    [CmdletBinding(DefaultParameterSetName = 'Item')]
    param(
        [Parameter(Mandatory, Position = 0)]$Run,
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'Item')][string]$ItemId,
        [Parameter(Mandatory, ParameterSetName = 'Context')][ValidateSet('Preflight','Cleanup','Diagnostic')][string]$Context,
        [Parameter(Mandatory)][ValidateSet('Normal','Diagnostic')][string]$Kind,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [switch]$Activate
    )
    $Kind = if ($Kind -eq 'Normal') { 'Normal' } else { 'Diagnostic' }
    if ($Context) { $Context = switch ($Context) { 'Preflight' { 'Preflight' }; 'Cleanup' { 'Cleanup' }; default { 'Diagnostic' } } }
    Assert-PtReportOpen $Run
    $events = @(Read-PtReportEvents $Run)
    if ($ItemId) {
        $metadata = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $Run.Workspace 'run.json')))
        if ($ItemId -cnotin @($metadata.Items.Id)) { throw "Unknown inventory item: $ItemId" }
        if (Get-PtReportItemCompletion $events $ItemId) {
            throw 'Item is completed; use Reopen-PtVerificationItem with a reason for local review or rerun.'
        }
    }
    if ($Context -eq 'Diagnostic' -and $Kind -ne 'Diagnostic') { throw 'Diagnostic context requires Diagnostic kind.' }
    $attempt = [pscustomobject]@{
        Run = $Run; Id = [Guid]::NewGuid().ToString('N'); ItemId = $ItemId; Kind = $Kind
        Phase = $(if ($ItemId) { 'Verification' } else { $Context }); Name = $Name
        Closed = $false; StepStack = [Collections.Generic.List[string]]::new(); LastStepId = ''
    }
    [IO.Directory]::CreateDirectory((Join-Path $Run.Workspace "attempts\$($attempt.Id)")) | Out-Null
    Add-PtReportEvent $Run 'AttemptStarted' @{ Kind = $Kind; Name = $Name } $attempt
    if ($Activate) { Set-PtActiveVerificationAttempt $attempt }
    $attempt
}

function Stop-PtVerificationAttempt {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Attempt, [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason)
    Assert-PtReportAttempt $Attempt
    if ($Attempt.StepStack.Count) { throw 'Cannot stop an attempt with running steps.' }
    Add-PtReportEvent $Attempt.Run 'AttemptStopped' @{ Reason = $Reason } $Attempt
    $Attempt.Closed = $true
    if ((Get-PtActiveVerificationAttempt) -eq $Attempt) { Set-PtActiveVerificationAttempt $null }
}

function Get-PtVerificationAttempt {
    <# .SYNOPSIS
    Retrieve a stopped attempt for post-capture review in another process, never resume its driving.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][string]$AttemptId)
    Assert-PtReportOpen $Run
    $events = @(Read-PtReportEvents $Run)
    $start = @($events | Where-Object { $_.Type -eq 'AttemptStarted' -and $_.AttemptId -ceq $AttemptId })
    $stop = @($events | Where-Object { $_.Type -eq 'AttemptStopped' -and $_.AttemptId -ceq $AttemptId })
    if ($start.Count -ne 1 -or $stop.Count -ne 1) { throw 'Review requires exactly one recorded, stopped attempt.' }
    $steps = @($events | Where-Object { $_.Type -eq 'StepStarted' -and $_.AttemptId -ceq $AttemptId })
    $ends = @($events | Where-Object { $_.Type -eq 'StepEnded' -and $_.AttemptId -ceq $AttemptId })
    if (@($steps | Where-Object { $_.StepId -cnotin @($ends.StepId) }).Count) { throw 'An interrupted step cannot be resumed or reviewed as completed.' }
    [pscustomobject]@{
        Run=$Run; Id=$AttemptId; ItemId=$start[0].ItemId; Kind=$start[0].Data.Kind
        Phase=$start[0].Phase; Name=$start[0].Data.Name; Closed=$true
        StepStack=[Collections.Generic.List[string]]::new()
        LastStepId=$(if ($ends.Count) { $ends[-1].StepId } else { '' })
    }
}

function New-PtVerificationArtifactPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Attempt, [Parameter(Mandatory)][string]$Name)
    Assert-PtReportAttempt $Attempt
    Assert-PtReportName $Name
    $relative = "attempts\$($Attempt.Id)\$([Guid]::NewGuid().ToString('N'))-$Name"
    Add-PtReportEvent $Attempt.Run 'ArtifactReserved' @{ Path = $relative } $Attempt
    Resolve-PtReportPath $Attempt.Run $relative
}

function ConvertTo-PtReportArtifactName {
    param([Parameter(Mandatory)][string]$Name)
    $alias = [regex]::Replace($Name, '[^A-Za-z0-9_.-]', '-')
    $alias = [regex]::Replace($alias, '\.{2,}', '.').TrimEnd('.')
    if ($alias -notmatch '^[A-Za-z0-9]' -or $alias -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|$)') {
        $alias = "artifact-$alias"
    }
    if ($alias.Length -gt 101) {
        $extension = [IO.Path]::GetExtension($alias)
        if ($extension.Length -gt 16) { $extension = '' }
        $hash = (Get-PtReportHash ([Text.Encoding]::UTF8.GetBytes($Name))).Substring(0,12)
        $suffix = "-$hash$extension"
        $alias = $alias.Substring(0, 101 - $suffix.Length).TrimEnd('.') + $suffix
    }
    Assert-PtReportName $alias
    $alias
}

function Add-PtVerificationArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Attempt,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('Evidence','Screenshot','Restoration')][string]$Kind,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Description,
        [string]$StepId = '',
        [switch]$Synthetic,
        [string]$Name
    )
    Assert-PtReportAttempt $Attempt
    $Kind = switch ($Kind) { 'Evidence' { 'Evidence' }; 'Screenshot' { 'Screenshot' }; default { 'Restoration' } }
    Assert-PtReportNoLink $Path
    if (-not [IO.File]::Exists($Path)) { throw "Missing evidence file: $Path" }
    $full = [IO.Path]::GetFullPath($Path)
    $originalName = [IO.Path]::GetFileName($full)
    if ($PSBoundParameters.ContainsKey('Name')) { Assert-PtReportName $Name }
    $relative = [IO.Path]::GetRelativePath($Attempt.Run.Workspace, $full)
    $events = @(Read-PtReportEvents $Attempt.Run)
    $priorImport = @($events | Where-Object {
        $_.Type -eq 'ArtifactAdded' -and $_.AttemptId -ceq $Attempt.Id -and $_.Data.SourcePath -ceq $full
    } | Select-Object -Last 1)
    if ($priorImport.Count -and -not $PSBoundParameters.ContainsKey('Name')) {
        $priorFile = $priorImport[0].Data.File
        Assert-PtReportReference $Attempt.Run $priorFile
        if ((Get-PtReportHash ([IO.File]::ReadAllBytes($full))) -ceq $priorFile.Sha256) {
            if ($priorFile.Kind -cne $Kind -or $priorFile.Synthetic -ne $Synthetic.IsPresent) { throw 'Registered evidence cannot be relabeled.' }
            return $priorFile
        }
    }
    $reserved = @($events | Where-Object { $_.Type -eq 'ArtifactReserved' -and $_.AttemptId -ceq $Attempt.Id -and $_.Data.Path -ceq $relative })
    $existing = @($events | Where-Object { $_.Type -eq 'ArtifactAdded' -and $_.Data.File.Path -ceq $relative })
    if ($existing.Count) {
        $source = @($existing | Where-Object AttemptId -CEQ $Attempt.Id | Select-Object -First 1)
        if (-not $source.Count) { $source = @($existing | Select-Object -First 1) }
        $sealed = $source[0].Data.File
        Assert-PtReportReference $Attempt.Run $sealed
        if ($sealed.Kind -cne $Kind -or $sealed.Synthetic -ne $Synthetic.IsPresent -or $PSBoundParameters.ContainsKey('Name')) {
            throw 'Registered evidence cannot be relabeled; reuse its original kind and synthetic flag.'
        }
        if ($source[0].AttemptId -ceq $Attempt.Id) { return $sealed }
        $reference = ConvertFrom-PtReportJson (ConvertTo-Json -InputObject $sealed -Depth 10)
        $reference | Add-Member -Force -NotePropertyName OriginAttemptId -NotePropertyValue $source[0].AttemptId
        $reference | Add-Member -Force -NotePropertyName OriginStepId -NotePropertyValue $source[0].StepId
        $reference | Add-Member -Force -NotePropertyName ReferenceOnly -NotePropertyValue $true
        Add-PtReportEvent $Attempt.Run 'ArtifactAdded' @{ File = $reference } $Attempt
        return $reference
    }
    if ($reserved.Count -and $PSBoundParameters.ContainsKey('Name')) {
        throw 'Name aliases apply to imported files; choose the name when reserving an output path.'
    }
    if (-not $reserved.Count) {
        $alias = if ($PSBoundParameters.ContainsKey('Name')) { $Name } else { ConvertTo-PtReportArtifactName $originalName }
        $destination = New-PtVerificationArtifactPath $Attempt $alias
        Write-PtReportFile $destination ([IO.File]::ReadAllBytes($full))
        $relative = [IO.Path]::GetRelativePath($Attempt.Run.Workspace, $destination)
    }
    $reference = Get-PtReportFileReference $Attempt.Run $relative $Kind $Description $Synthetic.IsPresent
    $reference | Add-Member -NotePropertyName OriginalName -NotePropertyValue $originalName
    if ($Kind -eq 'Screenshot') {
        $bytes = [IO.File]::ReadAllBytes((Resolve-PtReportPath $Attempt.Run $relative))
        $png = $bytes.Length -ge 24 -and [BitConverter]::ToString($bytes, 0, 8) -eq '89-50-4E-47-0D-0A-1A-0A'
        $jpeg = $bytes.Length -ge 4 -and $bytes[0] -eq 255 -and $bytes[1] -eq 216 -and $bytes[-2] -eq 255 -and $bytes[-1] -eq 217
        if (-not ($png -or $jpeg)) { throw 'Screenshot evidence must be a PNG or JPEG, not a renamed text file.' }
    }
    if (-not $StepId -and $Attempt.StepStack.Count) { $StepId = $Attempt.StepStack[-1] }
    if ($StepId -and -not @($events | Where-Object {
        $_.Type -eq 'StepStarted' -and $_.StepId -ceq $StepId -and $_.AttemptId -ceq $Attempt.Id
    }).Count) { throw 'Artifact StepId must identify a recorded step in this attempt.' }
    Add-PtReportEvent $Attempt.Run 'ArtifactAdded' @{ File = $reference; SourcePath = $full } $Attempt $stepId
    $reference
}

function Assert-PtReportEvidence {
    param($Attempt, [object[]]$Evidence)
    $registered = @(Read-PtReportEvents $Attempt.Run | Where-Object { $_.Type -eq 'ArtifactAdded' -and $_.AttemptId -ceq $Attempt.Id })
    foreach ($file in $Evidence) {
        $match = @($registered | Where-Object { $_.Data.File.Path -ceq $file.Path -and $_.Data.File.Sha256 -ceq $file.Sha256 })
        if ($match.Count -ne 1) {
            throw 'Evidence must be registered in this attempt; diagnostic/cross-attempt evidence is not Normal evidence.'
        }
        $sealed = $match[0].Data.File
        if ($file.Kind -cne $sealed.Kind -or $file.Description -cne $sealed.Description -or $file.OriginalName -cne $sealed.OriginalName -or
            $file.OriginAttemptId -cne $sealed.OriginAttemptId -or $file.OriginStepId -cne $sealed.OriginStepId -or
            $file.ReferenceOnly -ne $sealed.ReferenceOnly -or
            $file.Length -ne $sealed.Length -or $file.Synthetic -isnot [bool] -or $file.Synthetic -ne $sealed.Synthetic) {
            throw 'Evidence metadata differs from its sealed registration; do not relabel evidence or remove Synthetic.'
        }
        Assert-PtReportReference $Attempt.Run $file
    }
}

function Write-PtReportSource {
    param($Run, [byte[]]$Bytes, [ValidateSet('executed.ps1','implementation.ps1')][string]$Name)
    $hash = Get-PtReportHash $Bytes
    $relative = "sources\$hash\$Name"
    $path = Resolve-PtReportPath $Run $relative
    $reference = [pscustomobject]@{
        Path=$relative; Sha256=$hash; Length=$Bytes.LongLength
        Kind='ExecutionSource'; Description=$Name; Synthetic=$false
    }
    if ([IO.File]::Exists($path)) {
        # A shared script must still match before it can be executed again.
        Assert-PtReportReference $Run $reference
    } else {
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
        Write-PtReportFile $path $Bytes
    }
    $reference
}

function ConvertTo-PtReportArguments {
    [CmdletBinding()]
    param([object[]]$Arguments)
    $ancestors = [Collections.Generic.List[object]]::new()
    function ConvertArgument($Value, [int]$Depth) {
        if ($Depth -gt 20) { throw 'Recorded arguments exceed the supported JSON depth of 20.' }
        if ($null -eq $Value) { return ,$null }
        if ($Value -is [string] -or $Value.GetType().IsValueType) { return ,$Value }
        if ($Value.PSObject.Properties['StepStack'] -and $Value.PSObject.Properties['Run'] -and
            $Value.Run.PSObject.Properties['JournalName']) {
            return [pscustomobject]@{ RecordedType='VerificationAttempt'; RunId=$Value.Run.Id; AttemptId=$Value.Id
                ItemId=$Value.ItemId; Kind=$Value.Kind; Phase=$Value.Phase; Closed=$Value.Closed }
        }
        if ($Value.PSObject.Properties['EventCache'] -and $Value.PSObject.Properties['JournalName']) {
            return [pscustomobject]@{ RecordedType='VerificationRun'; RunId=$Value.Id; Workspace=$Value.Workspace; JournalName=$Value.JournalName }
        }
        if ($Value -is [scriptblock]) { return [pscustomobject]@{ RecordedType='ScriptBlock'; Text=$Value.ToString() } }
        $dictionary = $Value -is [Collections.IDictionary]
        $sequence = $Value -is [Collections.IEnumerable] -and $Value -isnot [string]
        $record = $Value.PSObject.BaseObject -is [Management.Automation.PSCustomObject]
        if (-not ($dictionary -or $sequence -or $record)) { return ,$Value }
        foreach ($ancestor in $ancestors) {
            if ([object]::ReferenceEquals($ancestor,$Value)) { throw 'Recorded arguments contain a reference cycle.' }
        }
        $ancestors.Add($Value)
        try {
            if ($dictionary) {
                $copy = [ordered]@{}
                foreach ($key in $Value.Keys) {
                    if ($key -isnot [string]) { throw 'Recorded argument dictionary keys must be strings.' }
                    $copy[$key] = ConvertArgument $Value[$key] ($Depth + 1)
                }
                return ,$copy
            }
            if ($sequence) {
                $copy = @(foreach ($entry in $Value) { ConvertArgument $entry ($Depth + 1) })
                return ,$copy
            }
            $copy = [ordered]@{}
            foreach ($property in $Value.PSObject.Properties) { $copy[$property.Name] = ConvertArgument $property.Value ($Depth + 1) }
            [pscustomobject]$copy
        } finally { $ancestors.RemoveAt($ancestors.Count - 1) }
    }
    foreach ($argument in $Arguments) {
        $PSCmdlet.WriteObject((ConvertArgument $argument 0), $false)
    }
}

function Invoke-PtVerificationStep {
    [CmdletBinding(DefaultParameterSetName = 'Action')]
    param(
        [Parameter(Mandatory, Position = 0)]$Attempt,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Command,
        [Parameter(Mandatory, ParameterSetName = 'Action')][scriptblock]$Action,
        [Parameter(Mandatory, ParameterSetName = 'File')][string]$ScriptFile,
        [object[]]$ArgumentList = @(),
        [scriptblock]$Implementation
    )
    Assert-PtReportAttempt $Attempt
    $stepId = [Guid]::NewGuid().ToString('N')
    $relative = "attempts\$($Attempt.Id)\$stepId"
    $directory = Resolve-PtReportPath $Attempt.Run $relative
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    Write-PtReportText "$directory\command.txt" $Command
    $recordedArguments = @(ConvertTo-PtReportArguments $ArgumentList)
    Write-PtReportText "$directory\arguments.json" (ConvertTo-Json -InputObject $recordedArguments -Depth 20 -WarningAction Stop)
    $scriptPath = $null
    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $scriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptFile)
        Assert-PtReportNoLink $scriptPath
        $scriptBytes = [IO.File]::ReadAllBytes($scriptPath)
    } else { $scriptBytes = [Text.UTF8Encoding]::new($false).GetBytes($Action.ToString()) }
    $scriptSource = Write-PtReportSource $Attempt.Run $scriptBytes 'executed.ps1'
    $sources = @(
        foreach ($sourceName in 'command.txt','arguments.json') {
            Get-PtReportFileReference $Attempt.Run "$relative\$sourceName" 'ExecutionSource' $sourceName
        }
        $scriptSource
        if ($Implementation) {
            Write-PtReportSource $Attempt.Run ([Text.UTF8Encoding]::new($false).GetBytes($Implementation.ToString())) 'implementation.ps1'
        }
    )
    foreach ($outputName in 'stdout.txt','streams.jsonl','error.txt') { Write-PtReportText "$directory\$outputName" '' }
    $outputs = @('stdout.txt','streams.jsonl','error.txt' | ForEach-Object { "$relative\$_" })
    $start = [DateTimeOffset]::UtcNow
    $parent = if ($Attempt.StepStack.Count) { $Attempt.StepStack[-1] } else { $null }
    Add-PtReportEvent $Attempt.Run 'StepStarted' @{
        Name = $Name; Command = $Command; Start = $start.ToString('o'); Sources = $sources; OutputPaths = $outputs; ParentStepId = $parent
        ScriptFile = $scriptPath
    } $Attempt $stepId
    $Attempt.StepStack.Add($stepId)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $original = $null
    $previousAttempt = Get-PtActiveVerificationAttempt
    $formatter = $null
    $executionFileLease = $null
    $executionStarted = $false
    try {
        Set-PtActiveVerificationAttempt -Attempt $Attempt
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $true
        if ($PSCmdlet.ParameterSetName -eq 'File') {
            Assert-PtReportNoLink $scriptPath
            $executionFileLease = [IO.File]::Open($scriptPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            if ((Get-PtReportHash ([IO.File]::ReadAllBytes($scriptPath))) -cne $scriptSource.Sha256) {
                throw "Script source changed after recording; execution was not started: $scriptPath"
            }
            $invoke = $scriptPath
        } else { $invoke = $Action }
        $executionStarted = $true
        & $invoke @ArgumentList *>&1 | ForEach-Object {
            $record = $_
            $streamName = switch ($record) {
                { $_ -is [Management.Automation.ErrorRecord] } { 'Error'; break }
                { $_ -is [Management.Automation.WarningRecord] } { 'Warning'; break }
                { $_ -is [Management.Automation.VerboseRecord] } { 'Verbose'; break }
                { $_ -is [Management.Automation.DebugRecord] } { 'Debug'; break }
                { $_ -is [Management.Automation.InformationRecord] } { 'Information'; break }
                default { 'Output' }
            }
            $typeName = if ($null -eq $record) { 'null' } else { $record.GetType().FullName }
            $formatRecord = $typeName.StartsWith('Microsoft.PowerShell.Commands.Internal.Format.', [StringComparison]::Ordinal)
            $text = if ($formatRecord) { [Management.Automation.PSSerializer]::Serialize($record, 20) }
                elseif ($null -eq $record) { '' } elseif ($record -is [string]) { $record } else { $record | Out-String -Width 4096 }
            $entry = ConvertTo-Json -InputObject @{
                Stream = $streamName; Text = $text; Type = $typeName
            } -Compress
            [IO.File]::AppendAllText("$directory\streams.jsonl", $entry + "`n", [Text.UTF8Encoding]::new($false))
            if ($streamName -eq 'Output') {
                if ($formatRecord) {
                    if ($null -eq $formatter) {
                        $outputPath = "$directory\stdout.txt"
                        $formatter = {
                            Out-String -Stream -Width 4096 | ForEach-Object {
                                [IO.File]::AppendAllText($outputPath, $_ + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
                            }
                        }.GetNewClosure().GetSteppablePipeline()
                        $formatter.Begin($true)
                    }
                    $formatter.Process($record)
                } else {
                    [IO.File]::AppendAllText("$directory\stdout.txt", $text, [Text.UTF8Encoding]::new($false))
                }
                $PSCmdlet.WriteObject($record)
            } elseif ($streamName -eq 'Error') {
                throw $record
            } elseif ($streamName -eq 'Warning') { $PSCmdlet.WriteWarning($record.Message)
            } elseif ($streamName -eq 'Verbose') { $PSCmdlet.WriteVerbose($record.Message)
            } elseif ($streamName -eq 'Debug') { $PSCmdlet.WriteDebug($record.Message)
            } elseif ($streamName -eq 'Information') { $PSCmdlet.WriteInformation($record) }
        }
        if ($null -ne $formatter) { $formatter.End() }
    } catch {
        $original = $_
        try {
            [IO.File]::AppendAllText("$directory\error.txt", ($original | Format-List * -Force | Out-String -Width 4096), [Text.UTF8Encoding]::new($false))
        } catch {
            $original.Exception.Data['PtVerificationErrorCaptureFailure'] = $_.Exception.Message
            [Console]::Error.WriteLine("Verification error capture failed: $($_.Exception.Message)")
        }
    } finally {
        try {
            if ($null -ne $executionFileLease) { $executionFileLease.Dispose() }
        } catch {
            if ($original) {
                $original.Exception.Data['PtVerificationScriptReleaseFailure'] = $_.Exception.Message
                [Console]::Error.WriteLine("Script source release failed: $($_.Exception.Message)")
            } else { $original = $_ }
        }
        try {
            if ($null -ne $formatter) { $formatter.Dispose() }
        } catch {
            if ($original) {
                $original.Exception.Data['PtVerificationFormatterCleanupFailure'] = $_.Exception.Message
                [Console]::Error.WriteLine("Formatting cleanup failed: $($_.Exception.Message)")
            } else { $original = $_ }
        }
        $global:PtActiveVerificationAttempt = if ($previousAttempt -and -not $previousAttempt.Closed) { $previousAttempt } else { $null }
        $clock.Stop()
        $endTime = [DateTimeOffset]::UtcNow
        $Attempt.StepStack.RemoveAt($Attempt.StepStack.Count - 1)
        $Attempt.LastStepId = $stepId
        try {
            $files = @($outputs | ForEach-Object { Get-PtReportFileReference $Attempt.Run $_ 'RawOutput' 'Unabridged step output/error stream' })
            Add-PtReportEvent $Attempt.Run 'StepEnded' @{
                End = $endTime.ToString('o'); DurationMs = ($endTime - $start).TotalMilliseconds
                ActionDurationMs = $clock.Elapsed.TotalMilliseconds
                ActionStarted = $executionStarted
                Status = $(if ($original) { 'Error' } else { 'Completed' }); Files = $files
                Error = $(if ($original) {
                    @{ Message = $original.Exception.Message; Type = $original.Exception.GetType().FullName
                       ErrorId = $original.FullyQualifiedErrorId; Stack = $original.ScriptStackTrace; Position = $original.InvocationInfo.PositionMessage }
                } else { $null })
            } $Attempt $stepId
        } catch {
            if (-not $original) { throw }
            $original.Exception.Data['PtVerificationRecordingFailure'] = $_.Exception.Message
            [Console]::Error.WriteLine("Verification completion recording failed: $($_.Exception.Message)")
        }
    }
    if ($original) { $PSCmdlet.ThrowTerminatingError($original) }
}

function Add-PtVerificationAssertion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Attempt,
        [Parameter(Mandatory)][string]$AssertionId,
        [Parameter(Mandatory)][ValidateSet('PASS','FAIL','BLOCKED','NOT-OBSERVED')][string]$Verdict,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Category,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
        [object[]]$Evidence = @(),
        [long]$ObservationSequence = 0
    )
    Assert-PtReportSummaryText $Reason 'Reason'
    $Verdict = $Verdict.ToUpperInvariant()
    Assert-PtReportAttempt $Attempt -AllowClosed
    $metadata = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $Attempt.Run.Workspace 'run.json')))
    $item = $metadata.Items | Where-Object Id -CEQ $Attempt.ItemId
    if (-not $item -or $AssertionId -cnotin @($item.Assertions.Id)) { throw "Unknown inventory assertion: $AssertionId" }
    $events = @(Read-PtReportEvents $Attempt.Run)
    if (Get-PtReportItemCompletion $events $Attempt.ItemId) { throw 'Item is completed; reopen it before reviewing more observations.' }
    if ($ObservationSequence) {
        $raw = @($events | Where-Object { $_.Type -eq 'ObservationRecorded' -and $_.Sequence -eq $ObservationSequence -and
            $_.AttemptId -ceq $Attempt.Id -and $_.Data.AssertionId -ceq $AssertionId })
        if ($raw.Count -ne 1) { throw 'Observation must belong to this assertion and attempt.' }
        if (@($events | Where-Object { $_.Type -eq 'AssertionObserved' -and $_.Data.ObservationSequence -eq $ObservationSequence }).Count) {
            throw 'Observation already reviewed; retain history and record a new observation for corrections.'
        }
        if (-not $Evidence.Count) { $Evidence = @($raw[0].Data.Evidence) }
    }
    $blocked = @('BLK-ENV','BLK-HARDWARE','BLK-DRAG-REQUIRED','BLK-DESTRUCTIVE','BLK-VISUAL-RENDER','BLK-OVERLAY-INPUT-BLOCK','BLK-EXTERNAL-APP','BLK-INFRASTRUCTURE','BLK-INCOMPLETE')
    if (($Verdict -eq 'FAIL' -and $Category -cnotin @('product','checklist-stale','checklist-ambiguous')) -or
        ($Verdict -eq 'BLOCKED' -and $Category -cnotin $blocked) -or
        ($Verdict -eq 'NOT-OBSERVED' -and $Category -cne 'not-observed')) { throw 'Unknown verdict taxonomy category.' }
    if ($Verdict -eq 'PASS' -and -not $Evidence.Count) { throw 'PASS requires explicit observed evidence, not a successful command.' }
    Assert-PtReportEvidence $Attempt $Evidence
    if ($Verdict -eq 'PASS' -and -not @($Evidence | Where-Object { -not $_.ReferenceOnly }).Count) {
        throw 'Cross-attempt references cannot establish a fresh PASS; observe the Normal path in this attempt.'
    }
    Add-PtReportEvent $Attempt.Run 'AssertionObserved' @{
        AssertionId = $AssertionId; Verdict = $Verdict; Category = $Category; Reason = $Reason; Evidence = $Evidence
        ObservationSequence = $ObservationSequence
    } $Attempt
}

function Assert-PtReportSummaryText {
    param([string]$Text,[string]$Field)
    if ([Text.Encoding]::UTF8.GetByteCount($Text) -gt 4096) {
        throw "$Field must be a concise observation (at most 4096 UTF-8 bytes). Supply the full tree/output with Add-PtVerificationObservation -Detail or a registered evidence file."
    }
}

function Add-PtVerificationObservation {
    <# .SYNOPSIS
    Record actual data and candidate mismatches without committing a product verdict.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Attempt, [Parameter(Mandatory)][string]$AssertionId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Actual, [object[]]$Evidence = @(),
        [AllowNull()]$Detail)
    Assert-PtReportAttempt $Attempt
    $metadata = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $Attempt.Run.Workspace 'run.json')))
    $item = $metadata.Items | Where-Object Id -CEQ $Attempt.ItemId
    if (-not $item -or $AssertionId -cnotin @($item.Assertions.Id)) { throw "Unknown inventory assertion: $AssertionId" }
    if (Get-PtReportItemCompletion @(Read-PtReportEvents $Attempt.Run) $Attempt.ItemId) { throw 'Reopen the completed item before collecting observations.' }
    Assert-PtReportEvidence $Attempt $Evidence
    Assert-PtReportSummaryText $Actual 'Actual'
    if ($PSBoundParameters.ContainsKey('Detail')) {
        $text = if ($Detail -is [string]) { $Detail } else { ConvertTo-Json -InputObject $Detail -Depth 100 -WarningAction Stop }
        $extension = if ($Detail -is [string]) { 'txt' } else { 'json' }
        $path = New-PtVerificationArtifactPath $Attempt "observation-detail.$extension"
        Write-PtReportText $path $text
        $Evidence = @($Evidence) + @(Add-PtVerificationArtifact $Attempt $path Evidence 'Complete observation detail; not embedded in the review summary')
    }
    Add-PtReportEvent $Attempt.Run 'ObservationRecorded' @{ AssertionId = $AssertionId; Actual = $Actual; Evidence = $Evidence } $Attempt
    $Attempt.Run.Sequence
}

function Invoke-PtVerificationCase {
    <#
    .SYNOPSIS
    Run one bounded case/context, close its attempt even on error, and return its review handle.
    .NOTES
    No verdict is inferred. The action/script receives the attempt as its first argument.
    Review raw observations afterward and complete only that item; never serialize handles.
    #>
    [CmdletBinding(DefaultParameterSetName='ItemAction')]
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory,ParameterSetName='ItemAction')]
        [Parameter(Mandatory,ParameterSetName='ItemFile')][string]$ItemId,
        [Parameter(Mandatory,ParameterSetName='ContextAction')]
        [Parameter(Mandatory,ParameterSetName='ContextFile')][ValidateSet('Preflight','Cleanup','Diagnostic')][string]$Context,
        [ValidateSet('Normal','Diagnostic')][string]$Kind = 'Normal',
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory,ParameterSetName='ItemAction')]
        [Parameter(Mandatory,ParameterSetName='ContextAction')][scriptblock]$Action,
        [Parameter(Mandatory,ParameterSetName='ItemFile')]
        [Parameter(Mandatory,ParameterSetName='ContextFile')][string]$ScriptFile,
        [object[]]$ArgumentList = @(),
        [string]$OperationKey,
        [ValidateSet('Drive','Observe','Record')][string]$Stage='Drive',
        [scriptblock]$Cleanup,
        [object[]]$CleanupArgumentList=@(),
        [int]$MaxFailures,
        [int]$MaxRecoverySeconds
    )
    $operationBoundary = @('OperationKey','Stage','Cleanup','CleanupArgumentList','MaxFailures','MaxRecoverySeconds' |
        Where-Object { $PSBoundParameters.ContainsKey($_) }).Count -gt 0
    $selector = if ($ItemId) { @{ItemId=$ItemId} } else { @{Context=$Context} }
    $attempt = Start-PtVerificationAttempt -Run $Run @selector -Kind $Kind -Name $Name
    $execution = if ($PSCmdlet.ParameterSetName.EndsWith('File')) { @{ScriptFile=$ScriptFile} } else { @{Action=$Action} }
    $original = $null
    try {
        if ($operationBoundary) {
            if (-not (Get-Command Invoke-PtVerificationOperation -ErrorAction Ignore)) { . "$PSScriptRoot\pt-verification-operation.ps1" }
            $policy=@{}
            foreach($key in 'MaxFailures','MaxRecoverySeconds'){
                if($PSBoundParameters.ContainsKey($key)){$policy[$key]=$PSBoundParameters[$key]}
            }
            $cleanupOptions=@{}
            if($Cleanup){$cleanupOptions=@{Cleanup=$Cleanup;CleanupArgumentList=$CleanupArgumentList}}
            $output = @(Invoke-PtVerificationOperation -Attempt $attempt -OperationKey $OperationKey -Stage $Stage `
                -Command $Command @execution -ArgumentList (@($attempt) + $ArgumentList) @policy @cleanupOptions)
        } else {
            $output = @(Invoke-PtVerificationStep -Attempt $attempt -Name $Name -Command $Command @execution -ArgumentList (@($attempt) + $ArgumentList))
        }
    } catch { $original = $_ }
    finally {
        try { Stop-PtVerificationAttempt $attempt -Reason $(if ($original) { "Driver error: $($original.Exception.Message)" } else { 'Observations recorded; review before committing judgments.' }) }
        catch {
            if ($original) {
                $original.Exception.Data['AttemptCloseFailure'] = $_.Exception.Message
                [Console]::Error.WriteLine("Attempt closure failed: $($_.Exception.Message)")
            } else { throw }
        }
    }
    if ($original) { $PSCmdlet.ThrowTerminatingError($original) }
    [pscustomobject]@{ Attempt = $attempt; Output = $output }
}

function Invalidate-PtVerificationAssertion {
    <#
    .SYNOPSIS
    Append a reviewed correction for an invalid observation/judgment. Never assigns replacement PASS.
    .NOTES
    Requires fresh evidence in a Normal rerun of the same item. Product fixes or Diagnostic
    recovery are not observation errors. Repeat the affected assertions.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Attempt, [Parameter(Mandatory)][long]$Sequence,
        [Parameter(Mandatory)][ValidateSet('InvalidObservation','IncorrectJudgment')][string]$Cause,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]]$Evidence)
    Assert-PtReportAttempt $Attempt -AllowClosed
    if ($Attempt.Kind -ne 'Normal' -or -not $Attempt.ItemId) { throw 'Only a Normal item attempt can correct an invalid judgment.' }
    $events = @(Read-PtReportEvents $Attempt.Run)
    if (Get-PtReportItemCompletion $events $Attempt.ItemId) { throw 'Reopen the completed item before correcting its judgment.' }
    $old = @($events | Where-Object { $_.Type -eq 'AssertionObserved' -and $_.Sequence -eq $Sequence -and $_.ItemId -ceq $Attempt.ItemId })
    if ($old.Count -ne 1 -or $old[0].AttemptId -ceq $Attempt.Id) { throw 'Select an earlier judgment from a different attempt of the same item.' }
    if (@($events | Where-Object { $_.Type -eq 'AssertionInvalidated' -and $_.Data.Sequence -eq $Sequence }).Count) { throw 'Judgment already invalidated.' }
    $source = $events | Where-Object { $_.Type -eq 'AttemptStarted' -and $_.AttemptId -ceq $old[0].AttemptId }
    if ($source.Data.Kind -ne 'Normal') { throw 'Diagnostic results are not Normal judgments to correct.' }
    Assert-PtReportEvidence $Attempt $Evidence
    if (@($Evidence | Where-Object ReferenceOnly).Count) { throw 'Correction requires fresh Normal evidence, not imported recovery/history.' }
    Add-PtReportEvent $Attempt.Run 'AssertionInvalidated' @{
        Sequence = $Sequence; AssertionId = $old[0].Data.AssertionId; Cause = $Cause; Reason = $Reason; Evidence = $Evidence
    } $Attempt
}

function Add-PtVerificationRestoration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Attempt,
        [Parameter(Mandatory)][ValidateSet('PASS','FAIL','BLOCKED')][string]$Verdict,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
        [object[]]$Evidence = @()
    )
    $Verdict = $Verdict.ToUpperInvariant()
    Assert-PtReportAttempt $Attempt
    if ($Attempt.Phase -ne 'Cleanup' -or $Attempt.Kind -ne 'Normal') { throw 'Restoration requires a Normal Cleanup context.' }
    if ($Verdict -eq 'PASS' -and -not @($Evidence | Where-Object Kind -eq 'Restoration').Count) {
        throw 'Restoration PASS requires explicit Restoration evidence (including a no-mutation baseline comparison).'
    }
    Assert-PtReportEvidence $Attempt $Evidence
    if ($Verdict -eq 'PASS' -and -not @($Evidence | Where-Object { $_.Kind -eq 'Restoration' -and -not $_.ReferenceOnly }).Count) {
        throw 'Restoration PASS requires fresh Restoration evidence from the current cleanup, not an earlier receipt.'
    }
    Add-PtReportEvent $Attempt.Run 'RestorationObserved' @{ Verdict = $Verdict; Reason = $Reason; Evidence = $Evidence } $Attempt
}

function Complete-PtVerificationItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Run, [Parameter(Mandatory)][string]$ItemId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason, [string]$Caveats = ''
    )
    Assert-PtReportOpen $Run
    $metadata = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $Run.Workspace 'run.json')))
    if ($ItemId -cnotin @($metadata.Items.Id)) { throw "Unknown inventory item: $ItemId" }
    $events = @(Read-PtReportEvents $Run)
    if (Get-PtReportItemCompletion $events $ItemId) { throw 'Item already completed.' }
    Add-PtReportEvent $Run 'ItemCompleted' @{ ItemId = $ItemId; Reason = $Reason; Caveats = $Caveats }
}

function ConvertTo-PtReportState {
    param($Run, [object[]]$Events, [switch]$ForReview, $Metadata)
    if (-not $events.Count -or $events[0].Type -ne 'RunStarted') { throw 'Missing run initialization event.' }
    if (-not $ForReview) {
        Assert-PtReportReference $Run $events[0].Data.Metadata
        $metadata = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $Run.Workspace 'run.json')))
    }
    $references = [Collections.Generic.List[object]]::new()
    $references.Add($events[0].Data.Metadata)
    foreach ($source in $metadata.Inputs) { $references.Add($source.File) }
    foreach ($event in $events) {
        switch ($event.Type) {
            'ArtifactAdded' { $references.Add($event.Data.File) }
            'StepStarted' { foreach ($file in $event.Data.Sources) { $references.Add($file) } }
            'StepEnded' { foreach ($file in $event.Data.Files) { $references.Add($file) } }
            { $_ -in 'AssertionObserved','RestorationObserved','ObservationRecorded','AssertionInvalidated' } { foreach ($file in $event.Data.Evidence) { $references.Add($file) } }
        }
    }
    if (-not $ForReview) {
        $validated = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($reference in $references) {
            $signature = "$($reference.Length):$($reference.Sha256)"
            if ($validated.ContainsKey($reference.Path)) {
                if ($validated[$reference.Path] -cne $signature) { throw "Conflicting evidence identity: $($reference.Path)" }
            } else {
                Assert-PtReportReference $Run $reference
                $validated.Add($reference.Path, $signature)
            }
        }
    }
    $pendingArtifacts = @($events | Where-Object {
        $_.Type -eq 'ArtifactReserved' -and $_.Data.Path -cnotin @($events | Where-Object Type -eq 'ArtifactAdded' | ForEach-Object { $_.Data.File.Path })
    })
    foreach ($pending in $(if (-not $ForReview) { $pendingArtifacts })) {
        if ([IO.File]::Exists((Resolve-PtReportPath $Run $pending.Data.Path))) {
            $references.Add((Get-PtReportFileReference $Run $pending.Data.Path 'Unsealed' 'Reserved artifact never registered; not assertion evidence'))
        }
    }
    $steps = @(
        foreach ($start in @($events | Where-Object Type -eq 'StepStarted')) {
            $end = @($events | Where-Object { $_.Type -eq 'StepEnded' -and $_.StepId -ceq $start.StepId })
            if ($end.Count -gt 1) { throw 'Duplicate step completion in journal.' }
            $raw = if ($end.Count) { @($end[0].Data.Files) } elseif (-not $ForReview) {
                @($start.Data.OutputPaths | ForEach-Object {
                    $file = Get-PtReportFileReference $Run $_ 'Unsealed' 'Interrupted step raw output; no completion hash'
                    $references.Add($file)
                    $file
                })
            } else { @() }
            [pscustomobject]@{
                Id = $start.StepId; ItemId = $start.ItemId; AttemptId = $start.AttemptId; Phase = $start.Phase
                Name = $start.Data.Name; Command = $start.Data.Command; Start = $start.Data.Start
                End = $(if ($end.Count) { $end[0].Data.End } else { $null })
                DurationMs = $(if ($end.Count) { $end[0].Data.DurationMs } else { $null })
                ActionDurationMs = $(if ($end.Count) { $end[0].Data.ActionDurationMs } else { $null })
                ActionStarted = $(if ($end.Count -and $end[0].Data.PSObject.Properties['ActionStarted']) { $end[0].Data.ActionStarted } else { $null })
                Status = $(if ($end.Count) { $end[0].Data.Status } else { 'INCOMPLETE' })
                Sources = $start.Data.Sources; Outputs = $raw; ParentStepId = $start.Data.ParentStepId
                ScriptFile = $(if ($start.Data.PSObject.Properties['ScriptFile']) { $start.Data.ScriptFile } else { $null })
                Error = $(if ($end.Count) { $end[0].Data.Error } else { $null })
            }
        }
    )
    $attempts = @(
        foreach ($start in @($events | Where-Object Type -eq 'AttemptStarted')) {
            [pscustomobject]@{
                Id = $start.AttemptId; ItemId = $start.ItemId; Phase = $start.Phase; Kind = $start.Data.Kind; Name = $start.Data.Name
                Complete = [bool]@($events | Where-Object { $_.Type -eq 'AttemptStopped' -and $_.AttemptId -ceq $start.AttemptId }).Count
            }
        }
    )
    $effectiveAttempts = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($phase in 'Preflight','Cleanup') {
        $latest = @($attempts | Where-Object { $_.Phase -eq $phase -and $_.Kind -eq 'Normal' } | Select-Object -Last 1)
        if ($latest.Count) { [void]$effectiveAttempts.Add($latest[0].Id) }
    }
    $items = @(
        foreach ($item in $metadata.Items) {
            $normalIds = @($attempts | Where-Object { $_.ItemId -ceq $item.Id -and $_.Kind -eq 'Normal' } | ForEach-Object Id)
            $latestIds = @($normalIds | Select-Object -Last 1)
            if ($latestIds.Count) { [void]$effectiveAttempts.Add($latestIds[0]) }
            $observations = @($events | Where-Object { $_.Type -eq 'AssertionObserved' -and $_.ItemId -ceq $item.Id })
            $corrections = @($events | Where-Object { $_.Type -eq 'AssertionInvalidated' -and $_.ItemId -ceq $item.Id })
            $validObservations = @($observations | Where-Object { $_.Sequence -notin @($corrections.Data.Sequence) })
            $allNormal = @($validObservations | Where-Object AttemptId -CIn $normalIds)
            $completion = @(Get-PtReportItemCompletion $events $item.Id)
            $rawObservations = @($events | Where-Object { $_.Type -eq 'ObservationRecorded' -and $_.ItemId -ceq $item.Id })
            $assertionEvents = @($events | Where-Object {
                $_.AttemptId -cin $normalIds -and $_.Type -in 'AssertionObserved','ObservationRecorded','AssertionInvalidated'
            })
            $assertionAttempts = @{}
            $currentRawObservations = @(foreach ($child in $item.Assertions) {
                $touched = @($assertionEvents | Where-Object { $_.Data.AssertionId -ceq $child.Id })
                $assertionAttempts[$child.Id] = $normalIds | Where-Object { $_ -cin $touched.AttemptId } | Select-Object -Last 1
                $rawObservations | Where-Object { $_.AttemptId -ceq $assertionAttempts[$child.Id] -and $_.Data.AssertionId -ceq $child.Id } | Select-Object -Last 1
            })
            $pendingReviews = @($currentRawObservations | Where-Object {
                $_.Sequence -notin @($observations.Data.ObservationSequence)
            })
            $effectiveNormal = [Collections.Generic.List[object]]::new()
            $assertions = @(
                foreach ($child in $item.Assertions) {
                    $seen = @($allNormal | Where-Object {
                        $_.Data.AssertionId -ceq $child.Id -and $_.AttemptId -ceq $assertionAttempts[$child.Id]
                    } | Sort-Object { if ($_.Data.ObservationSequence) { $_.Data.ObservationSequence } else { $_.Sequence } })
                    $failure = @($allNormal | Where-Object { $_.Data.AssertionId -ceq $child.Id -and $_.Data.Verdict -eq 'FAIL' })
                    $pending = @($pendingReviews | Where-Object { $_.Data.AssertionId -ceq $child.Id })
                    $effective = if ($failure.Count) { $failure[0] } elseif ($pending.Count) { $null } elseif ($seen.Count) { $seen[-1] } else { $null }
                    if ($effective) { $effectiveNormal.Add($effective) }
                    [pscustomobject]@{
                        Id = $child.Id; Description = $child.Description
                        Required = $(if ($child.PSObject.Properties['Required']) { $child.Required } else { $true })
                        AttemptId = $(if ($effective) { $effective.AttemptId } elseif ($pending.Count) { $pending[0].AttemptId } else { $null })
                        Sequence = $(if ($effective) { $effective.Sequence } else { $null })
                        ObservationSequence = $(if ($effective) { $effective.Data.ObservationSequence } elseif ($pending.Count) { $pending[0].Sequence } else { $null })
                        Verdict = $(if ($effective) { $effective.Data.Verdict } else { 'NOT-OBSERVED' })
                        Category = $(if ($effective) { $effective.Data.Category } else { 'not-observed' })
                        Reason = $(if ($effective) { $effective.Data.Reason } elseif ($pending.Count) { "Latest Normal observation awaits review: $($pending[0].Sequence)." } else { 'No reviewed Normal-path observation was recorded.' })
                        Evidence = $(if ($effective) { @($effective.Data.Evidence) } elseif ($pending.Count) { @($pending[0].Data.Evidence) } else { @() })
                    }
                }
            )
            $failures = @($allNormal | Where-Object { $_.Data.Verdict -eq 'FAIL' })
            $missing = @($assertions | Where-Object { $_.Verdict -ne 'PASS' })
            $itemSteps = @($steps | Where-Object ItemId -CEQ $item.Id)
            $currentSteps = @($itemSteps | Where-Object AttemptId -CIn $latestIds)
            $unfinished = @($attempts | Where-Object { $_.ItemId -ceq $item.Id -and -not $_.Complete })
            $capturedScreenshots = @($events | Where-Object {
                $_.Type -eq 'ArtifactAdded' -and $_.Data.File.Kind -eq 'Screenshot' -and $_.AttemptId -cin $normalIds -and
                $_.StepId -cin @($itemSteps | Where-Object Status -eq 'Completed' | ForEach-Object Id)
            } | ForEach-Object { $_.Data.File.Path })
            $screenshot = @($effectiveNormal | Where-Object { $_.Data.Verdict -eq 'PASS' } | ForEach-Object { $_.Data.Evidence } |
                Where-Object { $_.Kind -eq 'Screenshot' -and $_.Path -cin $capturedScreenshots -and
                    -not $_.ReferenceOnly -and (-not $_.Synthetic -or $metadata.Scenario -eq 'InfrastructureAcceptance') })
            $verdict = 'BLOCKED'
            $category = 'BLK-INCOMPLETE'
            $issues = [Collections.Generic.List[string]]::new()
            if (-not $completion.Count) { $issues.Add('Item was not explicitly completed.') }
            if ($pendingReviews.Count) { $issues.Add('Raw observations are awaiting review: ' + ($pendingReviews.Sequence -join ', ')) }
            if ($unfinished.Count) { $issues.Add('Attempt remains open/interrupted.') }
            if (@($currentSteps | Where-Object Status -ne 'Completed').Count) { $issues.Add('Latest Normal attempt has step errors/incomplete execution; infrastructure is not a product verdict.') }
            if (-not $currentSteps.Count) { $issues.Add('No Normal command/probe step was recorded.') }
            if ($missing.Count) { $issues.Add('Subassertions are failed, blocked or NOT-OBSERVED: ' + ($missing.Id -join ', ')) }
            if ($item.UserVisible -and -not $screenshot.Count) { $issues.Add('Missing Normal-path screenshot evidence for user-visible behavior.') }
            if ($failures.Count) {
                $verdict = 'FAIL'
                $category = if (@($failures | Where-Object { $_.Data.Category -eq 'product' }).Count) { 'product' } else { $failures[0].Data.Category }
            } elseif (@($currentSteps | Where-Object Status -eq 'Error').Count) {
                $category = 'BLK-INFRASTRUCTURE'
            } elseif (-not $issues.Count) {
                $verdict = 'PASS'; $category = ($assertions | ForEach-Object Category | Select-Object -Unique) -join '; '
            } elseif (@($missing | Where-Object Verdict -eq 'BLOCKED').Count) {
                $category = @($missing | Where-Object Verdict -eq 'BLOCKED')[0].Category
            }
            [pscustomobject]@{
                Id = $item.Id; Description = $item.Description; Admin = $item.Admin; Clarity = $item.Clarity; UserVisible = $item.UserVisible
                Verdict = $verdict; Category = $category; Assertions = $assertions; Observations = $observations; Issues = $issues.ToArray()
                RawObservations = $rawObservations; CurrentRawObservations = $currentRawObservations; Corrections = $corrections
                Reason = $(if ($completion.Count) { $completion[-1].Data.Reason } else { 'Item incomplete.' })
                Caveats = $(if ($completion.Count) { $completion[-1].Data.Caveats } else { '' })
            }
        }
    )
    $restoration = @($events | Where-Object Type -eq 'RestorationObserved')
    $currentRestoration = @($restoration | Where-Object { $effectiveAttempts.Contains($_.AttemptId) })
    $finished = @($events | Where-Object Type -eq 'RunCompleted')
    $problems = [Collections.Generic.List[string]]::new()
    if (@($items | Where-Object Verdict -ne 'PASS').Count) { $problems.Add('Inventory contains failed, blocked or unobserved/incomplete items.') }
    if (@($items | ForEach-Object Assertions | Where-Object Verdict -ne 'PASS').Count) {
        $problems.Add('Subassertion inventory contains non-passing Normal coverage.')
    }
    $diagnosticIds = @($attempts | Where-Object Kind -eq 'Diagnostic' | ForEach-Object Id)
    if (@($events | Where-Object {
        $_.Type -eq 'AssertionObserved' -and $_.AttemptId -cin $diagnosticIds -and $_.Data.Verdict -ne 'PASS'
    }).Count) { $problems.Add('Non-passing Diagnostic observations remain; they cannot be discarded for signoff.') }
    if (@($steps | Where-Object {
        $_.Status -eq 'INCOMPLETE' -or ($_.Status -eq 'Error' -and $effectiveAttempts.Contains($_.AttemptId))
    }).Count) { $problems.Add('Unresolved execution errors or interrupted steps remain (infrastructure).') }
    if (@($attempts | Where-Object { -not $_.Complete }).Count) { $problems.Add('Open/interrupted attempts remain.') }
    if (@($attempts | Where-Object { $_.Id -cnotin @($steps.AttemptId) }).Count) { $problems.Add('Attempts without recorded commands/probes remain incomplete.') }
    if ($pendingArtifacts.Count) { $problems.Add('Unregistered artifact reservations remain.') }
    if (-not @($attempts | Where-Object { $_.Phase -eq 'Preflight' -and $_.Kind -eq 'Normal' -and $_.Complete }).Count -or
        -not @($steps | Where-Object Phase -eq 'Preflight').Count) { $problems.Add('Recorded preflight is missing.') }
    if (-not $currentRestoration.Count -or @($currentRestoration | Where-Object { $_.Data.Verdict -ne 'PASS' }).Count) {
        $problems.Add('Latest Normal Cleanup attempt lacks successful restoration evidence, or cleanup failed.')
    }
    if (-not $finished.Count) { $problems.Add('Run has not been explicitly finalized; retrospective is NOT-OBSERVED.') }
    [pscustomobject]@{
        SchemaVersion = 1; RunId = $Run.Id; Metadata = $metadata; Items = $items; Attempts = $attempts; Steps = $steps
        Restoration = $restoration; Events = $events; References = $references.ToArray()
        CurrentRestoration = $currentRestoration
        HistoricalRestorationFailures = @($restoration | Where-Object { -not $effectiveAttempts.Contains($_.AttemptId) -and $_.Data.Verdict -ne 'PASS' })
        Signoff = $(if ($ForReview) { 'NOT-VALIDATED' } elseif ($problems.Count) { 'WITHHELD' } else { 'APPROVED' }); SignoffReasons = $problems.ToArray()
        Completion = $(if ($finished.Count) { $finished[-1].Data } else { $null })
    }
}

function Get-PtReportState {
    param($Run)
    # Final export/validation never trusts a same-size/timestamp live cache.
    $state=ConvertTo-PtReportState -Run $Run -Events @(Read-PtReportEvents $Run -Fresh)
    $keys=@($state.Events|Where-Object {$_.Type -in 'OperationStarted','OperationPolicyLocked','OperationRejected'}|
        ForEach-Object {[string]$_.Data.OperationKey}|Select-Object -Unique)
    $operations=@(if($keys.Count){
        if(-not (Get-Command Get-PtVerificationOperationStatus -ErrorAction Ignore)){. "$PSScriptRoot\pt-verification-operation.ps1"}
        foreach($key in $keys){Get-PtVerificationOperationStatus -Run $Run -OperationKey $key}
    })
    $state|Add-Member NoteProperty Operations $operations
    foreach($operation in $operations){
        foreach($issue in @($operation.PendingOperations)+@($operation.UncertainOperations)){
            $state.Signoff='WITHHELD'
            $state.SignoffReasons=@($state.SignoffReasons)+@("Operation invocation '$($issue.OperationId)' has incomplete execution evidence: $($issue.Reason).")
        }
    }
    $state
}

function Get-PtVerificationReview {
    <#
    .SYNOPSIS
    Incrementally project item observations for review without rereading evidence bytes.
    .NOTES
    Not an archive validator or signoff. Uses the same verdict projection as final export.
    Only changed items are reprojected; returned text is explicitly bounded review text.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run, [string[]]$ItemId,
        [ValidateRange(80,4096)][int]$MaxTextCharacters=512)
    Read-PtReportEvents $Run -ValidateOnly
    if (-not $Run.PSObject.Properties['ReviewCache'] -or
        -not [object]::ReferenceEquals($Run.ReviewCache.Source,$Run.EventCache)) {
        Assert-PtReportReference $Run $Run.EventCache[0].Data.Metadata
        $metadata = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $Run.Workspace 'run.json')))
        $buckets = @{}
        foreach ($item in $metadata.Items) {
            $buckets[$item.Id] = @{ Metadata=$item; Events=[Collections.Generic.List[object]]::new(); Dirty=$true; State=$null }
        }
        $Run | Add-Member -Force NoteProperty ReviewCache @{
            Source=$Run.EventCache; Sequence=0; Metadata=$metadata; Buckets=$buckets
        }
    }
    $cache = $Run.ReviewCache
    foreach ($id in $ItemId) {
        if ($id -cnotin @($cache.Metadata.Items.Id)) { throw "Unknown review item: $id" }
    }
    $processed = $Run.EventCache.Count - $cache.Sequence
    for ($index=$cache.Sequence; $index -lt $Run.EventCache.Count; $index++) {
        $event = $Run.EventCache[$index]
        $id = if ($event.ItemId) { $event.ItemId } elseif ($event.Type -in 'ItemCompleted','ItemReopened') { $event.Data.ItemId }
        if ($id -and $cache.Buckets.ContainsKey($id)) {
            $cache.Buckets[$id].Events.Add($event)
            $cache.Buckets[$id].Dirty=$true
        }
    }
    $cache.Sequence=$Run.EventCache.Count
    $selected = if ($ItemId.Count) { @($cache.Metadata.Items | Where-Object Id -CIn $ItemId) } else { @($cache.Metadata.Items) }
    $recomputed=0
    $rows = @(foreach ($item in $selected) {
        $bucket=$cache.Buckets[$item.Id]
        if ($bucket.Dirty) {
            $metadata = [pscustomobject]@{ Items=@($bucket.Metadata); Inputs=@(); Scenario=$cache.Metadata.Scenario }
            $projection = ConvertTo-PtReportState $Run -Events (@($Run.EventCache[0]) + $bucket.Events.ToArray()) -ForReview -Metadata $metadata
            $bucket.State=$projection.Items[0]
            $bucket.Dirty=$false
            $recomputed++
        }
        $state=$bucket.State
        $attempts=@($bucket.Events | Where-Object { $_.Type -eq 'AttemptStarted' -and $_.Data.Kind -eq 'Normal' })
        $latest=if($attempts.Count){$attempts[-1].AttemptId}else{''}
        $observations=@(foreach($observation in $state.CurrentRawObservations){
            [pscustomobject]@{
                Sequence=$observation.Sequence; AssertionId=$observation.Data.AssertionId; AttemptId=$observation.AttemptId
                Reviewed=[bool]@($state.Observations | Where-Object { $_.Data.ObservationSequence -eq $observation.Sequence }).Count
                ActualPreview=Get-PtReportPreview $observation.Data.Actual $MaxTextCharacters
                Truncated=$observation.Data.Actual.Length -gt $MaxTextCharacters
                EvidenceCount=@($observation.Data.Evidence).Count
                Evidence=@($observation.Data.Evidence | Select-Object -First 2 Path,Kind,ReferenceOnly)
            }
        })
        [pscustomobject]@{
            Id=$state.Id; Description=$state.Description; Verdict=$state.Verdict; Category=$state.Category
            Issues=@($state.Issues); LatestNormalAttemptId=$latest; Observations=$observations
            Assertions=@(foreach($assertion in $state.Assertions){
                [pscustomobject]@{
                    Id=$assertion.Id; Description=$assertion.Description; Required=$assertion.Required
                    AttemptId=$assertion.AttemptId; Sequence=$assertion.Sequence; ObservationSequence=$assertion.ObservationSequence
                    Verdict=$assertion.Verdict; Category=$assertion.Category
                    ReasonPreview=Get-PtReportPreview $assertion.Reason $MaxTextCharacters
                    Truncated=$assertion.Reason.Length -gt $MaxTextCharacters
                    EvidenceCount=@($assertion.Evidence).Count
                    Evidence=@($assertion.Evidence | Select-Object -First 2 Path,Kind,ReferenceOnly)
                }
            })
        }
    })
    [pscustomobject]@{
        RunId=$Run.Id; Sequence=$cache.Sequence; IntegrityValidated=$false
        Purpose='Incremental review only; export/archive validation is required for signoff.'
        ProcessedEvents=$processed; RecomputedItems=$recomputed
        Counts=[pscustomobject]@{ Total=$rows.Count; Pass=@($rows|Where-Object Verdict -eq PASS).Count
            Fail=@($rows|Where-Object Verdict -eq FAIL).Count; Blocked=@($rows|Where-Object Verdict -eq BLOCKED).Count }
        Items=$rows
    }
}

function Get-PtReportPreview {
    param([AllowNull()][string]$Text,[int]$Limit)
    if($Text.Length -le $Limit){return $Text}
    $Text.Substring(0,$Limit) + ' [preview truncated; full text is retained in the journal/evidence]'
}

function ConvertTo-PtReportCell {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    # Encode metacharacters before using HTML code spans: pipes/backticks cannot split the table.
    $encoded = [Net.WebUtility]::HtmlEncode($Text)
    $encoded = $encoded.Replace('\','&#92;').Replace('|','&#124;').Replace('`','&#96;').Replace('*','&#42;').Replace('_','&#95;').Replace('[','&#91;').Replace(']','&#93;')
    $encoded.Replace("`r`n", '<br>').Replace("`n", '<br>').Replace("`r", '<br>')
}

function Format-PtReportLink {
    param($Reference)
    $url = $Reference.Path.Replace('\','/')
    "[$(ConvertTo-PtReportCell $Reference.Path)]($url)"
}

function Add-PtReportStepTable {
    param([Collections.Generic.List[string]]$Lines, [object[]]$Steps, $State)
    $Lines.Add('| # | Step | winapp / probe commands | Evidence / result |')
    $Lines.Add('|---|---|---|---|')
    $number = 0
    foreach ($step in $Steps) {
        $number++
        $commandFile = $step.Sources | Where-Object { $_.Path.EndsWith('\command.txt') }
        $scriptFile = $step.Sources | Where-Object { $_.Path.EndsWith('\executed.ps1') }
        $command = if (($step.Command -split "\r\n|\n|\r").Count -gt 3) {
            "script: $(Format-PtReportLink $scriptFile); exact command: $(Format-PtReportLink $commandFile)"
        } else { "<code>$(ConvertTo-PtReportCell $step.Command)</code><br>copy/paste: $(Format-PtReportLink $commandFile)" }
        if ($step.ScriptFile) { $command += "<br>executed from: <code>$(ConvertTo-PtReportCell $step.ScriptFile)</code>" }
        $files = @($step.Outputs) + @($State.Events | Where-Object { $_.Type -eq 'ArtifactAdded' -and $_.StepId -ceq $step.Id } | ForEach-Object { $_.Data.File })
        $links = @($files | ForEach-Object { "$(if ($_.Kind -eq 'Screenshot') { 'screenshot: ' })$(Format-PtReportLink $_)" }) -join '<br>'
        $errorText = if ($step.Error) { '<br>Infrastructure error: ' + (ConvertTo-PtReportCell $step.Error.Message) } else { '' }
        $Lines.Add("| $number | $(ConvertTo-PtReportCell $step.Name)<br>attempt: $($step.AttemptId)<br>phase: $($step.Phase) | $command | **$($step.Status)**; start: $($step.Start); end: $($step.End); ms: $($step.DurationMs)<br>$links$errorText |")
    }
    if (-not $Steps.Count) { $Lines.Add('| 1 | NOT-OBSERVED | No command recorded. | **INCOMPLETE** |') }
}

function Export-PtVerificationReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Run, [switch]$Final)
    $token = [Guid]::NewGuid().ToString('N')
    $prefix = if ($Final) { '' } else { "partial-$token-" }
    $reportName = "${prefix}report.md"
    $detailsName = "${prefix}details.md"
    $resultsName = "${prefix}results.json"
    $manifestName = "${prefix}artifact-manifest.json"
    $journalName = if ($Final) { 'events.jsonl' } else { "${prefix}events.jsonl" }
    try {
        foreach ($name in $reportName,$detailsName,$resultsName,$manifestName) {
            if ([IO.File]::Exists((Resolve-PtReportPath $Run $name))) { throw "Export would overwrite: $name" }
        }
        $state = Get-PtReportState $Run
        if ($Final -and -not $state.Completion) { throw 'Final export requires Complete-PtVerificationRun.' }
        $lines = [Collections.Generic.List[string]]::new()
        $lines.Add("# $(ConvertTo-PtReportCell $state.Metadata.Module) verification report - $($state.Metadata.Created)")
        $lines.Add('')
        $lines.Add('## Summary')
        $pass = @($state.Items | Where-Object Verdict -eq 'PASS').Count
        $product = @($state.Items | Where-Object { $_.Verdict -eq 'FAIL' -and $_.Category -eq 'product' }).Count
        $checklist = @($state.Items | Where-Object { $_.Verdict -eq 'FAIL' -and $_.Category -like 'checklist-*' }).Count
        $blocked = @($state.Items | Where-Object Verdict -eq 'BLOCKED').Count
        $lines.Add("- **Signoff**: **$($state.Signoff)**")
        $lines.Add("- **PASS**: $pass; **FAIL (product)**: $product; **FAIL (checklist)**: $checklist; **BLOCKED**: $blocked; **Total**: $($state.Items.Count); **PASS%**: $([Math]::Round(100 * $pass / $state.Items.Count, 2))")
        $lines.Add("- **BITS**: $(ConvertTo-PtReportCell $state.Metadata.Bits); **Scenario**: $($state.Metadata.Scenario)")
        if ($state.Metadata.Scenario -eq 'InfrastructureAcceptance') { $lines.Add('- **INFRASTRUCTURE ACCEPTANCE ONLY. Not a product signoff. Synthetic fixtures are labeled.**') }
        $lines.Add('- **Top blocker categories**: ' + ((@($state.Items | Where-Object Verdict -eq 'BLOCKED' | Group-Object Category | Sort-Object Count -Descending) | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ', '))
        $lines.Add('- **Items needing follow-up**: ' + ((@($state.Items | Where-Object Verdict -ne 'PASS') | ForEach-Object { "$($_.Id) ($($_.Category))" }) -join ', '))
        foreach ($reason in $state.SignoffReasons) { $lines.Add("- $(ConvertTo-PtReportCell $reason)") }
        $lines.Add('- **State mutations performed + restored**: only the explicit receipts under Cleanup performed apply; no inferred restoration.')
        $lines.Add("- Raw inventory, Unicode text, observations and retrospective: [$resultsName]($resultsName); input snapshots and hashes: [$manifestName]($manifestName).")
        $lines.Add('')
        $lines.Add('## Pre-flight')
        Add-PtReportStepTable $lines @($state.Steps | Where-Object Phase -eq 'Preflight') $state
        $lines.Add('')
        $lines.Add('## Items')
        foreach ($item in $state.Items) {
            $lines.Add('')
            $lines.Add("<a id=`"item-$($item.Id)`"></a>")
            $lines.Add("## Item $($item.Id) - $(ConvertTo-PtReportCell $item.Description) - **$($item.Verdict)**")
            $lines.Add('')
            $lines.Add("**Admin**: $($item.Admin) | **Clarity**: $($item.Clarity) | **Category**: $(ConvertTo-PtReportCell $item.Category)")
            $lines.Add('')
            $lines.Add('### Verification steps performed')
            Add-PtReportStepTable $lines @($state.Steps | Where-Object ItemId -CEQ $item.Id) $state
            $lines.Add('')
            $lines.Add('### Artifacts produced')
            foreach ($attempt in @($state.Attempts | Where-Object ItemId -CEQ $item.Id)) {
                $lines.Add("- Attempt $($attempt.Id): **$($attempt.Kind)**; $(ConvertTo-PtReportCell $attempt.Name); completed=$($attempt.Complete)")
                foreach ($file in @($state.References | Where-Object { $_.Path.StartsWith("attempts\$($attempt.Id)\") } | Sort-Object Path -Unique)) {
                    $lines.Add("- $(Format-PtReportLink $file) - $(ConvertTo-PtReportCell $file.Description)$(if ($file.Synthetic) { ' [SYNTHETIC FIXTURE]' })")
                }
            }
            $lines.Add('')
            $lines.Add('### Verdict reasoning')
            $lines.Add('')
            $lines.Add('| Subassertion | Normal verdict | Reason / evidence |')
            $lines.Add('|---|---|---|')
            foreach ($child in $item.Assertions) {
                $links = @($child.Evidence | ForEach-Object { Format-PtReportLink $_ }) -join '<br>'
                $legacy = if ($child.Required -ceq $false) { 'Legacy metadata: Required=false. ' } else { '' }
                $origin = if ($child.AttemptId) { "<br>Normal attempt: $($child.AttemptId); judgment: $($child.Sequence); observation: $($child.ObservationSequence)" } else { '' }
                $lines.Add("| $($child.Id): $(ConvertTo-PtReportCell $child.Description) | **$($child.Verdict)** | $legacy$(ConvertTo-PtReportCell $child.Reason)$origin<br>$links |")
            }
            $lines.Add('')
            foreach ($observation in $item.Observations) {
                $kind = ($state.Attempts | Where-Object Id -CEQ $observation.AttemptId).Kind
                $lines.Add("- Judgment $($observation.Sequence), $kind attempt $($observation.AttemptId), $($observation.Data.AssertionId): **$($observation.Data.Verdict)** ($(ConvertTo-PtReportCell $observation.Data.Category)) - $(ConvertTo-PtReportCell $observation.Data.Reason)")
            }
            foreach ($raw in $item.RawObservations) {
                $links = @($raw.Data.Evidence | ForEach-Object { Format-PtReportLink $_ }) -join '; '
                $lines.Add("- Raw observation $($raw.Sequence), $($raw.Data.AssertionId): $(ConvertTo-PtReportCell $raw.Data.Actual) $links")
            }
            foreach ($correction in $item.Corrections) {
                $links = @($correction.Data.Evidence | ForEach-Object { Format-PtReportLink $_ }) -join '; '
                $lines.Add("- **Judgment $($correction.Data.Sequence) invalidated** ($($correction.Data.Cause)): $(ConvertTo-PtReportCell $correction.Data.Reason) $links")
            }
            $lines.Add("- $(ConvertTo-PtReportCell $item.Reason)")
            foreach ($issue in $item.Issues) { $lines.Add("- **$(ConvertTo-PtReportCell $issue)**") }
            $lines.Add('')
            $lines.Add('### Caveats')
            $lines.Add($(if ($item.Caveats) { ConvertTo-PtReportCell $item.Caveats } else { 'None recorded. Diagnostic success never substitutes for Normal-path behavior.' }))
        }
        $lines.Add('')
        $lines.Add('## Diagnostic contexts (not checklist items)')
        if (@($state.Attempts | Where-Object Phase -eq 'Diagnostic').Count) {
            Add-PtReportStepTable $lines @($state.Steps | Where-Object Phase -eq 'Diagnostic') $state
        } else { $lines.Add('No non-item diagnostic contexts recorded.') }
        $lines.Add('')
        $lines.Add('## Cleanup performed')
        Add-PtReportStepTable $lines @($state.Steps | Where-Object Phase -eq 'Cleanup') $state
        if (-not $state.Restoration.Count) { $lines.Add('**NOT-OBSERVED: no restoration evidence recorded.**') }
        foreach ($receipt in $state.Restoration) {
            $links = @($receipt.Data.Evidence | ForEach-Object { Format-PtReportLink $_ }) -join '; '
            $scope = if ($receipt.Sequence -in $state.CurrentRestoration.Sequence) { 'Current cleanup' } else { 'Historical cleanup' }
            $lines.Add("- **$($receipt.Data.Verdict)**: $(ConvertTo-PtReportCell $receipt.Data.Reason) $links ($scope; attempt $($receipt.AttemptId); receipt $($receipt.Sequence))")
        }
        if ($state.Operations.Count) {
            $lines.Add('')
            $lines.Add('## Operation boundaries')
            $lines.Add('Invocation history only. No label-based execution locks, cumulative limits, automatic retries or inferred product/restoration judgments. Old policies and rejections below are historical records, not execution rules.')
            $lines.Add('| Legacy label | Invocations | Failures | Failed/diagnostic seconds | Pending records | Uncertain records |')
            $lines.Add('|---|---|---|---|---|---|')
            foreach($operation in $state.Operations){
                $label=if($operation.OperationKey){ConvertTo-PtReportCell $operation.OperationKey}else{'(none)'}
                $lines.Add("| $label | $($operation.InvocationCount) | $($operation.FailureCount) | $($operation.ActiveRecoverySeconds) | $(@($operation.PendingOperations).Count) | $(@($operation.UncertainOperations).Count) |")
            }
            $incompleteEvidence=@($state.Operations|ForEach-Object {$_.PendingOperations;$_.UncertainOperations})
            if($incompleteEvidence.Count){
                $lines.Add('')
                $lines.Add('| Invocation | Attempt | Stage | Evidence gap |')
                $lines.Add('|---|---|---|---|')
                foreach($issue in $incompleteEvidence){
                    $lines.Add("| $($issue.OperationId) | $($issue.AttemptId) | $($issue.Stage) | $($issue.Reason) |")
                }
            }
            $lines.Add('')
            $lines.Add('| Event sequence | Type | Invocation | Legacy label | Stage | Outcome / error |')
            $lines.Add('|---|---|---|---|---|---|')
            foreach($event in @($state.Events|Where-Object {$_.Type -like 'Operation*'})){
                $data=$event.Data
                $outcome=(@($data.Outcome,$data.Reason,$data.Error.Message)|Where-Object {$_}) -join '; '
                if($event.Type -eq 'OperationPolicyLocked'){$outcome=ConvertTo-Json $data -Compress}
                $lines.Add("| $($event.Sequence) | $($event.Type) | $(ConvertTo-PtReportCell $data.OperationId) | $(ConvertTo-PtReportCell $data.OperationKey) | $(ConvertTo-PtReportCell $data.Stage) | $(ConvertTo-PtReportCell $outcome) |")
            }
        }
        $lines.Add('')
        $lines.Add('## Retrospective')
        if (-not $state.Completion) { $lines.Add('**NOT-OBSERVED: partial run.**') }
        elseif ($state.Completion.NoFriction) { $lines.Add("Everything was smooth $([char]0x2014) no friction encountered.") }
        else {
            $lines.Add('| # | Friction (what slowed you / what was wrong) | Source | Severity | Cost | Suggested fix |')
            $lines.Add('|---|---|---|---|---|---|')
            $number = 0
            foreach ($row in $state.Completion.Retrospective) {
                $number++
                $lines.Add("| $number | $(ConvertTo-PtReportCell $row.Friction) | $($row.Source) | $($row.Severity) | $(ConvertTo-PtReportCell $row.Cost) | $(ConvertTo-PtReportCell $row.SuggestedFix) |")
            }
        }
        $lines.Add('')
        $lines.Add('## Artifact manifest')
        $lines.Add("All hashes and portable relative paths: [$manifestName]($manifestName). Raw outputs remain outside Markdown.")
        # Results/report are leaves; the manifest hashes them, never itself or another manifest.
        Write-PtReportText (Resolve-PtReportPath $Run $resultsName) (ConvertTo-Json -InputObject $state -Depth 45)
        Write-PtReportText (Resolve-PtReportPath $Run $detailsName) ($lines -join "`n")
        if (-not (Get-Command ConvertTo-PtVerificationSummary -ErrorAction Ignore)) { . "$PSScriptRoot\pt-verification-render.ps1" }
        $summary = ConvertTo-PtVerificationSummary -State $state -DetailsName $detailsName -ResultsName $resultsName -ManifestName $manifestName
        Write-PtReportText (Resolve-PtReportPath $Run $reportName) $summary
        if (-not $Final) {
            Write-PtReportFile (Resolve-PtReportPath $Run $journalName) ([IO.File]::ReadAllBytes((Resolve-PtReportPath $Run $Run.JournalName)))
        }
        $files = @($state.References | Sort-Object Path -Unique) + @(
            Get-PtReportFileReference $Run $journalName 'Journal' 'Append-only hash-chained events at export time'
            Get-PtReportFileReference $Run $reportName 'Report' 'Rendered report'
            Get-PtReportFileReference $Run $detailsName 'Details' 'Complete commands, attempts, corrections and evidence'
            Get-PtReportFileReference $Run $resultsName 'Results' 'Machine-readable results'
        )
        foreach ($file in $files) { Assert-PtReportReference $Run $file }
        $manifest = @{ SchemaVersion = 1; RunId = $Run.Id; Files = $files; ReportPath = $reportName; DetailsPath = $detailsName; ResultsPath = $resultsName; JournalPath = $journalName }
        Write-PtReportText (Resolve-PtReportPath $Run $manifestName) (ConvertTo-Json -InputObject $manifest -Depth 15)
        [pscustomobject]@{ Report = Join-Path $Run.Workspace $reportName; Results = Join-Path $Run.Workspace $resultsName
            Details = Join-Path $Run.Workspace $detailsName
            Manifest = Join-Path $Run.Workspace $manifestName; Signoff = $state.Signoff }
    } catch {
        $original = $_
        try { Write-PtReportText (Join-Path $Run.Workspace "export-failure-$token.txt") ($original | Format-List * -Force | Out-String -Width 4096) }
        catch {
            $original.Exception.Data['PtVerificationExportDiagnosticFailure'] = $_.Exception.Message
            [Console]::Error.WriteLine("Export diagnostic could not be saved: $($_.Exception.Message)")
        }
        $PSCmdlet.ThrowTerminatingError($original)
    }
}

function Complete-PtVerificationRun {
    [CmdletBinding(DefaultParameterSetName = 'Friction')]
    param(
        [Parameter(Mandatory, Position = 0)]$Run,
        [Parameter(Mandatory, ParameterSetName = 'Friction')][object[]]$Retrospective,
        [Parameter(Mandatory, ParameterSetName = 'Smooth')][switch]$NoFriction
    )
    Assert-PtReportOpen $Run
    if ($PSCmdlet.ParameterSetName -eq 'Smooth' -and -not $NoFriction) { throw 'Explicit -NoFriction or retrospective rows are required.' }
    if ($PSCmdlet.ParameterSetName -eq 'Friction') {
        if (-not $Retrospective.Count) { throw 'Retrospective cannot be empty; explicitly use -NoFriction if applicable.' }
        foreach ($row in $Retrospective) {
            if ($row.Source -cnotin @('SKILL-UNCLEAR','WINAPP-TOOL-BUG','WINAPP-DOC-UNCLEAR','HELPER-FLAW','PT-PRODUCT','CHECKLIST','ENVIRONMENT') -or
                $row.Severity -cnotin @('HIGH','MED','LOW') -or [string]::IsNullOrWhiteSpace($row.Friction) -or
                [string]::IsNullOrWhiteSpace($row.Cost) -or [string]::IsNullOrWhiteSpace($row.SuggestedFix)) { throw 'Invalid retrospective row.' }
        }
    }
    try { Get-PtReportState $Run | Out-Null }
    catch {
        $original = $_
        try {
            Write-PtReportText (Join-Path $Run.Workspace "finalization-failure-$([Guid]::NewGuid().ToString('N')).txt") `
                ($original | Format-List * -Force | Out-String -Width 4096)
        } catch {
            $original.Exception.Data['PtVerificationFinalizationDiagnosticFailure'] = $_.Exception.Message
            [Console]::Error.WriteLine("Finalization diagnostic could not be saved: $($_.Exception.Message)")
        }
        $PSCmdlet.ThrowTerminatingError($original)
    }
    Add-PtReportEvent $Run 'RunCompleted' @{ NoFriction = $NoFriction.IsPresent; Retrospective = @($Retrospective) }
    Export-PtVerificationReport $Run -Final
}

function Test-PtVerificationArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Workspace, [string]$ManifestName = 'artifact-manifest.json')
    Assert-PtReportName $ManifestName
    $location = [pscustomobject]@{ Workspace = [IO.Path]::GetFullPath($Workspace).TrimEnd('\') }
    $manifest = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Resolve-PtReportPath $location $ManifestName)))
    $run = Open-PtVerificationRun $location.Workspace -JournalName $manifest.JournalPath
    if ($manifest.RunId -cne $run.Id -or -not $manifest.Files.Count) { throw 'Invalid artifact manifest.' }
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $manifest.Files) {
        if (-not $paths.Add($file.Path) -or $file.Path -eq $ManifestName) { throw 'Duplicate/circular artifact manifest entry.' }
        Assert-PtReportReference $run $file
    }
    $state = Get-PtReportState $run
    foreach ($reference in @($state.References) + @(
        [pscustomobject]@{ Path = $manifest.JournalPath }
        [pscustomobject]@{ Path = $manifest.ReportPath }
        [pscustomobject]@{ Path = $manifest.ResultsPath }
        if ($manifest.DetailsPath) { [pscustomobject]@{ Path = $manifest.DetailsPath } }
    )) {
        if (-not $paths.Contains($reference.Path)) { throw "Manifest omits required artifact: $($reference.Path)" }
    }
    [pscustomobject]@{ Valid = $true; RunId = $run.Id; FileCount = $paths.Count; Signoff = $state.Signoff }
}
