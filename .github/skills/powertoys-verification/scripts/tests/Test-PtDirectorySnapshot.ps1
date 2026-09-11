<#
.SYNOPSIS
Offline, dependency-free acceptance for explicitly owned directory restoration.
.DESCRIPTION
Creates a new workspace, retains JSON evidence, and removes only its named fixture directories.
No applications, desktop, settings, registry, network, installations or historical archives.
.EXAMPLE
pwsh -NoProfile -File .\Test-PtDirectorySnapshot.ps1 -Workspace 'D:\evidence\unique-h04-run'
#>
param([string]$Workspace = (Join-Path $env:TEMP "pt-directory-acceptance-$([Guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$helper = Join-Path (Split-Path $PSScriptRoot -Parent) 'pt-directory-snapshot.ps1'
. $helper
$Workspace = Resolve-PtDirectorySnapshotPath $Workspace
if ((Get-PtDirectoryPathKind $Workspace) -ne 'Absent') { throw 'Use a new workspace for each acceptance attempt.' }
if ((Get-PtDirectoryPathKind ([IO.Path]::GetDirectoryName($Workspace))) -ne 'Directory') { throw 'Workspace parent must already exist.' }
[void][IO.Directory]::CreateDirectory($Workspace)
$results = [Collections.Generic.List[object]]::new()
$fixtures = [Collections.Generic.List[string]]::new()
$receipts = [Collections.Generic.List[object]]::new()
$sourceHashes = @(foreach ($source in @($PSCommandPath, $helper)) {
    [pscustomobject]@{ Path = $source; Sha256 = (Get-FileHash -LiteralPath $source).Hash }
})

function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        if ($_.Exception.Data.Contains('PtDirectorySnapshotReceipt')) { $receipts.Add($_.Exception.Data['PtDirectorySnapshotReceipt']) }
        return
    }
    throw "Expected rejection matching: $Pattern"
}
function Check([string]$Name, [scriptblock]$Action) {
    try {
        & $Action | Out-Null
        $results.Add([pscustomobject]@{ Name = $Name; Status = 'PASS' })
    } catch {
        $results.Add([pscustomobject]@{ Name = $Name; Status = 'FAIL'; Error = $_.Exception.Message; Stack = $_.ScriptStackTrace })
        throw
    } finally {
        ConvertTo-Json -InputObject @($results) -Depth 8 | Set-Content -LiteralPath "$Workspace\results.json"
    }
}
function New-Fixture([switch]$Absent) {
    $path = Join-Path $Workspace "fixture-$([Guid]::NewGuid().ToString('N'))"
    $fixtures.Add($path)
    if (-not $Absent) { [void][IO.Directory]::CreateDirectory($path) }
    $path
}
function Write-Bytes([string]$Path, [byte[]]$Bytes = @(1,2,3)) { [IO.File]::WriteAllBytes($Path, $Bytes) }
function Roundtrip($Value) { ConvertTo-Json -InputObject $Value -Depth 8 | ConvertFrom-Json }
function Fingerprint([string]$Path) {
    Get-PtDirectorySnapshot $Path | ConvertTo-Json -Depth 8 -Compress
}
function Remove-Fixture([string]$Path) {
    # Cleanup is confined to exact roots allocated above; delete links themselves, never their targets.
    foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries($Path)) {
        $attributes = [IO.File]::GetAttributes($entry)
        if ($attributes -band [IO.FileAttributes]::Directory) {
            if ($attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($entry, $false) }
            else { Remove-Fixture $entry }
        } else { [IO.File]::Delete($entry) }
    }
    [IO.Directory]::Delete($Path, $false)
}

try {
    Check 'Mixed original/changed/deleted/created files; binary, empty bytes, empty dirs and JSON' {
        $root = New-Fixture
        [void][IO.Directory]::CreateDirectory("$root\nested\empty")
        [void][IO.Directory]::CreateDirectory("$root\removed-empty")
        Write-Bytes "$root\binary.bin" @(0,255,13,10,239,187,191,128)
        Write-Bytes "$root\empty.bin" @()
        Write-Bytes "$root\removed.bin" @(4,5)
        Write-Bytes "$root\unchanged.bin" @(7)
        Write-Bytes "$root\nested\child.bin" @(8)
        $baseline = Roundtrip (Get-PtDirectorySnapshot $root)
        Require ($baseline.Files.Count -eq 5 -and $baseline.Directories.Count -eq 3) 'Exact file/directory inventory missing.'
        Require (($baseline.Files | Where-Object RelativePath -eq 'empty.bin').Base64 -ceq '') 'Empty bytes not captured.'
        Write-Bytes "$root\binary.bin" @(99)
        Write-Bytes "$root\empty.bin" @(100)
        [IO.File]::Delete("$root\removed.bin")
        Write-Bytes "$root\created.bin" @(6)
        [IO.Directory]::Delete("$root\removed-empty")
        [void][IO.Directory]::CreateDirectory("$root\created-empty")
        $post = Roundtrip (Get-PtDirectorySnapshot $root)
        $ownership = @{
            Snapshot = $baseline; ExpectedState = $post
            OwnedRelativePaths = @('binary.bin','empty.bin','removed.bin','created.bin')
            OwnedRelativeDirectories = @('removed-empty','created-empty')
        }
        $receipt = Restore-PtDirectorySnapshot @ownership
        $receipts.Add($receipt)
        Require ($receipt.WholeTreeMatchesBaseline -and $receipt.OwnedPathsMatchBaseline) 'Mixed restoration incomplete.'
        Require ($receipt.Changes.Count -eq 6) 'Unexpected number of owned changes.'
        Require ((Fingerprint $root) -ceq ($baseline | ConvertTo-Json -Depth 8 -Compress)) 'Original exact bytes/names not restored.'
        $stamp = [datetime]::new(2020, 1, 2, 3, 4, 5, [DateTimeKind]::Utc)
        [IO.File]::SetLastWriteTimeUtc("$root\binary.bin", $stamp)
        $again = Restore-PtDirectorySnapshot @ownership
        $receipts.Add($again)
        Require ($again.Changes.Count -eq 0 -and $again.WholeTreeMatchesBaseline) 'Repeated restore is not a no-op.'
        Require ([IO.File]::GetLastWriteTimeUtc("$root\binary.bin") -eq $stamp) 'Repeated restore rewrote unchanged bytes.'
    }
    Check 'No mutation and no ownership is a read-only complete comparison' {
        $root = New-Fixture
        Write-Bytes "$root\file"
        [void][IO.Directory]::CreateDirectory("$root\empty")
        $baseline = Roundtrip (Get-PtDirectorySnapshot $root)
        $stamp = [IO.File]::GetLastWriteTimeUtc("$root\file")
        $receipt = Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $baseline -OwnedRelativePaths @()
        $receipts.Add($receipt)
        Require ($receipt.WholeTreeMatchesBaseline -and $receipt.Changes.Count -eq 0) 'Untouched snapshot produced changes.'
        Require ([IO.File]::GetLastWriteTimeUtc("$root\file") -eq $stamp) 'No-mutation restore rewrote bytes.'
        $metadata = (Get-Command Restore-PtDirectorySnapshot).Parameters['OwnedRelativePaths']
        Require (@($metadata.Attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count -eq 1) 'Ownership is not mandatory.'
    }
    Check 'Originally absent root restored only with explicit root and directory ownership' {
        $root = New-Fixture -Absent
        $baseline = Roundtrip (Get-PtDirectorySnapshot $root -MaxFiles 0 -MaxBytes 0 -MaxDirectories 0)
        Require (-not $baseline.Exists -and $baseline.Files.Count -eq 0) 'Root absence lost.'
        [void][IO.Directory]::CreateDirectory("$root\child\empty")
        Write-Bytes "$root\child\created" @()
        $post = Roundtrip (Get-PtDirectorySnapshot $root)
        $ownership = @{
            Snapshot = $baseline; ExpectedState = $post; OwnRoot = $true
            OwnedRelativePaths = @('child\created'); OwnedRelativeDirectories = @('child','child\empty')
        }
        $receipt = Restore-PtDirectorySnapshot @ownership
        $receipts.Add($receipt)
        Require ($receipt.WholeTreeMatchesBaseline -and -not [IO.Directory]::Exists($root)) 'Test-created root remained.'
        Require ((Restore-PtDirectorySnapshot @ownership).Changes.Count -eq 0) 'Absent-root repeated restore mutated.'
        $root2 = New-Fixture -Absent
        $before2 = Get-PtDirectorySnapshot $root2
        [void][IO.Directory]::CreateDirectory($root2)
        $receipt2 = Restore-PtDirectorySnapshot -Snapshot $before2 -ExpectedState (Get-PtDirectorySnapshot $root2) -OwnedRelativePaths @()
        $receipts.Add($receipt2)
        Require (-not $receipt2.WholeTreeMatchesBaseline -and [IO.Directory]::Exists($root2)) 'Root ownership was inferred.'
        Require ($receipt2.UnownedDifferences.RelativePath -contains '.') 'Unowned root not surfaced.'
    }
    Check 'Declared additions removed; undeclared expected and concurrent additions preserved' {
        $root = New-Fixture
        Write-Bytes "$root\owned"
        $baseline = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\owned" @(9)
        Write-Bytes "$root\declared"
        Write-Bytes "$root\undeclared"
        [void][IO.Directory]::CreateDirectory("$root\owned-dir")
        $post = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\concurrent"
        Write-Bytes "$root\owned-dir\user-file"
        [void][IO.Directory]::CreateDirectory("$root\user-empty")
        $receipt = Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post `
            -OwnedRelativePaths @('owned','declared') -OwnedRelativeDirectories @('owned-dir')
        $receipts.Add($receipt)
        Require (-not [IO.File]::Exists("$root\declared")) 'Declared addition remained.'
        Require ([IO.File]::Exists("$root\undeclared") -and [IO.File]::Exists("$root\concurrent") -and [IO.File]::Exists("$root\owned-dir\user-file")) 'Unowned files were deleted.'
        Require ([IO.Directory]::Exists("$root\user-empty")) 'Concurrent empty directory was deleted.'
        Require ($receipt.Status -eq 'Partial' -and -not $receipt.WholeTreeMatchesBaseline -and -not $receipt.OwnedPathsMatchBaseline) 'Partial restoration falsely reported complete.'
        Require ($receipt.UnownedDifferences.Count -eq 4 -and $receipt.RetainedDirectories.RelativePath -contains 'owned-dir') 'Preserved differences missing from receipt.'
    }
    Check 'Unowned edits and deletions preserved; no diff-derived authorization' {
        $root = New-Fixture
        Write-Bytes "$root\edited"
        Write-Bytes "$root\deleted"
        $baseline = Get-PtDirectorySnapshot $root
        $post = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\edited" @(42)
        [IO.File]::Delete("$root\deleted")
        $fingerprint = Fingerprint $root
        $receipt = Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @()
        $receipts.Add($receipt)
        Require ($receipt.Changes.Count -eq 0 -and $receipt.UnownedDifferences.Count -eq 2 -and $receipt.OwnedPathsMatchBaseline) 'Unowned differences not accurately reported.'
        Require ((Fingerprint $root) -ceq $fingerprint) 'Unowned changes reverted.'
    }
    Check 'Whole-plan content conflict performs zero writes, even to an earlier safe path' {
        $root = New-Fixture
        Write-Bytes "$root\a-safe" @(1)
        Write-Bytes "$root\z-conflict" @(2)
        $baseline = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\a-safe" @(3)
        Write-Bytes "$root\z-conflict" @(4)
        $post = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\z-conflict" @(5)
        $fingerprint = Fingerprint $root
        $stamp = [IO.File]::GetLastWriteTimeUtc("$root\a-safe")
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('a-safe','z-conflict') } 'conflict; no writes'
        Require ((Fingerprint $root) -ceq $fingerprint) 'Conflict partially restored another path.'
        Require ([IO.File]::GetLastWriteTimeUtc("$root\a-safe") -eq $stamp) 'Safe path rewritten before conflict.'
        Require ($receipts[-1].Changes.Count -eq 0 -and $receipts[-1].Conflicts.Count -eq 1) 'Conflict receipt missing.'
    }
    Check 'Baseline state already restored on one path is accepted alongside expected-post paths' {
        $root = New-Fixture
        Write-Bytes "$root\a" @(1)
        Write-Bytes "$root\b" @(2)
        $baseline = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\a" @(3)
        Write-Bytes "$root\b" @(4)
        $post = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\a" @(1)
        $receipt = Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('a','b')
        $receipts.Add($receipt)
        Require ($receipt.WholeTreeMatchesBaseline -and $receipt.Changes.Count -eq 1) 'Partial retry failed to skip matching baseline.'
    }
    Check 'File/directory current collisions and captured type replacements reject without writes' {
        $root = New-Fixture
        Write-Bytes "$root\a-safe"
        Write-Bytes "$root\collision"
        $baseline = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\a-safe" @(9)
        $post = Get-PtDirectorySnapshot $root
        [IO.File]::Delete("$root\collision")
        [void][IO.Directory]::CreateDirectory("$root\collision")
        $fingerprint = Fingerprint $root
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('a-safe','collision') } 'conflict; no writes'
        Require ((Fingerprint $root) -ceq $fingerprint) 'Type conflict caused writes.'
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState (Get-PtDirectorySnapshot $root) -OwnedRelativePaths @() } 'replacement.*unsupported'
        $root2 = New-Fixture -Absent
        $before2 = Get-PtDirectorySnapshot $root2
        Write-Bytes $root2
        Reject { Restore-PtDirectorySnapshot -Snapshot $before2 -ExpectedState $before2 -OwnedRelativePaths @() -OwnRoot } 'root.*type collision'
        [IO.File]::Delete($root2)
        [IO.Directory]::Delete("$root\collision")
        [void][IO.Directory]::CreateDirectory("$root\collision")
        $dirBaseline = Get-PtDirectorySnapshot $root
        [IO.Directory]::Delete("$root\collision")
        Write-Bytes "$root\collision"
        Reject { Restore-PtDirectorySnapshot -Snapshot $dirBaseline -ExpectedState $dirBaseline -OwnedRelativePaths @('a-safe') -OwnedRelativeDirectories @('collision') } 'conflict; no writes'
    }
    Check 'Missing directory/root recreation requires explicit ownership of each ancestor' {
        $root = New-Fixture
        [void][IO.Directory]::CreateDirectory("$root\child")
        Write-Bytes "$root\child\file"
        $baseline = Get-PtDirectorySnapshot $root
        [IO.File]::Delete("$root\child\file")
        [IO.Directory]::Delete("$root\child")
        [IO.Directory]::Delete($root)
        $post = Get-PtDirectorySnapshot $root
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('child\file') } 'Required parent'
        Require (-not [IO.Directory]::Exists($root)) 'Parent conflict wrote root.'
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('child\file') -OwnedRelativeDirectories @('child') } 'Required parent'
        $receipt = Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('child\file') -OwnedRelativeDirectories @('child') -OwnRoot
        $receipts.Add($receipt)
        Require ($receipt.WholeTreeMatchesBaseline) 'Explicit ancestor restoration failed.'
    }
    Check 'Owned test-created root with concurrent contents remains and is reported partial' {
        $root = New-Fixture -Absent
        $baseline = Get-PtDirectorySnapshot $root
        [void][IO.Directory]::CreateDirectory($root)
        Write-Bytes "$root\owned"
        $post = Get-PtDirectorySnapshot $root
        [void][IO.Directory]::CreateDirectory("$root\concurrent-empty")
        $receipt = Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('owned') -OwnRoot
        $receipts.Add($receipt)
        Require (-not $receipt.WholeTreeMatchesBaseline -and $receipt.RetainedDirectories.RelativePath -contains '.') 'Nonempty root was removed or not reported.'
        Require ([IO.Directory]::Exists("$root\concurrent-empty")) 'Concurrent directory lost.'
    }
    Check 'Malformed hash/base64/schema/length/absence and root mismatches reject before writing' {
        $root = New-Fixture
        Write-Bytes "$root\file"
        $baseline = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\file" @(9)
        $post = Get-PtDirectorySnapshot $root
        $fingerprint = Fingerprint $root
        foreach ($mutation in @(
            { param($s) $s.Files[0].Sha256 = '0' * 64 },
            { param($s) $s.Files[0].Sha256 = 'bad' },
            { param($s) $s.Files[0].Base64 = '!!!!' },
            { param($s) $s.Files[0].Base64 = 'A QI' },
            { param($s) $s.Files[0].Length = 4 },
            { param($s) $s.Files[0].Length = -1 },
            { param($s) $s.SchemaVersion = 2 },
            { param($s) $s.Exists = 'true' },
            { param($s) $s.Exists = $false },
            { param($s) $s.Files = $null },
            { param($s) $s.PSObject.Properties.Remove('Directories') },
            { param($s) $s | Add-Member Extra 'not-schema' },
            { param($s) $s.Path += '\' }
        )) {
            $bad = Roundtrip $baseline
            & $mutation $bad
            Reject { Restore-PtDirectorySnapshot -Snapshot $bad -ExpectedState $post -OwnedRelativePaths @('file') } 'snapshot|hash|base64|Length'
            Require ((Fingerprint $root) -ceq $fingerprint) 'Malformed baseline caused writes.'
        }
        $badPost = Roundtrip $post
        $badPost.Files[0].Sha256 = '0' * 64
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $badPost -OwnedRelativePaths @('file') } 'hash'
        $other = Get-PtDirectorySnapshot (New-Fixture)
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $other -OwnedRelativePaths @('file') } 'same root'
    }
    Check 'Traversal, invalid Windows names, case duplicates and parent collisions reject' {
        $root = New-Fixture
        Write-Bytes "$root\file"
        $baseline = Get-PtDirectorySnapshot $root
        foreach ($name in @('..\outside','a\..\file','.\file','\absolute','C:\outside','a/file','file:ads','*','a?b',
            'a||b','NUL','COM1.txt','LPT9','CONOUT$','trail.','trail ','a\\b','.git','nested\.git\config','','a"' + [char]1)) {
            $bad = Roundtrip $baseline
            $bad.Files[0].RelativePath = $name
            Reject { Restore-PtDirectorySnapshot -Snapshot $bad -ExpectedState $baseline -OwnedRelativePaths @() } 'relative path|Windows name'
            Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $baseline -OwnedRelativePaths @($name) } 'relative path|Windows name|empty string'
        }
        $duplicate = Roundtrip $baseline
        $extra = Roundtrip $duplicate.Files[0]
        $extra.RelativePath = 'FILE'
        $duplicate.Files += $extra
        Reject { Restore-PtDirectorySnapshot -Snapshot $duplicate -ExpectedState $baseline -OwnedRelativePaths @() } 'duplicate'
        $collision = Roundtrip $baseline
        $collision.Directories = @('file')
        Reject { Restore-PtDirectorySnapshot -Snapshot $collision -ExpectedState $baseline -OwnedRelativePaths @() } 'collision'
        $missingParent = Roundtrip $baseline
        $missingParent.Files[0].RelativePath = 'missing\file'
        Reject { Restore-PtDirectorySnapshot -Snapshot $missingParent -ExpectedState $baseline -OwnedRelativePaths @() } 'Missing directory parent'
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $baseline -OwnedRelativePaths @('file','FILE') } 'duplicate'
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $baseline -OwnedRelativePaths @('FILE') } 'Ownership type/name'
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $baseline -OwnedRelativePaths @() -OwnedRelativeDirectories @('file') } 'Ownership type/name'
        $renamed = Roundtrip $baseline
        $renamed.Files[0].RelativePath = 'FILE'
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $renamed -OwnedRelativePaths @() } 'case-only rename'
        $duplicateDirectories = Roundtrip $baseline
        $duplicateDirectories.Directories = @('empty','EMPTY')
        Reject { Restore-PtDirectorySnapshot -Snapshot $duplicateDirectories -ExpectedState $baseline -OwnedRelativePaths @() } 'duplicate'
        $parentCase = Roundtrip $baseline
        $parentCase.Directories = @('child')
        $parentCase.Files[0].RelativePath = 'CHILD\file'
        Reject { Restore-PtDirectorySnapshot -Snapshot $parentCase -ExpectedState $baseline -OwnedRelativePaths @() } 'parent name casing'
        [IO.File]::Move("$root\file", "$root\intermediate")
        [IO.File]::Move("$root\intermediate", "$root\FILE")
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $baseline -OwnedRelativePaths @('file') } 'conflict; no writes'
        Require ((Get-PtDirectorySnapshot $root).Files[0].RelativePath -ceq 'FILE') 'Current name conflict was overwritten.'
    }
    Check 'Bounds are enforced for capture and both restore snapshots before mutation' {
        $root = New-Fixture
        Write-Bytes "$root\a" @(1,2,3)
        Write-Bytes "$root\b" @(4,5)
        [void][IO.Directory]::CreateDirectory("$root\empty")
        $baseline = Get-PtDirectorySnapshot $root -MaxFiles 2 -MaxBytes 5 -MaxDirectories 1
        Reject { Get-PtDirectorySnapshot $root -MaxFiles 1 } 'MaxFiles'
        Reject { Get-PtDirectorySnapshot $root -MaxBytes 4 } 'MaxBytes'
        Reject { Get-PtDirectorySnapshot $root -MaxDirectories 0 } 'MaxDirectories'
        Reject { Get-PtDirectorySnapshot $root -MaxBytes -1 } 'range'
        Write-Bytes "$root\a" @(9)
        $post = Get-PtDirectorySnapshot $root
        $fingerprint = Fingerprint $root
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('a') -MaxBytes 4 } 'MaxBytes'
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('a') -MaxFiles 1 } 'MaxFiles'
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('a') -MaxDirectories 0 } 'MaxDirectories'
        Write-Bytes "$root\concurrent" @(8,8,8)
        Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('a') -MaxBytes 5 } 'MaxBytes'
        [IO.File]::Delete("$root\concurrent")
        Require ((Fingerprint $root) -ceq $fingerprint) 'Bounds failure changed files.'
        $empty = New-Fixture
        Write-Bytes "$empty\empty" @()
        Require ((Get-PtDirectorySnapshot $empty -MaxBytes 0).Files[0].Length -eq 0) 'Zero-byte bound rejected empty bytes.'
        $small = Get-PtDirectorySnapshot $empty
        Write-Bytes "$empty\second" @(1)
        $large = Get-PtDirectorySnapshot $empty
        Reject { Restore-PtDirectorySnapshot -Snapshot $small -ExpectedState $large -OwnedRelativePaths @('second') -MaxFiles 1 } 'MaxFiles'
        Reject { Restore-PtDirectorySnapshot -Snapshot $small -ExpectedState $large -OwnedRelativePaths @('second') -MaxBytes 0 } 'MaxBytes'
        Require ([IO.File]::Exists("$empty\second")) 'Oversized expected state caused writes.'
    }
    Check 'Broad/protected/nonlocal roots rejected before tree enumeration' {
        foreach ($path in @([IO.Path]::GetPathRoot($Workspace), $HOME, $env:TEMP,
            [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..\..')), 'C:\Users', '\\server\share\fixture',
            '\\?\C:\fixture', '.\relative', 'C:/fixture/test', 'C:\fixture\..\test')) {
            Reject { Get-PtDirectorySnapshot $path } 'Refusing|absolute local|Windows name'
        }
        $repository = New-Fixture
        [void][IO.Directory]::CreateDirectory("$repository\.git")
        Reject { Get-PtDirectorySnapshot $repository } 'repository root'
        $nestedRepository = New-Fixture
        [void][IO.Directory]::CreateDirectory("$nestedRepository\nested\.git")
        Reject { Get-PtDirectorySnapshot $nestedRepository } 'Repository marker'
        $missing = New-Fixture -Absent
        Reject { Get-PtDirectorySnapshot "$missing\child" } 'existing parent'
    }
    Check 'Junction/root/ancestor/dangling reparse rejection never follows targets or writes' {
        $root = New-Fixture
        $target = New-Fixture
        Write-Bytes "$root\a-safe"
        Write-Bytes "$target\sentinel" @(42)
        $baseline = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\a-safe" @(9)
        $post = Get-PtDirectorySnapshot $root
        $targetFingerprint = Fingerprint $target
        New-Item -ItemType Junction -Path "$root\link" -Target $target -ErrorAction Stop | Out-Null
        try {
            Reject { Get-PtDirectorySnapshot $root } 'Reparse/link'
            Reject { Get-PtDirectorySnapshot "$root\link" } 'Reparse/link'
            Reject { Get-PtDirectorySnapshot "$root\link\child" } 'Reparse/link'
            Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('a-safe') } 'Reparse/link'
            Require ([IO.File]::ReadAllBytes("$root\a-safe")[0] -eq 9) 'Reparse conflict wrote safe file.'
            Require ((Fingerprint $target) -ceq $targetFingerprint) 'Junction target mutated.'
        } finally { [IO.Directory]::Delete("$root\link", $false) }
        $dangling = New-Fixture
        New-Item -ItemType Junction -Path "$root\dangling" -Target $dangling -ErrorAction Stop | Out-Null
        [IO.Directory]::Delete($dangling)
        try { Reject { Get-PtDirectorySnapshot $root } 'Reparse/link' }
        finally { [IO.Directory]::Delete("$root\dangling", $false) }
    }
    Check 'Hardlinks reject on capture and restore, including unowned concurrent aliases' {
        $root = New-Fixture
        $target = New-Fixture
        Write-Bytes "$root\a-safe"
        Write-Bytes "$target\sentinel" @(42)
        $baseline = Get-PtDirectorySnapshot $root
        Write-Bytes "$root\a-safe" @(9)
        $post = Get-PtDirectorySnapshot $root
        New-Item -ItemType HardLink -Path "$root\alias" -Target "$target\sentinel" -ErrorAction Stop | Out-Null
        try {
            Reject { Get-PtDirectorySnapshot $root } 'hardlink'
            Reject { Restore-PtDirectorySnapshot -Snapshot $baseline -ExpectedState $post -OwnedRelativePaths @('a-safe') } 'hardlink'
            Require ([IO.File]::ReadAllBytes("$root\a-safe")[0] -eq 9) 'Hardlink rejection occurred after writes.'
            Require ([IO.File]::ReadAllBytes("$target\sentinel")[0] -eq 42) 'Hardlink target mutated.'
        } finally { [IO.File]::Delete("$root\alias") }
    }
    Check 'Cloud/offline/recall attribute guard rejects conservatively without hydration' {
        foreach ($mask in @(0x400, 0x1000, 0x40000, 0x400000)) {
            Reject { [PtDirectorySnapshotNative]::CheckAttributes([Enum]::ToObject([IO.FileAttributes], $mask), 'synthetic-attribute-probe') } 'Cloud Files'
        }
        [PtDirectorySnapshotNative]::CheckAttributes([IO.FileAttributes]::Normal, 'synthetic-attribute-probe')
    }
} finally {
    foreach ($fixture in $fixtures) {
        if ([IO.Directory]::Exists($fixture)) { Remove-Fixture $fixture }
        elseif ([IO.File]::Exists($fixture)) { [IO.File]::Delete($fixture) }
    }
    [pscustomobject]@{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Sources = $sourceHashes; Results = @($results); Receipts = @($receipts)
        FixtureRoots = @($fixtures)
        AllFixtureRootsRemoved = (@($fixtures | Where-Object { [IO.Directory]::Exists($_) -or [IO.File]::Exists($_) }).Count -eq 0)
        Scope = 'Offline unique fixtures only; no desktop, applications, user settings, registry, archives or network.'
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$Workspace\evidence.json"
}
"PASS: $($results.Count) offline groups. Evidence: $Workspace\evidence.json"
