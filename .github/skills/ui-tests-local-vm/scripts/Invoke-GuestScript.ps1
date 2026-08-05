# Copyright (c) Microsoft Corporation
# The Microsoft Corporation licenses this file to you under the MIT license.
# See the LICENSE file in the project root for more information.

<#
.SYNOPSIS
Runs a scriptblock inside the dockur/windows UI-test guest over WinRM, handling the credential
import and PSSession lifecycle. Token-efficient replacement for the repeated
Import-Clixml / New-PSSession / Invoke-Command / Remove-PSSession boilerplate when inspecting or
mutating guest state (package registration, staged runtime files, registry, processes).

.PARAMETER ScriptBlock
The scriptblock to run in the guest. Its output is returned to the host.

.PARAMETER WinRmPort
Host loopback WinRM port mapped to the guest (scaffold default 15986 HTTPS).

.PARAMETER UseHttp
Use http:// with Negotiate authentication instead of the default HTTPS/Basic connection.

.EXAMPLE
./Invoke-GuestScript.ps1 -WinRmPort 15986 -CredentialPath "$env:LOCALAPPDATA\PowerToysUiTestVm-Win11\admin.credential.xml" -ScriptBlock {
    Get-AppxPackage *ImageResizerContextMenu* | Select-Object -Expand Name
}

.EXAMPLE
# Neutralize a sparse package to reproduce CI's unsigned/classic scenario.
./Invoke-GuestScript.ps1 -WinRmPort 15986 -CredentialPath $cred -ScriptBlock {
    Get-AppxPackage -AllUsers *ImageResizerContextMenu* | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers }
    Rename-Item C:\PowerToysUiTestRun\PowerToys\WinUI3Apps\ImageResizerContextMenuPackage.msix -NewName ImageResizerContextMenuPackage.msix.disabled
}
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][scriptblock]$ScriptBlock,
    [object[]]$ArgumentList = @(),
    [int]$WinRmPort = 15986,
    [switch]$UseHttp,
    [string]$CredentialPath = (Join-Path $env:LOCALAPPDATA 'PowerToysUiTestVm-Win11\admin.credential.xml')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $CredentialPath)) {
    throw "Credential file not found: $CredentialPath. Point -CredentialPath at the VM's admin.credential.xml."
}
$credential = Import-Clixml $CredentialPath

$scheme = if ($UseHttp) { 'http' } else { 'https' }
$authentication = if ($UseHttp) { 'Negotiate' } else { 'Basic' }
$sessionOption = if ($UseHttp) {
    New-PSSessionOption
}
else {
    New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
}
$session = New-PSSession `
    -ConnectionUri "${scheme}://127.0.0.1:$WinRmPort/wsman" `
    -Authentication $authentication `
    -Credential $credential `
    -SessionOption $sessionOption

try {
    Invoke-Command -Session $session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
}
finally {
    Remove-PSSession $session -ErrorAction SilentlyContinue
}
