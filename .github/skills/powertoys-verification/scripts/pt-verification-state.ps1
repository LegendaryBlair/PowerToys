#Requires -Version 7.4
# Guarded restoration primitives. See references/verification-harness.md.
if (-not ('PtVerification.ClipboardGuard' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'pt-verification-native.cs') -ErrorAction Stop
}

function Get-PtFileHashBytes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Get-PtFileBytes {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::Open($Path, 'Open', 'Read', [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $buffer = [IO.MemoryStream]::new()
        try { $stream.CopyTo($buffer); return ,$buffer.ToArray() }
        finally { $buffer.Dispose() }
    } finally { $stream.Dispose() }
}

function New-PtFileGuard {
    <#.SYNOPSIS
    Capture an existing file. Rollback requires an explicit expected-current hash and a stopped writer.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $ErrorActionPreference = 'Stop'
    $fullPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if ((Get-Item -LiteralPath $fullPath).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'File guards do not follow reparse points.'
    }
    $bytes = Get-PtFileBytes $fullPath
    $hash = Get-PtFileHashBytes $bytes
    if ((Get-PtFileHashBytes (Get-PtFileBytes $fullPath)) -cne $hash) { throw "File changed while taking snapshot: $fullPath" }
    [pscustomobject]@{ Path = $fullPath; Bytes = $bytes; Hash = $hash }
}

function Restore-PtFileGuard {
    <#.SYNOPSIS
    Compare under an exclusive handle before restoring bytes; never force past a conflict.
    #>
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][string]$ExpectedCurrentHash)
    $ErrorActionPreference = 'Stop'
    $stream = [IO.File]::Open($Guard.Path, 'Open', 'ReadWrite', [IO.FileShare]::None)
    try {
        $buffer = [IO.MemoryStream]::new()
        try { $stream.CopyTo($buffer); $actual = Get-PtFileHashBytes $buffer.ToArray() }
        finally { $buffer.Dispose() }
        if ($actual -cne $Guard.Hash -and $actual -cne $ExpectedCurrentHash) {
            throw "File restoration conflict: $($Guard.Path)"
        }
        if ((Get-PtFileHashBytes $Guard.Bytes) -cne $Guard.Hash) { throw 'Snapshot bytes were modified.' }
        if ($actual -cne $Guard.Hash) {
            $stream.Position = 0
            $stream.Write($Guard.Bytes, 0, $Guard.Bytes.Length)
            $stream.SetLength($Guard.Bytes.Length)
            $stream.Flush($true)
        }
        $stream.Position = 0
        $verify = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($verify)
            if ((Get-PtFileHashBytes $verify.ToArray()) -cne $Guard.Hash) { throw 'Restored file differs from snapshot.' }
        } finally { $verify.Dispose() }
        [pscustomobject]@{ Path = $Guard.Path; Hash = $Guard.Hash; Restored = $true }
    } finally { $stream.Dispose() }
}

function New-PtClipboardGuard {
    <#.SYNOPSIS
    Eagerly snapshot supported native formats in memory, using a window owned by this STA process.
    #>
    param([Parameter(Mandatory)][long]$OwnerHwnd)
    $ErrorActionPreference = 'Stop'
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Clipboard guards require pwsh -STA.' }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $sequence = [PtVerification.ClipboardGuard]::GetClipboardSequenceNumber()
    $bitmapHandle = [IntPtr]::Zero
    $data = [Windows.Forms.Clipboard]::GetDataObject()
    try {
        if ($data -and $data.GetDataPresent('PNG',$false)) {
            $png = $data.GetData('PNG',$false)
            if ($png -isnot [IO.MemoryStream]) { throw 'PNG clipboard data is not a supported byte stream.' }
            $copy = [IO.MemoryStream]::new($png.ToArray())
            try {
                $bitmap = [Drawing.Bitmap]::new($copy)
                try { $bitmapHandle = $bitmap.GetHbitmap() }
                finally { $bitmap.Dispose() }
            } finally { $copy.Dispose() }
        }
        [PtVerification.ClipboardGuard]::new($OwnerHwnd,$bitmapHandle,$sequence)
    } finally { [PtVerification.ClipboardGuard]::ReleaseBitmap($bitmapHandle) }
}

function Register-PtClipboardWrite {
    <#.SYNOPSIS
    Acknowledge one just-completed copy from an explicitly identified writer, not arbitrary current content.
    #>
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][uint32]$BeforeSequence,
        [Parameter(Mandatory)][int]$WriterProcessId, [Parameter(Mandatory)][long]$WriterStartTicks)
    $process = Get-Process -Id $WriterProcessId -ErrorAction Stop
    if ($process.StartTime.ToUniversalTime().Ticks -ne $WriterStartTicks) { throw 'Clipboard writer identity changed.' }
    $Guard.AcceptWrite($BeforeSequence, $WriterProcessId)
}

function Invoke-PtRestoredState {
    <#.SYNOPSIS
    Run a mutation with guaranteed cleanup; preserve original enabled state and aggregate action/cleanup errors.
    .DESCRIPTION
    ReadEnabled returns exactly one Boolean. SetEnabled receives the desired Boolean and must use the UI.
    Quiesce must wait for all relevant writers to stop. Restore and Verify are supplied scoped operations.
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$ReadEnabled,
        [Parameter(Mandatory)][scriptblock]$SetEnabled,
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][scriptblock]$Quiesce,
        [Parameter(Mandatory)][scriptblock]$Restore,
        [Parameter(Mandatory)][scriptblock]$Verify
    )
    $ErrorActionPreference = 'Stop'
    $original = & $ReadEnabled
    if ($original -isnot [bool]) { throw 'ReadEnabled must return exactly one Boolean.' }
    $errors = [Collections.Generic.List[Exception]]::new()
    $output = $null
    try { $output = & $Action }
    catch { $errors.Add($_.Exception) }
    finally {
        $restored = $false
        try {
            & $SetEnabled $false | Out-Null
            & $Quiesce | Out-Null
            & $Restore | Out-Null
            $restored = $true
        } catch { $errors.Add($_.Exception) }
        # Do not restart a writer over an unresolved file/clipboard conflict.
        if ($restored) {
            try {
                & $SetEnabled $original | Out-Null
                $actual = & $ReadEnabled
                if ($actual -isnot [bool] -or $actual -ne $original) { throw 'Original enablement was not restored.' }
                $verified = & $Verify
                if ($verified -isnot [bool] -or -not $verified) { throw 'Post-restore verification did not return true.' }
            } catch { $errors.Add($_.Exception) }
        }
    }
    if ($errors.Count) { throw [AggregateException]::new('Action and/or restoration failed; no successful cleanup receipt.', $errors.ToArray()) }
    [pscustomobject]@{ Output = $output; OriginalEnabled = $original; Restored = $true }
}
