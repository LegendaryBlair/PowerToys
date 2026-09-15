#requires -Version 7.0
<#
.SYNOPSIS
Offline acceptance for partial assertion coverage, cleanup recovery and script-file context.
#>
param([string]$Workspace=(Join-Path $env:TEMP "pt-continuations-$([Guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-verification-report.ps1"
if(Test-Path -LiteralPath $Workspace){throw 'Use a new acceptance workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$proof=Join-Path $Workspace 'fixture.txt'
[IO.File]::WriteAllText($proof,'Synthetic fixture only. No product or desktop changes.')
$inputs=@(
    @{Name='fixture.txt';Role='Skill';Path=$proof}
    @{Name='tests.ps1';Role='Checklist';Path=$PSCommandPath}
    @{Name='recorder.ps1';Role='Helper';Path="$PSScriptRoot\..\pt-verification-report.ps1"}
)
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return $_}
    throw "Expected error: $Pattern"
}
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace})}
    finally{
        Set-PtActiveVerificationAttempt -Attempt $null
        $results.ToArray()|ConvertTo-Json -Depth 8|Set-Content -LiteralPath "$Workspace\results.json"
    }
}
function NewRun([string]$Name){
    $run=New-PtVerificationRun -Workspace "$Workspace\$Name" -Module 'Continuation acceptance' `
        -Bits 'Offline synthetic only' -Scenario InfrastructureAcceptance -Inputs $inputs -Items @(
            @{Id='I1';Description='Two independent expectations in one scenario';Admin='NO';Clarity='CLEAR';UserVisible=$false
                Assertions=@(@{Id='first';Description='First value matches'},@{Id='second';Description='Second value matches'})}
        )
    $a=Start-PtVerificationAttempt $run -Context Preflight -Kind Normal -Name preflight
    Invoke-PtVerificationStep $a -Name preflight -Command 'Synthetic preflight' -Action {'offline'}|Out-Null
    Stop-PtVerificationAttempt $a -Reason 'No external prerequisites'
    $run
}
function Observe($Run,[string[]]$Ids=@('first','second'),[string]$Verdict='PASS',[string]$Kind='Normal'){
    $a=Start-PtVerificationAttempt $Run -ItemId I1 -Kind $Kind -Name "Observe $($Ids -join ',')"
    Invoke-PtVerificationStep $a -Name observation -Command 'Read synthetic values' -Action {'observed'}|Out-Null
    $evidence=Add-PtVerificationArtifact $a $proof Evidence 'Synthetic observed values' -Synthetic
    foreach($id in $Ids){
        $category=switch($Verdict){FAIL {'product'} BLOCKED {'BLK-ENV'} default {'fixture'}}
        Add-PtVerificationAssertion $a $id $Verdict $category 'Synthetic comparison' -Evidence @($evidence)
    }
    Stop-PtVerificationAttempt $a -Reason 'Specified assertions observed'
    $a
}
function Restore($Run,[string[]]$Verdicts=@('PASS')){
    $a=Start-PtVerificationAttempt $Run -Context Cleanup -Kind Normal -Name 'Complete baseline comparison'
    Invoke-PtVerificationStep $a -Name cleanup -Command 'Compare every mutated resource to its baseline' -Action {'compared'}|Out-Null
    $evidence=Add-PtVerificationArtifact $a $proof Restoration 'Fresh complete synthetic baseline comparison' -Synthetic
    foreach($verdict in $Verdicts){Add-PtVerificationRestoration $a $verdict 'Synthetic restoration result' -Evidence @($evidence)}
    Stop-PtVerificationAttempt $a -Reason 'Complete scope reviewed'
    $a
}
function Finish($Run){
    Complete-PtVerificationItem $Run I1 -Reason 'All registered assertions reviewed'
    Complete-PtVerificationRun $Run -NoFriction
}

Check 'Separate Normal attempts accumulate independent assertions and preserve their origins' {
    $run=NewRun partial
    $one=Observe $run @('first')
    $oneSequence=$run.Sequence-1
    $two=Observe $run @('second')
    Restore $run|Out-Null
    $export=Finish $run
    $state=Get-PtReportState $run
    Require ($export.Signoff -eq 'APPROVED') 'Partial Normal attempts discarded earlier valid coverage'
    Require ($state.Items[0].Assertions[0].AttemptId -ceq $one.Id -and $state.Items[0].Assertions[1].AttemptId -ceq $two.Id) 'Assertion origins are missing'
    Require ($state.Items[0].Assertions[0].Sequence -eq $oneSequence) 'Original judgment sequence changed'
    $review=Get-PtVerificationReview -Run $run
    Require ($review.Items[0].Assertions[0].AttemptId -ceq $one.Id) 'Incremental review lost assertion provenance'
    Require (Test-PtVerificationArchive $run.Workspace).Valid 'Partial coverage archive is invalid'
}
Check 'A targeted unreviewed observation blocks only its assertion and survives an unrelated continuation' {
    $run=NewRun pending
    Observe $run|Out-Null
    $a=Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name 'Reobserve first'
    Invoke-PtVerificationStep $a -Name read -Command 'Read a new first value' -Action {'new value'}|Out-Null
    $evidence=Add-PtVerificationArtifact $a $proof Evidence 'Fresh first-value observation' -Synthetic
    $sequence=Add-PtVerificationObservation $a first 'New value awaits review' -Evidence @($evidence)
    Stop-PtVerificationAttempt $a -Reason 'Observation awaiting review'
    Observe $run @('second')|Out-Null
    $review=Get-PtVerificationReview -Run $run
    Require ($review.Items[0].Assertions[0].Verdict -eq 'NOT-OBSERVED' -and $review.Items[0].Assertions[1].Verdict -eq 'PASS') 'Pending assertion reused old PASS or discarded unrelated PASS'
    Require (@($review.Items[0].Observations|Where-Object {$_.Sequence -eq $sequence -and -not $_.Reviewed}).Count -eq 1) 'Unrelated attempt hid pending review'
    Add-PtVerificationAssertion $a first PASS fixture 'Reviewed latest first value' -ObservationSequence $sequence
    Restore $run|Out-Null
    Require ((Finish $run).Signoff -eq 'APPROVED') 'Reviewed partial continuation did not complete'
}
Check 'Targeted BLOCKED replaces old PASS; Diagnostic PASS cannot replace Normal coverage' {
    $run=NewRun targeted
    Observe $run|Out-Null
    Observe $run @('first') BLOCKED|Out-Null
    Observe $run @('first') PASS Diagnostic|Out-Null
    $state=Get-PtReportState $run
    Require ($state.Items[0].Assertions[0].Verdict -eq 'BLOCKED' -and $state.Items[0].Assertions[1].Verdict -eq 'PASS') 'Targeted result or unrelated coverage was lost'
    Observe $run @('first')|Out-Null
    Restore $run|Out-Null
    Require ((Finish $run).Signoff -eq 'APPROVED') 'Fresh Normal evidence did not resolve targeted BLOCKED'
}
Check 'A repaired partial driver failure retains valid coverage but an unresolved latest error still blocks' {
    $run=NewRun partial-driver-repair
    $a=Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name 'First passes before second driver fails'
    Invoke-PtVerificationStep $a -Name first -Command 'Observe first value' -Action {'first'}|Out-Null
    $evidence=Add-PtVerificationArtifact $a $proof Evidence 'Observed first value' -Synthetic
    Add-PtVerificationAssertion $a first PASS fixture 'First value matched' -Evidence @($evidence)
    Reject {Invoke-PtVerificationStep $a -Name second -Command 'Synthetic second observer error' -Action {throw 'second observer failed'}} 'second observer failed'|Out-Null
    Stop-PtVerificationAttempt $a -Reason 'Second observer needs repair'
    Require ((Get-PtReportState $run).Items[0].Category -eq 'BLK-INFRASTRUCTURE') 'Current driver error did not block'
    Observe $run @('second')|Out-Null
    Restore $run|Out-Null
    Require ((Finish $run).Signoff -eq 'APPROVED') 'Repairing the second observer discarded the successful first assertion'
    Require (@((Get-PtReportState $run).Steps|Where-Object Status -eq Error).Count -eq 1) 'Original driver error disappeared'
}
Check 'Review order within one attempt cannot replace a newer observation with an older one' {
    $run=NewRun observation-order
    $a=Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name 'Two observations'
    Invoke-PtVerificationStep $a -Name read -Command 'Collect two synthetic observations' -Action {'observed'}|Out-Null
    $evidence=Add-PtVerificationArtifact $a $proof Evidence 'Synthetic observed values' -Synthetic
    $old=Add-PtVerificationObservation $a first 'Earlier condition missing' -Evidence @($evidence)
    $new=Add-PtVerificationObservation $a first 'Latest condition satisfied' -Evidence @($evidence)
    Stop-PtVerificationAttempt $a -Reason 'Review queued observations'
    Add-PtVerificationAssertion $a first PASS fixture 'Latest value matches' -ObservationSequence $new
    Add-PtVerificationAssertion $a first BLOCKED BLK-ENV 'Earlier condition was missing' -ObservationSequence $old
    Observe $run @('second')|Out-Null
    Restore $run|Out-Null
    Require ((Finish $run).Signoff -eq 'APPROVED') 'Review arrival order replaced the latest actual observation'
    Require ((Get-PtReportState $run).Items[0].Assertions[0].ObservationSequence -eq $new) 'Selected observation provenance is incorrect'
}
Check 'Real failures remain sticky while unrelated coverage survives a correction of an invalid judgment' {
    $run=NewRun correction
    Observe $run @('first') FAIL|Out-Null
    $failureSequence=$run.Sequence-1
    $second=Observe $run @('second')
    $retry=Observe $run @('first')
    Require ((Get-PtReportState $run).Items[0].Verdict -eq 'FAIL') 'Later success erased a real failure'
    $evidence=@(Read-PtReportEvents $run|Where-Object {$_.Type -eq 'ArtifactAdded' -and $_.AttemptId -ceq $retry.Id})[0].Data.File
    Invalidate-PtVerificationAssertion $retry $failureSequence InvalidObservation 'Synthetic original observer was wrong' @($evidence)
    Restore $run|Out-Null
    Require ((Finish $run).Signoff -eq 'APPROVED') 'Corrected assertion discarded the unrelated successful assertion'
    Require ((Get-PtReportState $run).Items[0].Assertions[1].AttemptId -ceq $second.Id) 'Correction changed unrelated provenance'
}
Check 'Historical cleanup failure does not veto a later fully verified restoration' {
    $run=NewRun restored
    Observe $run|Out-Null
    Restore $run @('FAIL')|Out-Null
    $oldJournal=[IO.File]::ReadAllText("$($run.Workspace)\events.jsonl")
    Restore $run|Out-Null
    $export=Finish $run
    $state=Get-PtReportState $run
    Require ($export.Signoff -eq 'APPROVED') 'Historical restoration failure vetoed current successful restoration'
    Require ($state.HistoricalRestorationFailures.Count -eq 1 -and $state.CurrentRestoration.Count -eq 1) 'Restoration history was erased'
    Require ([IO.File]::ReadAllText("$($run.Workspace)\events.jsonl").StartsWith($oldJournal)) 'Cleanup recovery rewrote history'
    Require (Test-PtVerificationArchive $run.Workspace).Valid 'Recovered archive is invalid'
}
Check 'Delayed review of an old attempt cannot replace a newer result for the same assertion' {
    $run=NewRun delayed-review
    $a=Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name 'Earlier observation'
    Invoke-PtVerificationStep $a -Name read -Command 'Read earlier value' -Action {'earlier'}|Out-Null
    $evidence=Add-PtVerificationArtifact $a $proof Evidence 'Earlier synthetic value' -Synthetic
    $sequence=Add-PtVerificationObservation $a first 'Earlier unreviewed value' -Evidence @($evidence)
    Stop-PtVerificationAttempt $a -Reason 'Review deferred'
    $later=Observe $run
    Add-PtVerificationAssertion $a first BLOCKED BLK-ENV 'Earlier condition was missing' -ObservationSequence $sequence
    Restore $run|Out-Null
    Require ((Finish $run).Signoff -eq 'APPROVED') 'Late review replaced newer Normal evidence'
    Require ((Get-PtReportState $run).Items[0].Assertions[0].AttemptId -ceq $later.Id) 'Late review changed current provenance'
}
Check 'Invalidating a later judgment does not resurrect an older PASS without a replacement observation' {
    $run=NewRun correction-needs-observation
    Observe $run|Out-Null
    Observe $run @('first') FAIL|Out-Null
    $sequence=$run.Sequence-1
    $a=Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name 'Correct only the bad judgment'
    Invoke-PtVerificationStep $a -Name correction -Command 'Prove earlier observer invalid, without retesting product' -Action {'invalid observer'}|Out-Null
    $evidence=Add-PtVerificationArtifact $a $proof Evidence 'Synthetic observer defect evidence' -Synthetic
    Invalidate-PtVerificationAssertion $a $sequence InvalidObservation 'Observer was invalid; no replacement result yet' @($evidence)
    Stop-PtVerificationAttempt $a -Reason 'Correction is not a new PASS'
    $state=Get-PtReportState $run
    Require ($state.Items[0].Assertions[0].Verdict -eq 'NOT-OBSERVED' -and $state.Items[0].Assertions[1].Verdict -eq 'PASS') 'Invalidation fabricated a replacement result or dropped unrelated coverage'
}
Check 'One successful resource does not hide another current restoration failure' {
    $run=NewRun still-unrestored
    Observe $run|Out-Null
    Restore $run @('FAIL','PASS')|Out-Null
    Require ((Finish $run).Signoff -eq 'WITHHELD') 'Current partial restoration was approved'
}
Check 'A cleanup retry cannot recycle an earlier receipt as fresh final-state evidence' {
    $run=NewRun stale-restoration
    $old=Restore $run
    $file=@(Read-PtReportEvents $run|Where-Object {$_.Type -eq 'ArtifactAdded' -and $_.AttemptId -ceq $old.Id})[0].Data.File
    $retry=Start-PtVerificationAttempt $run -Context Cleanup -Kind Normal -Name retry
    $reference=Add-PtVerificationArtifact $retry (Join-Path $run.Workspace $file.Path) Restoration 'Old receipt' -Synthetic
    Reject {Add-PtVerificationRestoration $retry PASS 'No current comparison' @($reference)} 'fresh.*Restoration|Restoration.*fresh'|Out-Null
}
Check 'Diagnostic non-PASS policy is unchanged by Normal continuation and cleanup recovery' {
    $run=NewRun diagnostic-policy
    Observe $run|Out-Null
    Observe $run @('first') BLOCKED Diagnostic|Out-Null
    Restore $run|Out-Null
    Require ((Finish $run).Signoff -eq 'WITHHELD') 'Unrequested Diagnostic policy was changed'
}
Check 'ScriptFile preserves original paths, relative dependencies, arguments and caller location' {
    $run=NewRun script-context
    $sourceDirectory=Join-Path $Workspace 'source context'
    [IO.Directory]::CreateDirectory($sourceDirectory)|Out-Null
    $source=Join-Path $sourceDirectory 'case.ps1'
    [IO.File]::WriteAllText((Join-Path $sourceDirectory 'dependency.ps1'),'function Get-FixtureValue { "sibling" }')
    [IO.File]::WriteAllText((Join-Path $sourceDirectory 'data.txt'),'fixture-data')
    [IO.File]::WriteAllText($source,@'
param($attempt,$argument)
. "$PSScriptRoot\dependency.ps1"
[pscustomobject]@{
    Root=$PSScriptRoot; Path=$PSCommandPath; InvocationPath=$MyInvocation.MyCommand.Path
    Data=[IO.File]::ReadAllText("$PSScriptRoot\data.txt"); Dependency=Get-FixtureValue
    Location=(Get-Location).Path; Argument=$argument; AttemptId=$attempt.Id
}
'@)
    Push-Location $Workspace
    try{
        $case=Invoke-PtVerificationCase -Run $run -ItemId I1 -Name 'Original script context' -Command 'Run source context\case.ps1' `
            -Stage Observe -ScriptFile '.\source context\case.ps1' -ArgumentList @('original-argument')
        $output=$case.Output[0]
        Require ($output.Root -ceq $sourceDirectory -and $output.Path -ceq $source -and $output.InvocationPath -ceq $source) 'Original script identity changed'
        Require ($output.Data -ceq 'fixture-data' -and $output.Dependency -ceq 'sibling') 'Relative dependencies did not resolve'
        Require ($output.Location -ceq $Workspace -and $output.Argument -ceq 'original-argument' -and $output.AttemptId -ceq $case.Attempt.Id) 'Caller scope or case arguments changed'
        Require ((Get-Location).Path -ceq $Workspace) 'Recorded script changed caller location'
        $fileSteps=@((Get-PtReportState $run).Steps|Where-Object {$_.AttemptId -ceq $case.Attempt.Id -and $_.ScriptFile})
        Require ($fileSteps.Count -eq 1) 'Original script must have one producing file step'
        $step=$fileSteps[0]
        Require ($step.ScriptFile -ceq $source) 'Original execution path is absent from the step record'
        $snapshot=@($step.Sources|Where-Object {$_.Path.EndsWith('\executed.ps1')})[0]
        Require ((Get-FileHash -LiteralPath $source).Hash -ceq $snapshot.Sha256) 'Executed source and archived snapshot differ'
    }finally{Pop-Location}
}
Check 'Executing source cannot change mid-call; its read lease releases even on an error' {
    $run=NewRun script-lease
    $source=Join-Path $Workspace 'self-edit.ps1'
    [IO.File]::WriteAllText($source,'param($path) [IO.File]::WriteAllText($path,''"unexpected replacement"'')')
    $before=(Get-FileHash -LiteralPath $source).Hash
    $a=Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name lease
    Reject {Invoke-PtVerificationStep $a -Name self-edit -Command 'Synthetic source write attempt' -ScriptFile $source -ArgumentList @($source)} 'used by another process|sharing|access'|Out-Null
    Require ((Get-FileHash -LiteralPath $source).Hash -ceq $before) 'Executing file was modified'
    [IO.File]::WriteAllText($source,'"next-version"')
    Require ((Invoke-PtVerificationStep $a -Name next -Command 'Run revised source after release' -ScriptFile $source) -ceq 'next-version') 'Read lease leaked or source revision was lost'
}
Check 'A source change after snapshot capture prevents execution, records no driver failure and still cleans up' {
    $run=NewRun changed-before-execution
    . "$PSScriptRoot\..\pt-verification-operation.ps1"
    $changingSource=Join-Path $Workspace 'changing-source.ps1'
    [IO.File]::WriteAllText($changingSource,'param($counter) $counter.Calls++; "original"')
    $counter=@{Calls=0;Cleanups=0;Edited=$false}
    $savedWriter=${function:Write-PtReportSource}
    function Write-PtReportSource {
        param($Run,[byte[]]$Bytes,[string]$Name)
        $reference=& $savedWriter $Run $Bytes $Name
        if($Name -eq 'executed.ps1' -and -not $counter.Edited){
            $counter.Edited=$true
            [IO.File]::WriteAllText($changingSource,'param($counter) $counter.Calls++; "replacement"')
        }
        $reference
    }
    $a=Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name 'Source drift'
    try{
        Reject {
            Invoke-PtVerificationOperation $a -Stage Observe -Command 'Observe source drift' -ScriptFile $changingSource `
                -ArgumentList @($counter) -Cleanup {param($c) $c.Cleanups++} -CleanupArgumentList @($counter)
        } 'source changed.*not started'|Out-Null
    }finally{Set-Item Function:\Write-PtReportSource $savedWriter}
    Require ($counter.Calls -eq 0 -and $counter.Cleanups -eq 1) 'Changed source executed or cleanup was skipped'
    $end=@(Read-PtReportEvents $run|Where-Object Type -eq OperationEnded)[0].Data
    Require ($end.ActionStarted -ceq $false -and -not $end.Failed -and $end.ActionDurationTicks -eq 0) 'Pre-execution source rejection was charged as a driver failure'
    Require ((Get-PtVerificationOperationStatus $run).UncertainOperations.Count -eq 0) 'Known unexecuted source was reported as uncertain execution'
    Require ((Invoke-PtVerificationOperation $a -Stage Observe -Command 'Record and execute updated source' -ScriptFile $changingSource -ArgumentList @($counter)) -ceq 'replacement') 'Corrected invocation was locked'
}

$results.ToArray()|ForEach-Object {[pscustomobject]$_}|Format-Table Name,Status -AutoSize
if(@($results|Where-Object Status -eq FAIL).Count){throw "Continuation regressions failed. Evidence: $Workspace"}
"PASS: $($results.Count) continuation groups. Evidence: $Workspace"
