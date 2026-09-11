#requires -Version 7.0
<#
.SYNOPSIS
Record and restore PowerToys common WinUI shortcut controls through their shipped UI.
.NOTES
Does not activate modules, edit application JSON, use Reset, or infer product verdicts.
Caller owns Settings navigation/window lifetime and final desktop restoration.
#>
foreach($dependency in 'pt-uia','pt-state-snapshot','pt-foreground-guard','pt-sendinput-chord','pt-verification-report'){
    . "$PSScriptRoot\$dependency.ps1"
}

function Assert-PtShortcutBinding {
    param([Parameter(Mandatory)]$Binding)
    $names=@($Binding.PSObject.Properties.Name)
    if($Binding -is [Collections.IDictionary]){$names=@($Binding.Keys)}
    if(@($names|Where-Object {$_ -cnotin 'win','ctrl','alt','shift','code','key'}).Count){
        throw 'Unsupported shortcut fields; exact UI-only restoration cannot be guaranteed.'
    }
    if('key' -cnotin $names){throw 'Missing legacy key field; this adapter requires the complete six-field PowerToys binding schema.'}
    foreach($name in 'win','ctrl','alt','shift'){
        if($name -cnotin $names -or $Binding.$name -isnot [bool]){throw "Shortcut $name must be an explicit Boolean."}
    }
    if($Binding.code -isnot [int] -and $Binding.code -isnot [long]){throw 'Shortcut code must be an integer virtual-key code.'}
    if($Binding.code -lt 8 -or $Binding.code -gt 254 -or $Binding.code -in 0x10,0x11,0x12,0x5B,0x5C,0xA0,0xA1,0xA2,0xA3,0xA4,0xA5){
        throw 'Unsupported main key or empty shortcut; this adapter requires a restorable nonempty binding.'
    }
    if(-not ($Binding.win -or $Binding.ctrl -or $Binding.alt -or $Binding.shift)){throw 'A shortcut must include a modifier.'}
    if('key' -cin $names -and ($Binding.key -isnot [string] -or $Binding.key -cne '')){
        throw 'Nonempty/unknown legacy key fields are unsupported; do not normalize away original state.'
    }
    if(($Binding.win -and $Binding.code -in 0x4C,0x09) -or ($Binding.ctrl -and $Binding.alt -and $Binding.code -eq 0x2E) -or
        ($Binding.code -eq 0x09 -and -not ($Binding.win -or $Binding.ctrl -or $Binding.alt))){
        throw 'Reserved system/navigation shortcut is not safe to record through this adapter.'
    }
}

function ConvertTo-PtShortcutKey {
    param([Parameter(Mandatory)]$Binding)
    Assert-PtShortcutBinding $Binding
    $canonical=[ordered]@{win=$Binding.win;ctrl=$Binding.ctrl;alt=$Binding.alt;shift=$Binding.shift;code=[int]$Binding.code}
    $names=if($Binding -is [Collections.IDictionary]){@($Binding.Keys)}else{@($Binding.PSObject.Properties.Name)}
    if('key' -cin $names){$canonical.key=$Binding.key}
    ConvertTo-Json -InputObject $canonical -Compress
}

function Get-PtShortcutBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SettingsPath,[Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$PropertyPath)
    $value=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($SettingsPath))
    foreach($part in $PropertyPath){
        if([string]::IsNullOrEmpty($part) -or $part -cnotin @($value.PSObject.Properties.Name)){throw "Missing shortcut property segment: $part"}
        $value=$value.$part
    }
    Assert-PtShortcutBinding $value
    $value
}

function Get-PtShortcutKeyName {
    param([Parameter(Mandatory)][int]$Code,[Parameter(Mandatory)][long]$Hwnd)
    if(-not ('PtShortcutKeyNames' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class PtShortcutKeyNames {
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
    [DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint thread);
    [DllImport("user32.dll")] static extern uint MapVirtualKeyEx(uint code,uint mode,IntPtr layout);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern int GetKeyNameText(int parameter,StringBuilder text,int length);
    public static string Name(int code,long hwnd) {
        uint pid;
        uint thread=GetWindowThreadProcessId(new IntPtr(hwnd),out pid);
        if(thread==0) throw new Win32Exception(1400);
        uint scan=MapVirtualKeyEx((uint)code,4,GetKeyboardLayout(thread));
        if(scan==0) throw new InvalidOperationException("Virtual key has no mapped scan code.");
        int parameter=(int)((scan & 0xFF)<<16);
        if((scan & 0xFF00)!=0) parameter|=1<<24;
        var text=new StringBuilder(128);
        if(GetKeyNameText(parameter,text,text.Capacity)==0) throw new Win32Exception();
        return text.ToString();
    }
}
'@
    }
    [PtShortcutKeyNames]::Name($Code,$Hwnd)
}

function Get-PtShortcutDisplay {
    param($Binding,[long]$Hwnd,[switch]$Dialog)
    $keys=@(
        if($Binding.win -and -not $Dialog){'Win'}
        if($Binding.ctrl){'Ctrl'}
        if($Binding.alt){'Alt'}
        if($Binding.shift){'Shift'}
        Get-PtShortcutKeyName $Binding.code $Hwnd
    )
    if($Dialog){$keys}else{$keys -join ' + '}
}

function Get-PtShortcutEditor {
    param($Snapshot)
    Assert-PtWindowIdentity $Snapshot.Identity
    $native=Get-PtNativeWindow -Hwnd $Snapshot.Identity.hwnd
    if(-not $native.Visible -or $native.Minimized){throw 'Settings must be explicitly visible and not minimized.'}
    $page=Resolve-PtUiElement -Hwnd $Snapshot.Identity.hwnd -AutomationId $Snapshot.PageAutomationId -ControlType ListItem
    if(-not $page.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected){
        throw 'The expected Settings page is not selected; no shortcut control was changed.'
    }
    $button=Resolve-PtUiElement -Hwnd $Snapshot.Identity.hwnd -AutomationId $Snapshot.AutomationId -ControlType Button -WithinAutomationId $Snapshot.WithinAutomationId
    if(-not $button.Current.IsEnabled -or $button.Current.IsOffscreen){throw 'Shortcut edit control is disabled or offscreen.'}
    $button
}

function Save-PtShortcutSnapshot {
    param($Snapshot)
    Assert-PtShortcutSnapshot $Snapshot
    $temporary=Join-Path $Snapshot.Workspace "shortcut-write-$([Guid]::NewGuid().ToString('N')).tmp"
    try{
        Write-PtReportText $temporary (ConvertTo-Json -InputObject $Snapshot -Depth 15)
        [IO.File]::Move($temporary,$Snapshot.ReceiptPath,$true)
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Assert-PtShortcutSnapshot {
    param($Snapshot)
    if($Snapshot.Schema -cne 'PtShortcut.v1' -or
        [IO.Path]::GetFileName($Snapshot.ReceiptPath) -cnotmatch '^shortcut-[a-f0-9]{32}\.json$' -or
        [IO.Path]::GetDirectoryName($Snapshot.ReceiptPath) -ine $Snapshot.Workspace){
        throw 'Invalid shortcut ownership receipt.'
    }
    Assert-PtReportNoLink $Snapshot.ReceiptPath
    $saved=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($Snapshot.ReceiptPath))
    if((ConvertTo-PtShortcutKey $saved.Original) -cne (ConvertTo-PtShortcutKey $Snapshot.Original) -or
        $saved.SettingsPath -cne $Snapshot.SettingsPath -or ($saved.PropertyPath -join "`0") -cne ($Snapshot.PropertyPath -join "`0") -or
        $saved.PageAutomationId -cne $Snapshot.PageAutomationId -or $saved.AutomationId -cne $Snapshot.AutomationId -or
        $saved.WithinAutomationId -cne $Snapshot.WithinAutomationId -or $saved.OriginalHelpText -cne $Snapshot.OriginalHelpText -or
        (ConvertTo-Json $saved.Identity -Compress) -cne (ConvertTo-Json $Snapshot.Identity -Compress)){
        throw 'Shortcut baseline/target differs from the persisted receipt; do not mutate Original to construct a new chord.'
    }
}

function Get-PtShortcutSnapshot {
    <# .SYNOPSIS
    Persist original fields and exact control/window identity before editing a shortcut.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][long]$Hwnd,[Parameter(Mandatory)][string]$PageAutomationId,
        [Parameter(Mandatory)][string]$SettingsPath,[Parameter(Mandatory)][string[]]$PropertyPath,
        [Parameter(Mandatory)][string]$Workspace,[string]$AutomationId='EditButton',[string]$WithinAutomationId)
    Initialize-PtUiAutomation
    $directory=(Get-Item -LiteralPath $Workspace -ErrorAction Stop).FullName
    if(-not [IO.Directory]::Exists($directory)){throw 'Shortcut receipts require an existing workspace directory.'}
    Assert-PtReportNoLink $directory
    $binding=Get-PtShortcutBinding $SettingsPath $PropertyPath
    $snapshot=[pscustomobject]@{
        Schema='PtShortcut.v1';Workspace=$directory;Identity=Get-PtWindowIdentity $Hwnd;PageAutomationId=$PageAutomationId
        SettingsPath=[IO.Path]::GetFullPath($SettingsPath);PropertyPath=@($PropertyPath)
        AutomationId=$AutomationId;WithinAutomationId=$WithinAutomationId
        Original=$binding;ExpectedCurrent=$binding;OriginalHelpText=''
        ReceiptPath=Join-Path $directory "shortcut-$([Guid]::NewGuid().ToString('N')).json"
    }
    $editor=Get-PtShortcutEditor $snapshot
    $snapshot.OriginalHelpText=$editor.Current.HelpText
    if($snapshot.OriginalHelpText -ine (Get-PtShortcutDisplay $binding $Hwnd)){
        throw 'Editor HelpText does not match the supplied settings binding; target/schema/layout pairing is unverified.'
    }
    Write-PtReportText $snapshot.ReceiptPath (ConvertTo-Json -InputObject $snapshot -Depth 15)
    $snapshot
}

function Get-PtShortcutDialogButton {
    param($Dialog,[string]$AutomationId)
    $condition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,$AutomationId)
    Select-PtUniqueUiElement -Elements @($Dialog.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)) -Description "owned shortcut dialog $AutomationId"
}

function Find-PtShortcutDialog {
    param($Snapshot,[string]$EditorName)
    $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$Snapshot.Identity.hwnd)
    $condition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'PrimaryButton')
    $buttons=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)|Where-Object{-not $_.Current.IsOffscreen})
    if(-not $buttons.Count){return $null}
    $save=Select-PtUniqueUiElement -Elements $buttons -Description 'visible dialog save button'
    $walker=[Windows.Automation.TreeWalker]::RawViewWalker
    $dialog=$save
    while($dialog -and $dialog.Current.ControlType -ne [Windows.Automation.ControlType]::Window){$dialog=$walker.GetParent($dialog)}
    if(-not $dialog -or $dialog.Current.ClassName -cne 'Popup' -or $dialog.Current.Name -cne $EditorName){
        throw 'Unexpected dialog provider/name; refusing to treat it as a shortcut recorder.'
    }
    $null=Get-PtShortcutDialogButton $dialog CloseButton
    $null=Get-PtShortcutDialogButton $dialog ResetBtn
    $dialog
}

function Get-PtShortcutDialogKeys {
    param($Dialog)
    $scroll=Get-PtShortcutDialogButton $Dialog ContentScrollViewer
    $walker=[Windows.Automation.TreeWalker]::RawViewWalker
    $node=$walker.GetFirstChild($scroll)
    $keys=[Collections.Generic.List[string]]::new()
    $visited=[Collections.Generic.HashSet[string]]::new()
    while($node){
        $id=@($node.GetRuntimeId()) -join ','
        if(-not $visited.Add($id) -or $visited.Count -gt 64){throw 'Unexpected/cyclic shortcut dialog subtree.'}
        $name=$node.Current.Name
        if($node.Current.ClassName -eq 'TextBlock' -and $name -and $name -cne $Dialog.Current.Name){
            if($name -ceq [string][char]0xE752){$name='Shift'}
            $keys.Add($name)
        }
        $node=$walker.GetNextSibling($node)
    }
    $keys.ToArray()
}

function Close-PtShortcutDialog {
    param($Snapshot,$Dialog)
    Assert-PtWindowIdentity $Snapshot.Identity
    try {$null=$Dialog.Current.Name}
    catch [Windows.Automation.ElementNotAvailableException] {return}
    if($Dialog.Current.IsOffscreen){return}
    (Get-PtShortcutDialogButton $Dialog CloseButton).GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
    Wait-PtCondition -Description 'owned shortcut dialog cancellation' -TimeoutSeconds 3 -Probe {
        try {$Dialog.Current.IsOffscreen}
        catch [Windows.Automation.ElementNotAvailableException] {$true}
    }|Out-Null
}

function Assert-PtShortcutInputIdle {
    foreach($key in 0x5B,0x5C,0x10,0x11,0x12,0xA0,0xA1,0xA2,0xA3,0xA4,0xA5){
        if(([PtChord]::GetAsyncKeyState($key) -band 0x8000) -ne 0){throw "Modifier $key is already held; recorder input is refused without releasing it."}
    }
}

function Set-PtShortcutBinding {
    <#
    .SYNOPSIS
    Prove recorder readiness with a safe modifier, capture a chord, then Save or Cancel.
    .NOTES
    CapturedObserver is read-only and receives the captured facts before commit.
    Failure before commit cancels the owned dialog. Always pair with Restore-PtShortcutSnapshot.
    Windows key artwork is absent from this provider's UIA tree: complete Win/modifier
    verification uses the saved edit-button HelpText AND every persisted binding field.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)]$Binding,
        [ValidateSet('Save','Cancel')][string]$Mode='Save',[ValidateRange(1,15)][int]$TimeoutSeconds=5,
        [scriptblock]$CapturedObserver,[object[]]$ObserverArgumentList=@())
    Assert-PtShortcutBinding $Binding
    Assert-PtShortcutSnapshot $Snapshot
    $desired=ConvertFrom-PtReportJson (ConvertTo-PtShortcutKey $Binding)
    $shortcutObserver=$CapturedObserver
    $shortcutObserverArguments=$ObserverArgumentList
    $drive={
        param($target,$requested,$commitMode,$timeout)
        $before=Get-PtShortcutBinding $target.SettingsPath $target.PropertyPath
        if((ConvertTo-PtShortcutKey $before) -cne (ConvertTo-PtShortcutKey $target.ExpectedCurrent)){
            throw 'Shortcut changed outside this transaction; refusing to overwrite concurrent state.'
        }
        $editor=Get-PtShortcutEditor $target
        if($editor.Current.HelpText -ine (Get-PtShortcutDisplay $before $target.Identity.hwnd)){throw 'Current UI and settings binding disagree.'}
        $result=[pscustomobject]@{Before=$before;Requested=$requested;Mode=$commitMode;Changed=$false;Actual=$before
            DialogKeys=@();DialogWindowsArtworkObservable=$false;HelpText=$editor.Current.HelpText;Receipt=$target.ReceiptPath}
        if(Find-PtShortcutDialog $target $editor.Current.Name){throw 'A dialog already exists; it is not owned by this edit operation.'}
        if($commitMode -eq 'Save' -and (ConvertTo-PtShortcutKey $before) -ceq (ConvertTo-PtShortcutKey $requested)){return $result}
        Assert-PtShortcutInputIdle
        $dialog=$null;$originalError=$null
        try{
            Assert-PtForegroundOrAbort -Hwnd $target.Identity.hwnd
            $editor.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
            $dialog=Wait-PtCondition -Description 'owned shortcut recorder' -TimeoutSeconds $timeout -Probe {
                Find-PtShortcutDialog $target $editor.Current.Name
            }
            Invoke-PtHeldKeys -Hwnd $target.Identity.hwnd -Keys @(0x11) -KeyDownDelayMilliseconds 0 -Action {
                Wait-PtCondition -Description 'recorder hook acknowledges Ctrl before main-key input' -TimeoutSeconds $timeout -Probe {
                    $keys=@(Get-PtShortcutDialogKeys $dialog)
                    $keys.Count -eq 1 -and $keys[0] -ceq 'Ctrl' -and -not (Get-PtShortcutDialogButton $dialog PrimaryButton).Current.IsEnabled
                }|Out-Null
            }
            Assert-PtShortcutInputIdle
            $modifiers=@(if($requested.win){0x5B};if($requested.ctrl){0x11};if($requested.alt){0x12};if($requested.shift){0x10})
            $expected=@(Get-PtShortcutDisplay $requested $target.Identity.hwnd -Dialog)
            Invoke-PtHeldKeys -Hwnd $target.Identity.hwnd -Keys $modifiers -KeyDownDelayMilliseconds 0 -Action {
                Send-PtChord -Hwnd $target.Identity.hwnd -Key $requested.code|Out-Null
                Wait-PtCondition -Description 'captured shortcut key labels and enabled Save' -TimeoutSeconds $timeout -Probe {
                    $keys=@(Get-PtShortcutDialogKeys $dialog)
                    ($keys -join '|') -ieq ($expected -join '|') -and (Get-PtShortcutDialogButton $dialog PrimaryButton).Current.IsEnabled
                }|Out-Null
            }
            $result.DialogKeys=@(Get-PtShortcutDialogKeys $dialog)
            if($shortcutObserver){
                $observerFacts=ConvertFrom-PtReportJson (ConvertTo-Json -InputObject $result -Depth 15)
                $active=Get-PtActiveVerificationAttempt
                if($active){
                    Invoke-PtVerificationStep $active -Name 'Observe captured shortcut before commit' -Command 'Read captured facts through the supplied observer' `
                        -Action $shortcutObserver -ArgumentList (@($observerFacts)+$shortcutObserverArguments)|Out-Null
                }else{& $shortcutObserver $observerFacts @shortcutObserverArguments|Out-Null}
            }
            if($commitMode -eq 'Save'){
                if((@(Get-PtShortcutDialogKeys $dialog) -join '|') -ine ($expected -join '|')){throw 'Captured shortcut changed before commit.'}
                if((ConvertTo-PtShortcutKey (Get-PtShortcutBinding $target.SettingsPath $target.PropertyPath)) -cne (ConvertTo-PtShortcutKey $before)){
                    throw 'Persisted shortcut changed while the recorder was open; commit refused.'
                }
                Assert-PtShortcutInputIdle
                $target.ExpectedCurrent=$requested
                Save-PtShortcutSnapshot $target
                (Get-PtShortcutDialogButton $dialog PrimaryButton).GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
                $after=Wait-PtCondition -Description 'exact persisted shortcut and complete UI HelpText' -TimeoutSeconds $timeout -Probe {
                    $actual=Get-PtShortcutBinding $target.SettingsPath $target.PropertyPath
                    $button=Get-PtShortcutEditor $target
                    if((ConvertTo-PtShortcutKey $actual) -ceq (ConvertTo-PtShortcutKey $requested) -and
                        $button.Current.HelpText -ieq (Get-PtShortcutDisplay $requested $target.Identity.hwnd)){
                        [pscustomobject]@{Binding=$actual;HelpText=$button.Current.HelpText}
                    }
                }
                $result.Actual=$after.Binding;$result.HelpText=$after.HelpText;$result.Changed=$true
            }
        }catch{$originalError=$_;$originalError.Exception.Data['ShortcutReceipt']=$target.ReceiptPath;throw}
        finally{
            if($dialog){
                try {Close-PtShortcutDialog $target $dialog}
                catch {
                    if($originalError){$originalError.Exception.Data['ShortcutDialogCleanupFailure']=$_.Exception.Message;[Console]::Error.WriteLine($_.Exception.Message)}
                    else{throw}
                }
            }
        }
        if($commitMode -eq 'Cancel'){
            $actual=Get-PtShortcutBinding $target.SettingsPath $target.PropertyPath
            if((ConvertTo-PtShortcutKey $actual) -cne (ConvertTo-PtShortcutKey $before)){throw 'Cancellation changed persisted shortcut fields.'}
            $result.Actual=$actual
            $result.HelpText=(Get-PtShortcutEditor $target).Current.HelpText
            if($result.HelpText -ine (Get-PtShortcutDisplay $before $target.Identity.hwnd)){throw 'Cancellation did not restore the original displayed shortcut.'}
        }
        $result
    }
    $attempt=Get-PtActiveVerificationAttempt
    if($attempt){
        $snapshotText=(ConvertTo-Json -InputObject $Snapshot -Depth 15 -Compress).Replace("'","''")
        $bindingText=(ConvertTo-PtShortcutKey $desired).Replace("'","''")
        Invoke-PtVerificationStep $attempt -Name 'Edit scoped shortcut binding' `
            -Command "Set-PtShortcutBinding -Snapshot (ConvertFrom-PtReportJson '$snapshotText') -Binding (ConvertFrom-PtReportJson '$bindingText') -Mode $Mode -TimeoutSeconds $TimeoutSeconds # Optional observer source/arguments are retained in its nested step." `
            -Implementation ${function:Set-PtShortcutBinding} -Action $drive -ArgumentList @($Snapshot,$desired,$Mode,$TimeoutSeconds)
    }else{& $drive $Snapshot $desired $Mode $TimeoutSeconds}
}

function Restore-PtShortcutSnapshot {
    <# .SYNOPSIS
    Restore the captured original chord through UI; never assume Reset means factory defaults.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot)
    $current=Get-PtShortcutBinding $Snapshot.SettingsPath $Snapshot.PropertyPath
    if((ConvertTo-PtShortcutKey $current) -ceq (ConvertTo-PtShortcutKey $Snapshot.Original)){
        $Snapshot.ExpectedCurrent=$current
    }
    $result=Set-PtShortcutBinding -Snapshot $Snapshot -Binding $Snapshot.Original
    if($result.HelpText -cne $Snapshot.OriginalHelpText){throw 'Original shortcut fields match but original UI HelpText was not restored.'}
    Save-PtShortcutSnapshot $Snapshot
    $result
}
