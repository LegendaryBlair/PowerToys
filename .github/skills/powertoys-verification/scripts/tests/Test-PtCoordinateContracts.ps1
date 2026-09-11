param([Parameter(Mandatory)][string]$Workspace)
$ErrorActionPreference='Stop'
$helpers=Split-Path $PSScriptRoot -Parent
foreach($name in 'pt-desktop','pt-state-snapshot','pt-foreground-guard'){. "$helpers\$name.ps1"}
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$baseline=Get-PtDesktopSnapshot
$baseline|ConvertTo-Json -Depth 10|Set-Content "$Workspace\baseline.json"
$observations=[Collections.Generic.List[object]]::new()
try{
    if(-not [PtDesktop]::SetCursorPos(300,200)){throw 'Cannot set the owned pointer probe position'}
    $window=$baseline.foreground.hwnd
    $expectedPlacement=Get-PtWindowSnapshot $window|ConvertTo-Json -Depth 10 -Compress
    foreach($context in -1,-2,-4){
        $previous=[PtDesktop]::SetThreadDpiAwarenessContext([IntPtr]$context)
        if($previous -eq [IntPtr]::Zero){throw "Cannot enter DPI context $context"}
        try{
            $actual=Get-PtDesktopSnapshot
            $placement=Get-PtWindowSnapshot $window|ConvertTo-Json -Depth 10 -Compress
            $observations.Add(@{Context=$context;Pointer=$actual.pointer;PlacementMatches=($placement -ceq $expectedPlacement);ActualPlacement=$placement;ExpectedPlacement=$expectedPlacement;Status='Observed'})
            if($actual.pointer.X -ne 300 -or $actual.pointer.Y -ne 200 -or $placement -cne $expectedPlacement){
                throw "Coordinate units changed in DPI awareness context $context"
            }
            Restore-PtDesktopSnapshot $actual|Out-Null
            $observations[-1].Status='PASS'
        }finally{[void][PtDesktop]::SetThreadDpiAwarenessContext($previous)}
    }
    $legacy=$baseline|ConvertTo-Json -Depth 10|ConvertFrom-Json
    $legacy.PSObject.Properties.Remove('coordinateSpace')
    $rejected=$false
    try{Restore-PtDesktopSnapshot $legacy|Out-Null}catch{
        if($_.Exception.Message -notmatch 'unspecified coordinate units'){throw}
        $rejected=$true
    }
    if(-not $rejected){throw 'Legacy ambiguous coordinate units were silently accepted'}
    $observations.Add(@{Name='Unspecified legacy snapshot rejected before mutation';Status='PASS'})
}finally{
    try{Restore-PtDesktopSnapshot $baseline|ConvertTo-Json -Depth 10|Set-Content "$Workspace\restored.json"}
    finally{$observations|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
"PASS: 4 DPI coordinate contract groups. $Workspace"
