#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-statistics-guidance-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. "$skill\scripts\pt-verification-report.ps1"
if(Test-Path -LiteralPath $Workspace){throw 'Use a new test workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$guide=[IO.File]::ReadAllText("$skill\references\reporting-format.md")
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected failure: $Pattern"
}
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message});throw}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
function Get-Example([string]$Label){
    $pattern='(?ms)^```powershell\r?\n(?<code># '+[regex]::Escape($Label)+'\r?\n.*?)^```[ \t]*\r?$'
    $matches=[regex]::Matches($guide,$pattern)
    Require ($matches.Count -eq 1) "Expected one executable documentation example: $Label"
    [scriptblock]::Create($matches[0].Groups['code'].Value)
}
$line='{"type":"tool.execution_start","id":"event-1","timestamp":"2026-09-30T07:40:00.1234567Z","data":{"toolCallId":"call-1","toolName":"powershell"}}'
. (Get-Example 'Statistics UTC parsing')
. (Get-Example 'Statistics execution segments')

Check 'Actual documentation preserves JSON UTC text and fractional ticks' {
    Require ($sessionEvent.timestamp -is [string]) 'JSON timestamp was implicitly converted to DateTime'
    Require ($eventUtc.ToString('o') -ceq '2026-09-30T07:40:00.1234567+00:00') 'UTC instant or fractional precision changed'
    Require ($sessionEvent.data.toolCallId -ceq 'call-1' -and $sessionEvent.data.toolName -ceq 'powershell') 'Session start fields were not decoded'
}
Check 'Equivalent positive and negative offsets select the same instant' {
    $positive=ConvertTo-StatisticsUtc '2026-09-30T15:40:00.1234567+08:00'
    $negative=ConvertTo-StatisticsUtc '2026-09-30T03:40:00.1234567-04:00'
    Require ($positive.UtcTicks -eq $eventUtc.UtcTicks -and $negative.UtcTicks -eq $eventUtc.UtcTicks) 'Offset normalization shifted the event'
}
Check 'Typed UTC/local dates retain their instant without string reparsing' {
    $utc=$eventUtc.UtcDateTime
    $local=$utc.ToLocalTime()
    foreach($value in @($utc,$local,$eventUtc)){
        Require ((ConvertTo-StatisticsUtc $value).UtcTicks -eq $eventUtc.UtcTicks) 'Typed time conversion lost timezone or ticks'
    }
}
Check 'Missing timezone and invalid timestamps are explicit errors' {
    Reject {ConvertTo-StatisticsUtc '2026-09-30T07:40:00'} 'explicit timezone'
    Reject {ConvertTo-StatisticsUtc ([DateTime]::SpecifyKind($eventUtc.UtcDateTime,[DateTimeKind]::Unspecified))} 'no timezone'
    Reject {ConvertTo-StatisticsUtc 'not-a-timeZ'} 'recognized|valid|Parse'
    Reject {ConvertTo-StatisticsUtc 123} 'explicit timezone'
}
$segments=@(
    @{StartUtc='2026-09-30T07:32:00Z';EndUtc='2026-09-30T07:45:00Z'},
    @{StartUtc='2026-09-30T16:04:00+08:00';EndUtc='2026-09-30T16:05:00+08:00'}
)
Check 'Task 2 gap, final dispositions and exact end boundaries are excluded' {
    Require (Test-StatisticsExecutionTime '2026-09-30T07:32:00Z' $segments) 'Execution start excluded'
    Require (Test-StatisticsExecutionTime '2026-09-30T07:44:59.9999999Z' $segments) 'Last included tick excluded'
    Require (-not (Test-StatisticsExecutionTime '2026-09-30T07:45:00Z' $segments)) 'Reporting boundary included'
    Require (-not (Test-StatisticsExecutionTime '2026-09-30T07:55:00Z' $segments)) 'Intervening report work counted'
    Require (Test-StatisticsExecutionTime '2026-09-30T08:04:00Z' $segments) 'Recovery segment excluded'
    Require (-not (Test-StatisticsExecutionTime '2026-09-30T08:09:46Z' $segments)) 'Final outcome assignment counted as execution'
}
Check 'Overlapping, reversed and empty execution ranges are rejected' {
    Reject {Test-StatisticsExecutionTime $eventUtc @($segments[1],$segments[0])} 'ordered'
    Reject {Test-StatisticsExecutionTime $eventUtc @($segments[0],$segments[0])} 'nonoverlapping'
    Reject {Test-StatisticsExecutionTime $eventUtc @(@{StartUtc=$eventUtc;EndUtc=$eventUtc})} 'nonempty'
}
Check 'Session start/completion IDs pair without requiring a tool name on completion' {
    $json=@(
        '{"type":"tool.execution_start","id":"e1","timestamp":"2026-09-30T07:35:00Z","data":{"toolCallId":"controller","toolName":"powershell"}}',
        '{"type":"tool.execution_complete","id":"e2","timestamp":"2026-09-30T07:35:10Z","data":{"toolCallId":"controller","success":true}}',
        '{"type":"tool.execution_start","id":"e3","timestamp":"2026-09-30T15:44:59+08:00","data":{"toolCallId":"view","toolName":"view"}}',
        '{"type":"tool.execution_start","id":"e4","timestamp":"2026-09-30T07:45:00Z","data":{"toolCallId":"statistics","toolName":"powershell"}}',
        '{"type":"tool.execution_start","id":"e5","timestamp":"2026-09-30T08:04:00Z","data":{"toolCallId":"recovery","toolName":"powershell"}}',
        '{"type":"tool.execution_start","id":"e6","timestamp":"2026-09-30T08:09:46Z","data":{"toolCallId":"disposition","toolName":"powershell"}}'
    )
    $events=@($json|ForEach-Object {ConvertFrom-PtReportJson $_})
    $starts=@($events|Where-Object {$_.type -eq 'tool.execution_start' -and (Test-StatisticsExecutionTime $_.timestamp $segments)})
    Require ($starts.Count -eq 3 -and 'controller' -in $starts.data.toolCallId) 'Known request missing or reporting requests included'
    $completions=@{}
    foreach($event in $events|Where-Object type -EQ 'tool.execution_complete'){$completions[$event.data.toolCallId]=$event}
    $end=$completions['controller']
    Require ($end.data.success -eq $true -and -not $end.data.PSObject.Properties['toolName']) 'Completion schema fixture changed'
    $controller=@($starts|Where-Object {$_.data.toolCallId -ceq 'controller'})[0]
    $duration=(ConvertTo-StatisticsUtc $end.timestamp)-(ConvertTo-StatisticsUtc $controller.timestamp)
    Require ($duration.TotalSeconds -eq 10) 'Paired duration incorrect'
    Require (-not $completions.ContainsKey('recovery') -and 'recovery' -in $starts.data.toolCallId) 'Unfinished request was omitted instead of retaining unknown duration'
}
Write-Output "PASS: $($results.Count) executable statistics-guidance groups; no product, clipboard or live session access. $Workspace"
