param([Parameter(Mandatory)][string]$StateDirectory)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form = [Windows.Forms.Form]::new()
$form.Text = "PowerToys helper fixture $([IO.Path]::GetFileName($StateDirectory))"
$form.StartPosition = 'Manual'
$form.Location = [Drawing.Point]::new(200,200)
$form.Size = [Drawing.Size]::new(620,340)
$form.ImeMode = 'Disable'
$edit = [Windows.Forms.TextBox]::new()
$edit.Name = 'FixtureInput'
$edit.AccessibleName = 'Fixture input'
$edit.Multiline = $true
$edit.Dock = 'Fill'
$edit.ImeMode = 'Disable'
$edit.Add_KeyDown({
    [pscustomobject]@{ key = [int]$_.KeyCode; down = $true; ticks = [Diagnostics.Stopwatch]::GetTimestamp() } |
        ConvertTo-Json -Compress | Add-Content -LiteralPath "$StateDirectory\keys.jsonl"
})
$edit.Add_KeyUp({
    [pscustomobject]@{ key = [int]$_.KeyCode; down = $false; ticks = [Diagnostics.Stopwatch]::GetTimestamp() } |
        ConvertTo-Json -Compress | Add-Content -LiteralPath "$StateDirectory\keys.jsonl"
    [IO.File]::WriteAllText("$StateDirectory\text.txt", $edit.Text)
})
$menu = [Windows.Forms.ContextMenuStrip]::new()
[void]$menu.Items.Add('Fixture action')
$menu.Add_Opened({ [IO.File]::WriteAllText("$StateDirectory\menu.txt", 'open') })
$menu.Add_Closed({ [IO.File]::WriteAllText("$StateDirectory\menu.txt", 'closed') })
$edit.ContextMenuStrip = $menu
$form.Controls.Add($edit)
$other = [Windows.Forms.Form]::new()
$other.Text = 'Second helper window - same process'
$other.StartPosition = 'Manual'
$other.Location = [Drawing.Point]::new(850,200)
$other.Size = [Drawing.Size]::new(420,240)
$form.Add_Shown({
    $other.Show()
    $form.Activate()
    $edit.Focus()
    [pscustomobject]@{
        hwnd = $form.Handle.ToInt64(); otherHwnd = $other.Handle.ToInt64()
        processId = $PID; stopwatchFrequency = [Diagnostics.Stopwatch]::Frequency
    } | ConvertTo-Json | Set-Content -LiteralPath "$StateDirectory\ready.json"
})
try { [Windows.Forms.Application]::Run($form) }
finally { $other.Dispose(); $menu.Dispose(); $form.Dispose() }
