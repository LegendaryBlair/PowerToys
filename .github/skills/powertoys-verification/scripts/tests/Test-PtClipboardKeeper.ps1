#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-clipboard-keeper-offline-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-clipboard-session.ps1"
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
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
    $receipt=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($receipts[0].FullName))
    Require ($receipt.Phase -ceq 'Disposed' -and $receipt.State.Restored) 'Final receipt did not preserve successful restoration'
    Require (-not ([IO.File]::ReadAllText($receipts[0].FullName) -match '"(Bytes|Base64|Content)"')) 'Keeper persisted payload instead of metadata'
    Write-PtReportText "$Workspace\results.json" '{"ControllerExitRetention":"PASS","Reconnection":"PASS","DisconnectedClientRetention":"PASS","ResumedReleaseObligation":"PASS","NativeFailureMetadata":"PASS","UnrestoredDisposeRefusal":"PASS","OriginalByteRestoration":"PASS","ExplicitKeeperExit":"PASS","RealClipboardAccess":false}'
}finally{
    if($session -and -not $session.Disposed){
        if(-not $session.Restored){$session.Restore()}
        $session.Dispose()
    }
    if($controller){$controller.Dispose()}
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
}
"PASS: actual controller exit, pipe reconnection and keeper restoration with fake native clipboard only. $Workspace"
