#requires -Version 7.2
# Copyright (c) Microsoft Corporation. Licensed under the MIT license.
foreach($dependency in 'pt-file-set-snapshot','pt-settings-session','pt-shortcut-recorder'){
    . "$PSScriptRoot\$dependency.ps1"
}

function Read-PtTextExtractorRecovery {
    param([Parameter(Mandatory)][string]$RecoveryPath)
    Assert-PtReportNoLink $RecoveryPath
    $secure=[IO.File]::ReadAllText($RecoveryPath)|ConvertTo-SecureString
    $text=[Net.NetworkCredential]::new('', $secure).Password
    $state=ConvertFrom-PtReportJson $text
    if($state.Schema -cne 'PtTextExtractorState.v1'){throw 'Unsupported Text Extractor recovery record.'}
    foreach($snapshot in $state.Original,$state.Expected){
        $null=ConvertTo-PtFileSetSnapshotMap $snapshot 1MB
        if(($snapshot.FileNames -join ',') -cne 'settings.json' -or $snapshot.FileState.Files.Count -ne 1){
            throw 'Text Extractor requires an existing settings.json baseline.'
        }
    }
    if($state.Original.FileState.Path -cne $state.Expected.FileState.Path){throw 'Recovery roots differ.'}
    $state
}

function Write-PtTextExtractorRecovery {
    param([Parameter(Mandatory)][string]$RecoveryPath,[Parameter(Mandatory)]$State,[switch]$Create)
    Assert-PtReportNoLink $RecoveryPath
    $encrypted=(ConvertTo-Json $State -Depth 20 -Compress)|ConvertTo-SecureString -AsPlainText -Force|ConvertFrom-SecureString
    $pending="$RecoveryPath.$([guid]::NewGuid().ToString('N')).pending"
    try{
        $bytes=[Text.Encoding]::UTF8.GetBytes($encrypted)
        $file=[IO.File]::Open($pending,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$file.Write($bytes,0,$bytes.Length);$file.Flush($true)}finally{$file.Dispose()}
        [IO.File]::Move($pending,$RecoveryPath,(-not $Create))
    }finally{if([IO.File]::Exists($pending)){[IO.File]::Delete($pending)}}
}

function Get-PtTextExtractorDocument {
    param([Parameter(Mandatory)]$Snapshot)
    $bytes=[Convert]::FromBase64String($Snapshot.FileState.Files[0].Base64)
    $text=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
    $document=ConvertFrom-PtReportJson $text
    if($document.name -cne 'TextExtractor' -or $document.properties.PreferredLanguage -isnot [string]){
        throw 'Unsupported Text Extractor settings document.'
    }
    $document
}

function New-PtTextExtractorState {
    <#
    .SYNOPSIS
    Preserve the complete existing module file before navigation/mutation, encrypted for this user.
    .NOTES
    RecoveryPath must be in an existing private directory outside the run evidence workspace.
    Returns metadata only. Do not publish the encrypted journal or private decoded snapshots.
    #>
    param([Parameter(Mandatory)][string]$SettingsPath,[Parameter(Mandatory)][string]$RecoveryPath)
    if(-not [IO.Path]::IsPathFullyQualified($SettingsPath) -or [IO.Path]::GetFileName($SettingsPath) -cne 'settings.json' -or
        -not [IO.Path]::IsPathFullyQualified($RecoveryPath) -or -not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($RecoveryPath))){
        throw 'Supply an absolute settings.json path and an existing private recovery directory.'
    }
    if(Test-Path -LiteralPath $RecoveryPath){throw 'Recovery record already exists; retain its original baseline.'}
    $attempt=Get-PtActiveVerificationAttempt
    if($attempt -and [IO.Path]::GetFullPath($RecoveryPath).StartsWith(
        "$($attempt.Run.Workspace.TrimEnd('\'))\",[StringComparison]::OrdinalIgnoreCase)){
        throw 'Private recovery must be outside the evidence workspace.'
    }
    $before=Get-PtFileSetSnapshot -Path ([IO.Path]::GetDirectoryName($SettingsPath)) -FileNames @('settings.json') -MaxBytes 1MB
    if($before.FileState.Files.Count -ne 1){throw 'An absent original requires an isolated fixture; no product file was created.'}
    $document=Get-PtTextExtractorDocument $before
    Assert-PtShortcutBinding $document.properties.ActivationShortcut
    $state=[pscustomobject]@{Schema='PtTextExtractorState.v1';Original=$before;Expected=$before;Pending=$null;Phase='Captured'}
    Write-PtTextExtractorRecovery -RecoveryPath $RecoveryPath -State $state -Create
    [pscustomobject]@{RecoveryPath=$RecoveryPath;OriginalSha256=$before.FileState.Files[0].Sha256;Phase=$state.Phase}
}

function Get-PtTextExtractorOwnedState {
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][AllowEmptyString()][string]$PreferredLanguage)
    $current=Get-PtFileSetSnapshot -Path $State.Original.FileState.Path -FileNames @('settings.json') -MaxBytes 1MB
    if($current.FileState.Files.Count -ne 1){throw 'Settings disappeared during the declared UI action.'}
    $expected=Get-PtTextExtractorDocument $State.Expected
    $actual=Get-PtTextExtractorDocument $current
    if($actual.version -cnotin @($expected.version,'1.0')){throw 'Unexpected settings version after UI action.'}
    $expected.properties.PreferredLanguage=$PreferredLanguage
    $expected.version=$actual.version
    $left=[System.Text.Json.Nodes.JsonNode]::Parse((ConvertTo-Json $expected -Depth 15))
    $right=[System.Text.Json.Nodes.JsonNode]::Parse((ConvertTo-Json $actual -Depth 15))
    if(-not [System.Text.Json.Nodes.JsonNode]::DeepEquals($left,$right)){
        throw 'UI post-state differs outside the declared preference/version; recovery retained.'
    }
    $current
}

function Wait-PtTextExtractorOwnedState {
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][AllowEmptyString()][string]$PreferredLanguage)
    $settled=@{Hash='';Since=[Diagnostics.Stopwatch]::StartNew();Snapshot=$null}
    Wait-PtCondition -Description 'declared OCR settings write settled' -TimeoutSeconds 5 -PollMilliseconds 100 -Probe {
        $current=Get-PtTextExtractorOwnedState -State $State -PreferredLanguage $PreferredLanguage
        $hash=$current.FileState.Files[0].Sha256
        if($hash -cne $settled.Hash){$settled.Hash=$hash;$settled.Since.Restart()}
        if($settled.Since.ElapsedMilliseconds -ge 700){$current}
    }
}

function Invoke-PtTextExtractorPreferenceChange {
    <#
    .SYNOPSIS
    Persist intended ownership before one UI action and seal only its complete validated post-state.
    .NOTES
    The callback must perform a synchronous UI selection/save and await its persisted value.
    Exceptions do not replay input. A matching declared write is retained for cleanup even on error.
    #>
    param([Parameter(Mandatory)][string]$RecoveryPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$PreferredLanguage,
        [Parameter(Mandatory)][scriptblock]$Action,[object[]]$ArgumentList=@())
    $state=Read-PtTextExtractorRecovery $RecoveryPath
    if($state.Pending){throw 'Resolve the pending action before another mutation.'}
    $current=Get-PtFileSetSnapshot -Path $state.Expected.FileState.Path -FileNames @('settings.json') -MaxBytes 1MB
    if($current.FileState.Files[0].Sha256 -cne $state.Expected.FileState.Files[0].Sha256){throw 'Settings changed outside the transaction; no UI action issued.'}
    $state.Pending=[pscustomobject]@{PreferredLanguage=$PreferredLanguage}
    Write-PtTextExtractorRecovery $RecoveryPath $state
    $failure=$null
    try{& $Action @ArgumentList|Out-Null}catch{$failure=$_}
    try{
        $current=Get-PtFileSetSnapshot -Path $state.Expected.FileState.Path -FileNames @('settings.json') -MaxBytes 1MB
        if($failure -and $current.FileState.Files[0].Sha256 -ceq $state.Expected.FileState.Files[0].Sha256){
            $state.Pending=$null
        }else{
            $state.Expected=Wait-PtTextExtractorOwnedState -State $state -PreferredLanguage $PreferredLanguage
            $state.Pending=$null;$state.Phase='Changed'
        }
        Write-PtTextExtractorRecovery $RecoveryPath $state
    }catch{
        if($failure){$failure.Exception.Data['PostStateFailure']=$_.Exception.Message}else{$failure=$_}
    }
    if($failure){$failure.Exception.Data['TextExtractorRecoveryPath']=$RecoveryPath;throw $failure}
    [pscustomobject]@{RecoveryPath=$RecoveryPath;ExpectedSha256=$state.Expected.FileState.Files[0].Sha256;Phase=$state.Phase}
}

function Restore-PtTextExtractorFile {
    param([Parameter(Mandatory)][string]$RecoveryPath)
    $state=Read-PtTextExtractorRecovery $RecoveryPath
    if($state.Pending){
        $current=Get-PtFileSetSnapshot -Path $state.Expected.FileState.Path -FileNames @('settings.json') -MaxBytes 1MB
        if($current.FileState.Files[0].Sha256 -cne $state.Expected.FileState.Files[0].Sha256){
            $state.Expected=Wait-PtTextExtractorOwnedState -State $state -PreferredLanguage $state.Pending.PreferredLanguage
        }
        $state.Pending=$null
        Write-PtTextExtractorRecovery $RecoveryPath $state
    }
    $receipt=Restore-PtFileSetSnapshot -Snapshot $state.Original -ExpectedState $state.Expected -OwnedFileNames @('settings.json') -MaxBytes 1MB
    $state.Expected=$state.Original;$state.Phase='FileRestored'
    Write-PtTextExtractorRecovery $RecoveryPath $state
    $receipt
}

function Set-PtTextExtractorPage {
    param([Parameter(Mandatory)]$SettingsTarget,[Parameter(Mandatory)][string]$Page)
    Assert-PtWindowIdentity $SettingsTarget
    $item=Resolve-PtUiElement -Hwnd $SettingsTarget.hwnd -AutomationId $Page -ControlType ListItem
    $item.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Wait-PtCondition -Description "Settings page $Page" -Probe {
        (Read-PtSettingsUiState $SettingsTarget.hwnd).PageAutomationId -ceq $Page
    }|Out-Null
}

function Restore-PtTextExtractorState {
    <#
    .SYNOPSIS
    Restore exact file bytes, discard the stale page and verify the recreated Settings model by UI writeback.
    .NOTES
    Caller owns the shared Settings/desktop baseline. No process is closed or restarted.
    Uses a real unchanged-shortcut Save as a cache oracle, not a language dropdown caption.
    #>
    param([Parameter(Mandatory)][string]$RecoveryPath,[Parameter(Mandatory)]$SettingsTarget,
        [Parameter(Mandatory)][string]$Workspace)
    $state=Read-PtTextExtractorRecovery $RecoveryPath
    $original=Get-PtTextExtractorDocument $state.Original
    $settingsPath=Join-Path $state.Original.FileState.Path 'settings.json'
    Set-PtTextExtractorPage -SettingsTarget $SettingsTarget -Page GeneralNavItem
    Restore-PtTextExtractorFile $RecoveryPath|Out-Null
    $state=Read-PtTextExtractorRecovery $RecoveryPath
    $null=Wait-PtTextExtractorOwnedState -State $state -PreferredLanguage $original.properties.PreferredLanguage
    Set-PtTextExtractorPage -SettingsTarget $SettingsTarget -Page TextExtractorNavItem
    $shortcut=Get-PtShortcutSnapshot -Hwnd $SettingsTarget.hwnd -PageAutomationId TextExtractorNavItem `
        -SettingsPath $settingsPath -PropertyPath @('properties','ActivationShortcut') -Workspace $Workspace `
        -WithinAutomationId TextExtractorActivationShortcut
    Invoke-PtTextExtractorPreferenceChange -RecoveryPath $RecoveryPath -PreferredLanguage $original.properties.PreferredLanguage `
        -ArgumentList @($shortcut) -Action {
            param($snapshot)
            $save=Set-PtShortcutBinding -Snapshot $snapshot -Binding $snapshot.Original -CommitUnchanged
            if(-not $save.Committed -or $save.Changed){throw 'The unchanged-shortcut cache probe did not commit unchanged fields.'}
        }|Out-Null
    Set-PtTextExtractorPage -SettingsTarget $SettingsTarget -Page GeneralNavItem
    $receipt=Restore-PtTextExtractorFile $RecoveryPath
    $state=Read-PtTextExtractorRecovery $RecoveryPath
    $null=Wait-PtTextExtractorOwnedState -State $state -PreferredLanguage $original.properties.PreferredLanguage
    $state.Phase='Verified'
    Write-PtTextExtractorRecovery $RecoveryPath $state
    [pscustomobject]@{RecoveryPath=$RecoveryPath;FileRestored=$receipt.SelectedFilesMatchBaseline
        SettingsWritebackMatched=$true;ShortcutUnchanged=$true;Phase=$state.Phase}
}
