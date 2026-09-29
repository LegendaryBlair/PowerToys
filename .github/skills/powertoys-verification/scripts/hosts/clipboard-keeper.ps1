#requires -Version 7.2
param([Parameter(Mandatory)][string]$Id,[Parameter(Mandatory)][string]$ReceiptPath)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-file-io.ps1"
. "$PSScriptRoot\..\pt-clipboard-session.ps1"
Add-Type -AssemblyName System.Windows.Forms
$owner=[Windows.Forms.Form]::new()
$null=$owner.Handle
try{
    Start-PtClipboardKeeperLoop -Id $Id -ReceiptPath $ReceiptPath -Capture {
        New-PtClipboardGuard -OwnerHwnd $owner.Handle.ToInt64()
    } -Pump {[Windows.Forms.Application]::DoEvents()}
}finally{$owner.Dispose()}
