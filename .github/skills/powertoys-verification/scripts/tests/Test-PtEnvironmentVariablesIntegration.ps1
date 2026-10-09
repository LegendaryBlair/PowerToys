#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-env-integration-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Get-ChildItem "$skill\scripts" -Filter '*.ps1' |
    Where-Object Name -NE 'pt-session-diagnose.ps1' | ForEach-Object {. $_.FullName}
if(Test-Path -LiteralPath $Workspace){throw 'Use a new test workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$private=Join-Path $Workspace 'private'
[IO.Directory]::CreateDirectory($private)|Out-Null
$journal=Join-Path $private 'recovery.dpapi'
$file=Join-Path $private 'fixture.txt'
$baselineReceipts=@()
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace});throw}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
try{
    $inventoryPath="$skill\references\assertion-inventories\environment-variables.json"
    $checklistPath="$skill\references\release-checklist\environment-variables.md"
    $inventory=Import-PtAssertionInventory $inventoryPath $checklistPath
    Check 'Functional checklist and explicit inventory retain all existing requirements' {
        $text=[IO.File]::ReadAllText("$skill\references\release-checklist\environment-variables.md")
        $aliases=@($inventory.Items.Assertions.Id|ForEach-Object {($_ -split '\.')[0]}|Sort-Object -Unique)
        $expected=@(1..20|ForEach-Object {'EV-B{0:D2}' -f $_})+@('EV-B03-S','EV-B04-S','EV-B05-S','EV-L01','EV-T01')+
            @(1..16|ForEach-Object {'EV-P{0:D2}' -f $_})
        Require (@(Compare-Object $expected $aliases).Count -eq 0) 'Original source coverage changed'
        Require ($inventory.Revision -eq 3 -and $inventory.Items.Count -eq 29 -and @($inventory.Items.Assertions).Count -eq 135) 'Frozen revision/counts changed'
        foreach($removed in 'Provenance and applicability','Original baseline','PR disposition map','Coverage accounting',
            'Canonical execution inventory','Draft validation matrices','Entry points and conditional coverage'){
            Require (-not $text.Contains($removed)) "Removed narrative heading remains: $removed"
        }
        Require ($text.Contains('## Legend') -and $text.Contains('## Fixtures & conventions') -and
            $text.Contains('## Environment Variables (29 items)')) 'Workspaces-style layout missing'
        Require ([regex]::Matches($text,'(?m)^  - \*\*EV-').Count -eq 0) 'Detailed child list still duplicated in checklist'
        Require (@($inventory.Items.Assertions|Where-Object {$_.Description -match '^- \*\*EV-'}).Count -eq 0) 'Inventory descriptions still contain source-label markup'
        foreach($id in $expected){
            Require (@($inventory.Items.Assertions|Where-Object {$_.Id.StartsWith("$id.")}).Count -gt 0) "Source has no canonical assertion: $id"
        }
    }
    Check 'Distinct baselines and prerequisites cannot replace ordinary coverage' {
        $applied=@($inventory.Items|Where-Object Id -EQ 'EV-APPLIED-EDIT')[0]
        foreach($variant in 'absent','existing'){
            foreach($stage in 'apply','edit','rename','unapply'){
                Require ($applied.Assertions.Id -ccontains "EV-P07.$variant-$stage") 'Applied-edit baseline/stage omitted'
            }
        }
        $core=@($inventory.Items|Where-Object Id -EQ 'EV-VALIDATION')[0]
        $system=@($inventory.Items|Where-Object Id -EQ 'EV-VALIDATION-SYSTEM')[0]
        Require ($core.Admin -ceq 'NO' -and $system.Admin -ceq 'YES') 'System prerequisite leaked into ordinary validation'
        Require (@($core.Assertions|Where-Object Id -Like 'EV-P03.*').Count -eq 0) 'Provider-dependent inputs block ordinary matrix'
        foreach($surface in 'add-user','edit-user','profile-new','profile-edit','profile-name'){
            foreach($rule in 'EV-P01','EV-P02'){Require ($core.Assertions.Id -ccontains "$rule.$surface") 'Validation surface/rule omitted'}
        }
        $quick=@($inventory.Items|Where-Object Id -EQ 'EV-QUICK-ACCESS')[0]
        $companion=@($inventory.Items|Where-Object Id -EQ 'EV-CMDPAL')[0]
        Require ($quick.Assertions.Count -eq 1 -and $quick.Assertions[0].Id -ceq 'EV-P14.quick-access') 'Quick Access gained a Command Palette dependency'
        foreach($id in 'EV-P14.cmdpal','EV-P14.settings','EV-P15.pin','EV-P15.invoke-pinned','EV-P15.fallback'){
            Require ($companion.Assertions.Id -ccontains $id) 'Companion route or pin/fallback assertion omitted'
        }
        Require (@($inventory.Items.Assertions|Where-Object Id -Like 'EV-P09.ordinary*').Count -eq 0) 'Ordinary startup counted again'
        $control=@($inventory.Items|Where-Object Id -EQ 'EV-CONTROL-INPUT')[0]
        $controlSystem=@($inventory.Items|Where-Object Id -EQ 'EV-CONTROL-INPUT-SYSTEM')[0]
        Require ($control.Admin -ceq 'NO' -and $controlSystem.Admin -ceq 'YES') 'Control-input scope metadata is mixed'
        Require (($control.Assertions.Id -join ',') -ceq 'EV-P03.user-names,EV-P03.user-values') 'Non-admin control-input assertions changed'
        Require (($controlSystem.Assertions.Id -join ',') -ceq 'EV-P03.system-names,EV-P03.system-values') 'System control-input assertions changed'
        Require (@($inventory.Items.Assertions|Where-Object Id -in 'EV-P03.names','EV-P03.values').Count -eq 0) 'Mixed-scope legacy assertions were reused'
        $persistence=@($inventory.Items.Assertions|Where-Object Id -EQ 'EV-P13.persistence')[0].Description
        Require ($persistence.Contains('Both disabled and enabled') -and $persistence.Contains('stored module flag') -and
            $persistence.Contains('Settings toggle after save') -and $persistence.Contains('no Settings close/reopen is required')) 'Persistence requires borrowed Settings restart or omits one state'
    }
    Check 'Scenario A template rejects run-local regrouping before initialization' {
        $changed=ConvertFrom-PtReportJson (ConvertTo-Json -InputObject $inventory.Items -Depth 30)
        $applied=@($changed|Where-Object Id -EQ 'EV-APPLIED-EDIT')[0]
        $applied.Assertions=@($applied.Assertions|Where-Object Id -NE 'EV-P07.absent-edit')
        $target=Join-Path $Workspace 'rejected-regrouping'
        foreach($module in 'Environment Variables','EnvironmentVariables'){
            Reject {& "$skill\templates\verification-run.ps1" -Skill $skill -Workspace $target -Module $module `
                -Bits 'Synthetic inventory rejection; no product execution' -Items $changed `
                -Inputs @(@{Name='test.ps1';Role='Other';Path=$PSCommandPath}) -Preflight {throw 'must not run'} `
                -Cases {throw 'must not run'} -NoFriction `
                -ResourcePlan @{Schema='PtRunResources.v1';Resources=@(@{Id='fixture';Kind='Other';RestoreStep='fixture'})} `
                -CleanupPlan @(@{Id='fixture';Phase='Verify';DependsOn=@();Action={};Verify={$true}})} 'frozen module inventory'
            Require (-not (Test-Path $target)) 'Regrouping reached run creation'
        }
    }
    $inputs=@(Get-PtVerificationInputs -Skill $skill -Inputs @(
        @{Name='integration-test.ps1';Role='Other';Path=$PSCommandPath},
        @{Name='environment-variables.md';Role='Profile';Path="$skill\references\modules\environment-variables.md"},
        @{Name='env-checklist.md';Role='Checklist';Path="$skill\references\release-checklist\environment-variables.md"},
        @{Name='env-inventory.json';Role='Other';Path=$inventoryPath},
        @{Name='environment-variables-fixtures.md';Role='Other';Path="$skill\references\environment-variables-fixtures.md"}))
    Check 'WIP bootstrap and source manifest include the private helper and module material' {
        foreach($name in 'New-PtEnvJournal','Restore-PtEnvJournal','Set-PtEnvOwnedVariableValue',
            'Invoke-PtVerificationCase','Invoke-PtCleanupPlan','Get-PtSettingsUiSnapshot','Assert-PtWindowRelease'){
            Require ([bool](Get-Command $name -ErrorAction Ignore)) "Missing integration API: $name"
        }
        Require (@($inputs|Where-Object Path -EQ "$skill\scripts\pt-environment-variables-state.ps1").Count -eq 1) 'Module helper source was not included exactly once'
    }
    Check 'Existing-value PASS cannot hide unobserved originally-absent assertions' {
        $coverage=New-PtVerificationRun -Workspace "$Workspace\coverage" -Module 'Environment Variables inventory fixture' `
            -Scenario InfrastructureAcceptance -Bits 'Synthetic assertion projection only; no product or desktop access' `
            -Inputs $inputs -Items $inventory.Items
        $attempt=Start-PtVerificationAttempt -Run $coverage -ItemId 'EV-APPLIED-EDIT' -Kind Normal -Name 'Synthetic existing-value observations'
        $path=New-PtVerificationArtifactPath $attempt 'synthetic.json'
        Write-PtReportText $path '{"Synthetic":true}'
        $evidence=Add-PtVerificationArtifact $attempt $path Evidence 'Synthetic observation, not product evidence' -Synthetic
        foreach($stage in 'apply','edit','rename','unapply'){
            Add-PtVerificationAssertion -Attempt $attempt -AssertionId "EV-P07.existing-$stage" `
                -Verdict PASS -Category 'Synthetic contract' -Reason 'Existing-value fixture only' -Evidence @($evidence)
        }
        Stop-PtVerificationAttempt $attempt -Reason 'No originally-absent observations supplied'
        Complete-PtVerificationItem $coverage 'EV-APPLIED-EDIT' -Reason 'Incomplete baseline matrix'
        $state=Get-PtReportState $coverage
        $item=@($state.Items|Where-Object Id -EQ 'EV-APPLIED-EDIT')[0]
        Require ($item.Verdict -ceq 'BLOCKED') 'Partial baseline coverage became a complete PASS'
        Require (@($item.Assertions|Where-Object {$_.Id -like 'EV-P07.absent-*' -and $_.Verdict -eq 'NOT-OBSERVED'}).Count -eq 4) 'Originally-absent coverage disappeared'
        Require (@($item.Assertions|Where-Object {$_.Id -like 'EV-P07.existing-*' -and $_.Verdict -eq 'PASS'}).Count -eq 4) 'Independent existing-value coverage was discarded'
        $export=Export-PtVerificationReport $coverage
        Test-PtVerificationArchive $coverage.Workspace -ManifestName (Split-Path $export.Manifest -Leaf)|Out-Null
        $rendered=[IO.File]::ReadAllText($export.Report)
        foreach($child in $inventory.Items.Assertions){
            Require ($rendered.Contains($child.Id)) "Canonical assertion missing from report: $($child.Id)"
        }
    }
    Check 'Missing System elevation leaves complete non-admin control input PASS' {
        $coverage=New-PtVerificationRun -Workspace "$Workspace\control-scope" -Module 'Control input scope fixture' `
            -Scenario InfrastructureAcceptance -Bits 'Synthetic recorder scope test; no product or desktop access' `
            -Inputs $inputs -Items $inventory.Items
        Invoke-PtVerificationCase -Run $coverage -ItemId 'EV-CONTROL-INPUT' -Name 'Synthetic non-admin observations' `
            -Command 'Record synthetic non-admin matrix outcomes, not a live product test' -Action {
                param($attempt)
                $path=New-PtVerificationArtifactPath $attempt 'synthetic.png'
                Write-PtReportFile $path ([Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='))
                $proof=Add-PtVerificationArtifact $attempt $path Screenshot 'Synthetic scope fixture, not a product capture' -Synthetic
                foreach($id in 'EV-P03.user-names','EV-P03.user-values'){
                    Add-PtVerificationAssertion -Attempt $attempt -AssertionId $id -Verdict PASS -Category 'Synthetic contract' `
                        -Reason 'All synthetic non-admin rows supplied; independent of System coverage' -Evidence @($proof)
                }
            }|Out-Null
        Complete-PtVerificationItem $coverage 'EV-CONTROL-INPUT' -Reason 'Synthetic non-admin scope complete'
        Invoke-PtVerificationCase -Run $coverage -ItemId 'EV-CONTROL-INPUT-SYSTEM' -Name 'Synthetic missing elevation' `
            -Command 'Record unavailable System fixture without driving any UI' -Action {
                param($attempt)
                foreach($id in 'EV-P03.system-names','EV-P03.system-values'){
                    Add-PtVerificationAssertion -Attempt $attempt -AssertionId $id -Verdict BLOCKED -Category 'BLK-ENV' `
                        -Reason 'Synthetic missing elevation; no System observations supplied'
                }
            }|Out-Null
        Complete-PtVerificationItem $coverage 'EV-CONTROL-INPUT-SYSTEM' -Reason 'System fixture unavailable'
        $state=Get-PtReportState $coverage
        Require (($state.Items|Where-Object Id -EQ 'EV-CONTROL-INPUT').Verdict -ceq 'PASS') 'System prerequisite blocked non-admin case'
        Require (($state.Items|Where-Object Id -EQ 'EV-CONTROL-INPUT-SYSTEM').Verdict -ceq 'BLOCKED') 'Missing System coverage disappeared'
        Require ($state.Signoff -ceq 'WITHHELD') 'Partial scope was presented as full signoff'
    }
    $secret='PRIVATE_ENV_FIXTURE_'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($file,$secret)
    New-PtEnvJournal $journal
    $baselineReceipts=@(Add-PtEnvTrackedResource $journal 'owned-file' -FilePath $file)
    $run=New-PtVerificationRun -Workspace "$Workspace\run" -Module 'Environment Variables integration fixture' `
        -Scenario InfrastructureAcceptance -Bits 'Synthetic private file only; no product, environment or UI access' `
        -Inputs $inputs -Items @(@{Id='local-state';Admin='NO';Clarity='CLEAR';UserVisible=$false
            Description='Module private journal uses the common recorder and cleanup plan'
            Assertions=@(@{Id='guard';Description='Conflict refusal and exact original restoration'})})
    $attempt=Start-PtVerificationAttempt -Run $run -ItemId local-state -Kind Normal -Name 'Private journal boundaries'
    Check 'Recorded private write emits sanitized receipts rather than original payload' {
        $null=Invoke-PtVerificationStep -Attempt $attempt -Name 'Owned synthetic write' `
            -Command 'Write one disposable file; register only a sanitized resource receipt' `
            -ArgumentList @($journal,$file) -Action {
                param($privateJournal,$ownedFile)
                [IO.File]::WriteAllText($ownedFile,'owned-change')
                $receipt=Get-PtEnvResourceReceipt $privateJournal 'owned-file'
                Set-PtEnvOwnedPostState $privateJournal 'owned-file' $receipt.Fingerprint 'Synthetic independently attributed file write'
                $receipt
            }
    }
    Stop-PtVerificationAttempt $attempt -Reason 'Synthetic write recorded without the private original'
    $cleanup=@(@{Id='private-state';Phase='Files';DependsOn=@();Arguments=@($journal,$baselineReceipts)
        Action={param($privateJournal,$originalReceipts) Restore-PtEnvJournal $privateJournal|Out-Null}
        Verify={
            param($privateJournal,$originalReceipts)
            $matches=$originalReceipts.Count -gt 0
            foreach($baseline in $originalReceipts){
                $actual=Get-PtEnvResourceReceipt $privateJournal $baseline.Id
                if($actual.Exists -ne $baseline.Exists -or $actual.Fingerprint -cne $baseline.Fingerprint){$matches=$false}
            }
            $matches
        }})
    Assert-PtRunResourcePlan -Plan @{Schema='PtRunResources.v1';Resources=@(
        @{Id='owned-file';Kind='File';RestoreStep='private-state'})} -CleanupPlan $cleanup
    Check 'Common cleanup records a conflict without overwriting it or deleting the journal' {
        [IO.File]::WriteAllText($file,'foreign-change')
        $attempt=Start-PtVerificationAttempt -Run $run -Context Cleanup -Kind Normal -Name 'Expected conflict'
        try{Reject {Invoke-PtCleanupPlan $attempt $cleanup} 'Cleanup incomplete'}
        finally{Stop-PtVerificationAttempt $attempt -Reason 'Expected synthetic conflict retained'}
        Require ([IO.File]::ReadAllText($file) -ceq 'foreign-change' -and [IO.File]::Exists($journal)) 'Foreign data or private journal was discarded'
    }
    Check 'Common cleanup restores exact original bytes and retains failed history' {
        # Undo the test's injected conflict to the already sealed synthetic state.
        [IO.File]::WriteAllText($file,'owned-change')
        $attempt=Start-PtVerificationAttempt -Run $run -Context Cleanup -Kind Normal -Name 'Verified private rollback'
        try{Invoke-PtCleanupPlan $attempt $cleanup|Out-Null}
        finally{Stop-PtVerificationAttempt $attempt -Reason 'Original private bytes and receipts compared'}
        Require ([IO.File]::ReadAllText($file) -ceq $secret) 'Private original was not restored'
        $state=Get-PtReportState $run
        Require (@($state.Restoration|Where-Object {$_.Data.Verdict -eq 'BLOCKED'}).Count -eq 1) 'Earlier conflict history lost'
        Require (@($state.Restoration|Where-Object {$_.Data.Verdict -eq 'PASS'}).Count -eq 1) 'Fresh restoration evidence missing'
    }
    Export-PtVerificationReport $run|Out-Null
    Check 'Run artifact output excludes decrypted snapshots and encrypted journals' {
        foreach($artifact in Get-ChildItem $run.Workspace -Recurse -File){
            Require ($artifact.Extension -ne '.dpapi' -and $artifact.Extension -ne '.pending') 'Private journal entered the report workspace'
            Require (-not [IO.File]::ReadAllText($artifact.FullName).Contains($secret)) 'Private original leaked into recorded arguments/output/evidence'
        }
    }
}
finally{
    if([IO.File]::Exists($journal)){
        foreach($baseline in $baselineReceipts){
            $actual=Get-PtEnvResourceReceipt $journal $baseline.Id
            if($actual.Exists -ne $baseline.Exists -or $actual.Fingerprint -cne $baseline.Fingerprint){
                throw "Synthetic fixture restoration incomplete; preserve private test journal at $journal"
            }
        }
        [IO.File]::Delete($journal)
    }
    if([IO.File]::Exists($file)){[IO.File]::Delete($file)}
    [IO.Directory]::Delete($private,$false)
}
"PASS: $($results.Count) WIP Environment Variables integration groups; no product or environment-variable mutation. $Workspace"
