# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

<#
.SYNOPSIS
Scripted, recoverable PowerToys comparison-baseline installation.
.DESCRIPTION
Dot-source this definitions-only library. Resolve/New functions do not change the
installation. Enter/Restore require explicit installation authority and the run's
private state-preservation/normal-shutdown adapters. See references/baseline-installation.md.
No automatic elevation, reboot, forced process termination or arbitrary uninstall command.
#>

function ConvertTo-PtBaselineVersion {
    param([Parameter(Mandatory)][string]$Version)
    if ($Version -notmatch '^v?(\d+\.\d+\.\d+)(?:\.(\d+))?$') { throw "Unsupported PowerToys version: $Version" }
    $revision = if ($Matches[2]) { $Matches[2] } else { '0' }
    ([version]"$($Matches[1]).$revision").ToString(4)
}

function Invoke-PtBaselineGitHub {
    param([Parameter(Mandatory)][string]$Endpoint)
    $text = & gh api --hostname github.com $Endpoint
    if ($LASTEXITCODE -ne 0) { throw "Official release lookup failed: $Endpoint (gh exit $LASTEXITCODE)" }
    ($text -join "`n") | ConvertFrom-Json -Depth 50
}

function Resolve-PtBaselineRelease {
    [CmdletBinding()]
    param(
        [ValidateSet('Stable', 'DevPreview')][string]$Channel = 'Stable',
        [string]$Version,
        [ValidateSet('x64', 'arm64')][string]$Architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant(),
        [ValidateSet('PerUser', 'PerMachine')][string]$Scope = 'PerUser'
    )
    $repo = 'repos/microsoft/PowerToys'
    if ($Version) {
        $normalized = ConvertTo-PtBaselineVersion $Version
        $tagVersion = if ($normalized.EndsWith('.0')) { $normalized.Substring(0, $normalized.Length - 2) } else { $normalized }
        $releases = @(Invoke-PtBaselineGitHub "$repo/releases/tags/v$tagVersion")
    }
    elseif ($Channel -eq 'Stable') {
        $releases = @(Invoke-PtBaselineGitHub "$repo/releases/latest")
    }
    else {
        # Bound discovery; absence is an acquisition limitation, not permission to use a CI/fork asset.
        $releases = @(Invoke-PtBaselineGitHub "$repo/releases?per_page=100") |
            Where-Object { $_.prerelease -and -not $_.draft } | Sort-Object published_at -Descending
    }
    foreach ($release in $releases) {
        if ($release.draft) { continue }
        if (-not $Version -and $Channel -eq 'Stable' -and $release.prerelease) { continue }
        $releaseVersion = ConvertTo-PtBaselineVersion ([string]$release.tag_name)
        if ($Version -and $releaseVersion -ne $normalized) { throw 'Release tag does not match the pinned version.' }
        $commit = Invoke-PtBaselineGitHub "$repo/commits/$([uri]::EscapeDataString($release.tag_name))"
        if ([string]$commit.sha -notmatch '^[0-9a-f]{40}$') { throw 'Release commit is not an immutable SHA.' }
        if (-not $Version -and $Channel -eq 'DevPreview') {
            $ancestry = Invoke-PtBaselineGitHub "$repo/compare/$($commit.sha)...main"
            if ($ancestry.status -notin @('ahead', 'identical')) { continue }
        }
        $prefix = if ($Scope -eq 'PerUser') { 'PowerToysUserSetup' } else { 'PowerToysSetup' }
        $assetVersion = ([string]$release.tag_name).TrimStart('v')
        $names = @(
            foreach ($text in @($assetVersion, $releaseVersion) | Select-Object -Unique) {
                "$prefix-$Architecture-$text.exe"
                "$prefix-$text-$Architecture.exe"
            }
        )
        $assets = @($release.assets | Where-Object { $_.name -in $names })
        if ($assets.Count -ne 1) { throw "Expected one exact $Scope/$Architecture installer in $($release.tag_name); found $($assets.Count)." }
        $asset = $assets[0]
        $expectedUrl = "https://github.com/microsoft/PowerToys/releases/download/$($release.tag_name)/$($asset.name)"
        if ($asset.browser_download_url -cne $expectedUrl) { throw 'Installer is not the exact official release asset URL.' }
        $digest = if ($asset.PSObject.Properties['digest']) { [string]$asset.digest } else { '' }
        if ($digest -and $digest -notmatch '^sha256:[0-9a-fA-F]{64}$') { throw 'Unsupported release asset digest.' }
        return [pscustomobject]@{
            Version = $releaseVersion; Channel = $(if ($release.prerelease) { 'DevPreview' } else { 'Stable' })
            Architecture = $Architecture; Scope = $Scope; Tag = $release.tag_name; Commit = $commit.sha
            AssetName = $asset.name; Url = $expectedUrl; Size = [long]$asset.size
            Digest = $digest; ReleaseId = $release.id; AssetId = $asset.id
        }
    }
    throw "No eligible official $Channel release found. Do not substitute another channel."
}

function Get-PtBaselineBinaryIdentity {
    param([Parameter(Mandatory)][string]$Path)
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $stream = [IO.File]::OpenRead($file.FullName)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'Not a PE executable.' }
        $stream.Position = 0x3c
        $header = $reader.ReadInt32()
        if ($header -lt 64 -or $header -gt $stream.Length - 6) { throw 'Invalid PE header.' }
        $stream.Position = $header
        if ($reader.ReadUInt32() -ne 0x4550) { throw 'Invalid PE signature.' }
        $architecture = switch ($reader.ReadUInt16()) {
            0x8664 { 'x64' }
            0xaa64 { 'arm64' }
            default { throw 'Unsupported PowerToys executable architecture.' }
        }
    }
    finally { $reader.Dispose(); $stream.Dispose() }
    [pscustomobject]@{
        Path = $file.FullName; Architecture = $architecture
        Version = ConvertTo-PtBaselineVersion $file.VersionInfo.FileVersion
        Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
}

function Get-PtBaselineRegistrations {
    param()
    if (-not $IsWindows) { throw 'PowerToys installation discovery requires Windows PowerShell 7.' }
    $entries = @(
        foreach ($scope in @('PerUser', 'PerMachine')) {
            $hive = if ($scope -eq 'PerUser') { [Microsoft.Win32.RegistryHive]::CurrentUser } else { [Microsoft.Win32.RegistryHive]::LocalMachine }
            foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
                try {
                    if ($null -eq $uninstall) { continue }
                    foreach ($name in $uninstall.GetSubKeyNames()) {
                        $key = $uninstall.OpenSubKey($name)
                        try {
                            $displayName = [string]$key.GetValue('DisplayName')
                            if ($displayName -notmatch '^PowerToys(?:\s|\(|$)') { continue }
                            if ([string]$key.GetValue('Publisher') -ne 'Microsoft Corporation') { throw 'Unrecognized PowerToys publisher.' }
                            [pscustomobject]@{
                                Scope = $scope; RegistrationId = $name; Key = "$hive\$view\$name"; Version = [string]$key.GetValue('DisplayVersion')
                                Location = [string]$key.GetValue('InstallLocation')
                                Kind = $(if ($key.GetValue('BundleCachePath')) { 'Bundle' } else { 'Msi' })
                            }
                        }
                        finally { $key.Dispose() }
                    }
                }
                finally { if ($uninstall) { $uninstall.Dispose() }; $base.Dispose() }
            }
        }
    )
    $entries
}

function Get-PtBaselineInstallation {
    [CmdletBinding()]
    param()
    $entries = @(
        foreach ($group in @(Get-PtBaselineRegistrations | Group-Object Scope, RegistrationId)) {
            # HKCU uninstall keys can be shared between the 32/64-bit registry views.
            $identities = @($group.Group | Select-Object Scope, RegistrationId, Version, Location, Kind -Unique)
            if ($identities.Count -ne 1) { throw 'Conflicting PowerToys registration views.' }
            $group.Group[0]
        }
    )
    $bundles = @($entries | Where-Object Kind -EQ Bundle)
    foreach ($msi in @($entries | Where-Object Kind -NE Bundle)) {
        if (@($bundles | Where-Object {
            # A per-user bundle can have its payload's MSI registration in HKLM.
            $sameLocation = if ($_.Location -and $msi.Location) {
                [IO.Path]::GetFullPath($_.Location).TrimEnd('\') -eq [IO.Path]::GetFullPath($msi.Location).TrimEnd('\')
            } else { $_.Scope -eq $msi.Scope }
            $sameLocation -and (ConvertTo-PtBaselineVersion $_.Version) -eq (ConvertTo-PtBaselineVersion $msi.Version)
        }).Count -ne 1) { throw 'Standalone or orphaned PowerToys MSI registration; no automatic switching.' }
    }
    $entries = $bundles
    $defaults = @(
        (Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.exe'),
        (Join-Path $env:ProgramFiles 'PowerToys\PowerToys.exe')
    )
    if ($entries.Count -gt 1) { throw 'Ambiguous PowerToys bundle registrations; no automatic switching.' }
    if ($entries.Count -eq 0) {
        if (@($defaults | Where-Object { Test-Path -LiteralPath $_ }).Count) { throw 'Unregistered PowerToys files require investigation before installation.' }
        return [pscustomobject]@{ Installed = $false; Version = ''; Architecture = ''; Scope = ''; Path = ''; Sha256 = '' }
    }
    $entry = $entries[0]
    $path = if ($entry.Location) { Join-Path $entry.Location 'PowerToys.exe' } elseif ($entry.Scope -eq 'PerUser') { $defaults[0] } else { $defaults[1] }
    if (@($defaults | Where-Object { $_ -ne $path -and (Test-Path -LiteralPath $_) }).Count) { throw 'Another PowerToys installation path exists.' }
    $identity = Get-PtBaselineBinaryIdentity $path
    if ($identity.Version -ne (ConvertTo-PtBaselineVersion $entry.Version)) { throw 'Registry and installed executable versions disagree.' }
    [pscustomobject]@{
        Installed = $true; Version = $identity.Version; Architecture = $identity.Architecture
        Scope = $entry.Scope; Path = $identity.Path; Sha256 = $identity.Sha256; RegistryKey = $entry.Key
    }
}

function Test-PtBaselineInstallationMatch {
    param($Actual, $Expected, [switch]$Exact)
    if (-not $Actual.Installed) { return ($Expected.PSObject.Properties['Installed'] -and -not $Expected.Installed) }
    if ($Expected.PSObject.Properties['Installed'] -and -not $Expected.Installed) { return $false }
    $match = $Actual.Version -eq $Expected.Version -and $Actual.Scope -eq $Expected.Scope -and $Actual.Architecture -eq $Expected.Architecture
    if ($Exact) { $match = $match -and $Actual.Path -eq $Expected.Path -and $Actual.Sha256 -eq $Expected.Sha256 }
    [bool]$match
}

function New-PtBaselineInstallationPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Baseline)
    $original = Get-PtBaselineInstallation
    if ($original.Installed -and $original.Scope -ne $Baseline.Scope) { throw 'Cross-scope switching is not supported; select the existing scope.' }
    [pscustomobject]@{
        Schema = 'pt-baseline-plan/v1'; Original = $original; Baseline = $Baseline
        SwitchRequired = -not (Test-PtBaselineInstallationMatch $original $Baseline)
        CreatedUtc = [datetime]::UtcNow.ToString('o')
    }
}

function Assert-PtBaselineInstaller {
    param([Parameter(Mandatory)]$Artifact)
    $file = Get-Item -LiteralPath $Artifact.Path -ErrorAction Stop
    if ($file.Length -ne $Artifact.Selection.Size -or (Get-FileHash -LiteralPath $file.FullName).Hash -ne $Artifact.Sha256) { throw 'Cached installer hash/length changed.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw 'Installer must have a valid Microsoft Authenticode signature.'
    }
    if ((ConvertTo-PtBaselineVersion $file.VersionInfo.FileVersion) -ne $Artifact.Selection.Version) { throw 'Installer file version does not match release selection.' }
    # Burn launchers can be x86 even for ARM64 payloads. Architecture is bound by the exact release asset, not its PE header.
    $selection = $Artifact.Selection
    $prefix = if ($selection.Scope -eq 'PerUser') { 'PowerToysUserSetup' } elseif ($selection.Scope -eq 'PerMachine') { 'PowerToysSetup' } else { throw 'Invalid installer scope.' }
    if ($selection.Architecture -notin @('x64', 'arm64')) { throw 'Invalid installer architecture.' }
    $versionText = ([string]$selection.Tag).TrimStart('v')
    $names = @(foreach ($text in @($versionText, $selection.Version) | Select-Object -Unique) {
        "$prefix-$($selection.Architecture)-$text.exe"
        "$prefix-$text-$($selection.Architecture).exe"
    })
    if ((ConvertTo-PtBaselineVersion $versionText) -ne $selection.Version -or $selection.AssetName -notin $names) {
        throw 'Installer filename does not match the selected version/architecture/scope.'
    }
    if ($selection.Url -cne "https://github.com/microsoft/PowerToys/releases/download/$($selection.Tag)/$($selection.AssetName)") { throw 'Non-official installer source.' }
    if ($selection.Digest -and $Artifact.Sha256 -ne $selection.Digest.Substring(7)) { throw 'Installer does not match the release asset digest.' }
}

function Save-PtBaselineInstaller {
    param([Parameter(Mandatory)]$Selection, [Parameter(Mandatory)][string]$Directory)
    [void][IO.Directory]::CreateDirectory($Directory)
    if ([IO.Path]::GetFileName($Selection.AssetName) -cne $Selection.AssetName) { throw 'Invalid installer asset name.' }
    $path = Join-Path $Directory $Selection.AssetName
    if (-not (Test-Path -LiteralPath $path)) {
        if ($Selection.Url -cne "https://github.com/microsoft/PowerToys/releases/download/$($Selection.Tag)/$($Selection.AssetName)") { throw 'Non-official download URL.' }
        Invoke-WebRequest -Uri $Selection.Url -OutFile $path -ErrorAction Stop
    }
    $artifact = [pscustomobject]@{ Path = $path; Selection = $Selection; Sha256 = (Get-FileHash -LiteralPath $path).Hash }
    Assert-PtBaselineInstaller $artifact
    $artifact
}

function Get-PtBaselineBootState {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager')
    if ($null -eq $key) { throw 'Cannot read pending file-replacement state.' }
    try { $pendingFiles = $key.GetValue('PendingFileRenameOperations') } finally { $key.Dispose() }
    [pscustomobject]@{
        Boot = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
        RebootPending = [bool](
            (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction Stop) -or
            (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction Stop) -or
            $pendingFiles
        )
    }
}

function Assert-PtBaselineQuiescent {
    # Do not enumerate titles/command lines or stop processes. The caller owns normal, identity-checked shutdown.
    $processes = @(Get-Process -Name 'PowerToys*', 'Microsoft.CmdPal*' -ErrorAction SilentlyContinue)
    if ($processes.Count) { throw "PowerToys/companion processes remain (PIDs: $($processes.Id -join ', ')); refuse installer execution." }
}

function Confirm-PtBaselineRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Installation, [Parameter(Mandatory)][int]$ProcessId)
    $process = Get-Process -Id $ProcessId -ErrorAction Stop
    if ($process.Path -ne $Installation.Path) { throw 'Runtime is not the installed Runner executable.' }
    $identity = Get-PtBaselineBinaryIdentity $process.Path
    if ($identity.Version -ne $Installation.Version -or $identity.Sha256 -ne $Installation.Sha256) { throw 'Runtime executable changed after installation observation.' }
    [pscustomobject]@{ ProcessId = $ProcessId; StartTimeUtc = $process.StartTime.ToUniversalTime().ToString('o'); Binary = $identity }
}

function New-PtBaselinePrivateDirectory {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $full) { throw 'Use a new private recovery directory, not an existing run.' }
    $local = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\') + '\'
    if (-not $full.StartsWith($local, [StringComparison]::OrdinalIgnoreCase)) { throw 'Recovery must stay under LOCALAPPDATA, outside the review delivery.' }
    for ($parent = [IO.DirectoryInfo]::new($full).Parent; $null -ne $parent; $parent = $parent.Parent) {
        if ($parent.Exists -and ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Recovery path has a reparse-point ancestor.' }
    }
    $directory = [IO.Directory]::CreateDirectory($full)
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    [IO.FileSystemAclExtensions]::SetAccessControl($directory, $acl)
    $full
}

function Save-PtBaselineSession {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)][string]$Phase)
    $Session.Sequence++
    $Session.Phase = $Phase
    $Session.UpdatedUtc = [datetime]::UtcNow.ToString('o')
    $path = Join-Path $Session.Directory ('receipt-{0:D5}.json' -f $Session.Sequence)
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Session | ConvertTo-Json -Depth 50))
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    $Session.PreviousSha256 = (Get-FileHash -LiteralPath $path).Hash
}

function Get-PtBaselineSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)
    $previous = ''
    $sequence = 0
    $session = $null
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -Filter 'receipt-*.json' -File | Sort-Object Name)) {
        $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 50
        if ($record.Schema -ne 'pt-baseline-session/v1' -or $record.Sequence -ne (++$sequence) -or $record.PreviousSha256 -ne $previous -or $record.Directory -ne [IO.Path]::GetFullPath($Directory)) {
            throw 'Invalid or relocated baseline recovery receipt chain.'
        }
        $previous = (Get-FileHash -LiteralPath $file.FullName).Hash
        $session = $record
    }
    if ($null -eq $session) { throw 'No baseline recovery receipt found.' }
    $session.PreviousSha256 = $previous
    $session
}

function Invoke-PtBaselineInstaller {
    param([Parameter(Mandatory)]$Session, [Parameter(Mandatory)]$Artifact, [ValidateSet('Install', 'Uninstall', 'Repair')][string]$Operation)
    Assert-PtBaselineInstaller $Artifact
    Assert-PtBaselineQuiescent
    if ((Get-PtBaselineBootState).RebootPending) { throw 'A reboot is pending; do not execute another installer.' }
    $Session.InstallationTouched = $true
    $Session.Installer = [pscustomobject]@{ Operation = $Operation; Path = $Artifact.Path; ProcessId = 0; StartTimeUtc = ''; Completed = $false; LaunchFailed = $false; ExitCode = $null }
    Save-PtBaselineSession $Session 'InstallerStarting'
    $log = Join-Path $Session.Directory ("installer-$($Session.Sequence)-$Operation.log")
    $arguments = @("/$($Operation.ToLowerInvariant())", '/quiet', '/norestart', '/log', "`"$log`"")
    if ($Operation -ne 'Uninstall' -and $Session.Plan.Original.Installed) {
        $installFolder = [IO.Path]::GetDirectoryName($Session.Plan.Original.Path)
        if ($installFolder.Contains('"')) { throw 'Invalid original installation directory.' }
        $arguments += "InstallFolder=`"$installFolder`""
    }
    try { $process = Start-Process -FilePath $Artifact.Path -ArgumentList $arguments -PassThru -ErrorAction Stop }
    catch {
        $Session.Installer.LaunchFailed = $true
        $Session.Installer.Completed = $true
        Save-PtBaselineSession $Session 'InstallerLaunchFailed'
        throw
    }
    $Session.Installer.ProcessId = $process.Id
    $Session.Installer.StartTimeUtc = $process.StartTime.ToUniversalTime().ToString('o')
    Save-PtBaselineSession $Session 'InstallerRunning'
    if (-not $process.WaitForExit(600000)) { throw 'Installer is still running; retain recovery and do not launch another installer.' }
    $process.Refresh()
    $Session.Installer.Completed = $true
    $Session.Installer.ExitCode = $process.ExitCode
    Save-PtBaselineSession $Session 'InstallerCompleted'
    $afterBoot = Get-PtBaselineBootState
    if ($process.ExitCode -in @(3010, 1641) -or $afterBoot.RebootPending) {
        $Session.RebootRequired = $true
        $Session.Boot = $afterBoot.Boot
        Save-PtBaselineSession $Session 'RebootRequired'
        throw 'Installer requires a reboot; no automatic reboot or further mutation.'
    }
    if ($process.ExitCode -ne 0) { throw "PowerToys $Operation failed: exit $($process.ExitCode)." }
}

function Enter-PtBaselineInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][scriptblock]$PreserveState,
        [Parameter(Mandatory)][scriptblock]$Quiesce,
        [Parameter(Mandatory)][scriptblock]$StartRuntime,
        [switch]$AllowInstall,
        [switch]$AllowMachineScope
    )
    if ($Plan.Schema -ne 'pt-baseline-plan/v1') { throw 'Invalid baseline plan.' }
    $directoryPath = New-PtBaselinePrivateDirectory $Directory
    $session = [pscustomobject]@{
        Schema = 'pt-baseline-session/v1'; Directory = $directoryPath; Sequence = 0; PreviousSha256 = ''
        Phase = 'Prepared'; UpdatedUtc = ''; Plan = $Plan; BaselineInstaller = $null; OriginalInstaller = $null
        StateReceipt = ''; StateReceiptSha256 = ''; StateTouched = $false; InstallationTouched = $false
        Installer = $null; RebootRequired = $false; Boot = ''; Runtime = $null
        Ready = $false; SafeForTarget = $true; Restored = $false; Error = ''
    }
    Save-PtBaselineSession $session 'Prepared'
    try {
        if (-not (Test-PtBaselineInstallationMatch (Get-PtBaselineInstallation) $Plan.Original -Exact)) { throw 'Installation changed after planning.' }
        if ($Plan.SwitchRequired) {
            if (-not $AllowInstall) { throw 'Installation authority was not supplied.' }
            if ($Plan.Baseline.Scope -eq 'PerMachine') {
                $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
                if (-not $AllowMachineScope -or -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Machine scope requires explicit authority and an already elevated session.' }
            }
            $boot = Get-PtBaselineBootState
            if ($boot.RebootPending) { throw 'Reboot pending before baseline preparation.' }
            $session.Boot = $boot.Boot
            $session.BaselineInstaller = Save-PtBaselineInstaller $Plan.Baseline (Join-Path $directoryPath 'baseline')
            if ($Plan.Original.Installed) {
                $rollback = Resolve-PtBaselineRelease -Version $Plan.Original.Version -Architecture $Plan.Original.Architecture -Scope $Plan.Original.Scope
                $session.OriginalInstaller = Save-PtBaselineInstaller $rollback (Join-Path $directoryPath 'original')
            }
            Save-PtBaselineSession $session 'InstallersVerified'
        }
        $stateDirectory = Join-Path $directoryPath 'state'
        [void][IO.Directory]::CreateDirectory($stateDirectory)
        $receipt = & $PreserveState $stateDirectory
        if ($receipt -isnot [string] -or -not [IO.Path]::GetFullPath($receipt).StartsWith("$stateDirectory\", [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
            throw 'PreserveState must return one existing immutable receipt file inside the private state directory.'
        }
        $session.StateReceipt = [IO.Path]::GetFullPath($receipt)
        $session.StateReceiptSha256 = (Get-FileHash -LiteralPath $receipt).Hash
        $session.StateTouched = $true
        $session.SafeForTarget = $false
        Save-PtBaselineSession $session 'StatePreserved'
        if ($Plan.SwitchRequired) {
            & $Quiesce $session | Out-Null
            Assert-PtBaselineQuiescent
            if (-not (Test-PtBaselineInstallationMatch (Get-PtBaselineInstallation) $Plan.Original -Exact)) { throw 'Installation changed before replacement.' }
            Assert-PtBaselineInstaller $session.BaselineInstaller
            if ($Plan.Original.Installed) {
                Invoke-PtBaselineInstaller $session $session.OriginalInstaller Uninstall
                if ((Get-PtBaselineInstallation).Installed) { throw 'Original installation remains after uninstall.' }
            }
            Invoke-PtBaselineInstaller $session $session.BaselineInstaller Install
        }
        $installed = Get-PtBaselineInstallation
        if (-not (Test-PtBaselineInstallationMatch $installed $Plan.Baseline)) { throw 'Actual installation does not match the selected baseline.' }
        $runtimeId = & $StartRuntime $session
        $session.Runtime = Confirm-PtBaselineRuntime -Installation $installed -ProcessId $runtimeId
        $session.Ready = $true
        Save-PtBaselineSession $session 'Ready'
    }
    catch {
        $session.Error = $_.Exception.Message
        Save-PtBaselineSession $session $(if ($session.SafeForTarget) { 'Unavailable' } else { 'RecoveryRequired' })
    }
    $session
}

function Restore-PtBaselineInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][scriptblock]$Quiesce,
        [Parameter(Mandatory)][scriptblock]$RestoreState,
        [Parameter(Mandatory)][scriptblock]$VerifyState
    )
    $session = Get-PtBaselineSession $Directory
    try {
        if ($session.Restored) {
            if (-not (Test-PtBaselineInstallationMatch (Get-PtBaselineInstallation) $session.Plan.Original -Exact)) { throw 'Original installation changed after restoration.' }
            return $session
        }
        if (-not $session.StateTouched) { return $session }
        if ((Get-FileHash -LiteralPath $session.StateReceipt).Hash -ne $session.StateReceiptSha256) { throw 'Private original-state receipt changed.' }
        if ($session.Installer -and -not $session.Installer.Completed) { throw 'Interrupted installer has no recorded exit status; explicit recovery is required.' }
        if ($session.RebootRequired) {
            $boot = Get-PtBaselineBootState
            if ($boot.Boot -eq $session.Boot -or $boot.RebootPending) { throw 'Required reboot has not completed; recovery remains pending.' }
            $session.RebootRequired = $false
        }
        if ($session.InstallationTouched) {
            if ($session.Plan.Original.Installed) { Assert-PtBaselineInstaller $session.OriginalInstaller }
            Assert-PtBaselineInstaller $session.BaselineInstaller
            & $Quiesce $session | Out-Null
            Assert-PtBaselineQuiescent
            $current = Get-PtBaselineInstallation
            if ($current.Installed -and -not (Test-PtBaselineInstallationMatch $current $session.Plan.Original)) {
                if (-not (Test-PtBaselineInstallationMatch $current $session.Plan.Baseline)) { throw 'Unexpected installation appeared; refuse to uninstall it.' }
                Invoke-PtBaselineInstaller $session $session.BaselineInstaller Uninstall
                $current = Get-PtBaselineInstallation
                if ($current.Installed) { throw 'Baseline remains after uninstall.' }
            }
            if ($session.Plan.Original.Installed) {
                $operation = if ($current.Installed) { 'Repair' } else { 'Install' }
                Invoke-PtBaselineInstaller $session $session.OriginalInstaller $operation
            }
        }
        if (-not (Test-PtBaselineInstallationMatch (Get-PtBaselineInstallation) $session.Plan.Original -Exact)) { throw 'Original installation identity was not restored.' }
        & $RestoreState $session.StateReceipt $session | Out-Null
        $verified = & $VerifyState $session.StateReceipt $session
        if ($verified -isnot [bool] -or -not $verified) { throw 'Original configuration/runtime restoration was not independently verified.' }
        $session.Ready = $false
        $session.Restored = $true
        $session.SafeForTarget = $true
        Save-PtBaselineSession $session 'Restored'
    }
    catch {
        $session.Error = $_.Exception.Message
        $session.SafeForTarget = $false
        Save-PtBaselineSession $session 'RecoveryRequired'
    }
    $session
}

function Invoke-PtBaselineComparison {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$AcquirePlan,
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][scriptblock]$PreserveState,
        [Parameter(Mandatory)][scriptblock]$Quiesce,
        [Parameter(Mandatory)][scriptblock]$StartRuntime,
        [Parameter(Mandatory)][scriptblock]$CaptureBaseline,
        [Parameter(Mandatory)][scriptblock]$RestoreState,
        [Parameter(Mandatory)][scriptblock]$VerifyState,
        [Parameter(Mandatory)][scriptblock]$CaptureTarget,
        [switch]$AllowInstall,
        [switch]$AllowMachineScope
    )
    $session = $null
    $directoryExisted = Test-Path -LiteralPath $Directory
    $result = [ordered]@{ BaselineStatus = 'Unavailable'; Baseline = $null; BaselineError = ''; Recovery = $null; TargetExecuted = $false; Target = $null; TargetError = '' }
    try {
        if ($directoryExisted) { throw 'Comparison requires a new recovery directory; an existing session will not be adopted.' }
        $plan = & $AcquirePlan
        $session = Enter-PtBaselineInstallation -Plan $plan -Directory $Directory -PreserveState $PreserveState -Quiesce $Quiesce -StartRuntime $StartRuntime -AllowInstall:$AllowInstall -AllowMachineScope:$AllowMachineScope
        if ($session.Ready) {
            $baseline = & $CaptureBaseline $session
            if ($baseline.Status -notin @('Reproduced', 'NotReproduced', 'Unavailable')) { throw 'Baseline capture must return Reproduced, NotReproduced or Unavailable.' }
            $result.BaselineStatus = $baseline.Status
            $result.Baseline = $baseline
        }
        else { $result.BaselineError = $session.Error }
    }
    catch { $result.BaselineError = $_.Exception.Message }
    finally {
        # Recover from a controller exception after a durable checkpoint, too.
        if (-not $directoryExisted -and (Test-Path -LiteralPath (Join-Path $Directory 'receipt-00001.json'))) {
            try { $result.Recovery = Restore-PtBaselineInstallation -Directory $Directory -Quiesce $Quiesce -RestoreState $RestoreState -VerifyState $VerifyState }
            catch { $result.Recovery = [pscustomobject]@{ SafeForTarget = $false; Error = $_.Exception.Message; Directory = $Directory } }
            $session = $result.Recovery
        }
    }
    if ($null -eq $session -or $session.SafeForTarget) {
        $result.TargetExecuted = $true
        try { $result.Target = & $CaptureTarget ([pscustomobject]$result) }
        catch { $result.TargetError = $_.Exception.Message }
    }
    [pscustomobject]$result
}
