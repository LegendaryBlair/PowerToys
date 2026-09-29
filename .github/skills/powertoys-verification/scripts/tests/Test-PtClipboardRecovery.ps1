#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-clipboard-offline-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\fixtures\Import-ClipboardNativeStub.ps1"
Import-PtClipboardNativeStub
. "$PSScriptRoot\..\pt-clipboard-guard.ps1"
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
$start=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return $_}
    throw "Expected rejection: $Pattern"
}
function Check([string]$Name,[scriptblock]$Body){
    [PtClipboardNativeStub]::Reset()
    try{& $Body|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace});throw}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
function Guard {
    $value=[PtClipboard.ClipboardGuard]::new(1)
    $value.RequireRestorationBeforeDispose=$true
    $value
}
Check 'Public write wrapper is exported and executes a successful action exactly once' {
    Require ([bool](Get-Command Invoke-PtClipboardWrite -ErrorAction Ignore)) 'Write API was nested rather than exported'
    $g=Guard;$script:count=0
    Invoke-PtClipboardWrite $g $PID $start -Action {$script:count++;[PtClipboardNativeStub]::Write(90,$PID)}
    Require ($script:count -eq 1 -and $g.PendingWriteState -ceq 'None') 'Successful action not confirmed exactly once'
    $g.Restore();$g.Dispose()
    Require ([PtClipboardNativeStub]::FormatCount -eq 2 -and [PtClipboardNativeStub]::Bytes(13)[0] -eq 65) 'Original formats not restored'
}
Check 'Pre-write contention prevents the action without changing the baseline' {
    $g=Guard;$script:count=0
    [PtClipboardNativeStub]::OpenFailures=1000
    Reject {Invoke-PtClipboardWrite $g $PID $start -Action {$script:count++}} 'OpenClipboard'
    Require ($script:count -eq 0 -and $g.PendingWriteState -ceq 'None') 'Write ran before successful preparation'
    [PtClipboardNativeStub]::OpenFailures=0;$g.Restore();$g.Dispose()
}
Check 'Post-write confirmation failure keeps a sealed receipt and restores without replay' {
    $g=Guard;$script:count=0
    Reject {Invoke-PtClipboardWrite $g $PID $start -Action {
        $script:count++;[PtClipboardNativeStub]::Write(90,$PID);[PtClipboardNativeStub]::OpenFailures=1000
    }} 'OpenClipboard'
    Require ($g.PendingWriteState -ceq 'ConfirmationPending' -and $g.PendingSequence -eq [PtClipboardNativeStub]::Sequence) 'Missing sealed pending receipt'
    [PtClipboardNativeStub]::OpenFailures=0
    Reject {$g.BeginWrite($PID,$start)} 'unacknowledged|pending'
    $g.Restore();$g.Dispose()
    Require ($script:count -eq 1 -and $g.Restored -and [PtClipboardNativeStub]::Bytes(13)[0] -eq 65) 'Copy was replayed or original not restored'
}
Check 'External write after sealing is never accepted or overwritten, even from the same PID' {
    foreach($writer in @($PID,123456)){
        [PtClipboardNativeStub]::Reset();$g=Guard
        Reject {Invoke-PtClipboardWrite $g $PID $start -Action {
            [PtClipboardNativeStub]::Write(90,$PID);[PtClipboardNativeStub]::OpenFailures=1000
        }} 'OpenClipboard'
        $sealed=$g.PendingSequence;[PtClipboardNativeStub]::OpenFailures=0
        [PtClipboardNativeStub]::Write(88,$writer)
        Reject {$g.SealWrite([PtClipboardNativeStub]::Sequence)} 'No prepared'
        Reject {$g.AcceptWrite($g.ExpectedSequence,$writer)} 'pending transaction'
        Reject {$g.ConfirmWrite()} 'sealed sequence'
        Reject {$g.Restore()} 'sealed sequence'
        Reject {$g.Dispose()} 'Restore the registered'
        Require ($g.PendingSequence -eq $sealed -and [PtClipboardNativeStub]::Bytes(13)[0] -eq 88 -and
            [PtClipboardNativeStub]::EmptyCalls -eq 0) 'Foreign state was changed or pending sequence refreshed'
    }
}
Check 'Wrong owner and recycled writer identity cannot confirm a pending write' {
    $g=Guard
    $g.BeginWrite($PID,$start);[PtClipboardNativeStub]::Write(90,123456);$g.SealWrite([PtClipboardNativeStub]::Sequence)
    Reject {$g.ConfirmWrite()} 'writer identity'
    [PtClipboardNativeStub]::WriterPid=$PID;[PtClipboardNativeStub]::WriterTicks=$start+1
    Reject {$g.ConfirmWrite()} 'writer identity'
    Require ([PtClipboardNativeStub]::EmptyCalls -eq 0) 'Invalid identity was restored over'
}
Check 'Action failure after writing stays ambiguous rather than being promoted to confirmed' {
    $g=Guard
    Reject {Invoke-PtClipboardWrite $g $PID $start -Action {[PtClipboardNativeStub]::Write(90,$PID);throw 'action failed'}} 'action failed'
    Require ($g.PendingWriteState -ceq 'ActionFailed') 'Action failure lost'
    Reject {$g.ConfirmWrite()} 'No completed'
    Reject {$g.Restore()} 'unacknowledged write'
    Require ([PtClipboardNativeStub]::Bytes(13)[0] -eq 90) 'Ambiguous action was overwritten'
}
Check 'Action failure before writing can restore the unchanged original' {
    $g=Guard
    Reject {Invoke-PtClipboardWrite $g $PID $start -Action {throw 'before write'}} 'before write'
    $g.Restore();$g.Dispose();Require $g.Restored 'Unchanged baseline could not be restored'
}
Check 'A no-op action fails confirmation but does not prevent unchanged-baseline restoration' {
    $g=Guard
    Reject {Invoke-PtClipboardWrite $g $PID $start -Action {}} 'sealed sequence'
    $g.Restore();$g.Dispose()
    Require $g.Restored 'No-op action blocked a safe unchanged restore'
}
Check 'Restoration contention preserves the backup and succeeds later' {
    $g=Guard
    Invoke-PtClipboardWrite $g $PID $start -Action {[PtClipboardNativeStub]::Write(90,$PID)}
    [PtClipboardNativeStub]::OpenFailures=1000
    Reject {$g.Restore()} 'OpenClipboard'
    Reject {$g.Dispose()} 'Restore the registered'
    [PtClipboardNativeStub]::OpenFailures=0;$g.Restore();$g.Dispose()
    Require ([PtClipboardNativeStub]::Bytes(13)[0] -eq 65) 'Restore retry lost the original'
}
Check 'Allocation and partial restore failures preserve originals and avoid leaking handles' {
    foreach($phase in 'Allocation','Set','Readback'){
        [PtClipboardNativeStub]::Reset();$g=Guard
        Invoke-PtClipboardWrite $g $PID $start -Action {[PtClipboardNativeStub]::Write(90,$PID)}
        switch($phase){
            Allocation {[PtClipboardNativeStub]::FailAllocCall=[PtClipboardNativeStub]::AllocCalls+2}
            Set {[PtClipboardNativeStub]::FailSetCall=2}
            Readback {[PtClipboardNativeStub]::FailGetCall=[PtClipboardNativeStub]::GetCalls+1}
        }
        Reject {$g.Restore()} 'GlobalAlloc|SetClipboardData|Read restored'
        Require (-not $g.Restored) 'Partial restoration claimed success'
        [PtClipboardNativeStub]::FailAllocCall=0;[PtClipboardNativeStub]::FailSetCall=0;[PtClipboardNativeStub]::FailGetCall=0
        $g.Restore();$g.Dispose()
        Require ([PtClipboardNativeStub]::AllocationCount -eq 2 -and [PtClipboardNativeStub]::Bytes(13)[0] -eq 65) 'Leaked buffers or lost original'
    }
}
Check 'Unlock failure does not certify restoration or mask a primary restore error' {
    $g=Guard;[PtClipboardNativeStub]::FailUnlock=$true;[PtClipboardNativeStub]::FailSetCall=1
    $failure=Reject {$g.Restore()} 'SetClipboardData'
    Require (-not $g.Restored -and $failure.Exception.GetBaseException().Data['ClipboardUnlockFailure'] -eq 'CloseClipboard') 'Unlock masked primary error or certified restoration'
    [PtClipboardNativeStub]::FailUnlock=$false;[PtClipboardNativeStub]::FailSetCall=0
    $g.Restore();$g.Dispose()
}
Check 'A foreign write after partial restoration prevents any further rollback' {
    $g=Guard
    Invoke-PtClipboardWrite $g $PID $start -Action {[PtClipboardNativeStub]::Write(90,$PID)}
    [PtClipboardNativeStub]::FailSetCall=2
    Reject {$g.Restore()} 'SetClipboardData'
    $emptyCount=[PtClipboardNativeStub]::EmptyCalls
    [PtClipboardNativeStub]::Write(88,123456);[PtClipboardNativeStub]::FailSetCall=0
    Reject {$g.Restore()} 'unacknowledged write'
    Require ([PtClipboardNativeStub]::Bytes(13)[0] -eq 88 -and [PtClipboardNativeStub]::EmptyCalls -eq $emptyCount) 'Partial restore retry overwrote foreign state'
}
[PtClipboardNativeStub]::Reset()
"PASS: $($results.Count) deterministic clipboard recovery groups; all native clipboard entry points replaced. $Workspace"
