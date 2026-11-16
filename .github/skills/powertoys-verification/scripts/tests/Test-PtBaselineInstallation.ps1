# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

param([string]$Workspace = (Join-Path $env:TEMP ('pt-baseline-acceptance-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\pt-baseline-installation.ps1')
[void][IO.Directory]::CreateDirectory($Workspace)
$script:passed = 0

function Assert-That([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    try { & $Action | Out-Null } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return
    }
    throw "Expected exception matching: $Pattern"
}
function Test-Case([string]$Name, [scriptblock]$Action) {
    try { & $Action; $script:passed++; Write-Host "PASS: $Name" }
    catch { throw "$Name`: $($_.Exception.Message)`n$($_.ScriptStackTrace)" }
}
function New-Release([string]$Version, [bool]$Preview = $false, [string]$Architecture = 'x64', [string]$Scope = 'PerUser') {
    $prefix = if ($Scope -eq 'PerUser') { 'PowerToysUserSetup' } else { 'PowerToysSetup' }
    $name = "$prefix-$Architecture-$Version.exe"
    [pscustomobject]@{
        id = 1; tag_name = "v$Version"; draft = $false; prerelease = $Preview; published_at = "$Version"
        assets = @([pscustomobject]@{ id = 2; name = $name; size = 123; digest = ''; browser_download_url = "https://github.com/microsoft/PowerToys/releases/download/v$Version/$name" })
    }
}
$script:apiRelease = New-Release '2.0.0'
$script:apiReleases = @()
$script:apiFailure = $false
function Invoke-PtBaselineGitHub {
    param([string]$Endpoint)
    if ($script:apiFailure) { throw 'Simulated network failure.' }
    if ($Endpoint -match '/commits/v(\d)') { return [pscustomobject]@{ sha = ($Matches[1] * 40) } }
    if ($Endpoint -match '/compare/(4{40})') { return [pscustomobject]@{ status = 'diverged' } }
    if ($Endpoint -match '/compare/') { return [pscustomobject]@{ status = 'ahead' } }
    if ($Endpoint -match 'releases\?') { return $script:apiReleases }
    if ($Endpoint -match '/tags/v1\.0\.0$') { return (New-Release '1.0.0') }
    $script:apiRelease
}

Test-Case 'Exact stable asset and immutable source, not first installer' {
    $script:apiRelease.assets[0].name = 'PowerToysUserSetup-2.0.0.0-x64.exe'
    $script:apiRelease.assets[0].browser_download_url = 'https://github.com/microsoft/PowerToys/releases/download/v2.0.0/PowerToysUserSetup-2.0.0.0-x64.exe'
    $script:apiRelease.assets = @((New-Release '2.0.0' $false 'arm64').assets[0], $script:apiRelease.assets[0])
    $selection = Resolve-PtBaselineRelease -Architecture x64
    Assert-That ($selection.Version -eq '2.0.0.0' -and $selection.Architecture -eq 'x64' -and $selection.Commit -eq ('2' * 40)) 'Wrong release selection.'
}
Test-Case 'Latest eligible main preview, no stable/fork fallback' {
    $script:apiReleases = @((New-Release '4.0.0' $true), (New-Release '3.0.0' $true), (New-Release '2.0.0'))
    $selection = Resolve-PtBaselineRelease -Channel DevPreview -Architecture x64
    Assert-That ($selection.Version -eq '3.0.0.0' -and $selection.Channel -eq 'DevPreview') 'Did not skip divergent preview.'
    $script:apiReleases = @((New-Release '2.0.0'))
    Assert-Throws { Resolve-PtBaselineRelease -Channel DevPreview -Architecture x64 } 'No eligible'
}
Test-Case 'Explicit version wins; missing/duplicate/wrong-scope assets refuse' {
    $selection = Resolve-PtBaselineRelease -Version '1.0.0.0' -Architecture x64
    Assert-That ($selection.Version -eq '1.0.0.0') 'Pin ignored.'
    Assert-Throws { Resolve-PtBaselineRelease -Scope PerMachine -Architecture x64 } 'Expected one exact'
    $script:apiRelease.assets += $script:apiRelease.assets[-1]
    Assert-Throws { Resolve-PtBaselineRelease -Architecture x64 } 'Expected one exact'
    $script:apiRelease = New-Release '2.0.0'
    $script:apiRelease.assets[0].browser_download_url = 'https://example.invalid/installer.exe'
    Assert-Throws { Resolve-PtBaselineRelease -Architecture x64 } 'exact official'
    $script:apiRelease = New-Release '2.0.0'
}

$realInstaller = ${function:Invoke-PtBaselineInstaller}
$realAssertInstaller = ${function:Assert-PtBaselineInstaller}
$realConfirmRuntime = ${function:Confirm-PtBaselineRuntime}
$realQuiescent = ${function:Assert-PtBaselineQuiescent}
$realDiscovery = ${function:Get-PtBaselineInstallation}
$script:testState = $null
function Reset-TestState {
    $script:testState = [pscustomobject]@{
        Original = [pscustomobject]@{ Installed = $true; Version = '1.0.0.0'; Architecture = 'x64'; Scope = 'PerUser'; Path = 'C:\PT\PowerToys.exe'; Sha256 = 'original-hash' }
        Current = $null; Calls = [Collections.Generic.List[string]]::new(); CacheFailure = ''
        FailAt = 0; RebootAt = 0; Boot = 'before'; RebootPending = $false; CorruptVersion = $false
        Verify = $true; Quiescent = $true; BadSignature = $false; TargetCount = 0
        LiveValue = 'original private settings'; Started = 0; Captured = 0
    }
    $script:testState.Current = $script:testState.Original
}
function Get-PtBaselineInstallation { $script:testState.Current }
function Get-PtBaselineBootState { [pscustomobject]@{ Boot = $script:testState.Boot; RebootPending = $script:testState.RebootPending } }
function Save-PtBaselineInstaller {
    param($Selection, [string]$Directory)
    $script:testState.Calls.Add("cache:$($Selection.Version)")
    if ($Selection.Version -eq $script:testState.CacheFailure) { throw 'Rollback package unavailable.' }
    [pscustomobject]@{ Path = (Join-Path $Directory $Selection.AssetName); Selection = $Selection; Sha256 = 'test-hash' }
}
function Assert-PtBaselineInstaller { param($Artifact); if ($script:testState.BadSignature) { throw 'Bad installer signature.' } }
function Assert-PtBaselineQuiescent { if (-not $script:testState.Quiescent) { throw 'Processes still running.' } }
function Confirm-PtBaselineRuntime {
    param($Installation, [int]$ProcessId)
    if ($ProcessId -ne 1234) { throw 'Wrong runtime PID.' }
    [pscustomobject]@{ ProcessId = $ProcessId; Binary = $Installation; StartTimeUtc = 'test-generation' }
}
function Invoke-PtBaselineInstaller {
    param($Session, $Artifact, [string]$Operation)
    Assert-PtBaselineInstaller $Artifact
    Assert-PtBaselineQuiescent
    $script:testState.Calls.Add("$Operation`:$($Artifact.Selection.Version)")
    $count = @($script:testState.Calls | Where-Object { $_ -notlike 'cache:*' }).Count
    $Session.InstallationTouched = $true
    $Session.Installer = [pscustomobject]@{ Completed = $true; ExitCode = 0 }
    Save-PtBaselineSession $Session 'InstallerStarting'
    if ($count -eq $script:testState.FailAt) { $Session.Installer.ExitCode = 1603; Save-PtBaselineSession $Session 'InstallerCompleted'; throw 'Simulated installer failure 1603.' }
    if ($Operation -eq 'Uninstall') {
        $script:testState.Current = [pscustomobject]@{ Installed = $false; Version = ''; Architecture = ''; Scope = ''; Path = ''; Sha256 = '' }
    }
    elseif ($Artifact.Selection.Version -eq '1.0.0.0') { $script:testState.Current = $script:testState.Original }
    else {
        $version = if ($script:testState.CorruptVersion) { '9.0.0.0' } else { $Artifact.Selection.Version }
        $script:testState.Current = [pscustomobject]@{ Installed = $true; Version = $version; Architecture = $Artifact.Selection.Architecture; Scope = $Artifact.Selection.Scope; Path = 'C:\PT\PowerToys.exe'; Sha256 = 'baseline-hash' }
    }
    if ($count -eq $script:testState.RebootAt) {
        $Session.RebootRequired = $true
        Save-PtBaselineSession $Session 'RebootRequired'
        throw 'Simulated reboot required.'
    }
    Save-PtBaselineSession $Session 'InstallerCompleted'
}
$preserve = {
    param($StateDirectory)
    $path = Join-Path $StateDirectory 'original.json'
    [IO.File]::WriteAllText($path, (@{ Value = $script:testState.LiveValue } | ConvertTo-Json))
    $path
}
$quiesce = { param($Session) }
$start = { param($Session); $script:testState.Started++; 1234 }
$restore = { param($Receipt, $Session); $script:testState.LiveValue = (Get-Content -LiteralPath $Receipt -Raw | ConvertFrom-Json).Value }
$verify = { param($Receipt, $Session); [bool]($script:testState.Verify -and $script:testState.LiveValue -eq 'original private settings') }
$capture = { param($Session); $script:testState.Captured++; $script:testState.LiveValue = 'baseline fixture settings'; [pscustomobject]@{ Status = 'Reproduced'; Evidence = @('before.mp4') } }
$target = { param($Result); $script:testState.TargetCount++; [pscustomobject]@{ Status = 'PASS'; Evidence = @('after.mp4') } }
function New-TestPlan { New-PtBaselineInstallationPlan -Baseline (Resolve-PtBaselineRelease -Architecture x64) }
function Invoke-ComparisonCase([string]$Name, [scriptblock]$Baseline = $capture, [scriptblock]$Acquire = { New-TestPlan }) {
    Invoke-PtBaselineComparison -AcquirePlan $Acquire -Directory (Join-Path $Workspace $Name) -PreserveState $preserve -Quiesce $quiesce -StartRuntime $start -CaptureBaseline $Baseline -RestoreState $restore -VerifyState $verify -CaptureTarget $target -AllowInstall
}

Test-Case 'Switch caches both installers before removal, restores state and exact original' {
    Reset-TestState
    $result = Invoke-ComparisonCase 'switch'
    Assert-That ($result.BaselineStatus -eq 'Reproduced' -and $result.Recovery.Restored -and $result.TargetExecuted) ($result | ConvertTo-Json -Depth 5)
    Assert-That (($script:testState.Calls -join ',') -eq 'cache:2.0.0.0,cache:1.0.0.0,Uninstall:1.0.0.0,Install:2.0.0.0,Uninstall:2.0.0.0,Install:1.0.0.0') 'Incorrect switch/rollback ordering.'
    Assert-That ($script:testState.LiveValue -eq 'original private settings') 'Private state not restored.'
    $count = $script:testState.Calls.Count
    $again = Restore-PtBaselineInstallation -Directory (Join-Path $Workspace 'switch') -Quiesce $quiesce -RestoreState $restore -VerifyState $verify
    Assert-That ($again.Restored -and $script:testState.Calls.Count -eq $count) 'Restore is not idempotent.'
}
Test-Case 'Already matching installation is reused without installer calls' {
    Reset-TestState
    $script:testState.Current = [pscustomobject]@{ Installed = $true; Version = '2.0.0.0'; Architecture = 'x64'; Scope = 'PerUser'; Path = 'C:\PT\PowerToys.exe'; Sha256 = 'baseline-hash' }
    $result = Invoke-ComparisonCase 'reuse'
    Assert-That ($result.Recovery.Restored -and $script:testState.Calls.Count -eq 0 -and $result.TargetExecuted) 'Reuse mutated installation.'
}
Test-Case 'Original absence is restored by removing only the owned baseline' {
    Reset-TestState
    $script:testState.Current = [pscustomobject]@{ Installed = $false; Version = ''; Architecture = ''; Scope = ''; Path = ''; Sha256 = '' }
    $result = Invoke-ComparisonCase 'absent'
    Assert-That ($result.Recovery.Restored -and -not $script:testState.Current.Installed -and $result.TargetExecuted) 'Original absence not restored.'
    Assert-That (($script:testState.Calls -join ',') -eq 'cache:2.0.0.0,Install:2.0.0.0,Uninstall:2.0.0.0') 'Wrong absent-install lifecycle.'
}
Test-Case 'Missing rollback material prevents removal and does not block target' {
    Reset-TestState
    $script:testState.CacheFailure = '1.0.0.0'
    $result = Invoke-ComparisonCase 'missing-rollback'
    Assert-That ($result.BaselineStatus -eq 'Unavailable' -and $result.TargetExecuted -and $script:testState.Started -eq 0) 'Unsafe/missing rollback handling.'
    Assert-That (@($script:testState.Calls | Where-Object { $_ -notlike 'cache:*' }).Count -eq 0) 'Removal attempted without rollback.'
}
Test-Case 'Non-reproduction and capture failure independently permit target capture' {
    Reset-TestState
    $result = Invoke-ComparisonCase 'not-reproduced' { param($Session); [pscustomobject]@{ Status = 'NotReproduced' } }
    Assert-That ($result.BaselineStatus -eq 'NotReproduced' -and $result.TargetExecuted -and $result.Recovery.Restored) 'Non-reproduction gated target.'
    Reset-TestState
    $result = Invoke-ComparisonCase 'capture-error' { throw 'Recorder failed.' }
    Assert-That ($result.BaselineStatus -eq 'Unavailable' -and $result.TargetExecuted -and $result.Recovery.Restored) 'Capture error gated target.'
    Reset-TestState
    $result = Invoke-ComparisonCase 'acquisition-error' -Acquire { throw 'Release unavailable.' }
    Assert-That ($result.TargetExecuted -and $script:testState.Calls.Count -eq 0) 'Acquisition error gated target.'
}
Test-Case 'Existing recovery directory is never adopted by a new comparison' {
    Reset-TestState
    $before = (Get-ChildItem -LiteralPath (Join-Path $Workspace 'switch') -Filter 'receipt-*.json').Count
    $result = Invoke-ComparisonCase 'switch'
    $after = (Get-ChildItem -LiteralPath (Join-Path $Workspace 'switch') -Filter 'receipt-*.json').Count
    Assert-That ($result.TargetExecuted -and $before -eq $after -and $script:testState.Calls.Count -eq 0) 'Unrelated recovery session was adopted.'
}
Test-Case 'Failed uninstall repairs original; failed baseline install rolls back' {
    foreach ($failure in @(1, 2)) {
        Reset-TestState
        $script:testState.FailAt = $failure
        $result = Invoke-ComparisonCase "failure-$failure"
        Assert-That ($result.Recovery.Restored -and $result.TargetExecuted -and $script:testState.Captured -eq 0) "Failure $failure did not restore safely."
    }
}
Test-Case 'Failed restoration and foreign installation block only dependent target mutation' {
    Reset-TestState
    $script:testState.FailAt = 4
    $result = Invoke-ComparisonCase 'restore-fails'
    Assert-That (-not $result.Recovery.SafeForTarget -and -not $result.TargetExecuted) 'Failed rollback was marked safe.'
    Reset-TestState
    $script:testState.CorruptVersion = $true
    $result = Invoke-ComparisonCase 'wrong-version'
    Assert-That (-not $result.TargetExecuted -and $script:testState.Captured -eq 0) 'Wrong installed version was captured.'
    Assert-That ($script:testState.Calls.Count -eq 4) 'Foreign installation was automatically removed.'
    Reset-TestState
    $script:testState.Verify = $false
    $result = Invoke-ComparisonCase 'state-conflict'
    Assert-That (-not $result.TargetExecuted -and -not $result.Recovery.SafeForTarget) 'Unverified settings restoration was accepted.'
}
Test-Case 'Reboot exit retains recovery; explicit post-reboot restore succeeds' {
    Reset-TestState
    $script:testState.RebootAt = 2
    $result = Invoke-ComparisonCase 'reboot'
    Assert-That (-not $result.TargetExecuted -and $result.Recovery.RebootRequired) 'Reboot requirement ignored.'
    $script:testState.Boot = 'after'
    $recovered = Restore-PtBaselineInstallation -Directory (Join-Path $Workspace 'reboot') -Quiesce $quiesce -RestoreState $restore -VerifyState $verify
    Assert-That ($recovered.Restored -and $recovered.SafeForTarget) 'Post-reboot recovery failed.'
}
Test-Case 'Install permission, process readiness and changed plan fail before removal' {
    Reset-TestState
    $plan = New-TestPlan
    $session = Enter-PtBaselineInstallation -Plan $plan -Directory (Join-Path $Workspace 'no-authority') -PreserveState $preserve -Quiesce $quiesce -StartRuntime $start
    Assert-That ($session.SafeForTarget -and -not $session.Ready -and $script:testState.Calls.Count -eq 0) 'Install authority bypassed.'
    $script:testState.Current = [pscustomobject]@{ Installed = $false; Version = ''; Architecture = ''; Scope = ''; Path = ''; Sha256 = '' }
    $session = Enter-PtBaselineInstallation -Plan $plan -Directory (Join-Path $Workspace 'stale-plan') -PreserveState $preserve -Quiesce $quiesce -StartRuntime $start -AllowInstall
    Assert-That (-not $session.Ready -and $script:testState.Calls.Count -eq 0) 'Stale plan mutated installation.'
    Reset-TestState
    $script:testState.Quiescent = $false
    $result = Invoke-ComparisonCase 'not-quiescent'
    Assert-That (@($script:testState.Calls | Where-Object { $_ -notlike 'cache:*' }).Count -eq 0) 'Installer ran while processes remained.'
}
Test-Case 'Original-state and receipt-chain tampering prevents restore' {
    Reset-TestState
    $session = Enter-PtBaselineInstallation -Plan (New-TestPlan) -Directory (Join-Path $Workspace 'tamper') -PreserveState $preserve -Quiesce $quiesce -StartRuntime $start -AllowInstall
    [IO.File]::AppendAllText($session.StateReceipt, 'changed')
    $result = Restore-PtBaselineInstallation -Directory $session.Directory -Quiesce $quiesce -RestoreState $restore -VerifyState $verify
    Assert-That (-not $result.SafeForTarget) 'Changed originals accepted.'
    [IO.File]::AppendAllText((Join-Path $session.Directory 'receipt-00001.json'), ' ')
    Assert-Throws { Get-PtBaselineSession $session.Directory } 'receipt chain'
}
Test-Case 'Registry views deduplicate only the same identity; distinct installations refuse' {
    $script:registrations = @(
        [pscustomobject]@{ Scope = 'PerUser'; RegistrationId = 'same-guid'; Key = 'view64'; Version = '1.0.0.0'; Location = 'C:\fixture'; Kind = 'Bundle' },
        [pscustomobject]@{ Scope = 'PerUser'; RegistrationId = 'same-guid'; Key = 'view32'; Version = '1.0.0.0'; Location = 'C:\fixture'; Kind = 'Bundle' }
    )
    function Get-PtBaselineRegistrations { $script:registrations }
    function Test-Path { param($LiteralPath); $false }
    function Get-PtBaselineBinaryIdentity {
        param($Path)
        [pscustomobject]@{ Path = $Path; Version = '1.0.0.0'; Architecture = 'x64'; Sha256 = 'identity' }
    }
    $installed = & $realDiscovery
    Assert-That ($installed.Installed -and $installed.Version -eq '1.0.0.0') 'Shared registry views treated as two installs.'
    $script:registrations[1].Version = '2.0.0.0'
    Assert-Throws { & $realDiscovery } 'Conflicting'
    $script:registrations[1].Version = '1.0.0.0'
    $script:registrations[1].RegistrationId = 'another-guid'
    Assert-Throws { & $realDiscovery } 'Ambiguous'
    $script:registrations[1].Kind = 'Msi'
    $script:registrations[1].Scope = 'PerMachine'
    Assert-That ((& $realDiscovery).Scope -eq 'PerUser') 'Payload MSI hive incorrectly changed bundle scope.'
    $script:registrations[1].Location = 'C:\another-install'
    Assert-Throws { & $realDiscovery } 'orphaned'
    $script:registrations = @($script:registrations[0])
    $script:registrations[0].Kind = 'Msi'
    Assert-Throws { & $realDiscovery } 'orphaned'
}
Test-Case 'Runtime attestation checks actual executable and current hash' {
    $identity = Get-PtBaselineBinaryIdentity ([Environment]::ProcessPath)
    $installation = [pscustomobject]@{ Path = $identity.Path; Version = $identity.Version; Sha256 = $identity.Sha256 }
    $runtime = & $realConfirmRuntime -Installation $installation -ProcessId $PID
    Assert-That ($runtime.ProcessId -eq $PID) 'Runtime identity not recorded.'
    $installation.Sha256 = 'changed'
    Assert-Throws { & $realConfirmRuntime -Installation $installation -ProcessId $PID } 'changed after'
    $installation.Path = 'C:\wrong\PowerToys.exe'
    Assert-Throws { & $realConfirmRuntime -Installation $installation -ProcessId $PID } 'not the installed'
}

# Test the real installer primitive with only its OS/process boundary replaced.
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$PassThru, $ErrorAction)
    $script:installerArguments = $ArgumentList
    if ($script:installerLaunchFails) { throw 'Simulated launch denied.' }
    $process = [pscustomobject]@{ Id = 4321; StartTime = [datetime]::UtcNow; ExitCode = $script:installerExit }
    $process | Add-Member ScriptMethod WaitForExit { param($Timeout); $script:installerFinishes }
    $process | Add-Member ScriptMethod Refresh {}
    $process
}
Test-Case 'Real installer primitive enforces quiet/no-restart, exit, timeout and reboot gates' {
    $script:installerLaunchFails = $false
    foreach ($code in @(0, 1603, 3010, 1641)) {
        Reset-TestState
        $session = Enter-PtBaselineInstallation -Plan (New-TestPlan) -Directory (Join-Path $Workspace "primitive-$code") -PreserveState $preserve -Quiesce $quiesce -StartRuntime $start
        $script:installerExit = $code
        $script:installerFinishes = $true
        $artifact = [pscustomobject]@{ Path = 'C:\fixture\PowerToys.exe' }
        if ($code -eq 0) { & $realInstaller $session $artifact Install }
        else { Assert-Throws { & $realInstaller $session $artifact Install } 'failed|reboot' }
        Assert-That ('/quiet' -in $script:installerArguments -and '/norestart' -in $script:installerArguments) 'Unsafe installer arguments.'
        Assert-That ($session.Installer.ExitCode -eq $code -and $session.Installer.Completed) 'Exit status lost.'
    }
    $script:installerFinishes = $false
    Assert-Throws { & $realInstaller $session $artifact Install } 'still running'
    Assert-That (-not $session.Installer.Completed) 'Timed-out process marked complete.'
    $script:testState.BadSignature = $true
    Assert-Throws { & $realInstaller $session $artifact Uninstall } 'signature'
    $script:testState.BadSignature = $false
    $script:installerLaunchFails = $true
    Assert-Throws { & $realInstaller $session $artifact Install } 'launch denied'
    Assert-That ($session.Installer.LaunchFailed -and $session.Installer.Completed -and $null -eq $session.Installer.ExitCode) 'Known launch failure treated as a running installer.'
}

function Get-AuthenticodeSignature {
    param($LiteralPath)
    [pscustomobject]@{ Status = $script:signatureStatus; SignerCertificate = [pscustomobject]@{ Subject = $script:signatureSubject } }
}
Test-Case 'Real package validation checks signature, size, hash, version and exact source' {
    $fixtureVersion = (Get-Item -LiteralPath ([Environment]::ProcessPath)).VersionInfo.FileVersion
    $script:apiRelease = New-Release $fixtureVersion
    $selection = Resolve-PtBaselineRelease -Architecture x64
    $assemblyPath = Join-Path $Workspace $selection.AssetName
    [IO.File]::Copy([Environment]::ProcessPath, $assemblyPath)
    $selection.Size = (Get-Item -LiteralPath $assemblyPath).Length
    $artifact = [pscustomobject]@{ Path = $assemblyPath; Selection = $selection; Sha256 = (Get-FileHash -LiteralPath $assemblyPath).Hash }
    $script:signatureStatus = 'Valid'
    $script:signatureSubject = 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US'
    & $realAssertInstaller $artifact
    $script:signatureStatus = 'NotSigned'
    Assert-Throws { & $realAssertInstaller $artifact } 'Authenticode'
    $script:signatureStatus = 'Valid'
    $script:signatureSubject = 'CN=Other Publisher, O=Not Microsoft Corporation, C=US'
    Assert-Throws { & $realAssertInstaller $artifact } 'Microsoft Authenticode'
    $script:signatureSubject = 'O=Microsoft Corporation'
    $artifact.Sha256 = 'wrong'
    Assert-Throws { & $realAssertInstaller $artifact } 'hash/length'
    $artifact.Sha256 = (Get-FileHash -LiteralPath $assemblyPath).Hash
    $selection.Version = '3.0.0.0'
    Assert-Throws { & $realAssertInstaller $artifact } 'file version'
    $selection.Version = ConvertTo-PtBaselineVersion $fixtureVersion
    $selection.Url = 'https://example.invalid/package.exe'
    Assert-Throws { & $realAssertInstaller $artifact } 'Non-official'
}

Write-Host "PASS: $script:passed offline baseline groups. Installer/process mutations were simulated. Evidence: $Workspace"
