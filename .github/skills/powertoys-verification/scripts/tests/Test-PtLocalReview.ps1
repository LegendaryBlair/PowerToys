#requires -Version 7.0
<#
.SYNOPSIS
Offline acceptance of local judgment correction and evidence reuse; never drives product UI.
#>
param([string]$Workspace = (Join-Path $env:TEMP "pt-local-review-$([Guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\pt-verification-report.ps1"
if (Test-Path $Workspace) { throw 'Use a new workspace.' }
[IO.Directory]::CreateDirectory($Workspace) | Out-Null
$proofFile = Join-Path $Workspace 'synthetic-observation.txt'
[IO.File]::WriteAllText($proofFile, 'Synthetic observation: snapshot lacks rows; independent render evidence shows them.')
$inputs = @(
    @{Name='skill.txt';Role='Skill';Path=$proofFile},
    @{Name='checklist.ps1';Role='Checklist';Path=$PSCommandPath},
    @{Name='recorder.ps1';Role='Helper';Path="$PSScriptRoot\..\pt-verification-report.ps1"}
)
function Require([bool]$Ok,[string]$Message) { if (-not $Ok) { throw $Message } }
function Reject([scriptblock]$Action,[string]$Pattern) {
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; return }
    throw "Expected rejection: $Pattern"
}
function NewRun([string]$Name) {
    $items = @(foreach ($id in 'L1','L2') {
        @{Id=$id;Description="Synthetic item $id";Admin='NO';Clarity='CLEAR';UserVisible=$false
          Assertions=@(@{Id='value';Description='Observe actual value';Required=$true})}
    })
    New-PtVerificationRun -Workspace "$Workspace\$Name" -Module 'Local review acceptance' -Bits 'Synthetic fixture only' `
        -Scenario InfrastructureAcceptance -Items $items -Inputs $inputs
}
function Collect($Run,[string]$Item) {
    Invoke-PtVerificationCase -Run $Run -ItemId $Item -Name 'Collect without judging' -Command 'Read synthetic observation' `
        -ArgumentList @($proofFile) -Action {
            param($attempt,$source)
            $evidence = Add-PtVerificationArtifact $attempt $source Evidence 'Observed fixture'
            $sequence = Add-PtVerificationObservation $attempt value -Actual 'Actual fixture contents observed' -Evidence @($evidence)
            [pscustomobject]@{Sequence=$sequence;Evidence=$evidence}
        }
}
function Commit($Case,[string]$Verdict='PASS',[string]$Category='synthetic fixture') {
    Add-PtVerificationAssertion $Case.Attempt value $Verdict $Category 'Reviewed actual evidence' -ObservationSequence $Case.Output[0].Sequence
}
$results = [Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action) {
    try { & $Action | Out-Null; $results.Add(@{Name=$Name;Status='PASS'}) }
    catch { $results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message}); throw }
    finally { $results | ConvertTo-Json -Depth 6 | Set-Content "$Workspace\acceptance-results.json" }
}
Check 'Raw observations remain unjudged until reviewed; thin lifecycle closes attempts' {
    $run = NewRun 'raw-review'
    $case = Collect $run L1
    Require $case.Attempt.Closed 'Case wrapper did not close its attempt'
    $case.Attempt = Get-PtVerificationAttempt -Run $run -AttemptId $case.Attempt.Id
    Reject { Invoke-PtVerificationStep $case.Attempt -Name 'Illegal continuation' -Command 'none' -Action { throw 'must not run' } } 'open verification attempt'
    $state = Get-PtReportState $run
    Require ($state.Items[0].Assertions[0].Verdict -eq 'NOT-OBSERVED') 'Data collection inferred a product PASS'
    Commit $case
    Complete-PtVerificationItem $run L1 -Reason 'Reviewed'
    Require ((Get-PtReportState $run).Items[0].Verdict -eq 'PASS') 'Review of closed attempt failed'
    Reject { Commit $case } 'completed'
    Require ($null -eq (Get-PtActiveVerificationAttempt)) 'Ambient context leaked'
}
Check 'Wrong product judgment corrected locally without rerunning an unrelated completed item' {
    $run = NewRun 'local-correction'
    $good = Collect $run L1
    Commit $good
    Complete-PtVerificationItem $run L1 -Reason 'Unrelated valid item'
    $bad = Collect $run L2
    Commit $bad FAIL product
    $oldSequence = $run.Sequence
    Complete-PtVerificationItem $run L2 -Reason 'Premature missing-row judgment'
    $before = Get-PtReportState $run
    $unrelated = $before.Items[0] | ConvertTo-Json -Depth 30 -Compress
    $oldJournal = [IO.File]::ReadAllText("$($run.Workspace)\events.jsonl")
    Reopen-PtVerificationItem $run L2 -Reason 'Screenshot disproved the incomplete UIA observation'
    $retry = Collect $run L2
    Commit $retry
    Require ((Get-PtReportState $run).Items[1].Verdict -eq 'FAIL') 'An ordinary retry washed away a prior product failure'
    Invalidate-PtVerificationAssertion -Attempt $retry.Attempt -Sequence $oldSequence -Cause InvalidObservation `
        -Reason 'Reviewed snapshot contained only host infrastructure; it never established missing product rows' -Evidence @($retry.Output[0].Evidence)
    Complete-PtVerificationItem $run L2 -Reason 'Corrected invalid observation, then repeated this item only'
    $after = Get-PtReportState $run
    Require ($after.Items[1].Verdict -eq 'PASS' -and $after.Items[1].Corrections.Count -eq 1) 'Local correction did not take effect'
    Require (($after.Items[0] | ConvertTo-Json -Depth 30 -Compress) -ceq $unrelated) 'Unrelated completed result changed'
    Require (@($after.Attempts | Where-Object ItemId -eq L1).Count -eq 1) 'Unrelated item was repeated'
    Require ([IO.File]::ReadAllText("$($run.Workspace)\events.jsonl").StartsWith($oldJournal)) 'Correction rewrote history'
    Require (@($after.Items[1].Observations | Where-Object {$_.Data.Verdict -eq 'FAIL'}).Count -eq 1) 'Original mistaken failure was erased'
    Reject {
        Invalidate-PtVerificationAssertion $retry.Attempt $oldSequence InvalidObservation 'Repeated correction' @($retry.Output[0].Evidence)
    } 'reopen|completed'
    $sealed = Complete-PtVerificationRun $run -NoFriction
    Reject { Reopen-PtVerificationItem $run L2 -Reason 'Change sealed run' } 'completed'
    Require (Test-PtVerificationArchive $run.Workspace).Valid 'Corrected history did not validate'
    $details = [IO.File]::ReadAllText($sealed.Details)
    Require ($details.Contains("Judgment $oldSequence invalidated")) 'Full trace hid the judgment correction'
    $summary = [IO.File]::ReadAllText($sealed.Report)
    Require ($summary.Contains('details.md#item-L2')) 'Summary does not link to corrected item trace'
    $manifest = Get-Content $sealed.Manifest -Raw | ConvertFrom-Json
    Require ($manifest.DetailsPath -eq 'details.md') 'Manifest omitted report-details identity'
    $detailsPath = $sealed.Details
    $bytes = [IO.File]::ReadAllBytes($detailsPath)
    [IO.File]::WriteAllText($detailsPath,'corrupted details')
    Reject { Test-PtVerificationArchive $run.Workspace } 'Changed evidence'
    [IO.File]::WriteAllBytes($detailsPath,$bytes)
    $manifest.Files = @($manifest.Files | Where-Object Path -ne 'details.md')
    $omitted = Join-Path $run.Workspace 'omitted-details.json'
    $manifest | ConvertTo-Json -Depth 15 | Set-Content $omitted
    Reject { Test-PtVerificationArchive $run.Workspace -ManifestName 'omitted-details.json' } 'omits'
}
Check 'Diagnostic recovery and unrelated evidence cannot revoke a real failure' {
    $run = NewRun 'correction-guards'
    $bad = Collect $run L1
    Commit $bad FAIL product
    $old = $run.Sequence
    $diagnostic = Start-PtVerificationAttempt $run -ItemId L1 -Kind Diagnostic -Name 'Restart recovery'
    $diagProof = Add-PtVerificationArtifact $diagnostic $proofFile Evidence 'Diagnostic only'
    Reject { Invalidate-PtVerificationAssertion $diagnostic $old InvalidObservation 'Restart works' @($diagProof) } 'Normal item'
    Stop-PtVerificationAttempt $diagnostic -Reason 'Diagnostic is not normal evidence'
    $other = Collect $run L2
    Reject { Invalidate-PtVerificationAssertion $other.Attempt $old InvalidObservation 'Wrong item' @($other.Output[0].Evidence) } 'same item'
    $retry = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Normal retry'
    $linked = Add-PtVerificationArtifact $retry (Join-Path $run.Workspace $diagProof.Path) Evidence 'Imported recovery'
    Reject { Invalidate-PtVerificationAssertion $retry $old InvalidObservation 'Recovery is not fresh evidence' @($linked) } 'fresh Normal evidence'
    Reject { Invalidate-PtVerificationAssertion $retry $old ProductFixed 'Not a judgment error' @($linked) } 'ValidateSet|does not belong|cannot validate'
    Require ((Get-PtReportState $run).Items[0].Verdict -eq 'FAIL') 'Invalid correction altered the real failure'
}
Check 'Repeated evidence registration reuses bytes and preserves cross-attempt provenance' {
    $run = NewRun 'evidence-reuse'
    $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Diagnostic -Name 'Old recovery'
    $one = Add-PtVerificationArtifact $a $proofFile Evidence 'First description'
    $two = Add-PtVerificationArtifact $a (Join-Path $run.Workspace $one.Path) Evidence 'Reference to the same evidence'
    $three = Add-PtVerificationArtifact $a $proofFile Evidence 'Repeat source import'
    Require ($one.Path -ceq $two.Path -and $one.Path -ceq $three.Path) 'Same-attempt reuse made duplicate files'
    Require (@(Read-PtReportEvents $run | Where-Object Type -eq ArtifactAdded).Count -eq 1) 'Reuse made duplicate registrations'
    $b = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'New ordinary flow'
    $history = Add-PtVerificationArtifact $b (Join-Path $run.Workspace $one.Path) Evidence 'History'
    Require ($history.Path -ceq $one.Path -and $history.OriginAttemptId -ceq $a.Id -and $history.ReferenceOnly) 'Cross-attempt provenance lost'
    Reject { Add-PtVerificationAssertion $b value PASS 'reference' 'Recovery proof reused' -Evidence @($history) } 'fresh PASS'
    $bytes = [IO.File]::ReadAllBytes((Join-Path $run.Workspace $one.Path))
    [IO.File]::WriteAllText((Join-Path $run.Workspace $one.Path), 'changed')
    Reject { Add-PtVerificationArtifact $a (Join-Path $run.Workspace $one.Path) Evidence 'Changed' } 'Changed evidence'
    [IO.File]::WriteAllBytes((Join-Path $run.Workspace $one.Path),$bytes)
}
Check 'Thin case wrapper preserves the original error and closes the failed attempt' {
    $run = NewRun 'thin-error'
    Reject { Invoke-PtVerificationCase -Run $run -ItemId L1 -Name 'Driver error' -Command 'throw original' -Action { throw 'original driver error' } } 'original driver error'
    $state = Get-PtReportState $run
    Require ($state.Attempts[0].Complete -and $state.Steps[0].Status -eq 'Error') 'Error did not close cleanly'
    Require ($state.Items[0].Verdict -eq 'BLOCKED') 'Driver failure became product failure'
}
Check 'Thin run template executes review then cleanup; a root failure still produces cleanup and partial output' {
    $skill = [IO.Path]::GetFullPath("$PSScriptRoot\..\..")
    $template = "$skill\templates\verification-run.ps1"
    $items = @(@{Id='T1';Description='Template fixture';Admin='NO';Clarity='CLEAR';UserVisible=$false
        Assertions=@(@{Id='value';Description='Read synthetic value';Required=$true})})
    $preflight = { param($attempt) 'Synthetic preflight only' }
    $cases = {
        param($run)
        $case = Invoke-PtVerificationCase -Run $run -ItemId T1 -Name 'Synthetic data' -Command 'Read a fixture' -ArgumentList @($proofFile) -Action {
            param($attempt,$path)
            $proof = Add-PtVerificationArtifact $attempt $path Evidence 'Observed synthetic fixture'
            Add-PtVerificationObservation $attempt value -Actual 'Fixture read' -Evidence @($proof)
        }
        Add-PtVerificationAssertion $case.Attempt value PASS 'Synthetic data review' 'Reviewed' -ObservationSequence $case.Output[0]
        Complete-PtVerificationItem $run T1 -Reason 'Reviewed'
    }
    $cleanup = {
        param($attempt)
        $proof = Add-PtVerificationArtifact $attempt $proofFile Restoration 'Synthetic cleanup comparison'
        Add-PtVerificationRestoration $attempt -Verdict PASS -Reason 'Only local fixture output was produced; product state untouched' -Evidence @($proof)
    }
    $arguments = @{
        Skill=$skill;Module='Thin template acceptance';Bits='Synthetic fixture only';Scenario='InfrastructureAcceptance'
        Items=$items;Inputs=$inputs;Preflight=$preflight;Cleanup=$cleanup;NoFriction=$true
    }
    $result = & $template @arguments -Workspace "$Workspace\template-pass" -Cases $cases
    Require ($result.Signoff -eq 'APPROVED') 'Template did not finalize complete reviewed coverage'
    Require (Test-PtVerificationArchive "$Workspace\template-pass").Valid 'Template archive invalid'
    Reject { & $template @arguments -Workspace "$Workspace\template-fail" -Cases { throw 'original case failure' } } 'original case failure'
    $partial = Get-ChildItem "$Workspace\template-fail" -Filter '*results.json' | Select-Object -First 1
    $state = Get-Content $partial.FullName -Raw | ConvertFrom-Json
    Require ($state.CurrentRestoration[0].Data.Verdict -eq 'PASS' -and $state.Signoff -eq 'WITHHELD') 'Failure skipped cleanup or became approved'
    $resumeArguments = $arguments.Clone()
    $resumeArguments.Items = (ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$Workspace\template-fail\run.json"))).Items
    $resumed = & $template @resumeArguments -Workspace "$Workspace\template-fail" -Cases $cases -Resume
    Require ($resumed.Signoff -eq 'APPROVED') 'Template could not continue a safely closed partial run'
    Reject { & $template @resumeArguments -Workspace "$Workspace\template-fail" -Cases $cases -Resume } 'completed'
}
Check 'Reparse validation supports long evidence paths without allowing redirecting junctions' {
    $parent = Join-Path $Workspace (('long-' + ('x' * 90)) + '\' + ('y' * 90))
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $target = Join-Path $Workspace 'long-junction-target'
    [IO.Directory]::CreateDirectory($target) | Out-Null
    $link = Join-Path $parent ('link-' + ('z' * 35))
    Require ($link.Length -gt 260) 'Long-path fixture is not long enough'
    New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
    try { Reject { Assert-PtReportNoLink $link } 'Redirecting/unsupported reparse point' }
    finally { [IO.Directory]::Delete($link) }
}
"PASS: $($results.Count) local review groups. Evidence: $Workspace"
