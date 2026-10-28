#requires -Version 7.2
foreach($dependency in 'pt-uia','pt-foreground-guard','pt-sendinput-chord'){. "$PSScriptRoot\$dependency.ps1"}

function Invoke-PtQuickAccentGesture {
    <#
    .SYNOPSIS
    Hold a base letter during Quick Accent observations using the shared input lifetime.
    .NOTES
    Run inside a recorded case. The caller owns the editor and its text, file and usage baselines.
    No activation, foreground change, readiness verdict or automatic retry is inferred.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(1,[long]::MaxValue)][long]$WindowHandle,
        [Parameter(Mandatory)][ValidateRange(1,254)][uint16]$KeyCode,
        [ValidateRange(0,254)][uint16]$TriggerCode=0,
        [uint16[]]$Modifiers=@(),
        [ValidateRange(0,10000)][int]$DelayMs=1000,
        [Parameter(Mandatory)][scriptblock]$Observe,
        [object[]]$ArgumentList=@()
    )
    $target=Get-PtWindowIdentity $WindowHandle
    if(-not(Test-PtForeground -Hwnd $WindowHandle)){throw 'The exact owned editor must already be foreground.'}
    $keys=@($Modifiers)+@($KeyCode)
    if($TriggerCode){$keys+=@($TriggerCode)}
    if(@($keys|Select-Object -Unique).Count -ne $keys.Count -or
        @($keys|Where-Object {$_ -lt 1 -or $_ -gt 254}).Count){throw 'Gesture keys must be distinct virtual-key codes in 1..254.'}
    foreach($key in $keys){
        if(([PtChord]::GetAsyncKeyState($key) -band 0x8000) -ne 0){throw "Key $key is already held; no gesture issued."}
    }
    Invoke-PtHeldKeys -Keys @($Modifiers+$KeyCode) -KeyDownDelayMilliseconds 0 -Action {
        Assert-PtWindowIdentity $target
        if(-not(Test-PtForeground -Hwnd $WindowHandle)){throw 'Editor lost foreground before the trigger; no trigger issued.'}
        if($TriggerCode){Send-PtChord -Key $TriggerCode|Out-Null}
        if($DelayMs){Start-Sleep -Milliseconds $DelayMs}
        Assert-PtWindowIdentity $target
        & $Observe $target @ArgumentList
    }
}

function Get-PtQuickAccentDialogControl {
    param([Parameter(Mandatory)]$Target,[Parameter(Mandatory)][string]$AutomationId,
        [Parameter(Mandatory)][string]$ControlType,[switch]$Optional)
    Assert-PtWindowIdentity $Target
    try{Resolve-PtUiElement -Hwnd $Target.hwnd -AutomationId $AutomationId -ControlType $ControlType}
    catch{
        if($Optional -and $_.Exception.Data['PtUiResolutionStatus'] -ceq 'Missing'){return}
        throw
    }
}

function Invoke-PtQuickAccentCharacterDialog {
    <#
    .SYNOPSIS
    Open one character-set draft, then cancel only that same draft if the callback leaves it open.
    .NOTES
    Run inside a recorded case with a captured Settings baseline. The callback receives the owned
    search control and Settings identity; scope its actions to that dialog. Provider errors propagate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(1,[long]::MaxValue)][long]$WindowHandle,
        [Parameter(Mandatory)][string]$ManageButtonName,
        [Parameter(Mandatory)][scriptblock]$Action,
        [object[]]$ArgumentList=@(),
        [ValidateRange(0.1,30)][double]$TimeoutSeconds=5
    )
    Initialize-PtUiAutomation
    $target=Get-PtWindowIdentity $WindowHandle
    foreach($id in 'CharacterSetsSearchBox','PrimaryButton'){
        $type=if($id -eq 'PrimaryButton'){'Button'}else{'Group'}
        if(Get-PtQuickAccentDialogControl -Target $target -AutomationId $id -ControlType $type -Optional){
            throw 'An existing dialog must be preserved; no character dialog opened.'
        }
    }
    $button=Resolve-PtUiElement -Hwnd $WindowHandle -Name $ManageButtonName -ControlType Button
    if(-not $button.Current.IsEnabled -or $button.Current.IsOffscreen){throw 'Manage character sets must be visible and enabled.'}
    $ownedId=$null;$failure=$null
    try{
        Assert-PtWindowIdentity $target
        $button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
        $search=Wait-PtCondition -Description 'owned character-set draft' -TimeoutSeconds $TimeoutSeconds -Probe {
            Get-PtQuickAccentDialogControl -Target $target -AutomationId CharacterSetsSearchBox -ControlType Group -Optional
        }
        $ownedId=@($search.GetRuntimeId()) -join ','
        if(-not $ownedId){throw 'Character-set draft has no runtime identity.'}
        & $Action $search $target @ArgumentList
    }catch{$failure=$_}
    finally{
        if($ownedId){
            try{
                $current=Get-PtQuickAccentDialogControl -Target $target -AutomationId CharacterSetsSearchBox -ControlType Group -Optional
                if($current){
                    if((@($current.GetRuntimeId()) -join ',') -cne $ownedId){throw 'Character dialog was replaced; preserving the unowned replacement.'}
                    $cancel=Get-PtQuickAccentDialogControl -Target $target -AutomationId CloseButton -ControlType Button
                    if(-not $cancel.Current.IsEnabled -or $cancel.Current.IsOffscreen){throw 'Owned dialog Cancel is not usable.'}
                    $cancel.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
                    Wait-PtCondition -Description 'owned character-set draft closed' -TimeoutSeconds $TimeoutSeconds -Probe {
                        -not(Get-PtQuickAccentDialogControl -Target $target -AutomationId CharacterSetsSearchBox -ControlType Group -Optional)
                    }|Out-Null
                }
            }catch{
                if($failure){$failure.Exception.Data['CharacterDialogCleanupFailure']=$_.Exception.Message}else{$failure=$_}
            }
        }
    }
    if($failure){throw $failure}
}
