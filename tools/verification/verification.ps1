#requires -Version 7.0
# Copyright (c) Microsoft Corporation
# Licensed under the MIT license.
<#
.SYNOPSIS
Local, runtime-neutral verification work queue and human decisions.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('new','status','claim','submit','dispatch','decide','interrupt','recover')][string]$Operation,
    [Parameter(Mandatory)][string]$Root,
    [string]$WorkflowId, [string]$RequestFile, [string]$WorkerId, [string]$ResultFile,
    [string]$Decision, [string]$Actor, [string]$Reason, [string]$Evidence, [string]$Environment,
    [string]$Adapter, [int]$TimeoutSeconds = 0, [switch]$WorkerStopped
)
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Verification.psm1" -Force -DisableNameChecking
$parameters = @{ Root = $Root }
switch ($Operation) {
    new { New-VfWorkflow @parameters -RequestFile $RequestFile | ConvertTo-Json -Depth 60 }
    status { Get-VfStatus @parameters -WorkflowId $WorkflowId | ConvertTo-Json -Depth 60 }
    claim { Claim-VfTask @parameters -WorkflowId $WorkflowId -WorkerId $WorkerId }
    submit { Submit-VfTask @parameters -WorkflowId $WorkflowId -ResultFile $ResultFile | ConvertTo-Json -Depth 60 }
    dispatch { Invoke-VfAgent @parameters -WorkflowId $WorkflowId -WorkerId $WorkerId -Adapter $Adapter -TimeoutSeconds $TimeoutSeconds | ConvertTo-Json -Depth 60 }
    decide { Decide-VfWorkflow @parameters -WorkflowId $WorkflowId -Decision $Decision -Actor $Actor -Reason $Reason | ConvertTo-Json -Depth 60 }
    interrupt { Stop-VfTask @parameters -WorkflowId $WorkflowId -Actor $Actor -Reason $Reason -Evidence $Evidence -WorkerStopped:$WorkerStopped | ConvertTo-Json -Depth 60 }
    recover { Restore-VfEnvironment @parameters -Environment $Environment -Actor $Actor -Reason $Reason -Evidence $Evidence | ConvertTo-Json -Depth 60 }
}
