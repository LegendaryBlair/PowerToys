# Copyright (c) Microsoft Corporation.
# The Microsoft Corporation licenses this file to you under the MIT license.
# See the LICENSE file in the project root for more information.

param(
    [Parameter(Mandatory)][string]$OutputFile,
    [Parameter(Mandatory)][string]$Title
)

$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputFile) { throw 'Fixture identity output must not already exist.' }
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[void][Windows.Forms.Application]::SetHighDpiMode([Windows.Forms.HighDpiMode]::PerMonitorV2)
$forms = @()
$context = [Windows.Forms.ApplicationContext]::new()
$script:openCount = 2
try {
    foreach ($number in 1, 2) {
        $form = [Windows.Forms.Form]::new()
        $form.Text = "$Title-$number"
        $form.StartPosition = 'Manual'
        $form.Location = [Drawing.Point]::new((120 + ($number - 1) * 700), 300)
        $form.Size = [Drawing.Size]::new(650, 350)
        $edit = [Windows.Forms.TextBox]::new()
        $edit.Name = "OwnedText$number"
        $edit.Multiline = $true
        $edit.Dock = 'Fill'
        $edit.ImeMode = [Windows.Forms.ImeMode]::Disable
        $form.Controls.Add($edit)
        $form.Add_FormClosed({
            $script:openCount--
            if ($script:openCount -eq 0) { $context.ExitThread() }
        })
        $forms += $form
        $form.Show()
    }
    @($forms | ForEach-Object {
        [pscustomobject]@{ Title = $_.Text; Hwnd = $_.Handle.ToInt64(); ProcessId = $PID }
    }) | ConvertTo-Json | Set-Content -LiteralPath $OutputFile
    [Windows.Forms.Application]::Run($context)
}
finally {
    foreach ($form in $forms) { $form.Dispose() }
    $context.Dispose()
}
