#requires -Version 7.2
param(
    [string]$Workspace=(Join-Path $env:TEMP "pt-ocr-state-$([guid]::NewGuid().ToString('N'))"),
    [switch]$CrashWriter,[string]$RecoveryPath,[string]$SettingsPath
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-text-extractor-state.ps1"
function Change([string]$Path,[string]$Preference){
    $value=[IO.File]::ReadAllText($Path)|ConvertFrom-Json
    $value.properties.PreferredLanguage=$Preference;$value.version='1.0'
    [IO.File]::WriteAllText($Path,(ConvertTo-Json $value -Depth 12))
}
if($CrashWriter){
    Invoke-PtTextExtractorPreferenceChange -RecoveryPath $RecoveryPath -PreferredLanguage 'English (United States)' `
        -ArgumentList @($SettingsPath) -Action {param($path) Change $path 'English (United States)';exit 23}
    exit 24
}
if(Test-Path $Workspace){throw 'Use a new test workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$root=Join-Path $Workspace 'owned-settings'
$private=Join-Path $Workspace 'private'
[IO.Directory]::CreateDirectory($root)|Out-Null
[IO.Directory]::CreateDirectory($private)|Out-Null
$path=Join-Path $root 'settings.json'
$base=@{
    name='TextExtractor';version='1'
    properties=@{PreferredLanguage='';ActivationShortcut=@{win=$true;ctrl=$false;alt=$false;shift=$true;code=84;key=''}}
    retained=@{data='unrelated-original';order=@('b','a')}
}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
$results=@()
try{
    foreach($preference in '','English (United States)'){
        $base.properties.PreferredLanguage=$preference
        [IO.File]::WriteAllText($path,(ConvertTo-Json $base -Depth 12),[Text.UTF8Encoding]::new($true))
        $hash=(Get-FileHash $path).Hash
        $journal=Join-Path $private "$([guid]::NewGuid().ToString('N')).json.dpapi"
        $receipt=New-PtTextExtractorState -SettingsPath $path -RecoveryPath $journal
        Require ($receipt.OriginalSha256 -ceq $hash) 'Original snapshot hash differs'
        Require (-not [IO.File]::ReadAllText($journal).Contains('unrelated-original')) 'Recovery file disclosed plaintext'
        Invoke-PtTextExtractorPreferenceChange -RecoveryPath $journal -PreferredLanguage 'Owned OCR language' `
            -ArgumentList @($path) -Action {param($p) Change $p 'Owned OCR language'}|Out-Null
        $restored=Restore-PtTextExtractorFile $journal
        Require ($restored.SelectedFilesMatchBaseline -and (Get-FileHash $path).Hash -ceq $hash) 'Original empty/explicit preference, version or bytes were lost'
        Require ((Restore-PtTextExtractorFile $journal).Changes.Count -eq 0) 'Completed restoration was not idempotent'
        Reject {New-PtTextExtractorState $path $journal} 'already exists'
        $results+=@{Case="Byte-exact empty/explicit original '$preference' and repeated cleanup";Status='PASS'}
    }
    $journal=Join-Path $private 'callback-failure.dpapi'
    New-PtTextExtractorState $path $journal|Out-Null
    $hash=(Get-FileHash $path).Hash
    Reject {
        Invoke-PtTextExtractorPreferenceChange $journal 'Owned OCR language' -ArgumentList @($path) -Action {
            param($p) Change $p 'Owned OCR language';throw 'deliberate failure after owned write'
        }
    } 'deliberate failure'
    Restore-PtTextExtractorFile $journal|Out-Null
    Require ((Get-FileHash $path).Hash -ceq $hash) 'Callback error lost recovery ownership'
    $results+=@{Case='Callback failure after an attributable write';Status='PASS'}

    $base.properties.PreferredLanguage=''
    [IO.File]::WriteAllText($path,(ConvertTo-Json $base -Depth 12))
    $journal=Join-Path $private 'crashed-controller.dpapi'
    New-PtTextExtractorState $path $journal|Out-Null
    $hash=(Get-FileHash $path).Hash
    & (Get-Command pwsh).Source -NoProfile -File $PSCommandPath -CrashWriter -RecoveryPath $journal -SettingsPath $path
    Require ($LASTEXITCODE -eq 23) 'Child did not exit at the intended pending-write boundary'
    Require ($null -ne (Read-PtTextExtractorRecovery $journal).Pending) 'Interrupted operation lost its durable pending intent'
    Restore-PtTextExtractorFile $journal|Out-Null
    Require ((Get-FileHash $path).Hash -ceq $hash) 'New controller could not restore the original bytes'
    $results+=@{Case='Controller exit and durable pending-action recovery';Status='PASS'}
    $journal=Join-Path $private 'pending-before-input.dpapi'
    New-PtTextExtractorState $path $journal|Out-Null
    $pending=Read-PtTextExtractorRecovery $journal
    $pending.Pending=[pscustomobject]@{PreferredLanguage='Never issued'}
    Write-PtTextExtractorRecovery $journal $pending
    Require ((Restore-PtTextExtractorFile $journal).Changes.Count -eq 0) 'Pending intent without input should restore without a file write'
    $results+=@{Case='Interrupted before UI action; original remains unchanged';Status='PASS'}

    $journal=Join-Path $private 'conflict.dpapi'
    New-PtTextExtractorState $path $journal|Out-Null
    Invoke-PtTextExtractorPreferenceChange $journal 'Owned OCR language' -ArgumentList @($path) -Action {param($p) Change $p 'Owned OCR language'}|Out-Null
    $value=[IO.File]::ReadAllText($path)|ConvertFrom-Json
    $value.retained.data='unknown-concurrent-change'
    [IO.File]::WriteAllText($path,(ConvertTo-Json $value -Depth 12))
    $hash=(Get-FileHash $path).Hash
    Reject {Restore-PtTextExtractorFile $journal} 'conflict; no writes'
    Require ((Get-FileHash $path).Hash -ceq $hash -and (Test-Path $journal)) 'Conflict overwrote user data or removed recovery'
    $called=@{Value=$false}
    Reject {Invoke-PtTextExtractorPreferenceChange $journal '' -Action {$called.Value=$true}} 'outside the transaction'
    Require (-not $called.Value) 'Conflict still issued a UI action'
    $results+=@{Case='Concurrent changes refuse restoration and further UI effects';Status='PASS'}
    function Get-PtActiveVerificationAttempt {[pscustomobject]@{Run=[pscustomobject]@{Workspace=$Workspace}}}
    Reject {New-PtTextExtractorState $path (Join-Path $Workspace 'must-not-be-archived.dpapi')} 'outside the evidence'
    Require (-not (Test-Path (Join-Path $Workspace 'must-not-be-archived.dpapi'))) 'Private baseline leaked into evidence'
    $results+=@{Case='Private journal cannot enter the evidence workspace';Status='PASS'}
}finally{
    if([IO.File]::Exists($path)){[IO.File]::Delete($path)}
    [IO.Directory]::Delete($root,$false)
}
$results|ConvertTo-Json -Depth 5|Set-Content "$Workspace\results.json"
"PASS: Text Extractor durable originals, exact rollback, interrupted-controller recovery and conflict refusal. $Workspace"
