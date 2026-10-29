#requires -Version 7.2
# Explicit selected-file preservation; unrelated siblings and live logs are never read.
. "$PSScriptRoot\pt-directory-snapshot.ps1"

function Assert-PtSnapshotFileNames {
    param([string]$Root,$FileNames)
    if($FileNames -isnot [array] -or $FileNames.Count -lt 1 -or $FileNames.Count -gt 64){
        throw 'Supply between 1 and 64 explicit direct-child file names.'
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($name in $FileNames){
        Assert-PtDirectoryRelativePath $name
        if($name.Contains('\') -or $Root.Length+1+$name.Length -ge 260){
            throw "Only bounded direct-child file names are supported: $name"
        }
        if(-not $seen.Add($name)){throw "Duplicate/case-duplicate selected file: $name"}
    }
}

function Get-PtFileSetSnapshot {
    <#
    .SYNOPSIS
    Capture exact bytes/existence for named files without enumerating sibling contents.
    .DESCRIPTION
    The narrow local root must already exist. Quiesce selected writers, not unrelated logs.
    Reuses directory-snapshot path/link/cloud/hardlink checks and byte bounds. No ownership
    is inferred from capture. This is not a whole-directory snapshot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$FileNames,
        [ValidateRange(0,2147483647)][long]$MaxBytes=16MB
    )
    $root=Resolve-PtDirectorySnapshotPath $Path
    Assert-PtSnapshotFileNames $root $FileNames
    if((Get-PtDirectoryPathKind $root) -ne 'Directory'){throw 'Selected-file root must be an existing directory.'}
    $files=[Collections.Generic.List[object]]::new()
    [long]$total=0
    foreach($name in $FileNames){
        $path="$root\$name"
        $kind=Get-PtDirectoryPathKind $path
        if($kind -eq 'Absent'){continue}
        if($kind -ne 'File'){throw "Selected file is a directory: $name"}
        $entries=@([IO.Directory]::EnumerateFileSystemEntries($root,$name,[IO.SearchOption]::TopDirectoryOnly))
        if($entries.Count -ne 1 -or [IO.Path]::GetFileName($entries[0]) -cne $name){
            throw "Selected file has changed spelling or identity: $name"
        }
        $bytes=[PtDirectorySnapshotNative]::Read($path,$MaxBytes-$total)
        $total+=$bytes.LongLength
        $files.Add([pscustomobject]@{RelativePath=$name;Length=$bytes.LongLength
            Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
            Base64=[Convert]::ToBase64String($bytes)})
    }
    [pscustomobject]@{
        Schema='PtFileSetSnapshot.v1'
        FileNames=@($FileNames)
        FileState=[pscustomobject]@{SchemaVersion=1;Path=$root;Exists=$true
            Files=@($files);Directories=@()}
    }
}

function ConvertTo-PtFileSetSnapshotMap {
    param($Snapshot,[long]$MaxBytes)
    Assert-PtDirectorySnapshotRecord $Snapshot @('Schema','FileNames','FileState')
    if($Snapshot.Schema -cne 'PtFileSetSnapshot.v1'){throw 'Unsupported selected-file snapshot schema.'}
    $map=ConvertTo-PtDirectorySnapshotMap $Snapshot.FileState 64 $MaxBytes 0
    if(-not $Snapshot.FileState.Exists){throw 'Selected-file root absence is not supported.'}
    Assert-PtSnapshotFileNames $Snapshot.FileState.Path $Snapshot.FileNames
    foreach($file in $Snapshot.FileState.Files){
        if($file.RelativePath -cnotin $Snapshot.FileNames){throw 'Snapshot contains an unselected file.'}
    }
    ,$map
}

function Restore-PtFileSetSnapshot {
    <#
    .SYNOPSIS
    Restore only explicitly owned selected files, including original absence.
    .DESCRIPTION
    Validate the complete plan before writes, then recheck each changed file. Unowned
    selected changes are retained; siblings outside the selection are not inspected.
    Selected writers must be quiescent. Like directory rollback this is not an atomic
    filesystem transaction: namespace races/I/O failures can leave partial restoration.
    Original and ExpectedState must retain the same root and exact ordered selection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)]$ExpectedState,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$OwnedFileNames,
        [ValidateRange(0,2147483647)][long]$MaxBytes=16MB
    )
    $before=ConvertTo-PtFileSetSnapshotMap $Snapshot $MaxBytes
    $expected=ConvertTo-PtFileSetSnapshotMap $ExpectedState $MaxBytes
    $root=$Snapshot.FileState.Path
    if($root -cne $ExpectedState.FileState.Path -or
        ($Snapshot.FileNames -join "`0") -cne ($ExpectedState.FileNames -join "`0")){
        throw 'Original and expected snapshots require the same root and exact file selection.'
    }
    $owned=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($name in $OwnedFileNames){
        if($name -cnotin $Snapshot.FileNames -or -not $owned.Add($name)){
            throw "Ownership must name unique exact selected files: $name"
        }
    }
    $currentSnapshot=Get-PtFileSetSnapshot -Path $root -FileNames $Snapshot.FileNames -MaxBytes $MaxBytes
    $current=ConvertTo-PtFileSetSnapshotMap $currentSnapshot $MaxBytes
    $plan=[Collections.Generic.List[object]]::new()
    $conflicts=[Collections.Generic.List[string]]::new()
    foreach($name in $Snapshot.FileNames){
        if(-not $owned.Contains($name) -or (Test-PtDirectoryEntryEqual $current[$name] $before[$name])){continue}
        if(-not (Test-PtDirectoryEntryEqual $current[$name] $expected[$name])){
            $conflicts.Add($name)
        }else{
            $action=if($null -eq $before[$name]){'RemoveFile'}else{'WriteFile'}
            $plan.Add([pscustomobject]@{FileName=$name;Action=$action})
        }
    }
    if($conflicts.Count){
        $error=[InvalidOperationException]::new("Selected-file restore conflict; no writes performed: $($conflicts -join ', ')")
        $error.Data['PtFileSetSnapshotReceipt']=[pscustomobject]@{Path=$root;Scope='SelectedFiles'
            Status='Conflict';Changes=@();Conflicts=@($conflicts);SelectedFilesMatchBaseline=$false}
        throw $error
    }
    $changes=[Collections.Generic.List[object]]::new()
    foreach($change in $plan){
        $name=$change.FileName
        $fresh=Get-PtFileSetSnapshot -Path $root -FileNames @($name) -MaxBytes $MaxBytes
        $freshMap=ConvertTo-PtFileSetSnapshotMap $fresh $MaxBytes
        if(-not (Test-PtDirectoryEntryEqual $freshMap[$name] $current[$name])){
            throw "Selected file changed after precheck; restoration may be partial: $name"
        }
        if($change.Action -eq 'RemoveFile'){
            [IO.File]::Delete("$root\$name")
        }else{
            [PtDirectorySnapshotNative]::Write("$root\$name",
                [Convert]::FromBase64String($before[$name].Base64),($null -eq $current[$name]))
        }
        $changes.Add($change)
    }
    $actual=ConvertTo-PtFileSetSnapshotMap (Get-PtFileSetSnapshot -Path $root -FileNames $Snapshot.FileNames -MaxBytes $MaxBytes) $MaxBytes
    $unowned=[Collections.Generic.List[string]]::new()
    foreach($name in $Snapshot.FileNames){
        if(Test-PtDirectoryEntryEqual $actual[$name] $before[$name]){continue}
        if($owned.Contains($name)){throw "Selected-file post-restore comparison failed; restoration may be partial: $name"}
        $unowned.Add($name)
    }
    [pscustomobject]@{Path=$root;Scope='SelectedFiles';FileNames=@($Snapshot.FileNames)
        Status=$(if($unowned.Count){'Partial'}else{'Restored'});OwnedFilesMatchBaseline=$true
        SelectedFilesMatchBaseline=($unowned.Count -eq 0);Changes=@($changes);UnownedDifferences=@($unowned)}
}
