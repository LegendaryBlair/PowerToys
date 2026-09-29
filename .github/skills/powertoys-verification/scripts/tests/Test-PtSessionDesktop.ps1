#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-session-desktop-$([guid]::NewGuid().ToString('N'))"),
    [switch]$SkipClipboard,[switch]$DisposableClipboard)
$ErrorActionPreference='Stop'
if(-not $SkipClipboard -and -not $DisposableClipboard){throw 'Clipboard acceptance requires an explicitly disposable session; supply -SkipClipboard or -DisposableClipboard.'}
$helpers=Split-Path $PSScriptRoot -Parent
foreach($name in 'pt-desktop','pt-verification-report','pt-settings-session','pt-clipboard-session'){. "$helpers\$name.ps1"}
if([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'){throw 'Use pwsh -STA.'}
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$desktop=Get-PtDesktopSnapshot
$process=$null;$owned=$null;$guard=$null;$provider=$null;$results=@()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
function WaitReady([string]$Path){
    Wait-PtCondition -Description 'Owned WPF fixture readiness' -TimeoutSeconds 15 -Probe {
        if([IO.File]::Exists($Path)){ConvertFrom-PtReportJson ([IO.File]::ReadAllText($Path))}
    }
}
$fixture="$PSScriptRoot\fixtures\SettingsSurface.ps1"
$shell=(Get-Command pwsh).Source
$ready="$Workspace\borrowed-ready.json"
try{
    $process=Start-Process $shell -ArgumentList @('-NoProfile','-STA','-File',"`"$fixture`"",'-ReadyPath',"`"$ready`"") -PassThru
    $target=WaitReady $ready
    Require ($target.ProcessId -eq $process.Id) 'Fixture process ownership mismatch'
    $identity=Get-PtWindowIdentity $target.Hwnd
    $sibling=Get-PtWindowIdentity $target.Sibling
    $run=New-PtVerificationRun -Workspace "$Workspace\run" -Module 'Owned desktop acceptance' -Bits 'Synthetic WPF only' `
        -Scenario InfrastructureAcceptance -Items @(@{Id='fixture';Admin='NO';Clarity='CLEAR';UserVisible=$true;Description='Owned fixture';Assertions=@(@{Id='state';Description='State restoration'})}) `
        -Inputs @(Get-PtVerificationInputs -Skill (Split-Path $helpers -Parent) -Inputs @(
            @{Name='test.ps1';Role='Checklist';Path=$PSCommandPath},
            @{Name='SettingsSurface.ps1';Role='Other';Path=$fixture}))
    New-PtResourceSession $run|Out-Null
    Register-PtBorrowedWindow $sibling|Out-Null
    [void][PtDesktop]::ShowWindow([IntPtr]$target.Hwnd,6)
    $snapshot=Get-PtSettingsUiSnapshot $target.Hwnd $run.Workspace
    Require ($snapshot.Native.placement.showCmd -eq 2) 'Initial minimized placement was not captured'
    [void][PtDesktop]::ShowWindow([IntPtr]$target.Hwnd,9)
    $changed=ConvertFrom-PtReportJson (ConvertTo-Json $snapshot.Ui -Depth 20)
    $changed.PageAutomationId='FixtureNavItem'
    $changed.Expansion|ForEach-Object {$_.State='Collapsed'}
    $changed.Scroll|ForEach-Object {if($_.Vertical -ge 0){$_.Vertical=70}}
    Set-PtSettingsUiState $target.Hwnd $changed
    Require ((Read-PtSettingsUiState $target.Hwnd).PageAutomationId -ceq 'FixtureNavItem') 'Synthetic navigation did not occur'
    $restored=Restore-PtSettingsUiSnapshot $snapshot
    Require ($restored.Restored -and $restored.Native.placement.showCmd -eq 2) 'Minimized state was not restored'
    Reject {Close-PtTrackedWindow $identity} 'no explicit owned'
    Assert-PtWindowIdentity $sibling
    $results+=@(@{Name='Borrowed page/expansion/scroll/minimized placement and sibling preservation';Status='PASS'})

    $ownedReady="$Workspace\owned-ready.json"
    $creation=Start-PtOwnedProcess $shell @('-NoProfile','-STA','-File',"`"$fixture`"",'-ReadyPath',"`"$ownedReady`"",'-Simple')
    $owned=WaitReady $ownedReady
    $ownedIdentity=Get-PtWindowIdentity $owned.Hwnd
    Register-PtCreatedWindow $ownedIdentity $creation|Out-Null
    foreach($window in @(Get-PtNativeWindow -ProcessId $creation.ProcessId|Where-Object Hwnd -NE $owned.Hwnd)){
        Register-PtCreatedWindow (Get-PtWindowIdentity $window.Hwnd) $creation|Out-Null
    }
    if(-not $SkipClipboard){
        $guard=New-PtClipboardSession -Workspace $Workspace
        Protect-PtClipboardWriter $guard $creation.ProcessId
        Reject {$guard.Dispose()} 'Restore the registered'
        Reject {Close-PtTrackedWindow $ownedIdentity} 'clipboard obligation'
        $guard.Restore();Assert-PtClipboardRestored $guard;$guard.Dispose()
        $results+=@(@{Name='Live clipboard obligation gates close and disposal';Status='PASS'})
    }else{$results+=@(@{Name='Live clipboard obligation gates close and disposal';Status='SKIPPED';Reason='Explicit no-clipboard acceptance scope'})}
    $reopened=Invoke-PtOwnedWindowReopen $ownedIdentity $creation -ResolveHwnd {
        param($launched)
        $visible=Wait-PtCondition -Description 'Reopened owned synthetic window' -TimeoutSeconds 15 -Probe {
            $matches=@(Get-PtNativeWindow -ProcessId $launched.ProcessId -Visible|Where-Object Title -eq 'Owned harness Settings fixture')
            if($matches.Count -eq 1){$matches[0]}
        }
        $visible.Hwnd
    }
    $creation=$reopened.Creation;$ownedIdentity=$reopened.Window.Identity
    foreach($window in @(Get-PtNativeWindow -ProcessId $creation.ProcessId|Where-Object Hwnd -NE $ownedIdentity.hwnd)){
        Register-PtCreatedWindow (Get-PtWindowIdentity $window.Hwnd) $creation|Out-Null
    }
    Close-PtTrackedWindow $ownedIdentity
    Wait-PtCondition -Description 'Owned fixture process exited' -TimeoutSeconds 10 -Probe { -not (Get-Process -Id $creation.ProcessId -ErrorAction SilentlyContinue) }|Out-Null
    $owned=$null
    $results+=@(@{Name='Launch-owned reopen returns a fresh identity';Status='PASS'})
    $attempt=Start-PtVerificationAttempt -Run $run -Context Cleanup -Name 'Owned fixture cleanup' -Kind Normal
    try{Complete-PtResourceSession $attempt|Out-Null}
    finally{Stop-PtVerificationAttempt $attempt -Reason 'Synthetic borrowed baselines retained and owned process gone'}
}finally{
    if($guard -and -not $guard.Restored){$guard.Restore()}
    if($guard){Assert-PtClipboardRestored $guard;$guard.Dispose()}
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
    # These two processes were created by this test, before/after its inner borrowing boundary.
    foreach($candidate in @($creation,$process)){
        if(-not $candidate){continue}
        $processId=if($candidate.PSObject.Properties['ProcessId']){$candidate.ProcessId}else{$candidate.Id}
        $startTicks=if($candidate.PSObject.Properties['ProcessStartTicks']){$candidate.ProcessStartTicks}else{$candidate.StartTime.ToUniversalTime().Ticks}
        $current=Get-Process -Id $processId -ErrorAction SilentlyContinue
        if($current -and $current.StartTime.ToUniversalTime().Ticks -eq $startTicks){
            foreach($window in @(Get-PtNativeWindow -ProcessId $processId|Where-Object Visible)){
                if([PtDesktop]::IsWindow([IntPtr][long]$window.Hwnd)){Close-PtTrackedWindow (Get-PtWindowIdentity $window.Hwnd)}
            }
            Wait-PtCondition -Description 'Test-owned process cleanup' -TimeoutSeconds 10 -Probe {-not (Get-Process -Id $processId -ErrorAction SilentlyContinue)}|Out-Null
        }
    }
    if($provider){$provider.Dispose()}
    Restore-PtDesktopSnapshot $desktop|ConvertTo-Json -Depth 20|Set-Content "$Workspace\desktop-restored.json"
    Write-PtReportText "$Workspace\results.json" (ConvertTo-Json -InputObject $results -Depth 10)
}
"PASS: $(@($results|Where-Object Status -eq 'PASS').Count) owned desktop groups; $(@($results|Where-Object Status -eq 'SKIPPED').Count) explicitly skipped. No PowerToys module executed. $Workspace"
