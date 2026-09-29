# Explicit sequential cleanup stages over the existing recorder, not a scheduler.
function Assert-PtCleanupPlan {
    param([Parameter(Mandatory)][object[]]$Steps)
    if(-not $Steps.Count){throw 'Cleanup plan must contain explicit resource comparisons.'}
    $phases=@('Input','Clipboard','Ui','Quiesce','Files','Lifecycle','Windows','Verify')
    $known=@{};$previous=-1
    foreach($step in $Steps){
        if(-not $step.Id -or $known.ContainsKey($step.Id) -or $step.Action -isnot [scriptblock] -or $step.Verify -isnot [scriptblock]){
            throw 'Cleanup steps need unique IDs and explicit Action/Verify blocks.'
        }
        Assert-PtReportName $step.Id
        $phase=[array]::IndexOf($phases,$step.Phase)
        if($phase -lt $previous -or $phase -lt 0){throw 'Cleanup phases must follow the declared safe order.'}
        foreach($dependency in @($step.DependsOn)){if(-not $known.ContainsKey($dependency)){throw 'Cleanup dependency must reference an earlier step.'}}
        $known[$step.Id]=$true;$previous=$phase
    }
}

function Invoke-PtCleanupPlan {
    <#.SYNOPSIS
    Execute declared restoration stages, gate dependent stages on verified success, and retain every result.
    #>
    param([Parameter(Mandatory)]$Attempt,[Parameter(Mandatory)][object[]]$Steps)
    $ErrorActionPreference='Stop'
    if($Attempt.Phase -ne 'Cleanup' -or $Attempt.Kind -ne 'Normal'){throw 'Cleanup plan requires a Normal Cleanup attempt.'}
    Assert-PtCleanupPlan $Steps
    $outcomes=@{};$rows=@()
    foreach($step in $Steps){
        $row=[ordered]@{Resource=$step.Id;Phase=$step.Phase;Verdict='BLOCKED';Reason=$null}
        $unmet=@($step.DependsOn|Where-Object {$outcomes[$_] -ne 'PASS'})
        if($unmet.Count){$row.Reason="Unresolved dependencies: $($unmet -join ', ')"}
        else{
            try{
                Invoke-PtVerificationStep -Attempt $Attempt -Name "Restore $($step.Id)" `
                    -Command "Run explicit $($step.Phase) cleanup and verify $($step.Id)" `
                    -ArgumentList @($step.Action,$step.Verify,@($step.Arguments)) -Action {
                        param($action,$verify,$arguments)
                        & $action @arguments|Out-Null
                        $actual=@(& $verify @arguments)
                        if($actual.Count -ne 1 -or $actual[0] -isnot [bool] -or -not $actual[0]){
                            throw 'Cleanup verifier must return exactly Boolean true.'
                        }
                        $true
                    }|Out-Null
                $row.Verdict='PASS';$row.Reason='Declared resource comparison succeeded.'
            }catch{$row.Reason=$_.Exception.Message}
        }
        $outcomes[$step.Id]=$row.Verdict;$rows+=@([pscustomobject]$row)
        $file=New-PtVerificationArtifactPath -Attempt $Attempt -Name "cleanup-$($step.Id).json"
        Write-PtReportText $file (ConvertTo-Json $row -Depth 6)
        $evidence=Add-PtVerificationArtifact -Attempt $Attempt -Path $file -Kind Restoration -Description "Cleanup $($step.Id), phase $($step.Phase)"
        Add-PtVerificationRestoration -Attempt $Attempt -Verdict $row.Verdict -Reason "$($step.Id): $($row.Reason)" -Evidence @($evidence)
    }
    if(@($rows|Where-Object Verdict -ne 'PASS').Count){
        $error=[InvalidOperationException]::new('Cleanup incomplete; independent steps attempted, dependent unsafe steps withheld.')
        $error.Data['CleanupResults']=$rows
        throw $error
    }
    $rows
}
