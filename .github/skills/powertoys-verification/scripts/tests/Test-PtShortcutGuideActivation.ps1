#requires -Version 7.2
param([Parameter(Mandatory)][string]$Workspace,[Parameter(Mandatory)][long]$ForegroundHwnd,
    [ValidateRange(1,5)][int]$Iterations=2)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-shortcut-guide-entrypoints.ps1"
$helpers=Split-Path $PSScriptRoot -Parent
$run=New-PtVerificationRun -Workspace $Workspace -Module 'SG activation diagnosis' `
    -Bits "Installed PowerToys $((Get-Process PowerToys).FileVersion), immutable; diagnostic comparisons only" `
    -Scenario InfrastructureAcceptance -Items @(
        @{Id='Activation';Description='Controlled native-only versus UIA activation observation';Admin='NO';Clarity='CLEAR';UserVisible=$false
            Assertions=@(@{Id='comparison';Description='Record native visibility before and after one activation without inferring a product fix'})}
    ) -Inputs @(@{Name='SKILL.md';Role='Skill';Path="$helpers\..\SKILL.md"}
        @{Name='test.ps1';Role='Checklist';Path=$PSCommandPath}
        foreach($file in @(Get-ChildItem -LiteralPath $helpers -File -Filter '*.ps1'|Where-Object Name -ne pt-session-diagnose.ps1)){
            @{Name=$file.Name;Role='Helper';Path=$file.FullName}
        })
$baseline=$null;$guide=$null;$failure=$null
$facts=[Collections.Generic.List[object]]::new()
function Proof($Attempt,[string]$Name,$Value,[string]$Kind='Evidence'){
    $path=New-PtVerificationArtifactPath $Attempt "$Name.json"
    ConvertTo-Json -InputObject $Value -Depth 20|Set-Content $path
    Add-PtVerificationArtifact $Attempt $path $Kind $Name
}
try{
    $preflight=Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Record native baseline' `
        -Command 'Capture original desktop and hidden SG identity; no settings mutation or restart' -ArgumentList @($ForegroundHwnd) -Action {
            param($attempt,$targetHwnd)
            $desktop=Get-PtDesktopSnapshot -WindowHwnd @($targetHwnd)
            $hostWindow=Get-PtShortcutGuideHost
            if($hostWindow.Visible){throw 'Guide is already visible; diagnostic does not own it.'}
            $context=@{Desktop=$desktop;Guide=(Get-PtWindowIdentity $hostWindow.Hwnd)
                Target=(Get-PtWindowIdentity $targetHwnd);Configuration=(Get-PtSgFlowConfiguration)}
            Proof $attempt baseline $context|Out-Null
            $context
        }
    $context=$preflight.Output[0];$baseline=$context.Desktop;$guide=$context.Guide
    foreach($entry in 'NamedEvent','Chord'){
        foreach($observer in 'NativeOnly','UIA'){
            foreach($iteration in 1..$Iterations){
                $case=Invoke-PtVerificationCase -Run $run -ItemId Activation -Kind Diagnostic -Name "$entry-$observer-$iteration" `
                    -Command 'One activation, no subsequent input/focus action during 1.2 seconds of observation; close only afterward' `
                    -ArgumentList @($context,$entry,$observer,$iteration) -Action {
                        param($attempt,$scope,$entryPath,$observationMode,$number)
                        Assert-PtWindowIdentity $scope.Guide
                        if((Get-PtNativeWindow -Hwnd $scope.Guide.hwnd).Visible){throw 'Prior diagnostic did not leave a hidden guide.'}
                        Assert-PtForegroundOrAbort -Hwnd $scope.Target.hwnd
                        Assert-PtShortcutInputIdle
                        $samples=[Collections.Generic.List[object]]::new()
                        $clock=[Diagnostics.Stopwatch]::StartNew()
                        $activationTime=[DateTimeOffset]::UtcNow.ToString('o')
                        if($entryPath -eq 'NamedEvent'){
                            Invoke-PtSharedEvent -Name ShortcutGuide.Trigger|Out-Null
                        }else{
                            $binding=$scope.Configuration.Chord
                            $mods=@(if($binding.win){91};if($binding.ctrl){17};if($binding.alt){18};if($binding.shift){16})
                            Send-PtChord -Hwnd $scope.Target.hwnd -Mods $mods -Key $binding.code|Out-Null
                        }
                        $lastSignature=''
                        try{
                            do{
                                $before=Get-PtNativeWindow -Hwnd $scope.Guide.hwnd
                                $foregroundBefore=[PtDesktop]::GetForegroundWindow().ToInt64()
                                $presentation=if($observationMode -eq 'UIA'){Get-PtShortcutGuidePresentation $scope.Guide}else{$null}
                                $after=Get-PtNativeWindow -Hwnd $scope.Guide.hwnd
                                $foregroundAfter=[PtDesktop]::GetForegroundWindow().ToInt64()
                                $held=@(1,2,16,17,18,27,91,92|Where-Object {([PtChord]::GetAsyncKeyState($_) -band 0x8000) -ne 0})
                                $signature="$($before.Visible)|$($after.Visible)|$foregroundBefore|$foregroundAfter|$($presentation.Kind)|$($held -join ',')"
                                if($signature -cne $lastSignature){
                                    $samples.Add(@{Milliseconds=$clock.Elapsed.TotalMilliseconds;VisibleBefore=$before.Visible;VisibleAfter=$after.Visible
                                        ForegroundBefore=$foregroundBefore;ForegroundAfter=$foregroundAfter;Presentation=$presentation.Kind;HeldKeys=$held})
                                    $lastSignature=$signature
                                }
                                Start-Sleep -Milliseconds 20
                            }while($clock.Elapsed.TotalMilliseconds -lt 1200)
                            $result=@{Entry=$entryPath;Observer=$observationMode;Iteration=$number;ActivationTime=$activationTime
                                Chord=$scope.Configuration.Chord;Guide=$scope.Guide;Samples=$samples.ToArray()
                                FinalVisible=(Get-PtNativeWindow -Hwnd $scope.Guide.hwnd).Visible}
                            Proof $attempt observation $result|Out-Null
                            $result
                        }finally{
                            if((Get-PtNativeWindow -Hwnd $scope.Guide.hwnd).Visible){
                                Invoke-PtWinApp -Arguments @('invoke','CloseButton','-w',"$($scope.Guide.hwnd)")|Out-Null
                            }
                            Wait-PtCondition -Description 'hidden guide after diagnostic cleanup' -TimeoutSeconds 5 -Probe {
                                -not (Get-PtNativeWindow -Hwnd $scope.Guide.hwnd).Visible
                            }|Out-Null
                        }
                    }
                $facts.Add($case.Output[0])
            }
        }
    }
    Complete-PtVerificationItem $run Activation -Reason 'Diagnostic samples recorded; no Normal-path PASS or product fix inferred'
}catch{$failure=$_}
finally{
    if($baseline){
        try{
            Invoke-PtVerificationCase -Run $run -Context Cleanup -Name 'Restore original desktop' -Command 'Compare exact original foreground, pointer and tracked placement' `
                -ArgumentList @($baseline) -Action {
                    param($attempt,$original)
                    $restored=Restore-PtDesktopSnapshot $original
                    $proof=Proof $attempt restoration $restored Restoration
                    Add-PtVerificationRestoration $attempt PASS 'No product settings changed; original desktop restored.' -Evidence @($proof)
                }|Out-Null
        }catch{if($failure){$failure.Exception.Data['CleanupFailure']=$_.Exception.Message}else{$failure=$_}}
    }
    ConvertTo-Json -InputObject $facts.ToArray() -Depth 20|Set-Content "$Workspace\activation-comparison.json"
    Set-PtActiveVerificationAttempt -Attempt $null
    Complete-PtVerificationRun $run -Retrospective @(@{Friction='Diagnostic-only activation comparison, not a repaired product or completed module checklist.'
        Source='HELPER-FLAW';Severity='MED';Cost="$($facts.Count) controlled samples";SuggestedFix='Use the recorded native visibility and product logs to attribute early dismissal.'})|Out-Null
    Test-PtVerificationArchive -Workspace $Workspace|Out-Null
}
if($failure){throw $failure}
$facts.ToArray()|ForEach-Object {[pscustomobject]@{Entry=$_.Entry;Observer=$_.Observer;Iteration=$_.Iteration;FinalVisible=$_.FinalVisible}}|Format-Table
"Diagnostic evidence: $Workspace"
