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
Check 'Exited process getters fail explicitly instead of yielding null identities' {
    $info=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    foreach($argument in '-NoProfile','-Command','exit 0'){$info.ArgumentList.Add($argument)}
    $owned=[Diagnostics.Process]::Start($info)
    try{
        if(-not $owned.WaitForExit(5000)){throw 'Owned process did not exit'}
        Reject {Get-PtLifecycleProcessIdentity $owned} 'already exited'
    }finally{$owned.Dispose()}
}
Check 'Restarts require Diagnostic context and cannot erase Normal failures' {
    Reject {Restart-PtModuleLifecycle -Snapshot @{} -Reason 'No recorded context'} 'active Diagnostic'
    $proof=Join-Path $Workspace 'proof.txt';[IO.File]::WriteAllText($proof,'Synthetic lifecycle evidence')
    $run=New-PtVerificationRun -Workspace "$Workspace\recording" -Module 'H06 synthetic contracts' -Bits 'No desktop or product transitions' `
        -Scenario InfrastructureAcceptance -Inputs @(
            @{Name='skill.txt';Role='Skill';Path=$proof},@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath},
            @{Name='lifecycle.ps1';Role='Helper';Path="$helpers\pt-module-lifecycle.ps1"}
        ) -Items @(@{Id='I1';Description='Normal failure is retained';Admin='NO';Clarity='CLEAR';UserVisible=$false
            Assertions=@(@{Id='value';Description='Actual Normal behavior';Required=$true})})
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
