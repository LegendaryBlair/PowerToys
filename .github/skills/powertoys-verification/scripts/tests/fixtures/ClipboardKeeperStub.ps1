# Actual keeper loop and ClipboardGuard with every native clipboard call replaced.
param([Parameter(Mandatory)][string]$Id,[Parameter(Mandatory)][string]$ReceiptPath)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\Import-ClipboardNativeStub.ps1"
Import-PtClipboardNativeStub
. "$PSScriptRoot\..\..\pt-clipboard-session.ps1"
# Test-only proxy methods inject a post-write confirmation failure on the keeper's fake clipboard.
function Capture {
    $native=[PtClipboard.ClipboardGuard]::new(1)
    $proxy=[pscustomobject]@{Native=$native;RequireRestorationBeforeDispose=$false}
    foreach($name in 'Restored','ExpectedSequence','PendingWriteState','PendingSequence','FormatCount','BitmapFromPng','OriginalWriterProcessId'){
        $proxy|Add-Member ScriptProperty $name ([scriptblock]::Create("`$this.Native.$name"))
    }
    $proxy|Add-Member ScriptMethod BeginWrite {param($writer,$ticks)
        $this.Native.BeginWrite($writer,$ticks)
        [PtClipboardNativeStub]::Write(90,$writer)
    }
    $proxy|Add-Member ScriptMethod SealWrite {param($sequence)
        $this.Native.SealWrite($sequence);[PtClipboardNativeStub]::OpenFailures=1000
    }
    $proxy|Add-Member ScriptMethod ConfirmWrite {$this.Native.ConfirmWrite()}
    $proxy|Add-Member ScriptMethod Restore {
        [PtClipboardNativeStub]::OpenFailures=0;$this.Native.Restore()
        if([PtClipboardNativeStub]::FormatCount -ne 2 -or [PtClipboardNativeStub]::Bytes(13)[0] -ne 65){
            throw 'Keeper lost original synthetic bytes.'
        }
    }
    $proxy|Add-Member ScriptMethod Dispose {
        $this.Native.RequireRestorationBeforeDispose=$true
        $this.Native.Dispose()
    }
    $proxy
}
Start-PtClipboardKeeperLoop -Id $Id -ReceiptPath $ReceiptPath -Capture ${function:Capture}
