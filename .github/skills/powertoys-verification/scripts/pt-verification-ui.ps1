#Requires -Version 7.4
. (Join-Path $PSScriptRoot 'pt-verification-run.ps1')
if (-not ('PtVerification.Desktop' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'pt-verification-native.cs') -ErrorAction Stop
}

function Get-PtWindowIdentity {
    <#.SYNOPSIS
    Capture an exact HWND and its process identity. Never choose the first app window.
    #>
    param([Parameter(Mandatory)][long]$Hwnd)
    $ErrorActionPreference = 'Stop'
    if (-not [PtVerification.Desktop]::IsWindow([IntPtr]$Hwnd)) { throw "Window no longer exists: $Hwnd" }
    [uint32]$owner = 0
    $thread = [PtVerification.Desktop]::GetWindowThreadProcessId([IntPtr]$Hwnd, [ref]$owner)
    if (-not $thread -or -not $owner) { throw 'Window owner cannot be read.' }
    $process = Get-Process -Id $owner -ErrorAction Stop
    if (-not $process.Path) { throw 'Process path cannot be read.' }
    [pscustomobject]@{ Hwnd=$Hwnd; ProcessId=$owner; ThreadId=$thread; StartTicks=$process.StartTime.ToUniversalTime().Ticks; Path=$process.Path }
}

function Assert-PtWindowIdentity {
    param([Parameter(Mandatory)]$Window, [switch]$Foreground, [switch]$Visible)
    $ErrorActionPreference = 'Stop'
    $actual = Get-PtWindowIdentity $Window.Hwnd
    foreach ($field in @('Hwnd','ProcessId','ThreadId','StartTicks','Path')) {
        if ($actual.$field -cne $Window.$field) { throw "Window identity changed: $field" }
    }
    if ($Visible -and (-not [PtVerification.Desktop]::IsWindowVisible([IntPtr]$Window.Hwnd) -or [PtVerification.Desktop]::Cloaked([IntPtr]$Window.Hwnd))) {
        throw 'Target window is hidden or cloaked.'
    }
    if ($Foreground -and [PtVerification.Desktop]::GetForegroundWindow().ToInt64() -ne $Window.Hwnd) { throw 'Exact target HWND is not foreground; no input sent.' }
}

function Get-PtUiNodes {
    param([Parameter(Mandatory)]$Tree)
    foreach ($node in @($Tree)) {
        if ($null -eq $node) { continue }
        if ($node.type) { $node }
        foreach ($property in @('windows','elements','children')) {
            if ($node.$property) { Get-PtUiNodes $node.$property }
        }
    }
}

function Resolve-PtUiControl {
    <#.SYNOPSIS
    Resolve exactly one typed control within the supplied window tree or parent row; ambiguity is an error.
    #>
    param([Parameter(Mandatory)]$Root, [Parameter(Mandatory)][string]$Type,
        [string]$AutomationId, [string]$Name, [switch]$AllowOffscreen)
    $ErrorActionPreference = 'Stop'
    if (-not $AutomationId -and -not $Name) { throw 'Supply AutomationId or Name.' }
    $nodes = @(Get-PtUiNodes $Root | Where-Object {
        $_.type -ceq $Type -and (-not $AutomationId -or $_.automationId -ceq $AutomationId) -and
        (-not $Name -or $_.name -ceq $Name) -and ($AllowOffscreen -or $_.isOffscreen -eq $false)
    })
    if (@($nodes | Where-Object { -not $_.selector }).Count) { throw 'Matching node lacks a usable runtime selector.' }
    $matches = @($nodes | Group-Object selector -CaseSensitive | ForEach-Object {
        $fingerprints = @($_.Group | ForEach-Object {
            $_ | Select-Object type,name,automationId,x,y,width,height | ConvertTo-Json -Compress
        } | Select-Object -Unique)
        if ($fingerprints.Count -ne 1) { throw "Conflicting nodes share a selector: $($_.Name)" }
        $_.Group[0]
    })
    if ($matches.Count -ne 1) { throw "Expected one $Type control; found $($matches.Count)." }
    return $matches[0]
}

function Invoke-PtWindowCommand {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)]$Window, [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('inspect','search','get-value','get-property','wait-for','invoke','click','hover','scroll','set-value','send-keys','focus')][string]$Verb,
        [AllowEmptyString()][string[]]$Arguments = @(), [ValidateRange(1,600)][int]$TimeoutSeconds=30,
        [string]$WinAppPath='winapp')
    $ErrorActionPreference = 'Stop'
    if (@($Arguments | Where-Object { $_ -match '^(--?(a|app|w|window))($|=)' }).Count) { throw 'Do not override the scoped window selector.' }
    $inputOperation = $Verb -in @('click','hover','send-keys','focus') -or ($Verb -eq 'scroll' -and '--wheel' -in $Arguments)
    Assert-PtWindowIdentity $Window -Visible -Foreground:$inputOperation
    $result = Invoke-PtRecordedCommand -Run $Run -Name $Name -FilePath $WinAppPath -Arguments (@('ui',$Verb) + $Arguments + @('-w',"$($Window.Hwnd)")) -TimeoutSeconds $TimeoutSeconds
    if ($Verb -in @('inspect','search','get-value','get-property','wait-for')) {
        try { Assert-PtWindowIdentity $Window -Visible }
        catch {
            Save-PtRunJson (Join-Path $Run.Workspace "commands\$($result.Id)\observation-error.json") @{ Error=$_.ToString(); Window=$Window }
            $invocationPath = Join-Path $Run.Workspace "commands\$($result.Id)\invocation.json"
            $invocation = Get-Content -LiteralPath $invocationPath -Raw | ConvertFrom-Json
            $invocation.Status = 'Error'; $invocation.Error = $_.ToString()
            Save-PtRunJson $invocationPath $invocation
            throw
        }
    }
    return $result
}

function Set-PtScopedToggle {
    <#.SYNOPSIS
    Read an exact toggle, change only when needed, then verify readback. Callers separately check persistence/lifecycle.
    #>
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)]$Window,
        [Parameter(Mandatory)][string]$Selector, [Parameter(Mandatory)][bool]$Enabled,
        [string]$OnValue='On', [string]$OffValue='Off', [string]$WinAppPath='winapp')
    $ErrorActionPreference = 'Stop'
    if ($OnValue -ceq $OffValue) { throw 'Toggle states must differ.' }
    $read = Invoke-PtWindowCommand $Run $Window 'Read toggle' get-value -Arguments @($Selector,'--json') -WinAppPath $WinAppPath
    $value = ($read.Stdout | ConvertFrom-Json -ErrorAction Stop).text
    if ($value -cne $OnValue -and $value -cne $OffValue) { throw "Unknown toggle state: $value" }
    $desired = if ($Enabled) { $OnValue } else { $OffValue }
    if ($value -cne $desired) {
        $null = Invoke-PtWindowCommand $Run $Window 'Change toggle' invoke -Arguments @($Selector) -WinAppPath $WinAppPath
    }
    $receipt = Invoke-PtWindowCommand $Run $Window 'Verify toggle' wait-for -Arguments @($Selector,'--value',$desired,'-t','5000') -WinAppPath $WinAppPath
    [pscustomobject]@{ PreviousEnabled=($value -ceq $OnValue); Enabled=$Enabled; Changed=($value -cne $desired); EvidencePath=$receipt.EvidencePath }
}

function Save-PtWindowCapture {
    <#.SYNOPSIS
    Capture live physical bounds without activating a window; reject changed identity/foreground/geometry.
    #>
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][object[]]$Windows, [Parameter(Mandatory)][string]$Name)
    $ErrorActionPreference = 'Stop'
    if (-not $Windows.Count) { throw 'Capture requires a window.' }
    $null = Assert-PtRunCurrent $Run
    Add-Type -AssemblyName System.Drawing
    $oldDpi = [PtVerification.Desktop]::SetThreadDpiAwarenessContext([IntPtr](-4))
    if ($oldDpi -eq [IntPtr]::Zero) { throw 'Cannot enter physical-coordinate DPI context.' }
    $id = [guid]::NewGuid().ToString('N')
    $imagePath = Join-Path $Run.Workspace "$id.png"
    $sidecar = Join-Path $Run.Workspace "$id.capture.json"
    $record = [ordered]@{ Name=$Name; Windows=$Windows; Valid=$false; Error=$null }
    try {
        $foreground = [PtVerification.Desktop]::GetForegroundWindow().ToInt64()
        $rects = @(foreach ($window in $Windows) {
            Assert-PtWindowIdentity $window -Visible
            $rect = [PtVerification.Desktop+Rect]::new()
            if (-not [PtVerification.Desktop]::GetWindowRect([IntPtr]$window.Hwnd,[ref]$rect)) { throw 'Cannot measure capture window.' }
            $rect
        })
        $left = ($rects.Left | Measure-Object -Minimum).Minimum
        $top = ($rects.Top | Measure-Object -Minimum).Minimum
        $right = ($rects.Right | Measure-Object -Maximum).Maximum
        $bottom = ($rects.Bottom | Measure-Object -Maximum).Maximum
        $width = [int]($right-$left); $height = [int]($bottom-$top)
        if ($width -le 0 -or $height -le 0 -or [long]$width*$height -gt 40000000) { throw 'Invalid/oversized capture bounds.' }
        $record.Bounds = @{ Left=$left; Top=$top; Width=$width; Height=$height }
        $record.Foreground = $foreground
        $bitmap = [Drawing.Bitmap]::new($width,$height)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try { $graphics.CopyFromScreen([int]$left,[int]$top,0,0,$bitmap.Size) }
            finally { $graphics.Dispose() }
            $bitmap.Save($imagePath,[Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose() }
        for ($i=0; $i -lt $Windows.Count; $i++) {
            Assert-PtWindowIdentity $Windows[$i] -Visible
            $after = [PtVerification.Desktop+Rect]::new()
            if (-not [PtVerification.Desktop]::GetWindowRect([IntPtr]$Windows[$i].Hwnd,[ref]$after) -or -not $after.Equals($rects[$i])) { throw 'Capture window moved.' }
        }
        if ([PtVerification.Desktop]::GetForegroundWindow().ToInt64() -ne $foreground) { throw 'Foreground changed during capture.' }
        $record.Valid = $true
    } catch { $record.Error=$_.ToString(); throw }
    finally {
        $dpiRestored = [PtVerification.Desktop]::SetThreadDpiAwarenessContext($oldDpi) -ne [IntPtr]::Zero
        if (-not $dpiRestored) { $record.Valid=$false; $record.Error="$($record.Error) DPI context restoration failed." }
        Save-PtRunJson $sidecar $record
        if (-not $dpiRestored) { throw 'DPI context restoration failed.' }
    }
    [pscustomobject]@{ Image=[IO.Path]::GetFileName($imagePath); Observation=[IO.Path]::GetFileName($sidecar); Valid=$true }
}
