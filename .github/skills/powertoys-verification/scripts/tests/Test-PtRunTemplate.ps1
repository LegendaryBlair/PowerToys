#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-template-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. "$skill\scripts\pt-verification-report.ps1"
. "$skill\scripts\pt-session-safety.ps1"
. "$skill\scripts\pt-state-snapshot.ps1"
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$global:PtTemplateFixtureState=@{Path="$Workspace\fixture.txt";Baseline=$null;Expected=$null
    CleanupRan=0;IndependentCleanupRan=0;FailRestore=$false;FailCase=$false;ForeignWrite=$false}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return $_}
    throw "Expected failure: $Pattern"
}
function ClearSession {
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
    $global:PtTemplateFixtureState.Baseline=$null
}
$items=@(@{Id='I1';Description='Synthetic template';Admin='NO';Clarity='CLEAR';UserVisible=$false
    Assertions=@(@{Id='value';Description='Synthetic value'})})
$inputs=@(@{Name='checklist.ps1';Role='Checklist';Path=$PSCommandPath})
$preflight={
    param($attempt)
    $fixture=$global:PtTemplateFixtureState
    $path=Join-Path $attempt.Run.Workspace 'original-file.json'
    if(Test-Path -LiteralPath $path){
        $fixture.Baseline=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($path))
    }else{
        $fixture.Baseline=Get-PtFileSnapshot $fixture.Path
        Write-PtReportText $path (ConvertTo-Json $fixture.Baseline -Depth 6)
    }
    Add-PtVerificationArtifact $attempt $path Evidence 'Original file baseline retained across this run only'|Out-Null
}
$cases={
    param($run)
    $result=Invoke-PtVerificationCase -Run $run -ItemId I1 -Name 'Observe synthetic value' -Command 'Read synthetic value' -Action {
        param($attempt)
        $fixture=$global:PtTemplateFixtureState
        [IO.File]::WriteAllText($fixture.Path,'owned-change')
        $fixture.Expected=Get-PtFileSnapshot $fixture.Path
        if($fixture.ForeignWrite){[IO.File]::WriteAllText($fixture.Path,'foreign-change')}
        if($fixture.FailCase){throw 'Synthetic case failure'}
        $file=New-PtVerificationArtifactPath $attempt 'value.txt';Write-PtReportText $file 'synthetic'
        $evidence=Add-PtVerificationArtifact $attempt $file Evidence 'Synthetic value'
        Add-PtVerificationAssertion -Attempt $attempt -AssertionId value -Verdict PASS -Category 'Synthetic contract' -Reason 'Observed synthetic value' -Evidence @($evidence)
    }
    Complete-PtVerificationItem $run I1 -Reason 'Synthetic observation recorded'
}
$plan=@(
    @{Id='synthetic-file';Phase='Files';DependsOn=@();Action={
        $fixture=$global:PtTemplateFixtureState;$fixture.CleanupRan++
        if($fixture.FailRestore){throw 'Synthetic file restoration failure'}
        if($fixture.Expected){Restore-PtFileSnapshot $fixture.Baseline -ExpectedState $fixture.Expected|Out-Null}
    };Verify={
        (Get-PtFileSnapshot $global:PtTemplateFixtureState.Path).base64 -ceq $global:PtTemplateFixtureState.Baseline.base64
    }},
    @{Id='independent';Phase='Verify';DependsOn=@();Action={$global:PtTemplateFixtureState.IndependentCleanupRan++};Verify={$true}}
)
$common=@{Skill=$skill;Module='Synthetic template fixture';Scenario='InfrastructureAcceptance';Bits='No module execution'
    Items=$items;Inputs=$inputs;Preflight=$preflight;Cases=$cases;CleanupPlan=$plan;NoFriction=$true
    ResourcePlan=@{Schema='PtRunResources.v1';Resources=@(
        @{Id='synthetic-file';Kind='File';RestoreStep='synthetic-file'})}}
[IO.File]::WriteAllText($global:PtTemplateFixtureState.Path,'first-original')
$output=& "$skill\templates\verification-run.ps1" @common -Workspace "$Workspace\clean"
Require ($null -eq (Get-PtActiveResourceSession)) 'Clean template left an active resource session'
Require ([IO.File]::ReadAllText($global:PtTemplateFixtureState.Path) -ceq 'first-original') 'First run did not restore its original'
Test-PtVerificationArchive -Workspace "$Workspace\clean"|Out-Null

# Each new run accepts its actual starting state, not an earlier run's values.
[IO.File]::WriteAllText($global:PtTemplateFixtureState.Path,'second-original')
& "$skill\templates\verification-run.ps1" @common -Workspace "$Workspace\independent"|Out-Null
Require ([IO.File]::ReadAllText($global:PtTemplateFixtureState.Path) -ceq 'second-original') 'Second run restored another run baseline'
Test-PtVerificationArchive -Workspace "$Workspace\independent"|Out-Null

$global:PtTemplateFixtureState.FailRestore=$true
$before=$global:PtTemplateFixtureState.IndependentCleanupRan
$failure=Reject {& "$skill\templates\verification-run.ps1" @common -Workspace "$Workspace\failed-cleanup"} 'Cleanup incomplete'
Require ($global:PtTemplateFixtureState.IndependentCleanupRan -eq $before+1) 'Failed restoration skipped independent cleanup'
Require ([IO.File]::ReadAllText($global:PtTemplateFixtureState.Path) -ceq 'owned-change') 'Failed cleanup was presented as restored'
$failed=Get-PtReportState (Open-PtVerificationRun "$Workspace\failed-cleanup")
Require (@($failed.Restoration|Where-Object {$_.Data.Verdict -eq 'BLOCKED'}).Count -gt 0) 'Resource failure was not recorded'
$baselinePath="$Workspace\failed-cleanup\original-file.json"
$baselineHash=Get-PtReportHash ([IO.File]::ReadAllBytes($baselinePath))
ClearSession

$resumeOptions=$common.Clone()
$resumeOptions.Cases={param($run)}
$wrong=$resumeOptions.Clone()
$wrong.ResourcePlan=ConvertFrom-PtReportJson (ConvertTo-Json $common.ResourcePlan -Depth 8)
$wrong.ResourcePlan.Resources[0].Id='different-resource'
Reject {& "$skill\templates\verification-run.ps1" @wrong -Workspace "$Workspace\failed-cleanup" -Resume} 'original resource plan'|Out-Null
$global:PtTemplateFixtureState.FailRestore=$false
& "$skill\templates\verification-run.ps1" @resumeOptions -Workspace "$Workspace\failed-cleanup" -Resume|Out-Null
Require ([IO.File]::ReadAllText($global:PtTemplateFixtureState.Path) -ceq 'second-original') 'Resume adopted the dirty state as its baseline'
Require ($baselineHash -ceq (Get-PtReportHash ([IO.File]::ReadAllBytes($baselinePath)))) 'Original local snapshot was overwritten'
Test-PtVerificationArchive -Workspace "$Workspace\failed-cleanup"|Out-Null

$global:PtTemplateFixtureState.ForeignWrite=$true
Reject {& "$skill\templates\verification-run.ps1" @common -Workspace "$Workspace\foreign-conflict"} 'Cleanup incomplete'|Out-Null
Require ([IO.File]::ReadAllText($global:PtTemplateFixtureState.Path) -ceq 'foreign-change') 'Run-local rollback overwrote foreign changes'
ClearSession
$global:PtTemplateFixtureState.ForeignWrite=$false
$global:PtTemplateFixtureState.FailCase=$true;$global:PtTemplateFixtureState.FailRestore=$true
$before=$global:PtTemplateFixtureState.IndependentCleanupRan
$failure=Reject {& "$skill\templates\verification-run.ps1" @common -Workspace "$Workspace\primary-and-cleanup-errors"} 'Synthetic case failure'
Require ($failure.Exception.Data['CleanupFailure'] -match 'Cleanup incomplete' -and
    $global:PtTemplateFixtureState.IndependentCleanupRan -eq $before+1) 'Primary/cleanup errors lost or independent cleanup skipped'
ClearSession

$global:PtTemplateFixtureState.FailCase=$false;$global:PtTemplateFixtureState.FailRestore=$false
$global:PtTemplateFixtureState.Expected=$null
$preflightFailure=$common.Clone()
$preflightFailure.Preflight={param($attempt) throw 'Synthetic preflight failure'}
$before=$global:PtTemplateFixtureState.CleanupRan
$failure=Reject {& "$skill\templates\verification-run.ps1" @preflightFailure -Workspace "$Workspace\preflight-failure"} 'Synthetic preflight failure'
Require ($global:PtTemplateFixtureState.CleanupRan -eq $before+1) 'Preflight failure skipped cleanup'
ClearSession

foreach($removed in 'SharedStateProbe','DesktopKey','PreviousHandoffPath','PreviousHandoffHash','BatchId'){
    Require (-not (Get-Command "$skill\templates\verification-run.ps1").Parameters.ContainsKey($removed)) "Removed template parameter still exposed: $removed"
}
Require (-not (Test-Path "$skill\scripts\pt-run-handoff.ps1")) 'Removed helper is still shipped'
Require (@(Get-ChildItem $Workspace -Recurse -File -Filter '*handoff*').Count -eq 0) 'Run emitted cross-run artifacts'
$receipt=ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$Workspace\clean\resource-session.json"))
Require (-not $receipt.PSObject.Properties['Shared']) 'New resource session retains cross-run state'
Remove-Variable PtTemplateFixtureState -Scope Global
Write-PtReportText "$Workspace\results.json" '{"LocalRestoration":"PASS","IndependentRunBaselines":"PASS","CleanupFailureEvidence":"PASS","IndependentCleanup":"PASS","ResumeOriginalBaseline":"PASS","ResumePlanGuard":"PASS","ForeignChangesPreserved":"PASS","PrimaryAndCleanupErrors":"PASS","PreflightFailureCleanup":"PASS","RemovedCrossRunSurface":"PASS"}'
"PASS: run-local template cleanup, resume and failure contracts; no module UI driven. $Workspace"
