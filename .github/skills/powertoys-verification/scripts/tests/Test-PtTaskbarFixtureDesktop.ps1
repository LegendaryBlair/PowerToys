#requires -Version 7.2
param([Parameter(Mandatory)][string]$Workspace)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-taskbar-fixture.ps1"
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$fixture=$null;$failure=$null
$facts=[Collections.Generic.List[object]]::new()
try{
    $fixture=New-PtTaskbarFixture -Workspace $Workspace -Count 3
    foreach($index in 3,2,1){
        $facts.Add((Move-PtTaskbarFixtureToSlot -Fixture $fixture -AppIndex $index -Slot 1))
    }
    $slots=Get-PtTaskbarSlots
    for($index=0;$index -lt 3;$index++){
        if($slots.Apps[$index].AppId -cne $fixture.Apps[$index].AppId){throw 'Owned first three slot identities differ from actual order'}
    }
    foreach($iteration in 1..3){
        Assert-PtForegroundOrAbort -Hwnd $fixture.Apps[1].Identity.hwnd
        $route=Invoke-PtTaskbarSlot -Fixture $fixture -Slot 1
        if($route.ForegroundHwnd -ne $fixture.Apps[0].Identity.hwnd -or $route.WindowsHeldAfter){throw 'Standalone Win+1 did not route/release correctly'}
        $facts.Add($route)
    }
}catch{$failure=$_}
finally{
    $facts|ConvertTo-Json -Depth 25|Set-Content "$Workspace\observations.json"
    if($fixture){
        try{
            $cleanup=Remove-PtTaskbarFixture -Fixture $fixture
            $cleanup|ConvertTo-Json -Depth 15|Set-Content "$Workspace\cleanup.json"
            if(-not $cleanup.Closed -or -not $cleanup.DesktopRestored -or -not $cleanup.TaskbarCompared){throw 'Fixture cleanup result is incomplete'}
        }catch{
            if($failure){$failure.Exception.Data['CleanupFailure']=$_.Exception.Message}else{$failure=$_}
        }
    }
}
if($failure){$failure|Format-List * -Force|Out-String|Set-Content "$Workspace\error.txt";throw $failure}
@{Status='PASS';NativeMoves=3;Win1Routes=3;Cleanup=$cleanup}|ConvertTo-Json -Depth 15|Set-Content "$Workspace\results.json"
"PASS: three native placements, three standalone Win+1 routes and complete taskbar/desktop restoration. $Workspace"
