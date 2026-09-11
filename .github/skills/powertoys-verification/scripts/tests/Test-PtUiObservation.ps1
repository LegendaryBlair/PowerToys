#requires -Version 7.0
param([string]$Workspace=(Join-Path $env:TEMP "pt-observation-$([Guid]::NewGuid().ToString('N'))"),[switch]$Interactive)
$ErrorActionPreference='Stop'
$helpers=Split-Path $PSScriptRoot -Parent
. "$helpers\pt-ui-observation.ps1"
Initialize-PtUiAutomation
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Status){
    try{& $Body|Out-Null}catch{
        $diagnostic=$_.Exception.Data['UiObservation']
        if(-not $diagnostic -or $diagnostic.Status -cne $Status){throw}
        Require ($diagnostic.Classification -eq 'BLK-INFRASTRUCTURE') 'Failure became a product verdict'
        return
    }
    throw "Expected structured failure: $Status"
}
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace});throw}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
function FakeElement {
    $element=[pscustomobject]@{Properties=@{};Patterns=@{};PatternReads=0}
    $element|Add-Member ScriptMethod GetCurrentPropertyValue {
        param($property,$ignoreDefault)
        if(-not $ignoreDefault){throw 'Default-value substitution is forbidden'}
        if($this.Properties.ContainsKey($property.Id)){return $this.Properties[$property.Id]}
        return [Windows.Automation.AutomationElement]::NotSupported
    }
    $element|Add-Member ScriptMethod TryGetCurrentPattern {
        param($pattern,$output)
        $this.PatternReads++
        if($this.Patterns.ContainsKey($pattern.Id)){$output.Value=$this.Patterns[$pattern.Id];return $true}
        $output.Value=$null
        return $false
    }
    $element
}
$target=[pscustomobject]@{hwnd=1;processId=1;processStartTicks=1;className='Synthetic'}
Check 'Actual empty text is distinct from the accessible name and unsupported patterns' {
    $element=FakeElement
    $element.Properties[[Windows.Automation.AutomationElement]::IsPasswordProperty.Id]=$false
    $element.Properties[[Windows.Automation.AutomationElement]::NameProperty.Id]='Search shortcuts'
    $element.Patterns[[Windows.Automation.ValuePattern]::Pattern.Id]=[pscustomobject]@{Current=[pscustomobject]@{Value=''}}
    $value=Read-PtUiObservationValue $element Text $target 100
    Require ($value.Value -is [string] -and $value.Value.Length -eq 0 -and $value.Source -eq 'ValuePattern.Value') 'Empty text was replaced by a label'
    Require ((Read-PtUiObservationValue $element Name $target 100).Value -ceq 'Search shortcuts') 'Explicit accessible name was not preserved'
    $element.Patterns.Clear()
    Reject {Read-PtUiObservationValue $element Text $target 100} Unsupported
}
Check 'Observed false/zero values remain typed; unsupported properties are not defaults' {
    $element=FakeElement
    $element.Properties[[Windows.Automation.AutomationElement]::IsEnabledProperty.Id]=$false
    $element.Patterns[[Windows.Automation.SelectionItemPattern]::Pattern.Id]=[pscustomobject]@{Current=[pscustomobject]@{IsSelected=$false}}
    $element.Patterns[[Windows.Automation.RangeValuePattern]::Pattern.Id]=[pscustomobject]@{Current=[pscustomobject]@{Value=0.0}}
    Require ((Read-PtUiObservationValue $element IsEnabled $target 100).Value -ceq $false) 'False was lost'
    Require ((Read-PtUiObservationValue $element IsSelected $target 100).Value -ceq $false) 'Unselected became unsupported'
    Require ((Read-PtUiObservationValue $element RangeValue $target 100).Value -eq 0) 'Zero was lost'
    Reject {Read-PtUiObservationValue $element HelpText $target 100} Unsupported
}
Check 'Protected values, null/coerced values and truncated text never become observations' {
    $element=FakeElement
    $element.Properties[[Windows.Automation.AutomationElement]::IsPasswordProperty.Id]=$true
    Reject {Read-PtUiObservationValue $element Text $target 100} Unsupported
    Require ($element.PatternReads -eq 0) 'Protected content was requested'
    $element.Properties[[Windows.Automation.AutomationElement]::IsPasswordProperty.Id]=$false
    $element.Patterns[[Windows.Automation.ValuePattern]::Pattern.Id]=[pscustomobject]@{Current=[pscustomobject]@{Value=$null}}
    Reject {Read-PtUiObservationValue $element Text $target 100} ReadError
    $element.Patterns[[Windows.Automation.ValuePattern]::Pattern.Id].Current.Value='12345'
    Reject {Read-PtUiObservationValue $element Text $target 4} ReadError
    $element.Properties[[Windows.Automation.AutomationElement]::IsEnabledProperty.Id]='false'
    Reject {Read-PtUiObservationValue $element IsEnabled $target 100} ReadError
}
Check 'Empty/zero geometry and unmodified whitespace remain distinct facts' {
    $element=FakeElement
    $element.Properties[[Windows.Automation.AutomationElement]::BoundingRectangleProperty.Id]=[Windows.Rect]::new(0,0,0,0)
    $zero=(Read-PtUiObservationValue $element BoundingRectangle $target 100).Value
    Require (-not $zero.IsEmpty -and $zero.Width -eq 0 -and $zero.Height -eq 0) 'Zero geometry was fabricated as missing'
    $element.Properties[[Windows.Automation.AutomationElement]::BoundingRectangleProperty.Id]=[Windows.Rect]::Empty
    Require (Read-PtUiObservationValue $element BoundingRectangle $target 100).Value.IsEmpty 'Empty geometry was coerced'
    $element.Properties[[Windows.Automation.AutomationElement]::BoundingRectangleProperty.Id]=[Windows.Rect]::new([double]::NaN,0,0,0)
    Reject {Read-PtUiObservationValue $element BoundingRectangle $target 100} ReadError
    $element.Properties[[Windows.Automation.AutomationElement]::IsPasswordProperty.Id]=$false
    $range=[pscustomobject]@{Text="line`r`n "}
    $range|Add-Member ScriptMethod GetText {param($limit) $this.Text}
    $element.Patterns[[Windows.Automation.TextPattern]::Pattern.Id]=[pscustomobject]@{DocumentRange=$range}
    $text=Read-PtUiObservationValue $element Text $target 100
    Require ($text.Value -ceq "line`r`n " -and $text.Source -eq 'TextPattern.DocumentRange') 'TextPattern data was trimmed or replaced'
}
if(-not $Interactive){"PASS: $($results.Count) offline observation groups. $Workspace";return}
. "$helpers\pt-foreground-guard.ps1"
$desktop=Get-PtDesktopSnapshot
$desktop|ConvertTo-Json -Depth 12|Set-Content "$Workspace\desktop-before.json"
$process=$null;$identity=$null;$captured=[Collections.Generic.List[object]]::new()
try{
    $start=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($argument in @('-NoProfile','-STA','-File',"$PSScriptRoot\Show-PtDesktopFixture.ps1",'-StateDirectory',$Workspace,'-Observation')){$start.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::Start($start)
    $ready=Wait-PtCondition -Description 'owned observation fixture' -TimeoutSeconds 10 -Probe {
        if(Test-Path "$Workspace\ready.json"){Get-Content "$Workspace\ready.json" -Raw|ConvertFrom-Json}
    }
    $identity=Get-PtWindowIdentity $ready.hwnd
    Check 'Public observation reads real empty text/false and preserves unsupported provider properties' {
        $before=Get-PtDesktopSnapshot
        $text=Get-PtUiObservation -Target $identity -AutomationId FixtureInput -ControlType Edit -Property Text
        $name=Get-PtUiObservation -Target $identity -AutomationId FixtureInput -ControlType Edit -Property Name
        $disabled=Get-PtUiObservation -Target $identity -AutomationId FixtureDisabled -ControlType Edit -Property IsEnabled
        $geometry=Get-PtUiObservation -Target $identity -AutomationId FixtureInput -ControlType Edit -Property BoundingRectangle
        $offscreen=Get-PtUiObservation -Target $identity -AutomationId FixtureInput -ControlType Edit -Property IsOffscreen
        $rangeElement=Resolve-PtUiElement -Hwnd $identity.hwnd -AutomationId FixtureRange -ControlType Slider
        $rangePattern=$null
        if($rangeElement.TryGetCurrentPattern([Windows.Automation.RangeValuePattern]::Pattern,[ref]$rangePattern)){
            $zero=Get-PtUiObservation -Target $identity -AutomationId FixtureRange -ControlType Slider -Property RangeValue
            Require ($zero.Value -eq 0) 'Supported numeric zero was lost'
            $captured.Add($zero)
        }else{
            Reject {Get-PtUiObservation -Target $identity -AutomationId FixtureRange -ControlType Slider -Property RangeValue} Unsupported
        }
        Require ($text.Status -eq 'Observed' -and $text.Value -ceq '' -and $name.Value -ceq 'Fixture input') 'Real empty input was replaced by its name'
        Require ($disabled.Value -ceq $false) 'False live property lost'
        Require (-not $geometry.Value.IsEmpty -and $geometry.Value.Width -gt 0 -and $geometry.Value.Units -eq 'PhysicalPixels') 'Visible input geometry was not observed'
        Require ($offscreen.Value -ceq $false) 'Visible input offscreen state was substituted'
        Initialize-PtNativeUiProperty
        $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$identity.hwnd)
        $nativeName=[PtNativeUiProperty]::Read($identity.hwnd,[int[]]$root.GetRuntimeId(),30005)
        $unsupported=[PtNativeUiProperty]::Read($identity.hwnd,[int[]]$root.GetRuntimeId(),30045)
        Require ($nativeName.Supported -and $nativeName.Value -eq $root.Current.Name -and -not $unsupported.Supported) 'Native ignore-default bridge changed property support semantics'
        foreach($observation in $text,$name,$disabled,$geometry,$offscreen){$captured.Add($observation)}
        $after=Get-PtDesktopSnapshot
        Require ((ConvertTo-Json $before -Depth 12 -Compress) -ceq (ConvertTo-Json $after -Depth 12 -Compress)) 'Read-only observation moved foreground/pointer'
    }
    Check 'Missing, ambiguous, unsupported, protected and stale targets have distinct structured errors' {
        Reject {Get-PtUiObservation -Target $identity -AutomationId Missing -ControlType Edit -Property Text} Missing
        Reject {Get-PtUiObservation -Target $identity -AutomationId FixtureCombo -ControlType ComboBox -Property Name} Ambiguous
        Reject {Get-PtUiObservation -Target $identity -AutomationId FixtureInput -ControlType Edit -Property IsSelected} Unsupported
        Reject {Get-PtUiObservation -Target $identity -AutomationId FixturePassword -ControlType Edit -Property Text} Unsupported
        $stale=ConvertFrom-PtReportJson (ConvertTo-Json $identity -Compress);$stale.processStartTicks++
        Reject {Get-PtUiObservation -Target $stale -Property Name} Stale
        $scoped=Get-PtUiObservation -Target $identity -AutomationId FixtureCombo -ControlType ComboBox -WithinAutomationId FixturePanel1 -Property Name
        Require ($scoped.Value -ceq 'Fixture choice') 'Explicit scoped resolution failed'
    }
    Check 'Observation composition records real facts; unsupported reads stay infrastructure errors' {
        $run=New-PtVerificationRun -Workspace "$Workspace\recorded" -Module 'H07 property acceptance' -Bits 'Owned synthetic UI fixture only' `
            -Scenario InfrastructureAcceptance -Inputs @(
                @{Name='SKILL.md';Role='Skill';Path="$helpers\..\SKILL.md"},
                @{Name='test.ps1';Role='Checklist';Path=$PSCommandPath},
                @{Name='observation.ps1';Role='Helper';Path="$helpers\pt-ui-observation.ps1"},
                @{Name='recorder.ps1';Role='Helper';Path="$helpers\pt-verification-report.ps1"}
            ) -Items @(@{Id='I1';Description='Typed read-only observations';Admin='NO';Clarity='CLEAR';UserVisible=$false
                Assertions=@(@{Id='text';Description='Actual empty string';Required=$true})})
        $attempt=Start-PtVerificationAttempt $run -ItemId I1 -Kind Normal -Name observation -Activate
        Get-PtUiObservation -Target $identity -AutomationId FixtureInput -ControlType Edit -Property Text|Out-Null
        Reject {Get-PtUiObservation -Target $identity -AutomationId FixtureInput -ControlType Edit -Property IsSelected} Unsupported
        Stop-PtVerificationAttempt $attempt -Reason 'Expected negative observation retained'
        $state=Get-PtReportState $run
        Require ($state.Steps.Count -eq 2 -and $state.Steps[0].Status -eq 'Completed' -and $state.Steps[1].Status -eq 'Error') 'Automatic recording lost observations/errors'
        Require ($state.Items[0].Verdict -eq 'BLOCKED' -and $state.Items[0].Category -eq 'BLK-INFRASTRUCTURE') 'Unsupported property became a product verdict'
    }
    Close-PtTrackedWindow $identity
    Check 'A genuinely closed window is stale, not a successful empty observation' {
        Reject {Get-PtUiObservation -Target $identity -Property Name} Stale
    }
}finally{
    Set-PtActiveVerificationAttempt -Attempt $null
    if($identity -and [PtDesktop]::IsWindow([IntPtr]$identity.hwnd)){Close-PtTrackedWindow $identity}
    try{
        if($process -and -not $process.HasExited -and -not $process.WaitForExit(5000)){throw 'Owned fixture did not exit'}
    }finally{
        $captured|ConvertTo-Json -Depth 12|Set-Content "$Workspace\observations.json"
        Restore-PtDesktopSnapshot $desktop|ConvertTo-Json -Depth 12|Set-Content "$Workspace\desktop-restored.json"
    }
}
"PASS: $($results.Count) observation groups. $Workspace"
