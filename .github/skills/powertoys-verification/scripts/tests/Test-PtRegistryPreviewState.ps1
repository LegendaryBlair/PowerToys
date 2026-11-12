# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.
#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-registry-preview-state-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-registry-preview-state.ps1"
if(Test-Path $Workspace){throw 'Use a new test workspace.'}
[IO.Directory]::CreateDirectory("$Workspace\module")|Out-Null
[IO.Directory]::CreateDirectory("$Workspace\private")|Out-Null
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
$module="$Workspace\module"
[IO.File]::WriteAllText("$module\settings.json",'{"properties":{"default_reg_app":false}}')
$receipt=New-PtRegistryPreviewFileState -ModuleDirectory $module -PrivateDirectory "$Workspace\private"
[IO.File]::WriteAllText("$module\app-placement.json",'{"owned":1}')
Set-PtRegistryPreviewExpectedFiles -ReceiptPath $receipt -ExpectedState (
    Get-PtFileSetSnapshot $module @('settings.json','app-placement.json'))
$hostExe=(Get-Command pwsh).Source
$helper=(Resolve-Path "$PSScriptRoot\..\pt-registry-preview-state.ps1").Path
& $hostExe -NoProfile -Command ". '$helper'; Restore-PtRegistryPreviewFiles -ReceiptPath '$receipt' | ConvertTo-Json -Compress" |
    Set-Content "$Workspace\fresh-process-result.json"
if($LASTEXITCODE -ne 0){throw 'Fresh-process restore failed.'}
Require (-not (Test-Path "$module\app-placement.json")) 'Original absence was not restored after controller exit.'

[IO.File]::WriteAllText("$module\app-placement.json",'original-placement')
$receipt=New-PtRegistryPreviewFileState -ModuleDirectory $module -PrivateDirectory "$Workspace\private"
$originalHash=(Read-PtRegistryPreviewFileState $receipt).Original.Sha256
[IO.File]::WriteAllText("$module\app-placement.json",'owned-placement')
Set-PtRegistryPreviewExpectedFiles $receipt (Get-PtFileSetSnapshot $module @('settings.json','app-placement.json'))
Require ((Read-PtRegistryPreviewFileState $receipt).Original.Sha256 -ceq $originalHash) 'Post-state replaced original identity.'
[IO.File]::WriteAllText("$module\app-placement.json",'foreign-placement')
Reject {Restore-PtRegistryPreviewFiles $receipt} 'conflict; no writes'
Require ([IO.File]::ReadAllText("$module\app-placement.json") -ceq 'foreign-placement') 'Conflict was overwritten.'
[IO.File]::WriteAllText("$module\app-placement.json",'owned-placement')
[IO.File]::WriteAllText("$module\settings.json",'foreign-settings')
$restored=Restore-PtRegistryPreviewFiles $receipt
Require ($restored.Status -eq 'Partial' -and $restored.OwnedFilesMatchBaseline) 'Unrelated settings difference was hidden.'
Require ([IO.File]::ReadAllText("$module\app-placement.json") -ceq 'original-placement') 'Original placement bytes lost.'
Require ([IO.File]::ReadAllText("$module\settings.json") -ceq 'foreign-settings') 'Unowned settings overwritten.'
$state=Read-PtRegistryPreviewFileState $receipt
$original=Join-Path "$Workspace\private" $state.Original.Name
[IO.File]::AppendAllText($original,'tamper')
Reject {Restore-PtRegistryPreviewFiles $receipt} 'hash mismatch'
@{FreshProcessAbsence='PASS';OriginalRetained='PASS';ConflictNoWrites='PASS';UnownedSettingsPreserved='PASS';TamperRejected='PASS'} |
    ConvertTo-Json | Set-Content "$Workspace\results.json"
"PASS: Registry Preview private file recovery, original absence, conflicts and tamper guards. $Workspace"
