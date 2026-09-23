#Requires -Version 7.4
param([Parameter(Mandatory)][string]$Receipt, [Parameter(Mandatory)][string]$StopFile)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::PerMonitorV2) | Out-Null
$main=[Windows.Forms.Form]::new()
$main.Text='Owned verification harness fixture'
$main.StartPosition='Manual'; $main.Location=[Drawing.Point]::new(100,100)
$main.Size=[Drawing.Size]::new(600,350)
$edit=[Windows.Forms.TextBox]::new()
$edit.Name='FixtureInput'; $edit.AccessibleName='Fixture input'; $edit.Text='original'
$edit.Location=[Drawing.Point]::new(20,20); $edit.Width=300
$main.Controls.Add($edit)
$toggle=[Windows.Forms.CheckBox]::new()
$toggle.Name='FixtureToggle';$toggle.AccessibleName='Fixture toggle'
$toggle.Location=[Drawing.Point]::new(20,70)
$main.Controls.Add($toggle)
$popup=[Windows.Forms.Form]::new()
$popup.Text='Owned verification popup'; $popup.StartPosition='Manual'
$popup.Location=[Drawing.Point]::new(500,200); $popup.Size=[Drawing.Size]::new(300,200)
$popup.BackColor=[Drawing.Color]::Blue
$timer=[Windows.Forms.Timer]::new(); $timer.Interval=200
$timer.Add_Tick({if(Test-Path -LiteralPath $StopFile){$popup.Close();$main.Close()}})
$main.Add_Shown({
    $popup.Show($main)
    @{ ProcessId=$PID; Main=$main.Handle.ToInt64(); Popup=$popup.Handle.ToInt64() } |
        ConvertTo-Json | Set-Content -LiteralPath $Receipt
})
try { $timer.Start(); [Windows.Forms.Application]::Run($main) }
finally { $timer.Dispose();$popup.Dispose();$main.Dispose() }
