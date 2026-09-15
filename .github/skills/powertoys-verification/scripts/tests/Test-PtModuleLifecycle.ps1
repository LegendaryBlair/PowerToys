#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-lifecycle-$([Guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$helpers=Split-Path $PSScriptRoot -Parent
. "$helpers\pt-module-lifecycle.ps1"
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
function CaptureFailure([scriptblock]$Body){
    try{& $Body|Out-Null}catch{return $_}
    throw 'Expected a terminating observation error'
}
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace});throw}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
$profile=[pscustomobject]@{Id='fixture';ModuleKey='Fixture';PageAutomationId='FixtureNav';ToggleAutomationId='FixtureToggle'
    Model='Resident';ProcessName='fixture';ProcessPath='C:\fixture\fixture.exe';WindowClass='FixtureHost'
    Events=@(@{Name='Local\pt-lifecycle-fixture';WhenEnabled='Present';WhenDisabled='Ignore'})}
$runner=[pscustomobject]@{processId=10;processStartTicks=100;sessionId=1;path='C:\fixture\PowerToys.exe'}
$process=[pscustomobject]@{processId=11;processStartTicks=101;sessionId=1;path='C:\fixture\fixture.exe'}
$window=[pscustomobject]@{identity=[pscustomobject]@{hwnd=20;processId=11;processStartTicks=101;className='FixtureHost'};visible=$false;minimized=$false}
$event=[pscustomobject]@{Name='Local\pt-lifecycle-fixture';Exists=$true;WhenEnabled='Present';WhenDisabled='Ignore'}
function State([bool]$Enabled,[bool]$Runtime=$true){
    ConvertTo-PtModuleLifecycleState $profile $Enabled $runner @($(if($Runtime){$process})) @($(if($Runtime){$window})) @($event)
}
function New-ProbeFailure([int]$Code,[string]$Stage){
    $error=[ComponentModel.Win32Exception]::new($Code)
    $error.Data['LifecycleProcessStage']=$Stage
    $error.Data['LifecycleProcessIdentity']=[pscustomobject]@{processId=11;processStartTicks=101;sessionId=1;path=$null}
    $error
}
Check 'Profiles require explicit models, executable scope and per-state event semantics' {
    Assert-PtModuleLifecycleProfile $profile
    $copy=ConvertFrom-PtReportJson (ConvertTo-Json $profile -Depth 10)
    $copy.Model='Unknown';Reject {Assert-PtModuleLifecycleProfile $copy} 'explicit lifecycle'
    $copy=ConvertFrom-PtReportJson (ConvertTo-Json $profile -Depth 10)
    $copy.ProcessName='PowerToys';$copy.ProcessPath='C:\fixture\PowerToys.exe'
    Reject {Assert-PtModuleLifecycleProfile $copy} 'Runner/Settings'
    $copy=ConvertFrom-PtReportJson (ConvertTo-Json $profile -Depth 10)
    $copy.Events[0].WhenDisabled='Guess';Reject {Assert-PtModuleLifecycleProfile $copy} 'explicit Present/Absent/Ignore'
}
Check 'Resident readiness is not inferred from enabled JSON, and Runner-owned events may survive disable' {
    Require ((State $true $false).Status -eq 'TransitioningOrUnavailable') 'Enabled flag falsely proved process readiness'
    Require ((State $true $true).RuntimeReady) 'Complete native contract was not ready'
    Require ((State $false $true).Status -eq 'TransitioningOrUnavailable') 'Disable ignored a surviving process'
    $off=State $false $false
    Require ($off.Status -eq 'Disabled' -and $off.Events[0].Exists) 'Surviving Runner-owned event prevented valid disable'
    $missingHost=ConvertTo-PtModuleLifecycleState $profile $true $runner @($process) @() @($event)
    Require (-not $missingHost.SatisfiesNativeContract) 'Process presence substituted for required host'
}
Check 'Runner-hosted and on-demand models do not invent independent process readiness' {
    $hosted=[pscustomobject]@{Id='hosted';ModuleKey='Hosted';PageAutomationId='HostedNav';ToggleName='Hosted';Model='RunnerHosted';WindowClass='HostedWindow'}
    Assert-PtModuleLifecycleProfile $hosted
    $ready=ConvertTo-PtModuleLifecycleState $hosted $true $runner @() @($window) @()
    Require ($ready.RuntimeReady -and $ready.Processes.Count -eq 0 -and $ready.Runner.processId -eq 10) 'Runner-hosted required an invented process'
    $onDemand=[pscustomobject]@{Id='on-demand';ModuleKey='Demand';PageAutomationId='DemandNav';ToggleName='Demand';Model='OnDemand'}
    Assert-PtModuleLifecycleProfile $onDemand
    $idle=ConvertTo-PtModuleLifecycleState $onDemand $true $runner @() @() @()
    Require ($idle.Status -eq 'ConfiguredEnabled' -and -not $idle.RuntimeReady -and $idle.Scope -eq 'ConfigurationOnly') 'On-demand configuration claimed runtime readiness'
}
Check 'Ambiguous process/host ownership and explicit missing signal remain failures' {
    $ambiguous=ConvertTo-PtModuleLifecycleState $profile $true $runner @($process,$process) @($window) @($event)
    Require ($ambiguous.Status -eq 'Ambiguous' -and -not $ambiguous.SatisfiesNativeContract) 'Multiple processes were silently selected'
    $missing=[pscustomobject]@{Name='event';Exists=$false;WhenEnabled='Present';WhenDisabled='Absent'}
    Require (-not (ConvertTo-PtModuleLifecycleState $profile $true $runner @($process) @($window) @($missing)).RuntimeReady) 'Missing required event was ignored'
}
Check 'Candidate probes exclude other sessions and wrong paths, retain all exact matches and tolerate confirmed exit' {
    $calls=[Collections.Generic.List[int]]::new()
    function Get-PtLifecycleProcessCandidates {
        param($Name)
        Require ($Name -eq 'fixture') 'Wrong candidate name'
        foreach($id in 11..16){[pscustomobject]@{Id=$id;SessionId=$(if($id -eq 12){2}else{1})}}
    }
    function Get-PtLifecycleProcessProbe {
        param($ProcessId)
        $calls.Add($ProcessId)
        if($ProcessId -eq 13){return}
        [pscustomobject]@{processId=$ProcessId;processStartTicks=(100+$ProcessId)
            sessionId=$(if($ProcessId -eq 16){2}else{1})
            path=$(if($ProcessId -eq 14){'C:\elsewhere\fixture.exe'}else{$profile.ProcessPath})}
    }
    $found=@(Get-PtLifecycleProcesses $profile 1)
    Require (($calls -join ',') -eq '11,13,14,15,16') 'Other-session candidate was opened or an in-scope candidate was skipped'
    Require (($found.processId -join ',') -eq '11,15') 'Path/session filtering selected a wrong or single arbitrary process'
    Require ((ConvertTo-PtModuleLifecycleState $profile $true $runner $found @() @($event)).Status -eq 'Ambiguous') 'Multiple live candidates claimed readiness'
}
Check 'Denied candidates terminate with identity, stage, native code and original exception rather than apparent exit' {
    function Get-PtLifecycleProcessCandidates {param($Name) [pscustomobject]@{Id=11;SessionId=1}}
    foreach($stage in 'OpenProcess','GetProcessTimes','QueryFullProcessImageName','GetExitCodeProcess.After'){
        $original=New-ProbeFailure 5 $stage
        function Get-PtLifecycleProcessProbe {param($ProcessId) throw $original}
        $failure=CaptureFailure {Get-PtLifecycleProcesses $profile 1}
        $detail=$failure.Exception.Data['LifecycleProcessObservation']
        Require ($failure.FullyQualifiedErrorId -like 'PtLifecycleProcess.ReadError*') 'Missing structured error ID'
        Require ($detail.Status -eq 'ReadError' -and $detail.Stage -eq $stage -and $detail.NativeErrorCode -eq 5) 'Native error provenance lost'
        Require ($detail.processId -eq 11 -and $detail.processStartTicks -eq 101 -and $detail.sessionId -eq 1 -and
            $detail.ExpectedPath -eq $profile.ProcessPath -and $null -eq $detail.path) 'Unknown path became a claimed identity'
        Require ([object]::ReferenceEquals($failure.Exception.GetBaseException(),$original)) 'Original native exception was replaced'
    }
    function Get-PtLifecycleRunner {$runner}
    function Get-PtLifecycleConfiguredEnabled {param($Profile) $false}
    $failure=CaptureFailure {Wait-PtModuleLifecycle $profile $false -TimeoutSeconds 0.2}
    Require ($failure.Exception.Data['LifecycleProcessObservation'].NativeErrorCode -eq 5 -and
        $null -eq $failure.Exception.Data['LifecycleLastObservation']) 'Failed observation became Disabled or RuntimeReady'
}
Check 'One healthy candidate cannot hide a denied candidate, and unrelated failures propagate unchanged' {
    function Get-PtLifecycleProcessCandidates {param($Name) [pscustomobject]@{Id=10;SessionId=1};[pscustomobject]@{Id=11;SessionId=1}}
    $original=New-ProbeFailure 5 'OpenProcess'
    function Get-PtLifecycleProcessProbe {param($ProcessId) if($ProcessId -eq 11){throw $original};$process}
    $emitted=[Collections.Generic.List[object]]::new()
    $failure=CaptureFailure {Get-PtLifecycleProcesses $profile 1|ForEach-Object {$emitted.Add($_)}}
    Require ($emitted.Count -eq 0 -and [object]::ReferenceEquals($failure.Exception.GetBaseException(),$original)) 'Partial results escaped the failed observation'
    foreach($original in @([InvalidOperationException]::new('Unrelated enumeration bug'),[ComponentModel.Win32Exception]::new(6))){
        function Get-PtLifecycleProcessProbe {param($ProcessId) throw $original}
        $failure=CaptureFailure {Get-PtLifecycleProcesses $profile 1}
        Require ([object]::ReferenceEquals($failure.Exception.GetBaseException(),$original)) 'Unrelated exception was swallowed or reclassified'
    }
    function Get-PtLifecycleProcessCandidates {param($Name) throw $original}
    $failure=CaptureFailure {Get-PtLifecycleProcesses $profile 1}
    Require ([object]::ReferenceEquals($failure.Exception.GetBaseException(),$original)) 'Enumeration failure became an empty candidate set'
}
Check 'Runner identity uses the same probe and refuses missing, reused-session or multiple candidates' {
    $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
    $fixture=@{Ids=@(10);Session=$session;Path='C:\fixture\PowerToys.exe'}
    function Get-PtLifecycleProcessCandidates {param($Name) foreach($id in $fixture.Ids){[pscustomobject]@{Id=$id;SessionId=$session}}}
    function Get-PtLifecycleProcessProbe {param($ProcessId) [pscustomobject]@{processId=$ProcessId;processStartTicks=100;sessionId=$fixture.Session;path=$fixture.Path}}
    Require ((Get-PtLifecycleRunner).processId -eq 10) 'Runner query did not use native identity'
    $fixture.Session=$session+1
    Reject {Get-PtLifecycleRunner} 'Exactly one Runner'
    $fixture.Session=$session;$fixture.Ids=@(10,11)
    Reject {Get-PtLifecycleRunner} 'Exactly one Runner'
    $fixture.Ids=@(10);$fixture.Path='C:\fixture\other.exe'
    Reject {Get-PtLifecycleRunner} 'Exactly one Runner'
    function Get-PtLifecycleProcessProbe {param($ProcessId) return}
    Reject {Get-PtLifecycleRunner} 'Exactly one Runner'
}
Check 'PID reuse resets stable readiness rather than retaining the old start time' {
    $old=State $true $true
    $new=State $true $true
    $new.Processes=@([pscustomobject]@{processId=11;processStartTicks=202;sessionId=1;path=$profile.ProcessPath})
    $new.Windows=@([pscustomobject]@{identity=[pscustomobject]@{hwnd=20;processId=11;processStartTicks=202;className='FixtureHost'};visible=$false;minimized=$false})
    $sequence=[Collections.Generic.Queue[object]]::new()
    foreach($state in @($old,$new,$new)){$sequence.Enqueue($state)}
    function Get-PtModuleLifecycleState {param($Profile) $sequence.Dequeue()}
    $ready=Wait-PtModuleLifecycle $profile $true -TimeoutSeconds 2 -ExpectedRunner $runner
    Require ($sequence.Count -eq 0 -and $ready.Processes[0].processStartTicks -eq 202) 'Recycled PID satisfied the previous identity stability check'
}
Check 'Wait observes a stable native identity and preserves the last failed observation' {
    $sequence=[Collections.Generic.Queue[object]]::new()
    $sequence.Enqueue((State $true $false));$sequence.Enqueue((State $true $true));$sequence.Enqueue((State $true $true))
    function Get-PtModuleLifecycleState {param($Profile) $sequence.Dequeue()}
    $ready=Wait-PtModuleLifecycle $profile $true -TimeoutSeconds 2 -ExpectedRunner $runner
    Require ($ready.RuntimeReady -and $sequence.Count -eq 0) 'Wait returned before two stable ready observations'
    function Get-PtModuleLifecycleState {param($Profile) State $true $false}
    $caught=$false
    try{Wait-PtModuleLifecycle $profile $true -TimeoutSeconds 0.15|Out-Null}catch{
        Require ($_.Exception.Data['LifecycleLastObservation'].Status -eq 'TransitioningOrUnavailable') 'Timeout lost its concrete state'
        $caught=$true
    }
    Require $caught 'Unavailable runtime did not time out'
    $changed=State $true $true;$changed.Runner=[pscustomobject]@{processId=99;processStartTicks=999;sessionId=1;path='C:\fixture\PowerToys.exe'}
    function Get-PtModuleLifecycleState {param($Profile) $changed}
    Reject {Wait-PtModuleLifecycle $profile $true -ExpectedRunner $runner} 'Runner identity changed'
}
Check 'Missing/non-Boolean configuration is not treated as disabled' {
    $copy=ConvertFrom-PtReportJson (ConvertTo-Json $profile -Depth 10)
    $path=Join-Path $Workspace 'settings.json'
    $copy|Add-Member NoteProperty SettingsPath $path
    [IO.File]::WriteAllText($path,'{"enabled":{}}')
    Reject {Get-PtLifecycleConfiguredEnabled $copy} 'Missing/non-Boolean'
    [IO.File]::WriteAllText($path,'{"enabled":{"Fixture":"false"}}')
    Reject {Get-PtLifecycleConfiguredEnabled $copy} 'Missing/non-Boolean'
    [IO.File]::WriteAllText($path,'{"enabled":{"Fixture":false}}')
    Require ((Get-PtLifecycleConfiguredEnabled $copy) -eq $false) 'Real false was lost'
}
Check 'Event observation distinguishes absence from wrong kernel object type' {
    $name="Local\pt-lifecycle-$([Guid]::NewGuid().ToString('N'))"
    Require (-not (Test-PtSharedEvent $name)) 'Missing event was present'
    $handle=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$name)
    try{Require (Test-PtSharedEvent $name) 'Existing event not observed'}finally{$handle.Dispose()}
    Require (-not (Test-PtSharedEvent $name)) 'Probe retained an event handle'
    $mutex=[Threading.Mutex]::new($false,$name)
    try{Reject {Test-PtSharedEvent $name} 'Cannot observe event'}finally{$mutex.Dispose()}
}
Check 'Explicit transitions and cleanup recover partial enablement without automatic restart' {
    $fixture=@{Enabled=$false;Runtime=$false;Boot=$true;Toggles=0;Visible=$false}
    function Get-PtModuleLifecycleState {
        param($Profile)
        $state=State $fixture.Enabled $fixture.Runtime
        if($fixture.Visible){$state.VisibleWindows=@($window)}
        $state
    }
    function Get-PtLifecycleToggle {
        param($Snapshot)
        $pattern=[pscustomobject]@{Fixture=$fixture}
        $pattern|Add-Member ScriptMethod Toggle {
            $this.Fixture.Toggles++
            $this.Fixture.Enabled=-not $this.Fixture.Enabled
            $this.Fixture.Runtime=$this.Fixture.Enabled -and $this.Fixture.Boot
        }
        [pscustomobject]@{Enabled=$fixture.Enabled;Pattern=$pattern;Control=$null}
    }
    $settings=[pscustomobject]@{hwnd=2;processId=3;processStartTicks=4;className='SyntheticSettings'}
    $snapshot=Get-PtModuleLifecycleSnapshot $profile $settings $Workspace
    $on=Set-PtModuleEnabled $snapshot $true -TimeoutSeconds 2
    Require ($on.Changed -and $on.After.RuntimeReady -and $on.InvalidatePriorReferences) 'Enable did not return fresh runtime observations'
    $noop=Set-PtModuleEnabled $snapshot $true -TimeoutSeconds 2
    Require (-not $noop.Changed -and $fixture.Toggles -eq 1) 'Matching enable state was toggled'
    Restore-PtModuleLifecycleSnapshot $snapshot -TimeoutSeconds 2|Out-Null
    Require (-not $fixture.Enabled -and $fixture.Toggles -eq 2) 'Original disabled state was not restored'
    $fixture.Boot=$false
    Reject {Set-PtModuleEnabled $snapshot $true -TimeoutSeconds 0.15} 'Timed out'
    Require ($fixture.Toggles -eq 3) 'Failed enable silently retried/restarted'
    $saved=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($snapshot.ReceiptPath))
    Require ($saved.PendingEnabled -eq $true -and $saved.OriginalEnabled -eq $false) 'Partial transition lost its recovery receipt'
    Restore-PtModuleLifecycleSnapshot -ReceiptPath $saved.ReceiptPath -TimeoutSeconds 2|Out-Null
    Require (-not $fixture.Enabled -and $fixture.Toggles -eq 4) 'Cleanup did not handle a persisted partial enable'
    $fixture.Enabled=$true;$fixture.Runtime=$true;$fixture.Boot=$true;$fixture.Visible=$true
    $visibleSnapshot=Get-PtModuleLifecycleSnapshot $profile $settings $Workspace
    Reject {Set-PtModuleEnabled $visibleSnapshot $false} 'visible UI'
    Require ($fixture.Toggles -eq 4) 'Visible user UI was closed'
}
Check 'Limited-rights native identity survives denied HasExited and MainModule; required denial is never exit' {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;
public static class PtLifecycleAclFixture {
    [DllImport("advapi32.dll")] static extern uint GetSecurityInfo(SafeProcessHandle h,int type,uint info,
        out IntPtr owner,out IntPtr group,out IntPtr dacl,out IntPtr sacl,out IntPtr descriptor);
    [DllImport("advapi32.dll")] static extern uint SetSecurityInfo(SafeProcessHandle h,int type,uint info,
        IntPtr owner,IntPtr group,byte[] dacl,IntPtr sacl);
    [DllImport("advapi32.dll")] static extern int GetSecurityDescriptorLength(IntPtr descriptor);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
    public static byte[] Save(SafeProcessHandle process) {
        uint code=GetSecurityInfo(process,6,4,out var owner,out var group,out var dacl,out var sacl,out var descriptor);
        if(code != 0) throw new Win32Exception((int)code);
        try {
            var bytes=new byte[GetSecurityDescriptorLength(descriptor)];
            Marshal.Copy(descriptor,bytes,0,bytes.Length);
            return bytes;
        } finally { LocalFree(descriptor); }
    }
    public static void Apply(SafeProcessHandle process,byte[] original,int deny) {
        var descriptor=new RawSecurityDescriptor(original,0);
        var acl=descriptor.DiscretionaryAcl;
        if(acl == null) throw new InvalidOperationException("Fixture requires a non-null original DACL.");
        if(deny != 0) acl.InsertAce(0,new CommonAce(AceFlags.None,AceQualifier.AccessDenied,deny,
            new SecurityIdentifier(WellKnownSidType.WorldSid,null),false,null));
        var bytes=new byte[acl.BinaryLength];
        acl.GetBinaryForm(bytes,0);
        uint code=SetSecurityInfo(process,6,4,IntPtr.Zero,IntPtr.Zero,bytes,IntPtr.Zero);
        if(code != 0) throw new Win32Exception((int)code);
    }
}
'@ -ErrorAction Stop
    $info=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true
    foreach($argument in '-NoProfile','-NonInteractive','-Command',"[Console]::WriteLine('ready'); [Console]::In.ReadLineAsync().Wait(30000) | Out-Null; exit 259"){$info.ArgumentList.Add($argument)}
    $owned=[Diagnostics.Process]::Start($info)
    $originalAcl=$null
    try{
        $handshake=$owned.StandardOutput.ReadLineAsync()
        Require ($handshake.Wait(5000) -and $handshake.Result -eq 'ready') 'Owned no-UI process did not become responsive'
        $identity=Get-PtLifecycleProcessIdentity $owned
        Require ($identity.processId -eq $owned.Id -and $identity.processStartTicks -eq $owned.get_StartTime().ToUniversalTime().Ticks -and
            $identity.sessionId -eq $owned.get_SessionId() -and $identity.path -ieq $info.FileName) 'Native identity changed PID/start/path/session'
        $originalAcl=[PtLifecycleAclFixture]::Save($owned.SafeHandle)
        # Restrict only this disposable child. The already-owned handle can restore its DACL.
        [PtLifecycleAclFixture]::Apply($owned.SafeHandle,$originalAcl,0x100410)
        $fresh=[Diagnostics.Process]::GetProcessById($owned.Id)
        try{
            $legacy=CaptureFailure {$fresh.get_HasExited()}
            Require ($legacy.Exception.GetBaseException().NativeErrorCode -eq 5) 'Fixture did not reproduce archived HasExited access denial'
            $moduleFailure=CaptureFailure {$fresh.get_MainModule()}
            Require ($moduleFailure.Exception.GetBaseException().NativeErrorCode -eq 5) 'Fixture did not deny higher-rights module enumeration'
            $limited=Get-PtLifecycleProcessIdentity $fresh
            Require ((ConvertTo-Json $limited -Compress) -ceq (ConvertTo-Json $identity -Compress)) 'Limited-rights probe failed on the same live identity'
            [PtLifecycleAclFixture]::Apply($owned.SafeHandle,$originalAcl,0x101410)
            $denied=CaptureFailure {Get-PtLifecycleProcessIdentity $fresh -AllowExited -ExpectedPath $info.FileName}
            $detail=$denied.Exception.Data['LifecycleProcessObservation']
            Require ($detail.NativeErrorCode -eq 5 -and $detail.Stage -eq 'OpenProcess' -and $detail.processId -eq $owned.Id -and
                $denied.Exception.GetBaseException().NativeErrorCode -eq 5) 'Actual limited-query denial became exit or lost its cause'
            [pscustomobject]@{Identity=$identity;LegacyHasExitedError=$legacy.Exception.ToString();LegacyMainModuleError=$moduleFailure.Exception.ToString()
                LimitedIdentity=$limited;DeniedObservation=$detail;DeniedError=$denied.Exception.ToString()} |
                ConvertTo-Json -Depth 8|Set-Content "$Workspace\native-probe-evidence.json"
        }finally{$fresh.Dispose()}
        [PtLifecycleAclFixture]::Apply($owned.SafeHandle,$originalAcl,0)
        $owned.StandardInput.Close()
        Require ($owned.WaitForExit(5000) -and $owned.ExitCode -eq 259) 'Owned process did not exit with STILL_ACTIVE as its real exit code'
        Require ($null -eq (Get-PtLifecycleProcessIdentity $owned -AllowExited)) 'Exited child with code 259 appeared live'
        Reject {Get-PtLifecycleProcessIdentity $owned} 'already exited'
    }finally{
        try{
            if($originalAcl){[PtLifecycleAclFixture]::Apply($owned.SafeHandle,$originalAcl,0)}
        }finally{
            $owned.StandardInput.Close()
            try{if(-not $owned.WaitForExit(5000)){throw "Owned fixture PID $($owned.Id) failed to exit; its stdin deadline is 30 seconds."}}
            finally{$owned.Dispose()}
        }
    }
}
Check 'Restarts require Diagnostic context and cannot erase Normal failures' {
    Reject {Restart-PtModuleLifecycle -Snapshot @{} -Reason 'No recorded context'} 'active Diagnostic'
    $proof=Join-Path $Workspace 'proof.txt';[IO.File]::WriteAllText($proof,'Synthetic lifecycle evidence')
    $run=New-PtVerificationRun -Workspace "$Workspace\recording" -Module 'H06 synthetic contracts' -Bits 'No desktop or product transitions' `
        -Scenario InfrastructureAcceptance -Inputs @(
            @{Name='skill.txt';Role='Skill';Path=$proof},@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath},
            @{Name='lifecycle.ps1';Role='Helper';Path="$helpers\pt-module-lifecycle.ps1"}
        ) -Items @(@{Id='I1';Description='Normal failure is retained';Admin='NO';Clarity='CLEAR';UserVisible=$false
            Assertions=@(@{Id='value';Description='Actual Normal behavior'})})
    $normal=Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name normal -Activate
    Reject {Restart-PtModuleLifecycle -Snapshot @{} -Reason 'Wrong context'} 'active Diagnostic'
    Invoke-PtVerificationStep $normal -Name normal -Command 'Synthetic Normal failure evidence' -Action {'Observed mismatch'}|Out-Null
    $evidence=Add-PtVerificationArtifact $normal $proof Evidence 'Synthetic mismatch'
    Add-PtVerificationAssertion $normal value FAIL product 'Synthetic Normal mismatch' -Evidence @($evidence)
    Stop-PtVerificationAttempt $normal -Reason 'Recorded failure'
    $diagnostic=Start-PtVerificationAttempt $run -ItemId I1 -Kind Diagnostic -Name recovery -Activate
    $fixture=@{Enabled=$true;Runtime=$true;Toggles=0}
    function Get-PtModuleLifecycleState {param($Profile) State $fixture.Enabled $fixture.Runtime}
    function Get-PtLifecycleToggle {
        param($Snapshot)
        $pattern=[pscustomobject]@{Fixture=$fixture}
        $pattern|Add-Member ScriptMethod Toggle {
            $this.Fixture.Toggles++;$this.Fixture.Enabled=-not $this.Fixture.Enabled;$this.Fixture.Runtime=$this.Fixture.Enabled
        }
        [pscustomobject]@{Enabled=$fixture.Enabled;Pattern=$pattern;Control=$null}
    }
    $settings=[pscustomobject]@{hwnd=2;processId=3;processStartTicks=4;className='SyntheticSettings'}
    $snapshot=Get-PtModuleLifecycleSnapshot $profile $settings $Workspace
    $restart=Restart-PtModuleLifecycle $snapshot -Reason 'Explicit simulated recovery' -TimeoutSeconds 2
    Require ($restart.Kind -eq 'Diagnostic' -and -not $restart.RunnerRestarted -and $fixture.Toggles -eq 2) 'Restart escaped its explicit module scope'
    Stop-PtVerificationAttempt $diagnostic -Reason 'Recovery does not replace the Normal path'
    Require ((Get-PtReportState $run).Items[0].Verdict -eq 'FAIL') 'Diagnostic recovery erased Normal failure'
    $export=Complete-PtVerificationRun $run -NoFriction
    Require (Test-PtVerificationArchive $run.Workspace).Valid 'Lifecycle recorded source/arguments did not survive export'
}
"PASS: $($results.Count) offline lifecycle groups. $Workspace"
