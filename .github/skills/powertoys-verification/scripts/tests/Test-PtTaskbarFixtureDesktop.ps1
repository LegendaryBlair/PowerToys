#requires -Version 7.2
param([Parameter(Mandatory)][string]$Workspace)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-taskbar-fixture.ps1"
. "$PSScriptRoot\..\pt-verification-report.ps1"
$helpers=Split-Path $PSScriptRoot -Parent
$run=New-PtVerificationRun -Workspace $Workspace -Module 'Calculator taskbar fixture' `
    -Bits 'Installed Windows Calculator; no PowerToys or Calculator settings changes' -Scenario InfrastructureAcceptance `
    -Items @(@{Id='Calculator';Description='Calculator first-slot routing with paired restoration';Admin='NO';Clarity='CLEAR';UserVisible=$true
        Assertions=@(@{Id='slot';Description='Calculator occupies the observed first app slot'}
            @{Id='route';Description='Three Win+1 actions bring the exact Calculator window foreground and release input'})}) `
    -Inputs @(@{Name='SKILL.md';Role='Skill';Path="$helpers\..\SKILL.md"}
        @{Name='test.ps1';Role='Checklist';Path=$PSCommandPath}
        foreach($name in 'pt-taskbar-fixture','pt-shortcut-guide','pt-desktop','pt-state-snapshot','pt-sendinput-chord','pt-foreground-guard','pt-verification-report'){
            @{Name="$name.ps1";Role='Helper';Path="$helpers\$name.ps1"}
        })
$fixture=$null;$failure=$null;$export=$null
function Proof($Attempt,[string]$Name,$Value,[string]$Kind='Evidence'){
    $path=New-PtVerificationArtifactPath $Attempt "$Name.json"
    ConvertTo-Json -InputObject $Value -Depth 25|Set-Content -LiteralPath $path
    Add-PtVerificationArtifact $Attempt $path $Kind $Name
}
try{
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Calculator and desktop readiness' `
        -Command 'Read registered Calculator, existing windows and original foreground; no mutation' -Action {
            param($attempt)
            $calculator=Get-PtTaskbarCalculator
            $foreground=Get-PtForegroundWindow
            if(@(Get-PtTaskbarCalculatorWindows $calculator).Count){throw 'Calculator is already open; preserve user state.'}
            Proof $attempt preflight @{Calculator=$calculator;Foreground=$foreground}|Out-Null
        }|Out-Null
    $case=Invoke-PtVerificationCase -Run $run -ItemId Calculator -Name 'Create Calculator fixture' `
        -Command 'Record original taskbar and desktop, then open one system Calculator' -ArgumentList @($Workspace) -Action {
            param($attempt,$work)
            New-PtTaskbarFixture -Workspace $work
        }
    $fixture=$case.Output[0]
    $case=Invoke-PtVerificationCase -Run $run -ItemId Calculator -Name 'First-slot move and Win+1' `
        -Command 'Move Calculator to first slot; route Win+1 from the original foreground three times' -ArgumentList @($fixture) -Action {
            param($attempt,$owned)
            $move=Move-PtTaskbarFixtureToSlot $owned -Slot 1
            $slots=Get-PtTaskbarSlots
            if($slots.Apps[0].AppId -cne $owned.Apps[0].AppId){throw 'Calculator is not in the first observed slot.'}
            $proof=Proof $attempt slots @{Move=$move;Slots=$slots}
            $image=New-PtVerificationArtifactPath $attempt calculator-first.png
            Save-PtPassiveScreenshot -Path $image|Out-Null
            $photo=Add-PtVerificationArtifact $attempt $image Screenshot 'Actual Calculator first-slot placement'
            Add-PtVerificationAssertion $attempt slot PASS 'Observed taskbar mapping' 'Calculator is physically first.' -Evidence @($proof,$photo)
            $original=(Read-PtTaskbarFixture $owned).Marker.Desktop.foreground
            foreach($iteration in 1..3){
                Assert-PtForegroundOrAbort -Hwnd $original.hwnd
                $route=Invoke-PtTaskbarSlot $owned -Slot 1
                if($route.ForegroundHwnd -ne $owned.Apps[0].Identity.hwnd -or $route.WindowsHeldAfter){
                    throw 'Win+1 did not route to Calculator and release Windows.'
                }
                $evidence=Proof $attempt "route-$iteration" $route
                Add-PtVerificationAssertion $attempt route PASS 'Exact routed HWND and released keys' "Observed Win+1 cycle $iteration." -Evidence @($evidence,$photo)
            }
        }
    Complete-PtVerificationItem $run Calculator -Reason 'Observed Calculator slot and all three routes'
}catch{$failure=$_}
finally{
    $receipt=if($fixture){$fixture.ReceiptPath}elseif($failure){$failure.Exception.Data['FixtureReceipt']}else{$null}
    try{
        Invoke-PtVerificationCase -Run $run -Context Cleanup -Name 'Restore Calculator fixture state' `
            -Command 'Restore any original Calculator slot, close only owned Calculator HWND, compare taskbar and desktop' `
            -ArgumentList @($receipt) -Action {
                param($attempt,$fixtureReceipt)
                $result=if($fixtureReceipt){Remove-PtTaskbarFixture -ReceiptPath $fixtureReceipt}else{@{NoFixtureLaunched=$true}}
                $proof=Proof $attempt restoration $result Restoration
                Add-PtVerificationRestoration $attempt PASS 'Complete owned fixture cleanup, or preflight ended before creating any fixture.' -Evidence @($proof)
            }|Out-Null
    }catch{
        if($failure){$failure.Exception.Data['CleanupFailure']=$_.Exception.Message}else{$failure=$_}
    }
    Set-PtActiveVerificationAttempt -Attempt $null
    $export=if($failure){
        $source=if($failure.Exception.Message -match 'No foreground window|Calculator is already open|registered system Calculator'){ 'ENVIRONMENT' }else{ 'HELPER-FLAW' }
        Complete-PtVerificationRun $run -Retrospective @(@{Friction=$failure.Exception.Message;Source=$source
            Severity='HIGH';Cost='This acceptance attempt';SuggestedFix='Inspect the original execution error and cleanup receipt; no product PASS is inferred.'})
    }else{Complete-PtVerificationRun $run -NoFriction}
    Test-PtVerificationArchive -Workspace $Workspace|Out-Null
}
if($failure){throw $failure}
if($export.Signoff -ne 'APPROVED'){throw "Calculator fixture acceptance incomplete: $($export.Report)"}
"PASS: Calculator first-slot placement, three Win+1 routes and complete restoration. $($export.Report)"
