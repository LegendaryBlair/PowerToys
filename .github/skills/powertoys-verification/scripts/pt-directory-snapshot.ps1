#requires -Version 7.2
# Standalone, explicit-ownership rollback for small, quiescent local test directories.

if (-not ('PtDirectorySnapshotNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class PtDirectorySnapshotNative
{
    [StructLayout(LayoutKind.Sequential)]
    private struct FileInfo
    {
        public uint Attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string path, uint access, uint share,
        IntPtr security, uint creation, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfo info);

    public static void CheckAttributes(FileAttributes attributes, string path)
    {
        // Reparse points (including Cloud Files), offline data and recall-on-access are unsupported.
        if (((uint)attributes & (0x400u | 0x1000u | 0x40000u | 0x400000u)) != 0)
            throw new IOException("Reparse/link or Cloud Files placeholder is unsupported: " + path);
    }

    private static FileStream Open(string path, bool write, bool create)
    {
        var handle = CreateFileW(path, write ? 0xC0000000u : 0x80000000u, 1,
            IntPtr.Zero, create ? 1u : 3u, 0x00200000u, IntPtr.Zero); // OPEN_REPARSE_POINT
        try
        {
            if (handle.IsInvalid)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open snapshot file: " + path);
            if (!GetFileInformationByHandle(handle, out var info))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot inspect snapshot file: " + path);
            CheckAttributes((FileAttributes)info.Attributes, path);
            if ((info.Attributes & 0x10u) != 0 || info.Links != 1)
                throw new IOException("Directory or hardlink conflict at file: " + path);
            return new FileStream(handle, write ? FileAccess.ReadWrite : FileAccess.Read);
        }
        catch
        {
            handle.Dispose();
            throw;
        }
    }

    public static byte[] Read(string path, long maxBytes)
    {
        using (var stream = Open(path, false, false))
        {
            if (stream.Length > maxBytes || stream.Length > int.MaxValue)
                throw new IOException("MaxBytes exceeded while capturing: " + path);
            var bytes = new byte[(int)stream.Length];
            int offset = 0;
            while (offset < bytes.Length)
            {
                int read = stream.Read(bytes, offset, bytes.Length - offset);
                if (read == 0) throw new IOException("File changed while capturing: " + path);
                offset += read;
            }
            if (stream.ReadByte() != -1) throw new IOException("File changed while capturing: " + path);
            return bytes;
        }
    }

    public static void Write(string path, byte[] bytes, bool create)
    {
        using (var stream = Open(path, true, create))
        {
            stream.SetLength(0);
            stream.Write(bytes, 0, bytes.Length);
            stream.Flush();
        }
    }
}
'@
}

function Assert-PtDirectoryRelativePath {
    param($Path)
    if ($Path -isnot [string] -or -not $Path -or $Path.Length -gt 255) {
        throw 'Relative path must be a nonempty Windows path of at most 255 characters.'
    }
    foreach ($part in $Path.Split('\')) {
        if ($part -ieq '.git') { throw "Repository marker '.git' is not a supported relative path." }
        if (-not $part -or $part -match '[<>:"/|?*\x00-\x1f]' -or $part -match '[. ]$' -or
            $part -match '^(CON|PRN|AUX|NUL|CLOCK\$|CONIN\$|CONOUT\$|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])(\.|$)') {
            throw "Invalid Windows name or traversal in relative path: '$Path'."
        }
    }
}

function Resolve-PtDirectorySnapshotPath {
    param($Path)
    if (-not $IsWindows) { throw 'Directory snapshots require PowerShell 7 on Windows.' }
    if ($Path -isnot [string] -or $Path -notmatch '^[A-Za-z]:\\' -or $Path.Length -ge 260) {
        throw 'Specify an absolute local drive path shorter than 260 characters; UNC/device/provider paths are unsupported.'
    }
    $full = $Path.TrimEnd('\')
    if ($full.Length -le 3) { throw "Refusing a broad/root directory: $Path" }
    Assert-PtDirectoryRelativePath $full.Substring(3)
    if ($full -cne [IO.Path]::GetFullPath($full)) { throw "Noncanonical root path: $Path" }
    $repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
    $protected = @($HOME, $env:USERPROFILE, $env:TEMP, $env:TMP, $env:WINDIR,
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA, $repo)
    if ($full.Substring(3).Split('\').Count -lt 2) { throw "Refusing a broad/root directory: $full" }
    foreach ($item in $protected) {
        if (-not $item) { continue }
        $item = [IO.Path]::GetFullPath($item).TrimEnd('\')
        if ($item.Equals($full, [StringComparison]::OrdinalIgnoreCase) -or
            $item.StartsWith("$full\", [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing protected directory or its ancestor: $full"
        }
    }
    $full
}

function Get-PtDirectoryPathKind {
    param([string]$Path)
    # Inspect each component before accessing a descendant; never enumerate a reparse directory.
    $parts = $Path.Substring(3).Split('\')
    $cursor = $Path.Substring(0, 3)
    [PtDirectorySnapshotNative]::CheckAttributes([IO.File]::GetAttributes($cursor), $cursor)
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $cursor = [IO.Path]::Combine($cursor, $parts[$i])
        try { $attributes = [IO.File]::GetAttributes($cursor) }
        catch [IO.FileNotFoundException] { return 'Absent' }
        catch [IO.DirectoryNotFoundException] { return 'Absent' }
        [PtDirectorySnapshotNative]::CheckAttributes($attributes, $cursor)
        $directory = ($attributes -band [IO.FileAttributes]::Directory) -ne 0
        if (-not $directory -and $i -lt $parts.Count - 1) { throw "File occupies directory ancestor: $cursor" }
    }
    if ($directory) { 'Directory' } else { 'File' }
}

function Get-PtDirectorySnapshot {
    <#
    .SYNOPSIS
    Capture existence, exact relative names, file bytes/SHA256 and all directories in a small root.
    .DESCRIPTION
    Use an explicit local test root with an existing parent. Quiesce writers first. Reject links,
    Cloud Files placeholders and broad roots. Does not capture ACLs, streams or timestamps.
    .EXAMPLE
    $before = Get-PtDirectorySnapshot -Path 'D:\fixtures\unique-case' -MaxFiles 32 -MaxBytes 1MB
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(0, 2147483647)][int]$MaxFiles = 256,
        [ValidateRange(0, 2147483647)][long]$MaxBytes = 16MB,
        [ValidateRange(0, 2147483647)][int]$MaxDirectories = 256
    )
    $root = Resolve-PtDirectorySnapshotPath $Path
    $kind = Get-PtDirectoryPathKind $root
    if ($kind -eq 'File') { throw "Directory root has a file type collision: $root" }
    if ($kind -eq 'Directory' -and (Get-PtDirectoryPathKind "$root\.git") -ne 'Absent') {
        throw "Refusing repository root: $root"
    }
    if ((Get-PtDirectoryPathKind ([IO.Path]::GetDirectoryName($root))) -ne 'Directory') {
        throw "Snapshot root requires an existing parent directory: $root"
    }
    $files = [Collections.Generic.List[object]]::new()
    $directories = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pending = [Collections.Generic.Stack[string]]::new()
    [long]$total = 0
    if ($kind -eq 'Directory') { $pending.Push($root) }
    while ($pending.Count) {
        $directory = $pending.Pop()
        if ((Get-PtDirectoryPathKind $directory) -ne 'Directory') { throw "Directory changed during capture: $directory" }
        foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries($directory)) {
            $relative = $entry.Substring($root.Length + 1)
            Assert-PtDirectoryRelativePath $relative
            if ($entry.Length -ge 260) { throw "Snapshot path must be shorter than 260 characters: $entry" }
            if (-not $seen.Add($relative)) { throw "Case-duplicate snapshot path: $relative" }
            $entryKind = Get-PtDirectoryPathKind $entry
            if ($entryKind -eq 'Directory') {
                if ($directories.Count -ge $MaxDirectories) { throw "MaxDirectories ($MaxDirectories) exceeded at: $entry" }
                $directories.Add($relative)
                $pending.Push($entry)
            } elseif ($entryKind -eq 'File') {
                if ($files.Count -ge $MaxFiles) { throw "MaxFiles ($MaxFiles) exceeded at: $entry" }
                $bytes = [PtDirectorySnapshotNative]::Read($entry, $MaxBytes - $total)
                $total += $bytes.LongLength
                $files.Add([pscustomobject]@{
                    RelativePath = $relative; Length = $bytes.LongLength
                    Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
                    Base64 = [Convert]::ToBase64String($bytes)
                })
            } else { throw "Entry disappeared during capture: $entry" }
        }
    }
    [pscustomobject]@{
        SchemaVersion = 1; Path = $root; Exists = ($kind -eq 'Directory')
        Files = @($files | Sort-Object RelativePath -CaseSensitive)
        Directories = @($directories | Sort-Object -CaseSensitive)
    }
}

function Assert-PtDirectorySnapshotRecord {
    param($Value, [string[]]$Properties)
    if ($Value -isnot [pscustomobject] -or @($Value.PSObject.Properties).Count -ne $Properties.Count) {
        throw "Malformed snapshot record; expected properties: $($Properties -join ', ')."
    }
    foreach ($property in $Properties) {
        if ($Value.PSObject.Properties.Name -cnotcontains $property) { throw "Missing snapshot property: $property" }
    }
}

function ConvertTo-PtDirectorySnapshotMap {
    param($Snapshot, [int]$MaxFiles, [long]$MaxBytes, [int]$MaxDirectories)
    Assert-PtDirectorySnapshotRecord $Snapshot @('SchemaVersion','Path','Exists','Files','Directories')
    if ($Snapshot.SchemaVersion -isnot [int] -and $Snapshot.SchemaVersion -isnot [long]) { throw 'Invalid snapshot schema version.' }
    if ($Snapshot.SchemaVersion -ne 1 -or $Snapshot.Exists -isnot [bool] -or
        $Snapshot.Files -isnot [array] -or $Snapshot.Directories -isnot [array]) { throw 'Malformed snapshot schema, existence or arrays.' }
    $root = Resolve-PtDirectorySnapshotPath $Snapshot.Path
    if ($root -cne $Snapshot.Path) { throw 'Snapshot Path must be canonical without a trailing separator.' }
    if ($Snapshot.Files.Count -gt $MaxFiles -or $Snapshot.Directories.Count -gt $MaxDirectories) {
        throw 'Snapshot exceeds MaxFiles or MaxDirectories.'
    }
    if (-not $Snapshot.Exists -and ($Snapshot.Files.Count -or $Snapshot.Directories.Count)) { throw 'Absent snapshot root cannot contain entries.' }
    $map = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($Snapshot.Exists) { $map.Add('.', [pscustomobject]@{ RelativePath = '.'; Kind = 'Directory' }) }
    [long]$total = 0
    foreach ($directory in $Snapshot.Directories) {
        Assert-PtDirectoryRelativePath $directory
        if ($map.ContainsKey($directory)) { throw "Duplicate/case-duplicate snapshot path: $directory" }
        $map.Add($directory, [pscustomobject]@{ RelativePath = $directory; Kind = 'Directory' })
    }
    foreach ($file in $Snapshot.Files) {
        Assert-PtDirectorySnapshotRecord $file @('RelativePath','Length','Sha256','Base64')
        Assert-PtDirectoryRelativePath $file.RelativePath
        if ($map.ContainsKey($file.RelativePath)) { throw "Duplicate/case-duplicate or type collision in snapshot: $($file.RelativePath)" }
        if (($file.Length -isnot [int] -and $file.Length -isnot [long]) -or $file.Length -lt 0 -or
            $file.Length -gt $MaxBytes - $total) { throw "Invalid Length or MaxBytes exceeded: $($file.RelativePath)" }
        if ($file.Sha256 -isnot [string] -or $file.Sha256 -cnotmatch '^[A-Fa-f0-9]{64}$' -or
            $file.Base64 -isnot [string] -or $file.Base64.Length -ne 4 * [math]::Ceiling($file.Length / 3.0)) {
            throw "Invalid SHA256/base64/length: $($file.RelativePath)"
        }
        $bytes = [Convert]::FromBase64String($file.Base64)
        if ($bytes.LongLength -ne $file.Length -or [Convert]::ToBase64String($bytes) -cne $file.Base64 -or
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -ine $file.Sha256) {
            throw "Snapshot hash/base64/length mismatch: $($file.RelativePath)"
        }
        $total += $file.Length
        $map.Add($file.RelativePath, [pscustomobject]@{
            RelativePath = $file.RelativePath; Kind = 'File'; Base64 = $file.Base64
            Sha256 = $file.Sha256.ToUpperInvariant(); Length = $file.Length
        })
    }
    foreach ($entry in $map.Values) {
        if ($entry.RelativePath -eq '.') { continue }
        if ($root.Length + 1 + $entry.RelativePath.Length -ge 260) { throw "Snapshot path is too long: $($entry.RelativePath)" }
        $parent = [IO.Path]::GetDirectoryName($entry.RelativePath)
        if (-not $parent) { $parent = '.' }
        if (-not $map.ContainsKey($parent) -or $map[$parent].Kind -ne 'Directory') {
            throw "Missing directory parent or type collision in snapshot: $($entry.RelativePath)"
        }
        if ($parent -ne '.' -and $map[$parent].RelativePath -cne $parent) { throw "Inconsistent parent name casing: $($entry.RelativePath)" }
    }
    ,$map
}

function Test-PtDirectoryEntryEqual {
    param($Left, $Right)
    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    if ($Left.RelativePath -cne $Right.RelativePath -or $Left.Kind -ne $Right.Kind) { return $false }
    $Left.Kind -eq 'Directory' -or $Left.Base64 -ceq $Right.Base64
}

function Restore-PtDirectorySnapshot {
    <#
    .SYNOPSIS
    Restore explicitly owned paths only after checking the entire plan for concurrent conflicts.
    .DESCRIPTION
    ExpectedState is the caller-recorded post-mutation snapshot, not a fresh baseline to authorize
    arbitrary changes. OwnedRelativePaths is mandatory (use @() for no file ownership).
    Directory ownership is nonrecursive. OwnRoot explicitly owns root existence, including a
    test-created root when Snapshot.Exists is false. Only empty owned directories are removed.
    See references\directory-snapshots.md for receipts, rejected inputs and filesystem race limits.
    .EXAMPLE
    Restore-PtDirectorySnapshot -Snapshot $before -ExpectedState $after `
        -OwnedRelativePaths @('fixture.bin') -OwnedRelativeDirectories @('empty') -OwnRoot
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)]$ExpectedState,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$OwnedRelativePaths,
        [string[]]$OwnedRelativeDirectories = @(),
        [switch]$OwnRoot,
        [ValidateRange(0, 2147483647)][int]$MaxFiles = 256,
        [ValidateRange(0, 2147483647)][long]$MaxBytes = 16MB,
        [ValidateRange(0, 2147483647)][int]$MaxDirectories = 256
    )
    $before = ConvertTo-PtDirectorySnapshotMap $Snapshot $MaxFiles $MaxBytes $MaxDirectories
    $expected = ConvertTo-PtDirectorySnapshotMap $ExpectedState $MaxFiles $MaxBytes $MaxDirectories
    if ($Snapshot.Path -cne $ExpectedState.Path) { throw 'Snapshot and ExpectedState must have the exact same root Path.' }
    $root = $Snapshot.Path
    $owned = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($kind in 'File','Directory') {
        $paths = if ($kind -eq 'File') { $OwnedRelativePaths } else { $OwnedRelativeDirectories }
        foreach ($relative in $paths) {
            Assert-PtDirectoryRelativePath $relative
            if ($root.Length + 1 + $relative.Length -ge 260) { throw "Owned path is too long: $relative" }
            if ($owned.ContainsKey($relative)) { throw "Duplicate/case-duplicate ownership: $relative" }
            $owned.Add($relative, $kind)
            foreach ($map in @($before, $expected)) {
                if ($map.ContainsKey($relative) -and ($map[$relative].Kind -ne $kind -or $map[$relative].RelativePath -cne $relative)) {
                    throw "Ownership type/name collision: $relative"
                }
            }
        }
    }
    if ($OwnRoot) { $owned.Add('.', 'Directory') }
    foreach ($relative in $before.Keys) {
        if ($expected.ContainsKey($relative) -and ($before[$relative].Kind -ne $expected[$relative].Kind -or
            $before[$relative].RelativePath -cne $expected[$relative].RelativePath)) {
            throw "File/directory replacement or case-only rename is unsupported: $relative"
        }
    }
    $limits = @{ MaxFiles = $MaxFiles; MaxBytes = $MaxBytes; MaxDirectories = $MaxDirectories }
    $currentSnapshot = Get-PtDirectorySnapshot -Path $root @limits
    $current = ConvertTo-PtDirectorySnapshotMap $currentSnapshot $MaxFiles $MaxBytes $MaxDirectories
    $conflicts = [Collections.Generic.List[object]]::new()
    $plan = [Collections.Generic.List[object]]::new()
    $predicted = [Collections.Generic.Dictionary[string,object]]::new($current, [StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $owned.Keys) {
        $original = $before[$relative]
        $now = $current[$relative]
        if (Test-PtDirectoryEntryEqual $now $original) { continue }
        if (-not (Test-PtDirectoryEntryEqual $now $expected[$relative])) {
            $conflicts.Add([pscustomobject]@{ RelativePath = $relative; Reason = 'Current content/type/name is neither baseline nor ExpectedState.' })
            continue
        }
        $action = if ($null -eq $original) { "Remove$($owned[$relative])" }
            elseif ($owned[$relative] -eq 'Directory') { 'CreateDirectory' } else { 'WriteFile' }
        $plan.Add([pscustomobject]@{ RelativePath = $relative; Action = $action })
        if ($null -eq $original) { [void]$predicted.Remove($relative) } else { $predicted[$relative] = $original }
    }
    foreach ($change in $plan) {
        if ($change.Action -notin 'WriteFile','CreateDirectory' -or $change.RelativePath -eq '.') { continue }
        $parent = [IO.Path]::GetDirectoryName($change.RelativePath)
        if (-not $parent) { $parent = '.' }
        if (-not $predicted.ContainsKey($parent) -or $predicted[$parent].Kind -ne 'Directory') {
            $conflicts.Add([pscustomobject]@{ RelativePath = $change.RelativePath; Reason = "Required parent '$parent' is absent/not a directory; explicitly own its restoration." })
        }
    }
    if ($conflicts.Count) {
        $receipt = [pscustomobject]@{ Path = $root; Status = 'Conflict'; Changes = @(); Conflicts = @($conflicts); WholeTreeMatchesBaseline = $false }
        $error = [InvalidOperationException]::new("Directory restore conflict; no writes performed: $(($conflicts | ForEach-Object { "$($_.RelativePath): $($_.Reason)" }) -join '; ')")
        $error.Data['PtDirectorySnapshotReceipt'] = $receipt
        throw $error
    }
    $changes = [Collections.Generic.List[object]]::new()
    $retained = [Collections.Generic.List[object]]::new()
    $ordered = @($plan | Where-Object Action -eq 'CreateDirectory' | Sort-Object { $_.RelativePath.Length }) +
        @($plan | Where-Object Action -in 'WriteFile','RemoveFile' | Sort-Object RelativePath) +
        @($plan | Where-Object Action -eq 'RemoveDirectory' | Sort-Object { $_.RelativePath.Length } -Descending)
    foreach ($change in $ordered) {
        $relative = $change.RelativePath
        $path = if ($relative -eq '.') { $root } else { "$root\$relative" }
        $kind = Get-PtDirectoryPathKind $path
        $now = $current[$relative]
        $actual = if ($kind -eq 'Absent') { $null }
            elseif ($kind -eq 'Directory') { [pscustomobject]@{ RelativePath = $relative; Kind = 'Directory' } }
            else { [pscustomobject]@{ RelativePath = $relative; Kind = 'File'; Base64 = [Convert]::ToBase64String([PtDirectorySnapshotNative]::Read($path, $MaxBytes)) } }
        if (-not (Test-PtDirectoryEntryEqual $actual $now)) { throw "Directory changed after precheck; restoration may be partial: $path" }
        switch ($change.Action) {
            'CreateDirectory' {
                if ((Get-PtDirectoryPathKind ([IO.Path]::GetDirectoryName($path))) -ne 'Directory') { throw "Directory parent changed after precheck: $path" }
                [void][IO.Directory]::CreateDirectory($path)
            }
            'WriteFile' { [PtDirectorySnapshotNative]::Write($path, [Convert]::FromBase64String($before[$relative].Base64), ($null -eq $now)) }
            'RemoveFile' { [IO.File]::Delete($path) }
            'RemoveDirectory' {
                if (@([IO.Directory]::EnumerateFileSystemEntries($path)).Count) {
                    $retained.Add([pscustomobject]@{ RelativePath = $relative; Reason = 'Not empty; remaining contents are not deletion authorization.' })
                    continue
                }
                [IO.Directory]::Delete($path, $false)
            }
        }
        $changes.Add($change)
    }
    $actualSnapshot = Get-PtDirectorySnapshot -Path $root @limits
    $actualMap = ConvertTo-PtDirectorySnapshotMap $actualSnapshot $MaxFiles $MaxBytes $MaxDirectories
    $all = [Collections.Generic.HashSet[string]]::new($before.Keys, [StringComparer]::OrdinalIgnoreCase)
    $all.UnionWith($actualMap.Keys)
    $unowned = [Collections.Generic.List[object]]::new()
    $wholeMatches = $true
    $ownedMatches = $true
    foreach ($relative in ($all | Sort-Object -CaseSensitive)) {
        if (Test-PtDirectoryEntryEqual $before[$relative] $actualMap[$relative]) { continue }
        $wholeMatches = $false
        if ($owned.ContainsKey($relative)) {
            $ownedMatches = $false
            if ($retained.RelativePath -notcontains $relative) { throw "Post-restore comparison failed; restoration may be partial: $relative" }
        } else {
            $unowned.Add([pscustomobject]@{
                RelativePath = $relative
                BaselineKind = $(if ($before.ContainsKey($relative)) { $before[$relative].Kind } else { 'Absent' })
                ActualKind = $(if ($actualMap.ContainsKey($relative)) { $actualMap[$relative].Kind } else { 'Absent' })
            })
        }
    }
    [pscustomobject]@{
        Path = $root; Status = $(if ($wholeMatches) { 'Restored' } else { 'Partial' })
        WholeTreeMatchesBaseline = $wholeMatches; OwnedPathsMatchBaseline = $ownedMatches
        Changes = @($changes); UnownedDifferences = @($unowned); RetainedDirectories = @($retained)
    }
}
