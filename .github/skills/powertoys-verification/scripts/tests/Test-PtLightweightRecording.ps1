#requires -Version 7.0
<#
.SYNOPSIS
Offline H09 contracts, including archived verdict parity and measured recording/review cost.
#>
param(
    [string]$Workspace=(Join-Path $env:TEMP "pt-lightweight-$([Guid]::NewGuid().ToString('N'))"),
    [string]$ArchivedWorkspace,
    [string]$BaselineRecorder,
    [ValidateSet('Contracts','Benchmark')][string]$Mode='Contracts',
    [string]$Recorder=(Join-Path (Split-Path $PSScriptRoot -Parent) 'pt-verification-report.ps1')
)
$ErrorActionPreference='Stop'
. $Recorder
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$proof=Join-Path $Workspace 'fixture.txt'
[IO.File]::WriteAllText($proof,'Synthetic observation; no product or desktop access.')
$inputs=@(
    @{Name='skill.txt';Role='Skill';Path=$proof}
    @{Name='checklist.ps1';Role='Checklist';Path=$PSCommandPath}
    @{Name='recorder.ps1';Role='Helper';Path=$Recorder}
)
function NewRun([string]$Name){
    $items=@(foreach($id in 'L1','L2'){
        @{Id=$id;Description="Synthetic $id";Admin='NO';Clarity='CLEAR';UserVisible=$false
            Assertions=@(@{Id='value';Description='Observe actual value';Required=$true})}
    })
    New-PtVerificationRun -Workspace "$Workspace\$Name" -Module 'H09 acceptance' -Bits 'Offline synthetic only' `
        -Scenario InfrastructureAcceptance -Items $items -Inputs $inputs
}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
function Collect($Run,[string]$Item='L1'){
    Invoke-PtVerificationCase -Run $Run -ItemId $Item -Name 'Observe fixture' -Command 'Read one synthetic fixture' -ArgumentList @($proof) -Action {
        param($attempt,$path)
        $evidence=Add-PtVerificationArtifact $attempt $path Evidence 'Observed fixture'
        $sequence=Add-PtVerificationObservation $attempt value -Actual 'Observed fixture value' -Evidence @($evidence)
        [pscustomobject]@{Sequence=$sequence;Evidence=$evidence}
    }
}
function SameVerdicts($Run){
    $full=Get-PtReportState $Run
    $review=Get-PtVerificationReview $Run
    foreach($item in $full.Items){
        $row=@($review.Items|Where-Object Id -CEQ $item.Id)[0]
        Require ($row.Verdict -ceq $item.Verdict -and $row.Category -ceq $item.Category) "Review verdict differs: $($item.Id)"
        Require ((ConvertTo-Json -InputObject @($row.Issues) -Compress) -ceq (ConvertTo-Json -InputObject @($item.Issues) -Compress)) 'Review lost coverage issues'
        foreach($child in $item.Assertions){
            $shown=@($row.Assertions|Where-Object Id -CEQ $child.Id)[0]
            Require ($shown.Verdict -ceq $child.Verdict -and $shown.Required -eq $child.Required -and $shown.Description -ceq $child.Description) 'Review changed a child assertion'
        }
    }
    Require (-not $review.IntegrityValidated -and -not $review.PSObject.Properties['Signoff']) 'Review falsely claims archive validation'
}
if($Mode -eq 'Benchmark'){
    $run=NewRun benchmark
    $clock=[Diagnostics.Stopwatch]::StartNew()
    for($index=0;$index -lt 40;$index++){
        Invoke-PtVerificationCase -Run $run -ItemId L1 -Name "probe-$index" -Command "synthetic-probe $index" -ArgumentList @($index) -Action {
            param($attempt,$value)
            if($attempt.Run.Id -ne $run.Id){throw 'Actual callback did not receive its original handle'}
            "value-$value"
        }|Out-Null
    }
    $recordMs=$clock.Elapsed.TotalMilliseconds
    $clock.Restart()
    if(Get-Command Get-PtVerificationReview -ErrorAction Ignore){Get-PtVerificationReview $run|Out-Null}
    $clock.Restart()
    for($index=0;$index -lt 6;$index++){
        if(Get-Command Get-PtVerificationReview -ErrorAction Ignore){Get-PtVerificationReview $run|Out-Null}
        else{Get-PtReportState $run|Out-Null}
    }
    $reviewMs=$clock.Elapsed.TotalMilliseconds
    $files=@(Get-ChildItem $run.Workspace -File -Recurse)
    $scripts=@($files|Where-Object {$_.Name -in 'executed.ps1','implementation.ps1'})
    $argsBytes=(@($files|Where-Object Name -eq arguments.json)|Measure-Object Length -Sum).Sum
    $result=@{Steps=40;Reviews=6;RecordingMs=$recordMs;ReviewMs=$reviewMs;SourceFiles=$scripts.Count
        SourceBytes=($scripts|Measure-Object Length -Sum).Sum;ArgumentBytes=$argsBytes
        Files=$files.Count;Bytes=($files|Measure-Object Length -Sum).Sum}
    $result|ConvertTo-Json|Set-Content "$Workspace\benchmark.json"
    return
}
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace});throw}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
Check 'Shared sources preserve actual script versions and reject tampering before execution' {
    $run=NewRun sources
    $source=Join-Path $Workspace 'actual-script.ps1'
    [IO.File]::WriteAllText($source,'param($number) "version-one-$number"')
    $a=Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name source
    $one=Invoke-PtVerificationStep $a -Name first -Command first -ScriptFile $source -ArgumentList @(1)
    $two=Invoke-PtVerificationStep $a -Name second -Command second -ScriptFile $source -ArgumentList @(2)
    Require ($one -ceq 'version-one-1' -and $two -ceq 'version-one-2') 'Source dedup changed execution'
    $state=Get-PtReportState $run
    $refs=@($state.Steps|ForEach-Object Sources|Where-Object {$_.Path.EndsWith('\executed.ps1')})
    Require ($refs.Count -eq 2 -and $refs[0].Path -ceq $refs[1].Path) 'Identical script version was copied per step'
    $blob=Join-Path $run.Workspace $refs[0].Path
    $bytes=[IO.File]::ReadAllBytes($blob)
    [IO.File]::WriteAllText($blob,'throw "must never execute corrupted shared source"')
    Reject {Invoke-PtVerificationStep $a -Name corrupt -Command corrupt -ScriptFile $source} 'Changed evidence'
    [IO.File]::WriteAllBytes($blob,$bytes)
    [IO.File]::WriteAllText($source,'"version-two"')
    Require ((Invoke-PtVerificationStep $a -Name revised -Command revised -ScriptFile $source) -ceq 'version-two') 'Source revision did not execute'
    Require (@(Get-ChildItem "$($run.Workspace)\sources" -Filter executed.ps1 -File -Recurse).Count -eq 2) 'Revised script source lost its distinct identity'
}
Check 'Callback handles are recorded by identity without serializing mutable event caches' {
    $run=NewRun arguments
    $case=Collect $run
    $state=Get-PtReportState $run
    $argRef=@($state.Steps[0].Sources|Where-Object {$_.Path.EndsWith('\arguments.json')})[0]
    $text=[IO.File]::ReadAllText((Join-Path $run.Workspace $argRef.Path))
    $args=ConvertFrom-PtReportJson $text
    Require ($args[0].RecordedType -eq 'VerificationAttempt' -and $args[0].AttemptId -ceq $case.Attempt.Id -and $args[1] -ceq $proof) 'Recorded argument identity/value changed'
    Require ($text.Length -lt 2048 -and -not $text.Contains('EventCache')) 'Argument output grew with recorder state'
    Require ([object]::ReferenceEquals($run,$case.Attempt.Run)) 'Actual callback handle was replaced'
}
Check 'Incremental review matches full projection through raw, failure, retry, correction and reopen' {
    $run=NewRun review
    SameVerdicts $run
    $a=Collect $run
    SameVerdicts $run
    Add-PtVerificationAssertion $a.Attempt value FAIL product 'Incorrect initial observation' -ObservationSequence $a.Output[0].Sequence
    $failure=$run.Sequence
    Complete-PtVerificationItem $run L1 -Reason 'Initial review'
    SameVerdicts $run
    $warm=Get-PtVerificationReview $run
    Require ($warm.ProcessedEvents -eq 0 -and $warm.RecomputedItems -eq 0) 'Unchanged review reprojected the run'
    $b=Collect $run L2
    $delta=Get-PtVerificationReview $run
    Require ($delta.RecomputedItems -eq 1 -and $delta.Items[0].Verdict -eq 'FAIL') 'Unrelated update reprojected/changed L1'
    Add-PtVerificationAssertion $b.Attempt value PASS fixture 'Actual evidence' -ObservationSequence $b.Output[0].Sequence
    Complete-PtVerificationItem $run L2 -Reason 'Reviewed'
    Reopen-PtVerificationItem $run L1 -Reason 'Fix an invalid observation'
    $retry=Collect $run
    Add-PtVerificationAssertion $retry.Attempt value PASS fixture 'Fresh evidence' -ObservationSequence $retry.Output[0].Sequence
    SameVerdicts $run
    Require ((Get-PtVerificationReview $run -ItemId L1).Items[0].Verdict -eq 'FAIL') 'Retry erased historical failure'
    Invalidate-PtVerificationAssertion $retry.Attempt $failure InvalidObservation 'Original observation was invalid' @($retry.Output[0].Evidence)
    Complete-PtVerificationItem $run L1 -Reason 'Corrected and reviewed'
    SameVerdicts $run
    $again=Open-PtVerificationRun $run.Workspace
    Require ((Get-PtVerificationReview $again).Items[0].Verdict -eq 'PASS') 'Reopened review lost corrected history'
    Reject {Get-PtVerificationReview $again -ItemId Missing} 'Unknown review item'
    $detached=Get-PtVerificationReview $again
    $detached.Items[0].Verdict='FAIL'
    Require ((Get-PtVerificationReview $again).Items[0].Verdict -eq 'PASS') 'Caller mutation polluted cached state'
}
Check 'Large detail remains exact in one artifact and oversized Actual is rejected before journal changes' {
    $run=NewRun detail
    $a=Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name detail
    $large='tree-entry-'*100000
    $sequence=$run.Sequence
    Reject {Add-PtVerificationObservation $a value -Actual $large} 'at most 4096 UTF-8 bytes'
    Reject {Add-PtVerificationAssertion $a value FAIL product $large} 'at most 4096 UTF-8 bytes'
    Require ($sequence -eq $run.Sequence) 'Oversized observation partially mutated the journal'
    $seq=Invoke-PtVerificationStep $a -Name observed -Command 'Record concise facts and separate detail' -ArgumentList @($large) -Action {
        param($fullText)
        Add-PtVerificationObservation $a value -Actual 'Observed one complete synthetic tree' -Detail $fullText
    }
    $event=@(Read-PtReportEvents $run|Where-Object Sequence -eq $seq)[0]
    $reference=$event.Data.Evidence[0]
    Require ([IO.File]::ReadAllText((Join-Path $run.Workspace $reference.Path)) -ceq $large) 'Raw detail was truncated/changed'
    Require ((Get-Item "$($run.Workspace)\events.jsonl").Length -lt 30000) 'Full tree was embedded in the event journal'
    $review=Get-PtVerificationReview $run
    Require (($review|ConvertTo-Json -Depth 20).Length -lt 6000) 'Large detail leaked into daily review'
    Add-PtVerificationAssertion $a value PASS fixture 'Reviewed the actual tree' -ObservationSequence $seq
    Stop-PtVerificationAttempt $a -Reason 'Observed'
    Complete-PtVerificationItem $run L1 -Reason 'Reviewed'
    $export=Export-PtVerificationReport $run
    Require ((Get-Item $export.Details).Length -lt 40000) 'Raw tree leaked into Markdown'
    Require (Test-PtVerificationArchive $run.Workspace -ManifestName (Split-Path $export.Manifest -Leaf)).Valid 'Detail evidence is not covered by the archive'
}
Check 'Light review does not rehash artifacts; final validation still rejects changed evidence' {
    $run=NewRun integrity
    $a=Collect $run
    Get-PtVerificationReview $run|Out-Null
    $path=Join-Path $run.Workspace $a.Output[0].Evidence.Path
    $bytes=[IO.File]::ReadAllBytes($path)
    [IO.File]::WriteAllText($path,'corrupted artifact')
    try{
        $review=Get-PtVerificationReview $run
        Require (-not $review.IntegrityValidated -and $review.ProcessedEvents -eq 0) 'Live review pretends to validate evidence'
        Reject {Get-PtReportState $run} 'Changed evidence'
        Reject {Export-PtVerificationReport $run} 'Changed evidence'
    }finally{[IO.File]::WriteAllBytes($path,$bytes)}
    SameVerdicts $run
}
Check 'Error, Diagnostic and interrupted observations keep the same infrastructure classification' {
    $run=NewRun failures
    $normal=Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Driver failure'
    Reject {Invoke-PtVerificationStep $normal -Name failed -Command 'Throw a driver error' -Action {throw 'synthetic driver error'}} 'synthetic driver error'
    Stop-PtVerificationAttempt $normal -Reason 'Driver failed'
    SameVerdicts $run
    $diagnostic=Start-PtVerificationAttempt $run -ItemId L1 -Kind Diagnostic -Name 'Recovery only'
    $evidence=Add-PtVerificationArtifact $diagnostic $proof Evidence 'Recovery evidence only'
    Invoke-PtVerificationStep $diagnostic -Name recovery -Command 'Read recovery state' -Action {'Recovered'}|Out-Null
    Add-PtVerificationAssertion $diagnostic value PASS fixture 'Diagnostic works' -Evidence @($evidence)
    Stop-PtVerificationAttempt $diagnostic -Reason 'Diagnostic is not Normal coverage'
    SameVerdicts $run
    Require ((Get-PtVerificationReview $run).Items[0].Category -ceq 'BLK-INFRASTRUCTURE') 'Recovery laundered a Normal driver error'
    $interrupted=Start-PtVerificationAttempt $run -ItemId L2 -Kind Normal -Name 'Interrupted fixture'
    Add-PtReportEvent $run StepStarted @{Name='Synthetic interrupted step';Command='none';Start=[DateTimeOffset]::UtcNow.ToString('o')
        Sources=@();OutputPaths=@();ParentStepId=$null} $interrupted 'synthetic-interrupted'
    SameVerdicts $run
    Require ((Get-PtVerificationReview $run).Items[1].Verdict -ceq 'BLOCKED') 'Interrupted execution became PASS'
}
Check 'Observation limits count UTF-8 bytes and detail JSON preserves complete object structure' {
    $run=NewRun unicode-detail
    $a=Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name unicode
    $character=[string][char]0x4E2D
    $boundary=Add-PtVerificationObservation $a value -Actual ($character*1365)
    Require ($boundary -eq $run.Sequence) 'Valid 4095-byte observation was rejected'
    Reject {Add-PtVerificationObservation $a value -Actual ($character*1366)} '4096 UTF-8 bytes'
    $detail=[pscustomobject]@{nodes=@([pscustomobject]@{name='first';children=@([pscustomobject]@{name='child'})});value=$null}
    $sequence=Add-PtVerificationObservation $a value -Actual 'One parent and one child observed' -Detail $detail
    $event=@(Read-PtReportEvents $run|Where-Object Sequence -eq $sequence)[0]
    $text=[IO.File]::ReadAllText((Join-Path $run.Workspace $event.Data.Evidence[0].Path))
    Require ((ConvertFrom-PtReportJson $text).nodes[0].children[0].name -ceq 'child') 'Detail structure was truncated'
}
Check 'Case operations share budgets, always clean up and preserve original callback arguments' {
    $run=NewRun case-operation
    $counters=@{Driven=0;Cleaned=0}
    $driveFixtureAction={param($attempt,$counter) $counter.Driven++;throw 'case driver failure'}
    $fixtureCleanup={param($counter) $counter.Cleaned++}
    Reject {Invoke-PtVerificationCase -Run $run -ItemId L1 -Name first -Command first -OperationKey shared-host `
        -MaxFailures 1 -Action $driveFixtureAction -ArgumentList @($counters) -Cleanup $fixtureCleanup -CleanupArgumentList @($counters)} 'case driver failure'
    $stopped=$false
    try{
        Invoke-PtVerificationCase -Run $run -ItemId L2 -Name 'Another item same obstacle' -Command second `
            -OperationKey shared-host -Action $driveFixtureAction -ArgumentList @($counters) -Cleanup $fixtureCleanup -CleanupArgumentList @($counters)|Out-Null
    }catch{
        if($_.FullyQualifiedErrorId -notlike 'PtVerificationOperationBudgetExceeded*'){throw}
        $stopped=$true
    }
    Require ($stopped -and $counters.Driven -eq 1 -and $counters.Cleaned -eq 2) 'Case budget rejection drove again or skipped cleanup'
    $script=Join-Path $Workspace 'case-file.ps1'
    [IO.File]::WriteAllText($script,'param($attempt,$value) if(-not $attempt.Id){throw "Missing actual attempt"}; "file-$value"')
    $result=Invoke-PtVerificationCase -Run $run -ItemId L2 -Name 'Independent file case' -Command file `
        -OperationKey independent -Stage Observe -ScriptFile $script -ArgumentList @('observed')
    Require ($result.Output[0] -ceq 'file-observed' -and $result.Attempt.Closed) 'Operation-backed ScriptFile changed the case contract'
    $state=Get-PtReportState $run
    Require (@($state.Items|Where-Object Verdict -eq FAIL).Count -eq 0) 'Driver failures became product FAIL'
    Require ($state.Operations.Count -eq 2) 'Operation status is absent from full export state'
    $before=$run.Sequence
    Reject {Invoke-PtVerificationCase -Run $run -ItemId L2 -Name invalid -Command none -Action {} -Cleanup {}} 'require a stable OperationKey'
    Require ($run.Sequence -eq $before) 'Invalid operation configuration created an attempt'
}
Check 'Interrupted operations withhold signoff without changing fully passing product assertions' {
    $run=NewRun pending-signoff
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name preflight -Command preflight -Action {'Offline preflight'}|Out-Null
    foreach($id in 'L1','L2'){
        $case=Collect $run $id
        Add-PtVerificationAssertion $case.Attempt value PASS fixture 'Reviewed fixture' -ObservationSequence $case.Output[0].Sequence
        Complete-PtVerificationItem $run $id -Reason 'Complete'
    }
    $cleanup=Start-PtVerificationAttempt $run -Context Cleanup -Kind Normal -Name 'Offline restoration'
    Invoke-PtVerificationStep $cleanup -Name cleanup -Command cleanup -Action {'No live state changed'}|Out-Null
    $receipt=Add-PtVerificationArtifact $cleanup $proof Restoration 'Offline-only fixture comparison'
    Add-PtVerificationRestoration $cleanup PASS 'No live mutations' -Evidence @($receipt)
    Stop-PtVerificationAttempt $cleanup -Reason 'Complete'
    $key='pending-operation'
    $operationId=[Guid]::NewGuid().ToString('N')
    Add-PtReportEvent $run OperationPolicyLocked @{OperationKey=$key;MaxFailures=3;MaxRecoverySeconds=300}
    Add-PtReportEvent $run OperationStarted @{OperationKey=$key;OperationId=$operationId;Stage='Observe';Command='Synthetic interruption'
        Start=[DateTimeOffset]::UtcNow.ToString('o');Recovery=$false;Execution='Action'} $case.Attempt
    $export=Complete-PtVerificationRun $run -NoFriction
    $state=Get-PtReportState $run
    Require (@($state.Items|Where-Object Verdict -ne PASS).Count -eq 0) 'Pending infrastructure operation changed product assertions'
    Require ($state.Signoff -eq 'WITHHELD' -and ($state.SignoffReasons -join '|').Contains("Operation '$key' requires infrastructure recovery: Interrupted")) 'Interrupted operation was not an explicit signoff hold'
    Require ((Get-Content $export.Details -Raw).Contains('## Operation boundaries')) 'Details omit operation budget/interruption history'
    Require ((Get-Content $export.Report -Raw).Contains('details.md#operation-boundaries')) 'Compact report has no operation-details link'
    Require (Test-PtVerificationArchive $run.Workspace).Valid 'Operation-aware signoff did not validate after export'
}
if($ArchivedWorkspace){
    Check 'Authentic archived verdicts and required child coverage are unchanged by the shared projection' {
        $run=Open-PtVerificationRun $ArchivedWorkspace
        $saved=ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $ArchivedWorkspace 'results.json')))
        $fullClock=[Diagnostics.Stopwatch]::StartNew()
        $full=Get-PtReportState $run
        $fullClock.Stop()
        $expected=ConvertTo-Json -InputObject $saved.Items -Depth 80 -Compress
        $actual=ConvertTo-Json -InputObject $full.Items -Depth 80 -Compress
        Require ($expected -ceq $actual) 'Archived item projection changed'
        Require ($saved.Signoff -ceq $full.Signoff -and ($saved.SignoffReasons -join '|') -ceq ($full.SignoffReasons -join '|')) 'Archived signoff gates changed'
        SameVerdicts $run
        $clock=[Diagnostics.Stopwatch]::StartNew()
        1..5|ForEach-Object{Get-PtVerificationReview $run|Out-Null}
        $clock.Stop()
        @{Items=$full.Items.Count;Events=$full.Events.Count;WarmReviews=5;Milliseconds=$clock.Elapsed.TotalMilliseconds
            FullProjectionMilliseconds=$fullClock.Elapsed.TotalMilliseconds}|ConvertTo-Json|Set-Content "$Workspace\archive-review.json"
    }
}
if($BaselineRecorder){
    Check 'Same-workload benchmark reduces source/argument duplication and warm review time' {
        foreach($entry in @(@{Name='before';Recorder=$BaselineRecorder},@{Name='after';Recorder=$Recorder})){
            & (Get-Command pwsh).Source -NoProfile -File $PSCommandPath -Mode Benchmark -Recorder $entry.Recorder -Workspace "$Workspace\$($entry.Name)"
            if($LASTEXITCODE -ne 0){throw "Benchmark child failed: $($entry.Name)"}
        }
        $before=Get-Content "$Workspace\before\benchmark.json" -Raw|ConvertFrom-Json
        $after=Get-Content "$Workspace\after\benchmark.json" -Raw|ConvertFrom-Json
        Require ($after.SourceFiles -eq 1 -and $before.SourceFiles -eq 40) 'Same source version was not deduplicated'
        Require ($after.ArgumentBytes -lt $before.ArgumentBytes*0.2) 'Handle serialization remains too large'
        Require ($after.ReviewMs -lt $before.ReviewMs*0.3) 'Warm review did not improve by at least 70%'
        @{Before=$before;After=$after}|ConvertTo-Json -Depth 8|Set-Content "$Workspace\comparison.json"
    }
}
"PASS: $($results.Count) lightweight recording groups. $Workspace"
