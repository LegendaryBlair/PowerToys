# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE.txt in the skill directory.
#requires -Version 7.2
param(
    [Parameter(Mandatory)][string]$StateDirectory,
    [ValidateRange(0,31)][int]$MonitorIndex = 0,
    [string]$LanguageSample = ''
)
$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathFullyQualified($StateDirectory) -or
    -not (Test-Path -LiteralPath $StateDirectory -PathType Container) -or
    (Test-Path -LiteralPath (Join-Path $StateDirectory 'ready.json'))) {
    throw 'Supply a new owned absolute state directory without a readiness receipt.'
}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::PerMonitorV2) | Out-Null
[Windows.Forms.Application]::EnableVisualStyles()
$screens = [Windows.Forms.Screen]::AllScreens
if ($MonitorIndex -ge $screens.Count) { throw 'Requested monitor is not available.' }
$screen = $screens[$MonitorIndex]
$form = [Windows.Forms.Form]::new()
$form.Text = "Text Extractor owned scene $([IO.Path]::GetFileName($StateDirectory))"
$form.StartPosition = 'Manual'
$form.FormBorderStyle = 'None'
$form.Bounds = $screen.Bounds
$form.BackColor = [Drawing.Color]::White
$form.AutoScaleMode = 'None'
$font = [Drawing.Font]::new('Segoe UI', 24, [Drawing.FontStyle]::Regular)
$labels = [Collections.Generic.List[object]]::new()
foreach ($line in @(
    @{Id='Region';Text='PowerToys Text Extractor';X=0.10;Y=0.32},
    @{Id='Language';Text=$LanguageSample;X=0.57;Y=0.32},
    @{Id='Line1';Text='Alpha Bravo';X=0.10;Y=0.52},
    @{Id='Line2';Text='Charlie Delta';X=0.10;Y=0.60},
    @{Id='Cell11';Text='Apple';X=0.57;Y=0.52},
    @{Id='Cell12';Text='11';X=0.80;Y=0.52},
    @{Id='Cell21';Text='Berry';X=0.57;Y=0.60},
    @{Id='Cell22';Text='22';X=0.80;Y=0.60}
)) {
    $label = [Windows.Forms.Label]::new()
    $label.Name = $line.Id
    $label.Text = $line.Text
    $label.AutoSize = $true
    $label.Font = $font
    $label.ForeColor = [Drawing.Color]::Black
    $label.Location = [Drawing.Point]::new([int]($screen.Bounds.Width*$line.X),[int]($screen.Bounds.Height*$line.Y))
    $form.Controls.Add($label)
    $labels.Add($label)
}
$form.Add_Shown({
    $form.Activate()
    $regions = @{}
    foreach ($label in $labels) {
        $rect = $label.RectangleToScreen($label.ClientRectangle)
        $regions[$label.Name] = @{Left=$rect.Left;Top=$rect.Top;Width=$rect.Width;Height=$rect.Height;Text=$label.Text}
    }
    @{
        ProcessId=$PID;Hwnd=$form.Handle.ToInt64();Dpi=$form.DeviceDpi;DeviceName=$screen.DeviceName
        Bounds=@{Left=$form.Left;Top=$form.Top;Width=$form.Width;Height=$form.Height}
        Regions=$regions
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $StateDirectory 'ready.json')
})
try { [Windows.Forms.Application]::Run($form) }
finally { $form.Dispose(); $font.Dispose() }
