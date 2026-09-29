# Read live settings without denying the product's writer. No retries, defaults or mutations.

function Read-PtSharedFileBytes {
    <#.SYNOPSIS
    Read through a handle that permits concurrent read/write/delete. This is not an atomic snapshot.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $buffer = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($buffer)
            return ,$buffer.ToArray()
        } finally { $buffer.Dispose() }
    } finally { $stream.Dispose() }
}

function Read-PtSharedFileText {
    <#.SYNOPSIS
    Read UTF-8/BOM-identified text with live-writer sharing; malformed encoding remains an error.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $bytes = Read-PtSharedFileBytes -Path $Path
    $memory = [IO.MemoryStream]::new($bytes, $false)
    try {
        $reader = [IO.StreamReader]::new($memory, [Text.UTF8Encoding]::new($false, $true), $true)
        try { $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $memory.Dispose() }
}
