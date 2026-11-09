# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.
#requires -Version 7.2
. "$PSScriptRoot\pt-module-lifecycle.ps1"

function Get-PtAwakeNativeExecutionState {
    if(-not ('PtAwakePowerNative' -as [type])){
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PtAwakePowerNative {
    [DllImport("powrprof.dll")]
    public static extern uint CallNtPowerInformation(
        int level, IntPtr input, uint inputSize, out uint output, uint outputSize);
}
'@
    }
    [uint32]$flags=0
    $status=[PtAwakePowerNative]::CallNtPowerInformation(16,[IntPtr]::Zero,0,[ref]$flags,4)
    if($status -ne 0){throw "SystemExecutionState read failed: NTSTATUS=0x$($status.ToString('X8'))."}
    $flags
}

function Get-PtAwakePowerObservation {
    <#
    .SYNOPSIS
    Read system-wide execution requests, optionally bracketing the read with Awake identity checks.
    .DESCRIPTION
    Supply ProcessIdentity from Get-PtLifecycleProcessProbe for a resident instance.
    Omit it only for an explicitly established absent-process observation. This read does not
    attribute requests to a process, change power policy, prove physical sleep prevention or
    replace a controlled before/after comparison. Errors are not zero-request observations.
    #>
    [CmdletBinding()]
    param($ProcessIdentity)
    foreach($phase in 'Before','After'){
        if($ProcessIdentity){
            foreach($key in 'processId','processStartTicks','sessionId','path'){
                if($null -eq $ProcessIdentity.$key -or [string]::IsNullOrWhiteSpace([string]$ProcessIdentity.$key)){
                    throw "Incomplete Awake process identity: $key."
                }
            }
            $current=Get-PtLifecycleProcessProbe -ProcessId $ProcessIdentity.processId
            if(-not $current -or $current.processStartTicks -ne $ProcessIdentity.processStartTicks -or
                $current.sessionId -ne $ProcessIdentity.sessionId -or $current.path -ine $ProcessIdentity.path){
                throw "Awake process identity changed $phase the power observation."
            }
        }
        if($phase -eq 'Before'){$flags=Get-PtAwakeNativeExecutionState}
    }
    [pscustomobject]@{
        Scope='SystemWide'
        Flags=$flags
        SystemRequired=([uint32]$flags -band 1) -ne 0
        DisplayRequired=([uint32]$flags -band 2) -ne 0
        ProcessIdentity=$ProcessIdentity
        ObservedUtc=[DateTimeOffset]::UtcNow.ToString('O')
    }
}
