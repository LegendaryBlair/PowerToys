#requires -Version 7.2
. "$PSScriptRoot\pt-fancyzones-displays.ps1"
. "$PSScriptRoot\pt-fancyzones-mutation.ps1"
. "$PSScriptRoot\pt-file-io.ps1"
. "$PSScriptRoot\pt-uia.ps1"
. "$PSScriptRoot\pt-session-safety.ps1"
. "$PSScriptRoot\pt-foreground-guard.ps1"
. "$PSScriptRoot\pt-shared-events.ps1"
if (-not ('PtFancyZonesDriverNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class PtFancyZonesDriverNative {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetPropW(IntPtr window, string name);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll")] static extern bool GetLayeredWindowAttributes(IntPtr window, out uint key, out byte alpha, out uint flags);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window, uint attribute, out Rect rect, int size);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern uint RegisterWindowMessageW(string name);
    [DllImport("user32.dll", SetLastError=true)]
    static extern IntPtr SendMessageTimeoutW(IntPtr window, uint message, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    public static void RefreshEditorInput(long window) {
        uint message = RegisterWindowMessageW("{d8f9c0e3-5d77-4e83-8a4f-7c704c2bfb4a}");
        if (message == 0) throw new Win32Exception();
        IntPtr result;
        if (SendMessageTimeoutW(new IntPtr(window), message, IntPtr.Zero, IntPtr.Zero, 3, 5000, out result)==IntPtr.Zero)
            throw new Win32Exception();
    }
    public static long ZoneMask(long window) { return GetPropW(new IntPtr(window), "FancyZones_zones").ToInt64(); }
    public static object Read(long window) {
        IntPtr handle=new IntPtr(window);
        Rect frame;
        int hr=DwmGetWindowAttribute(handle, 9, out frame, Marshal.SizeOf<Rect>());
        if(hr != 0) Marshal.ThrowExceptionForHR(hr);
        uint color, flags; byte alpha;
        bool alphaRead=GetLayeredWindowAttributes(handle,out color,out alpha,out flags);
        return new {
            Frame=frame, ZoneMask=ZoneMask(window), Dpi=GetDpiForWindow(handle),
            Maximized=IsZoomed(handle), Owner=GetWindow(handle,4).ToInt64(),
            Layered=(GetWindowLongPtr(handle,-20).ToInt64() & 0x80000)!=0,
            AlphaRead=alphaRead, Alpha=alpha, AlphaFlags=flags
        };
    }
}
'@
}

function Get-PtFancyZonesWindowState {
    param([Parameter(Mandatory)]$Identity)
    Assert-PtWindowIdentity $Identity
    $session = Get-PtActiveResourceSession
    $owned = @($session.Windows | Where-Object {
        $_.Ownership -ceq 'Owned' -and -not $_.Closed -and $_.Identity.hwnd -eq $Identity.hwnd
    })
    if ($owned.Count -ne 1) { throw 'Window observations require the exact owned fixture identity.' }
    Assert-PtWindowIdentity $owned[0].Identity
    [pscustomobject]@{
        Identity=$Identity
        Native=([PtFancyZonesDriverNative]::Read($Identity.hwnd))
        Window=(Get-PtNativeWindow -Hwnd $Identity.hwnd)
    }
}

function Assert-PtFancyZonesHost {
    param([Parameter(Mandatory)]$Creation)
    $session = Get-PtActiveResourceSession
    if (-not $session) { throw 'FancyZones driver requires an active resource session.' }
    $registered = @($session.Processes | Where-Object Id -CEQ $Creation.Id)
    $actual = Get-PtResourceProcessIdentity -ProcessId $Creation.ProcessId
    if ($registered.Count -ne 1 -or $registered[0].State -cne 'Started' -or
        $registered[0].ProcessId -ne $Creation.ProcessId -or
        $registered[0].ProcessStartTicks -ne $Creation.ProcessStartTicks -or
        -not $actual -or $actual.processStartTicks -ne $Creation.ProcessStartTicks -or
        $actual.path -ine $Creation.ImagePath) {
        throw 'FancyZones host is not the exact owned live process.'
    }
}

function New-PtFancyZonesDriverContext {
    param(
        [Parameter(Mandatory)]$ExpectedState,
        [Parameter(Mandatory)]$HostCreation,
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$EditorPath,
        [Parameter(Mandatory)][string]$PrivateRecoveryDirectory
    )
    Assert-PtFancyZonesHost $HostCreation
    Assert-PtWindowIdentity $Settings
    ConvertTo-PtFileSetSnapshotMap $ExpectedState 8MB | Out-Null
    if ('last-used-virtual-desktop.json' -cnotin $ExpectedState.FileNames) {
        throw 'Snapshot last-used-virtual-desktop.json before module/desktop activation.'
    }
    $root = [IO.Path]::GetFullPath($PrivateRecoveryDirectory).TrimEnd('\')
    if (-not [IO.Directory]::Exists($root) -or
        $root.StartsWith($ExpectedState.FileState.Path, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Use a separate existing private recovery directory.'
    }
    $path = Join-Path $root 'driver-expected-module.json'
    if (Test-Path -LiteralPath $path) { throw 'Driver recovery already exists; retain the original context.' }
    $copy = ConvertFrom-PtReportJson ($ExpectedState | ConvertTo-Json -Depth 10 -Compress)
    [IO.File]::WriteAllText($path, ($copy | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{
        ModuleRoot=$copy.FileState.Path; ExpectedModule=$copy; ExpectedSnapshotPath=$path
        HostCreation=$HostCreation; Settings=$Settings; EditorPath=$EditorPath
        EditorCreation=$null; Editor=$null; InMutation=$false
        LayoutIds=@(); ApplicationPaths=@(); HotkeyDigits=@(); DefaultOrientations=@(); TemplateTypes=@()
    }
}

function New-PtFancyZonesDriverScope {
    param([Parameter(Mandatory)]$Context)
    Assert-PtFancyZonesHost $Context.HostCreation
    $model = Get-PtFancyZonesDisplayModel
    $areas = @(foreach ($span in $false,$true) {
        $parameters = New-PtFancyZonesEditorParameters -DisplayModel $model -HostProcessId $Context.HostCreation.ProcessId `
            -Spanning $span -TargetMonitor $model.Monitors[0].Handle
        foreach ($monitor in $parameters.monitors) { ConvertTo-PtFancyZonesDevice $monitor }
    })
    [pscustomobject]@{
        WorkAreas=$areas; LayoutIds=@($Context.LayoutIds); ApplicationPaths=@($Context.ApplicationPaths)
        SettingKeys=@(); HotkeyDigits=@($Context.HotkeyDigits); DefaultOrientations=@($Context.DefaultOrientations)
        TemplateTypes=@($Context.TemplateTypes); GeneratedEditorInput=$false
        HostProcessId=$Context.HostCreation.ProcessId; NativeSerialization=$false
        NewLayoutName=$null; NewLayoutType=$null; TargetDesktop=$null
    }
}

function Invoke-PtFancyZonesDriverAction {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Scope,
        [Parameter(Mandatory)][scriptblock]$Action,
        [object[]]$ArgumentList=@()
    )
    $attempt = Get-PtActiveVerificationAttempt
    if (-not $attempt) { throw 'Drive FancyZones inside a recorded verification attempt.' }
    if ($Context.InMutation) { throw 'Do not nest FancyZones mutation scopes.' }
    $expected = $Context.ExpectedModule
    $Context.InMutation = $true
    $primaryError = $null
    try {
        Invoke-PtFancyZonesScopedAction -ExpectedState ([ref]$expected) -Scope $Scope `
            -Action $Action -ArgumentList $ArgumentList
    } catch {
        $primaryError = $_
        throw
    } finally {
        $Context.InMutation = $false
        $Context.ExpectedModule = $expected
        try {
            $staging = $Context.ExpectedSnapshotPath + '.' + [guid]::NewGuid().ToString('N') + '.new'
            Write-PtReportText -Path $staging -Text ($expected | ConvertTo-Json -Depth 12)
            [IO.File]::Move($staging, $Context.ExpectedSnapshotPath, $true)
        } catch {
            if ($primaryError) { $primaryError.Exception.Data['PrivateRecoveryWriteFailure'] = $_.Exception.Message }
            else { throw }
        }
    }
}

function Open-PtFancyZonesEditor {
    param([Parameter(Mandatory)]$Context)
    Assert-PtFancyZonesHost $Context.HostCreation
    if ($Context.EditorCreation) {
        Assert-PtWindowIdentity $Context.Editor
        return $Context.Editor
    }
    $scope = New-PtFancyZonesDriverScope $Context
    $scope.GeneratedEditorInput = $true
    $scope.NativeSerialization = $true
    Invoke-PtFancyZonesDriverAction -Context $Context -Scope $scope -ArgumentList @($Context) -Action {
        param($driver)
        $settings = ConvertFrom-PtReportJson (Read-PtSharedFileText (Join-Path $driver.ModuleRoot 'settings.json'))
        Get-PtFancyZonesCurrentEditorInput -Context $driver -Spanning $settings.properties.fancyzones_span_zones_across_monitors.value | Out-Null
        $driver.EditorCreation = Invoke-PtOwnedProcessActivation -FilePath $driver.EditorPath -TimeoutSeconds 15 `
            -Action { Invoke-PtSharedEvent -Name FancyZones.ToggleEditor }
        $window = Wait-PtCondition -Description 'owned FancyZones editor main' -TimeoutSeconds 15 -Probe {
            $windows = @(Get-PtNativeWindow -ProcessId $driver.EditorCreation.ProcessId -Visible |
                Where-Object { $_.Title -match 'FancyZones Editor' })
            if ($windows.Count -gt 1) { throw 'Ambiguous FancyZones editor main.' }
            if ($windows.Count -eq 1) { $windows[0] }
        }
        $driver.Editor = Get-PtWindowIdentity $window.Hwnd
        Register-PtCreatedProcessWindows $driver.EditorCreation | Out-Null
        Assert-PtForegroundOrAbort -Hwnd $driver.Editor.hwnd
    } | Out-Null
    $Context.Editor
}

function Get-PtFancyZonesCurrentEditorInput {
    <#.SYNOPSIS
    Request the installed host's current editor-input model, without changing its settings.
    .NOTES
    This writes the generated cache and must run inside a GeneratedEditorInput mutation
    scope. Unlike a fixed sleep or persisted Settings value, the reply observes the host.
    No layout-update notification, restart, input gesture or test-result inference occurs.
    #>
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][bool]$Spanning)
    if (-not $Context.InMutation) { throw 'Generated editor input requires an active driver mutation scope.' }
    Assert-PtFancyZonesHost $Context.HostCreation
    $windows = @(Get-PtNativeWindow -ProcessId $Context.HostCreation.ProcessId -ClassName SuperFancyZones)
    if ($windows.Count -ne 1) { throw 'Expected exactly one owned FancyZones message window.' }
    Register-PtCreatedProcessWindows $Context.HostCreation | Out-Null
    $identity = Get-PtWindowIdentity $windows[0].Hwnd
    Wait-PtCondition -Description 'host acknowledges the current work-area mode' -TimeoutSeconds 12 -Probe {
        Assert-PtWindowIdentity $identity
        [PtFancyZonesDriverNative]::RefreshEditorInput($identity.hwnd)
        $document = ConvertFrom-PtReportJson (Read-PtSharedFileText (Join-Path $Context.ModuleRoot 'editor-parameters.json'))
        if ($document.'process-id' -eq $Context.HostCreation.ProcessId -and
            $document.'span-zones-across-monitors' -eq $Spanning -and @($document.monitors).Count -gt 0) {
            $document
        }
    }
}

function Close-PtFancyZonesEditor {
    param([Parameter(Mandatory)]$Context)
    if (-not $Context.EditorCreation) { return }
    $scope = New-PtFancyZonesDriverScope $Context
    $scope.GeneratedEditorInput = $true
    Invoke-PtFancyZonesDriverAction -Context $Context -Scope $scope -ArgumentList @($Context) -Action {
        param($driver)
        Register-PtCreatedProcessWindows $driver.EditorCreation | Out-Null
        Stop-PtOwnedProcess -Creation $driver.EditorCreation -TimeoutSeconds 15 -ArgumentList @($driver.Editor) -RequestExit {
            param($process, $window)
            Close-PtTrackedWindow $window
        } | Out-Null
        $driver.EditorCreation = $null
        $driver.Editor = $null
    } | Out-Null
}

function Invoke-PtFancyZonesElementClick {
    param([Parameter(Mandatory)][long]$Hwnd, [Parameter(Mandatory)]$Element)
    Assert-PtForegroundOrAbort -Hwnd $Hwnd
    $scroll = $null
    if ($Element.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern, [ref]$scroll)) { $scroll.ScrollIntoView() }
    $bounds = $Element.Current.BoundingRectangle
    if ($Element.Current.IsOffscreen -or -not $Element.Current.IsEnabled -or $bounds.Width -le 0 -or $bounds.Height -le 0) {
        throw 'The actual FancyZones control is not clickable.'
    }
    $point = '{0},{1}' -f [int]($bounds.Left+$bounds.Width/2), [int]($bounds.Top+$bounds.Height/2)
    Invoke-PtWinApp -Arguments @('drag',$point,$point,'-w',"$Hwnd",'--hold-ms','30') | Out-Null
}

function Select-PtFancyZonesMonitor {
    param([Parameter(Mandatory)]$Context, [Parameter(Mandatory)][int]$MonitorNumber)
    $hwnd = (Open-PtFancyZonesEditor $Context).hwnd
    $parameters = Get-PtFancyZonesSnapshotJson $Context.ExpectedModule 'editor-parameters.json'
    $ordinal = Get-PtFancyZonesMonitorOrdinal -EditorParameters $parameters -MonitorNumber $MonitorNumber
    $list = Resolve-PtUiElement -Hwnd $hwnd -AutomationId Monitors -ControlType List
    $items = @($list.FindAll([Windows.Automation.TreeScope]::Descendants,
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,
            [Windows.Automation.ControlType]::ListItem)))
    $matching = @($items | Where-Object {
        @($_.FindAll([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty,"$ordinal"))).Count -gt 0
    })
    $target = Select-PtUniqueUiElement -Elements $matching -Description "actual monitor $MonitorNumber"
    Invoke-PtFancyZonesElementClick -Hwnd $hwnd -Element $target
}

function Set-PtFancyZonesBoolean {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$ContainerId,
        [Parameter(Mandatory)][string]$SettingKey,
        [Parameter(Mandatory)][bool]$Value
    )
    $scope = New-PtFancyZonesDriverScope $Context
    $scope.SettingKeys = @($SettingKey)
    if ($SettingKey -ceq 'fancyzones_span_zones_across_monitors') {
        if ($Context.EditorCreation) { throw 'Close the owned editor before changing spanning.' }
        $scope.NativeSerialization = $true
        $scope.GeneratedEditorInput = $true
    } else {
        $scope.WorkAreas = @()
    }
    $result = [pscustomobject]@{Requested=$Value;Actual=$null}
    Invoke-PtFancyZonesDriverAction -Context $Context -Scope $scope -ArgumentList @($Context,$ContainerId,$SettingKey,$Value,$result) -Action {
        param($driver,$containerId,$settingKey,$requested,$output)
        Assert-PtWindowIdentity $driver.Settings
        Assert-PtForegroundOrAbort -Hwnd $driver.Settings.hwnd
        Initialize-PtUiAutomation
        $root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$driver.Settings.hwnd)
        $container = Select-PtUniqueUiElement -Description $containerId -Elements @(
            $root.FindAll([Windows.Automation.TreeScope]::Descendants,
                [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,$containerId)))
        $scroll = $null
        if ($container.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern,[ref]$scroll)) {
            $scroll.ScrollIntoView()
        }
        $controls = @($container) + @($container.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition))
        $toggle = @(foreach ($element in $controls) {
            $pattern = $null
            if ($element.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern,[ref]$pattern)) {
                $ancestor = $element
                $nestedCard = $false
                while ($ancestor -and -not [Windows.Automation.Automation]::Compare($ancestor, $container)) {
                    if ($ancestor.Current.ControlType -eq [Windows.Automation.ControlType]::Group -and
                        $ancestor.Current.AutomationId) {
                        $nestedCard = $true
                        break
                    }
                    $ancestor = [Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($ancestor)
                }
                if ($nestedCard) { continue }
                [pscustomobject]@{Element=$element;Pattern=$pattern}
            }
        })
        if ($toggle.Count -ne 1) { throw "Expected one actual toggle under $containerId." }
        if (-not $toggle[0].Element.Current.IsEnabled) { throw "The toggle under $containerId is disabled." }
        if (($toggle[0].Pattern.Current.ToggleState -eq 'On') -ne $requested) { $toggle[0].Pattern.Toggle() }
        Wait-PtCondition -Description 'FancyZones setting persistence' -TimeoutSeconds 8 -Probe {
            $json = ConvertFrom-PtReportJson (Read-PtSharedFileText (Join-Path $driver.ModuleRoot 'settings.json'))
            $json.properties.$settingKey.value -eq $requested
        } | Out-Null
        $output.Actual = $toggle[0].Pattern.Current.ToggleState -eq 'On'
        if ($settingKey -ceq 'fancyzones_span_zones_across_monitors') {
            Get-PtFancyZonesCurrentEditorInput -Context $driver -Spanning $requested | Out-Null
        }
    } | Out-Null
    $result
}
