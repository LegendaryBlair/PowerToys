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
    $wrong = [pscustomobject]@{
        hwnd=$identity.hwnd; processId=$identity.processId
        processStartTicks=$identity.processStartTicks; className='NotTheFixtureClass'
    }
    $rejected=$false
    try { Get-PtAlwaysOnTopWindowState -Identity $wrong | Out-Null } catch { $rejected=$true }
    Require $rejected 'Mismatched window identity was accepted.'
} finally { $window.Dispose() }
$rejected=$false
try { Get-PtAlwaysOnTopWindowState -Identity $identity | Out-Null } catch { $rejected=$true }
Require $rejected 'Destroyed window identity was accepted.'
'PASS: Always On Top read-only observations distinguish marker/style, alpha availability, and stale identities.'
