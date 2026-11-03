#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "verify-FancyZones-P0P1-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'){throw 'Use pwsh -STA.'}
if(Test-Path -LiteralPath $Workspace){throw 'Use a new acceptance workspace.'}
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach($name in 'pt-desktop','pt-foreground-guard','pt-verification-report','pt-session-safety','pt-state-snapshot','pt-owned-capture'){
    . "$skill\scripts\$name.ps1"
}
$fixtureRoot=Join-Path $env:TEMP "pt-capture-fixture-$([guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($fixtureRoot)|Out-Null
$exe=Join-Path $fixtureRoot 'CaptureSurface.exe'
$source="$PSScriptRoot\fixtures\CaptureSurface.cs"
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll "/out:$exe" $source
if($LASTEXITCODE -ne 0){throw 'Capture fixture build failed.'}
$items=@(
    @{Id='capture-guard';Description='Unregistered intersecting window prevents capture';Admin='NO';Clarity='CLEAR';UserVisible=$false
        Assertions=@(@{Id='refusal';Description='No pixels are published for an unregistered above-background window'})},
    @{Id='composed';Description='Owned transparent overlay is captured over owned opaque content';Admin='NO';Clarity='CLEAR';UserVisible=$true
        Assertions=@(@{Id='pixels';Description='Captured pixels include the actual translucent layer, not just its underlying window'})},
    @{Id='region';Description='A scoped capture never expands to the whole window';Admin='NO';Clarity='CLEAR';UserVisible=$true
        Assertions=@(@{Id='bounds';Description='Accepted image dimensions equal the requested contained region'})},
    @{Id='lifecycle';Description='Owned capture fixture exits through its normal shutdown protocol';Admin='NO';Clarity='CLEAR';UserVisible=$false
        Assertions=@(@{Id='exit';Description='Exact process and all registered windows are absent after shutdown'})}
)
$run=New-PtVerificationRun -Workspace $Workspace -Module 'FancyZones P0 P1 helper acceptance' `
    -Scenario InfrastructureAcceptance -Bits 'Owned synthetic WinForms fixture; no PowerToys state changes; actual composed desktop capture' `
    -Items $items -Inputs @(Get-PtVerificationInputs -Skill $skill -Inputs @(
        @{Name='acceptance.ps1';Role='Checklist';Path=$PSCommandPath},
        @{Name='CaptureSurface.cs';Role='Other';Path=$source},
        @{Name='CaptureSurface.exe';Role='Other';Path=$exe}))
$plan=@{Schema='PtRunResources.v1';Resources=@(@{Id='fixture';Kind='Process';Ownership='Owned';FilePath=$exe;RestoreStep='fixture-exit'})}
$session=New-PtResourceSession $run -ResourcePlan $plan
$session.ResourcePlan=$plan;Save-PtResourceSession $session
$desktop=$null;$creation=$null;$ready=$null;$failure=$null
function Require($Condition,$Message){if(-not $Condition){throw $Message}}
function Proof($Attempt,$Name,$Value,[string]$Kind='Evidence'){
    $path=New-PtVerificationArtifactPath $Attempt "$Name.json"
    Write-PtReportText $path (ConvertTo-Json $Value -Depth 12)
    Add-PtVerificationArtifact $Attempt $path $Kind $Name -Synthetic
}
try{
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Preserve desktop and declare capture fixture' `
        -Command 'Read interactive desktop baseline and verify native fixture prerequisites' -Action {
            param($attempt)
            if(-not [PtDesktop]::GetForegroundWindow()){throw 'No interactive desktop.'}
            $script:desktop=Get-PtDesktopSnapshot
            Proof $attempt 'desktop-baseline' $script:desktop|Out-Null
        }|Out-Null
    Invoke-PtVerificationCase -Run $run -Context Preflight -Name 'Launch declared owned capture fixture' `
        -Command 'Start exact fixture executable, observe actual windows and initially register only target/background' -Action {
            param($attempt)
            $script:creation=Start-PtOwnedProcess -FilePath $exe -ArgumentList @("`"$fixtureRoot`"")
            $script:ready=Wait-PtCondition -Description 'owned capture fixture ready' -TimeoutSeconds 10 -Probe {
                if(Test-Path "$fixtureRoot\ready.json"){Get-Content "$fixtureRoot\ready.json" -Raw|ConvertFrom-Json}
            }
            foreach($hwndValue in @($script:ready.target,$script:ready.background)){
                Register-PtCreatedWindow (Get-PtWindowIdentity $hwndValue) $script:creation|Out-Null
            }
            Proof $attempt 'fixture-identities' $script:ready|Out-Null
        }|Out-Null
    $target=Get-PtWindowIdentity $ready.target
    $background=Get-PtWindowIdentity $ready.background
    Invoke-PtVerificationCase -Run $run -ItemId capture-guard -Name 'Refuse unregistered overlay before capturing' `
        -Command 'Request a composed capture with a deliberately unregistered synthetic sibling; verify no output' -Action {
            param($attempt)
            $path=Join-Path $fixtureRoot 'must-not-exist.png'
            $denied=$null
            try{Save-PtOwnedScreenshot -Path $path -WindowIdentity @($target) -OpaqueBackgroundIdentity $background|Out-Null}
            catch{$denied=$_.Exception.Message}
            Require ($denied -match 'unowned above-background' -and -not(Test-Path $path)) 'Unregistered overlay was not rejected before publication.'
            $evidence=Proof $attempt 'capture-refusal' @{Rejected=$true;OutputAbsent=$true;Reason=$denied}
            Add-PtVerificationAssertion $attempt refusal PASS 'Ownership guard' 'Actual overlapping unregistered HWND was refused before capture.' @($evidence)
        }|Out-Null
    Complete-PtVerificationItem $run capture-guard -Reason 'Actual ownership refusal observed'
    Register-PtCreatedProcessWindows $creation|Out-Null
    foreach($case in 'composed','region'){
        Invoke-PtVerificationCase -Run $run -ItemId $case -Name "Capture $case owned scene" `
            -Command 'Capture only inside the owned opaque background; independently inspect dimensions and translucent pixels' `
            -ArgumentList @($case) -Action {
                param($attempt,$caseId)
                $overlay=Get-PtNativeWindow -Hwnd $ready.overlay
                $scope=Get-PtCaptureWindowBounds -WindowIdentity @($target)
                $region=if($caseId -eq 'region'){
                    [pscustomobject]@{Left=[int]($overlay.Rect.Left+10);Top=[int]($overlay.Rect.Top+10);Width=80;Height=60}
                }else{[pscustomobject]@{Left=$scope.Left;Top=$scope.Top;Width=$scope.Width;Height=$scope.Height}}
                $path=New-PtVerificationArtifactPath $attempt "$caseId.png"
                Save-PtOwnedScreenshot -Path $path -WindowIdentity @($target) -OpaqueBackgroundIdentity $background -Region $region|Out-Null
                $bitmap=[Drawing.Bitmap]::new($path)
                try{
                    $x=if($caseId -eq 'region'){40}else{[int]($overlay.Rect.Left+90-$region.Left)}
                    $y=if($caseId -eq 'region'){30}else{[int]($overlay.Rect.Top+60-$region.Top)}
                    $pixel=$bitmap.GetPixel($x,$y)
                    Require ($bitmap.Width -eq $region.Width -and $bitmap.Height -eq $region.Height) 'Capture dimensions expanded or changed.'
                    Require ($pixel.R -gt 220 -and $pixel.G -ge 90 -and $pixel.G -le 170 -and $pixel.B -ge 90 -and $pixel.B -le 170) 'Composed translucent red layer was missing or incorrect.'
                    $facts=@{Width=$bitmap.Width;Height=$bitmap.Height;R=[int]$pixel.R;G=[int]$pixel.G;B=[int]$pixel.B}
                }finally{$bitmap.Dispose()}
                $image=Add-PtVerificationArtifact $attempt $path Screenshot 'Actual owned synthetic layered-window capture' -Synthetic
                Add-PtVerificationArtifact $attempt "$path.state.json" Evidence 'Before/after owned capture scene' -Synthetic|Out-Null
                $evidence=Proof $attempt 'actual-pixels' $facts
                $assertion=if($caseId -eq 'region'){'bounds'}else{'pixels'}
                Add-PtVerificationAssertion $attempt $assertion PASS 'Composed pixels and native bounds' 'Actual translucent pixels and requested image dimensions matched.' @($image,$evidence)
            }|Out-Null
        Complete-PtVerificationItem $run $case -Reason 'Actual captured pixels independently inspected'
    }
    Invoke-PtVerificationCase -Run $run -ItemId lifecycle -Name 'Normal exact fixture exit' `
        -Command 'Request fixture exit once and observe exact process/window absence' -Action {
            param($attempt)
            $receipt=Stop-PtOwnedProcess $creation -RequestExit {param($identity,$directory) [IO.File]::WriteAllText((Join-Path $directory 'exit'),'exit')} `
                -ArgumentList @($fixtureRoot) -TimeoutSeconds 10
            foreach($hwndValue in @($ready.target,$ready.background,$ready.overlay)){
                Require (-not [PtDesktop]::IsWindow([IntPtr][long]$hwndValue)) 'Owned capture window survived normal exit.'
            }
            $evidence=Proof $attempt 'normal-exit' $receipt
            Add-PtVerificationAssertion $attempt exit PASS 'Exact process lifetime' 'Owned fixture and all three windows exited through the normal protocol.' @($evidence)
        }|Out-Null
    Complete-PtVerificationItem $run lifecycle -Reason 'Process and sibling absence observed'
}catch{$failure=$_}
finally{
    try{
        Invoke-PtVerificationCase -Run $run -Context Cleanup -Name 'Restore desktop and certify resource obligations' `
        -Command 'Normally close any remaining owned fixture, restore original desktop and independently compare resources' -Action {
            param($attempt)
            if($creation){
                Register-PtCreatedProcessWindows $creation|Out-Null
                Stop-PtOwnedProcess $creation -RequestExit {param($identity,$directory) [IO.File]::WriteAllText((Join-Path $directory 'exit'),'exit')} `
                    -ArgumentList @($fixtureRoot) -TimeoutSeconds 10|Out-Null
            }
            if($desktop){
                $restored=Restore-PtDesktopSnapshot $desktop
                $proof=Proof $attempt 'desktop-restoration' $restored Restoration
                Add-PtVerificationRestoration $attempt PASS 'Original foreground and pointer restoration verified.' @($proof)
            }
            Complete-PtResourceSession $attempt|Out-Null
        }|Out-Null
    }catch{
        if($failure){$failure.Exception.Data['CleanupFailure']=$_.Exception.Message}else{$failure=$_}
    }
    if(-not $failure){$global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}}
    Export-PtVerificationReport $run|Out-Null
}
if($failure){throw $failure}
"ACCEPTANCE_READY_FOR_FINALIZATION: $Workspace"
