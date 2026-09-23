#Requires -Version 7.4
param([string]$OutputDirectory = (Join-Path $env:TEMP "pt-harness-tests-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\pt-verification-state.ps1')
. (Join-Path $PSScriptRoot '..\pt-verification-ui.ps1')
$root = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $root) { throw 'Test output must be a fresh directory.' }
New-Item -ItemType Directory -Path $root | Out-Null
$checks = [Collections.Generic.List[object]]::new()
function Check($Name, [scriptblock]$Body) {
    & $Body
    $checks.Add([pscustomobject]@{ Name=$Name; Passed=$true })
    Write-Output "PASS $Name"
}
function Require($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Body, [string]$Pattern) {
    $errorRecord = $null
    try { & $Body | Out-Null } catch { $errorRecord = $_ }
    if (-not $errorRecord -or $errorRecord.ToString() -notmatch $Pattern) { throw "Expected failure matching '$Pattern'; got '$errorRecord'" }
}

Check 'Empty JSON collections are persisted, not dropped by the pipeline' {
    Save-PtRunJson (Join-Path $root 'empty.json') @()
    Require ([IO.File]::ReadAllText((Join-Path $root 'empty.json')).Trim() -ceq '[]') 'Empty collection missing'
}
$path=Join-Path $root 'state.json'; [IO.File]::WriteAllText($path,'original')
$guard=New-PtFileGuard $path
Check 'Original bytes restored only over declared current bytes' {
    [IO.File]::WriteAllText($path,'owned change')
    $receipt=Restore-PtFileGuard $guard (Get-PtFileHashBytes ([Text.Encoding]::UTF8.GetBytes('owned change')))
    Require ($receipt.Restored -and [IO.File]::ReadAllText($path) -ceq 'original') 'File not restored'
}
Check 'Foreign file change is retained' {
    [IO.File]::WriteAllText($path,'foreign')
    Reject { Restore-PtFileGuard $guard $guard.Hash } 'conflict'
    Require ([IO.File]::ReadAllText($path) -ceq 'foreign') 'Foreign data overwritten'
}
Check 'Missing original file is not silently recreated' {
    $missing=Join-Path $root 'deleted.json'; [IO.File]::WriteAllText($missing,'original')
    $snapshot=New-PtFileGuard $missing; [IO.File]::Delete($missing)
    Reject { Restore-PtFileGuard $snapshot $snapshot.Hash } 'Could not find|cannot find'
}
Check 'Snapshot tampering rejected' {
    $tamperPath=Join-Path $root 'tamper.json'; [IO.File]::WriteAllText($tamperPath,'before')
    $snapshot=New-PtFileGuard $tamperPath; $snapshot.Bytes[0]=0
    Reject { Restore-PtFileGuard $snapshot $snapshot.Hash } 'Snapshot bytes'
}
foreach ($enabled in @($false,$true)) {
    Check "Lifecycle returns to original enabled=$enabled on success and action failure" {
        foreach ($fail in @($false,$true)) {
            $script:enabled=$enabled; $script:restored=$false; $script:stopped=$false
            $parameters=@{
                ReadEnabled={ $script:enabled }
                SetEnabled={ param($value) $script:enabled=$value }
                Action={ $script:enabled=-not $script:enabled; if($fail){throw 'action failure'}; 'action result' }
                Quiesce={ Require (-not $script:enabled) 'Writer still enabled'; $script:stopped=$true }
                Restore={ Require $script:stopped 'No writer stop'; $script:restored=$true }
                Verify={ $script:restored }
            }
            if($fail){Reject { Invoke-PtRestoredState @parameters } 'action failure'}
            else { $receipt=Invoke-PtRestoredState @parameters; Require $receipt.Restored 'No restoration receipt' }
            Require ($script:enabled -eq $enabled -and $script:restored) 'Original lifecycle not restored'
        }
    }
}
Check 'Cleanup conflict is explicit and prevents restarting writer' {
    $script:enabled=$true
    Reject { Invoke-PtRestoredState -ReadEnabled {$script:enabled} -SetEnabled {param($v)$script:enabled=$v} -Action {throw 'action broke'} -Quiesce {} -Restore {throw 'restore conflict'} -Verify {$true} } 'restore conflict'
    Require (-not $script:enabled) 'Restarted writer over a conflict'
}
Check 'Non-Boolean state and verification are rejected' {
    Reject { Invoke-PtRestoredState -ReadEnabled {'false'} -SetEnabled {} -Action {} -Quiesce {} -Restore {} -Verify {$true} } 'exactly one Boolean'
    Reject { Invoke-PtRestoredState -ReadEnabled {$false} -SetEnabled {} -Action {} -Quiesce {} -Restore {} -Verify {} } 'verification'
}
Check 'Nonterminating callback errors still fail under a permissive caller' {
    $savedPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        Reject { Invoke-PtRestoredState -ReadEnabled {$false} -SetEnabled {} -Action {Write-Error 'callback failure'} -Quiesce {} -Restore {} -Verify {$true} } 'callback failure'
    } finally { $ErrorActionPreference=$savedPreference }
}

$tree=@{type='Window'; children=@(
    @{type='Group';name='row-a';selector='a';isOffscreen=$false;children=@(@{type='Button';name='Copy';selector='copy-a';isOffscreen=$false})},
    @{type='Group';name='row-b';selector='b';isOffscreen=$false;children=@(@{type='Button';name='Copy';selector='copy-b';isOffscreen=$false})}
)}
Check 'Repeated controls require parent scope' {
    Reject { Resolve-PtUiControl $tree 'Button' -Name Copy } 'found 2'
    $row=Resolve-PtUiControl $tree 'Group' -Name row-b
    Require ((Resolve-PtUiControl $row 'Button' -Name Copy).selector -ceq 'copy-b') 'Wrong row'
}
Check 'Duplicate projection of one selector is deduplicated' {
    $node=$tree.children[0].children[0]
    Require ((Resolve-PtUiControl @{elements=@($node,$node)} 'Button' -Name Copy).selector -ceq 'copy-a') 'Duplicate not resolved'
}
Check 'Different controls cannot hide behind one duplicate selector' {
    Reject { Resolve-PtUiControl @{elements=@(
        @{type='Button';name='Copy';selector='same';isOffscreen=$false;x=10},
        @{type='Button';name='Copy';selector='same';isOffscreen=$false;x=50}
    )} 'Button' -Name Copy } 'Conflicting nodes'
}
Check 'Missing, offscreen and wrong-type nodes are not silently selected' {
    Reject { Resolve-PtUiControl $tree 'Edit' -Name Copy } 'found 0'
    Reject { Resolve-PtUiControl @{type='Button';name='Copy';selector='x';isOffscreen=$true} 'Button' -Name Copy } 'found 0'
    Reject { Resolve-PtUiControl @{type='Button';name='Copy';isOffscreen=$false} 'Button' -Name Copy } 'lacks'
}

$inventory=@(@{Id='one';AssertionIds=@('CP01','CP02')},@{Id='two';AssertionIds=@('CP03')})
$run=New-PtRecordedRun -Workspace (Join-Path $root 'run') -Bits 'synthetic helper fixture; not product verification' -Scenarios $inventory -InputPath $PSCommandPath
$shell=(Get-Process -Id $PID).Path
Check 'Inventory duplicates and existing workspace rejected' {
    Reject { New-PtRecordedRun -Workspace (Join-Path $root 'bad') -Bits test -Scenarios @(@{Id='s';AssertionIds=@('x','x')}) } 'duplicate'
    Reject { New-PtRecordedRun -Workspace $run.Workspace -Bits test -Scenarios $inventory } 'already exists'
}
Check 'Native arguments preserve empty strings, spaces and Unicode' {
    $script=Join-Path $root 'echo.ps1'
    'param([AllowEmptyString()][string]$First,[string]$Second); [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); ConvertTo-Json -Compress -InputObject @($First,$Second)' | Set-Content -LiteralPath $script
    $value='two words ' + [char]0x4E2D
    $command=Invoke-PtRecordedCommand $run same-label $shell -Arguments @('-NoProfile','-File',$script,'',$value)
    $values=$command.Stdout|ConvertFrom-Json
    Require ($values.Count -eq 2 -and $values[0] -ceq '' -and $values[1] -ceq $value) 'Argument corruption'
}
Check 'Labels do not lock invocations' {
    $first=Invoke-PtRecordedCommand $run same-label $shell -Arguments @('-NoProfile','-Command','"ok"')
    $second=Invoke-PtRecordedCommand $run same-label $shell -Arguments @('-NoProfile','-Command','"ok"')
    Require ($first.Id -cne $second.Id) 'Invocation IDs reused'
}
Check 'Exit failure retains stdout/stderr and can be followed by another call' {
    Reject { Invoke-PtRecordedCommand $run fail $shell -Arguments @('-NoProfile','-Command','[Console]::Out.Write("before"); [Console]::Error.Write("original error"); exit 7') } 'code 7'
    $records=@(Get-ChildItem "$($run.Workspace)\commands" -Filter invocation.json -Recurse|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json})
    $failed=$records|Where-Object Name -EQ fail
    Require ($failed.Status -eq 'Error' -and $failed.ExitCode -eq 7) 'Failure record wrong'
    Require ([IO.File]::ReadAllText("$($run.Workspace)\commands\$($failed.Id)\stderr.txt") -ceq 'original error') 'stderr lost'
    $null=Invoke-PtRecordedCommand $run fail $shell -Arguments @('-NoProfile','-Command','"recovery"')
}
Check 'Timeout records uncertainty and terminates its owned process' {
    Reject { Invoke-PtRecordedCommand $run timeout $shell -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 30') -TimeoutSeconds 1 } 'timed out'
    $record=Get-ChildItem "$($run.Workspace)\commands" -Filter invocation.json -Recurse|ForEach-Object {Get-Content $_.FullName -Raw|ConvertFrom-Json}|Where-Object Name -EQ timeout
    Require ($record.Status -eq 'Timeout') 'Timeout not preserved'
    Require (-not (Get-Process -Id $record.ProcessId -ErrorAction SilentlyContinue)) 'Owned timed-out process still alive'
}
Check 'Spawn failures produce a durable error record' {
    Reject { Invoke-PtRecordedCommand $run spawn-error (Join-Path $root 'missing.exe') } 'cannot find|No such file|not found'
}
[IO.File]::WriteAllText((Join-Path $run.Workspace 'proof.txt'),'fixture evidence')
Check 'Unknown assertions and escaping/missing evidence rejected' {
    Reject { Set-PtRecordedAssertion $run other PASS reason @('proof.txt') } 'Unknown'
    Reject { Set-PtRecordedAssertion $run CP01 PASS reason @('..\state.json') } 'outside'
    Reject { Set-PtRecordedAssertion $run CP01 PASS reason @('missing.txt') } 'missing'
}
Check 'Partial update does not erase unrelated assertions; FAIL is sticky' {
    Set-PtRecordedAssertion $run CP01 FAIL 'Observed fixture defect' @('proof.txt')
    Set-PtRecordedAssertion $run CP02 PASS 'Independent result' @('proof.txt')
    Reject { Set-PtRecordedAssertion $run CP01 PASS 'Pretend fixed' @('proof.txt') } 'silently replaced'
    $current=Get-Content "$($run.Workspace)\run.json" -Raw|ConvertFrom-Json
    Require ($current.Assertions[0].Verdict -eq 'FAIL' -and $current.Assertions[1].Verdict -eq 'PASS' -and $current.Assertions[2].Verdict -eq 'NOT-OBSERVED') 'Assertion evidence erased'
}
Check 'Cleanup evidence and incomplete coverage withhold signoff' {
    Set-PtRecordedCleanup $run $true 'Restoration verified against fixture' @('proof.txt')
    $summary=Complete-PtRecordedRun $run
    Require ($summary.Signoff -eq 'WITHHELD' -and ($summary.Scenarios|Where-Object Id -EQ one).Verdict -eq 'FAIL') 'Invalid signoff'
    Reject { Set-PtRecordedAssertion $run CP03 PASS 'late' @('proof.txt') } 'finalized'
}
Check 'Archive move verifies hashes and refuses tampering/overwrite' {
    $destination=Join-Path $root 'archive'
    $null=Move-PtRecordedArchive $run $destination
    Require (Test-PtRecordedArchive $destination).Valid 'Archive invalid'
    Reject { Move-PtRecordedArchive $run $destination } 'exists'
    [IO.File]::AppendAllText((Join-Path $destination 'proof.txt'),'tamper')
    Reject { Test-PtRecordedArchive $destination } 'mismatch'
}
Check 'Changed input snapshots and changed judgment evidence are rejected' {
    $other=New-PtRecordedRun (Join-Path $root 'input-check') test @(@{Id='s';AssertionIds=@('a')}) -InputPath $PSCommandPath
    [IO.File]::AppendAllText((Join-Path $other.Workspace $other.Inputs[0].Path),'tamper')
    Reject { Invoke-PtRecordedCommand $other no-run $shell } 'snapshot changed'
    $other=New-PtRecordedRun (Join-Path $root 'evidence-check') test @(@{Id='s';AssertionIds=@('a')})
    [IO.File]::WriteAllText((Join-Path $other.Workspace 'proof.txt'),'before')
    Set-PtRecordedAssertion $other a PASS test @('proof.txt')
    [IO.File]::AppendAllText((Join-Path $other.Workspace 'proof.txt'),'after')
    Reject { Complete-PtRecordedRun $other } 'Evidence changed'
}
Check 'All-pass with verified cleanup can be approved' {
    $complete=New-PtRecordedRun (Join-Path $root 'complete') test @(@{Id='s';AssertionIds=@('a')})
    [IO.File]::WriteAllText((Join-Path $complete.Workspace 'proof.txt'),'evidence')
    Set-PtRecordedAssertion $complete a PASS test @('proof.txt')
    Set-PtRecordedCleanup $complete $true verified @('proof.txt')
    Require ((Complete-PtRecordedRun $complete).Signoff -eq 'APPROVED') 'Unexpected withheld'
}
Check 'Invalid captures withhold approval even if a caller records PASS' {
    $captureRun=New-PtRecordedRun (Join-Path $root 'capture-check') test @(@{Id='s';AssertionIds=@('a')})
    [IO.File]::WriteAllText((Join-Path $captureRun.Workspace 'proof.txt'),'evidence')
    Save-PtRunJson (Join-Path $captureRun.Workspace 'failed.capture.json') @{Valid=$false;Error='Foreground changed'}
    Set-PtRecordedAssertion $captureRun a PASS test @('proof.txt')
    Set-PtRecordedCleanup $captureRun $true verified @('proof.txt')
    Require ((Complete-PtRecordedRun $captureRun).Signoff -eq 'WITHHELD') 'Invalid capture approved'
}
Check 'Archive detects a duplicated manifest entry hiding another file' {
    $complete=New-PtRecordedRun (Join-Path $root 'duplicate-manifest') test @(@{Id='s';AssertionIds=@('a')})
    $null=Complete-PtRecordedRun $complete
    $manifestPath=Join-Path $complete.Workspace 'manifest.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    $manifest[1]=$manifest[0]
    Save-PtRunJson $manifestPath $manifest
    Reject {Test-PtRecordedArchive $complete.Workspace} 'Duplicate'
}
$checks | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'checks.json')
Write-Output "Passed $($checks.Count) checks. Evidence: $root"
