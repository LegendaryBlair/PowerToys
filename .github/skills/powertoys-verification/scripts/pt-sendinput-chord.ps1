# scripts/pt-sendinput-chord.ps1
# Inject a global hotkey chord (e.g. Win+Shift+/) into the system input stream.
# Critical: INPUT struct MUST be cb=40 on x64 (with padding for the MOUSEINPUT union member).
# The common bug "Win+ hotkeys can't be injected" is a marshaling error producing 32-byte struct
# and SendInput returns 0 with GetLastError()==87 (ERROR_INVALID_PARAMETER).
#
# This SHOULD be a last resort. Prefer Named Events (Invoke-PtSharedEvent) when the module exposes one.
# Use this only for: (a) explicit hotkey-trigger verification tests, (b) modules without Named Events,
# (c) UI keystrokes inside an already-foreground window (use Send-KeyToHwnd via PostMessage instead
# for elevated -> non-elevated AppX, see references/winapp-ui-testing.md).

if (-not ('PtChord' -as [type])) {
    Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;
        using System.Collections.Generic;
        public static class PtChord {
            [StructLayout(LayoutKind.Sequential)]
            struct INPUT { public uint type; public KEYBDINPUT ki; public int pad1; public int pad2; } // pad to 40 bytes
            [StructLayout(LayoutKind.Sequential)]
            struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
            [DllImport("user32.dll", SetLastError=true)]
            static extern uint SendInput(uint n, INPUT[] p, int cb);
            [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
            const uint KEYUP = 0x0002;
            static INPUT K(ushort vk, bool up) {
                INPUT i=new INPUT(); i.type=1; i.ki.wVk=vk;
                bool extended = vk == 0x5B || vk == 0x5C || vk == 0xA3 || vk == 0xA5 ||
                    (vk >= 0x21 && vk <= 0x28) || vk == 0x2D || vk == 0x2E;
                i.ki.dwFlags=(up?KEYUP:0) | (extended?1u:0u); return i;
            }
            public static uint Key(ushort key, bool up) {
                return SendInput(1, new INPUT[] { K(key, up) }, Marshal.SizeOf(typeof(INPUT)));
            }
            public static uint Chord(ushort[] mods, ushort key) {
                var l=new List<INPUT>();
                foreach(var m in mods) l.Add(K(m,false));
                l.Add(K(key,false)); l.Add(K(key,true));
                for(int i=mods.Length-1;i>=0;i--) l.Add(K(mods[i],true));
                var a=l.ToArray();
                return SendInput((uint)a.Length, a, Marshal.SizeOf(typeof(INPUT)));
            }
            public static uint Tap(ushort key) { return Chord(new ushort[0], key); }
        }
'@
}

# Common VK codes for chord mods:
#   LWIN=0x5B  RWIN=0x5C  CTRL=0x11  SHIFT=0x10  ALT=0x12
# Main key VKs:
#   0x08 Backspace 0x09 Tab 0x0D Enter 0x1B Escape 0x20 Space
#   0x25 Left 0x26 Up 0x27 Right 0x28 Down
#   0x30..0x39 0..9    0x41..0x5A A..Z

function Send-PtChord {
    <#
    .SYNOPSIS
    Inject a chord with configurable dwell. Throws on incomplete input; releases keys in finally.
    .EXAMPLE
    Send-PtChord -Mods 0x5B,0x10 -Key 0x43      # Win+Shift+C (Color Picker)
    Send-PtChord -Mods 0x5B,0x11 -Key 0x52      # Win+Ctrl+R (PowerOcr)
    Send-PtChord -Mods 0x5B,0xA4 -Key 0x20      # Win+Alt+Space (CmdPal default)
    Send-PtChord -Key 0x0D                       # plain Enter (no mods)
    #>
    [CmdletBinding()]
    param(
        [uint16[]]$Mods = @(),
        [Parameter(Mandatory)][ValidateRange(1,254)][uint16]$Key,
        [ValidateRange(0,5000)][int]$KeyDownMilliseconds = 90,
        [ValidateRange(0,1000)][int]$ModifierDelayMilliseconds = 40,
        [long]$Hwnd
    )
    if ($PSBoundParameters.ContainsKey('Hwnd')) {
        Assert-PtForegroundOrAbort -Hwnd $Hwnd
    }
    Invoke-PtHeldKeys -Keys @($Mods + $Key) -KeyDownDelayMilliseconds $ModifierDelayMilliseconds -Action {
        Start-Sleep -Milliseconds $KeyDownMilliseconds
    }
    return 2 * ($Mods.Count + 1)
}

function Invoke-PtHeldKeys {
    <#
    .SYNOPSIS
    Hold keys during an observation, then release every injected key even if the action throws.
    .NOTES
    The action may change foreground (for example Win+1). Guard the initial HWND, not the result.
    Already-held keys are rejected so cleanup never releases a key owned by the user/outer scope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateCount(1,16)][uint16[]]$Keys,
        [Parameter(Mandatory)][scriptblock]$Action,
        [ValidateRange(0,1000)][int]$KeyDownDelayMilliseconds = 40,
        [long]$Hwnd
    )
    if (@($Keys | Select-Object -Unique).Count -ne $Keys.Count -or @($Keys | Where-Object { $_ -lt 1 -or $_ -gt 254 }).Count) {
        throw 'Keys must be unique virtual-key codes in 1..254.'
    }
    foreach ($key in $Keys) {
        if (([PtChord]::GetAsyncKeyState($key) -band 0x8000) -ne 0) { throw "Key $key is already held; input aborted." }
    }
    if ($PSBoundParameters.ContainsKey('Hwnd')) { Assert-PtForegroundOrAbort -Hwnd $Hwnd }
    $down = [Collections.Generic.List[uint16]]::new()
    $releaseErrors = [Collections.Generic.List[string]]::new()
    $originalError = $null
    try {
        foreach ($key in $Keys) {
            if ([PtChord]::Key($key, $false) -ne 1) {
                throw "SendInput key-down $key failed (Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
            }
            $down.Add($key)
            if ($KeyDownDelayMilliseconds) { Start-Sleep -Milliseconds $KeyDownDelayMilliseconds }
        }
        & $Action
    } catch {
        $originalError = $_
        throw
    } finally {
        for ($i = $down.Count - 1; $i -ge 0; $i--) {
            if ([PtChord]::Key($down[$i], $true) -ne 1) { $releaseErrors.Add("Key-up $($down[$i]) failed") }
        }
        if ($releaseErrors.Count) {
            $message = "Input cleanup failed: $($releaseErrors -join '; ')"
            if ($originalError) {
                $originalError.Exception.Data['InputCleanupFailure'] = $message
                [Console]::Error.WriteLine($message)
            } else { throw $message }
        }
    }
}

function Wait-PtHotkeyAccepted {
    <#
    .SYNOPSIS
    After Send-PtChord, verify the PT runner saw it by tailing its log for the centralized-hook line.
    Returns the matching log line (if any) within $TimeoutSec.
    .EXAMPLE
    Send-PtChord -Mods 0x5B,0x10 -Key 0x43
    $line = Wait-PtHotkeyAccepted -ModuleHint 'Color' -TimeoutSec 3
    if (-not $line) { throw "Runner did not log hotkey invocation" }
    #>
    [CmdletBinding()]
    param([string]$ModuleHint = '', [int]$TimeoutSec = 3)
    $log = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\PowerToys\RunnerLogs" -Filter 'runner-log_*.log' -EA SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $log) { return $null }
    $start = (Get-Date).AddSeconds(-2)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        $line = Get-Content $log.FullName -Tail 50 -EA SilentlyContinue |
                Where-Object { $_ -match 'hotkey is invoked from Centralized keyboard hook' -and ($ModuleHint -eq '' -or $_ -match $ModuleHint) } |
                Select-Object -Last 1
        if ($line) { return $line }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    return $null
}
