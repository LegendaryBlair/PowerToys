#requires -Version 7.2
foreach($dependency in 'pt-uia','pt-state-snapshot','pt-sendinput-chord','pt-taskbar-fixture'){. "$PSScriptRoot\$dependency.ps1"}

function Invoke-PtRunnerTrayRightClick {
    param([Parameter(Mandatory)]$Target,[Parameter(Mandatory)]$Icon)
    Initialize-PtTaskbarNative
    if([PtDesktop]::GetForegroundWindow() -eq [IntPtr]::Zero){throw 'An attached interactive desktop is required for the tray gesture.'}
    if([PtTaskbarNative]::RightButtonDown() -or [PtTaskbarNative]::LeftButtonDown()){throw 'A mouse button is already held; no input issued.'}
    Assert-PtWindowIdentity $Target
    $element=Resolve-PtUiElement -Hwnd $Target.hwnd -Name $Icon.name -ControlType Button
    $rect=$element.Current.BoundingRectangle
    if($element.Current.IsOffscreen -or -not $element.Current.IsEnabled -or $rect.Width -le 0 -or $rect.Height -le 0){
        throw 'The actual tray icon is not a usable pointer target.'
    }
    $x=[int][Math]::Floor($rect.Left+$rect.Width/2);$y=[int][Math]::Floor($rect.Top+$rect.Height/2)
    if([PtTaskbarNative]::PointWindow($x,$y) -ne $Target.hwnd){throw 'The tray icon is covered by a different native window.'}
    if((Send-PtTaskbarMouse -Kind Move -X $x -Y $y) -ne 1){throw 'Tray pointer input was not accepted.'}
    Wait-PtCondition -Description 'actual pointer at the observed tray icon' -TimeoutSeconds 2 -PollMilliseconds 25 -Probe {
        $point=Get-PtTaskbarPointer
        $point.X -eq $x -and $point.Y -eq $y
    }|Out-Null
    Assert-PtWindowIdentity $Target
    if([PtTaskbarNative]::PointWindow($x,$y) -ne $Target.hwnd){throw 'Tray hit receiver changed after pointer movement.'}
    $fresh=Resolve-PtUiElement -Hwnd $Target.hwnd -Name $Icon.name -ControlType Button
    $actual=$fresh.Current.BoundingRectangle
    if($fresh.Current.IsOffscreen -or -not $fresh.Current.IsEnabled -or
        $actual.Left -ne $rect.Left -or $actual.Top -ne $rect.Top -or
        $actual.Width -ne $rect.Width -or $actual.Height -ne $rect.Height -or
        [PtTaskbarNative]::PointWindow($x,$y) -ne $Target.hwnd){
        throw 'The unique tray target moved or became covered before the gesture.'
    }
    $pressed=$false;$failure=$null
    try{
        if([PtTaskbarNative]::RightButtonDown() -or [PtTaskbarNative]::LeftButtonDown()){throw 'Mouse button state changed before the gesture.'}
        if((Send-PtTaskbarMouse -Kind RightDown) -ne 1){throw 'Tray right-button down was not accepted.'}
        $pressed=$true
    }catch{$failure=$_}
    finally{
        if($pressed){
            try{
                if((Send-PtTaskbarMouse -Kind RightUp) -ne 1){throw 'Tray right-button release was not accepted.'}
                Wait-PtCondition -Description 'injected right button released' -TimeoutSeconds 2 -PollMilliseconds 25 -Probe {
                    -not [PtTaskbarNative]::RightButtonDown()
                }|Out-Null
            }catch{if($failure){$failure.Exception.Data['RightButtonReleaseFailure']=$_.Exception.Message}else{$failure=$_}}
        }
    }
    if($failure){throw $failure}
    [pscustomobject]@{Method='UIA target plus native SendInput right-click';Target=$Target;Name=$Icon.name;X=$x;Y=$y
        Guard='Unique live Button, stable bounds and native root hit receiver; no UIA point-child assumption'}
}

function Find-PtRunnerTrayControl {
    param([Parameter(Mandatory)]$Target,[Parameter(Mandatory)][string]$Query,
        [ValidateSet('Button','MenuItem')][string]$Type='Button',[switch]$RunnerIcon)
    Assert-PtWindowIdentity $Target
    $arguments=@('search',$Query,'-w',"$($Target.hwnd)",'--type',$Type,'--max','100','--json')
    if($RunnerIcon){$arguments+=@('--class-name','SystemTray.NormalButton')}
    $result=ConvertFrom-PtReportJson (Invoke-PtWinApp -Arguments $arguments -AllowNoMatches)
    if($result.hasMore -ne $false -or $result.matchCount -ne @($result.matches).Count){
        throw 'Tray query is incomplete; no action permitted.'
    }
    $matches=@($result.matches)
    if($RunnerIcon){$matches=@($matches|Where-Object {$_.name -match '^PowerToys v[0-9]'})}
    if($matches.Count -gt 1){throw 'Ambiguous tray control; no first-match action permitted.'}
    if($matches.Count -eq 1){
        if(-not $matches[0].isEnabled -or $matches[0].isOffscreen -or
            $matches[0].width -le 0 -or $matches[0].height -le 0){return}
        $matches[0]
    }
}

function Get-PtRunnerTrayOverflow {
    @(Get-PtNativeWindow -ClassName TopLevelWindowForOverflowXamlIsland -Visible |
        Where-Object {-not (Test-PtWindowCloaked -Hwnd $_.Hwnd)})
}

function Close-PtRunnerTrayOverflow {
    param([Parameter(Mandatory)]$Taskbar,[Parameter(Mandatory)]$Overflow,
        [string]$OverflowButtonName='Show Hidden Icons',[string]$ClosedButtonName,[double]$TimeoutSeconds=8)
    if(-not $ClosedButtonName){$ClosedButtonName=$OverflowButtonName}
    $visible=@(Get-PtRunnerTrayOverflow|Where-Object Hwnd -EQ $Overflow.hwnd)
    if(-not $visible.Count){return [pscustomobject]@{Hidden=$true;AlreadyHidden=$true}}
    Assert-PtWindowIdentity $Overflow
    Assert-PtWindowIdentity $Taskbar
    $gesture=Invoke-PtRunnerOverflowDismissClick -Taskbar $Taskbar -Overflow $Overflow -ClosedButtonName $ClosedButtonName
    Wait-PtCondition -Description 'owned tray overflow hidden' -TimeoutSeconds $TimeoutSeconds -Probe {
        @(Get-PtRunnerTrayOverflow|Where-Object Hwnd -EQ $Overflow.hwnd).Count -eq 0
    }|Out-Null
    [pscustomobject]@{Hidden=$true;AlreadyHidden=$false;Gesture=$gesture}
}

function Invoke-PtRunnerOverflowDismissClick {
    param($Taskbar,$Overflow,[string]$ClosedButtonName)
    Initialize-PtTaskbarNative
    Initialize-PtUiAutomation
    if([PtDesktop]::GetForegroundWindow() -eq [IntPtr]::Zero){throw 'An attached interactive desktop is required for popup dismissal.'}
    if([PtTaskbarNative]::LeftButtonDown() -or [PtTaskbarNative]::RightButtonDown()){throw 'A mouse button is held before popup dismissal.'}
    $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$Taskbar.hwnd)
    $condition=[Windows.Automation.AndCondition]::new(
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::Button),
        [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ClassNameProperty,'SystemTray.NormalButton'))
    $buttons=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)|Where-Object {
        $_.Current.Name.StartsWith($ClosedButtonName,[StringComparison]::Ordinal)
    })
    $button=Select-PtUniqueUiElement -Elements $buttons -Description 'owned overflow control'
    if($button.Current.Name -ceq $ClosedButtonName){return [pscustomobject]@{Pressed=$false;Reason='Shell already reports the closed state'}}
    $rect=$button.Current.BoundingRectangle
    if($button.Current.IsOffscreen -or -not $button.Current.IsEnabled -or $rect.Width -le 0 -or $rect.Height -le 0){
        throw 'Overflow dismissal control is not usable.'
    }
    $x=[int][Math]::Floor($rect.Left+$rect.Width/2);$y=[int][Math]::Floor($rect.Top+$rect.Height/2)
    if([PtTaskbarNative]::PointWindow($x,$y) -ne $Taskbar.hwnd){throw 'Overflow dismissal control is covered.'}
    if((Send-PtTaskbarMouse -Kind Move -X $x -Y $y) -ne 1){throw 'Dismissal pointer move was not accepted.'}
    Wait-PtCondition -Description 'pointer on the actual overflow control' -TimeoutSeconds 2 -PollMilliseconds 25 -Probe {
        $point=Get-PtTaskbarPointer;$point.X -eq $x -and $point.Y -eq $y
    }|Out-Null
    if(-not @(Get-PtRunnerTrayOverflow|Where-Object Hwnd -EQ $Overflow.hwnd).Count -or $button.Current.Name -ceq $ClosedButtonName){
        return [pscustomobject]@{Pressed=$false;Reason='Popup closed before the pointer action'}
    }
    Assert-PtWindowIdentity $Taskbar
    $actual=$button.Current.BoundingRectangle
    if($button.Current.IsOffscreen -or -not $button.Current.IsEnabled -or
        -not $button.Current.Name.StartsWith($ClosedButtonName,[StringComparison]::Ordinal) -or
        $actual.Left -ne $rect.Left -or $actual.Top -ne $rect.Top -or
        $actual.Width -ne $rect.Width -or $actual.Height -ne $rect.Height -or
        [PtTaskbarNative]::PointWindow($x,$y) -ne $Taskbar.hwnd){throw 'Overflow dismissal target changed before input.'}
    $pressed=$false
    try{
        if([PtTaskbarNative]::LeftButtonDown() -or [PtTaskbarNative]::RightButtonDown()){throw 'Mouse button state changed before dismissal.'}
        if(-not @(Get-PtRunnerTrayOverflow|Where-Object Hwnd -EQ $Overflow.hwnd).Count -or $button.Current.Name -ceq $ClosedButtonName){
            return [pscustomobject]@{Pressed=$false;Reason='Popup closed before button-down'}
        }
        if((Send-PtTaskbarMouse -Kind Down) -ne 1){throw 'Dismissal button-down was not accepted.'}
        $pressed=$true
    }finally{
        if($pressed -and (Send-PtTaskbarMouse -Kind Up) -ne 1){throw 'Dismissal button release was not accepted.'}
    }
    Wait-PtCondition -Description 'dismissal button released' -TimeoutSeconds 2 -PollMilliseconds 25 -Probe {
        -not [PtTaskbarNative]::LeftButtonDown()
    }|Out-Null
    [pscustomobject]@{Pressed=$true;Method='State-checked physical chevron click';X=$x;Y=$y}
}

function Invoke-PtRunnerTrayCommand {
    <#
    .SYNOPSIS
    Invoke a real Runner-owned tray menu item through winapp; no WM_COMMAND/WM_CLOSE substitute.
    .NOTES
    Requires an interactive Windows 11 desktop and a visible or overflowed Runner icon.
    Command IDs are the native menu AutomationIds, not commands sent directly to the window.
    Existing open menus/overflow are not adopted. Only this operation's popup is dismissed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)]
        [ValidateSet('Exit','Settings','QuickAccess')][string]$Command,
        [ValidateNotNullOrEmpty()][string]$OverflowButtonName='Show Hidden Icons',
        [scriptblock]$Observe,[object[]]$ObservationArguments=@(),
        [ValidateRange(0.1,30)][double]$TimeoutSeconds=8)
    Assert-PtRunnerRestartIdentity $State.Runner
    if(@(Get-PtNativeWindow -ProcessId $State.Runner.processId -ClassName '#32768' -Visible).Count -or
        @(Get-PtRunnerTrayOverflow).Count){throw 'An existing tray menu/overflow must be preserved or dismissed before this operation.'}
    $bars=@(Get-PtNativeWindow -ClassName Shell_TrayWnd -Visible)
    if($bars.Count -ne 1){throw 'Exactly one primary taskbar is required.'}
    $bar=Get-PtWindowIdentity $bars[0].Hwnd
    $desktop=Get-PtDesktopSnapshot
    $overflow=$null;$menu=$null;$failure=$null;$issued=$false;$result=$null;$closedButtonName=$null
    try{
        $owner=$bar
        $icon=Find-PtRunnerTrayControl -Target $owner -Query 'PowerToys v' -RunnerIcon
        if(-not $icon){
            $toggle=Find-PtRunnerTrayControl -Target $bar -Query $OverflowButtonName
            if(-not $toggle){throw 'Runner icon and hidden-icons control are unavailable; no preference was changed.'}
            $closedButtonName=$toggle.name
            Invoke-PtWinApp -Arguments @('invoke',$toggle.selector,'-w',"$($bar.hwnd)",'--action','invoke','--json')|Out-Null
            $overflow=Wait-PtCondition -Description 'the newly opened tray overflow' -TimeoutSeconds $TimeoutSeconds -Probe {
                $found=@(Get-PtRunnerTrayOverflow)
                if($found.Count -gt 1){throw 'Ambiguous new tray overflow.'}
                if($found.Count -eq 1){Get-PtWindowIdentity $found[0].Hwnd}
            }
            $owner=$overflow
            $icon=Wait-PtCondition -Description 'the exact PowerToys Runner icon, not Awake or a taskbar app button' `
                -TimeoutSeconds $TimeoutSeconds -Probe {
                    Find-PtRunnerTrayControl -Target $owner -Query 'PowerToys v' -RunnerIcon
                }
        }
        Assert-PtRunnerRestartIdentity $State.Runner
        $gesture=Invoke-PtRunnerTrayRightClick -Target $owner -Icon $icon
        $menu=Wait-PtCondition -Description 'one actual menu owned by the attested Runner' -TimeoutSeconds $TimeoutSeconds -Probe {
            $found=@(Get-PtNativeWindow -ProcessId $State.Runner.processId -ClassName '#32768' -Visible)
            if($found.Count -gt 1){throw 'Ambiguous Runner context menu.'}
            if($found.Count -eq 1){Get-PtWindowIdentity $found[0].Hwnd}
        }
        $id=switch($Command){'Exit'{'40001'} 'Settings'{'40002'} 'QuickAccess'{'40006'}}
        $item=Find-PtRunnerTrayControl -Target $menu -Query $id -Type MenuItem
        if(-not $item -or -not $item.isInvokable -or $item.automationId -cne $id){
            throw "The actual $Command menu item does not expose the expected Invoke operation."
        }
        Assert-PtRunnerRestartIdentity $State.Runner
        $result=[pscustomobject]@{Command=$Command;Runner=$State.Runner;IconName=$icon.name
            Menu=$menu;AutomationId=$id;Caption=$item.name;OverflowOpened=($null -ne $overflow);Gesture=$gesture}
        Invoke-PtWinApp -Arguments @('invoke',$item.selector,'-w',"$($menu.hwnd)",'--action','invoke','--json')|Out-Null
        $issued=$true
        if($Observe){$result|Add-Member NoteProperty Observation @(& $Observe $result @ObservationArguments)}
    }catch{$failure=$_}
    finally{
        try{
            if(-not $issued -and $menu -and [PtDesktop]::IsWindow([IntPtr][long]$menu.hwnd)){
                Assert-PtWindowIdentity $menu
                $foreground=Get-PtForegroundWindow
                if($foreground.ProcessId -ne $State.Runner.processId){throw 'Cannot safely cancel the owned menu after foreground changed.'}
                Send-PtChord -Key 0x1B|Out-Null
                Wait-PtCondition -Description 'owned Runner menu cancellation' -TimeoutSeconds $TimeoutSeconds -Probe {
                    @(Get-PtNativeWindow -ProcessId $State.Runner.processId -ClassName '#32768' -Visible).Count -eq 0
                }|Out-Null
            }
            if($overflow){
                $closed=Close-PtRunnerTrayOverflow -Taskbar $bar -Overflow $overflow -OverflowButtonName $OverflowButtonName -ClosedButtonName $closedButtonName -TimeoutSeconds $TimeoutSeconds
                if($result){$result|Add-Member NoteProperty OverflowCleanup $closed}
            }
        }catch{if($failure){$failure.Exception.Data['TrayCleanupFailure']=$_.Exception.Message}else{$failure=$_}}
        try{
            if(('PtTaskbarNative' -as [type]) -and ([PtTaskbarNative]::RightButtonDown() -or [PtTaskbarNative]::LeftButtonDown())){
                throw 'Mouse-button state remains held; refusing pointer restoration until release is resolved.'
            }
            Restore-PtPointerPosition $desktop.pointer|Out-Null
        }catch{if($failure){$failure.Exception.Data['TrayPointerCleanupFailure']=$_.Exception.Message}else{$failure=$_}}
    }
    if($failure){$failure.Exception.Data['TrayCommandReceipt']=$result;throw $failure}
    $result
}

function Get-PtRunnerShellLaunchTarget {
    <#.SYNOPSIS
    Resolve the installed Start menu shortcut before exit; never guess an installation or elevation.
    #>
    param([Parameter(Mandatory)]$State)
    if($State.Elevated){throw 'Normal tray restart currently requires a non-elevated Runner; use the real product restart action for elevation-sensitive coverage.'}
    $settings=Get-PtSettings
    if($null -eq $settings -or $settings.run_elevated -isnot [bool] -or $settings.run_elevated){
        throw 'Normal shortcut launch must not request elevation; inspect the actual startup preference before exit.'
    }
    $shell=New-Object -ComObject WScript.Shell
    try{
        $matches=@(foreach($root in @(
            (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'))){
            foreach($file in @(Get-ChildItem -LiteralPath $root -File -Filter '*PowerToys*.lnk' -Recurse -ErrorAction Stop)){
                $link=$shell.CreateShortcut($file.FullName)
                try{
                    if($link.TargetPath -ieq $State.Runner.path -and [string]::IsNullOrWhiteSpace($link.Arguments)){
                        $bytes=[IO.File]::ReadAllBytes($file.FullName)
                        if($bytes.Length -lt 76 -or [BitConverter]::ToUInt32($bytes,0) -ne 0x4C){
                            throw 'Installed shortcut has an invalid Shell Link header.'
                        }
                        if(([BitConverter]::ToUInt32($bytes,20) -band 0x2000) -ne 0){
                            throw 'Installed shortcut requests elevation; normal restart will not silently approve it.'
                        }
                        [pscustomobject]@{Shortcut=$file.FullName;Target=$link.TargetPath
                            Sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
                    }
                }finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}
            }
        })
    }finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
    if($matches.Count -ne 1){throw 'Exactly one installed no-argument PowerToys shortcut matching the attested executable is required before exit.'}
    $matches[0]
}

function Invoke-PtRunnerShellLaunch {
    param([Parameter(Mandatory)]$Target)
    if((Get-FileHash -LiteralPath $Target.Shortcut -Algorithm SHA256 -ErrorAction Stop).Hash -cne $Target.Sha256){
        throw 'Installed shortcut changed after preflight; no launch issued.'
    }
    $shell=New-Object -ComObject Shell.Application
    $folder=$null;$item=$null
    try{
        $folder=$shell.NameSpace([IO.Path]::GetDirectoryName($Target.Shortcut))
        if(-not $folder){throw 'Windows Shell could not resolve the installed shortcut folder.'}
        $item=$folder.ParseName([IO.Path]::GetFileName($Target.Shortcut))
        if(-not $item){throw 'Windows Shell could not resolve the attested shortcut.'}
        $item.InvokeVerb('open')
        [pscustomobject]@{Method='Windows Shell shortcut Open';Shortcut=$Target.Shortcut;Target=$Target.Target}
    }finally{
        foreach($value in @($item,$folder,$shell)){
            if($null -ne $value){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($value)}
        }
    }
}
