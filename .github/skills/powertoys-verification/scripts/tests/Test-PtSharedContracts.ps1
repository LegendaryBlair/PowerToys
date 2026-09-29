#requires -Version 7.2
<#
.SYNOPSIS
Offline shared-contract checks: synthetic files and objects only; no clipboard or desktop mutation.
#>
param([string]$Workspace = (Join-Path $env:TEMP "pt-shared-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference = 'Stop'
$helpers = Split-Path $PSScriptRoot -Parent
foreach ($name in 'pt-state','pt-module-lifecycle','pt-shortcut-recorder','pt-shortcut-guide-flow','pt-clipboard-guard') {
    . "$helpers\$name.ps1"
}
if (Test-Path -LiteralPath $Workspace) { throw 'Use a new test workspace.' }
[IO.Directory]::CreateDirectory($Workspace) | Out-Null
$results = [Collections.Generic.List[object]]::new()
function Require([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Reject([scriptblock]$Body, [string]$Pattern) {
    try { & $Body | Out-Null }
    catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; return }
    throw "Expected failure: $Pattern"
}
function Check([string]$Name, [scriptblock]$Body) {
    try { & $Body | Out-Null; $results.Add(@{Name=$Name;Status='PASS'}) }
    catch { $results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace}); throw }
    finally { ConvertTo-Json -InputObject @($results) -Depth 8 | Set-Content -LiteralPath "$Workspace\results.json" }
}
Check 'Live reads coexist with an open product-like writer and preserve lossless JSON' {
    $file = Join-Path $Workspace 'shared-settings.json'
    [IO.File]::WriteAllText($file, '{"enabled":{"Fixture":true},"ticks":639259548125726790,"time":"2026-09-23T09:13:46.1200000Z"}')
    $writer = [IO.File]::Open($file, 'Open', 'ReadWrite', [IO.FileShare]::ReadWrite)
    try {
        $doc = ConvertFrom-PtReportJson (Read-PtSharedFileText $file)
        Require ($doc.enabled.Fixture -and $doc.ticks -eq 639259548125726790L -and $doc.time -is [string]) 'Lossless read changed data'
        Require (Get-PtLifecycleConfiguredEnabled @{SettingsPath=$file;ModuleKey='Fixture'}) 'Lifecycle reader blocked the writer'
        Require ((Get-PtFileSnapshot $file).exists) 'Snapshot read failed with shared writer'
    } finally { $writer.Dispose() }
}
Check 'Encoding, empty files, missing files and invalid settings remain explicit' {
    $file = Join-Path $Workspace 'text.txt'
    [IO.File]::WriteAllText($file, 'bom-text', [Text.Encoding]::Unicode)
    Require ((Read-PtSharedFileText $file) -ceq 'bom-text') 'BOM decoding failed'
    [IO.File]::WriteAllBytes($file, [byte[]]@())
    Require ((Read-PtSharedFileBytes $file).Length -eq 0) 'Empty bytes were lost'
    [IO.File]::WriteAllText($file, '{broken')
    Reject { Get-PtLifecycleConfiguredEnabled @{SettingsPath=$file;ModuleKey='Fixture'} } 'JSON|invalid|Expected|parse'
    [IO.File]::WriteAllText($file, '{"enabled":{}}')
    Reject { Get-PtLifecycleConfiguredEnabled @{SettingsPath=$file;ModuleKey='Fixture'} } 'Missing/non-Boolean'
    Reject { Read-PtSharedFileBytes (Join-Path $Workspace 'missing.json') } 'Could not find|cannot find'
}
Check 'Guarded file rollback restores known writes, is idempotent and preserves foreign changes' {
    $file = Join-Path $Workspace 'guard.bin'
    [IO.File]::WriteAllBytes($file, [byte[]]@(0,255,13,10))
    $before = Get-PtFileSnapshot $file
    [IO.File]::WriteAllText($file, 'owned')
    $expected = Get-PtFileSnapshot $file
    $actual = Restore-PtFileSnapshot -Snapshot $before -ExpectedState $expected
    Require ($actual.base64 -ceq $before.base64) 'Rollback did not match original'
    $time = [IO.File]::GetLastWriteTimeUtc($file)
    Restore-PtFileSnapshot -Snapshot $before -ExpectedState $expected | Out-Null
    Require ([IO.File]::GetLastWriteTimeUtc($file) -eq $time) 'No-op rollback wrote the file'
    [IO.File]::WriteAllText($file, 'foreign')
    Reject { Restore-PtFileSnapshot -Snapshot $before -ExpectedState $expected } 'conflict'
    Require ([IO.File]::ReadAllText($file) -ceq 'foreign') 'Foreign change overwritten'
    $wrong = $expected.PSObject.Copy(); $wrong.path = Join-Path $Workspace 'other.bin'
    Reject { Restore-PtFileSnapshot -Snapshot $before -ExpectedState $wrong } 'same canonical path'
    $bad = $before.PSObject.Copy(); $bad.base64 = 'not base64!'
    Reject { Restore-PtFileSnapshot -Snapshot $bad -ExpectedState $expected } 'Base-64|Base64'
}
Check 'Baseline capture rejects a changing file instead of silently accepting one read' {
    $file = Join-Path $Workspace 'changing.json'
    [IO.File]::WriteAllText($file, 'original')
    $originalRead = ${function:Read-PtSharedFileBytes}
    $reads = @{Count=0}
    function Read-PtSharedFileBytes {
        param($Path)
        $reads.Count++
        return ,([Text.Encoding]::UTF8.GetBytes("value-$($reads.Count)"))
    }
    try { Reject { Get-PtFileSnapshot $file } 'changed during baseline capture' }
    finally { Set-Item Function:\Read-PtSharedFileBytes $originalRead }
}
Check 'Guarded rollback refuses active writers and absence instead of changing ownership' {
    $file = Join-Path $Workspace 'exclusive.json'
    [IO.File]::WriteAllText($file, 'original')
    $before = Get-PtFileSnapshot $file
    $writer = [IO.File]::Open($file, 'Open', 'ReadWrite', [IO.FileShare]::ReadWrite)
    try { Reject { Restore-PtFileSnapshot -Snapshot $before -ExpectedState $before } 'used by another process|sharing|access' }
    finally { $writer.Dispose() }
    $absent = Get-PtFileSnapshot (Join-Path $Workspace 'absent.json')
    Reject { Restore-PtFileSnapshot -Snapshot $absent -ExpectedState $absent } 'existing-file'
    Require (-not (Test-Path $absent.path)) 'Unsupported absent restore created a file'
    [IO.File]::Delete($file)
    Reject { Restore-PtFileSnapshot -Snapshot $before -ExpectedState $before } 'Could not find|cannot find'
}
Check 'Shortcut settings read tolerates the same writer contract' {
    $file = Join-Path $Workspace 'shortcut.json'
    [IO.File]::WriteAllText($file, '{"properties":{"ActivationShortcut":{"win":true,"ctrl":false,"alt":false,"shift":true,"code":67,"key":""}}}')
    $writer = [IO.File]::Open($file, 'Open', 'ReadWrite', [IO.FileShare]::ReadWrite)
    try { Require ((Get-PtShortcutBinding $file @('properties','ActivationShortcut')).code -eq 67) 'Shortcut shared read failed' }
    finally { $writer.Dispose() }
}
Check 'Clipboard primitive compiles and shutdown gate rejects missing restoration' {
    Initialize-PtClipboardGuard
    Require ($null -ne ('PtClipboard.ClipboardGuard' -as [type])) 'Native clipboard source did not compile'
    Require ($null -eq ('PtVerification.Desktop' -as [type])) 'An alternate desktop identity stack was imported'
    Reject { Assert-PtClipboardRestored @{Restored=$false} } 'not complete'
    Reject { Assert-PtClipboardRestored @{Restored='true'} } 'not complete'
    Assert-PtClipboardRestored @{Restored=$true}
    $guard = [pscustomobject]@{Calls=0}
    $guard | Add-Member ScriptMethod AcceptWrite {param($sequence,$pidValue) $this.Calls++; $sequence+1}
    Reject { Register-PtClipboardWrite $guard 10 $PID 1 } 'identity changed'
    Require ($guard.Calls -eq 0) 'Stale writer was accepted'
    $start = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
    Require ((Register-PtClipboardWrite $guard 10 $PID $start) -eq 11) 'Write receipt not returned'
}
Check 'Scoped capture resolves physical owner-popup union and refuses stale or hidden identities' {
    $oldNative = ${function:Get-PtNativeWindow}; $oldAssert = ${function:Assert-PtWindowIdentity}
    $oldCloaked = ${function:Test-PtWindowCloaked}
    $native = @{
        1L=@{Visible=$true;Minimized=$false;Rect=@{Left=-200;Top=10;Right=100;Bottom=210}}
        2L=@{Visible=$true;Minimized=$false;Rect=@{Left=80;Top=100;Right=300;Bottom=300}}
    }
    function Get-PtNativeWindow { param([long]$Hwnd) $native[$Hwnd] }
    function Test-PtWindowCloaked { param([long]$Hwnd) [bool]$native[$Hwnd].Cloaked }
    function Assert-PtWindowIdentity { param($Identity) if ($Identity.processStartTicks -ne 100) { throw 'identity changed' } }
    try {
        $one=@{hwnd=1L;processStartTicks=100}; $two=@{hwnd=2L;processStartTicks=100}
        $bounds=Get-PtCaptureWindowBounds @($one,$two)
        Require ($bounds.Left -eq -200 -and $bounds.Top -eq 10 -and $bounds.Width -eq 500 -and $bounds.Height -eq 290) 'Incorrect physical union'
        $native[2L].Minimized=$true
        Reject { Get-PtCaptureWindowBounds @($one,$two) } 'minimized'
        $native[2L].Minimized=$false; $native[2L].Cloaked=$true
        Reject { Get-PtCaptureWindowBounds @($one,$two) } 'cloaked'
        Reject { Get-PtCaptureWindowBounds @(@{hwnd=1L;processStartTicks=99}) } 'identity changed'
        Reject { Save-PtPassiveScreenshot -Path (Join-Path $Workspace 'never.png') -WindowIdentity @() } 'cannot be empty'
    } finally {
        Set-Item Function:\Get-PtNativeWindow $oldNative
        Set-Item Function:\Assert-PtWindowIdentity $oldAssert
        Set-Item Function:\Test-PtWindowCloaked $oldCloaked
    }
}
Check 'Canonical input set includes every native and script helper without duplicate sources' {
    $skill = Split-Path $helpers -Parent
    $inputs = @(Get-PtVerificationInputs -Skill $skill -Inputs @(@{Name='this-test.ps1';Role='Checklist';Path=$PSCommandPath}))
    Require (@($inputs | Where-Object Path -EQ "$helpers\pt-clipboard-guard.cs").Count -eq 1) 'Native clipboard source missing'
    Require (@($inputs | Where-Object Path -EQ "$helpers\pt-file-io.ps1").Count -eq 1) 'Shared reader source missing'
    Require (@($inputs | Where-Object Path -EQ "$helpers\hosts\clipboard-keeper.ps1").Count -eq 1) 'Keeper host source missing'
    $explicit = @{Name='custom-recorder.ps1';Role='Helper';Path="$helpers\pt-verification-report.ps1"}
    $again = @(Get-PtVerificationInputs -Skill $skill -Inputs @($explicit))
    Require (@($again | Where-Object Path -EQ $explicit.Path).Count -eq 1) 'Explicit helper duplicated'
    Reject { Get-PtVerificationInputs -Skill $skill -Inputs @($explicit,$explicit) } 'Duplicate input'
    $run = New-PtVerificationRun -Workspace (Join-Path $Workspace 'recorded-inputs') -Module 'Shared-contract fixture' `
        -Bits 'Offline synthetic fixture; no product UI' -Scenario InfrastructureAcceptance -Items @(
            @{Id='I1';Description='Input integrity';Admin='NO';Clarity='CLEAR';UserVisible=$false;
                Assertions=@(@{Id='source';Description='Native and script source inputs'})}
        ) -Inputs $inputs
    $metadata = ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $run.Workspace 'run.json')))
    Require (@($metadata.Inputs | Where-Object OriginalPath -EQ "$helpers\pt-clipboard-guard.cs").Count -eq 1) 'Recorder lost the native dependency'
}
Check 'Primitive failure retains the primary error and still restores independent desktop state' {
    $parse=$null;$tokens=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\Test-PtPrimitiveDesktop.ps1",[ref]$tokens,[ref]$parse)
    $finalizer=@($ast.FindAll({param($node)
        $node -is [Management.Automation.Language.TryStatementAst] -and $node.Finally -and
        $node.Finally.Extent.Text.Contains('restoration-status.json')
    },$true))
    Require ($finalizer.Count -eq 1) 'Cannot locate the actual primitive cleanup body'
    $guard=[pscustomobject]@{Restored=$false}
    $guard|Add-Member ScriptMethod Restore {throw 'Injected clipboard conflict'}
    $guard|Add-Member ScriptMethod Dispose {throw 'Unrestored guard must not be disposed'}
    $popup=$null;$owner=$null;$bitmap=$null;$png=$null;$baseline=@{Synthetic=$true}
    $testError=try{throw 'Original copy acknowledgement failure'}catch{$_}
    function Restore-PtDesktopSnapshot {param($Snapshot) $Snapshot}
    $body=[scriptblock]::Create(($finalizer[0].Finally.Statements.Extent.Text -join "`n"))
    . $body
    $receipt=ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$Workspace\restoration-status.json"))
    Require (-not $receipt.ClipboardRestored -and $receipt.DesktopRestored) 'Clipboard failure skipped desktop cleanup or claimed restoration'
    Require ($testError.Exception.Message -ceq 'Original copy acknowledgement failure' -and
        $testError.Exception.Data['CleanupFailures'].Count -eq 1) 'Cleanup masked the primary error'
}
Check 'Clipboard retries only bounded lock contention, never an action or a different native error' {
    $source=[IO.File]::ReadAllText("$helpers\pt-clipboard-guard.cs")
    $source=$source.Replace('namespace PtClipboard','namespace PtClipboardLockFixture')
    $isWindow='[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);'
    $open='[DllImport("user32.dll", SetLastError = true)] private static extern bool OpenClipboard(IntPtr owner);'
    Require ($source.Contains($isWindow) -and $source.Contains($open)) 'Native clipboard test boundaries changed'
    $source=$source.Replace($isWindow,'public static bool IsWindow(IntPtr hwnd) { return true; }')
    $source=$source.Replace('[DllImport("user32.dll")] private static extern IntPtr GetOpenClipboardWindow();',
        'private static IntPtr GetOpenClipboardWindow() { return IntPtr.Zero; }')
    $source=$source.Replace('[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);',
        'public static uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId) { processId=0; return 0; }')
    $source=$source.Replace($open,@'
        public static int NativeOpenAttempts, FailuresRemaining, FailureCode = 5;
        private static bool OpenClipboard(IntPtr owner) {
            NativeOpenAttempts++;
            if (FailuresRemaining-- <= 0) return true;
            Marshal.SetLastPInvokeError(FailureCode);
            return false;
        }
'@)
    Add-Type -TypeDefinition $source
    $type='PtClipboardLockFixture.ClipboardGuard' -as [type]
    $instance=[Runtime.CompilerServices.RuntimeHelpers]::GetUninitializedObject($type)
    $method=$type.GetMethod('Lock',[Reflection.BindingFlags]'Instance,NonPublic')
    [PtClipboardLockFixture.ClipboardGuard]::FailuresRemaining=3
    $method.Invoke($instance,@())
    Require ([PtClipboardLockFixture.ClipboardGuard]::NativeOpenAttempts -eq 4) 'Contention was not retried'
    [PtClipboardLockFixture.ClipboardGuard]::NativeOpenAttempts=0
    [PtClipboardLockFixture.ClipboardGuard]::FailuresRemaining=1000
    [PtClipboardLockFixture.ClipboardGuard]::FailureCode=87
    Reject {$method.Invoke($instance,@())} 'OpenClipboard'
    Require ([PtClipboardLockFixture.ClipboardGuard]::NativeOpenAttempts -eq 1) 'A non-contention error was retried'
    [PtClipboardLockFixture.ClipboardGuard]::FailureCode=5
    $clock=[Diagnostics.Stopwatch]::StartNew()
    Reject {$method.Invoke($instance,@())} 'OpenClipboard'
    Require ($clock.ElapsedMilliseconds -ge 490 -and $clock.ElapsedMilliseconds -lt 2000) 'Clipboard lock retry was not bounded to 500 ms'
}
"PASS: $($results.Count) shared WIP contract groups. No clipboard or desktop was mutated. $Workspace"
