# A separate STA keeper retains only in-memory clipboard data across ordinary controller exit.
. "$PSScriptRoot\pt-clipboard-guard.ps1"
. "$PSScriptRoot\pt-file-io.ps1"
. "$PSScriptRoot\pt-verification-report.ps1"

function Get-PtClipboardKeeperState {
    param($Guard)
    if(-not $Guard){return $null}
    [pscustomobject]@{Restored=$Guard.Restored;ExpectedSequence=$Guard.ExpectedSequence
        PendingWriteState=$Guard.PendingWriteState;PendingSequence=$Guard.PendingSequence
        FormatCount=$Guard.FormatCount;BitmapFromPng=$Guard.BitmapFromPng;OriginalWriterProcessId=$Guard.OriginalWriterProcessId}
}

function Get-PtClipboardFailureDetail {
    param([Parameter(Mandatory)][Exception]$Exception)
    $base=$Exception.GetBaseException()
    [pscustomobject]@{Type=$base.GetType().FullName
        NativeErrorCode=$(if($base -is [ComponentModel.Win32Exception]){$base.NativeErrorCode}else{$null})
        LockHwnd=$base.Data['ClipboardLockHwnd'];LockProcessId=$base.Data['ClipboardLockProcessId']}
}

function Wait-PtClipboardPipeTask {
    param([Parameter(Mandatory)]$Task,[Parameter(Mandatory)][int]$TimeoutMilliseconds,[scriptblock]$Pump)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while(-not $Task.IsCompleted){
        if($Pump){& $Pump}
        if($clock.ElapsedMilliseconds -ge $TimeoutMilliseconds){throw [TimeoutException]::new('Clipboard keeper pipe timed out. The keeper may still retain the backup.')}
        Start-Sleep -Milliseconds 20
    }
    $Task.GetAwaiter().GetResult()
}

function Start-PtClipboardKeeperLoop {
    <#.SYNOPSIS
    Serve metadata-only commands; disconnection does not dispose a captured original.
    #>
    param([Parameter(Mandatory)][string]$Id,[Parameter(Mandatory)][string]$ReceiptPath,
        [Parameter(Mandatory)][scriptblock]$Capture,[scriptblock]$Pump)
    $ErrorActionPreference='Stop'
    if($Id -cnotmatch '^[a-f0-9]{32}$'){throw 'Invalid clipboard keeper ID.'}
    Assert-PtReportNoLink $ReceiptPath
    if([IO.Path]::GetFileName($ReceiptPath) -cne "clipboard-session-$Id.json" -or (Test-Path -LiteralPath $ReceiptPath)){
        throw 'Keeper requires its new unique receipt path; never replace a previous baseline.'
    }
    $pipeName="PowerToys.Verification.Clipboard.$Id"
    $process=Get-Process -Id $PID
    $guard=$null;$finished=$false;$lastError=$null
    $receipt=[pscustomobject]@{Schema='PtClipboardSession.v1';Id=$Id;PipeName=$pipeName;Path=$ReceiptPath
        ProcessId=$PID;ProcessStartTicks=$process.StartTime.ToUniversalTime().Ticks;State=$null;Phase='Waiting';LastError=$null;LastFailure=$null;Errors=@()}
    function NoteFailure([string]$Message){
        # Never depend on the departed controller's stdout/stderr handles to retain the backup.
        $receipt.Errors=@(@($receipt.Errors)+$Message|Select-Object -Last 8)
    }
    function SaveReceipt {
        Assert-PtReportNoLink $ReceiptPath
        $receipt.State=Get-PtClipboardKeeperState $guard;$receipt.LastError=$lastError
        $temporary="$ReceiptPath.$([guid]::NewGuid().ToString('N')).tmp"
        try{
            Write-PtReportText $temporary (ConvertTo-Json $receipt -Depth 8)
            [IO.File]::Move($temporary,$ReceiptPath,$true)
        }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
    }
    SaveReceipt
    while(-not $finished){
        $pipe=$null;$reader=$null;$writer=$null
        try{
            $pipe=[IO.Pipes.NamedPipeServerStream]::new($pipeName,[IO.Pipes.PipeDirection]::InOut,1,
                [IO.Pipes.PipeTransmissionMode]::Byte,([IO.Pipes.PipeOptions]::Asynchronous -bor [IO.Pipes.PipeOptions]::CurrentUserOnly))
            $wait=$pipe.WaitForConnectionAsync()
            if($guard){
                while(-not $wait.IsCompleted){if($Pump){& $Pump};Start-Sleep -Milliseconds 25}
                $wait.GetAwaiter().GetResult()
            }else{Wait-PtClipboardPipeTask $wait 15000 $Pump}
            $reader=[IO.StreamReader]::new($pipe,[Text.UTF8Encoding]::new($false),$false,1024,$true)
            $writer=[IO.StreamWriter]::new($pipe,[Text.UTF8Encoding]::new($false),1024,$true)
            $writer.AutoFlush=$true
            $line=Wait-PtClipboardPipeTask ($reader.ReadLineAsync()) 10000 $Pump
            if($null -eq $line){throw [IO.EndOfStreamException]::new('Controller disconnected; captured clipboard backup retained.')}
            if($line.Length -gt 16384){throw 'Clipboard keeper request is too large.'}
            $request=ConvertFrom-PtReportJson $line
            $result=$null;$commandError=$null;$failureDetail=$null
            try{
                if($request.Id -cne $Id){throw 'Clipboard keeper ID mismatch.'}
                if($request.Command -notin 'Capture','Status' -and -not $guard){throw 'No clipboard snapshot has been captured.'}
                switch -CaseSensitive ($request.Command){
                    Capture {
                        if($guard){throw 'Clipboard baseline already captured; cannot replace it.'}
                        $guard=& $Capture
                        $guard.RequireRestorationBeforeDispose=$true
                        $receipt.Phase='Captured'
                    }
                    Status {}
                    BeginWrite {$guard.BeginWrite([int]$request.WriterProcessId,[long]$request.WriterStartTicks)}
                    SealWrite {$guard.SealWrite([uint32]$request.Sequence)}
                    FailWrite {$guard.FailWrite()}
                    ConfirmWrite {$result=$guard.ConfirmWrite()}
                    AssertUnchanged {$guard.AssertUnchanged()}
                    AcceptWrite {$result=$guard.AcceptWrite([uint32]$request.Sequence,[int]$request.WriterProcessId)}
                    Restore {$guard.Restore();$receipt.Phase='Restored'}
                    Dispose {$guard.Dispose();$receipt.Phase='Disposed';$finished=$true}
                    default {throw 'Unsupported clipboard keeper command.'}
                }
            }catch{$commandError=$_.Exception.Message;$failureDetail=Get-PtClipboardFailureDetail $_.Exception}
            if($commandError){NoteFailure $commandError}
            $receipt.LastFailure=$failureDetail
            $lastError=$commandError;SaveReceipt
            $response=@{Id=$Id;ProcessId=$PID;ProcessStartTicks=$receipt.ProcessStartTicks;State=$receipt.State
                Success=($null -eq $commandError);Error=$commandError;Failure=$failureDetail;Result=$result;KeeperErrors=$receipt.Errors}
            Wait-PtClipboardPipeTask ($writer.WriteLineAsync((ConvertTo-Json $response -Depth 8 -Compress))) 10000 $Pump
        }catch{
            $lastError=$_.Exception.Message
            NoteFailure $lastError
            try{SaveReceipt}catch{NoteFailure "Receipt update failed; backup retained in process ${PID}: $($_.Exception.Message)"}
            if(-not $guard){$finished=$true}
            else{Start-Sleep -Milliseconds 200}
        }finally{
            foreach($resource in @($reader,$writer,$pipe)){
                if($resource){try{$resource.Dispose()}catch{NoteFailure "Transport cleanup failed: $($_.Exception.Message)"}}
            }
        }
    }
}

function Invoke-PtClipboardSessionRequest {
    param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)][string]$Command,[hashtable]$Arguments=@{})
    $ErrorActionPreference='Stop'
    $process=Get-Process -Id $Session.ProcessId -ErrorAction Stop
    if($process.StartTime.ToUniversalTime().Ticks -ne $Session.ProcessStartTicks){throw 'Clipboard keeper process identity changed; its original backup is unavailable.'}
    $pipe=[IO.Pipes.NamedPipeClientStream]::new('.',$Session.PipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
    $reader=$null;$writer=$null
    try{
        Wait-PtClipboardPipeTask ($pipe.ConnectAsync(3000)) 4000
        $reader=[IO.StreamReader]::new($pipe,[Text.UTF8Encoding]::new($false),$false,1024,$true)
        $writer=[IO.StreamWriter]::new($pipe,[Text.UTF8Encoding]::new($false),1024,$true);$writer.AutoFlush=$true
        $request=@{Id=$Session.Id;Command=$Command}
        foreach($key in $Arguments.Keys){
            if($key -in 'Id','Command'){throw 'Cannot override clipboard session identity/command.'}
            $request[$key]=$Arguments[$key]
        }
        Wait-PtClipboardPipeTask ($writer.WriteLineAsync((ConvertTo-Json $request -Compress))) 5000
        $line=Wait-PtClipboardPipeTask ($reader.ReadLineAsync()) 10000
        if(-not $line){throw 'Clipboard keeper disconnected; reconnect for status without replaying the action.'}
        $response=ConvertFrom-PtReportJson $line
        if($response.Id -cne $Session.Id -or $response.ProcessId -ne $Session.ProcessId -or
            $response.ProcessStartTicks -ne $Session.ProcessStartTicks){throw 'Clipboard keeper response identity mismatch.'}
        if($response.State){
            foreach($property in $response.State.PSObject.Properties){$Session.($property.Name)=$property.Value}
        }
        $Session.KeeperErrors=@($response.KeeperErrors)
        if($response.Success -isnot [bool] -or -not $response.Success){
            $error=[InvalidOperationException]::new("Clipboard keeper $Command failed: $($response.Error)")
            $error.Data['ClipboardFailure']=$response.Failure
            throw $error
        }
        $response.Result
    }catch{
        $_.Exception.Data['ClipboardRecoveryReceipt']=$Session.Path
        throw
    }finally{
        if($reader){$reader.Dispose()};if($writer){$writer.Dispose()};$pipe.Dispose()
    }
}

function Connect-PtClipboardSession {
    <#.SYNOPSIS
    Reattach to a still-live keeper; a receipt never reconstructs lost clipboard payload.
    #>
    param([Parameter(Mandatory)][string]$ReceiptPath)
    Assert-PtReportNoLink $ReceiptPath
    $record=ConvertFrom-PtReportJson (Read-PtSharedFileText $ReceiptPath)
    if($record.Schema -cne 'PtClipboardSession.v1' -or $record.Id -cnotmatch '^[a-f0-9]{32}$' -or
        $record.PipeName -cne "PowerToys.Verification.Clipboard.$($record.Id)" -or
        [IO.Path]::GetFullPath($ReceiptPath) -ine $record.Path -or $record.Phase -eq 'Disposed'){
        throw 'Invalid or disposed clipboard recovery receipt.'
    }
    $session=[pscustomobject]@{Id=$record.Id;Path=$record.Path;PipeName=$record.PipeName
        ProcessId=$record.ProcessId;ProcessStartTicks=$record.ProcessStartTicks
        Restored=$false;ExpectedSequence=0;PendingWriteState='None';PendingSequence=0;FormatCount=0;BitmapFromPng=$false
        OriginalWriterProcessId=0;Disposed=$false;KeeperErrors=@()}
    $session|Add-Member ScriptMethod Refresh {Invoke-PtClipboardSessionRequest $this Status|Out-Null}
    $session|Add-Member ScriptMethod AssertUnchanged {Invoke-PtClipboardSessionRequest $this AssertUnchanged|Out-Null}
    $session|Add-Member ScriptMethod BeginWrite {param($writer,$ticks) Invoke-PtClipboardSessionRequest $this BeginWrite @{WriterProcessId=$writer;WriterStartTicks=$ticks}|Out-Null}
    $session|Add-Member ScriptMethod SealWrite {param($sequence) Invoke-PtClipboardSessionRequest $this SealWrite @{Sequence=$sequence}|Out-Null}
    $session|Add-Member ScriptMethod FailWrite {Invoke-PtClipboardSessionRequest $this FailWrite|Out-Null}
    $session|Add-Member ScriptMethod ConfirmWrite {Invoke-PtClipboardSessionRequest $this ConfirmWrite}
    $session|Add-Member ScriptMethod AcceptWrite {param($sequence,$writer) Invoke-PtClipboardSessionRequest $this AcceptWrite @{Sequence=$sequence;WriterProcessId=$writer}}
    $session|Add-Member ScriptMethod Restore {Invoke-PtClipboardSessionRequest $this Restore|Out-Null}
    $session|Add-Member ScriptMethod Dispose {if(-not $this.Disposed){Invoke-PtClipboardSessionRequest $this Dispose|Out-Null;$this.Disposed=$true}}
    $session.Refresh()
    $resources=Get-PtActiveResourceSession
    if($resources){
        Assert-PtResourceSession $resources
        foreach($obligation in @($resources.Obligations|Where-Object {$_.RecoveryReceipt -ceq $record.Path})){
            if($obligation.OwnerProcessId -ne $record.ProcessId -or $obligation.KeeperStartTicks -ne $record.ProcessStartTicks){
                throw 'Clipboard recovery receipt does not match the original release obligation.'
            }
            $global:PtLiveResourceGuards[$obligation.Id]=$session
        }
    }
    $session
}

function New-PtClipboardSession {
    <#.SYNOPSIS
    Capture in a separate STA process so an ordinary controller exception cannot discard the original.
    #>
    param([Parameter(Mandatory)][string]$Workspace)
    $ErrorActionPreference='Stop'
    $resources=Get-PtActiveResourceSession
    if($resources -and $resources.ResourcePlan -and -not @($resources.ResourcePlan.Resources|Where-Object Kind -EQ 'Clipboard').Count){
        throw 'Clipboard access is not declared in the run resource plan.'
    }
    Initialize-PtClipboardGuard
    $directory=(Get-Item -LiteralPath $Workspace -ErrorAction Stop).FullName
    Assert-PtReportNoLink $directory
    $id=[guid]::NewGuid().ToString('N')
    $receipt=Join-Path $directory "clipboard-session-$id.json"
    $start=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -ErrorAction Stop).Source)
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($argument in @('-NoProfile','-STA','-File',"$PSScriptRoot\hosts\clipboard-keeper.ps1",'-Id',$id,'-ReceiptPath',$receipt)){
        $start.ArgumentList.Add($argument)
    }
    $process=[Diagnostics.Process]::Start($start)
    try{
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while(-not [IO.File]::Exists($receipt)){
            if($process.HasExited){throw 'Clipboard keeper exited before readiness.'}
            if($clock.ElapsedMilliseconds -gt 10000){throw 'Clipboard keeper startup timed out.'}
            Start-Sleep -Milliseconds 25
        }
        $session=Connect-PtClipboardSession $receipt
        if($session.ProcessId -ne $process.Id -or $session.ProcessStartTicks -ne $process.StartTime.ToUniversalTime().Ticks){
            throw 'Clipboard keeper is not the launched process.'
        }
        Invoke-PtClipboardSessionRequest $session Capture|Out-Null
        if(Get-PtActiveResourceSession){
            Add-PtClipboardObligation -Guard $session -OwnerProcessId $session.ProcessId
            if($session.OriginalWriterProcessId -gt 0){Protect-PtClipboardWriter $session $session.OriginalWriterProcessId}
        }
        $session
    }catch{
        $_.Exception.Data['ClipboardRecoveryReceipt']=$receipt
        throw
    }finally{$process.Dispose()}
}
