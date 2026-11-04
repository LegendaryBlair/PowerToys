#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-fz-recording-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-verification-report.ps1"
$recipe=Join-Path $PSScriptRoot 'Test-PtFancyZonesCaseDesktop.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($recipe,[ref]$null,[ref]$null)
foreach($name in 'Case-Proof','Record-CaseCondition','Complete-CaseConditions'){
    $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
    if(-not $function){throw "Missing recipe function: $name"}
    . ([scriptblock]::Create($function.Extent.Text))
}
$itemId='recording'
$selected=@([pscustomobject]@{Id=$itemId;Description='Synthetic case-ledger regression';Admin='NO';Clarity='CLEAR';UserVisible=$false
    Assertions=@([pscustomobject]@{Id='recording.observed';Description='An observed condition'},
        [pscustomobject]@{Id='recording.missing';Description='An unexecuted condition'})})
$run=New-PtVerificationRun -Workspace $Workspace -Module 'FancyZones recorder regression' -Bits 'Synthetic offline fixture' `
    -Scenario InfrastructureAcceptance -Items $selected -Inputs @(
        @{Name='recipe.ps1';Role='Other';Path=$recipe},
        @{Name='synthetic-test.ps1';Role='Checklist';Path=$PSCommandPath},
        @{Name='recorder.ps1';Role='Helper';Path="$PSScriptRoot\..\pt-verification-report.ps1"},
        @{Name='skill.md';Role='Skill';Path="$PSScriptRoot\..\..\SKILL.md"})
$global:FzCase=@{Run=$run;Ledger=@{}}
foreach($id in 'observed','missing'){
    $FzCase.Ledger[$id]=[pscustomobject]@{Id=$id;ChildId="recording.$id";Verdict='NOT-OBSERVED';Category='not-observed'
        Passed=$false;Executed=$false;Actual='Not executed';Evidence=@();ObservationSequence=$null;AttemptId=$null}
}
$case=Invoke-PtVerificationCase -Run $run -ItemId $itemId -Name 'Synthetic ledger recording' -Command 'Exercise recording only; no product actions' -Action {
    param($attempt)
    $rejected=$false
    try {
        Record-CaseCondition -Attempt $attempt -ConditionId observed -Verdict PASS -Category synthetic `
            -Actual 'Must reject unexecuted pass' -Executed $false -Detail @{Synthetic=$true}
    }catch{$rejected=$_.Exception.Message -match 'unexecuted'}
    if(-not $rejected){throw 'Unexecuted condition was accepted as PASS.'}
    Record-CaseCondition -Attempt $attempt -ConditionId observed -Verdict PASS -Category synthetic `
        -Actual 'Synthetic observation' -Executed $true -Detail @{Synthetic=$true;Observed=1}
    Complete-CaseConditions $attempt
}
$state=Get-PtReportState $run
$assertions=@($state.Events|Where-Object Type -CEQ 'AssertionObserved')
if($assertions.Count -ne 2 -or $assertions[0].Data.Verdict -cne 'PASS' -or
    $assertions[1].Data.Verdict -cne 'BLOCKED' -or $assertions[0].AttemptId -cne $case.Attempt.Id){
    throw 'Same-producing-attempt judgments or missing-condition accounting failed.'
}
Complete-PtVerificationItem -Run $run -ItemId $itemId -Reason 'Synthetic recording test completed with intentionally missing condition.'
Complete-PtVerificationRun -Run $run -NoFriction|Out-Null
Test-PtVerificationArchive -Workspace $Workspace|Out-Null
$global:FzCase=$null
'PASS: original attempt preserved, unexecuted PASS rejected, missing condition remains BLOCKED.'
