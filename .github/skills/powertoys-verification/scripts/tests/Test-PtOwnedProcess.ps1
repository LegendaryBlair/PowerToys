#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-owned-process-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
foreach($helper in 'pt-desktop','pt-verification-report','pt-session-safety','pt-cleanup-plan'){
    . "$skill\scripts\$helper.ps1"
}
if(Test-Path -LiteralPath $Workspace){throw 'Use a new test workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$source=Join-Path $Workspace 'HeadlessFixture.cs'
$exe=Join-Path $Workspace 'HeadlessFixture.exe'
[IO.File]::WriteAllText($source,@'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
static class HeadlessFixture {
    static void Main(string[] args) {
        File.WriteAllText(args[0] + ".ready", Process.GetCurrentProcess().Id.ToString());
        var timer = Stopwatch.StartNew();
        while (!File.Exists(args[0]) && timer.Elapsed.TotalSeconds < 30) Thread.Sleep(50);
    }
}
'@)
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe "/out:$exe" $source
if($LASTEXITCODE -ne 0){throw 'Headless synthetic fixture compilation failed.'}
$signals=[Collections.Generic.List[string]]::new()
$creations=[Collections.Generic.List[object]]::new()
function Require($condition,$message){if(-not $condition){throw $message}}
try{
    $plan=@{Schema='PtRunResources.v1';Resources=@(@{Id='headless';Kind='Process';Ownership='Owned';FilePath=$exe;RestoreStep='exit'})}
    $steps=@(@{Id='exit';Phase='Quiesce';DependsOn=@();Action={};Verify={$true}})
    Assert-PtRunResourcePlan $plan $steps
    $run=New-PtVerificationRun -Workspace "$Workspace\run" -Module 'Headless ownership fixture' `
        -Bits 'Synthetic no-window executable; no product/UI actions' -Scenario InfrastructureAcceptance `
        -Items @(@{Id='identity';Description='Headless process ownership';Admin='NO';Clarity='CLEAR';UserVisible=$false
            Assertions=@(@{Id='exit';Description='Observed exact process exit'})}) `
        -Inputs @(Get-PtVerificationInputs -Skill $skill -Inputs @(@{Name='test.ps1';Role='Checklist';Path=$PSCommandPath}))
    $session=New-PtResourceSession $run -ResourcePlan $plan
    $session.ResourcePlan=$plan;Save-PtResourceSession $session
    foreach($mode in 'direct','indirect'){
        $signal=Join-Path $Workspace "$mode.exit";$signals.Add($signal)
        $creation=if($mode -eq 'direct'){
            Start-PtOwnedProcess -FilePath $exe -ArgumentList @("`"$signal`"")
        }else{
            Invoke-PtOwnedProcessActivation -FilePath $exe -Action {
                param($path,$exitFile)
                Start-Process -FilePath $path -ArgumentList @("`"$exitFile`"") -PassThru|Out-Null
            } -ArgumentList @($exe,$signal)
        }
        $creations.Add($creation)
        Wait-PtCondition -Description 'headless fixture ready' -TimeoutSeconds 5 -Probe {[IO.File]::Exists("$signal.ready")}|Out-Null
        Require (@(Get-PtNativeWindow -ProcessId $creation.ProcessId).Count -eq 0) 'Fixture unexpectedly created a native window'
        $identity=Get-PtResourceProcessIdentity $creation.ProcessId
        Require ($identity.path -ieq $exe -and $identity.processStartTicks -eq $creation.ProcessStartTicks) 'Kernel identity differs from creation receipt'
        $attempt=Start-PtVerificationAttempt $run -Context Cleanup -Kind Normal -Name "$mode still alive"
        $blocked=$false
        try{Complete-PtResourceSession $attempt|Out-Null}catch{$blocked=$_.Exception.Message -match 'unresolved ownership'}
        finally{Stop-PtVerificationAttempt $attempt -Reason 'Expected live-process cleanup blocker'}
        Require $blocked 'Live headless helper was omitted from restoration'
        $receipt=Stop-PtOwnedProcess $creation -RequestExit {
            param($identity,$exitFile)
            [IO.File]::WriteAllText($exitFile,'exit')
        } -ArgumentList @($signal)
        Require ($receipt.Exited -and -not (Get-PtResourceProcessIdentity $creation.ProcessId)) 'Headless exit was not independently observed'
    }
    $attempt=Start-PtVerificationAttempt $run -Context Cleanup -Kind Normal -Name 'Final headless absence'
    try{Complete-PtResourceSession $attempt|Out-Null}
    finally{Stop-PtVerificationAttempt $attempt -Reason 'Both owned helpers exited'}
    [IO.File]::WriteAllText("$Workspace\results.json",'{"Direct":"PASS","Indirect":"PASS","LiveProcessBlocksCleanup":"PASS","IdentityAndExit":"PASS","InteractiveDesktopRequired":false}')
}finally{
    foreach($signal in $signals){[IO.File]::WriteAllText($signal,'exit')}
    foreach($creation in $creations){
        $process=Get-Process -Id $creation.ProcessId -ErrorAction SilentlyContinue
        if($process -and $process.StartTime.ToUniversalTime().Ticks -eq $creation.ProcessStartTicks){
            if(-not $process.WaitForExit(35000)){throw "Owned headless fixture $($creation.ProcessId) did not exit."}
        }
    }
    $global:PtActiveResourceSession=$null;$global:PtLiveResourceGuards=@{}
}
"PASS: direct/indirect no-window process ownership and exit; no product or interactive desktop used. $Workspace"
