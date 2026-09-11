param([Parameter(Mandatory)][string]$StateDirectory,[switch]$Churn,[switch]$Observation)
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
if($Observation){
    $disabled=[Windows.Forms.TextBox]::new()
    $disabled.Name='FixtureDisabled';$disabled.AccessibleName='Disabled fixture';$disabled.Enabled=$false
    $disabled.Dock='Bottom';$form.Controls.Add($disabled)
    $password=[Windows.Forms.TextBox]::new()
    $password.Name='FixturePassword';$password.AccessibleName='Synthetic protected fixture'
    $password.UseSystemPasswordChar=$true;$password.Text='synthetic-never-read'
    $password.Dock='Bottom';$form.Controls.Add($password)
    $range=[Windows.Forms.TrackBar]::new()
    $range.Name='FixtureRange';$range.Minimum=0;$range.Maximum=10;$range.Value=0
    $range.Dock='Bottom';$range.Height=32;$form.Controls.Add($range)
}
foreach ($groupName in 'FixturePanel1','FixturePanel2') {
    $panel = [Windows.Forms.Panel]::new()
    $panel.Name = $groupName
    $panel.Dock = 'Bottom'
    $panel.Height = 32
    $combo = [Windows.Forms.ComboBox]::new()
    $combo.Name = 'FixtureCombo'
    $combo.AccessibleName = 'Fixture choice'
    $combo.DropDownStyle = 'DropDownList'
    $combo.Dock = 'Fill'
    $combo.Items.AddRange([object[]]@('Alpha','Beta','Gamma'))
    $combo.SelectedIndex = 0
    $panel.Controls.Add($combo)
    $form.Controls.Add($panel)
}
$other = [Windows.Forms.Form]::new()
$other.Text = 'Second helper window - same process'
$other.StartPosition = 'Manual'
$other.Location = [Drawing.Point]::new(850,200)
$other.Size = [Drawing.Size]::new(420,240)
$transients=[Collections.Generic.List[Windows.Forms.Form]]::new()
$timer=[Windows.Forms.Timer]::new()
if($Churn){
    $timer.Interval=10
    $timer.Add_Tick({
        foreach($window in $transients){$window.Dispose()}
        $transients.Clear()
        for($i=0;$i -lt 4;$i++){
            $window=[Windows.Forms.Form]::new()
            $window.Text='Owned transient enumeration fixture'
            [void]$window.Handle
            $transients.Add($window)
        }
    })
    $timer.Start()
}
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
finally {
    $timer.Stop();$timer.Dispose()
    foreach($window in $transients){$window.Dispose()}
    $other.Dispose(); $menu.Dispose(); $form.Dispose()
}
