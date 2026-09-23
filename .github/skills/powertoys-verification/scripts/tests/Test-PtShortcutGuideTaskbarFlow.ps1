#requires -Version 7.2
param([Parameter(Mandatory)][string]$Workspace,[switch]$RoutingOnly)
$ErrorActionPreference='Stop'
$helpers=Split-Path $PSScriptRoot -Parent
. "$helpers\pt-shortcut-guide-flow.ps1"
. "$helpers\pt-taskbar-fixture.ps1"
$inputs=@(
    @{Name='SKILL.md';Role='Skill';Path="$helpers\..\SKILL.md"}
    @{Name='acceptance.ps1';Role='Checklist';Path=$PSCommandPath}
    foreach($name in 'pt-shortcut-guide-flow','pt-taskbar-fixture','pt-shortcut-guide','pt-module-lifecycle','pt-shortcut-recorder','pt-sendinput-chord','pt-foreground-guard','pt-desktop','pt-state-snapshot','pt-uia','pt-ui-observation','pt-verification-report','pt-verification-operation','pt-verification-render'){
        @{Name="$name.ps1";Role='Helper';Path="$helpers\$name.ps1"}
    }
)
$items=@(
    @{Id='Slots';Description='System Calculator occupies the first slot among at least three observed app slots'}
    @{Id='NamedEvent';Description='Repeated named-event open, passive observation and UI close'}
    @{Id='Chord';Description='Repeated exact configured chord open and Escape close'}
    @{Id='Win1';Description='Owned slot-one routing while SG indicators and Windows remain held'}
)
if($RoutingOnly){$items=@($items|Where-Object {$_.Id -in 'Slots','Win1'})}
foreach($item in $items){
    $item.Admin='NO';$item.Clarity='CLEAR';$item.UserVisible=$true
    $item.Assertions=@(@{Id='contract';Description=$item.Description})
}
$run=New-PtVerificationRun -Workspace $Workspace -Module 'H08-H11 composed SG/taskbar acceptance' `
    -Bits "Installed PowerToys $((Get-Process PowerToys).FileVersion); system Calculator fixture, no pin or registry writes" `
    -Scenario InfrastructureAcceptance -Inputs $inputs -Items $items
$fixture=$null;$failures=[Collections.Generic.List[string]]::new();$rootFailure=$null
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function CaptureProof($Attempt,[string]$Name,$Data,[string]$Description){
    $path=New-PtVerificationArtifactPath $Attempt "$Name.json"
    $Data|ConvertTo-Json -Depth 25|Set-Content $path
    Add-PtVerificationArtifact $Attempt $path Evidence $Description
}
function CheckCase([string]$Id,[scriptblock]$Action,[object[]]$Arguments){
    try{
        $case=Invoke-PtVerificationCase -Run $run -ItemId $Id -Name $Id `
            -Stage Drive -Command "Execute the supplied $Id contract with owned fixtures and explicit observations" -Action $Action -ArgumentList $Arguments
        if($Id -eq 'Win1'){
            @{ItemId=$Id;AttemptId=$case.Attempt.Id;Evidence=@($case.Output);Reason='Native routing/key checks completed; review held screenshots because UIA may lose indicator content after foreground changes.'}|
                ConvertTo-Json -Depth 20|Set-Content "$Workspace\pending-visual-review.json"
            return
        }
        Add-PtVerificationAssertion $case.Attempt contract PASS 'Owned native/UIA/input observations' 'All explicit contract comparisons succeeded.' -Evidence @($case.Output)
        Complete-PtVerificationItem $run $Id -Reason 'Observed contract completed'
    }catch{
        $failure=$_
        $review=Get-PtVerificationReview $run -ItemId $Id
        $attempt=Get-PtVerificationAttempt $run -AttemptId $review.Items[0].LatestNormalAttemptId
        $productEvidence=$failure.Exception.Data['PtSgIndicatorRetentionEvidence']
        if($productEvidence){
            Add-PtVerificationAssertion $attempt contract FAIL product $failure.Exception.Message -Evidence @($productEvidence)
        }else{
            Add-PtVerificationAssertion $attempt contract BLOCKED BLK-INFRASTRUCTURE $failure.Exception.Message
        }
        Complete-PtVerificationItem $run $Id -Reason 'Original execution and observed outcome retained; independent cases continue'
        $failures.Add("$Id`: $($failure.Exception.Message)")
    }
}
try{
    $preflight=Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Create explicitly owned fixtures' `
        -Command 'Capture baseline and open one system Calculator window' -ArgumentList @($Workspace) -Action {
            param($attempt,$work)
            New-PtTaskbarFixture -Workspace $work
        }
    $fixture=$preflight.Output[0]
    CheckCase Slots {
        param($attempt,$owned)
        $moves=@(Move-PtTaskbarFixtureToSlot -Fixture $owned -Slot 1 -DragMethod Native)
        $slots=Get-PtTaskbarSlots
        Require ($slots.Apps.Count -ge 3 -and $slots.Apps[0].AppId -ceq $owned.Apps[0].AppId) 'Calculator must be first among at least three identified app slots'
        $proof=CaptureProof $attempt slots @{Moves=$moves;Slots=$slots} 'Fresh observed slot/AppID mapping; foreign relative order retained'
        $image=New-PtVerificationArtifactPath $attempt taskbar-slots.png
        Save-PtPassiveScreenshot -Path $image|Out-Null
        $photo=Add-PtVerificationArtifact $attempt $image Screenshot 'System Calculator first-slot taskbar window'
        @($proof,$photo)
    } @($fixture)
    foreach($entry in $(if(-not $RoutingOnly){@('NamedEvent','Chord')})){
        CheckCase $entry {
            param($attempt,$owned,$entryPath,$work)
            $proofs=[Collections.Generic.List[object]]::new()
            for($cycle=1;$cycle -le 3;$cycle++){
                $close=if($entryPath -eq 'Chord'){'Escape'}else{'CloseButton'}
                $foreground=(Read-PtTaskbarFixture $owned).Marker.Desktop.foreground
                $result=Invoke-PtShortcutGuideCycle -ForegroundTarget $foreground -Workspace $work -Entry $entryPath -CloseRoute $close `
                    -ArgumentList @($proofs,$cycle) -Action {
                        param($session,$evidence,$number)
                        $active=Get-PtActiveVerificationAttempt
                        $image=New-PtVerificationArtifactPath $active "guide-$number.png"
                        Save-PtPassiveScreenshot -Path $image|Out-Null
                        $evidence.Add((Add-PtVerificationArtifact $active $image Screenshot 'Owned full guide survived passive observation'))
                        Get-PtShortcutGuidePresentation $session.GuideTarget
                    }
                $proofs.Add((CaptureProof $attempt "cycle-$cycle" $result 'Actual explicit entry/observation/close flow'))
            }
            $proofs.ToArray()
        } @($fixture,$entry,$Workspace)
    }
    if($fixture.Phase -ne 'Ready'){
        Invoke-PtVerificationCase -Run $run -ItemId Win1 -Name 'Routing prerequisite not established' `
            -Command 'Record the failed slot setup without pressing Windows or a taskbar digit' -ArgumentList @($fixture.Phase,$fixture.LastOperation) -Action {
                param($attempt,$phase,$operation)
                $proof=CaptureProof $attempt setup-incomplete @{Phase=$phase;Operation=$operation} 'Original slot-setup failure'
                Add-PtVerificationAssertion $attempt contract BLOCKED BLK-INCOMPLETE `
                    'Slot setup did not complete safely; held routing was not attempted.' -Evidence @($proof)
            }|Out-Null
        Complete-PtVerificationItem $run Win1 -Reason 'Held routing requires a ready fixture with verified slot mapping'
        $failures.Add('Win1: slot setup incomplete; no held routing attempted')
    }else{
    CheckCase Win1 {
        param($attempt,$owned,$work)
        $proofs=[Collections.Generic.List[object]]::new()
        foreach($key in 91,92,91){
            $foreground=(Read-PtTaskbarFixture $owned).Marker.Desktop.foreground
            $held=Invoke-PtShortcutGuideHold -ForegroundTarget $foreground -Workspace $work -Mode Indicators -WindowsKey $key `
                -ArgumentList @($owned,$key,$proofs) -Action {
                    param($session,$taskbar,$virtualKey,$evidence)
                    $before=Get-PtShortcutGuidePresentation $session.GuideTarget
                    Require ($before.Kind -eq 'Indicators') 'Indicator-only state was not observed before routing'
                    $routed=Invoke-PtTaskbarSlot -Fixture $taskbar -Slot 1 -WhileWindowsHeld -WindowsKey $virtualKey `
                        -AllowedForegroundTarget $session.GuideTarget
                    $after=Get-PtShortcutGuidePresentation $session.GuideTarget
                    $active=Get-PtActiveVerificationAttempt
                    $routingState=@{
                        Before=$before;Routing=$routed;After=$after
                        WinDown=(([PtChord]::GetAsyncKeyState($virtualKey) -band 0x8000) -ne 0)
                    }
                    $nativeRouteProof=CaptureProof $active "routing-state-$($evidence.Count)" $routingState `
                        'Immediate post-routing observation retained before judging indicator lifetime'
                    $evidence.Add($nativeRouteProof)
                    if(-not $after.Visible -and $routingState.WinDown -and $routed.WindowsHeldAfter -and
                        $after.ForegroundHwnd -eq $routed.Target.hwnd){
                        $failure=[InvalidOperationException]::new('Calculator routing succeeded with Windows still held, but SG indicators became hidden before Windows release.')
                        $failure.Data['PtSgIndicatorRetentionEvidence']=$nativeRouteProof
                        throw $failure
                    }
                    Require $after.Visible 'SG host became hidden before Windows release'
                    Require ([PtDesktop]::GetForegroundWindow().ToInt64() -eq $taskbar.Apps[0].Identity.hwnd) 'Win+1 did not route to the exact owned first window'
                    Require (([PtChord]::GetAsyncKeyState($virtualKey) -band 0x8000) -ne 0) 'The outer Windows hold was released by routing'
                    $active=Get-PtActiveVerificationAttempt
                    $image=New-PtVerificationArtifactPath $active held-win1.png
                    Save-PtPassiveScreenshot -Path $image|Out-Null
                    $evidence.Add((Add-PtVerificationArtifact $active $image Screenshot 'Post-routing capture while Windows is held; indicator content requires visual review'))
                    [pscustomobject]@{Before=$before;Routing=$routed;After=$after;WindowsKey=$virtualKey
                        IndicatorContentVerifiedByUia=($after.Kind -eq 'Indicators');VisualReviewRequired=$true}
                }
            Require ($held.AfterRelease.Kind -eq 'Hidden') 'Indicators remained after release'
            Require ([PtDesktop]::GetForegroundWindow().ToInt64() -eq $owned.Apps[0].Identity.hwnd) 'Foreground routing was replaced after release'
            $proofs.Add((CaptureProof $attempt "win1-$($proofs.Count)" $held 'While-held routing and after-release native observations'))
        }
        $proofs.ToArray()
    } @($fixture,$Workspace)
    }
}catch{$rootFailure=$_;throw}
finally{
    if($fixture){
        try{Invoke-PtVerificationCase -Run $run -Context Cleanup -Name 'Remove only owned taskbar fixtures' `
            -Command 'Close tracked owned windows and compare the original taskbar, pin files and desktop' -ArgumentList @($fixture) -Action {
                param($attempt,$owned)
                $result=Remove-PtTaskbarFixture -Fixture $owned
                Require ($result.Closed -and $result.DesktopRestored -and $result.TaskbarCompared) 'Fixture cleanup result does not prove its declared comparisons'
                $path=New-PtVerificationArtifactPath $attempt fixture-restoration.json
                $result|ConvertTo-Json -Depth 20|Set-Content $path
                $proof=Add-PtVerificationArtifact $attempt $path Restoration 'H11 paired fixture cleanup result'
                Add-PtVerificationRestoration $attempt PASS 'Owned fixture windows closed; original taskbar/pins and captured desktop comparison succeeded.' -Evidence @($proof)
            }|Out-Null}catch{
                if($rootFailure){$rootFailure.Exception.Data['FixtureCleanupFailure']=$_.Exception.Message}
                else{throw}
            }
    }
    Set-PtActiveVerificationAttempt -Attempt $null
    $failures.ToArray()|ConvertTo-Json|Set-Content "$Workspace\failures.json"
}
if($failures.Count){"PARTIAL: $($failures -join '; ')"}else{"Native contracts completed; held screenshots require explicit visual review before Win1 verdict."}
"Caller-owned Settings/config/whole-task desktop cleanup remains before finalization: $Workspace"
