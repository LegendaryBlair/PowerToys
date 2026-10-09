#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-resources-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach($helper in 'pt-verification-report','pt-session-safety','pt-cleanup-plan','pt-clipboard-session'){
    . "$skill\scripts\$helper.ps1"
}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected failure: $Pattern"
}
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message});throw}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
$steps=@(@{Id='files';Phase='Files';DependsOn=@();Action={};Verify={$true}},
    @{Id='windows';Phase='Windows';DependsOn=@('files');Action={};Verify={$true}})
$plan=@{Schema='PtRunResources.v1';Resources=@(
    @{Id='settings';Kind='Settings';Hwnd=42L},
    @{Id='module-file';Kind='File';RestoreStep='files'},
    @{Id='fixture';Kind='Window';Ownership='Owned';RestoreStep='windows'})}
Check 'Explicit used resources wire to Settings and local cleanup without requiring clipboard' {
    Assert-PtRunResourcePlan $plan $steps
    Require (@($plan.Resources|Where-Object Kind -EQ Clipboard).Count -eq 0) 'Non-clipboard scope gained clipboard dependency'
}
Check 'Missing Settings target and cleanup comparisons fail before driving' {
    Reject {Assert-PtRunResourcePlan $plan $steps -SettingsHwnd 43} 'SettingsHwnd'
    Reject {Assert-PtRunResourcePlan $plan @($steps[1])} 'dependency'
    $copy=ConvertFrom-PtReportJson (ConvertTo-Json $plan -Depth 10)
    $copy.Resources[1].RestoreStep='missing'
    Reject {Assert-PtRunResourcePlan $copy $steps} 'no matching cleanup'
    $copy.Resources[0].Hwnd=0
    Reject {Assert-PtRunResourcePlan $copy $steps} 'unique, positive'
}
Check 'Borrowed windows cannot omit ownership and duplicate resources remain invalid' {
    $copy=ConvertFrom-PtReportJson (ConvertTo-Json $plan -Depth 10)
    $copy.Resources[2].Ownership=$null
    Reject {Assert-PtRunResourcePlan $copy $steps} 'Borrowed or Owned'
    $copy.Resources[2].Ownership='Borrowed'
    Assert-PtRunResourcePlan $copy $steps
    $copy.Resources[2].Id=$copy.Resources[1].Id
    Reject {Assert-PtRunResourcePlan $copy $steps} 'unique IDs'
}
Check 'All four actual module entry paths reject absent wiring before creating a run' {
    foreach($module in 'Color Picker','Workspaces','Shortcut Guide','Environment Variables'){
        $target=Join-Path $Workspace $module.Replace(' ','')
        Reject {& "$skill\templates\verification-run.ps1" -Skill $skill -Workspace $target -Module $module `
            -Bits 'Synthetic wiring rejection; no product execution' -Items @(@{Id='unused'}) `
            -Inputs @(@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath}) -Preflight {throw 'must not run'} `
            -Cases {throw 'must not run'} -Cleanup {} -NoFriction} 'require ResourcePlan'
        Require (-not (Test-Path $target)) 'Missing wiring reached run creation'
    }
}
Check 'A file resource needs only its local cleanup and explicit verifier' {
    $local=@{Schema='PtRunResources.v1';Resources=@(@{Id='local';Kind='File';RestoreStep='files'})}
    Assert-PtRunResourcePlan $local $steps
    Reject {Assert-PtRunResourcePlan $local @(@{Id='files';Phase='Files';DependsOn=@();Action={}})} 'Action/Verify'
}
Check 'Declared clipboard resources must use the clipboard phase' {
    $clipboard=@{Schema='PtRunResources.v1';Resources=@(@{Id='clipboard';Kind='Clipboard';RestoreStep='files'})}
    Reject {Assert-PtRunResourcePlan $clipboard $steps} 'Clipboard-phase'
}
Check 'A no-clipboard resource session blocks capture before starting a keeper' {
    function Get-PtNativeWindow {}
    $run=New-PtVerificationRun -Workspace "$Workspace\no-clipboard" -Module 'Wiring fixture' `
        -Bits 'Offline declaration only' -Scenario InfrastructureAcceptance `
        -Items @(@{Id='I1';Description='Resource contract';Admin='NO';Clarity='CLEAR';UserVisible=$false;Assertions=@(@{Id='a';Description='No clipboard'})}) `
        -Inputs @(Get-PtVerificationInputs -Skill $skill -Inputs @(@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath}))
    $session=New-PtResourceSession $run
    $session.ResourcePlan=$plan;Save-PtResourceSession $session
    Reject {New-PtClipboardSession $run.Workspace} 'not declared'
    Require (@(Get-ChildItem $run.Workspace -Filter 'clipboard-session-*').Count -eq 0) 'A keeper started for undeclared clipboard use'
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
}
"PASS: $($results.Count) resource wiring groups; no Settings or clipboard access. $Workspace"
