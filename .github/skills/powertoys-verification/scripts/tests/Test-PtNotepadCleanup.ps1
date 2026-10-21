#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-notepad-cleanup-offline-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
if(('PtDesktop' -as [type]) -or ('Windows.Automation.AutomationElement' -as [type])){throw 'Run these synthetic desktop/UIA boundaries in a fresh process.'}
Add-Type @'
using System;
public static class PtNotepadCleanupStub {
    public static bool WindowAlive, TabAlive, HoldWindow;
    public static int Ticks, Invocations, InvokedAt;
    public static void Reset() {
        WindowAlive=TabAlive=true; HoldWindow=false; Ticks=Invocations=0; InvokedAt=-1;
        Windows.Automation.AutomationElement.Button.Current.Name="Don't save";
        Windows.Automation.AutomationElement.Button.Current.ControlType=Windows.Automation.ControlType.Button;
    }
    public static void Advance() {
        Ticks++;
        if(InvokedAt<0)return;
        if(Ticks>=InvokedAt+2)TabAlive=false;
        if(Ticks>=InvokedAt+4 && !HoldWindow)WindowAlive=false;
    }
}
public static class PtDesktop {
    public static bool IsWindow(IntPtr hwnd) { return PtNotepadCleanupStub.WindowAlive; }
}
namespace Windows.Automation {
    public enum TreeScope { Descendants }
    public sealed class PropertyCondition { public PropertyCondition(object property,object value) {} }
    public static class ControlType {
        public static readonly object Button=new object(), Text=new object();
    }
    public sealed class ElementInfo {
        public string Name="Don't save";
        public bool IsOffscreen=false, IsEnabled=true;
        public object ControlType=Windows.Automation.ControlType.Button;
    }
    public sealed class InvokePattern {
        public static readonly object Pattern=new object();
        public void Invoke() { PtNotepadCleanupStub.Invocations++; PtNotepadCleanupStub.InvokedAt=PtNotepadCleanupStub.Ticks; }
    }
    public static class SelectionItemPattern { public static readonly object Pattern=new object(); }
    public sealed class AutomationElement {
        public static readonly object AutomationIdProperty=new object();
        public static readonly AutomationElement Button=new AutomationElement();
        public ElementInfo Current=new ElementInfo();
        public static AutomationElement FromHandle(IntPtr hwnd) { return new AutomationElement(); }
        public AutomationElement[] FindAll(TreeScope scope,PropertyCondition condition) { return new[]{Button}; }
        public InvokePattern GetCurrentPattern(object pattern) { return new InvokePattern(); }
    }
}
'@
. "$PSScriptRoot\..\pt-owned-fixtures.ps1"
function Initialize-PtOwnedFixtures {}
function Assert-PtWindowIdentity {param($Identity) if(-not [PtNotepadCleanupStub]::WindowAlive){throw 'Synthetic window is gone.'}}
function Assert-PtProcessRelease {param($ProcessId)}
function Restore-PtPointerPosition {param($Point) $script:pointerRestores++}
function Restore-PtDesktopSnapshot {param($Snapshot) $script:desktopRestores++}
function Get-PtNotepadTabs {param($Hwnd) if([PtNotepadCleanupStub]::TabAlive){$script:tab}}
function Wait-PtCondition {
    param($Description,$TimeoutSeconds,[scriptblock]$Probe)
    for($i=0;$i -lt 6;$i++){
        [PtNotepadCleanupStub]::Advance()
        $result=& $Probe
        if($result){return $result}
    }
    throw "Timed out waiting for $Description"
}
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Pattern){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
function Fixture {
    [PtNotepadCleanupStub]::Reset()
    $script:pointerRestores=0;$script:desktopRestores=0;$script:selected=$true
    $id=[guid]::NewGuid().ToString('N')
    $script:tab=[pscustomobject]@{Current=[pscustomobject]@{Name="pt-notepad-$id.txt"}}
    $script:tab|Add-Member ScriptMethod GetRuntimeId {@(1,2)}
    $script:tab|Add-Member ScriptMethod GetCurrentPattern {param($Pattern) [pscustomobject]@{Current=[pscustomobject]@{IsSelected=$script:selected}}}
    $fixture=[pscustomobject]@{Kind='Notepad';Id=$id;Workspace=$Workspace;Path=(Join-Path $Workspace "pt-notepad-$id.txt")
        ReceiptPath=(Join-Path $Workspace "fixture-$id.json");Identity=@{hwnd=1;processId=2};Baseline=@()
        Desktop=@{pointer=@{X=10;Y=20}};TabRuntimeId=@(1,2);OwnsWindow=$true;CloseRequested=$true;ContentClosed=$false;Closed=$false}
    [IO.File]::WriteAllText($fixture.Path,'Only test-owned content.')
    Save-PtOwnedFixture $fixture
    $fixture
}
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[scriptblock]$Action){
    try{& $Action|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message});throw}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
Check 'English discard executes once and awaits delayed owned-window disappearance' {
    $fixture=Fixture
    Remove-PtNotepadFixture $fixture -DiscardFixtureEdits|Out-Null
    Require ($fixture.Closed -and $fixture.DiscardRequested -and [PtNotepadCleanupStub]::Invocations -eq 1) 'Discard replayed or cleanup incomplete'
    Require (-not [PtNotepadCleanupStub]::WindowAlive -and $script:pointerRestores -eq 1 -and $script:desktopRestores -eq 1) 'Asynchronous closure or desktop restoration was skipped'
}
Check 'A localized prompt requires its explicit expected label and supports receipt retry' {
    $fixture=Fixture
    $label=-join ([char[]](0x4E0D,0x4FDD,0x5B58))
    [Windows.Automation.AutomationElement]::Button.Current.Name=$label
    Reject {Remove-PtNotepadFixture $fixture -DiscardFixtureEdits} 'save prompts require explicit ownership consent'
    Require ([PtNotepadCleanupStub]::Invocations -eq 0 -and (Test-Path $fixture.Path)) 'Unknown localized action was invoked'
    $fixture=Get-Content $fixture.ReceiptPath -Raw|ConvertFrom-Json
    Remove-PtNotepadFixture $fixture -DiscardFixtureEdits -DiscardButtonName $label|Out-Null
    Require ($fixture.Closed -and [PtNotepadCleanupStub]::Invocations -eq 1) 'Localized pending-close retry failed'
}
Check 'An expected label does not itself authorize discarding edits' {
    $fixture=Fixture
    Reject {Remove-PtNotepadFixture $fixture -DiscardButtonName "Don't save"} 'save prompts require explicit ownership consent'
    Require ([PtNotepadCleanupStub]::Invocations -eq 0) 'Discard occurred without opt-in'
}
Check 'Renamed or unselected owned-tab identity prevents discarding another document' {
    foreach($variant in 'Renamed','Unselected'){
        $fixture=Fixture
        if($variant -eq 'Renamed'){$script:tab.Current.Name='Another document'}else{$script:selected=$false}
        Reject {Remove-PtNotepadFixture $fixture -DiscardFixtureEdits} 'owned Notepad tab'
        Require ([PtNotepadCleanupStub]::Invocations -eq 0) 'Unowned or unselected document was discarded'
    }
}
Check 'Matching text on a non-button is not a discard action' {
    $fixture=Fixture
    [Windows.Automation.AutomationElement]::Button.Current.ControlType=[Windows.Automation.ControlType]::Text
    Reject {Remove-PtNotepadFixture $fixture -DiscardFixtureEdits} 'save prompts require explicit ownership consent'
    Require ([PtNotepadCleanupStub]::Invocations -eq 0) 'A non-button role was invoked'
}
Check 'A surviving owned window is preserved without replaying discard on retry' {
    $fixture=Fixture
    [PtNotepadCleanupStub]::HoldWindow=$true
    Reject {Remove-PtNotepadFixture $fixture -DiscardFixtureEdits} 'remaining tabs are preserved'
    $fixture=Get-Content $fixture.ReceiptPath -Raw|ConvertFrom-Json
    Require ($fixture.ContentClosed -and $fixture.DiscardRequested -and -not $fixture.Closed) 'Partial cleanup receipt lost the completed actions'
    Reject {Remove-PtNotepadFixture $fixture -DiscardFixtureEdits} 'remaining tabs are preserved'
    Require ([PtNotepadCleanupStub]::Invocations -eq 1 -and [PtNotepadCleanupStub]::WindowAlive) 'Discard replayed or an untracked window was forced closed'
}
"PASS: $($results.Count) synthetic Notepad cleanup groups; no desktop input or real application access. $Workspace"
