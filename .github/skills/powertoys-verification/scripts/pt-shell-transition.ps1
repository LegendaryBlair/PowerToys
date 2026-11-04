#requires -Version 7.2
. "$PSScriptRoot\pt-desktop.ps1"
. "$PSScriptRoot\pt-state-snapshot.ps1"
. "$PSScriptRoot\pt-foreground-guard.ps1"
. "$PSScriptRoot\pt-sendinput-chord.ps1"

function Get-PtTaskViewSurface {
    param([Parameter(Mandatory)][string]$Title)
    $windows=@(Get-PtNativeWindow -Visible)
    try {
        $foreground=Get-PtForegroundWindow
        if($foreground.Hwnd -notin @($windows.Hwnd)){$windows+=@($foreground)}
    } catch {
        if($_.Exception.Data['PtDesktopStatus'] -cne 'NoForeground'){throw}
    }
    foreach($window in $windows){
        if($window.ClassName -cnotin @('MultitaskingViewFrame','XamlExplorerHostIslandWindow') -or
            $window.Title -cne $Title){continue}
        $process=Get-PtResourceProcessIdentity $window.ProcessId
        if($process.path -ine (Join-Path $env:WINDIR 'explorer.exe')){continue}
        Get-PtWindowIdentity $window.Hwnd
    }
}

function Close-PtTaskViewTransition {
    <#.SYNOPSIS
    Dismiss only an exactly identified test-opened Task View, including normal destruction.
    #>
    param([Parameter(Mandatory)]$Transition,[ValidateRange(0.1,30)][double]$TimeoutSeconds=5)
    if($Transition.State -ceq 'NotOpened'){return}
    if($Transition.State -ceq 'Closed'){return}
    if($Transition.State -cne 'Opened' -or -not $Transition.Surface){
        throw 'Task View transition ownership is unresolved; no closing input sent.'
    }
    if(-not(Test-PtTrackedWindowClosed $Transition.Surface -AllowHidden)){
        Assert-PtWindowIdentity $Transition.Surface
        $matching=@(Get-PtTaskViewSurface -Title $Transition.Title|Where-Object hwnd -EQ $Transition.Surface.hwnd)
        if($matching.Count -ne 1){
            if(Test-PtTrackedWindowClosed $Transition.Surface -AllowHidden){$Transition.State='Closed';return}
            throw 'The tracked Shell surface no longer identifies Task View; no Escape sent.'
        }
        $foreground=Get-PtForegroundWindow
        if($foreground.Hwnd -ne $Transition.Surface.hwnd){
            throw 'The test-opened Task View is no longer foreground; no Escape sent elsewhere.'
        }
        Send-PtChord -Hwnd $Transition.Surface.hwnd -Key 0x1B|Out-Null
        Wait-PtTrackedWindowClosed -Identity $Transition.Surface -AllowHidden -TimeoutSeconds $TimeoutSeconds
    }
    $Transition.State='Closed'
}

function Invoke-PtTaskViewScope {
    <#
    .SYNOPSIS
    Open an initially absent Task View over a tracked fixture and restore the transition.
    .NOTES
    Title is the actual localized Task View caption, not an arbitrary Shell class exemption.
    Transition is assigned before input and retained on failure for the caller's cleanup.
    Desktop creation/pinning and their restoration are separate caller-owned operations.
    #>
    param(
        [Parameter(Mandatory)]$TargetIdentity,
        [Parameter(Mandatory)][ref]$Transition,
        [Parameter(Mandatory)][scriptblock]$Action,
        [object[]]$ArgumentList=@(),
        [string]$Title='Task View',
        [ValidateRange(0.1,30)][double]$TimeoutSeconds=5
    )
    if($Transition.Value -and $Transition.Value.State -cnotin @('NotOpened','Closed')){
        throw 'An earlier Task View transition remains unresolved.'
    }
    Assert-PtWindowIdentity $TargetIdentity
    if(@(Get-PtTaskViewSurface -Title $Title).Count){throw 'Task View already exists; do not adopt or dismiss it.'}
    $state=[pscustomobject]@{State='NotOpened';Target=$TargetIdentity;Surface=$null;Title=$Title}
    $Transition.Value=$state
    $failure=$null
    try {
        Assert-PtForegroundOrAbort -Hwnd $TargetIdentity.hwnd
        $state.State='Opening'
        Send-PtChord -Hwnd $TargetIdentity.hwnd -Mods @(0x5B) -Key 0x09|Out-Null
        $surface=Wait-PtCondition -Description 'new foreground Task View identity' -TimeoutSeconds $TimeoutSeconds -Probe {
            $found=@(Get-PtTaskViewSurface -Title $Title)
            if($found.Count -gt 1){throw 'Ambiguous Task View surface; no ownership inferred.'}
            if($found.Count -eq 1){
                try{$foreground=Get-PtForegroundWindow}catch{
                    if($_.Exception.Data['PtDesktopStatus'] -ceq 'NoForeground'){return $null}
                    throw
                }
                if($foreground.Hwnd -eq $found[0].hwnd){$found[0]}
            }
        }
        $state.Surface=$surface
        $state.State='Opened'
        & $Action $surface @ArgumentList
    } catch {$failure=$_;throw}
    finally {
        try {
            Close-PtTaskViewTransition -Transition $state -TimeoutSeconds $TimeoutSeconds
            Assert-PtWindowIdentity $TargetIdentity
            Assert-PtForegroundOrAbort -Hwnd $TargetIdentity.hwnd
        } catch {
            if($failure){$failure.Exception.Data['TaskViewCleanupFailure']=$_.Exception.Message}
            else{throw}
        }
    }
}
