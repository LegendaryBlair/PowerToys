#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-report-statistics-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. "$skill\scripts\pt-verification-report.ps1"
. "$skill\scripts\pt-session-safety.ps1"
if(Test-Path $Workspace){throw 'Use a new test workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$global:PtStatisticsFixture=@{Cleaned=$false;ReportCalled=$false;FailCase=$false;FailReport=$false;WrongRun=$false;WrongTotal=$false}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
$items=@(@{Id='I1';Description='Synthetic reporting sequence';Admin='NO';Clarity='CLEAR';UserVisible=$false
    Assertions=@(@{Id='value';Description='Synthetic observation'})})
$cases={
    param($run)
    Invoke-PtVerificationCase -Run $run -ItemId I1 -Name 'Synthetic observation' -Command 'Observe fixed fixture' -Action {
        param($attempt)
        if($global:PtStatisticsFixture.FailCase){throw 'Original execution error'}
        $path=New-PtVerificationArtifactPath $attempt 'value.txt'
        Write-PtReportText $path 'synthetic'
        $evidence=Add-PtVerificationArtifact $attempt $path Evidence 'Synthetic observation'
        Add-PtVerificationAssertion $attempt value PASS 'Synthetic comparison' 'Observed fixed fixture' -Evidence @($evidence)
    }|Out-Null
    Complete-PtVerificationItem $run I1 -Reason 'Fixture observed'
}
$report={
    param($attempt)
    $global:PtStatisticsFixture.ReportCalled=$true
    if(-not $global:PtStatisticsFixture.Cleaned){throw 'Reporting ran before cleanup'}
    if($attempt.Phase -ne 'Diagnostic' -or $attempt.Kind -ne 'Diagnostic'){throw 'Reporting replaced the cleanup context'}
    if($global:PtStatisticsFixture.FailReport){throw 'Statistics extraction error'}
    $events=@(Read-PtReportEvents $attempt.Run)
    $cutoff=@($events|Where-Object {$_.Type -eq 'AttemptStopped' -and $_.Phase -eq 'Cleanup'}|Select-Object -Last 1)[0]
    if(-not $cutoff){throw 'Task 1 cleanup cutoff missing'}
    # Synthetic collection data exercises report wiring only, not a session-log parser.
    $stats=@{RunId=$(if($global:PtStatisticsFixture.WrongRun){'another-run'}else{$attempt.Run.Id})
        CountingMode='agent-origin-requests';Coverage='partial'
        Task1Cutoff=@{JournalSequence=$cutoff.Sequence;Utc=$cutoff.Timestamp}
        ExecutionSegments=@(@{StartUtc=$events[0].Timestamp;EndUtc=$cutoff.Timestamp})
        ModuleTotals=@{AgentToolRequests=3;ExecutionLifecycleWallSeconds=2;ToolResponseWaitUnionSeconds=$null}
        AttributionRecords=@(
            @{SessionId='synthetic';ToolCallId='one';ToolName='powershell'},
            @{SessionId='synthetic';ToolCallId='two';ToolName='powershell'},
            @{SessionId='synthetic';ToolCallId='three';ToolName='view'})
        Cases=@(@{CaseId='I1';NormalAttempts=1;DiagnosticAttempts=0;RecordedDriverSeconds=1.5;CaseSpanSeconds=2;FailedDriverSteps=0})
        Limitations=@('Synthetic counts test report wiring only; tool-response duration deliberately unavailable.')}
    if($global:PtStatisticsFixture.WrongTotal){$stats.ModuleTotals.AgentToolRequests=9}
    $older=New-PtVerificationArtifactPath $attempt 'statistics.json'
    Write-PtReportText $older (ConvertTo-Json @{RunId=$attempt.Run.Id;CountingMode='agent-origin-requests'
        Coverage='unavailable';ModuleTotals=@{AgentToolRequests=999}} -Depth 8)
    Add-PtVerificationArtifact $attempt $older Evidence 'Earlier statistics retained as history'|Out-Null
    $json=New-PtVerificationArtifactPath $attempt 'statistics.json'
    Write-PtReportText $json (ConvertTo-Json $stats -Depth 12)
    Add-PtVerificationArtifact $attempt $json Evidence 'Latest synthetic statistics for inline reporting'|Out-Null
}
$plan=@(@{Id='fixture';Phase='Verify';DependsOn=@();Action={$global:PtStatisticsFixture.Cleaned=$true}
    Verify={$global:PtStatisticsFixture.Cleaned}})
$options=@{Skill=$skill;Module='Report statistics fixture';Scenario='InfrastructureAcceptance';Bits='Synthetic reporting only'
    Items=$items;Inputs=@(@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath})
    Preflight={param($attempt)};Cases=$cases;CleanupPlan=$plan;Report=$report;NoFriction=$true
    ResourcePlan=@{Schema='PtRunResources.v1';Resources=@(@{Id='fixture';Kind='Other';RestoreStep='fixture'})}}
try{
    & "$skill\templates\verification-run.ps1" @options -Workspace "$Workspace\success"|Out-Null
    Require $global:PtStatisticsFixture.ReportCalled 'Report callback was not invoked'
    $run=Open-PtVerificationRun "$Workspace\success"
    $state=Get-PtReportState $run
    Require (@($state.Attempts|Where-Object Phase -EQ Cleanup).Count -eq 1) 'Statistics created another cleanup attempt'
    Require (@($state.CurrentRestoration|Where-Object {$_.Data.Verdict -ne 'PASS'}).Count -eq 0) 'Reporting changed restoration status'
    $reportText=[IO.File]::ReadAllText("$Workspace\success\report.md")
    Require ($reportText.Contains('## Execution statistics') -and
        $reportText.Contains('| powershell | 2 |') -and $reportText.Contains('| view | 1 |') -and
        $reportText.Contains('| I1 | PASS | 1 / 0 | 1.5 | 2 | 0 |')) 'Export did not render actual statistics inline'
    Require (-not $reportText.Contains('statistics.md') -and -not $reportText.Contains('| Winapp |') -and
        -not $reportText.Contains('| Helpers |') -and -not $reportText.Contains('999')) 'Legacy columns/summary or superseded counts remain'
    $manifest=ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$Workspace\success\artifact-manifest.json"))
    $statsFiles=@($manifest.Files|Where-Object Path -Match '-statistics\.(json|md)$')
    Require ($statsFiles.Count -eq 2) 'Current and historical statistics artifacts are not integrity-covered'
    $data=$state.ExecutionStatistics.Data
    Require ($data.ModuleTotals.AgentToolRequests -eq 3) 'Latest registered statistics was not selected'
    $exported=ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$Workspace\success\results.json"))
    Require ($exported.ExecutionStatistics.Data.ModuleTotals.AgentToolRequests -eq 3) 'Exported results lack self-contained rendering data'
    $reportStart=@($state.Events|Where-Object {$_.Type -eq 'AttemptStarted' -and $_.Data.Name -eq 'Report preparation'})[0]
    Require ($data.Task1Cutoff.JournalSequence -lt $reportStart.Sequence -and
        $null -eq $data.ModuleTotals.ToolResponseWaitUnionSeconds) 'Reporting counted itself or changed unavailable duration to zero'
    Test-PtVerificationArchive -Workspace $run.Workspace|Out-Null
    $statsPath=Join-Path $run.Workspace $state.ExecutionStatistics.Artifact.Path
    $originalBytes=[IO.File]::ReadAllBytes($statsPath)
    try{
        [IO.File]::AppendAllText($statsPath,' ')
        $rejected=$false
        try{Get-PtReportState $run|Out-Null}catch{$rejected=$_.Exception.Message -match 'Changed evidence'}
        Require $rejected 'Tampered statistics were loaded for rendering'
    }finally{[IO.File]::WriteAllBytes($statsPath,$originalBytes)}

    $global:PtStatisticsFixture.WrongRun=$true
    $failure=$null
    try{& "$skill\templates\verification-run.ps1" @options -Workspace "$Workspace\wrong-run"|Out-Null}catch{$failure=$_}
    Require ($failure.Exception.Message -match 'belonging to this run') 'Cross-run statistics were accepted'
    $unsealed=Open-PtVerificationRun "$Workspace\wrong-run"
    Require (@(Read-PtReportEvents $unsealed|Where-Object Type -EQ RunCompleted).Count -eq 0) 'Invalid statistics sealed the run before validation'
    $global:PtStatisticsFixture.WrongRun=$false
    $global:PtStatisticsFixture.WrongTotal=$true
    $failure=$null
    try{& "$skill\templates\verification-run.ps1" @options -Workspace "$Workspace\wrong-total"|Out-Null}catch{$failure=$_}
    Require ($failure.Exception.Message -match 'does not reconcile') 'Inconsistent statistics total was accepted'
    $unsealed=Open-PtVerificationRun "$Workspace\wrong-total"
    Require (@(Read-PtReportEvents $unsealed|Where-Object Type -EQ RunCompleted).Count -eq 0) 'Statistics rendering failure sealed the run'
    $global:PtStatisticsFixture.WrongTotal=$false

    $global:PtStatisticsFixture.Cleaned=$false;$global:PtStatisticsFixture.ReportCalled=$false
    $global:PtStatisticsFixture.FailCase=$true;$global:PtStatisticsFixture.FailReport=$true
    $failure=$null
    try{& "$skill\templates\verification-run.ps1" @options -Workspace "$Workspace\failed"|Out-Null}catch{$failure=$_}
    Require ($failure.Exception.Message -match 'Original execution error') 'Statistics error masked execution failure'
    Require ($failure.Exception.Data['ReportPreparationFailure'] -match 'Statistics extraction error') 'Secondary reporting error lost'
    Require ($global:PtStatisticsFixture.Cleaned -and $global:PtStatisticsFixture.ReportCalled) 'Failed execution skipped cleanup or reporting'
    Write-PtReportText "$Workspace\results.json" '{"ReportAfterCleanup":"PASS","StatisticsCutoff":"PASS","UnavailableDuration":"PASS","InlineStatistics":"PASS","LatestStatistics":"PASS","SelfContainedResults":"PASS","IntegrityCovered":"PASS","TamperingRefused":"PASS","CrossRunStatisticsRefusedBeforeSealing":"PASS","InvalidTotalsRefusedBeforeSealing":"PASS","RestorationScopePreserved":"PASS","PrimaryAndReportingErrorsPreserved":"PASS"}'
}finally{
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
    Remove-Variable PtStatisticsFixture -Scope Global
}
"PASS: report-phase statistics integration; no product or clipboard operations. $Workspace"
