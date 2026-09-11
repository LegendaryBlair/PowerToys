param(
    [switch]$Interactive,
    [string]$Workspace = (Join-Path $env:TEMP "pt-ui-contracts-$([Guid]::NewGuid().ToString('N'))")
)
$ErrorActionPreference='Stop'
$helperRoot=Split-Path $PSScriptRoot -Parent
foreach($name in 'pt-desktop','pt-uia','pt-state-snapshot','pt-foreground-guard'){. "$helperRoot\$name.ps1"}
if(Test-Path $Workspace){throw 'Use a new acceptance workspace'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message});throw}
    finally{$results|ConvertTo-Json -Depth 6|Set-Content "$Workspace\results.json"}
}
function Element([int[]]$RuntimeId){
    $element=[pscustomobject]@{Id=$RuntimeId;Name='Same caption'}
    $element|Add-Member ScriptMethod GetRuntimeId {return ,$this.Id}
    $element
}
Check 'Duplicate exposure is collapsed by runtime identity, not caption' {
    $one=Element @(42,1);$duplicate=Element @(42,1);$different=Element @(42,2)
    $result=Select-PtUniqueUiElement -Elements @($one,$duplicate) -Description fixture
    Require ([object]::ReferenceEquals($one,$result)) 'Identity dedup changed its target'
    Reject {Select-PtUniqueUiElement -Elements @($one,$different) -Description fixture} '2 distinct'
    Reject {Select-PtUniqueUiElement -Elements @() -Description fixture} '0 distinct'
    Reject {Select-PtUniqueUiElement -Elements @((Element @())) -Description fixture} 'identity unavailable'
}
Check 'Explicit missing targets remain errors; scoped discovery does not invent targets' {
    Reject {Get-PtNativeWindow -Hwnd 0} 'HWND=0'
    Reject {[PtDesktop]::Read([IntPtr]::Zero)} 'no longer exists'
    Reject {Get-PtNativeWindow -ProcessId 0} 'validate|range'
    $found=@(Get-PtNativeWindow -ProcessId $PID -ClassName 'NoSuchPowerToysFixtureClass')
    Require ($found.Count -eq 0) 'Process/class filter returned an unrelated window'
    Reject {Wait-PtWindow -ProcessId $PID -ClassName 'NoSuchPowerToysFixtureClass' -TimeoutSeconds 0.15} 'Timed out'
}
if(-not $Interactive){"PASS: $($results.Count) offline UI contracts. $Workspace";return}
$baseline=Get-PtDesktopSnapshot
$baseline|ConvertTo-Json -Depth 10|Set-Content "$Workspace\baseline.json"
$process=$null;$fixture=$null
try{
    $start=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-STA','-File',"$PSScriptRoot\Show-PtDesktopFixture.ps1",'-StateDirectory',$Workspace,'-Churn')){$start.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::Start($start)
    $ready=Wait-PtCondition -Description 'owned UI fixture readiness' -Probe {
        if(Test-Path "$Workspace\ready.json"){Get-Content "$Workspace\ready.json" -Raw|ConvertFrom-Json}
    }
    $fixture=Get-PtWindowIdentity $ready.hwnd
    Check 'Different same-ID controls require explicit container scope' {
        Reject {Resolve-PtUiElement -Hwnd $ready.hwnd -AutomationId FixtureCombo -ControlType ComboBox} '2 distinct'
        $first=Resolve-PtUiElement -Hwnd $ready.hwnd -AutomationId FixtureCombo -ControlType ComboBox -WithinAutomationId FixturePanel1
        Require ($null -ne $first) 'Scoped control not found'
        try{
            [void][PtDesktop]::ShowWindow([IntPtr]$ready.hwnd,6)
            Reject {Select-PtComboBoxItem -Hwnd $ready.hwnd -ControlName 'Fixture choice' -WithinAutomationId FixturePanel1 -ItemName Beta} 'hidden or minimized'
        }finally{[void][PtDesktop]::ShowWindow([IntPtr]$ready.hwnd,9)}
    }
    Check 'Combo selection opens, chooses, reads back and repeats without touching other ComboBox' {
        $result=Select-PtComboBoxItem -Hwnd $ready.hwnd -AutomationId FixtureCombo -WithinAutomationId FixturePanel1 -ItemName Beta
        $result|ConvertTo-Json -Depth 8|Set-Content "$Workspace\combo-selected.json"
        Require ($result.Actual[0] -eq 'Beta' -and $result.Before[0] -eq 'Alpha') 'Selection readback mismatch'
        $second=Resolve-PtUiElement -Hwnd $ready.hwnd -AutomationId FixtureCombo -ControlType ComboBox -WithinAutomationId FixturePanel2
        Require (@(Get-PtComboBoxSelection $second)[0] -eq 'Alpha') 'Another same-caption ComboBox was changed'
        $same=Select-PtComboBoxItem -Hwnd $ready.hwnd -AutomationId FixtureCombo -WithinAutomationId FixturePanel1 -ItemName Beta
        Require (-not $same.Changed) 'No-op selection performed another mutation'
        Reject {Select-PtComboBoxItem -Hwnd $ready.hwnd -AutomationId FixtureCombo -WithinAutomationId FixturePanel1 -ItemName Missing -TimeoutSeconds 0.2} 'Timed out'
        $first=Resolve-PtUiElement -Hwnd $ready.hwnd -AutomationId FixtureCombo -ControlType ComboBox -WithinAutomationId FixturePanel1
        $expand=$first.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern)
        Require ($expand.Current.ExpandCollapseState -eq 'Collapsed') 'Owned popup remained open after failure'
        Select-PtComboBoxItem -Hwnd $ready.hwnd -AutomationId FixtureCombo -WithinAutomationId FixturePanel1 -ItemName Alpha|Out-Null
    }
    Check 'Native discovery filters correctly under concurrent owned window creation/destruction' {
        $windowClass=(Get-PtNativeWindow -Hwnd $ready.hwnd).ClassName
        for($i=0;$i -lt 100;$i++){
            $windows=@(Get-PtNativeWindow -ProcessId $ready.processId)
            Require (@($windows|Where-Object ProcessId -ne $ready.processId).Count -eq 0) 'Unrelated PID leaked through native filter'
        }
        Reject {Wait-PtWindow -ProcessId $ready.processId -ClassName $windowClass -Visible -TimeoutSeconds 0.2} 'Ambiguous'
    }
}finally{
    if($fixture -and [PtDesktop]::IsWindow([IntPtr]$fixture.hwnd)){Close-PtTrackedWindow $fixture}
    if($process -and -not $process.HasExited -and -not $process.WaitForExit(5000)){throw "Owned UI fixture $($process.Id) did not exit"}
    Restore-PtDesktopSnapshot $baseline|ConvertTo-Json -Depth 12|Set-Content "$Workspace\restored.json"
}
"PASS: $($results.Count) UI contract groups. $Workspace"
