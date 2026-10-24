# Copyright (c) Microsoft Corporation.
# The Microsoft Corporation licenses this file to you under the MIT license.
# See the LICENSE file in the project root for more information.

if (-not ('PtQuickAccentInput' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class PtQuickAccentInput
{
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT
    {
        public ushort vk, scan;
        public uint flags, time;
        public UIntPtr extra;
    }
    [StructLayout(LayoutKind.Explicit, Size = 40)]
    struct INPUT
    {
        [FieldOffset(0)] public uint type;
        [FieldOffset(8)] public KEYBDINPUT key;
    }
    [DllImport("user32.dll", SetLastError = true)]
    static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    public static void Key(ushort key, bool up)
    {
        var input = new INPUT { type = 1 };
        input.key.vk = key;
        input.key.flags = (up ? 2u : 0u) | ((key >= 0x21 && key <= 0x28) ? 1u : 0u);
        if (SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>()) != 1)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "SendInput did not accept the key event.");
    }
}
'@
}

function Invoke-PtQuickAccentGesture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][long]$WindowHandle,
        [Parameter(Mandatory)][uint16]$KeyCode,
        [uint16]$TriggerCode = 0,
        [uint16[]]$Modifiers = @(),
        [ValidateRange(0, 10000)][int]$DelayMs = 1000,
        [Parameter(Mandatory)][scriptblock]$Observe
    )
    if ([IntPtr]::Size -ne 8) { throw 'This input helper requires a 64-bit PowerShell host.' }
    if ([PtQuickAccentInput]::GetForegroundWindow().ToInt64() -ne $WindowHandle) {
        throw 'The exact owned fixture HWND must already be foreground.'
    }
    $keys = @($Modifiers) + @($KeyCode)
    if ($TriggerCode) { $keys += $TriggerCode }
    foreach ($key in $keys) {
        if (([PtQuickAccentInput]::GetAsyncKeyState($key) -band 0x8000) -ne 0) {
            throw "Key $key is already held; no input injected."
        }
    }
    $held = [Collections.Generic.List[uint16]]::new()
    try {
        foreach ($key in (@($Modifiers) + @($KeyCode))) {
            $held.Add($key)
            [PtQuickAccentInput]::Key($key, $false)
        }
        if ($TriggerCode) {
            $held.Add($TriggerCode)
            [PtQuickAccentInput]::Key($TriggerCode, $false)
            [PtQuickAccentInput]::Key($TriggerCode, $true)
            $held.RemoveAt($held.Count - 1)
        }
        Start-Sleep -Milliseconds $DelayMs
        & $Observe
    }
    finally {
        $releaseErrors = @()
        for ($index = $held.Count - 1; $index -ge 0; $index--) {
            try { [PtQuickAccentInput]::Key($held[$index], $true) }
            catch { $releaseErrors += $_ }
        }
        if ($releaseErrors.Count) { throw "Key release incomplete: $($releaseErrors -join '; ')" }
    }
}

function Get-PtQuickAccentFileHash {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [IO.File]::Exists($Path)) { return 'ABSENT' }
    $stream = [IO.File]::Open($Path, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))
    }
    finally { $stream.Dispose() }
}

function New-PtQuickAccentFileBaseline {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $exists = [IO.File]::Exists($fullPath)
    $bytes = if ($exists) { [IO.File]::ReadAllBytes($fullPath) } else { [byte[]]::new(0) }
    # The returned object contains private bytes. Keep it in the driver, never serialize it as evidence.
    [pscustomobject]@{
        Path = $fullPath
        Exists = $exists
        Bytes = $bytes
        Hash = if ($exists) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]$bytes)) } else { 'ABSENT' }
    }
}

function Restore-PtQuickAccentFileBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Baseline,
        [Parameter(Mandatory)][string]$ExpectedHash
    )
    if ((Get-PtQuickAccentFileHash -Path $Baseline.Path) -ne $ExpectedHash) {
        throw "Restoration conflict at $($Baseline.Path); original backup retained."
    }
    if ($Baseline.Exists) {
        [IO.File]::WriteAllBytes($Baseline.Path, [byte[]]$Baseline.Bytes)
    }
    elseif ([IO.File]::Exists($Baseline.Path)) {
        [IO.File]::Delete($Baseline.Path)
    }
    $actual = Get-PtQuickAccentFileHash -Path $Baseline.Path
    if ($actual -ne $Baseline.Hash) { throw "Restoration verification failed at $($Baseline.Path)." }
    [pscustomobject]@{ Path = $Baseline.Path; Restored = $true; Hash = $actual }
}

function Invoke-PtQuickAccentCharacterDialog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][long]$WindowHandle,
        [Parameter(Mandatory)][string]$ManageButtonName,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    Add-Type -AssemblyName UIAutomationClient
    $root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$WindowHandle)
    function Find-DialogControl([string]$Id) {
        $root.FindFirst([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::AutomationIdProperty, $Id))
    }
    if ((Find-DialogControl 'CharacterSetsSearchBox') -or (Find-DialogControl 'PrimaryButton')) {
        throw 'An existing dialog must be closed before opening character sets.'
    }
    $buttons = @($root.FindAll([Windows.Automation.TreeScope]::Descendants,
        [Windows.Automation.AndCondition]::new(
            [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::NameProperty, $ManageButtonName),
            [Windows.Automation.PropertyCondition]::new(
                [Windows.Automation.AutomationElement]::ControlTypeProperty,
                [Windows.Automation.ControlType]::Button))))
    if ($buttons.Count -ne 1 -or -not $buttons[0].Current.IsEnabled -or $buttons[0].Current.IsOffscreen) {
        throw 'A unique visible enabled Manage character sets button is required.'
    }
    $ownedSearchId = $null
    try {
        $buttons[0].GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        do {
            $search = Find-DialogControl 'CharacterSetsSearchBox'
            if ($search) { break }
            Start-Sleep -Milliseconds 50
        } while ([DateTime]::UtcNow -lt $deadline)
        if (-not $search) { throw 'Character dialog did not become observable; do not open it again.' }
        $ownedSearchId = $search.GetRuntimeId() -join ','
        & $Action $root
    }
    finally {
        $currentSearch = Find-DialogControl 'CharacterSetsSearchBox'
        if ($ownedSearchId -and $currentSearch -and
            (($currentSearch.GetRuntimeId() -join ',') -eq $ownedSearchId)) {
            $cancel = Find-DialogControl 'CloseButton'
            if (-not $cancel) { throw 'Owned character dialog has no observable Cancel control.' }
            $cancel.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
            $deadline = [DateTime]::UtcNow.AddSeconds(5)
            while ((Find-DialogControl 'CharacterSetsSearchBox') -and [DateTime]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 50
            }
            if (Find-DialogControl 'CharacterSetsSearchBox') { throw 'Owned character dialog did not close.' }
        }
    }
}
