param([Parameter(Mandatory)][string]$Workspace)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\..\pt-clipboard-session.ps1"
# Exercise the real public launcher, replacing only its child host with the native-free fixture.
$body=${function:New-PtClipboardSession}.ToString()
$boundary='"$PSScriptRoot\hosts\clipboard-keeper.ps1"'
if(-not $body.Contains($boundary)){throw 'Keeper launch boundary changed.'}
$body=$body.Replace($boundary,('"'+$PSScriptRoot+'\ClipboardKeeperStub.ps1"'))
Set-Item Function:\New-PtClipboardSession ([scriptblock]::Create($body))
$session=New-PtClipboardSession $Workspace
$session.BeginWrite($session.ProcessId,$session.ProcessStartTicks)
$session.SealWrite(101)
try{$session.ConfirmWrite();throw 'Expected injected confirmation failure'}catch{
    if($_.Exception.Message -notmatch 'OpenClipboard'){throw}
    [IO.File]::WriteAllText((Join-Path $Workspace 'controller-error.txt'),'Expected OpenClipboard confirmation failure; exiting controller with retained keeper.')
    exit 37
}
