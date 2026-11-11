# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.
#requires -Version 7.2
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-awake.ps1"
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){
    try {& $Action|Out-Null} catch {
        Require ($_.Exception.Message -match $Message) "Unexpected failure: $($_.Exception.Message)"
        return
    }
    throw "Expected rejection: $Message"
}
$identity=@{processId=101;processStartTicks=123456L;sessionId=2;path='C:\fixture\PowerToys.Awake.exe'}
$script:current=$identity
$script:reads=0
function Get-PtLifecycleProcessProbe {param($ProcessId) $script:current}
function Get-PtAwakeNativeExecutionState {$script:reads++; [uint32]3}
$value=Get-PtAwakePowerObservation -ProcessIdentity $identity
Require ($value.Scope -ceq 'SystemWide' -and $value.SystemRequired -and $value.DisplayRequired -and $script:reads -eq 1) 'Valid observation lost scope or identity/read contract.'
$script:current=@{processId=101;processStartTicks=654321L;sessionId=2;path=$identity.path}
Reject {Get-PtAwakePowerObservation -ProcessIdentity $identity} 'identity changed Before'
Require ($script:reads -eq 1) 'Stale identity reached native observation.'
$script:current=$identity
function Get-PtAwakeNativeExecutionState {$script:current=$null; [uint32]0}
Reject {Get-PtAwakePowerObservation -ProcessIdentity $identity} 'identity changed After'
$script:current=$identity
function Get-PtAwakeNativeExecutionState {throw 'native status failure'}
Reject {Get-PtAwakePowerObservation -ProcessIdentity $identity} 'native status failure'
Reject {Get-PtAwakePowerObservation -ProcessIdentity @{processId=101}} 'Incomplete Awake process identity'
'PASS: Awake power observation rejects stale identities and native errors without reporting false absence.'
