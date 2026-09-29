# Session-scoped resource ownership. Dependencies come from the canonical bootstrap.
# This is not an OS sandbox, scheduler or another verification recorder.

function Get-PtActiveResourceSession {
    $value=Get-Variable PtActiveResourceSession -Scope Global -ErrorAction Ignore
    if($value){$value.Value}
}

function Save-PtResourceSession {
    param([Parameter(Mandatory)]$Session)
    $original=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($Session.BaselinePath))
    if((Get-PtReportHash ([IO.File]::ReadAllBytes($Session.BaselinePath))) -cne $Session.BaselineHash -or
        $original.RunId -cne $Session.RunId){throw 'Resource baseline identity changed.'}
    $temporary="$($Session.Path).$([guid]::NewGuid().ToString('N')).tmp"
    try{
        Write-PtReportText $temporary (ConvertTo-Json $Session -Depth 30)
        [IO.File]::Move($temporary,$Session.Path,$true)
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Assert-PtResourceSession {
    param([Parameter(Mandatory)]$Session)
    if($Session.BaselinePath -ine (Join-Path ([IO.Path]::GetDirectoryName($Session.Path)) 'resource-baseline.json')){
        throw 'Resource baseline path does not belong to this session.'
    }
    $stored=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($Session.Path))
    if((ConvertTo-Json $stored -Depth 30 -Compress) -cne (ConvertTo-Json $Session -Depth 30 -Compress)){
        throw 'Resource session changed; reload its receipt before acting.'
    }
    if((Get-PtReportHash ([IO.File]::ReadAllBytes($Session.BaselinePath))) -cne $Session.BaselineHash){
        throw 'Resource baseline was altered.'
    }
    $baseline=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($Session.BaselinePath))
    if($baseline.RunId -cne $Session.RunId){throw 'Resource baseline run identity changed.'}
    if($Session.RunId -cne $stored.RunId -or $Session.Schema -cne 'PtResources.v1'){throw 'Invalid resource session.'}
}

function New-PtResourceSession {
    <#.SYNOPSIS
    Snapshot pre-existing native windows/process IDs before navigation or fixture creation.
    #>
    param([Parameter(Mandatory)]$Run)
    if(Get-PtActiveResourceSession){throw 'A resource session is already active.'}
    $baselinePath=Join-Path $Run.Workspace 'resource-baseline.json'
    $sessionPath=Join-Path $Run.Workspace 'resource-session.json'
    if((Test-Path $sessionPath) -or (Test-Path $baselinePath)){throw 'Existing resource session must be resumed, not rebaselined.'}
    $baseline=[pscustomobject]@{
        RunId=$Run.Id; Windows=@(Get-PtNativeWindow | Select-Object Hwnd,ProcessId,ClassName)
        ProcessIds=@(Get-Process | Select-Object -ExpandProperty Id)
    }
    Write-PtReportText $baselinePath (ConvertTo-Json $baseline -Depth 10)
    $session=[pscustomobject]@{
        Schema='PtResources.v1';RunId=$Run.Id;Path=$sessionPath
        BaselinePath=$baselinePath;BaselineHash=Get-PtReportHash ([IO.File]::ReadAllBytes($baselinePath))
        Processes=@();Windows=@();Obligations=@();Settings=@();Desktop=$null;ResourcePlan=$null
    }
    Write-PtReportText $sessionPath (ConvertTo-Json $session -Depth 30)
    $global:PtActiveResourceSession=$session
    $global:PtLiveResourceGuards=@{}
    $session
}

function Open-PtResourceSession {
    param([Parameter(Mandatory)]$Run)
    if(Get-PtActiveResourceSession){throw 'A resource session is already active.'}
    $session=ConvertFrom-PtReportJson ([IO.File]::ReadAllText((Join-Path $Run.Workspace 'resource-session.json')))
    if($session.RunId -cne $Run.Id -or $session.Path -ine (Join-Path $Run.Workspace 'resource-session.json')){
        throw 'Resource session does not belong to this run.'
    }
    Assert-PtResourceSession $session
    $global:PtActiveResourceSession=$session
    $global:PtLiveResourceGuards=@{}
    # Outstanding in-memory obligations remain blocking after restart, never assumed restored.
    $session
}

function Register-PtBorrowedWindow {
    param([Parameter(Mandatory)]$Identity)
    $session=Get-PtActiveResourceSession
    if(-not $session){throw 'A resource session is required.'}
    Assert-PtResourceSession $session;Assert-PtWindowIdentity $Identity
    $found=@($session.Windows|Where-Object {$_.Identity.hwnd -eq $Identity.hwnd})
    if($found.Count){
        if($found[0].Ownership -ne 'Borrowed' -or
            (ConvertTo-Json $found[0].Identity -Compress) -cne (ConvertTo-Json $Identity -Compress)){
            throw 'Window already has a different ownership contract or identity.'
        }
        return $found[0]
    }
    $record=[pscustomobject]@{Identity=$Identity;Ownership='Borrowed';Lifetime='Run';Creation=$null;Closed=$false}
    $session.Windows+=@($record);Save-PtResourceSession $session
    $record
}

function Start-PtOwnedProcess {
    <#.SYNOPSIS
    Record one authorized fixture launch and its actual process identity, not a name-based adoption.
    #>
    param([Parameter(Mandatory)][string]$FilePath,[string[]]$ArgumentList=@(),
        [ValidateSet('Case','Run')][string]$Lifetime='Case')
    $session=Get-PtActiveResourceSession
    if(-not $session){throw 'A resource session is required.'}
    Assert-PtResourceSession $session
    if($session.ResourcePlan -and -not @($session.ResourcePlan.Resources|Where-Object {
        $_.Kind -eq 'Window' -and $_.Ownership -eq 'Owned'
    }).Count){throw 'Owned process launch is not declared in the run resource plan.'}
    $before=@(Get-Process|Select-Object -ExpandProperty Id)
    $record=[pscustomobject]@{Id=[guid]::NewGuid().ToString('N');FilePath=$FilePath;Arguments=$ArgumentList
        ProcessId=0;ProcessStartTicks=0L;Lifetime=$Lifetime;State='Starting'}
    $session.Processes+=@($record);Save-PtResourceSession $session
    try{
        $args=@{FilePath=$FilePath;PassThru=$true}
        if($ArgumentList.Count){$args.ArgumentList=$ArgumentList}
        $process=Start-Process @args -ErrorAction Stop
        $record.ProcessId=$process.Id
        if($process.Id -in $before){throw 'Launch reused an existing process; ownership not established.'}
        $record.ProcessStartTicks=$process.StartTime.ToUniversalTime().Ticks
        $record.State='Started';Save-PtResourceSession $session
        $record
    }catch{$record.State='Unresolved';Save-PtResourceSession $session;throw}
}

function Assert-PtRunResourcePlan {
    <#.SYNOPSIS
    Fail before driving when a declared resource lacks its run-local restoration wiring.
    #>
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][object[]]$CleanupPlan,
        [long[]]$SettingsHwnd=@())
    if($Plan.Schema -cne 'PtRunResources.v1' -or -not @($Plan.Resources).Count){
        throw 'Supply an explicit nonempty PtRunResources.v1 resource plan.'
    }
    Assert-PtCleanupPlan $CleanupPlan
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $handles=[Collections.Generic.HashSet[long]]::new()
    foreach($resource in $Plan.Resources){
        Assert-PtReportName $resource.Id
        if(-not $ids.Add($resource.Id) -or $resource.Kind -cnotin 'Settings','Window','File','Clipboard','Other'){
            throw 'Resources require unique IDs and known kinds.'
        }
        if($resource.Kind -eq 'Settings'){
            if($resource.Hwnd -isnot [long] -and $resource.Hwnd -isnot [int]){throw 'Settings resources require an explicit native HWND.'}
            if($resource.Hwnd -le 0 -or -not $handles.Add($resource.Hwnd)){
                throw 'Settings HWNDs must be unique, positive values.'
            }
            if($resource.RestoreStep){throw 'Settings resources use the template adapter, not a substitute cleanup callback.'}
        }else{
            $step=@($CleanupPlan|Where-Object Id -CEQ $resource.RestoreStep)
            if($step.Count -ne 1){throw "Resource $($resource.Id) has no matching cleanup Action/Verify step."}
            if($resource.Kind -eq 'Clipboard' -and $step[0].Phase -cne 'Clipboard'){throw 'Clipboard resources require a Clipboard-phase restore step.'}
            if($resource.Kind -eq 'Window' -and $resource.Ownership -cnotin 'Borrowed','Owned'){
                throw 'Window resources must explicitly declare Borrowed or Owned.'
            }
        }
    }
    if($SettingsHwnd.Count -and ($SettingsHwnd.Count -ne $handles.Count -or
        @($SettingsHwnd|Where-Object {-not $handles.Contains($_)}).Count)){
        throw 'SettingsHwnd must match the resource plan; do not omit a borrowed Settings baseline.'
    }
}

function Register-PtCreatedWindow {
    param([Parameter(Mandatory)]$Identity,[Parameter(Mandatory)]$Creation)
    $session=Get-PtActiveResourceSession
    if(-not $session){throw 'A resource session is required.'}
    Assert-PtResourceSession $session;Assert-PtWindowIdentity $Identity
    $launch=@($session.Processes|Where-Object {$_.Id -ceq $Creation.Id -and $_.State -eq 'Started'})
    if($launch.Count -ne 1 -or $launch[0].ProcessId -ne $Identity.processId -or
        $launch[0].ProcessStartTicks -ne $Identity.processStartTicks){throw 'Window is not a product of the recorded launch.'}
    Register-PtOwnedWindowRecord $session $Identity $launch[0].Lifetime $launch[0].Id
}

function Register-PtOwnedWindowRecord {
    param($Session,$Identity,$Lifetime,$Creation,[ValidateSet('Process','Window')][string]$CloseScope='Process')
    Assert-PtResourceSession $Session;Assert-PtWindowIdentity $Identity
    $baseline=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($Session.BaselinePath))
    if($Identity.hwnd -in $baseline.Windows.Hwnd){throw 'Pre-existing window cannot be adopted as owned.'}
    if(@($Session.Windows|Where-Object {$_.Identity.hwnd -eq $Identity.hwnd}).Count){throw 'Window is already registered.'}
    $record=[pscustomobject]@{Identity=$Identity;Ownership='Owned';Lifetime=$Lifetime;Creation=$Creation;CloseScope=$CloseScope;Closed=$false}
    $Session.Windows+=@($record);Save-PtResourceSession $Session
    $record
}

function Register-PtFixtureWindowOwnership {
    <#.SYNOPSIS
    Bridge an already validated module fixture receipt; never grants ownership of a baseline HWND.
    #>
    param([Parameter(Mandatory)]$Identity,[Parameter(Mandatory)][string]$ReceiptPath)
    $session=Get-PtActiveResourceSession
    if(-not $session){return}
    Assert-PtResourceSession $session;Assert-PtWindowIdentity $Identity
    Assert-PtReportNoLink $ReceiptPath
    if(-not [IO.File]::Exists($ReceiptPath)){throw 'Missing module fixture receipt.'}
    $fixture=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($ReceiptPath))
    $target=switch($fixture.Kind){
        'Notepad' {
            Assert-PtOwnedFixture $fixture Notepad
            if(-not $fixture.OwnsWindow -or $fixture.Identity.hwnd -in @($fixture.Baseline.Identity.hwnd)){
                throw 'Notepad tab ownership does not own its window.'
            }
            $fixture.Identity
        }
        'Explorer' {
            Assert-PtOwnedFixture $fixture Explorer
            if($fixture.Identity.hwnd -in $fixture.BaselineHwnds){throw 'Explorer receipt reused a baseline window.'}
            $fixture.Identity
        }
        'Taskbar' {
            $validated=Read-PtTaskbarFixture -ReceiptPath $ReceiptPath
            if($validated.Fixture.Version -ne 2 -or $validated.Fixture.Apps.Count -ne 1){throw 'Unsupported taskbar receipt.'}
            $validated.Fixture.Apps[0].Identity
        }
        default {throw 'Unknown fixture ownership receipt.'}
    }
    if((ConvertTo-Json $target -Compress) -cne (ConvertTo-Json $Identity -Compress)){throw 'Fixture receipt does not own this identity.'}
    $existing=@($session.Windows|Where-Object {$_.Identity.hwnd -eq $Identity.hwnd})
    if($existing.Count){
        if($existing[0].Ownership -ne 'Owned' -or
            (ConvertTo-Json $existing[0].Identity -Compress) -cne (ConvertTo-Json $Identity -Compress)){
            throw 'Fixture ownership cannot replace an existing identity.'
        }
        return
    }
    $scope=if($fixture.Kind -in 'Explorer','Taskbar'){'Window'}else{'Process'}
    Register-PtOwnedWindowRecord $session $Identity 'Case' (Get-PtReportHash ([IO.File]::ReadAllBytes($ReceiptPath))) $scope|Out-Null
}

function Add-PtClipboardObligation {
    param([Parameter(Mandatory)]$Guard,[Parameter(Mandatory)][int]$OwnerProcessId)
    $session=Get-PtActiveResourceSession
    if(-not $session){return}
    Assert-PtResourceSession $session
    $id=[guid]::NewGuid().ToString('N')
    $session.Obligations+=@([pscustomobject]@{Id=$id;Kind='Clipboard';OwnerProcessId=$OwnerProcessId
        WriterProcessIds=@();Restored=$false
        RecoveryReceipt=$(if($Guard.PSObject.Properties['PipeName']){$Guard.Path}else{$null})
        KeeperStartTicks=$(if($Guard.PSObject.Properties['PipeName']){$Guard.ProcessStartTicks}else{$null})})
    $global:PtLiveResourceGuards[$id]=$Guard
    Save-PtResourceSession $session
}

function Protect-PtClipboardWriter {
    <#.SYNOPSIS
    Register the intended writer before its copy, without writing any clipboard contents.
    #>
    param([Parameter(Mandatory)]$Guard,[Parameter(Mandatory)][int]$ProcessId)
    $session=Get-PtActiveResourceSession
    if(-not $session){return}
    Assert-PtResourceSession $session
    $found=@($session.Obligations|Where-Object {
        [object]::ReferenceEquals($global:PtLiveResourceGuards[$_.Id],$Guard)
    })
    if($found.Count -ne 1){throw 'Clipboard guard is not registered in this session.'}
    if($ProcessId -le 0){throw 'Invalid writer process ID.'}
    $found[0].WriterProcessIds=@(@($found[0].WriterProcessIds)+$ProcessId|Select-Object -Unique)
    Save-PtResourceSession $session
}

function Assert-PtProcessRelease {
    param([int[]]$ProcessId)
    $session=Get-PtActiveResourceSession
    if(-not $session){return}
    Assert-PtResourceSession $session
    foreach($obligation in $session.Obligations){
        $live=$global:PtLiveResourceGuards[$obligation.Id]
        if($live -and $live.Restored -is [bool] -and $live.Restored){
            $obligation.Restored=$true;Save-PtResourceSession $session
        }
        if(-not $obligation.Restored -and @($ProcessId|Where-Object {
            $_ -eq $obligation.OwnerProcessId -or $_ -in $obligation.WriterProcessIds
        }).Count){throw 'Process release refused: unresolved clipboard obligation.'}
    }
}

function Assert-PtWindowRelease {
    param([Parameter(Mandatory)]$Identity)
    $session=Get-PtActiveResourceSession
    if(-not $session){return}
    Assert-PtResourceSession $session
    $owned=@($session.Windows|Where-Object {
        $_.Ownership -eq 'Owned' -and (ConvertTo-Json $_.Identity -Compress) -ceq (ConvertTo-Json $Identity -Compress)
    })
    if($owned.Count -ne 1){throw 'Window close refused: no explicit owned creation record (borrowed windows cannot be closed).'}
    Assert-PtProcessRelease -ProcessId $Identity.processId
    if($owned[0].CloseScope -eq 'Window'){return}
    foreach($window in @(Get-PtNativeWindow -ProcessId $Identity.processId)){
        $matching=@($session.Windows|Where-Object {$_.Ownership -eq 'Owned' -and $_.Identity.hwnd -eq $window.Hwnd})
        if($matching.Count -ne 1){throw 'Window close may affect an unowned sibling in the same process.'}
        Assert-PtWindowIdentity $matching[0].Identity
    }

}

function Invoke-PtOwnedWindowReopen {
        <#.SYNOPSIS
        Close only a launch-owned window, wait for its process exit, then launch a new recorded instance.
        #>
        param([Parameter(Mandatory)]$Identity,[Parameter(Mandatory)]$Creation,
            [Parameter(Mandatory)][scriptblock]$ResolveHwnd,[object[]]$ArgumentList=@())
        $session=Get-PtActiveResourceSession
        Assert-PtResourceSession $session
        $launch=@($session.Processes|Where-Object {$_.Id -ceq $Creation.Id})
        if($launch.Count -ne 1 -or $launch[0].ProcessId -ne $Identity.processId -or
            $launch[0].ProcessStartTicks -ne $Identity.processStartTicks){throw 'Reopen requires the actual owned launch record.'}
        Close-PtTrackedWindow $Identity
        Wait-PtCondition -Description 'Owned process exit before reopen' -TimeoutSeconds 5 -Probe {
            $process=Get-Process -Id $Identity.processId -ErrorAction SilentlyContinue
            -not $process -or $process.StartTime.ToUniversalTime().Ticks -ne $Identity.processStartTicks
        }|Out-Null
        $new=Start-PtOwnedProcess -FilePath $launch[0].FilePath -ArgumentList $launch[0].Arguments -Lifetime $launch[0].Lifetime
        $hwnd=& $ResolveHwnd $new @ArgumentList
        $target=Get-PtWindowIdentity $hwnd
        $ownership=Register-PtCreatedWindow -Identity $target -Creation $new
        [pscustomobject]@{Creation=$new;Window=$ownership}
}

function Register-PtSettingsObligation {
    param([Parameter(Mandatory)]$Snapshot)
    $session=Get-PtActiveResourceSession
    if(-not $session){return}
    Assert-PtResourceSession $session
    $session.Settings+=@([pscustomobject]@{Path=$Snapshot.Path;Identity=$Snapshot.Identity
        Hash=Get-PtReportHash ([IO.File]::ReadAllBytes($Snapshot.Path));Restored=$false;RestorationPath=$null;RestorationHash=$null})
    Save-PtResourceSession $session
}

function Complete-PtSettingsObligation {
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][string]$RestorationPath)
    $session=Get-PtActiveResourceSession
    if(-not $session){return}
    Assert-PtResourceSession $session
    $record=@($session.Settings|Where-Object Path -CEQ $Snapshot.Path)
    if($record.Count -ne 1 -or $record[0].Hash -cne (Get-PtReportHash ([IO.File]::ReadAllBytes($Snapshot.Path)))){
        throw 'Settings obligation baseline changed.'
    }
    $record[0].RestorationPath=$RestorationPath
    $record[0].RestorationHash=Get-PtReportHash ([IO.File]::ReadAllBytes($RestorationPath))
    $record[0].Restored=$true
    Save-PtResourceSession $session
}

function Complete-PtResourceSession {
    param([Parameter(Mandatory)]$Attempt)
    $session=Get-PtActiveResourceSession
    if(-not $session -or $session.RunId -cne $Attempt.Run.Id){throw 'Resource session/run mismatch.'}
    Assert-PtResourceSession $session
    $rows=@(foreach($record in $session.Windows){
        $exists=[PtDesktop]::IsWindow([IntPtr][long]$record.Identity.hwnd)
        $status='PASS';$reason='Owned window is absent.'
        if($record.Ownership -eq 'Borrowed'){
            try{Assert-PtWindowIdentity $record.Identity;$reason='Borrowed identity retained; UI-state receipt is separate.'}
            catch{$status='BLOCKED';$reason=$_.Exception.Message}
        }elseif($exists){$status='BLOCKED';$reason='Owned window remains or identity was recycled; no automatic close.'}
        [pscustomobject]@{Resource="window-$($record.Identity.hwnd)";Status=$status;Reason=$reason}
    })
    foreach($record in $session.Processes){
        $process=Get-Process -Id $record.ProcessId -ErrorAction SilentlyContinue
        $alive=$process -and $process.StartTime.ToUniversalTime().Ticks -eq $record.ProcessStartTicks
        $unresolved=$record.State -ne 'Started'
        $rows+=@([pscustomobject]@{Resource="launch-$($record.Id)";Status=$(if($alive -or $unresolved){'BLOCKED'}else{'PASS'})
            Reason=$(if($unresolved){'Launch ownership is unresolved.'}elseif($alive){'Owned process still alive.'}else{'Owned process exited.'})})
    }
    foreach($record in $session.Obligations){
        Assert-PtProcessRelease -ProcessId @() # Refresh completed live guards without releasing anything.
        $rows+=@([pscustomobject]@{Resource="clipboard-$($record.Id)";Status=$(if($record.Restored){'PASS'}else{'BLOCKED'})
            Reason='Clipboard obligation; in-memory data is never placed in this receipt.'})
    }
    foreach($record in $session.Settings){
        $valid=$false;$reason='Settings supported UI-state comparison; unsupported state is explicitly excluded.'
        try{
            if(-not $record.Restored -or -not [IO.File]::Exists($record.RestorationPath) -or
                (Get-PtReportHash ([IO.File]::ReadAllBytes($record.RestorationPath))) -cne $record.RestorationHash -or
                (Get-PtReportHash ([IO.File]::ReadAllBytes($record.Path))) -cne $record.Hash){throw 'Settings restoration receipt missing or changed.'}
            $snapshot=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($record.Path))
            Assert-PtWindowIdentity $snapshot.Identity
            $observed=Get-PtSettingsCurrentState $snapshot.Identity.hwnd -AllowTemporaryRestore
            $ui=$observed.Ui;$native=$observed.Native
            if((ConvertTo-Json $ui -Depth 20 -Compress) -cne (ConvertTo-Json $snapshot.Ui -Depth 20 -Compress) -or
                (ConvertTo-Json $native -Depth 20 -Compress) -cne (ConvertTo-Json $snapshot.Native -Depth 20 -Compress)){
                throw 'Settings changed after its restoration receipt.'
            }
            $valid=$true
        }catch{$reason=$_.Exception.Message}
        $rows+=@([pscustomobject]@{Resource=$record.Path;Status=$(if($valid){'PASS'}else{'BLOCKED'})
            Reason=$reason})
    }
    $file=New-PtVerificationArtifactPath -Attempt $Attempt -Name 'resource-completion.json'
    Write-PtReportText $file (ConvertTo-Json -InputObject $rows -Depth 8)
    $evidence=Add-PtVerificationArtifact -Attempt $Attempt -Path $file -Kind Restoration -Description 'Ownership/dependency completion, not arbitrary desktop equality'
    $verdict=if(@($rows|Where-Object Status -ne 'PASS').Count){'BLOCKED'}else{'PASS'}
    Add-PtVerificationRestoration -Attempt $Attempt -Verdict $verdict -Reason 'Recorded ownership and release obligations only; Settings and file comparisons remain separately required.' -Evidence @($evidence)
    if($verdict -ne 'PASS'){throw 'Resource session has unresolved ownership or restoration obligations.'}
    $rows
}
