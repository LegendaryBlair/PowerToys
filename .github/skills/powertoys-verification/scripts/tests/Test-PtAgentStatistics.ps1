# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.
#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-agent-statistics-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. "$skill\scripts\pt-agent-statistics.ps1"
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
if(Test-Path $Workspace){throw 'Use a new fixture workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$items=@(
    @{Id='I1';Description='Nested synthetic operation';Admin='NO';Clarity='CLEAR';UserVisible=$false;Assertions=@(@{Id='one';Description='One'})},
    @{Id='I2';Description='Failed synthetic operation';Admin='NO';Clarity='CLEAR';UserVisible=$false;Assertions=@(@{Id='two';Description='Two'})})
$run=New-PtVerificationRun -Workspace "$Workspace\run" -Module 'Statistics fixture' -Scenario InfrastructureAcceptance `
    -Bits 'Synthetic metadata only; no product state' -Items $items `
    -Inputs @(Get-PtVerificationInputs -Skill $skill -Inputs @(@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath}))
$first=Invoke-PtVerificationCase -Run $run -ItemId I1 -Name 'One outer operation' -Command 'Synthetic outer' -Action {
    param($attempt)
    Invoke-PtVerificationStep -Attempt $attempt -Name 'Nested' -Command 'Synthetic nested' -Action {Start-Sleep -Milliseconds 20}
}
Reject {Invoke-PtVerificationCase -Run $run -ItemId I2 -Name 'Failed operation' -Command 'Synthetic failure' -Action {throw 'Fixture failure'}} 'Fixture failure'
$review=Start-PtVerificationAttempt -Run $run -ItemId I1 -Kind Normal -Name 'Review only'
Stop-PtVerificationAttempt -Attempt $review -Reason 'No execution'
Invoke-PtVerificationCase -Run $run -ItemId I1 -Stage Record -Name 'Disposition-style metadata only' `
    -Command 'Record bookkeeping without a product operation' -Action {'record only'}|Out-Null
Invoke-PtVerificationCase -Run $run -Context Cleanup -Name 'Cleanup' -Command 'No resources to restore' -Action {}|Out-Null
$state=Get-PtReportState $run
$start=[DateTimeOffset]::Parse([string]$state.Events[0].Timestamp)
$end=[DateTimeOffset]::Parse([string]$state.Events[-1].Timestamp)
$session=[guid]::NewGuid().ToString()
function Event([string]$Type,[DateTimeOffset]$Time,$Data){
    @{type=$Type;timestamp=$Time.ToString('o');data=$Data}
}
$events=@(
    (Event 'session.start' $start.AddSeconds(-5) @{sessionId=$session}),
    (Event 'tool.execution_start' $start.AddSeconds(-1) @{toolCallId='entry';toolName='powershell';arguments=@{command='PRIVATE-PAYLOAD-MUST-NOT-LEAK'}}),
    (Event 'tool.execution_start' $start @{toolCallId='one-call';toolName='view'}),
    (Event 'tool.execution_complete' $start @{toolCallId='one-call';success=$true;result=@{content='PRIVATE-PAYLOAD-MUST-NOT-LEAK'}}),
    (Event 'tool.execution_start' $start.AddTicks(1) @{toolCallId='pending';toolName='powershell'}),
    (Event 'tool.execution_complete' $end.AddSeconds(1) @{toolCallId='entry';success=$true}),
    (Event 'tool.execution_start' $end.AddSeconds(2) @{toolCallId='reporting';toolName='powershell'}),
    (Event 'tool.execution_complete' $end.AddSeconds(3) @{toolCallId='reporting';success=$true}))
function WriteLog([string]$Name,[object[]]$Events){
    $path=Join-Path $Workspace $Name
    $lines=@($Events|ForEach-Object {ConvertTo-Json $_ -Depth 12 -Compress})
    [IO.File]::WriteAllLines($path,$lines,[Text.UTF8Encoding]::new($false))
    $path
}
$path=WriteLog 'events.jsonl' $events
$options=@{Run=$run;SessionLogPath=$path;SessionId=$session
    ExecutionSegments=@(@{StartUtc=$start.ToString('o');EndUtc=$end.ToString('o')})
    EntryToolCallId=@('entry');CaseByToolCallId=@{'one-call'='I1'}}
$stats=Get-PtAgentExecutionStatistics @options
Require ($stats.ModuleTotals.AgentToolRequests -eq 3) 'Early overlapping entry, zero-duration boundary call or pending call was lost'
Require ('reporting' -cnotin $stats.AttributionRecords.ToolCallId) 'Reporting outside the cutoff was counted'
Require ($null -eq $stats.ModuleTotals.ToolResponseWaitUnionSeconds) 'Missing completion became a fabricated wait duration'
Require (($stats.AttributionRecords|Where-Object ToolCallId -eq 'entry').Phase -eq 'MULTI-CASE') 'Outer entry was not retained once'
Require (($stats.AttributionRecords|Where-Object ToolCallId -eq 'one-call').CaseId -eq 'I1') 'Explicit case attribution was lost'
Require (($stats.NonCaseRows|Where-Object Phase -eq 'UNASSIGNED').AgentToolRequests -eq 1) 'Unassigned requests disappeared'
Require ($stats.Cases.Count -eq 2) 'Inventory case rows are missing'
$one=$stats.Cases|Where-Object CaseId -eq 'I1'
$outer=$state.Steps|Where-Object {$_.AttemptId -eq $first.Attempt.Id -and -not $_.ParentStepId}
Require ($one.NormalAttempts -eq 1 -and $one.RecordedDriverSeconds -eq $outer.DurationMs/1000) 'Review-only attempts or nested steps inflated metrics'
Require (($stats.Cases|Where-Object CaseId -eq 'I2').FailedDriverSteps -eq 1) 'Failed outer driver step was lost'
Require (-not (ConvertTo-Json $stats -Depth 20).Contains('PRIVATE-PAYLOAD-MUST-NOT-LEAK')) 'Raw tool payload escaped into statistics'

$complete=$options.Clone()
$complete.SessionLogPath=WriteLog 'complete.jsonl' @($events|Where-Object {$_.data.toolCallId -ne 'pending'})
$completeStats=Get-PtAgentExecutionStatistics @complete
Require ([Math]::Abs($completeStats.ModuleTotals.ToolResponseWaitUnionSeconds-($end-$start).TotalSeconds) -lt 0.000001) 'Overlapping tool waits were not clipped and unioned'
$pendingEntry=$options.Clone()
$pendingEntry.SessionLogPath=WriteLog 'pending-entry.jsonl' @($events|Where-Object {-not ($_.type -eq 'tool.execution_complete' -and $_.data.toolCallId -eq 'entry')})
$pendingStats=Get-PtAgentExecutionStatistics @pendingEntry
Require ($pendingStats.ModuleTotals.AgentToolRequests -eq 3 -and $null -eq ($pendingStats.AttributionRecords|Where-Object ToolCallId -eq 'entry').CompletionUtc) 'Known unfinished outer entry was discarded'
$wrong=$options.Clone();$wrong.SessionId='another-session'
Reject {Get-PtAgentExecutionStatistics @wrong} 'different session'
$wrong=$options.Clone();$wrong.EntryToolCallId=@('missing')
Reject {Get-PtAgentExecutionStatistics @wrong} 'missing from the source'
$wrong=$options.Clone();$wrong.ExecutionSegments=@($options.ExecutionSegments[0],$options.ExecutionSegments[0])
Reject {Get-PtAgentExecutionStatistics @wrong} 'ordered and nonoverlapping'
$wrong=$options.Clone();$wrong.SessionLogPath=WriteLog 'duplicate.jsonl' @($events+$events[1])
Reject {Get-PtAgentExecutionStatistics @wrong} 'duplicate tool start'
$tail=$options.Clone();$tail.SessionLogPath=WriteLog 'partial-tail.jsonl' $events
[IO.File]::AppendAllText($tail.SessionLogPath,'{"type":"tool.execution_complete","data":')
$partial=Get-PtAgentExecutionStatistics @tail
Require ($partial.Coverage -eq 'partial' -and $partial.ModuleTotals.AgentToolRequests -eq 3 -and
    @($partial.Limitations|Where-Object {$_ -match 'incomplete JSONL'}).Count -eq 1) 'Incomplete trailing metadata was silently accepted or lost valid requests'
$empty=$options.Clone();$empty.EntryToolCallId=@();$empty.CaseByToolCallId=@{}
$empty.SessionLogPath=WriteLog 'no-calls.jsonl' @($events[0])
Reject {Get-PtAgentExecutionStatistics @empty} 'no matching agent requests'

$register=$options.Clone();$register.Remove('Run')
Invoke-PtVerificationCase -Run $run -Context Diagnostic -Kind Diagnostic -Name 'Register statistics' `
    -Command 'Read synthetic session metadata and register the existing statistics schema' -ArgumentList @($register) -Action {
        param($attempt,$arguments)
        Add-PtAgentExecutionStatistics -Attempt $attempt @arguments|Out-Null
    }|Out-Null
$loaded=(Get-PtReportState $run).ExecutionStatistics.Data
Require ($loaded.RunId -eq $run.Id -and $loaded.Cases.Count -eq 2 -and $loaded.ModuleTotals.AgentToolRequests -eq 3) 'Registered statistics did not load through the existing report API'
Invoke-PtVerificationCase -Run $run -Context Diagnostic -Kind Diagnostic -Name 'Earlier malformed statistics' `
    -Command 'Create synthetic bad metadata to verify report-only repair' -Action {
        param($attempt)
        $path=New-PtVerificationArtifactPath -Attempt $attempt -Name 'statistics.json'
        Write-PtReportText $path '{"RunId":"wrong","CountingMode":"agent-origin-requests"}'
        Add-PtVerificationArtifact -Attempt $attempt -Path $path -Kind Evidence -Description 'Synthetic prior bad report metadata'|Out-Null
    }|Out-Null
Reject {Get-PtReportState $run} 'belonging to this run'
Invoke-PtVerificationCase -Run $run -Context Diagnostic -Kind Diagnostic -Name 'Repair statistics only' `
    -Command 'Replace only report metadata without replaying the recorded cases' -ArgumentList @($register) -Action {
        param($attempt,$arguments)
        Add-PtAgentExecutionStatistics -Attempt $attempt @arguments|Out-Null
    }|Out-Null
$repaired=Get-PtReportState $run
Require ($repaired.ExecutionStatistics.Data.RunId -eq $run.Id -and
    ($repaired.ExecutionStatistics.Data.Cases|Where-Object CaseId -eq I1).NormalAttempts -eq 1) 'Report-only repair failed or counted extra product execution'
$json=Join-Path $Workspace 'results.json'
Write-PtReportText $json '{"EarlyEntry":"PASS","Cutoff":"PASS","PendingCalls":"PASS","ExplicitAttribution":"PASS","OuterStepMetrics":"PASS","WaitUnion":"PASS","Privacy":"PASS","SourceValidation":"PASS","RecorderRegistration":"PASS"}'
"PASS: shared agent statistics extraction and registration; no product operations. $Workspace"
