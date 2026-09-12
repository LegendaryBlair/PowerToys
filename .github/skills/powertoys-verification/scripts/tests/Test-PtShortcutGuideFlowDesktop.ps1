#requires -Version 7.2
param([Parameter(Mandatory)][string]$Workspace,[ValidateRange(1,5)][int]$Cycles=3,
    [ValidateSet('Indicators','FullGuide')][string]$HoldMode='Indicators',
    [ValidateSet('CloseButton','Escape','Chord','OutsidePane')][string]$CloseRoute,[switch]$SkipHolds)
$ErrorActionPreference='Stop'
$helpers=Split-Path $PSScriptRoot -Parent
. "$helpers\pt-shortcut-guide-flow.ps1"
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$desktop=Get-PtDesktopSnapshot
$taskbar=Get-PtShortcutGuideTaskbarSnapshot
$desktop|ConvertTo-Json -Depth 12|Set-Content "$Workspace\desktop-before.json"
$taskbar|ConvertTo-Json -Depth 15|Set-Content "$Workspace\taskbar-before.json"
$process=$null;$target=$null;$failure=$null
$results=[Collections.Generic.List[object]]::new()
try{
    $start=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($argument in @('-NoProfile','-STA','-File',"$PSScriptRoot\Show-PtDesktopFixture.ps1",'-StateDirectory',$Workspace)){$start.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::Start($start)
    $ready=Wait-PtCondition -Description 'owned SG foreground fixture' -TimeoutSeconds 10 -Probe {
        if(Test-Path "$Workspace\ready.json"){Get-Content "$Workspace\ready.json" -Raw|ConvertFrom-Json}
    }
    $target=Get-PtWindowIdentity $ready.hwnd
    $routeCases=@(@{Entry='NamedEvent';Close='CloseButton'},@{Entry='Chord';Close='Escape'},@{Entry='NamedEvent';Close='Chord'},@{Entry='Chord';Close='OutsidePane'})
    if($CloseRoute){$routeCases=@($routeCases|Where-Object Close -eq $CloseRoute)}
    foreach($route in $routeCases){
        for($index=1;$index -le $Cycles;$index++){
            $image=Join-Path $Workspace "$($route.Entry)-$($route.Close)-$index.png"
            $cycle=Invoke-PtShortcutGuideCycle -ForegroundTarget $target -Workspace $Workspace -Entry $route.Entry -CloseRoute $route.Close `
                -ArgumentList @($image) -Action {
                    param($session,$imagePath)
                    Save-PtPassiveScreenshot -Path $imagePath|Out-Null
                    $state=Get-PtShortcutGuidePresentation $session.GuideTarget
                    if($state.Kind -ne 'FullGuide'){throw 'Full guide did not survive passive observation'}
                    $state
                }
            if($cycle.Output.Count -ne 1 -or $cycle.Output[0].Kind -ne 'FullGuide'){throw 'Cycle Output did not retain the full-guide observation'}
            $results.Add(@{Name="$($route.Entry) / $($route.Close) / $index";Status='PASS';Receipt=$cycle.Session.ReceiptPath;Image=$image;Input=$cycle.Close.Input})
            $results|ConvertTo-Json -Depth 12|Set-Content "$Workspace\results.json"
        }
    }
    foreach($key in $(if(-not $SkipHolds){@(91,92)})){
        $image=Join-Path $Workspace "hold-$HoldMode-$key.png"
        $hold=Invoke-PtShortcutGuideHold -ForegroundTarget $target -Workspace $Workspace -Mode $HoldMode -WindowsKey $key `
            -ArgumentList @($image,$key,$HoldMode) -Action {
                param($session,$imagePath,$virtualKey,$expectedMode)
                Save-PtPassiveScreenshot -Path $imagePath|Out-Null
                $state=Get-PtShortcutGuidePresentation $session.GuideTarget
                if($state.Kind -ne $expectedMode){throw 'Requested held presentation was not observed'}
                [pscustomobject]@{Presentation=$state;WindowsKeyDown=(([PtChord]::GetAsyncKeyState($virtualKey) -band 0x8000) -ne 0)}
            }
        $expectedAfter=if($HoldMode -eq 'Indicators' -or $hold.Session.Configuration.CloseOnRelease){'Hidden'}else{'FullGuide'}
        if($hold.AfterRelease.Kind -ne $expectedAfter){throw 'Observed release behavior differs from configured mode'}
        $results.Add(@{Name="Held $HoldMode VK $key";Status='PASS';Receipt=$hold.Session.ReceiptPath;Image=$image;Observation=$hold.Output;AfterRelease=$hold.AfterRelease.Kind})
    }
}catch{$failure=$_;$results.Add(@{Name='Flow acceptance failure';Status='FAIL';Error=$_.Exception.Message;Details=@($_.Exception.Data.Keys|ForEach-Object {$_})})}
finally{
    $errors=[Collections.Generic.List[string]]::new()
    if($target -and [PtDesktop]::IsWindow([IntPtr]$target.hwnd)){
        try{Close-PtTrackedWindow $target}catch{$errors.Add($_.Exception.Message)}
    }
    if($process -and -not $process.HasExited -and -not $process.WaitForExit(5000)){$errors.Add('Owned foreground fixture did not exit')}
    try{Restore-PtDesktopSnapshot $desktop|ConvertTo-Json -Depth 12|Set-Content "$Workspace\desktop-restored.json"}catch{$errors.Add($_.Exception.Message)}
    try{Assert-PtShortcutGuideTaskbarRestored $taskbar|ConvertTo-Json -Depth 15|Set-Content "$Workspace\taskbar-restored.json"}catch{$errors.Add($_.Exception.Message)}
    $results|ConvertTo-Json -Depth 15|Set-Content "$Workspace\results.json"
    if($errors.Count){
        if($failure){$failure.Exception.Data['FixtureCleanupErrors']=$errors.ToArray()}
        else{throw ($errors -join '; ')}
    }
}
if($failure){throw $failure}
"PASS: $($results.Count) real SG flow cycles. $Workspace"
