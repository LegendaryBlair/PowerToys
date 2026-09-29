#requires -Version 7.2
# Clipboard-only port of the Color Picker primitive; no alternate recorder/identity/lifecycle.
. "$PSScriptRoot\pt-session-safety.ps1"

function Initialize-PtClipboardGuard {
    if (-not ('PtClipboard.ClipboardGuard' -as [type])) {
        Add-Type -Path "$PSScriptRoot\pt-clipboard-guard.cs" -ErrorAction Stop
    }
}

function New-PtClipboardGuard {
    <#.SYNOPSIS
    Snapshot supported formats in memory, using a window owned by this STA process.
    #>
    param([Parameter(Mandatory)][long]$OwnerHwnd)
    $ErrorActionPreference = 'Stop'
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { throw 'Clipboard guards require pwsh -STA.' }
    Initialize-PtClipboardGuard
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $sequence = [PtClipboard.ClipboardGuard]::GetClipboardSequenceNumber()
    $bitmapHandle = [IntPtr]::Zero
    $data = [Windows.Forms.Clipboard]::GetDataObject()
    try {
        if ($data -and $data.GetDataPresent('PNG', $false)) {
            $png = $data.GetData('PNG', $false)
            if ($png -isnot [IO.MemoryStream]) { throw 'PNG clipboard data is not a supported byte stream.' }
            $copy = [IO.MemoryStream]::new($png.ToArray())
            try {
                $bitmap = [Drawing.Bitmap]::new($copy)
                try { $bitmapHandle = $bitmap.GetHbitmap() }
                finally { $bitmap.Dispose() }
            } finally { $copy.Dispose() }
        }
        $guard=[PtClipboard.ClipboardGuard]::new($OwnerHwnd, $bitmapHandle, $sequence)
        if(Get-PtActiveResourceSession){
            try{
                Add-PtClipboardObligation -Guard $guard -OwnerProcessId $PID
                if($guard.OriginalWriterProcessId -gt 0){Protect-PtClipboardWriter $guard $guard.OriginalWriterProcessId}
                $guard.RequireRestorationBeforeDispose=$true
            }catch{$guard.Dispose();throw}
        }
        $guard
    } finally { [PtClipboard.ClipboardGuard]::ReleaseBitmap($bitmapHandle) }
}

function Register-PtClipboardWrite {
    <#.SYNOPSIS
    Acknowledge a just-observed copy using the actual writer PID/start time and prior sequence.
    #>
    param([Parameter(Mandatory)]$Guard, [Parameter(Mandatory)][uint32]$BeforeSequence,
        [Parameter(Mandatory)][int]$WriterProcessId, [Parameter(Mandatory)][long]$WriterStartTicks)
    $process = Get-Process -Id $WriterProcessId -ErrorAction Stop
    if ($process.StartTime.ToUniversalTime().Ticks -ne $WriterStartTicks) { throw 'Clipboard writer identity changed.' }
    Protect-PtClipboardWriter -Guard $Guard -ProcessId $WriterProcessId
    $Guard.AcceptWrite($BeforeSequence, $WriterProcessId)
}

function Assert-PtClipboardRestored {
    <#.SYNOPSIS
    Refuse subsequent writer/owner shutdown while the caller still owes clipboard restoration.
    #>
    param([Parameter(Mandatory)]$Guard)
    if ($Guard.Restored -isnot [bool] -or -not $Guard.Restored) {
        throw 'Clipboard restoration is not complete; preserve the guard/owner/provider before shutdown.'
    }

    Assert-PtProcessRelease -ProcessId @()
}

function Invoke-PtClipboardWrite {
    <#.SYNOPSIS
    Execute once, seal the resulting sequence before lock acquisition, and confirm without replay.
    #>
    param([Parameter(Mandatory)]$Guard,[Parameter(Mandatory)][int]$WriterProcessId,
        [Parameter(Mandatory)][long]$WriterStartTicks,[Parameter(Mandatory)][scriptblock]$Action,
        [object[]]$ArgumentList=@())
    $ErrorActionPreference='Stop'
    Initialize-PtClipboardGuard
    $process=Get-Process -Id $WriterProcessId -ErrorAction Stop
    if($process.StartTime.ToUniversalTime().Ticks -ne $WriterStartTicks){throw 'Clipboard writer identity changed.'}
    Protect-PtClipboardWriter -Guard $Guard -ProcessId $WriterProcessId
    $Guard.BeginWrite($WriterProcessId,$WriterStartTicks)
    try{$output=@(& $Action @ArgumentList)}
    catch{
        $original=$_
        try{$Guard.FailWrite()}catch{$original.Exception.Data['ClipboardPendingFailure']=$_.Exception.Message}
        throw $original
    }
    $sequence=[PtClipboard.ClipboardGuard]::GetClipboardSequenceNumber()
    $Guard.SealWrite($sequence)
    $null=$Guard.ConfirmWrite()
    $output
}
