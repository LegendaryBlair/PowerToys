# scripts/pt-state.ps1
# Common state-verification helpers: settings.json diff, runner log grep, GPO log check,
# process spawn detection, AppX probe.
. "$PSScriptRoot\pt-file-io.ps1"
. "$PSScriptRoot\pt-verification-report.ps1"
. "$PSScriptRoot\pt-runner-ui.ps1"

function Get-PtSettings {
    <#
    .SYNOPSIS
    Read the master PT settings.json (enabled.<Module> flags + run_elevated + theme + language).
    #>
    $f = "$env:LOCALAPPDATA\Microsoft\PowerToys\settings.json"
    if (-not (Test-Path $f)) { return $null }
    ConvertFrom-PtReportJson (Read-PtSharedFileText -Path $f)
}

function Get-PtModuleSettings {
    <#
    .SYNOPSIS
    Read a single module's settings.json (e.g. AdvancedPaste, FancyZones, etc.).
    These ARE auto-reloaded by the per-module file watcher (~3s debounce).
    #>
    param([Parameter(Mandatory)][string]$ModuleDir)
    $f = "$env:LOCALAPPDATA\Microsoft\PowerToys\$ModuleDir\settings.json"
    if (-not (Test-Path $f)) { return $null }
    ConvertFrom-PtReportJson (Read-PtSharedFileText -Path $f)
}

function Get-CmdPalSettings {
    <#
    .SYNOPSIS
    Read CmdPal AppX settings.json (sandboxed path). Contains 19 ProviderSettings, DockSettings,
    GalleryFeedUrl, EscapeKeyBehaviorSetting, AutoGoHomeInterval, Hotkey, Aliases, etc.
    #>
    $f = "$env:LOCALAPPDATA\Packages\Microsoft.CommandPalette_8wekyb3d8bbwe\LocalState\settings.json"
    if (-not (Test-Path $f)) { return $null }
    ConvertFrom-PtReportJson (Read-PtSharedFileText -Path $f)
}

function Get-PtRunnerLogTail {
    <#
    .SYNOPSIS
    Tail the latest runner-log_<date>.log file for matching lines.
    .EXAMPLE
    Get-PtRunnerLogTail -Pattern 'hotkey is invoked' -TailLines 100
    Get-PtRunnerLogTail -Pattern 'GPO sets' -TailLines 50
    #>
    param([string]$Pattern = '.*', [int]$TailLines = 50)
    $log = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\PowerToys\RunnerLogs" -Filter 'runner-log_*.log' -EA SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $log) { return @() }
    Get-Content $log.FullName -Tail $TailLines -EA SilentlyContinue | Where-Object { $_ -match $Pattern }
}

function Test-PtModuleEnabled {
    <#
    .SYNOPSIS
    Check whether a specific module is enabled in master settings.json.
    Note: PT Run uses the key "PowerToys Run" (with space).
    #>
    param([Parameter(Mandatory)][string]$ModuleKey)
    $s = Get-PtSettings
    if (-not $s) { return $false }
    return [bool]$s.enabled.$ModuleKey
}

function Test-PtModuleProcess {
    <#
    .SYNOPSIS
    Return the process(es) for a module exe name (e.g. 'PowerToys.AdvancedPaste').
    Returns empty array if not running.
    #>
    param([Parameter(Mandatory)][string]$ExeName)
    @(Get-Process $ExeName -EA SilentlyContinue)
}

function Get-PtRunnerRestartState {
    param()
    $runner=Get-PtLifecycleRunner
    $elevated=Test-ProcessElevated -ProcessId $runner.processId
    if($elevated -isnot [bool]){throw 'Cannot establish Runner elevation before restart.'}
    $root=[IO.Path]::GetDirectoryName($runner.path).TrimEnd('\')+'\'
    $processes=@($runner)+@(foreach($process in @(Get-Process|Where-Object {
        $_.ProcessName -like 'PowerToys.*' -and $_.SessionId -eq $runner.sessionId
    })){
        $identity=Get-PtLifecycleProcessIdentity $process -AllowExited
        if($identity -and $identity.path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){$identity}
    })
    $hosts=@(Get-PtNativeWindow -ProcessId $runner.processId -ClassName 'PToyTrayIconWindow')
    if($hosts.Count -ne 1){throw 'Exactly one native Runner tray host is required before restart.'}
    $children=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($runner.processId)" -ErrorAction Stop |
        Select-Object -ExpandProperty ProcessId)
    [pscustomobject]@{
        Runner=$runner;Elevated=$elevated;Host=Get-PtWindowIdentity $hosts[0].Hwnd
        ImageHash=(Get-FileHash -LiteralPath $runner.path -Algorithm SHA256 -ErrorAction Stop).Hash
        Processes=$processes
        ChildProcesses=@($processes|Where-Object processId -In $children)
        VisibleWindows=@(foreach($identity in $processes){
            foreach($window in @(Get-PtNativeWindow -ProcessId $identity.processId -Visible)){
                if(-not (Test-PtWindowCloaked -Hwnd $window.Hwnd)){
                    Get-PtWindowIdentity $window.Hwnd
                }
            }
        })
    }
}

function Assert-PtRunnerRestartIdentity {
    param([Parameter(Mandatory)]$Expected)
    $actual=Get-PtLifecycleProcessProbe -ProcessId $Expected.processId
    if(-not $actual -or $actual.processStartTicks -ne $Expected.processStartTicks -or
        $actual.path -ine $Expected.path -or $actual.sessionId -ne $Expected.sessionId){
        throw 'Runner restart target exited or changed identity; no restart action was sent.'
    }
}

function Assert-PtRunnerRestartResources {
    param([Parameter(Mandatory)]$State)
    Assert-PtProcessRelease -ProcessId @($State.Processes.processId)
    $session=Get-PtActiveResourceSession
    if(-not $session){return}
    Assert-PtResourceSession $session
    $affected=@($State.Processes.processId)
    foreach($record in @($session.Windows|Where-Object {
        $_.Ownership -eq 'Borrowed' -and ($_.Identity.processId -in $affected -or $_.ReplacementIdentity.processId -in $affected)
    })){
        if(-not $record.AllowRunnerRestart -and -not @($session.Settings|Where-Object {
            $_.Identity.hwnd -eq $record.Identity.hwnd -and $_.AllowRunnerRestart
        }).Count){
            throw "Restart would invalidate borrowed window $($record.Identity.hwnd)'s same-instance restoration contract. Declare supported logical-state preservation before the run; do not rewrite its baseline."
        }
    }
    if(@($session.Settings|Where-Object {
        ($_.Identity.processId -in $affected -or $_.ReplacementIdentity.processId -in $affected) -and -not $_.AllowRunnerRestart
    }).Count){
        throw 'Restart requires an originally restartable Settings resource, not a same-instance restoration promise.'
    }
    $baseline=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($session.BaselinePath))
    $processScopes=@($baseline.ProcessScopes)+@(foreach($reference in @($session.AdditionalProcessScopes)){
        if($reference){Get-PtAdditionalProcessScope -Session $session -Reference $reference}
    })
    if(@($processScopes.Identities|Where-Object {$_.processId -in $affected}).Count){
        throw 'Restart conflicts with a declared pre-existing process identity that must survive. Use an explicit logical lifecycle resource instead of a same-instance process scope.'
    }
}

function Send-PtRunnerExit {
    param([Parameter(Mandatory)]$State,[string]$OverflowButtonName='Show Hidden Icons')
    Invoke-PtRunnerTrayCommand -State $State -Command Exit -OverflowButtonName $OverflowButtonName
}

function Start-PtRunnerAfterExit {
    param([Parameter(Mandatory)]$State)
    if(-not $State.LaunchTarget){throw 'No attested Windows Shell launch target was prepared before exit.'}
    Invoke-PtRunnerShellLaunch -Target $State.LaunchTarget
}

function Restart-PtRunner {
    <#
    .SYNOPSIS
    Explicitly restart PowerToys through its Runner, not Windows or an isolated module.
    .DESCRIPTION
    Discover the actual current-session installation, prepare affected state, request normal
    shutdown and relaunch once, or observe one supplied product UI restart action. Preserve
    errors and return fresh identities, never force-kill or silently retry the action.
    .PARAMETER Prepare
    Required preparation callback. Receives the read-only Before state and ArgumentList.
    Preserve affected settings, resolve actual draft/clipboard concerns and return exactly
    Boolean true. Existing module processes alone are not a reason to skip restart.
    .PARAMETER VerifyReady
    Required read-only callback receiving the new Runner identity and ArgumentList. Return
    exactly Boolean true when the case's Settings/module readiness contract is satisfied.
    False is polled; exceptions and non-Boolean output are errors, not success.
    .PARAMETER RestartAction
    Optional real UI restart action receiving Before and ArgumentList. It must perform the
    complete product restart; the helper never substitutes its own exit/launch on failure.
    .PARAMETER Launch
    Optional normal launch adapter receiving Before and ArgumentList, used only after normal
    exit. Supply this when caller/Runner tokens differ; preserve the attested installation
    and token. The default never launches from a mismatched caller token.
    .NOTES
    This operation is not restoration of files, drafts or borrowed HWNDs. Run it inside an
    existing recorded step and pair its preparation with verified logical-state cleanup.
    UI-under-test routes must use RestartAction; manual restart cannot certify their behavior.
    #>
    [CmdletBinding()]
    param(
        [scriptblock]$Prepare,
        [scriptblock]$VerifyReady,
        [scriptblock]$RestartAction,
        [scriptblock]$Launch,
        [ValidateNotNullOrEmpty()][string]$OverflowButtonName='Show Hidden Icons',
        [object[]]$ArgumentList=@(),
        [ValidateSet('Preserve','Elevated','NonElevated')][string]$ExpectedElevation='Preserve',
        [ValidateRange(0.1,300)][double]$TimeoutSeconds=30
    )
    foreach($dependency in @(
        @{Name='Get-PtLifecycleRunner';File='pt-module-lifecycle'},
        @{Name='Test-ProcessElevated';File='pt-admin-probe'},
        @{Name='Get-PtActiveResourceSession';File='pt-session-safety'})){
        if(-not (Get-Command $dependency.Name -ErrorAction Ignore)){. "$PSScriptRoot\$($dependency.File).ps1"}
    }
    if(-not $Prepare -or -not $VerifyReady){
        throw 'Restart-PtRunner requires explicit Prepare and VerifyReady callbacks; the old unguarded force-kill route is no longer supported.'
    }
    if($RestartAction -and $Launch){throw 'RestartAction and Launch are mutually exclusive.'}
    if(-not $RestartAction -and $ExpectedElevation -ne 'Preserve'){
        throw 'An elevation transition requires the explicit product RestartAction, not a generic relaunch.'
    }
    $before=Get-PtRunnerRestartState
    $expected=if($ExpectedElevation -eq 'Preserve'){$before.Elevated}else{$ExpectedElevation -eq 'Elevated'}
    $receipt=[pscustomobject]@{
        Scope='PowerToys';Route=$(if($RestartAction){'ProductAction'}else{'TrayExitAndShellLaunch'})
        Before=$before;After=$null;ExpectedElevated=$expected
        Phase='Preparation';ActionIssued=$false;ExitResult=$null;LaunchIssued=$false;LaunchResult=$null
        InvalidatePriorReferences=$false;Ready=$false
    }
    try{
        if(-not $RestartAction -and -not $Launch){
            $caller=Test-ProcessElevated -ProcessId $PID
            if($caller -isnot [bool] -or $caller -ne $before.Elevated){
                throw 'Caller and Runner elevation differ. Supply a verified same-user Launch adapter or the real product RestartAction; no process was stopped.'
            }
            $before|Add-Member NoteProperty LaunchTarget (Get-PtRunnerShellLaunchTarget $before)
        }
        $prepared=@(& $Prepare (ConvertFrom-PtReportJson (ConvertTo-Json $before -Depth 15)) @ArgumentList)
        if($prepared.Count -ne 1 -or $prepared[0] -isnot [bool] -or -not $prepared[0]){
            throw 'Restart preparation must return exactly Boolean true after preserving/resolving the affected state.'
        }
        $current=Get-PtRunnerRestartState
        Assert-PtRunnerRestartIdentity $before.Runner
        if($current.ImageHash -cne $before.ImageHash -or $current.Elevated -ne $before.Elevated){
            throw 'Runner image or elevation changed during preparation.'
        }
        foreach($window in $current.VisibleWindows){
            if(-not @($before.VisibleWindows|Where-Object {
                $_.hwnd -eq $window.hwnd -and $_.processId -eq $window.processId -and
                $_.processStartTicks -eq $window.processStartTicks -and $_.className -ceq $window.className
            }).Count){throw 'A new affected visible window appeared during preparation; review it before issuing another explicit restart.'}
        }
        Assert-PtRunnerRestartResources $current
        $session=Get-PtActiveResourceSession
        if($session){
            foreach($record in @($session.Windows|Where-Object {
                $_.AllowRunnerRestart -and
                ($_.Identity.processId -in $current.Processes.processId -or $_.ReplacementIdentity.processId -in $current.Processes.processId)
            })){
                $record.RestartAuthorization=[pscustomobject]@{Runner=$before.Runner;StartedTicks=[DateTime]::UtcNow.Ticks}
            }
            foreach($record in @($session.Settings|Where-Object {
                $_.AllowRunnerRestart -and
                ($_.Identity.processId -in $current.Processes.processId -or $_.ReplacementIdentity.processId -in $current.Processes.processId)
            })){
                $record.RestartAuthorization=[pscustomobject]@{Runner=$before.Runner;StartedTicks=[DateTime]::UtcNow.Ticks}
                $record.Restored=$false
            }
            Save-PtResourceSession $session
        }
        $receipt.Phase='Request';$receipt.ActionIssued=$true;$receipt.InvalidatePriorReferences=$true
        if($RestartAction){& $RestartAction (ConvertFrom-PtReportJson (ConvertTo-Json $current -Depth 15)) @ArgumentList|Out-Null}
        else{$receipt.ExitResult=Send-PtRunnerExit -State $current -OverflowButtonName $OverflowButtonName}
        $receipt.Phase='Exit'
        Wait-PtCondition -Description 'the recorded Runner instance to exit' -TimeoutSeconds $TimeoutSeconds -Probe {
            $actual=Get-PtLifecycleProcessProbe -ProcessId $before.Runner.processId
            -not $actual -or $actual.processStartTicks -ne $before.Runner.processStartTicks
        }|Out-Null
        if(-not $RestartAction){
            Wait-PtCondition -Description 'the original direct Runner children to finish their production shutdown' `
                -TimeoutSeconds $TimeoutSeconds -Probe {
                    foreach($child in $before.ChildProcesses){
                        $actual=Get-PtLifecycleProcessProbe -ProcessId $child.processId
                        if($actual -and $actual.processStartTicks -eq $child.processStartTicks){return $false}
                    }
                    $true
                }|Out-Null
            $receipt.Phase='Launch'
            $existing=@(Get-PtLifecycleProcessCandidates 'PowerToys'|Where-Object SessionId -EQ $before.Runner.sessionId)
            if($existing.Count){throw 'A Runner already appeared after exit; refusing a duplicate launch.'}
            if((Get-FileHash -LiteralPath $before.Runner.path -Algorithm SHA256 -ErrorAction Stop).Hash -cne $before.ImageHash){
                throw 'Installed Runner image changed before relaunch.'
            }
            $receipt.LaunchIssued=$true
            if($Launch){& $Launch (ConvertFrom-PtReportJson (ConvertTo-Json $before -Depth 15)) @ArgumentList|Out-Null}
            else{$receipt.LaunchResult=Start-PtRunnerAfterExit $before}
        }
        $receipt.Phase='Readiness'
        $settled=@{Key=$null;Count=0}
        $after=Wait-PtCondition -Description 'a new same-installation Runner and the declared readiness contract' `
            -TimeoutSeconds $TimeoutSeconds -Probe {
                $candidates=@(foreach($candidate in @(Get-PtLifecycleProcessCandidates 'PowerToys')){
                    if($candidate.SessionId -eq $before.Runner.sessionId){
                        Get-PtLifecycleProcessIdentity $candidate -AllowExited
                    }
                })
                if($candidates.Count -gt 1){throw 'Ambiguous current-session Runner instances after restart.'}
                if(-not $candidates.Count){$settled.Key=$null;$settled.Count=0;return $false}
                $identity=$candidates[0]
                if($identity.path -ine $before.Runner.path -or
                    ($identity.processId -eq $before.Runner.processId -and $identity.processStartTicks -eq $before.Runner.processStartTicks)){
                    throw 'Restart did not produce a new Runner from the attested installation.'
                }
                $elevated=Test-ProcessElevated -ProcessId $identity.processId
                if($elevated -isnot [bool] -or $elevated -ne $expected){throw 'Restarted Runner elevation could not be confirmed or differs from the requested state.'}
                $hosts=@(Get-PtNativeWindow -ProcessId $identity.processId -ClassName 'PToyTrayIconWindow')
                if($hosts.Count -gt 1){throw 'Restarted Runner has ambiguous native tray hosts.'}
                if(-not $hosts.Count){$settled.Key=$null;$settled.Count=0;return $false}
                $ready=@(& $VerifyReady $identity @ArgumentList)
                if($ready.Count -ne 1 -or $ready[0] -isnot [bool]){throw 'VerifyReady must return exactly one Boolean observation.'}
                Assert-PtRunnerRestartIdentity $identity
                if(-not $ready[0]){$settled.Key=$null;$settled.Count=0;return $false}
                $key="$($identity.processId):$($identity.processStartTicks):$($hosts[0].Hwnd)"
                if($key -ceq $settled.Key){$settled.Count++}else{$settled.Key=$key;$settled.Count=1}
                if($settled.Count -lt 2){return $false}
                [pscustomobject]@{Runner=$identity;Elevated=$elevated;Host=Get-PtWindowIdentity $hosts[0].Hwnd}
            }
        if((Get-FileHash -LiteralPath $before.Runner.path -Algorithm SHA256 -ErrorAction Stop).Hash -cne $before.ImageHash){
            throw 'Runner image changed during restart; installed-bit identity is not preserved.'
        }
        $receipt.After=$after;$receipt.Phase='Complete';$receipt.Ready=$true
        $receipt
    }catch{
        $failure=$_
        $failure.Exception.Data['RunnerRestartReceipt']=$receipt
        throw $failure
    }
}

function Backup-PtModuleSettings {
    <#
    .SYNOPSIS
    Snapshot a module's settings.json to TEMP for restore-on-exit. Returns the backup path.
    .EXAMPLE
    $bk = Backup-PtModuleSettings -ModuleDir AdvancedPaste
    try { ... mutate ... } finally { Restore-PtModuleSettings -ModuleDir AdvancedPaste -BackupPath $bk }
    #>
    param([Parameter(Mandatory)][string]$ModuleDir)
    $src = "$env:LOCALAPPDATA\Microsoft\PowerToys\$ModuleDir\settings.json"
    if (-not (Test-Path $src)) { return $null }
    $bk = Join-Path $env:TEMP ("ptbk-$ModuleDir-$(Get-Random -Maximum 9999).json")
    Copy-Item -Path $src -Destination $bk -Force
    return $bk
}

function Restore-PtModuleSettings {
    param(
        [Parameter(Mandatory)][string]$ModuleDir,
        [Parameter(Mandatory)][string]$BackupPath
    )
    $dst = "$env:LOCALAPPDATA\Microsoft\PowerToys\$ModuleDir\settings.json"
    Copy-Item -Path $BackupPath -Destination $dst -Force
    Remove-Item $BackupPath -Force -EA SilentlyContinue
}
