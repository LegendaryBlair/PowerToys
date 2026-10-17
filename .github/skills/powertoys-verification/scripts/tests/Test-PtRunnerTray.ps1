#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-tray-contract-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-state.ps1"
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Require($condition,$message){if(-not $condition){throw $message}}
function Reject([scriptblock]$body,[string]$pattern){
    try{& $body|Out-Null}catch{if($_.Exception.Message -notmatch $pattern){throw};return}
    throw "Expected rejection: $pattern"
}
function Check($name,[scriptblock]$body){
    $script:f=@{Overflow=$false;Menu=$false;Pinned=$false;Incomplete=$false;Ambiguous=$false;WrongId=$false;Exit=0;Clicks=0;Pointer=0;Commands=@()}
    & $body
    $results.Add(@{Name=$name;Status='PASS'})
}
function Assert-PtRunnerRestartIdentity {param($Expected)}
function Assert-PtWindowIdentity {param($Identity)}
function Get-PtWindowIdentity {
    param($Hwnd)
    [pscustomobject]@{hwnd=$Hwnd;processId=$(if($Hwnd -eq 70){10}else{20});processStartTicks=100L
        className=$(switch($Hwnd){50{'Shell_TrayWnd'} 60{'TopLevelWindowForOverflowXamlIsland'} 70{'#32768'}})}
}
function Get-PtNativeWindow {
    param($ProcessId,$ClassName,$Hwnd,[switch]$Visible)
    if($Hwnd -eq 60){return [pscustomobject]@{Hwnd=60;Visible=$f.Overflow}}
    if($ClassName -eq 'Shell_TrayWnd'){return [pscustomobject]@{Hwnd=50;Visible=$true}}
    if($ClassName -eq 'TopLevelWindowForOverflowXamlIsland' -and $f.Overflow){return [pscustomobject]@{Hwnd=60;Visible=$true}}
    if($ClassName -eq '#32768' -and $f.Menu){return [pscustomobject]@{Hwnd=70;Visible=$true}}
}
function Test-PtWindowCloaked {param($Hwnd) $false}
function Get-PtDesktopSnapshot {[pscustomobject]@{pointer=@{X=1;Y=2}}}
function Restore-PtPointerPosition {param($Point) $f.Pointer++}
function Get-PtForegroundWindow {[pscustomobject]@{Hwnd=50}}
function Send-PtChord {param($Key) Require ($Key -eq 0x1B) 'Unexpected dismissal key';$f.Overflow=$false;$f.Menu=$false}
function Invoke-PtRunnerTrayRightClick {
    param($Target,$Icon)
    Require ($Icon.name -ceq 'PowerToys v0.102.2862') 'Wrong icon'
    $f.Clicks++;$f.Menu=$true
    [pscustomobject]@{Method='synthetic guarded right-click';Target=$Target}
}
function Invoke-PtRunnerOverflowDismissClick {
    param($Taskbar,$Overflow,$ClosedButtonName)
    Require ($ClosedButtonName -ceq 'Localized hidden icons') 'Actual closed caption was not retained'
    $f.DismissCalls++
    if($f.DismissFailure){throw 'Injected popup dismissal failure'}
    if($f.CloseBeforePress){$f.Overflow=$false}
    $pressed=$f.Overflow
    $f.Overflow=$false;$f.Menu=$false
    [pscustomobject]@{Pressed=$pressed}
}
function Invoke-PtWinApp {
    param($Arguments,[switch]$AllowNoMatches)
    $f.Commands+=@(($Arguments -join '|'))
    $hwndValue=$Arguments[[array]::IndexOf($Arguments,'-w')+1]
    if($Arguments[0] -eq 'search'){
        $matches=@()
        $query=$Arguments[1]
        if($query -eq 'PowerToys v' -and ($hwndValue -eq '60' -or $f.Pinned)){
            $matches=@(
                @{name='PowerToys Awake';selector='awake';automationId='NotifyItemIcon';isEnabled=$true;isOffscreen=$false;width=80;height=80},
                @{name='PowerToys v0.102.2862';selector='runner';automationId='NotifyItemIcon';isEnabled=$true;isOffscreen=$false;width=80;height=80})
            if($f.Ambiguous){$matches+=@(@{name='PowerToys v0.102.2863';selector='other'})}
        }elseif($query -eq 'Show Hidden Icons'){
            $matches=@(@{name='Localized hidden icons';selector='overflow';automationId='SystemTrayIcon';isEnabled=$true;isOffscreen=$false;width=80;height=80})
        }elseif($hwndValue -eq '70'){
            $matches=@(@{name='Localized Close';selector=$query;automationId=$(if($f.WrongId){'40002'}else{$query})
                isEnabled=$true;isOffscreen=$false;isInvokable=$true;width=80;height=40})
        }
        return ConvertTo-Json @{matchCount=$matches.Count;hasMore=$f.Incomplete;matches=$matches} -Depth 5
    }
    if($Arguments[0] -eq 'click'){
        Require ($Arguments[1] -ceq 'PowerToys v0.102.2862' -and $Arguments -contains '--right') 'Wrong icon or wrong gesture'
        $f.Clicks++;$f.Menu=$true
    }elseif($Arguments[0] -eq 'invoke'){
        Require ($Arguments -contains '--action' -and $Arguments -contains 'invoke') 'Implicit action fallback requested'
        if($Arguments[1] -eq 'Localized hidden icons'){$f.Overflow=-not $f.Overflow}
        elseif($Arguments[1] -in '40001','40002','40006'){
            if($Arguments[1] -eq '40001'){$f.Exit++}
            $f.Menu=$false
        }
    }
    '{}'
}
$state=@{Runner=@{processId=10;processStartTicks=100L;path='C:\fixture\PowerToys.exe'}}
Check 'Overflow icon path invokes the actual localized Close item once and cleans overflow/pointer' {
    $receipt=Invoke-PtRunnerTrayCommand $state Exit
    Require ($receipt.AutomationId -ceq '40001' -and $receipt.Caption -ceq 'Localized Close') 'Exit localization/identity lost'
    Require ($f.Exit -eq 1 -and $f.Clicks -eq 1 -and -not $f.Overflow -and $f.Pointer -eq 1) 'Action replay or popup leak'
    Require (@($f.Commands|Where-Object {$_ -match '--class-name\\|SystemTray.NormalButton'}).Count -gt 0) 'Taskbar app buttons were not excluded'
}
Check 'Visible Runner icon does not open hidden icons' {
    $f.Pinned=$true
    $receipt=Invoke-PtRunnerTrayCommand $state Exit
    Require (-not $receipt.OverflowOpened -and @($f.Commands|Where-Object {$_ -like '*Show Hidden Icons*'}).Count -eq 0) 'Unnecessary overflow interaction'
}
Check 'Ephemeral target observation runs before overflow dismissal' {
    $receipt=Invoke-PtRunnerTrayCommand $state QuickAccess -Observe {
        param($receipt)
        Require $f.Overflow 'Overflow was dismissed before the target could be observed'
        [pscustomobject]@{Observed=$true}
    }
    Require ($receipt.Observation[0].Observed -and -not $f.Overflow) 'Observation or subsequent owned-popup cleanup was lost'
}
Check 'Cleanup honors the gesture adapter reporting closure before input' {
    $f.CloseBeforePress=$true
    $receipt=Invoke-PtRunnerTrayCommand $state Exit
    Require ($receipt.OverflowCleanup.Hidden -and -not $f.Overflow) 'Cleanup reopened the popup'
    Require (-not $receipt.OverflowCleanup.Gesture.Pressed) 'Already closed popup received input'
    Require (@($f.Commands|Where-Object {$_ -like 'invoke|Localized hidden icons|*'}).Count -eq 1) 'Cleanup used an unconditional second UIA toggle'
}
Check 'An already hidden popup skips the dismissal gesture' {
    $receipt=Invoke-PtRunnerTrayCommand $state Exit -Observe {$f.Overflow=$false}
    Require ($receipt.OverflowCleanup.AlreadyHidden -and -not $f.DismissCalls) 'Already hidden popup was driven'
}
Check 'Popup cleanup failure retains the issued command and still restores the pointer' {
    $f.DismissFailure=$true
    try{Invoke-PtRunnerTrayCommand $state Exit|Out-Null;throw 'Expected failure'}
    catch{
        Require ($_.Exception.Message -match 'Injected popup dismissal failure') 'Original cleanup error was lost'
        Require ($_.Exception.Data['TrayCommandReceipt'].AutomationId -ceq '40001') 'Issued command receipt was lost'
    }
    Require ($f.Exit -eq 1 -and $f.Pointer -eq 1) 'Failed cleanup replayed Exit or skipped independent pointer cleanup'
}
Check 'Pre-existing overflow and menus are not adopted or dismissed' {
    $f.Overflow=$true
    Reject {Invoke-PtRunnerTrayCommand $state Exit} 'existing tray menu'
    Require ($f.Overflow -and $f.Commands.Count -eq 0) 'Borrowed overflow was touched'
    $f.Overflow=$false;$f.Menu=$true
    Reject {Invoke-PtRunnerTrayCommand $state Exit} 'existing tray menu'
}
Check 'Incomplete queries and duplicate Runner icons refuse destructive action' {
    $f.Incomplete=$true
    Reject {Invoke-PtRunnerTrayCommand $state Exit} 'incomplete'
    Require ($f.Exit -eq 0) 'Incomplete query invoked Exit'
    $f.Incomplete=$false;$f.Pinned=$true;$f.Ambiguous=$true
    Reject {Invoke-PtRunnerTrayCommand $state Exit} 'Ambiguous tray control'
    Require ($f.Clicks -eq 0) 'Ambiguous icon was clicked'
}
Check 'An unexpected menu command ID cannot substitute for Exit' {
    $f.WrongId=$true
    Reject {Invoke-PtRunnerTrayCommand $state Exit} 'expected Invoke operation'
    Require ($f.Exit -eq 0) 'Wrong menu command was invoked'
}
Write-PtReportText "$Workspace\results.json" (ConvertTo-Json $results -Depth 5)
"PASS: $($results.Count) tray protocol groups; no real desktop actions. $Workspace"
