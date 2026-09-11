param([Parameter(Mandatory)][long]$Hwnd,[Parameter(Mandatory)][string]$Workspace)
$ErrorActionPreference='Stop'
$helpers=Split-Path $PSScriptRoot -Parent
foreach($name in 'pt-owned-fixtures','pt-verification-report'){. "$helpers\$name.ps1"}
Initialize-PtOwnedFixtures
$filePath=Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\Shortcut Guide\settings.json'
$identity=Get-PtWindowIdentity $Hwnd
if((Get-Process -Id $identity.processId).ProcessName -cne 'PowerToys.Settings'){throw 'Expected installed PowerToys Settings HWND.'}
$run=New-PtVerificationRun -Workspace $Workspace -Module 'H01 Settings control acceptance' `
    -Bits 'Installed Settings controls only; no Shortcut Guide activation or full module checklist' `
    -Scenario InfrastructureAcceptance -Inputs @(
        @{Name='SKILL.md';Role='Skill';Path="$helpers\..\SKILL.md"}
        @{Name='acceptance.ps1';Role='Checklist';Path=$PSCommandPath}
        @{Name='uia.ps1';Role='Helper';Path="$helpers\pt-uia.ps1"}
        @{Name='desktop.ps1';Role='Helper';Path="$helpers\pt-desktop.ps1"}
    ) -Items @(@{Id='H01';Description='Scoped WinUI ComboBox selection and restoration';Admin='NO';Clarity='CLEAR';UserVisible=$false
        Assertions=@(@{Id='selection';Description='Three control selectors select/read back and restore';Required=$true})})
$desktop=Get-PtDesktopSnapshot -WindowHwnd $Hwnd
$file=Get-PtFileSnapshot $filePath
$desktop|ConvertTo-Json -Depth 15|Set-Content "$Workspace\desktop-before.json"
$file|ConvertTo-Json -Depth 8|Set-Content "$Workspace\settings-before.json"
$beforeDocument=Get-Content $filePath -Raw|ConvertFrom-Json|ConvertTo-Json -Depth 30 -Compress
$attempt=Start-PtVerificationAttempt $run -ItemId H01 -Kind Normal -Name 'Installed ComboBoxes' -Activate
$results=[Collections.Generic.List[object]]::new()
$originalError=$null
try{
    Assert-PtForegroundOrAbort -Hwnd $Hwnd
    foreach($case in @(
        @{Selector=@{AutomationId='ShortcutGuide_WindowsKeyAction'};Requested='Open Shortcut Guide'}
        @{Selector=@{ControlName='Theme'};Requested='Light'}
        @{Selector=@{ControlName='Window position'};Requested='Right'}
    )){
        $resolveArgs=if($case.Selector.ContainsKey('ControlName')){@{Name=$case.Selector.ControlName}}else{$case.Selector}
        $control=Resolve-PtUiElement -Hwnd $Hwnd @resolveArgs -ControlType ComboBox
        $before=@(Get-PtComboBoxSelection $control)
        if($before.Count -ne 1){throw 'Baseline selection was not uniquely observed'}
        $args=$case.Selector
        try{
            $result=Select-PtComboBoxItem -Hwnd $Hwnd @args -ItemName $case.Requested
            if($result.Actual.Count -ne 1 -or $result.Actual[0] -cne $case.Requested){throw 'Selection readback mismatch'}
            $results.Add($result)
        }finally{
            Select-PtComboBoxItem -Hwnd $Hwnd @args -ItemName $before[0]|Out-Null
        }
    }
}catch{$originalError=$_}
finally{
    try{
        Assert-PtWindowIdentity $identity
        Wait-PtCondition -Description 'original persisted Shortcut Guide settings' -TimeoutSeconds 5 -Probe {
            (Get-Content $filePath -Raw|ConvertFrom-Json|ConvertTo-Json -Depth 30 -Compress) -ceq $beforeDocument
        }|Out-Null
        Restore-PtFileSnapshot $file|Out-Null
        $after=Get-PtFileSnapshot $filePath
        if(($after|ConvertTo-Json -Depth 8 -Compress) -cne ($file|ConvertTo-Json -Depth 8 -Compress)){throw 'Settings bytes were not restored'}
        $after|ConvertTo-Json -Depth 8|Set-Content "$Workspace\settings-restored.json"
    }catch{
        if($originalError){$originalError.Exception.Data['SettingsCleanupFailure']=$_.Exception.Message;[Console]::Error.WriteLine($_.Exception.Message)}else{$originalError=$_}
    }
    try{Restore-PtDesktopSnapshot $desktop|ConvertTo-Json -Depth 15|Set-Content "$Workspace\desktop-restored.json"}
    catch{if($originalError){$originalError.Exception.Data['DesktopCleanupFailure']=$_.Exception.Message}else{$originalError=$_}}
    $results|ConvertTo-Json -Depth 10|Set-Content "$Workspace\results.json"
    Stop-PtVerificationAttempt $attempt -Reason 'Bounded control acceptance finished'
    Set-PtActiveVerificationAttempt -Attempt $null
}
if($originalError){throw $originalError}
$state=Get-PtReportState $run
if(@($state.Steps|Where-Object Status -eq 'Completed').Count -lt 6){throw 'Public helper operations did not retain their recording context.'}
"PASS: three installed WinUI ComboBox round trips, immutable steps and exact settings/desktop restoration. $Workspace"
