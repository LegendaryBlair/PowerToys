#requires -Version 7.2
param([Parameter(Mandatory)][string]$StatePath,[Parameter(Mandatory)][string]$AppId,
    [Parameter(Mandatory)][string]$Title,[int]$Offset=0,[string]$ReceiptPath,[string]$FixtureId)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $StatePath){throw 'Fixture state file already exists.'}
if ($AppId -cnotmatch '^PowerToys\.Verification\.H11\.([a-f0-9]{32})\.([1-9])$') { throw 'Invalid H11 app identity.' }
$token = $Matches[1]
$index = [int]$Matches[2]
if ($ReceiptPath) {
    if ($FixtureId -cne $token) { throw 'Fixture token mismatch.' }
    $started = [Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
        if ($receipt.Kind -cne 'Taskbar' -or $receipt.Id -cne $FixtureId -or $receipt.ReceiptPath -cne $ReceiptPath -or
            $receipt.Apps[$index - 1].AppId -cne $AppId -or $receipt.Apps[$index - 1].StatePath -cne $StatePath -or
            (Get-FileHash -LiteralPath $receipt.MarkerPath).Hash -cne $receipt.MarkerHash) {
            throw 'Fixture launch receipt/marker mismatch.'
        }
        if ($receipt.Phase -cne 'Creating' -or $receipt.Apps[$index - 1].CloseRequested) { return }
        $launcher = $receipt.Apps[$index - 1].Launcher
        if ($launcher) {
            if ($launcher.ProcessId -ne $PID -or $launcher.ProcessStartTicks -ne $started) { throw 'Fixture launcher identity mismatch.' }
            break
        }
        if ($clock.Elapsed.TotalSeconds -ge 15) { throw 'No persisted launch permission; refusing to create a window.' }
        Start-Sleep -Milliseconds 50
    } while ($true)
} elseif ($FixtureId) { throw 'FixtureId requires ReceiptPath.' }
Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class PtTaskbarAppIdentity {
    [DllImport("shell32.dll",CharSet=CharSet.Unicode,PreserveSig=true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@
[Runtime.InteropServices.Marshal]::ThrowExceptionForHR([PtTaskbarAppIdentity]::SetCurrentProcessExplicitAppUserModelID($AppId))
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::ThrowException)
$form=[Windows.Forms.Form]::new()
$form.Text=$Title;$form.Name='PowerToysTaskbarFixture'
$form.StartPosition='Manual';$form.Location=[Drawing.Point]::new(240+$Offset,180+$Offset)
$form.Size=[Drawing.Size]::new(500,260);$form.ShowInTaskbar=$true
$label=[Windows.Forms.Label]::new()
$label.Name='FixtureIdentity';$label.Text=$Title;$label.Dock='Fill';$label.TextAlign='MiddleCenter'
$form.Controls.Add($label)
$form.Add_Shown({
    $state=[pscustomobject]@{Version=1;FixtureId=$token;Hwnd=$form.Handle.ToInt64();ProcessId=$PID;ProcessStartTicks=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks;AppId=$AppId;Title=$Title}
    $temporary="$StatePath.$([Guid]::NewGuid().ToString('N')).tmp"
    $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $state));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    [IO.File]::Move($temporary,$StatePath,$false)
})
try{[Windows.Forms.Application]::Run($form)}finally{$form.Dispose()}
