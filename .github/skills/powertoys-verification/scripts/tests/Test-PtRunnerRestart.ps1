#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-runner-restart-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach($helper in 'pt-module-lifecycle','pt-admin-probe','pt-state'){. "$skill\scripts\$helper.ps1"}
if(Test-Path -LiteralPath $Workspace){throw 'Use a new test workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$image=Join-Path $Workspace 'PowerToys.exe'
[IO.File]::WriteAllText($image,'synthetic image')
$results=[Collections.Generic.List[object]]::new()
function Require($value,$message){if(-not $value){throw $message}}
function Reject([scriptblock]$body,[string]$pattern){
    try{& $body|Out-Null}catch{
        if($_.Exception.Message -notmatch $pattern){throw}
        return $_
    }
    throw "Expected error: $pattern"
}
function Check([string]$name,[scriptblock]$body){
    ResetFixture
    & $body
    $results.Add(@{Name=$name;Status='PASS'})
}
$saved=@{}
foreach($name in 'Get-PtRunnerRestartState','Get-PtLifecycleProcessProbe','Get-PtLifecycleProcessCandidates',
    'Get-PtLifecycleProcessIdentity','Get-PtLifecycleRunner','Get-PtNativeWindow','Get-PtWindowIdentity',
    'Test-ProcessElevated','Send-PtRunnerExit','Start-PtRunnerAfterExit','Assert-PtProcessRelease','Get-PtActiveResourceSession'){
    $saved[$name]=(Get-Command $name).ScriptBlock
}
function ResetFixture {
    $script:fixture=@{
        Old=[pscustomobject]@{processId=410;processStartTicks=100L;sessionId=2;path=$image}
        New=[pscustomobject]@{processId=411;processStartTicks=200L;sessionId=2;path=$image}
        Exited=$false;Started=$false;StopRequests=0;Launches=0;Reads=0;StateReads=0
        CallerElevated=$false;NewElevated=$false;NoExit=$false;Ambiguous=$false;ClipboardBlocked=$false
        ExtraWindow=$false;NoHost=$false;ProbeFailure=$false;Session=$null;OtherProcesses=@()
    }
}
function Get-PtRunnerRestartState {
    $fixture.StateReads++
    $windows=if($fixture.ExtraWindow -and $fixture.StateReads -gt 1){
        @([pscustomobject]@{hwnd=990;processId=410;processStartTicks=100L;className='NewDialog'})
    }else{@()}
    [pscustomobject]@{
        Runner=$fixture.Old;Elevated=$false;Host=[pscustomobject]@{hwnd=910;processId=410;processStartTicks=100L;className='PToyTrayIconWindow'}
        ImageHash=(Get-FileHash $image).Hash;Processes=@($fixture.Old)+$fixture.OtherProcesses;VisibleWindows=$windows
    }
}
function Get-PtLifecycleProcessProbe {
    param($ProcessId)
    if($fixture.ProbeFailure){throw 'process probe failed'}
    if($ProcessId -eq $fixture.Old.processId -and -not $fixture.Exited){return $fixture.Old}
    if($ProcessId -eq $fixture.New.processId -and $fixture.Started){return $fixture.New}
}
function Get-PtLifecycleProcessCandidates {
    param($Name)
    if($fixture.Started){
        [pscustomobject]@{Id=$fixture.New.processId;SessionId=2}
        if($fixture.Ambiguous){[pscustomobject]@{Id=412;SessionId=2}}
    }
}
function Get-PtLifecycleProcessIdentity {
    param($Process,[switch]$AllowExited)
    if($Process.Id -eq 412){return [pscustomobject]@{processId=412;processStartTicks=201L;sessionId=2;path=$image}}
    Get-PtLifecycleProcessProbe $Process.Id
}
function Get-PtNativeWindow {
    param($ProcessId,$ClassName)
    if(-not $fixture.NoHost){[pscustomobject]@{Hwnd=911;ProcessId=$fixture.New.processId;ClassName='PToyTrayIconWindow'}}
}
function Get-PtWindowIdentity {
    param($Hwnd)
    [pscustomobject]@{hwnd=$Hwnd;processId=$fixture.New.processId;processStartTicks=$fixture.New.processStartTicks;className='PToyTrayIconWindow'}
}
function Test-ProcessElevated {
    param($ProcessId)
    if($ProcessId -eq $PID){return $fixture.CallerElevated}
    $fixture.NewElevated
}
function Send-PtRunnerExit {
    param($State)
    $fixture.StopRequests++
    if(-not $fixture.NoExit){$fixture.Exited=$true}
}
function Start-PtRunnerAfterExit {
    param($State)
    $fixture.Launches++;$fixture.Started=$true
    Require ($State.Runner.path -ceq $image) 'Launch lost actual installation path'
    [pscustomobject]@{ProcessId=$fixture.New.processId}
}
function Assert-PtProcessRelease {
    param($ProcessId)
    if($fixture.ClipboardBlocked){throw 'unresolved clipboard obligation'}
}
function Get-PtActiveResourceSession {$fixture.Session}
$options=@{Prepare={param($before) $true};VerifyReady={param($after) $fixture.Reads++;$true};TimeoutSeconds=0.3}
try{
    Check 'Legacy parameterless restart fails explicitly before any process action' {
        Reject {Restart-PtRunner} 'requires explicit Prepare and VerifyReady'|Out-Null
        Require ($fixture.StopRequests -eq 0 -and $fixture.Launches -eq 0) 'Unguarded legacy route survived'
    }
    Check 'Normal restart requests exit/launch once and returns stable new identity' {
        $r=Restart-PtRunner @options
        Require ($r.Ready -and $r.Scope -ceq 'PowerToys' -and $r.After.Runner.processId -eq 411) 'Missing observed replacement'
        Require ($fixture.StopRequests -eq 1 -and $fixture.Launches -eq 1 -and $fixture.Reads -eq 2) 'Action replayed or readiness not stable'
    }
    Check 'UI route is not replaced by a generic restart; array arguments stay intact' {
        $copy=$options.Clone();$packet=[pscustomobject]@{Values=@('a','b')}
        $copy.ArgumentList=@($packet)
        $copy.RestartAction={param($before,$packet) Require ($packet.Values.Count -eq 2) 'Packet flattened';$fixture.Exited=$true;$fixture.Started=$true}
        $r=Restart-PtRunner @copy
        Require ($r.Route -ceq 'ProductAction' -and $fixture.StopRequests -eq 0 -and $fixture.Launches -eq 0) 'UI action substituted'
    }
    Check 'Failed UI action retains original failure and partial receipt without recovery' {
        $copy=$options.Clone();$copy.RestartAction={throw 'UI action failed'}
        $error=Reject {Restart-PtRunner @copy} 'UI action failed'
        Require ($error.Exception.Data['RunnerRestartReceipt'].ActionIssued -and $fixture.Launches -eq 0) 'Original action failure lost'
    }
    Check 'Preparation refusal and non-Boolean output stop before mutation' {
        foreach($prepare in { $false },{ 'ready' },{ $true;$true }){
            $copy=$options.Clone();$copy.Prepare=$prepare
            Reject {Restart-PtRunner @copy} 'exactly Boolean true'|Out-Null
        }
        Require ($fixture.StopRequests -eq 0) 'Failed preparation stopped Runner'
    }
    Check 'Preparation cannot replace the captured identity by mutating its input' {
        $copy=$options.Clone();$copy.Prepare={param($before) $before.Runner.processId=999;$true}
        $r=Restart-PtRunner @copy
        Require ($r.Before.Runner.processId -eq 410) 'Callback modified immutable target'
    }
    Check 'A new visible window after preparation requires an explicit new review' {
        $fixture.ExtraWindow=$true
        Reject {Restart-PtRunner @options} 'new affected visible window'|Out-Null
        Require ($fixture.StopRequests -eq 0) 'Unreviewed dialog was closed'
    }
    Check 'Clipboard dependency blocks process release' {
        $fixture.ClipboardBlocked=$true
        Reject {Restart-PtRunner @options} 'clipboard obligation'|Out-Null
        Require ($fixture.StopRequests -eq 0) 'Clipboard owner released'
    }
    Check 'Token mismatch refuses before exit but explicit launch adapter is supported' {
        $fixture.CallerElevated=$true
        Reject {Restart-PtRunner @options} 'elevation differ'|Out-Null
        Require ($fixture.StopRequests -eq 0) 'Mismatched caller stopped Runner'
        $copy=$options.Clone();$copy.Launch={param($before) $fixture.Launches++;$fixture.Started=$true}
        $r=Restart-PtRunner @copy
        Require ($r.Ready -and -not $r.After.Elevated) 'Launch adapter result not checked'
    }
    Check 'Elevation transition requires the actual product action and validates its result' {
        $copy=$options.Clone();$copy.ExpectedElevation='Elevated'
        Reject {Restart-PtRunner @copy} 'requires the explicit product'|Out-Null
        $copy.RestartAction={$fixture.Exited=$true;$fixture.Started=$true;$fixture.NewElevated=$true}
        $r=Restart-PtRunner @copy
        Require $r.After.Elevated 'Expected elevated result not observed'
    }
    Check 'Exit timeout does not force-kill or launch another instance' {
        $fixture.NoExit=$true
        $error=Reject {Restart-PtRunner @options} 'Timed out waiting'
        Require ($fixture.StopRequests -eq 1 -and $fixture.Launches -eq 0 -and
            $error.Exception.Data['RunnerRestartReceipt'].Phase -ceq 'Exit') 'Exit failure lost or bypassed'
    }
    Check 'Wrong executable and ambiguous Runner identities fail rather than adopting them' {
        $copy=$options.Clone();$copy.RestartAction={$fixture.Exited=$true;$fixture.Started=$true;$fixture.New.path='C:\wrong\PowerToys.exe'}
        Reject {Restart-PtRunner @copy} 'attested installation'|Out-Null
        ResetFixture
        $fixture.Ambiguous=$true
        Reject {Restart-PtRunner @options} 'Ambiguous current-session'|Out-Null
    }
    Check 'PID reuse is distinguished by creation identity' {
        $fixture.New.processId=$fixture.Old.processId
        $r=Restart-PtRunner @options
        Require ($r.Ready -and $r.After.Runner.processStartTicks -eq 200L) 'New creation with recycled PID was confused with old Runner'
    }
    Check 'Readiness absence, exceptions and non-Boolean output never become success' {
        $copy=$options.Clone();$copy.VerifyReady={ $false }
        Reject {Restart-PtRunner @copy} 'Timed out waiting'|Out-Null
        ResetFixture
        $copy.VerifyReady={throw 'readiness probe failed'}
        Reject {Restart-PtRunner @copy} 'readiness probe failed'|Out-Null
        ResetFixture
        $copy.VerifyReady={ 'ready' }
        Reject {Restart-PtRunner @copy} 'exactly one Boolean'|Out-Null
    }
    Check 'Read errors remain errors, not evidence that Runner exited' {
        $fixture.ProbeFailure=$true
        Reject {Restart-PtRunner @options} 'process probe failed'|Out-Null
        Require ($fixture.StopRequests -eq 0) 'Read error allowed destructive action'
    }
    Check 'Missing native host cannot satisfy readiness' {
        $fixture.NoHost=$true
        Reject {Restart-PtRunner @options} 'Timed out waiting'|Out-Null
    }
    Check 'Common restart authorizes only originally restartable Settings resources' {
        $directory=Join-Path $Workspace 'restartable-session'
        [IO.Directory]::CreateDirectory($directory)|Out-Null
        $run=[pscustomobject]@{Id='restart-resource-fixture';Workspace=$directory}
        $fixture.Session=New-PtResourceSession $run
        $identity=[pscustomobject]@{hwnd=920;processId=420;processStartTicks=120L;className='SettingsFixture'}
        $fixture.OtherProcesses=@([pscustomobject]@{processId=420;processStartTicks=120L;sessionId=2;path=(Join-Path $Workspace 'PowerToys.Settings.exe')})
        $path=Join-Path $directory 'settings-original.json'
        Write-PtReportText $path '{}'
        $fixture.Session.Windows=@([pscustomobject]@{Identity=$identity;Ownership='Borrowed'})
        $fixture.Session.Settings=@([pscustomobject]@{
            Path=$path;Identity=$identity;AllowRunnerRestart=$false;ReplacementIdentity=$null
            RestartAuthorization=$null;Restored=$false
        })
        Save-PtResourceSession $fixture.Session
        Reject {Restart-PtRunner @options} 'same-instance restoration'|Out-Null
        Require ($fixture.StopRequests -eq 0) 'Borrowed lifetime contract was bypassed'
        $fixture.Session.Settings[0].AllowRunnerRestart=$true
        Save-PtResourceSession $fixture.Session
        $r=Restart-PtRunner @options
        $authorization=$fixture.Session.Settings[0].RestartAuthorization
        Require ($r.Ready -and $authorization.Runner.processId -eq 410 -and
            $authorization.StartedTicks -gt 0) 'Actual restart did not persist logical handover authorization'
        $global:PtActiveResourceSession=$null
    }
}finally{
    $global:PtActiveResourceSession=$null
    foreach($name in $saved.Keys){Set-Item "Function:\$name" $saved[$name]}
}
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe "/out:$image" "$PSScriptRoot\fixtures\RunnerRestartFixture.cs"
if($LASTEXITCODE -ne 0){throw 'Runner fixture compilation failed.'}
$originalCandidates=${function:Get-PtLifecycleProcessCandidates}
function Get-PtLifecycleProcessCandidates {
    param($Name)
    foreach($candidate in @(& $originalCandidates $Name)){
        $identity=Get-PtLifecycleProcessIdentity $candidate -AllowExited
        if($identity -and $identity.path -ieq $image){$candidate}
    }
}
$initial=$null
try{
    $initial=Start-Process -FilePath $image -PassThru -ErrorAction Stop
    Wait-PtCondition -Description 'hidden synthetic Runner host' -TimeoutSeconds 5 -Probe {
        @(Get-PtNativeWindow -ProcessId $initial.Id -ClassName 'PToyTrayIconWindow').Count -eq 1 -and
        [IO.File]::Exists("$Workspace\fixture-ready.txt")
    }|Out-Null
    $receipt=Restart-PtRunner -Prepare {
        param($before)
        Require ($before.Runner.path -ieq $image -and $before.VisibleWindows.Count -eq 0) 'Fixture scope includes unexpected UI'
        $true
    } -VerifyReady {
        param($identity)
        [IO.File]::ReadAllText("$Workspace\fixture-ready.txt") -ceq "$($identity.processId)"
    } -TimeoutSeconds 5
    Require ($receipt.Ready -and $receipt.Before.Runner.processId -ne $receipt.After.Runner.processId -and
        $receipt.Before.Elevated -eq $receipt.After.Elevated) 'Native restart did not preserve path/token or change process'
    Require ($null -eq (Get-PtLifecycleProcessProbe $initial.Id)) 'Original fixture did not exit'
    Write-PtReportText "$Workspace\native-restart.json" (ConvertTo-Json $receipt -Depth 15)
    $results.Add(@{Name='Actual hidden native host, graceful WM_CLOSE, same-path launch and observed identity/token/readiness';Status='PASS'})
}finally{
    foreach($candidate in @(Get-PtLifecycleProcessCandidates 'PowerToys')){
        $identity=Get-PtLifecycleProcessIdentity $candidate -AllowExited
        foreach($window in @(Get-PtNativeWindow -ProcessId $identity.processId -ClassName 'PToyTrayIconWindow')){
            Assert-PtRunnerRestartIdentity $identity
            if(-not [PtDesktop]::PostMessage([IntPtr]$window.Hwnd,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)){
                throw 'Could not request synthetic fixture cleanup.'
            }
        }
        Wait-PtCondition -Description 'synthetic Runner cleanup' -TimeoutSeconds 5 -Probe {
            $null -eq (Get-PtLifecycleProcessProbe $identity.processId)
        }|Out-Null
    }
    Set-Item Function:\Get-PtLifecycleProcessCandidates $originalCandidates
    if($initial){$initial.Dispose()}
    foreach($file in $image,"$Workspace\fixture-ready.txt"){
        if(Test-Path -LiteralPath $file){Remove-Item -LiteralPath $file -ErrorAction Stop}
    }
}
Write-PtReportText "$Workspace\results.json" (ConvertTo-Json $results -Depth 5)
"PASS: $($results.Count) unified Runner restart groups including actual hidden native fixture; no installed product was restarted. $Workspace"
