# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.
#requires -Version 7.2
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\pt-always-on-top.ps1"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PtAotObservationFixture {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SetProp(IntPtr hwnd,string name,IntPtr data);
    [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW", SetLastError=true)]
    public static extern IntPtr SetStyle(IntPtr hwnd,int index,IntPtr value);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetLayeredWindowAttributes(IntPtr hwnd,uint key,byte alpha,uint flags);
}
'@
function Require([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
$window = [Windows.Forms.Form]::new()
try {
    $identity = Get-PtWindowIdentity -Hwnd $window.Handle.ToInt64()
    $plain = Get-PtAlwaysOnTopWindowState -Identity $identity
    Require (-not $plain.Pinned -and -not $plain.Topmost -and $plain.LayerStatus -eq 'NotLayered' -and $null -eq $plain.Alpha) 'An ordinary window was reported pinned/layered.'
    Require ([PtAotObservationFixture]::SetProp($window.Handle,'AlwaysOnTop_Pinned',[IntPtr]1)) 'Fixture property setup failed.'
    $marked = Get-PtAlwaysOnTopWindowState -Identity $identity
    Require ($marked.Pinned -and -not $marked.Topmost) 'Pin marker was conflated with topmost style.'
    [void][PtAotObservationFixture]::SetStyle($window.Handle,-20,[IntPtr]([PtDesktop]::ExtendedStyle($window.Handle) -bor 0x80000))
    $unavailable = Get-PtAlwaysOnTopWindowState -Identity $identity
    Require ($unavailable.LayerStatus -eq 'Unavailable' -and $null -eq $unavailable.Alpha) 'Unavailable layered attributes were substituted with an alpha value.'
    Require ([PtAotObservationFixture]::SetLayeredWindowAttributes($window.Handle,0,173,2)) 'Fixture alpha setup failed.'
    $layer = Get-PtAlwaysOnTopWindowState -Identity $identity
    Require ($layer.LayerStatus -eq 'Available' -and $layer.Alpha -eq 173 -and $layer.LayerFlags -eq 2) 'Actual layered alpha/flags were not retained.'
    $alphaReader=${function:Get-PtAlwaysOnTopWindowState}
    try {
        $script:alphaReads=0
        function Get-PtAlwaysOnTopWindowState {
            param($Identity)
            $script:alphaReads++
            $value=switch($script:alphaReads){1{$null} 2{173} default{140}}
            [pscustomobject]@{Identity=$Identity;Layered=$true;LayerStatus=$(if($null -eq $value){'Unavailable'}else{'Available'});LayerFlags=2;Alpha=$value}
        }
        $changed=Wait-PtAlwaysOnTopAlphaChange -Identity $identity -Before $layer -TimeoutSeconds 2
        Require ($script:alphaReads -eq 3 -and $changed.Alpha -eq 140) 'Unavailable or unchanged alpha satisfied the change wait.'
        $rejected=$false
        try { Wait-PtAlwaysOnTopAlphaChange -Identity $identity -Before $unavailable -TimeoutSeconds 0.1 | Out-Null } catch { $rejected=$true }
        Require $rejected 'An unavailable baseline was treated as opaque.'
        $mismatch=[pscustomobject]@{Identity=@{hwnd=0};LayerStatus='NotLayered';Layered=$false;Alpha=$null}
        $rejected=$false
        try { Wait-PtAlwaysOnTopAlphaChange -Identity $identity -Before $mismatch -TimeoutSeconds 0.1 | Out-Null } catch { $rejected=$true }
        Require $rejected 'Alpha wait accepted a different baseline target.'
        function Get-PtAlwaysOnTopWindowState {
            param($Identity)
            [pscustomobject]@{Identity=$Identity;Layered=$true;LayerStatus='Available';LayerFlags=2;Alpha=$null}
        }
        $rejected=$false
        try { Wait-PtAlwaysOnTopAlphaChange -Identity $identity -Before $plain -TimeoutSeconds 0.1 | Out-Null } catch { $rejected=$true }
        Require $rejected 'A null alpha labeled Available was accepted as an actual change.'
        function Get-PtAlwaysOnTopWindowState {
            param($Identity)
            [pscustomobject]@{Identity=$Identity;Layered=$true;LayerStatus='Available';LayerFlags=1;Alpha=140}
        }
        $rejected=$false
        try { Wait-PtAlwaysOnTopAlphaChange -Identity $identity -Before $plain -TimeoutSeconds 0.1 | Out-Null } catch { $rejected=$true }
        Require $rejected 'Color-key-only attributes were mistaken for an active constant-alpha change.'
    } finally { Set-Item Function:\Get-PtAlwaysOnTopWindowState -Value $alphaReader }
    $wrong = [pscustomobject]@{
        hwnd=$identity.hwnd; processId=$identity.processId
        processStartTicks=$identity.processStartTicks; className='NotTheFixtureClass'
    }
    $rejected=$false
    try { Get-PtAlwaysOnTopWindowState -Identity $wrong | Out-Null } catch { $rejected=$true }
    Require $rejected 'Mismatched window identity was accepted.'
    $hostIntegrity = Get-PtAlwaysOnTopProcessIntegrity -ProcessId $PID
    Require ($hostIntegrity.Identity.processId -eq $PID -and $hostIntegrity.IntegrityRid -gt 0) 'Actual mandatory integrity was not read.'
    $rejected = $false
    try { Assert-PtAlwaysOnTopExecutionReady -Identity $identity -RequireForeground | Out-Null }
    catch { $rejected = $true }
    Require $rejected 'The hidden fixture was accepted as an exact foreground input target.'
    $reader = ${function:Get-PtAlwaysOnTopProcessIntegrity}
    try {
        function Get-PtAlwaysOnTopProcessIntegrity {
            param([int]$ProcessId)
            if ($ProcessId -eq $PID) { return $hostIntegrity }
            if ($guardCase -eq 'ReadError') { throw 'Synthetic token read failure.' }
            [pscustomobject]@{
                Identity = [pscustomobject]@{sessionId=($hostIntegrity.Identity.sessionId + [int]($guardCase -eq 'Session'))}
                IntegrityRid = $hostIntegrity.IntegrityRid + $(if ($guardCase -eq 'Integrity') {4096} else {0})
            }
        }
        foreach ($guardCase in 'Session','Integrity','ReadError') {
            $rejected = $false
            try { Assert-PtAlwaysOnTopExecutionReady -Identity $identity -PeerProcessId 2147483647 | Out-Null }
            catch { $rejected = $true }
            Require $rejected "Execution guard accepted $guardCase."
        }
    } finally { Set-Item Function:\Get-PtAlwaysOnTopProcessIntegrity -Value $reader }
} finally { $window.Dispose() }
$rejected=$false
try { Get-PtAlwaysOnTopWindowState -Identity $identity | Out-Null } catch { $rejected=$true }
Require $rejected 'Destroyed window identity was accepted.'
'PASS: Always On Top observations and execution guards reject stale identities, incompatible sessions/integrity, and unreadable tokens.'
