# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.
#requires -Version 7.2
. "$PSScriptRoot\pt-file-set-snapshot.ps1"
. "$PSScriptRoot\pt-verification-report.ps1"

function Read-PtRegistryPreviewFileState {
    <#.SYNOPSIS
    Load private original/expected placement snapshots after ordinary controller exit.
    #>
    param([Parameter(Mandatory)][string]$ReceiptPath)
    Assert-PtReportNoLink $ReceiptPath
    $receipt=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($ReceiptPath))
    if($receipt.Schema -cne 'PtRegistryPreviewFiles.v1' -or
        $receipt.Id -cnotmatch '^[a-f0-9]{32}$' -or
        [IO.Path]::GetFileName($ReceiptPath) -cne "registry-preview-$($receipt.Id).json"){
        throw 'Invalid Registry Preview file-state receipt.'
    }
    $directory=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ReceiptPath))
    foreach($kind in 'Original','Expected'){
        $record=$receipt.$kind
        if($record.Name -cnotmatch ('^'+$receipt.Id+'-[a-f0-9]{32}\.json$')){
            throw 'Invalid Registry Preview private snapshot name.'
        }
        $path=Join-Path $directory $record.Name
        Assert-PtReportNoLink $path
        if((Get-FileHash -LiteralPath $path).Hash -cne $record.Sha256){throw 'Registry Preview private snapshot hash mismatch.'}
        $snapshot=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($path))
        ConvertTo-PtFileSetSnapshotMap -Snapshot $snapshot -MaxBytes 1MB|Out-Null
        if($snapshot.FileState.Path -cne $receipt.ModuleDirectory -or
            ($snapshot.FileNames -join '|') -cne 'settings.json|app-placement.json'){
            throw 'Registry Preview file-state scope changed.'
        }
        $receipt|Add-Member -NotePropertyName "${kind}State" -NotePropertyValue $snapshot
    }
    $receipt
}

function New-PtRegistryPreviewFileState {
    <#.SYNOPSIS
    Persist selected original bytes/existence before editor startup. No process ownership is inferred.
    .NOTES
    PrivateDirectory must be caller-owned local storage outside the public run archive.
    The caller establishes quiescent writers. Do not return this private state as report evidence.
    #>
    param([Parameter(Mandatory)][string]$ModuleDirectory,
        [Parameter(Mandatory)][string]$PrivateDirectory)
    Assert-PtReportNoLink $PrivateDirectory
    if(-not [IO.Directory]::Exists($PrivateDirectory)){throw 'Create the private recovery directory before capture.'}
    $snapshot=Get-PtFileSetSnapshot -Path $ModuleDirectory -FileNames @('settings.json','app-placement.json') -MaxBytes 1MB
    $id=[guid]::NewGuid().ToString('N')
    $name="$id-$([guid]::NewGuid().ToString('N')).json"
    $path=Join-Path $PrivateDirectory $name
    [IO.File]::WriteAllText($path,(ConvertTo-Json $snapshot -Depth 12),[Text.UTF8Encoding]::new($false))
    $record=@{Name=$name;Sha256=(Get-FileHash -LiteralPath $path).Hash}
    $receipt=@{Schema='PtRegistryPreviewFiles.v1';Id=$id;ModuleDirectory=$snapshot.FileState.Path
        Original=$record;Expected=$record}
    $receiptPath=Join-Path $PrivateDirectory "registry-preview-$id.json"
    [IO.File]::WriteAllText($receiptPath,(ConvertTo-Json $receipt -Depth 8),[Text.UTF8Encoding]::new($false))
    Read-PtRegistryPreviewFileState -ReceiptPath $receiptPath|Out-Null
    $receiptPath
}

function Set-PtRegistryPreviewExpectedFiles {
    <#.SYNOPSIS
    Persist an attributed post-state before rollback; never replace the original.
    .NOTES
    Caller supplies a snapshot only after its declared editor writer is quiescent and its writes
    are attributable. A fresh observation alone is not ownership or conflict-recovery authority.
    #>
    param([Parameter(Mandatory)][string]$ReceiptPath,[Parameter(Mandatory)]$ExpectedState)
    $state=Read-PtRegistryPreviewFileState -ReceiptPath $ReceiptPath
    ConvertTo-PtFileSetSnapshotMap -Snapshot $ExpectedState -MaxBytes 1MB|Out-Null
    if($ExpectedState.FileState.Path -cne $state.ModuleDirectory -or
        ($ExpectedState.FileNames -join '|') -cne 'settings.json|app-placement.json'){
        throw 'Expected Registry Preview file-state scope changed.'
    }
    $directory=Split-Path -Parent $ReceiptPath
    $name="$($state.Id)-$([guid]::NewGuid().ToString('N')).json"
    $path=Join-Path $directory $name
    [IO.File]::WriteAllText($path,(ConvertTo-Json $ExpectedState -Depth 12),[Text.UTF8Encoding]::new($false))
    $receipt=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($ReceiptPath))
    $receipt.Expected=[pscustomobject]@{Name=$name;Sha256=(Get-FileHash -LiteralPath $path).Hash}
    $temporary="$ReceiptPath.$([guid]::NewGuid().ToString('N')).tmp"
    try{
        [IO.File]::WriteAllText($temporary,(ConvertTo-Json $receipt -Depth 8),[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,$ReceiptPath,$true)
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Restore-PtRegistryPreviewFiles {
    <#.SYNOPSIS
    Restore placement only; preserve and report unrelated module-setting changes.
    #>
    param([Parameter(Mandatory)][string]$ReceiptPath)
    $state=Read-PtRegistryPreviewFileState -ReceiptPath $ReceiptPath
    Restore-PtFileSetSnapshot -Snapshot $state.OriginalState -ExpectedState $state.ExpectedState `
        -OwnedFileNames @('app-placement.json') -MaxBytes 1MB
}
