#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-clipboard-keeper-offline-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\fixtures\Import-ClipboardNativeStub.ps1"
Import-PtClipboardNativeStub
. "$PSScriptRoot\..\pt-clipboard-session.ps1"
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
# Keep even an unexpected preserve-path launch native-free in the disposable-mode regression.
$launcher=${function:New-PtClipboardSession}.ToString()
$boundary='"$PSScriptRoot\hosts\clipboard-keeper.ps1"'
if(-not $launcher.Contains($boundary)){throw 'Keeper launch boundary changed.'}
Set-Item Function:\New-PtClipboardSession ([scriptblock]::Create(
    $launcher.Replace($boundary,('"'+$PSScriptRoot+'\fixtures\ClipboardKeeperStub.ps1"'))))
$disposable=$null
try{
    $disposable=New-PtClipboardSession -Workspace $Workspace -Policy Disposable -Reason 'Explicitly disposable synthetic test session'
    Require ($disposable.Policy -eq 'Disposable' -and -not $disposable.PSObject.Properties['PipeName'] -and
        $disposable.FormatCount -eq 0 -and [PtClipboardNativeStub]::GetCalls -eq 0 -and [PtClipboardNativeStub]::OpenCalls -eq 0) 'Disposable session captured original data or created a keeper'
    Require (@(Get-ChildItem $Workspace -Filter 'clipboard-session-*').Count -eq 0) 'Disposable session created a keeper receipt'
    Complete-PtClipboardSession $disposable
    Require (-not $disposable.Restored -and $disposable.Disposition -eq 'NotPreserved') 'Disposable completion claimed restoration'
}finally{
    if($disposable){Complete-PtClipboardSession $disposable}
}
$controller=$null;$session=$null
try{
    $start=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($argument in @('-NoProfile','-File',"$PSScriptRoot\fixtures\ClipboardControllerStub.ps1",'-Workspace',$Workspace)){$start.ArgumentList.Add($argument)}
    $controller=[Diagnostics.Process]::Start($start)
    Require ($controller.WaitForExit(25000)) 'Controller did not finish its injected failure'
    Require ($controller.ExitCode -eq 37) "Unexpected controller exit: $($controller.ExitCode)"
    $receipts=@(Get-ChildItem $Workspace -Filter 'clipboard-session-*.json')
    Require ($receipts.Count -eq 1) 'Missing unique keeper recovery receipt'
    $failedReceipt=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($receipts[0].FullName))
    Require ($failedReceipt.LastFailure.NativeErrorCode -eq 5) 'Keeper lost the native lock error code'
    $session=Connect-PtClipboardSession $receipts[0].FullName
    Require (-not $session.Restored -and $session.PendingWriteState -ceq 'ConfirmationPending' -and $session.PendingSequence -eq 101) 'Controller exit discarded pending original'
    $guarded=$false
    try{$session.Dispose()}catch{$guarded=$_.Exception.Message -match 'Restore the registered'}
    Require $guarded 'Keeper allowed disposal of unresolved original'
    $pipe=[IO.Pipes.NamedPipeClientStream]::new('.',$session.PipeName,[IO.Pipes.PipeDirection]::InOut)
    try{$pipe.Connect(3000)}finally{$pipe.Dispose()}
    # Recreate the resource-session reconnect boundary without enumerating any real windows.
    function Get-PtNativeWindow {}
    $skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $run=New-PtVerificationRun -Workspace "$Workspace\run" -Module 'Clipboard keeper fixture' `
        -Scenario InfrastructureAcceptance -Bits 'All clipboard APIs replaced by native stub' `
        -Items @(@{Id='I1';Description='Keeper recovery';Admin='NO';Clarity='CLEAR';UserVisible=$false
            Assertions=@(@{Id='retention';Description='Keeper survives controller'})}) `
        -Inputs @(Get-PtVerificationInputs -Skill $skill -Inputs @(@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath}))
    New-PtResourceSession $run|Out-Null
    Add-PtClipboardObligation $session $session.ProcessId
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
    Open-PtResourceSession $run|Out-Null
    $blocked=$false
    try{Assert-PtProcessRelease @($session.ProcessId)}catch{$blocked=$_.Exception.Message -match 'clipboard obligation'}
    Require $blocked 'Resume falsely released an unconnected keeper'
    $session=Connect-PtClipboardSession $receipts[0].FullName
    Require (@($session.KeeperErrors|Where-Object {$_ -match 'disconnected'}).Count -gt 0) 'Disconnected-client failure was not recorded'
    $session.Restore()
    Require ($session.Restored -and $session.PendingWriteState -ceq 'None') 'Reconnected keeper could not restore sealed action'
    Assert-PtClipboardRestored $session
    Require ((Get-PtActiveResourceSession).Obligations[0].Restored) 'Reconnected keeper did not complete its original release obligation'
    $keeper=Get-Process -Id $session.ProcessId
    $session.Dispose()
    Require ($keeper.WaitForExit(10000)) 'Restored keeper did not exit after explicit disposal'
    Complete-PtClipboardSession $session
    $receipt=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($receipts[0].FullName))
    Require ($receipt.Phase -ceq 'Disposed' -and $receipt.State.Restored) 'Final receipt did not preserve successful restoration'
    Require (-not ([IO.File]::ReadAllText($receipts[0].FullName) -match '"(Bytes|Base64|Content)"')) 'Keeper persisted payload instead of metadata'

    $discardWorkspace=Join-Path $Workspace 'discard'
    [IO.Directory]::CreateDirectory($discardWorkspace)|Out-Null
    $controller.Dispose()
    $start=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($argument in @('-NoProfile','-File',"$PSScriptRoot\fixtures\ClipboardControllerStub.ps1",
        '-Workspace',$discardWorkspace,'-FailureMode','ActionFailed')){$start.ArgumentList.Add($argument)}
    $controller=[Diagnostics.Process]::Start($start)
    Require ($controller.WaitForExit(25000) -and $controller.ExitCode -eq 37) 'Discard fixture did not reach its injected failure'
    $receipts=@(Get-ChildItem $discardWorkspace -Filter 'clipboard-session-*.json')
    Require ($receipts.Count -eq 1) 'Missing unique discard recovery receipt'
    $session=Connect-PtClipboardSession $receipts[0].FullName
    Add-PtClipboardObligation $session $session.ProcessId
    Require ($session.PendingWriteState -ceq 'ActionFailed') 'Discard fixture did not retain failed action'
    $refused=$false
    try{Invoke-PtClipboardSessionRequest $session Discard @{Reason='Missing explicit authority'}}
    catch{$refused=$_.Exception.Message -match 'explicit original-discard authority'}
    Require ($refused -and $session.Disposition -ceq 'Pending' -and $session.FormatCount -eq 2) 'Keeper accepted an unauthorized discard'
    $keeper=Get-Process -Id $session.ProcessId
    Complete-PtClipboardSession $session -DiscardOriginal -Reason 'Caller authorizes discarding the synthetic original after observer failure'
    Require ($keeper.HasExited -and $session.Disposed -and -not $session.Restored) 'Explicit discard did not close the keeper honestly'
    Complete-PtClipboardSession $session -DiscardOriginal -Reason 'Repeated cleanup of the same already disposed synthetic original'
    $receipt=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($receipts[0].FullName))
    Require ($receipt.Phase -ceq 'Disposed' -and $receipt.State.Disposition -ceq 'DiscardedByPolicy' -and
        $receipt.State.PendingWriteState -ceq 'ActionFailed' -and -not $receipt.State.Restored -and
        $receipt.State.DiscardReason -match 'Caller authorizes') 'Discard receipt erased failure or claimed restoration'
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
    Open-PtResourceSession $run|Out-Null
    Assert-PtProcessRelease @($session.ProcessId)
    $attempt=Start-PtVerificationAttempt $run -Context Cleanup -Name 'Explicit discard completion' -Kind Normal
    try{
        $rows=@(Complete-PtResourceSession $attempt)
        $discard=@($rows|Where-Object Disposition -EQ 'DiscardedByPolicy')
        Require ($discard.Count -eq 1 -and $discard[0].Status -eq 'PASS' -and -not $discard[0].Restored) 'Resource completion lost discard provenance'
    }finally{Stop-PtVerificationAttempt $attempt -Reason 'Authorized discard closes only its dependency'}

    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
    $policyRun=New-PtVerificationRun -Workspace "$Workspace\disposable-plan" -Module 'Clipboard policy fixture' `
        -Scenario InfrastructureAcceptance -Bits 'All clipboard APIs replaced by native stub' `
        -Items @(@{Id='I1';Description='Declared clipboard policy';Admin='NO';Clarity='CLEAR';UserVisible=$false
            Assertions=@(@{Id='policy';Description='Inherit original plan'})}) `
        -Inputs @(Get-PtVerificationInputs -Skill $skill -Inputs @(@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath}))
    $policy=@{Schema='PtRunResources.v1';Resources=@(@{Id='clipboard';Kind='Clipboard'
        Policy='Disposable';Reason='Caller-declared disposable fixture';RestoreStep='clipboard'})}
    New-PtResourceSession $policyRun -ResourcePlan $policy|Out-Null
    $guard=New-PtClipboardSession $policyRun.Workspace
    Require ($guard.Policy -eq 'Disposable' -and $guard.PolicyReason -ceq $policy.Resources[0].Reason -and
        @(Get-ChildItem $policyRun.Workspace -Filter 'clipboard-session-*').Count -eq 0) 'Original Disposable plan did not prevent keeper creation'
    Complete-PtClipboardSession $guard
    Assert-PtProcessRelease @($PID)
    Write-PtReportText "$Workspace\results.json" '{"DisposableSessionNoKeeper":"PASS","InheritedDisposablePlan":"PASS","ControllerExitRetention":"PASS","Reconnection":"PASS","DisconnectedClientRetention":"PASS","ResumedReleaseObligation":"PASS","NativeFailureMetadata":"PASS","UnrestoredDisposeRefusal":"PASS","OriginalByteRestoration":"PASS","ExplicitKeeperExit":"PASS","UnauthorizedDiscardRefusal":"PASS","FailedWriteDiscard":"PASS","PersistedDiscardRelease":"PASS","RealClipboardAccess":false}'
}finally{
    if($session -and -not $session.Disposed){
        Complete-PtClipboardSession $session -DiscardOriginal -Reason 'Cleanup of native-free synthetic keeper fixture'
    }
    if($controller){$controller.Dispose()}
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
}
"PASS: actual controller exit, pipe reconnection and keeper restoration with fake native clipboard only. $Workspace"
