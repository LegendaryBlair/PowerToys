#requires -Version 7.2
<#
.SYNOPSIS
Profile-driven native module lifecycle and explicit UI enable/disable/restart.
.NOTES
No process killing, Runner restart, module activation, JSON settings writes or automatic recovery.
Ready means the declared native lifecycle contract, not rendered content or functional health.
#>
foreach($dependency in 'pt-ui-observation','pt-shared-events'){. "$PSScriptRoot\$dependency.ps1"}

if(-not ('PtLifecycleProcess' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
public static class PtLifecycleProcess {
    public sealed class Identity {
        public int processId;
        public long processStartTicks;
        public int sessionId;
        public string path;
    }
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern SafeProcessHandle OpenProcess(uint access, bool inherit, int processId);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetProcessTimes(SafeProcessHandle process, out long creation, out long exit, out long kernel, out long user);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool QueryFullProcessImageName(SafeProcessHandle process, uint flags, StringBuilder name, ref int size);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetExitCodeProcess(SafeProcessHandle process, out uint code);

    static Win32Exception Failure(int code, string stage, Identity identity) {
        var error=new Win32Exception(code, stage + " failed for lifecycle PID " + identity.processId + ": " + new Win32Exception(code).Message);
        error.Data["LifecycleProcessStage"]=stage;
        error.Data["LifecycleProcessIdentity"]=identity;
        return error;
    }
    static int? FindSession(int processId) {
        // Enumeration supplies session/liveness without opening a second, higher-rights handle.
        var all=Process.GetProcesses();
        try {
            foreach(var process in all) {
                if(process.Id == processId) return process.SessionId;
            }
            return null;
        } finally { foreach(var process in all) process.Dispose(); }
    }
    static bool Exited(SafeProcessHandle handle, Identity identity, string stage) {
        if(!GetExitCodeProcess(handle,out uint code)) throw Failure(Marshal.GetLastWin32Error(),stage,identity);
        // STILL_ACTIVE is also a legal exit code; a fresh process snapshot disambiguates it.
        return code != 259;
    }
    public static Identity Read(int processId) {
        if(processId <= 0) throw new ArgumentOutOfRangeException(nameof(processId));
        var identity=new Identity { processId=processId, sessionId=-1 };
        using(var handle=OpenProcess(0x1000,false,processId)) {
            if(handle.IsInvalid) {
                int code=Marshal.GetLastWin32Error();
                if(code == 87 && !FindSession(processId).HasValue) return null;
                throw Failure(code,"OpenProcess",identity);
            }
            // Keep one handle alive through every read: a recycled PID cannot mix identities.
            int? session=FindSession(processId);
            if(!session.HasValue || Exited(handle,identity,"GetExitCodeProcess.Before")) return null;
            identity.sessionId=session.Value;
            if(!GetProcessTimes(handle,out long created,out long exited,out long kernel,out long user))
                throw Failure(Marshal.GetLastWin32Error(),"GetProcessTimes",identity);
            identity.processStartTicks=DateTime.FromFileTimeUtc(created).Ticks;
            var path=new StringBuilder(32768);
            int length=path.Capacity;
            if(!QueryFullProcessImageName(handle,0,path,ref length)) {
                int code=Marshal.GetLastWin32Error();
                var original=Failure(code,"QueryFullProcessImageName",identity);
                // A terminating process can lose its image before the next name enumeration.
                if(code == 31) {
                    try {
                        if(Exited(handle,identity,"GetExitCodeProcess.AfterImageFailure") || !FindSession(processId).HasValue) return null;
                    } catch(Exception confirmation) {
                        original.Data["LifecycleExitConfirmationFailure"]=confirmation;
                    }
                }
                throw original;
            }
            identity.path=path.ToString();
            if(Exited(handle,identity,"GetExitCodeProcess.After") || !FindSession(processId).HasValue) return null;
            return identity;
        }
    }
}
'@ -ErrorAction Stop
}

function Assert-PtModuleLifecycleProfile {
    param([Parameter(Mandatory)]$Profile)
    $allowed=@('Id','ModuleKey','PageAutomationId','ToggleAutomationId','ToggleName','WithinAutomationId','Model','ProcessName','ProcessPath','WindowClass','Events','SettingsPath')
    $names=if($Profile -is [Collections.IDictionary]){@($Profile.Keys)}else{@($Profile.PSObject.Properties.Name)}
    if(@($names|Where-Object {$_ -cnotin $allowed}).Count){throw 'Unknown lifecycle profile field.'}
    if($Profile.Id -cnotmatch '^[a-z0-9][a-z0-9.-]{0,63}$' -or
        [string]::IsNullOrWhiteSpace($Profile.ModuleKey) -or [string]::IsNullOrWhiteSpace($Profile.PageAutomationId) -or
        $Profile.Model -cnotin 'Resident','RunnerHosted','OnDemand'){throw 'Profile requires Id, ModuleKey, PageAutomationId and an explicit lifecycle Model.'}
    if([bool]$Profile.ToggleAutomationId -eq [bool]$Profile.ToggleName){throw 'Supply exactly one toggle AutomationId or Name.'}
    if($Profile.Model -eq 'Resident' -and (-not $Profile.ProcessName -or -not $Profile.ProcessPath)){
        throw 'Resident modules require an exact process name and executable path.'
    }
    if($Profile.Model -eq 'RunnerHosted' -and ($Profile.ProcessName -or $Profile.ProcessPath -or -not $Profile.WindowClass)){
        throw 'RunnerHosted requires a module-owned window class, not an independent process.'
    }
    if([bool]$Profile.ProcessName -ne [bool]$Profile.ProcessPath){throw 'ProcessName and ProcessPath must be supplied together.'}
    if($Profile.ProcessName){
        if($Profile.ProcessName -match '[\\/:*?]' -or $Profile.ProcessName -in 'PowerToys','PowerToys.Settings' -or
            -not [IO.Path]::IsPathFullyQualified($Profile.ProcessPath) -or
            [IO.Path]::GetFileNameWithoutExtension($Profile.ProcessPath) -ine $Profile.ProcessName){
            throw 'Invalid module executable scope; Runner/Settings cannot be used as dedicated module processes.'
        }
    }
    if($Profile.SettingsPath -and -not [IO.Path]::IsPathFullyQualified($Profile.SettingsPath)){throw 'SettingsPath must be absolute.'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $catalog=Get-PtSharedEventMap
    foreach($rule in @($Profile.Events)){
        if(-not $rule){continue}
        $fields=if($rule -is [Collections.IDictionary]){@($rule.Keys)}else{@($rule.PSObject.Properties.Name)}
        if(@($fields|Where-Object {$_ -cnotin 'Name','WhenEnabled','WhenDisabled'}).Count -or
            -not $seen.Add($rule.Name) -or $rule.WhenEnabled -cnotin 'Present','Absent','Ignore' -or
            $rule.WhenDisabled -cnotin 'Present','Absent','Ignore'){
            throw 'Event rules require unique names and explicit Present/Absent/Ignore expectations for both states.'
        }
        if(-not $catalog.ContainsKey($rule.Name) -and $rule.Name -cnotmatch '^Local\\[^\\\x00]+$'){
            throw "Unknown lifecycle event name: $($rule.Name)"
        }
    }
}

function Get-PtLifecycleProcessIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Process,[switch]$AllowExited,[string]$ExpectedPath)
    try{$identity=Get-PtLifecycleProcessProbe -ProcessId $Process.Id}
    catch{
        $cause=$_.Exception
        $native=$cause.GetBaseException()
        if($native -isnot [ComponentModel.Win32Exception] -or -not $native.Data.Contains('LifecycleProcessStage')){throw}
        $observed=$native.Data['LifecycleProcessIdentity']
        $details=[pscustomobject]@{
            Status='ReadError';Stage=$native.Data['LifecycleProcessStage'];NativeErrorCode=$native.NativeErrorCode
            processId=$Process.Id;processStartTicks=$observed.processStartTicks
            sessionId=$Process.SessionId;path=$observed.path;ExpectedPath=$ExpectedPath
            ObservedSessionId=$observed.sessionId;RequestedAccess='PROCESS_QUERY_LIMITED_INFORMATION (0x1000)'
        }
        $error=[InvalidOperationException]::new("Lifecycle process observation failed: PID $($Process.Id), session $($Process.SessionId), stage $($details.Stage), native error $($details.NativeErrorCode); expected path '$ExpectedPath'.",$cause)
        $error.Data['LifecycleProcessObservation']=$details
        $record=[Management.Automation.ErrorRecord]::new($error,'PtLifecycleProcess.ReadError',[Management.Automation.ErrorCategory]::ReadError,$details)
        $PSCmdlet.ThrowTerminatingError($record)
    }
    if($null -eq $identity){
        if($AllowExited){return}
        throw [InvalidOperationException]::new("Process $($Process.Id) already exited during lifecycle observation.")
    }
    $identity
}

function Get-PtLifecycleProcessProbe {
    param([Parameter(Mandatory)][int]$ProcessId)
    [PtLifecycleProcess]::Read($ProcessId)
}

function Get-PtLifecycleProcessCandidates {
    param([Parameter(Mandatory)][string]$Name)
    $all=[Diagnostics.Process]::GetProcessesByName($Name)
    try{
        foreach($process in $all){
            [pscustomobject]@{Id=$process.Id;SessionId=$process.get_SessionId()}
        }
    }finally{foreach($process in $all){$process.Dispose()}}
}

function Get-PtLifecycleRunner {
    $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
    $runners=@(foreach($candidate in @(Get-PtLifecycleProcessCandidates 'PowerToys')){
        if($candidate.SessionId -ne $session){continue}
        $identity=Get-PtLifecycleProcessIdentity $candidate -AllowExited
        if($identity -and $identity.sessionId -eq $session -and [IO.Path]::GetFileNameWithoutExtension($identity.path) -ieq 'PowerToys'){$identity}
    })
    if($runners.Count -ne 1){throw 'Exactly one Runner in the current session is required; no Runner will be started or replaced automatically.'}
    $runners[0]
}

function Get-PtLifecycleProcesses {
    param($Profile,[int]$SessionId)
    if(-not $Profile.ProcessName){return}
    $matches=@(foreach($candidate in @(Get-PtLifecycleProcessCandidates $Profile.ProcessName)){
        if($candidate.SessionId -ne $SessionId){continue}
        $identity=Get-PtLifecycleProcessIdentity $candidate -AllowExited -ExpectedPath $Profile.ProcessPath
        if($identity -and $identity.sessionId -eq $SessionId -and $identity.path -ieq $Profile.ProcessPath){$identity}
    })
    $matches
}

function Get-PtLifecycleConfiguredEnabled {
    param($Profile)
    $path=if($Profile.SettingsPath){$Profile.SettingsPath}else{Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\settings.json'}
    $settings=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($path))
    if($Profile.ModuleKey -cnotin @($settings.enabled.PSObject.Properties.Name) -or $settings.enabled.($Profile.ModuleKey) -isnot [bool]){
        throw "Missing/non-Boolean enabled.$($Profile.ModuleKey); absence is not disabled."
    }
    $settings.enabled.($Profile.ModuleKey)
}

function ConvertTo-PtModuleLifecycleState {
    param($Profile,[bool]$Enabled,$Runner,[object[]]$Processes,[object[]]$Windows,[object[]]$Events,[object[]]$VisibleWindows=@())
    $issues=[Collections.Generic.List[string]]::new()
    $ambiguous=$Processes.Count -gt 1 -or $Windows.Count -gt 1
    if($ambiguous){$issues.Add('Multiple matching native instances; ownership is ambiguous.')}
    foreach($event in $Events){
        $expected=if($Enabled){$event.WhenEnabled}else{$event.WhenDisabled}
        if(($expected -eq 'Present' -and -not $event.Exists) -or ($expected -eq 'Absent' -and $event.Exists)){
            $issues.Add("Event '$($event.Name)' expected $expected; observed Exists=$($event.Exists).")
        }
    }
    if($Profile.Model -eq 'Resident'){
        if($Enabled -and $Processes.Count -ne 1){$issues.Add('Enabled resident process is not present.')}
        if(-not $Enabled -and $Processes.Count){$issues.Add('Disabled resident process has not exited.')}
    }
    if($Profile.Model -ne 'OnDemand' -and $Profile.WindowClass){
        if($Enabled -and $Windows.Count -ne 1){$issues.Add('Enabled native host is not ready.')}
        if(-not $Enabled -and $Windows.Count){$issues.Add('Disabled native host has not disappeared.')}
    }
    $status=if($ambiguous){'Ambiguous'}elseif($issues.Count){'TransitioningOrUnavailable'}
        elseif($Profile.Model -eq 'OnDemand'){if($Enabled){'ConfiguredEnabled'}else{'ConfiguredDisabled'}}
        elseif($Enabled){'Ready'}else{'Disabled'}
    [pscustomobject]@{
        ProfileId=$Profile.Id;ModuleKey=$Profile.ModuleKey;Model=$Profile.Model;ConfiguredEnabled=$Enabled
        Status=$status;SatisfiesNativeContract=($issues.Count -eq 0);RuntimeReady=($status -eq 'Ready')
        Scope=$(if($Profile.Model -eq 'OnDemand'){'ConfigurationOnly'}else{'DeclaredNativeLifecycleOnly'})
        Runner=$Runner;Processes=@($Processes);Windows=@($Windows);VisibleWindows=@($VisibleWindows);Events=@($Events);Issues=$issues.ToArray()
        CapturedAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
    }
}

function Get-PtModuleLifecycleState {
    <# .SYNOPSIS
    Observe configured state, exact process/host identities and explicitly scoped event expectations.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile)
    Assert-PtModuleLifecycleProfile $Profile
    $runner=Get-PtLifecycleRunner
    $enabled=Get-PtLifecycleConfiguredEnabled $Profile
    $processes=@(Get-PtLifecycleProcesses $Profile $runner.sessionId)
    $owners=if($Profile.Model -eq 'RunnerHosted'){@($runner)}else{$processes}
    $observedWindows=@(
        foreach($owner in $owners){
            foreach($window in @(Get-PtNativeWindow -ProcessId $owner.processId)){
                if($Profile.Model -eq 'RunnerHosted' -and $window.ClassName -cne $Profile.WindowClass){continue}
                try{
                    [pscustomobject]@{identity=Get-PtWindowIdentity $window.Hwnd;visible=$window.Visible;minimized=$window.Minimized}
                }catch [ComponentModel.Win32Exception] {
                    if($_.Exception.GetBaseException().NativeErrorCode -ne 1400){throw}
                }
            }
        }
    )
    $windows=@($observedWindows|Where-Object {$Profile.WindowClass -and $_.identity.className -ceq $Profile.WindowClass})
    $visible=@($observedWindows|Where-Object visible)
    $events=@(foreach($rule in @($Profile.Events)){
        if($rule){[pscustomobject]@{Name=$rule.Name;Exists=Test-PtSharedEvent $rule.Name;WhenEnabled=$rule.WhenEnabled;WhenDisabled=$rule.WhenDisabled}}
    })
    $runnerAfter=Get-PtLifecycleRunner
    if((ConvertTo-Json $runnerAfter -Compress) -cne (ConvertTo-Json $runner -Compress)){throw 'Runner changed during lifecycle observation.'}
    ConvertTo-PtModuleLifecycleState $Profile $enabled $runner $processes $windows $events $visible
}

function Get-PtLifecycleToggle {
    param($Snapshot)
    Initialize-PtUiAutomation
    Assert-PtWindowIdentity $Snapshot.SettingsTarget
    $native=Get-PtNativeWindow -Hwnd $Snapshot.SettingsTarget.hwnd
    if(-not $native.Visible -or $native.Minimized){throw 'Settings must be explicitly visible and not minimized before lifecycle operations.'}
    $page=Resolve-PtUiElement -Hwnd $Snapshot.SettingsTarget.hwnd -AutomationId $Snapshot.Profile.PageAutomationId -ControlType ListItem
    if(-not $page.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected){throw 'The lifecycle profile Settings page is not selected.'}
    $selector=if($Snapshot.Profile.ToggleAutomationId){@{AutomationId=$Snapshot.Profile.ToggleAutomationId}}else{@{Name=$Snapshot.Profile.ToggleName}}
    $control=Resolve-PtUiElement -Hwnd $Snapshot.SettingsTarget.hwnd @selector -ControlType Button -WithinAutomationId $Snapshot.Profile.WithinAutomationId
    if(-not $control.Current.IsEnabled -or $control.Current.IsOffscreen){throw 'Module toggle is disabled, policy-controlled or offscreen; no transition was attempted.'}
    $pattern=$null
    if(-not $control.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern,[ref]$pattern)){throw 'The selected control does not expose TogglePattern.'}
    $state=$pattern.get_Current().get_ToggleState()
    if($state -notin [Windows.Automation.ToggleState]::On,[Windows.Automation.ToggleState]::Off){throw 'Indeterminate/invalid module toggle state is not a Boolean enable value.'}
    [pscustomobject]@{Control=$control;Pattern=$pattern;Enabled=($state -eq [Windows.Automation.ToggleState]::On)}
}

function Assert-PtLifecycleSnapshot {
    param($Snapshot)
    if($Snapshot.Schema -cne 'PtModuleLifecycle.v1' -or
        [IO.Path]::GetFileName($Snapshot.ReceiptPath) -cnotmatch '^lifecycle-[a-f0-9]{32}\.json$' -or
        [IO.Path]::GetDirectoryName($Snapshot.ReceiptPath) -ine $Snapshot.Workspace){throw 'Invalid lifecycle ownership receipt.'}
    Assert-PtReportNoLink $Snapshot.ReceiptPath
    $saved=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($Snapshot.ReceiptPath))
    foreach($field in 'Profile','SettingsTarget','Runner','OriginalState'){
        if((ConvertTo-Json $saved.$field -Depth 20 -Compress) -cne (ConvertTo-Json $Snapshot.$field -Depth 20 -Compress)){throw "Lifecycle baseline field changed: $field"}
    }
    if($Snapshot.OriginalEnabled -isnot [bool] -or $Snapshot.ExpectedEnabled -isnot [bool] -or
        $Snapshot.OriginalEnabled -ne $saved.OriginalEnabled){throw 'Original lifecycle enable state is not intact.'}
    if($null -ne $Snapshot.PendingEnabled -and $Snapshot.PendingEnabled -isnot [bool]){throw 'Pending enable state must be Boolean or null.'}
}

function Save-PtLifecycleSnapshot {
    param($Snapshot)
    Assert-PtLifecycleSnapshot $Snapshot
    $temporary=Join-Path $Snapshot.Workspace "lifecycle-write-$([Guid]::NewGuid().ToString('N')).tmp"
    try{
        Write-PtReportText $temporary (ConvertTo-Json $Snapshot -Depth 20)
        [IO.File]::Move($temporary,$Snapshot.ReceiptPath,$true)
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Get-PtModuleLifecycleSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile,[Parameter(Mandatory)]$SettingsTarget,[Parameter(Mandatory)][string]$Workspace)
    Assert-PtModuleLifecycleProfile $Profile
    $directory=(Get-Item -LiteralPath $Workspace -ErrorAction Stop).FullName
    if(-not [IO.Directory]::Exists($directory)){throw 'Lifecycle receipts require an existing directory.'}
    Assert-PtReportNoLink $directory
    $profileCopy=ConvertFrom-PtReportJson (ConvertTo-Json $Profile -Depth 10)
    $state=Get-PtModuleLifecycleState $profileCopy
    if($state.Status -eq 'Ambiguous'){throw 'Cannot snapshot ambiguous module ownership.'}
    $snapshot=[pscustomobject]@{
        Schema='PtModuleLifecycle.v1';Workspace=$directory;Profile=$profileCopy;SettingsTarget=$SettingsTarget
        Runner=$state.Runner;OriginalEnabled=$state.ConfiguredEnabled;ExpectedEnabled=$state.ConfiguredEnabled
        PendingEnabled=$null;OriginalState=$state
        ReceiptPath=Join-Path $directory "lifecycle-$([Guid]::NewGuid().ToString('N')).json"
    }
    $toggle=Get-PtLifecycleToggle $snapshot
    if($toggle.Enabled -ne $state.ConfiguredEnabled){throw 'UI toggle and persisted enable value disagree; do not override policy or stale settings.'}
    Write-PtReportText $snapshot.ReceiptPath (ConvertTo-Json $snapshot -Depth 20)
    $snapshot
}

function Wait-PtModuleLifecycle {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile,[Parameter(Mandatory)][bool]$Enabled,
        [ValidateRange(0.1,60)][double]$TimeoutSeconds=10,$ExpectedRunner)
    $poll=@{Last=$null;Signature=$null;Stable=0}
    try{
        Wait-PtCondition -Description "module '$($Profile.Id)' configured=$Enabled and declared native lifecycle" -TimeoutSeconds $TimeoutSeconds -Probe {
            $last=Get-PtModuleLifecycleState $Profile
            $poll.Last=$last
            if($ExpectedRunner -and (ConvertTo-Json $last.Runner -Compress) -cne (ConvertTo-Json $ExpectedRunner -Compress)){
                throw 'Runner identity changed; module-local lifecycle observation cannot continue.'
            }
            if($last.Status -eq 'Ambiguous'){throw 'Ambiguous native module instances; no instance is selected automatically.'}
            if($last.ConfiguredEnabled -eq $Enabled -and $last.SatisfiesNativeContract){
                $signature=ConvertTo-Json -InputObject @($last.Processes,$last.Windows) -Depth 12 -Compress
                if($signature -ceq $poll.Signature){$poll.Stable++}else{$poll.Stable=1;$poll.Signature=$signature}
                if($poll.Stable -ge 2){return $last}
            }else{$poll.Stable=0;$poll.Signature=$null}
        }
    }catch{
        $_.Exception.Data['LifecycleLastObservation']=$poll.Last
        throw
    }
}

function Set-PtModuleEnabled {
    <#
    .SYNOPSIS
    Explicitly change only the target module toggle and wait for the declared native outcome.
    .NOTES
    Matching configuration is not permission to restart an unhealthy runtime. Visible module
    windows must be closed through an explicitly owned user flow before lifecycle changes.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][bool]$Enabled,
        [ValidateRange(0.1,60)][double]$TimeoutSeconds=10)
    Assert-PtLifecycleSnapshot $Snapshot
    $body={
        param($snapshot,$requested,$timeout)
        $before=Get-PtModuleLifecycleState $snapshot.Profile
        if((ConvertTo-Json $before.Runner -Compress) -cne (ConvertTo-Json $snapshot.Runner -Compress)){throw 'Runner changed since the lifecycle snapshot.'}
        if($before.Status -eq 'Ambiguous'){throw 'Ambiguous module state; transition refused.'}
        if($before.ConfiguredEnabled -ne $snapshot.ExpectedEnabled -and
            ($null -eq $snapshot.PendingEnabled -or $before.ConfiguredEnabled -ne $snapshot.PendingEnabled)){
            throw 'Module enable state changed outside the recorded transition.'
        }
        $toggle=Get-PtLifecycleToggle $snapshot
        if($toggle.Enabled -ne $before.ConfiguredEnabled){throw 'UI/configuration mismatch before module transition.'}
        $changed=$toggle.Enabled -ne $requested
        if($changed){
            if(@($before.VisibleWindows).Count){throw 'Module has visible UI; close an explicitly owned surface before changing its lifecycle.'}
            $snapshot.PendingEnabled=$requested
            Save-PtLifecycleSnapshot $snapshot
            $toggle.Pattern.Toggle()
        }
        $after=Wait-PtModuleLifecycle $snapshot.Profile $requested -TimeoutSeconds $timeout -ExpectedRunner $snapshot.Runner
        if((Get-PtLifecycleToggle $snapshot).Enabled -ne $requested){throw 'UI toggle did not converge to the requested enable state.'}
        $snapshot.ExpectedEnabled=$requested;$snapshot.PendingEnabled=$null
        Save-PtLifecycleSnapshot $snapshot
        [pscustomobject]@{RequestedEnabled=$requested;Changed=$changed;Before=$before;After=$after
            InvalidatePriorReferences=$changed;ReceiptPath=$snapshot.ReceiptPath}
    }
    $attempt=Get-PtActiveVerificationAttempt
    if($attempt){
        $json=(ConvertTo-Json $Snapshot -Depth 20 -Compress).Replace("'","''")
        Invoke-PtVerificationStep $attempt -Name 'Set explicit module enable state' `
            -Command "Set-PtModuleEnabled -Snapshot (ConvertFrom-PtReportJson '$json') -Enabled `$$($Enabled.ToString().ToLowerInvariant()) -TimeoutSeconds $TimeoutSeconds" `
            -Implementation ${function:Set-PtModuleEnabled} -Action $body -ArgumentList @($Snapshot,$Enabled,$TimeoutSeconds)
    }else{& $body $Snapshot $Enabled $TimeoutSeconds}
}

function Restart-PtModuleLifecycle {
    <# .SYNOPSIS
    Explicit diagnostic disable/enable cycle. Never restarts Runner or rescues a Normal failure.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
        [ValidateRange(0.1,60)][double]$TimeoutSeconds=10)
    $attempt=Get-PtActiveVerificationAttempt
    if(-not $attempt -or $attempt.Kind -ne 'Diagnostic'){throw 'Module restart requires an active Diagnostic attempt and an explicit reason.'}
    if([string]::IsNullOrWhiteSpace($Reason)){throw 'Diagnostic restart requires a meaningful reason.'}
    Assert-PtLifecycleSnapshot $Snapshot
    if($Snapshot.Profile.Model -eq 'OnDemand'){throw 'OnDemand configuration has no module-runtime restart contract.'}
    $before=Get-PtModuleLifecycleState $Snapshot.Profile
    if(-not $before.ConfiguredEnabled){throw 'Cannot restart a disabled module; enable it explicitly first.'}
    $snapshotText=(ConvertTo-Json $Snapshot -Depth 20 -Compress).Replace("'","''")
    Invoke-PtVerificationStep $attempt -Name 'Explicit diagnostic module restart' `
        -Command "Restart-PtModuleLifecycle -Snapshot (ConvertFrom-PtReportJson '$snapshotText') -Reason '$($Reason.Replace("'","''"))' -TimeoutSeconds $TimeoutSeconds" `
        -Implementation ${function:Restart-PtModuleLifecycle} -ArgumentList @($Snapshot,$TimeoutSeconds,$Reason) -Action {
            param($snapshot,$timeout,$why)
            $off=Set-PtModuleEnabled $snapshot $false -TimeoutSeconds $timeout
            $on=Set-PtModuleEnabled $snapshot $true -TimeoutSeconds $timeout
            [pscustomobject]@{Kind='Diagnostic';Reason=$why;Disabled=$off.After;After=$on.After
                InvalidatePriorReferences=$true;RunnerRestarted=$false;ReceiptPath=$snapshot.ReceiptPath}
        }
}

function Restore-PtModuleLifecycleSnapshot {
    <# .SYNOPSIS
    Restore the original configured enable state, observing the current runtime rather than old PIDs.
    #>
    [CmdletBinding(DefaultParameterSetName='Snapshot')]
    param([Parameter(Mandatory,Position=0,ParameterSetName='Snapshot')]$Snapshot,
        [Parameter(Mandatory,ParameterSetName='Receipt')][string]$ReceiptPath,
        [ValidateRange(0.1,60)][double]$TimeoutSeconds=10)
    if($PSCmdlet.ParameterSetName -eq 'Receipt'){
        Assert-PtReportNoLink $ReceiptPath
        $Snapshot=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($ReceiptPath))
        if([IO.Path]::GetFullPath($ReceiptPath) -ine $Snapshot.ReceiptPath){throw 'Receipt path does not match its recorded ownership.'}
    }
    Assert-PtLifecycleSnapshot $Snapshot
    $current=Get-PtModuleLifecycleState $Snapshot.Profile
    if($current.ConfiguredEnabled -eq $Snapshot.OriginalEnabled){$Snapshot.ExpectedEnabled=$current.ConfiguredEnabled}
    Set-PtModuleEnabled $Snapshot $Snapshot.OriginalEnabled -TimeoutSeconds $TimeoutSeconds
}
