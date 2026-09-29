#requires -Version 7.0
# Copyright (c) Microsoft Corporation
# Licensed under the MIT license.
<#
.SYNOPSIS
Dependency-free coordinator acceptance using real child processes and the existing report validator.
#>
param([string]$Workspace = (Join-Path $env:TEMP ("pt-coordinator-" + [Guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\Verification.psm1" -Force -DisableNameChecking
if (Test-Path -LiteralPath $Workspace) { throw 'Use a new test workspace.' }
[IO.Directory]::CreateDirectory($Workspace) | Out-Null
$repository = Join-Path $Workspace 'source'
[IO.Directory]::CreateDirectory($repository) | Out-Null
[IO.File]::WriteAllText((Join-Path $repository 'checklist.txt'), 'Synthetic expectation: observe value.')
[IO.File]::WriteAllText((Join-Path $repository 'skill.txt'), 'Synthetic offline fixture.')
[IO.File]::WriteAllText((Join-Path $repository 'helper.ps1'), 'function Get-VfFixtureValue { throw "Synthetic observer failure" }')
$proof = Join-Path $Workspace 'proof.txt'
[IO.File]::WriteAllText($proof, 'Synthetic operator evidence: worker stopped; no product state accessed.')
$root = Join-Path $Workspace 'coordinator'
$adapter = Join-Path $PSScriptRoot 'Invoke-FixtureWorker.ps1'
$checks = [Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message } }
function Reject([scriptblock]$Action,[string]$Pattern) {
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; return }
    throw "Expected rejection: $Pattern"
}
function Check([string]$Name,[scriptblock]$Action) {
    try { & $Action | Out-Null; $checks.Add(@{ name = $Name; status = 'PASS' }) }
    catch { $checks.Add(@{ name = $Name; status = 'FAIL'; error = $_.Exception.Message; stack = $_.ScriptStackTrace }); throw }
    finally { ConvertTo-Json -InputObject $checks.ToArray() -Depth 8 | Set-Content -LiteralPath "$Workspace\results.json" }
}
function Request([bool]$Live = $false) {
    $path = Join-Path $Workspace ("request-" + [Guid]::NewGuid().ToString('N') + '.json')
    @{
        module = 'Coordinator fixture'; bits = 'Synthetic only'; repositoryRoot = $repository
        scope = 'Only synthetic files. Never interact with the desktop.'; live = $Live; environment = 'synthetic-desktop'
        inputs = @(@{ path = 'checklist.txt'; role = 'checklist' }, @{ path = 'skill.txt'; role = 'skill' }, @{ path = 'helper.ps1'; role = 'helper' })
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path
    $path
}
function NewWorkflow([bool]$Live = $false) { New-VfWorkflow -Root $root -RequestFile (Request $Live) }
function Dispatch($Workflow,[string]$Worker) {
    Invoke-VfAgent -Root $root -WorkflowId $Workflow.id -WorkerId $Worker -Adapter $adapter
}
function Decision($Workflow,[string]$Value) {
    Decide-VfWorkflow -Root $root -WorkflowId $Workflow.id -Decision $Value -Actor 'synthetic-operator' -Reason "Fixture decision: $Value"
}
function FailedResult($Packet,[string]$Status = 'failed') {
    @{ taskId = $Packet.taskId; workerId = $Packet.workerId; status = $Status; summary = 'Synthetic failure'; evidence = @($proof) } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Packet.resultPath
}

Check 'Complete runner-reviewer-repairer-human-confirmation loop with immutable revisions' {
    $workflow = NewWorkflow
    $script:completedId = $workflow.id
    $originalHash = (Get-FileHash -LiteralPath (Join-Path $repository 'helper.ps1')).Hash
    $first = Dispatch $workflow 'runner-1'
    Require ($first.status -eq 'ready' -and $first.nextRole -eq 'reviewer') 'Runner did not queue independent review.'
    Require ($first.latestRun.archive.productSignoff -eq 'WITHHELD') 'Synthetic harness failure became a product pass.'
    Reject { Claim-VfTask -Root $root -WorkflowId $workflow.id -WorkerId 'runner-1' } 'Independent review'
    $reviewed = Dispatch $workflow 'reviewer-1'
    Require ($reviewed.status -eq 'awaiting-decision') 'Review bypassed the human decision.'
    Reject { Decision $workflow accept } 'Acceptance requires'
    Decision $workflow repair | Out-Null
    $candidate = Dispatch $workflow 'repairer-1'
    Require ($candidate.candidate.changes.Count -eq 1) 'Candidate delta was not captured.'
    Require ((Get-FileHash -LiteralPath (Join-Path $repository 'helper.ps1')).Hash -ceq $originalHash) 'Repair modified the original repository.'
    $confirmed = Decision $workflow confirm
    Require ($confirmed.revision -eq 2 -and $confirmed.nextRole -eq 'runner') 'Candidate was not frozen for confirmation.'
    $second = Dispatch $workflow 'runner-2'
    Require ($second.latestRun.archive.productSignoff -eq 'APPROVED') 'Confirmation did not observe the repaired helper.'
    Dispatch $workflow 'reviewer-2' | Out-Null
    $accepted = Decision $workflow accept
    Require ($accepted.status -eq 'review-accepted') 'Reviewed workflow did not complete.'
    Require ($accepted.tasks.Count -eq 5 -and $accepted.history.Count -eq 14) 'Role history was lost.'
    Require ([IO.File]::Exists((Join-Path $accepted.directory 'revisions\1\helper.ps1'))) 'Old candidate was overwritten.'
}
Check 'CLI status survives a new process and acceptance is not a release sign-off' {
    $text = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File "$PSScriptRoot\..\verification.ps1" -Operation status -Root $root -WorkflowId $completedId
    Require ($LASTEXITCODE -eq 0) 'Status CLI failed.'
    $state = $text | ConvertFrom-Json -AsHashtable
    Require ($state.status -eq 'review-accepted' -and -not $state.Contains('releaseApproved')) 'Controller invented release approval.'
}
Check 'No fake completion without archive, no stale result and no second task claim' {
    $workflow = NewWorkflow
    $packetPath = Claim-VfTask -Root $root -WorkflowId $workflow.id -WorkerId 'worker-a'
    $packet = Get-Content -LiteralPath $packetPath -Raw | ConvertFrom-Json -AsHashtable
    Reject { Claim-VfTask -Root $root -WorkflowId $workflow.id -WorkerId 'worker-b' } 'no ready task'
    FailedResult $packet completed
    Reject { Submit-VfTask -Root $root -WorkflowId $workflow.id -ResultFile $packet.resultPath } 'archivePath'
    FailedResult $packet
    $state = Submit-VfTask -Root $root -WorkflowId $workflow.id -ResultFile $packet.resultPath
    Require ($state.nextRole -eq 'reviewer') 'Driver failure did not reach review.'
    Reject { Submit-VfTask -Root $root -WorkflowId $workflow.id -ResultFile $packet.resultPath } 'Stale'
}
Check 'One real environment is exclusive across workflows; failed execution needs explicit recovery' {
    $one = NewWorkflow $true
    $two = NewWorkflow $true
    $packetPath = Claim-VfTask -Root $root -WorkflowId $one.id -WorkerId 'live-runner'
    $packet = Get-Content -LiteralPath $packetPath -Raw | ConvertFrom-Json -AsHashtable
    Reject { Claim-VfTask -Root $root -WorkflowId $two.id -WorkerId 'other-runner' } 'Environment is busy'
    FailedResult $packet
    Submit-VfTask -Root $root -WorkflowId $one.id -ResultFile $packet.resultPath | Out-Null
    Require ((Get-VfStatus -Root $root).environments['synthetic-desktop'].state -eq 'recovery-required') 'Unverified failure silently freed the desktop.'
    Claim-VfTask -Root $root -WorkflowId $one.id -WorkerId 'offline-reviewer' | Out-Null
    Reject { Claim-VfTask -Root $root -WorkflowId $two.id -WorkerId 'other-runner' } 'Environment is busy'
    Restore-VfEnvironment -Root $root -Environment 'synthetic-desktop' -Actor 'operator' -Reason 'Worker stopped; all baseline checks passed' -Evidence $proof | Out-Null
    Claim-VfTask -Root $root -WorkflowId $two.id -WorkerId 'other-runner' | Out-Null
}
Check 'A persisted interrupted task requires worker-stop confirmation and cannot accept old output' {
    $workflow = NewWorkflow
    $packet = Get-Content -LiteralPath (Claim-VfTask -Root $root -WorkflowId $workflow.id -WorkerId 'interrupted-worker') -Raw | ConvertFrom-Json -AsHashtable
    Reject { Stop-VfTask -Root $root -WorkflowId $workflow.id -Actor operator -Reason stopped -Evidence $proof } 'WorkerStopped'
    Stop-VfTask -Root $root -WorkflowId $workflow.id -Actor operator -Reason stopped -Evidence $proof -WorkerStopped | Out-Null
    FailedResult $packet
    Reject { Submit-VfTask -Root $root -WorkflowId $workflow.id -ResultFile $packet.resultPath } 'Stale'
    Decision $workflow recheck | Out-Null
    Require ((Get-VfStatus -Root $root -WorkflowId $workflow.id).history[-2].type -eq 'interrupted') 'Interrupted history disappeared.'
}
Check 'Frozen input mutation is rejected instead of silently changing scored expectations' {
    $workflow = NewWorkflow
    [IO.File]::AppendAllText((Join-Path $workflow.bundle.root 'checklist.txt'), 'weakened')
    Reject { Claim-VfTask -Root $root -WorkflowId $workflow.id -WorkerId 'runner' } 'Changed evidence/input'
}
Check 'Reviewer cannot relabel product failure as an operational repair without supporting findings' {
    $workflow = NewWorkflow
    Dispatch $workflow 'runner' | Out-Null
    $packet = Get-Content -LiteralPath (Claim-VfTask -Root $root -WorkflowId $workflow.id -WorkerId 'reviewer') -Raw | ConvertFrom-Json -AsHashtable
    @{ taskId = $packet.taskId; workerId = $packet.workerId; status = 'completed'; summary = 'Wrong repair proposal'
        evidence = @($proof); recommendation = 'repair'; findings = @(@{ layer = 'product'; summary = 'Product differs'; evidence = @($proof) }) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $packet.resultPath
    Reject { Submit-VfTask -Root $root -WorkflowId $workflow.id -ResultFile $packet.resultPath } 'operational|profile/harness'
}
Check 'Candidate checklist changes and post-review tampering cannot be promoted' {
    $workflow = NewWorkflow
    Dispatch $workflow 'runner' | Out-Null
    Dispatch $workflow 'reviewer' | Out-Null
    Decision $workflow repair | Out-Null
    $packet = Get-Content -LiteralPath (Claim-VfTask -Root $root -WorkflowId $workflow.id -WorkerId 'repairer') -Raw | ConvertFrom-Json -AsHashtable
    $checklist = Join-Path $packet.candidateRoot 'checklist.txt'
    $old = [IO.File]::ReadAllText($checklist)
    [IO.File]::AppendAllText($checklist, 'weakened')
    FailedResult $packet completed
    Reject { Submit-VfTask -Root $root -WorkflowId $workflow.id -ResultFile $packet.resultPath } 'protected checklist'
    [IO.File]::WriteAllText($checklist, $old)
    & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $adapter -PacketPath (Join-Path (Split-Path $packet.resultPath -Parent) 'packet.json') -ResultPath $packet.resultPath
    Require ($LASTEXITCODE -eq 0) 'Fixture repair failed.'
    Submit-VfTask -Root $root -WorkflowId $workflow.id -ResultFile $packet.resultPath | Out-Null
    [IO.File]::AppendAllText($checklist, 'post-review mutation')
    Reject { Decision $workflow confirm } 'Changed evidence/input'
}
Check 'Registry writer contention rejects a second writer without losing committed state' {
    $before = (Get-FileHash -LiteralPath (Join-Path $root 'registry.json')).Hash
    $lease = [IO.File]::Open((Join-Path $root 'registry.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { Reject { NewWorkflow } 'another process|sharing|used by' } finally { $lease.Dispose() }
    Require ((Get-FileHash -LiteralPath (Join-Path $root 'registry.json')).Hash -ceq $before) 'Contended writer changed the registry.'
}
Check 'Adapter crash and timeout retain diagnostics and never become product verdicts' {
    foreach ($mode in 'crash','timeout') {
        $workflow = NewWorkflow
        $scriptPath = Join-Path $Workspace "$mode.ps1"
        $body = if ($mode -eq 'crash') { 'param($PacketPath,$ResultPath) "partial stdout"; [Console]::Error.WriteLine("worker error"); exit 23' }
            else { 'param($PacketPath,$ResultPath) "started"; Start-Sleep -Seconds 30' }
        [IO.File]::WriteAllText($scriptPath,$body)
        Reject { Invoke-VfAgent -Root $root -WorkflowId $workflow.id -WorkerId worker -Adapter $scriptPath -TimeoutSeconds 1 } 'exited with code 23|timeout'
        $state = Get-VfStatus -Root $root -WorkflowId $workflow.id
        Require ($state.status -eq 'awaiting-decision' -and $state.tasks[0].status -eq 'interrupted') 'Adapter failure fabricated completion.'
        Require ([IO.File]::Exists((Join-Path $state.tasks[0].directory 'worker.stderr.txt'))) 'Adapter stderr was lost.'
    }
}
Check 'Invalid request paths and missing explicit scope fail before workflow admission' {
    $path = Request
    $request = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    $request.inputs[0].path = '..\proof.txt'
    $request | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path
    Reject { New-VfWorkflow -Root $root -RequestFile $path } 'traversal'
    $request.inputs[0].path = 'checklist.txt'
    $request.Remove('live')
    $request | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path
    Reject { New-VfWorkflow -Root $root -RequestFile $path } 'explicit boolean'
}
"PASS: $($checks.Count) coordinator groups. Synthetic evidence: $Workspace"
