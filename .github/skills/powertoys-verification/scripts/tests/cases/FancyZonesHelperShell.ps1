param($Attempt)
$ErrorActionPreference='Stop'
Initialize-PtFancyZonesCaseWindows
Show-PtFancyZonesCaseWindow $FzCase.Target
$observed=[Collections.Generic.List[object]]::new()
Invoke-PtFancyZonesCaseTaskView -Target $FzCase.Target -ArgumentList @($observed) -Action {
    param($surface,$observations)
    $observations.Add([pscustomobject]@{Surface=$surface;Foreground=(Get-PtForegroundWindow).Hwnd})
}
$normal=$FzCase.TaskView.State -ceq 'Closed' -and
    (Test-PtTrackedWindowClosed $FzCase.TaskView.Surface -AllowHidden) -and
    (Get-PtForegroundWindow).Hwnd -eq $FzCase.Target.hwnd
Record-CaseCondition -Attempt $Attempt -ConditionId 'shell.normal:current-desktop' `
    -Verdict $(if($normal){'PASS'}else{'FAIL'}) -Category product -Executed $true `
    -Actual "Exact test-opened Task View closed and target foreground restored=$normal." `
    -Detail @{Transition=$FzCase.TaskView;During=@($observed)}
$expectedError=$null
try {
    Invoke-PtFancyZonesCaseTaskView -Target $FzCase.Target -Action {
        param($surface)
        throw 'Expected minimal-acceptance observation error'
    }
} catch {$expectedError=$_}
$cleanupError=if($expectedError){$expectedError.Exception.Data['TaskViewCleanupFailure']}else{$null}
$restored=$expectedError -and $expectedError.Exception.Message -ceq 'Expected minimal-acceptance observation error' -and
    -not $expectedError.Exception.Data['TaskViewCleanupFailure'] -and $FzCase.TaskView.State -ceq 'Closed' -and
    (Test-PtTrackedWindowClosed $FzCase.TaskView.Surface -AllowHidden) -and
    (Get-PtForegroundWindow).Hwnd -eq $FzCase.Target.hwnd
Record-CaseCondition -Attempt $Attempt -ConditionId 'shell.failure-cleanup:current-desktop' `
    -Verdict $(if($restored){'PASS'}else{'FAIL'}) -Category product -Executed $true `
    -Actual "Injected observer error retained and exact Shell transition cleaned=$restored." `
    -Detail @{Transition=$FzCase.TaskView;OriginalError=$expectedError.Exception.Message;CleanupError=$cleanupError}
