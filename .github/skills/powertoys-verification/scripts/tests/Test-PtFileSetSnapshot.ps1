#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-file-set-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-file-set-snapshot.ps1"
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$root=Join-Path $Workspace 'owned-files'
[IO.Directory]::CreateDirectory($root)|Out-Null
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return $_}
    throw "Expected rejection: $Pattern"
}
$names=@('settings.json','profiles.json','monitor_state.json','unowned.json')
[IO.File]::WriteAllText("$root\settings.json",'original-settings')
[IO.File]::WriteAllText("$root\profiles.json",'original-profiles')
[IO.File]::WriteAllText("$root\unowned.json",'original-unowned')
[IO.Directory]::CreateDirectory("$root\Logs")|Out-Null
$log=[IO.File]::Open("$root\Logs\live.log",[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    Reject {Get-PtDirectorySnapshot -Path $root} 'Cannot open snapshot file'|Out-Null
    $before=Get-PtFileSetSnapshot -Path $root -FileNames $names
    $before=$before|ConvertTo-Json -Depth 8|ConvertFrom-Json
    [IO.File]::WriteAllText("$root\settings.json",'owned-settings')
    [IO.File]::Delete("$root\profiles.json")
    [IO.File]::WriteAllText("$root\monitor_state.json",'owned-new-state')
    [IO.File]::WriteAllText("$root\unowned.json",'external-change')
    $expected=Get-PtFileSetSnapshot -Path $root -FileNames $names
    $owned=@('settings.json','profiles.json','monitor_state.json')
    $receipt=Restore-PtFileSetSnapshot -Snapshot $before -ExpectedState $expected -OwnedFileNames $owned
    Require ($receipt.Status -eq 'Partial' -and $receipt.OwnedFilesMatchBaseline -and -not $receipt.SelectedFilesMatchBaseline) 'Unowned selected change was hidden'
    Require ([IO.File]::ReadAllText("$root\settings.json") -ceq 'original-settings') 'Existing content not restored'
    Require ([IO.File]::ReadAllText("$root\profiles.json") -ceq 'original-profiles') 'Deleted original not recreated'
    Require (-not [IO.File]::Exists("$root\monitor_state.json")) 'Original absence not restored'
    Require ([IO.File]::ReadAllText("$root\unowned.json") -ceq 'external-change') 'Unowned selected change overwritten'
    $again=Restore-PtFileSetSnapshot -Snapshot $before -ExpectedState $expected -OwnedFileNames $owned
    Require ($again.Changes.Count -eq 0) 'Repeated restoration wrote files again'

    [IO.File]::WriteAllText("$root\settings.json",'owned-again')
    [IO.File]::WriteAllText("$root\profiles.json",'owned-profile')
    $expected=Get-PtFileSetSnapshot -Path $root -FileNames $names
    [IO.File]::WriteAllText("$root\settings.json",'concurrent-change')
    $failure=Reject {Restore-PtFileSetSnapshot $before $expected $owned} 'conflict; no writes'
    Require ($failure.Exception.Data['PtFileSetSnapshotReceipt'].Changes.Count -eq 0) 'Conflict performed a write'
    Require ([IO.File]::ReadAllText("$root\profiles.json") -ceq 'owned-profile') 'Conflict partially restored another file'

    Reject {Get-PtFileSetSnapshot $root @('..\outside')} 'direct-child|traversal|Invalid Windows'|Out-Null
    Reject {Get-PtFileSetSnapshot $root @('settings.json','SETTINGS.JSON')} 'Duplicate'|Out-Null
    Reject {Get-PtFileSetSnapshot $root @('Logs')} 'directory'|Out-Null
    Reject {Get-PtFileSetSnapshot $root @('settings.json') -MaxBytes 1} 'MaxBytes'|Out-Null
    Reject {Restore-PtFileSetSnapshot $before $expected @('not-selected.json')} 'Ownership'|Out-Null
    $bad=$before|ConvertTo-Json -Depth 8|ConvertFrom-Json
    $bad.FileState.Files[0].Base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('tampered'))
    Reject {Restore-PtFileSetSnapshot $bad $expected $owned} 'base64|hash|length'|Out-Null
    New-Item -ItemType HardLink -Path "$root\link.json" -Target "$root\settings.json"|Out-Null
    Reject {Get-PtFileSetSnapshot $root @('settings.json')} 'hardlink'|Out-Null
    [IO.File]::Delete("$root\link.json")
    Require ($log.Length -eq 0) 'Unrelated locked log was modified'
}finally{
    $log.Dispose()
    foreach($name in @('settings.json','profiles.json','monitor_state.json','unowned.json','link.json')){
        if([IO.File]::Exists("$root\$name")){[IO.File]::Delete("$root\$name")}
    }
    [IO.File]::Delete("$root\Logs\live.log")
    [IO.Directory]::Delete("$root\Logs",$false)
    [IO.Directory]::Delete($root,$false)
}
$result=@{LockedUnrelatedLog='PASS';ExistingDeletedAndAbsent='PASS';UnownedAndIdempotent='PASS'
    ConflictZeroWrites='PASS';InvalidScopeAndTamper='PASS';HardlinkRefusal='PASS';FixtureRemoved=(-not (Test-Path $root))}
$result|ConvertTo-Json|Set-Content "$Workspace\results.json"
"PASS: selected-file snapshots and guarded absence restoration without reading live siblings. $Workspace"
