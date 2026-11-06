# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.
#requires -Version 7.2
. "$PSScriptRoot\pt-verification-report.ps1"

function Get-PtAgentExecutionStatistics {
    <#
    .SYNOPSIS
    Project one session's tool metadata and recorded case metrics into the existing statistics schema.
    .NOTES
    Does not drive UI or emit command, result or conversation payloads. Attribution is explicit, never
    inferred from coincident wall-clock activity. Pending pre-segment entry calls require their known IDs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][string]$SessionLogPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SessionId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]]$ExecutionSegments,
        [string[]]$EntryToolCallId=@(),
        [hashtable]$CaseByToolCallId=@{}
    )
    function Instant($Value) {
        if($Value -is [DateTimeOffset]){return $Value.ToUniversalTime()}
        if($Value -is [DateTime]){return ([DateTimeOffset]$Value).ToUniversalTime()}
        if([string]::IsNullOrWhiteSpace([string]$Value)){throw 'A statistics timestamp is missing.'}
        [DateTimeOffset]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
    }
    function TextProperty([System.Text.Json.JsonElement]$Value,[string]$Name) {
        $property=[System.Text.Json.JsonElement]::new()
        if($Value.ValueKind -eq [System.Text.Json.JsonValueKind]::Object -and
            $Value.TryGetProperty($Name,[ref]$property) -and $property.ValueKind -eq [System.Text.Json.JsonValueKind]::String){
            $property.GetString()
        }
    }
    function Overlaps($Start,$End,$Segments) {
        foreach($segment in $Segments){
            if($Start -lt $segment.End -and $End -gt $segment.Start){return $true}
        }
        $false
    }
    function UnionSeconds($Ranges) {
        $total=0.0;$left=$null;$right=$null
        foreach($range in @($Ranges|Sort-Object Start)){
            if($null -eq $left){$left=$range.Start;$right=$range.End}
            elseif($range.Start -le $right){if($range.End -gt $right){$right=$range.End}}
            else{$total+=($right-$left).TotalSeconds;$left=$range.Start;$right=$range.End}
        }
        if($null -ne $left){$total+=($right-$left).TotalSeconds}
        $total
    }
    $segments=@(foreach($segment in $ExecutionSegments){
        $start=Instant $segment.StartUtc;$end=Instant $segment.EndUtc
        if($end -le $start){throw 'Execution segments must have positive duration.'}
        [pscustomobject]@{Start=$start;End=$end}
    })
    for($i=1;$i -lt $segments.Count;$i++){
        if($segments[$i].Start -lt $segments[$i-1].End){throw 'Execution segments must be ordered and nonoverlapping.'}
    }
    Assert-PtReportNoLink $SessionLogPath
    $calls=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $ends=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $limitations=[Collections.Generic.List[string]]::new()
    $identified=$false;$lineNumber=0
    $stream=[IO.File]::Open($SessionLogPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,
        ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $mapping=$null;$reader=$null
    try{
        $sourceLength=$stream.Length
        if(-not $sourceLength){throw 'The statistics source is empty.'}
        $mapping=[IO.MemoryMappedFiles.MemoryMappedFile]::CreateFromFile($stream,[NullString]::Value,0,
            [IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read,[IO.HandleInheritability]::None,$true)
        $reader=[IO.StreamReader]::new($mapping.CreateViewStream(0,$sourceLength,[IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read))
        while($null -ne ($line=$reader.ReadLine())){
            $lineNumber++
            if([string]::IsNullOrWhiteSpace($line)){continue}
            if($reader.EndOfStream -and -not $line.TrimEnd().EndsWith('}')){
                $limitations.Add('The source snapshot ends in an incomplete JSONL record; that trailing record was not interpreted.')
                break
            }
            if($line -notmatch '"(?:tool\.execution_start|tool\.execution_complete|session\.start|session\.resume|result)"'){continue}
            $document=$null
            try{$document=[System.Text.Json.JsonDocument]::Parse($line)}
            catch{throw "Invalid session metadata JSON at line $lineNumber; no payload is included in this error."}
            try{
                $root=$document.RootElement;$type=TextProperty $root 'type'
                if($type -notin 'tool.execution_start','tool.execution_complete','session.start','session.resume','result'){continue}
                $data=[System.Text.Json.JsonElement]::new()
                [void]$root.TryGetProperty('data',[ref]$data)
                if($type -in 'session.start','session.resume','result'){
                    $observed=if($type -eq 'result'){TextProperty $root 'sessionId'}else{TextProperty $data 'sessionId'}
                    if($observed){
                        if($observed -cne $SessionId){throw 'The statistics source belongs to a different session.'}
                        $identified=$true
                    }
                    continue
                }
                $id=TextProperty $data 'toolCallId'
                if(-not $id){throw "Missing tool-call identity at line $lineNumber."}
                $time=Instant (TextProperty $root 'timestamp')
                if($type -eq 'tool.execution_start'){
                    $name=TextProperty $data 'toolName'
                    if(-not $name -or $calls.ContainsKey($id)){throw 'Missing tool name or duplicate tool start.'}
                    $calls.Add($id,[pscustomobject]@{Id=$id;Name=$name;Start=$time})
                }else{
                    if($ends.ContainsKey($id)){throw 'Duplicate tool completion.'}
                    $success=[System.Text.Json.JsonElement]::new()
                    $succeeded=if($data.TryGetProperty('success',[ref]$success) -and
                        $success.ValueKind -in [System.Text.Json.JsonValueKind]::True,[System.Text.Json.JsonValueKind]::False){$success.GetBoolean()}else{$null}
                    $ends.Add($id,[pscustomobject]@{End=$time;Success=$succeeded})
                }
            }finally{if($document){$document.Dispose()}}
        }
    }finally{
        if($reader){$reader.Dispose()}
        if($mapping){$mapping.Dispose()}
        $stream.Dispose()
    }
    if(-not $identified){throw 'Session identity was not observed in the exact log/stream.'}
    foreach($id in $EntryToolCallId){if(-not $calls.ContainsKey($id)){throw 'A declared entry tool call is missing from the source.'}}
    # Recompute from journal data without depending on an earlier malformed statistics artifact.
    $state=ConvertTo-PtReportState -Run $Run -Events @(Read-PtReportEvents -Run $Run -Fresh)
    $caseIds=@($state.Items.Id)
    foreach($id in $CaseByToolCallId.Keys){
        if(-not $calls.ContainsKey($id) -or $CaseByToolCallId[$id] -cnotin $caseIds){throw 'Explicit tool/case attribution has an unknown identity.'}
    }
    $pendingEarlier=0;$waits=[Collections.Generic.List[object]]::new();$unknownWait=$false
    $records=@(foreach($call in $calls.Values|Sort-Object Start){
        $finish=if($ends.ContainsKey($call.Id)){$ends[$call.Id]}else{$null}
        $startsWithin=@($segments|Where-Object {$call.Start -ge $_.Start -and $call.Start -lt $_.End}).Count -gt 0
        $selected=if($finish){$startsWithin -or (Overlaps $call.Start $finish.End $segments)}else{
            $startsWithin -or
                ($call.Id -cin $EntryToolCallId -and $call.Start -lt $segments[-1].End)
        }
        if(-not $selected){
            if(-not $finish -and $call.Start -lt $segments[0].Start){$pendingEarlier++}
            continue
        }
        if($finish -and $finish.End -lt $call.Start){throw 'Tool completion precedes its start.'}
        if($finish){
            foreach($segment in $segments){
                $left=if($call.Start -gt $segment.Start){$call.Start}else{$segment.Start}
                $right=if($finish.End -lt $segment.End){$finish.End}else{$segment.End}
                if($right -gt $left){$waits.Add(@{Start=$left;End=$right})}
            }
        }else{$unknownWait=$true}
        $caseId=if($CaseByToolCallId.ContainsKey($call.Id)){$CaseByToolCallId[$call.Id]}else{$null}
        $phase=if($caseId){'Case'}elseif($call.Id -cin $EntryToolCallId){'MULTI-CASE'}else{'UNASSIGNED'}
        [pscustomobject]@{
            SessionId=$SessionId;ToolCallId=$call.Id;ToolName=$call.Name
            StartUtc=$call.Start.ToString('o');CompletionUtc=$(if($finish){$finish.End.ToString('o')}else{$null})
            Phase=$phase;CaseId=$caseId;Success=$(if($finish){$finish.Success}else{$null})
        }
    })
    foreach($id in @($EntryToolCallId)+@($CaseByToolCallId.Keys)){
        if($id -cnotin @($records.ToolCallId)){throw 'A declared tool call falls outside the execution segments.'}
    }
    if($pendingEarlier){$limitations.Add('Pending calls that started before the segments were omitted unless explicitly identified by EntryToolCallId.')}
    if($unknownWait){$limitations.Add('At least one selected tool call has no observed completion; wait-union duration is unavailable.')}
    if(@($records|Where-Object Phase -eq 'UNASSIGNED').Count){$limitations.Add('Unmapped requests remain UNASSIGNED; timing overlap alone does not establish a case relationship.')}
    $recordStepIds=@($state.Events|Where-Object {
        $_.Type -eq 'OperationEnded' -and $_.Data.Stage -eq 'Record'
    }|ForEach-Object {$_.Data.StepId})
    $caseRows=@(foreach($item in $state.Items){
        $steps=@($state.Steps|Where-Object {
            $_.ItemId -ceq $item.Id -and -not $_.ParentStepId -and $_.ActionStarted -eq $true -and
            $_.Id -cnotin $recordStepIds -and
            (Overlaps (Instant $_.Start) $(if($_.End){Instant $_.End}else{$segments[-1].End}) $segments)
        })
        $attemptIds=@($steps.AttemptId|Select-Object -Unique)
        $attempts=@($state.Attempts|Where-Object {$_.Id -cin $attemptIds})
        $complete=$steps.Count -gt 0 -and @($steps|Where-Object {-not $_.End -or $null -eq $_.DurationMs}).Count -eq 0
        $covered=$complete
        foreach($step in $steps){
            if(-not $step.End){continue}
            $start=Instant $step.Start;$end=Instant $step.End
            if(-not @($segments|Where-Object {$start -ge $_.Start -and $end -le $_.End}).Count){$covered=$false}
        }
        $ordered=@($steps|Sort-Object {Instant $_.Start})
        if($steps.Count -and -not $covered){$limitations.Add("Case $($item.Id) has incomplete or segment-truncated steps; full driver metrics are unavailable.")}
        [pscustomobject]@{
            CaseId=$item.Id
            NormalAttempts=@($attempts|Where-Object Kind -eq 'Normal').Count
            DiagnosticAttempts=@($attempts|Where-Object Kind -eq 'Diagnostic').Count
            RecordedDriverSeconds=$(if($covered){[double](($steps|Measure-Object DurationMs -Sum).Sum)/1000}else{$null})
            CaseSpanSeconds=$(if($covered){
                $last=($steps|ForEach-Object {Instant $_.End}|Sort-Object|Select-Object -Last 1)
                ($last-(Instant $ordered[0].Start)).TotalSeconds
            }else{$null})
            FailedDriverSteps=$(if($complete){@($steps|Where-Object {$_.Status -eq 'ERROR' -or $_.Error}).Count}else{$null})
        }
    })
    if(-not $records.Count -and @($caseRows|Where-Object {$_.NormalAttempts -gt 0 -or $_.DiagnosticAttempts -gt 0}).Count){
        throw 'Recorded execution has no matching agent requests; verify the source and segments rather than publishing zero.'
    }
    [pscustomobject]@{
        RunId=$Run.Id;CountingMode='agent-origin-requests'
        Coverage=$(if($limitations.Count){'partial'}else{'complete'})
        SourceSessionId=$SessionId;CollectedAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
        ExecutionSegments=@($segments|ForEach-Object {@{StartUtc=$_.Start.ToString('o');EndUtc=$_.End.ToString('o')}})
        ModuleTotals=@{AgentToolRequests=$records.Count;ExecutionLifecycleWallSeconds=(UnionSeconds $segments)
            ToolResponseWaitUnionSeconds=$(if($unknownWait){$null}else{UnionSeconds $waits})}
        AttributionRecords=$records;Cases=$caseRows
        NonCaseRows=@($records|Where-Object {-not $_.CaseId}|Group-Object Phase|ForEach-Object {@{Phase=$_.Name;AgentToolRequests=$_.Count}})
        Limitations=@($limitations)
    }
}

function Add-PtAgentExecutionStatistics {
    <#.SYNOPSIS
    Collect and register statistics inside the template's protected Report callback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Attempt,
        [Parameter(Mandatory)][string]$SessionLogPath,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][object[]]$ExecutionSegments,
        [string[]]$EntryToolCallId=@(),
        [hashtable]$CaseByToolCallId=@{}
    )
    Assert-PtReportAttempt $Attempt
    if($Attempt.Phase -ne 'Diagnostic' -or $Attempt.Kind -ne 'Diagnostic'){throw 'Statistics registration requires a reporting-only Diagnostic attempt.'}
    $arguments=@{}+$PSBoundParameters
    $arguments.Remove('Attempt')
    $statistics=Get-PtAgentExecutionStatistics -Run $Attempt.Run @arguments
    $path=New-PtVerificationArtifactPath -Attempt $Attempt -Name 'statistics.json'
    Write-PtReportText $path (ConvertTo-Json $statistics -Depth 20)
    Add-PtVerificationArtifact -Attempt $Attempt -Path $path -Kind Evidence -Description 'Current-session bounded agent metadata and outer recorded case metrics; no private payloads'
}
