#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-qa-contract-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
if('PtChord' -as [type]){throw 'Run synthetic input checks in a fresh process.'}
Add-Type @'
using System.Collections.Generic;
public static class PtChord {
    public static HashSet<int> Held=new HashSet<int>();
    public static List<string> Events=new List<string>();
    public static int FailRelease;
    public static short GetAsyncKeyState(int key) { return Held.Contains(key) ? unchecked((short)0x8000) : (short)0; }
    public static uint Key(ushort key,bool up) {
        Events.Add((up ? "U" : "D")+key);
        if(up && FailRelease==key)return 0;
        if(up)Held.Remove(key);else Held.Add(key);
        return 1;
    }
}
'@
. "$PSScriptRoot\..\pt-quick-accent.ps1"
Initialize-PtUiAutomation
if(Test-Path -LiteralPath $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Require($value,$message){if(-not $value){throw $message}}
function Reject([scriptblock]$body,[string]$pattern){
    try{& $body|Out-Null}catch{if($_.Exception.Message -notmatch $pattern){throw};return $_}
    throw "Expected rejection: $pattern"
}
function Check($name,[scriptblock]$body){
    [PtChord]::Held.Clear();[PtChord]::Events.Clear();[PtChord]::FailRelease=0
    $script:f=@{Foreground=$true;Stale=$false;Dialog=$false;Runtime=12;Opens=0;Cancels=0;CancelFails=$false}
    try{& $body;$results.Add(@{Name=$name;Status='PASS'})}
    finally{[IO.File]::WriteAllText("$Workspace\results.json",(ConvertTo-Json $results -Depth 6))}
}
function Get-PtWindowIdentity {
    param($Hwnd)
    if($Hwnd -ne 10){throw 'Unexpected window'}
    [pscustomobject]@{hwnd=10;processId=20;processStartTicks=30L;className='Fixture'}
}
function Test-PtForeground {param($Hwnd) $f.Foreground}
function Assert-PtWindowIdentity {param($Target) if($f.Stale){throw 'Changed target identity'}}
function Wait-PtCondition {
    param($Description,$TimeoutSeconds,[scriptblock]$Probe)
    for($i=0;$i -lt 3;$i++){$value=& $Probe;if($value){return $value}}
    throw "Timed out: $Description"
}
function Resolve-PtUiElement {
    param($Hwnd,$AutomationId,$Name,$ControlType)
    if($Name -eq 'Manage sets'){$kind='Manage'}
    elseif($AutomationId -eq 'CharacterSetsSearchBox' -and $f.Dialog){$kind='Search'}
    elseif($AutomationId -eq 'CloseButton' -and $f.Dialog){$kind='Cancel'}
    else{
        $error=[InvalidOperationException]::new('Synthetic missing control')
        $error.Data['PtUiResolutionStatus']='Missing';throw $error
    }
    $pattern=[pscustomobject]@{Kind=$kind;State=$f}
    $pattern|Add-Member ScriptMethod Invoke {
        if($this.Kind -eq 'Manage'){$this.State.Opens++;$this.State.Dialog=$true}
        elseif($this.Kind -eq 'Cancel'){
            $this.State.Cancels++
            if($this.State.CancelFails){throw 'Cancel failed'}
            $this.State.Dialog=$false
        }else{throw 'Unexpected invocation'}
    }
    $element=[pscustomobject]@{Pattern=$pattern;Runtime=$f.Runtime;Current=@{IsEnabled=$true;IsOffscreen=$false}}
    $element|Add-Member ScriptMethod GetRuntimeId {@(42,$this.Runtime)}
    $element|Add-Member ScriptMethod GetCurrentPattern {param($id) $this.Pattern}
    $element
}
Check 'Trigger is tapped once while shared lifetime holds only the owner letter' {
    $result=Invoke-PtQuickAccentGesture -WindowHandle 10 -KeyCode 65 -TriggerCode 32 -DelayMs 0 -ArgumentList @('value') -Observe {
        param($identity,$value)
        Require ($identity.hwnd -eq 10 -and $value -ceq 'value') 'Callback arguments lost'
        Require ([PtChord]::Held.Contains(65) -and -not [PtChord]::Held.Contains(32)) 'Wrong held state'
        'observed'
    }
    Require ($result -ceq 'observed' -and ([PtChord]::Events -join ',') -ceq 'D65,D32,U32,U65') 'Input replay or callback output lost'
}
Check 'Hold-only observer failure releases input through the common finally' {
    Reject {Invoke-PtQuickAccentGesture -WindowHandle 10 -KeyCode 65 -DelayMs 0 -Observe {throw 'Observer failed'}} 'Observer failed'|Out-Null
    Require ([PtChord]::Held.Count -eq 0 -and ([PtChord]::Events -join ',') -ceq 'D65,U65') 'Owner key leaked or trigger fabricated'
}
Check 'Pre-held trigger and duplicate keys fail before injecting any letter' {
    [void][PtChord]::Held.Add(32)
    Reject {Invoke-PtQuickAccentGesture -WindowHandle 10 -KeyCode 65 -TriggerCode 32 -DelayMs 0 -Observe {throw 'not reached'}} 'already held'|Out-Null
    [PtChord]::Held.Clear()
    Reject {Invoke-PtQuickAccentGesture -WindowHandle 10 -KeyCode 65 -Modifiers @(65) -DelayMs 0 -Observe {}} 'distinct'|Out-Null
    Require ([PtChord]::Events.Count -eq 0) 'Invalid precondition still injected input'
}
Check 'Foreground and identity failures do not force focus or replay input' {
    $f.Foreground=$false
    Reject {Invoke-PtQuickAccentGesture -WindowHandle 10 -KeyCode 65 -DelayMs 0 -Observe {}} 'already be foreground'|Out-Null
    Require ([PtChord]::Events.Count -eq 0) 'Wrong foreground received input'
    $f.Foreground=$true;$f.Stale=$true
    Reject {Invoke-PtQuickAccentGesture -WindowHandle 10 -KeyCode 65 -TriggerCode 32 -DelayMs 0 -Observe {}} 'Changed target'|Out-Null
    Require (([PtChord]::Events -join ',') -ceq 'D65,U65') 'Stale identity received a trigger or held key leaked'
}
Check 'Release error retains the original observer error' {
    [PtChord]::FailRelease=65
    $error=Reject {Invoke-PtQuickAccentGesture -WindowHandle 10 -KeyCode 65 -DelayMs 0 -Observe {throw 'Primary observer error'}} 'Primary observer error'
    Require ($error.Exception.Data['InputCleanupFailure'] -match 'Key-up 65 failed') 'Shared release failure lost'
}
Check 'Successful draft commit does not trigger a second Cancel' {
    Invoke-PtQuickAccentCharacterDialog -WindowHandle 10 -ManageButtonName 'Manage sets' -Action {
        param($search,$target)
        Require ($search.Runtime -eq 12 -and $target.hwnd -eq 10) 'Owned dialog context lost'
        $f.Dialog=$false
    }
    Require ($f.Opens -eq 1 -and $f.Cancels -eq 0) 'Committed dialog was canceled or reopened'
}
Check 'Callback failure cancels only the same owned draft once' {
    Reject {Invoke-PtQuickAccentCharacterDialog -WindowHandle 10 -ManageButtonName 'Manage sets' -Action {throw 'Draft action failed'}} 'Draft action failed'|Out-Null
    Require ($f.Opens -eq 1 -and $f.Cancels -eq 1 -and -not $f.Dialog) 'Draft cleanup missing or replayed'
}
Check 'Pre-existing or replaced drafts cannot be adopted' {
    $f.Dialog=$true
    Reject {Invoke-PtQuickAccentCharacterDialog -WindowHandle 10 -ManageButtonName 'Manage sets' -Action {}} 'existing dialog'|Out-Null
    Require ($f.Opens -eq 0 -and $f.Cancels -eq 0) 'Borrowed draft changed'
    $f.Dialog=$false
    Reject {Invoke-PtQuickAccentCharacterDialog -WindowHandle 10 -ManageButtonName 'Manage sets' -Action {$f.Runtime=99}} 'replaced'|Out-Null
    Require ($f.Cancels -eq 0 -and $f.Dialog) 'Replacement draft closed'
}
Check 'Cleanup failure remains attached to the original draft error' {
    $f.CancelFails=$true
    $error=Reject {Invoke-PtQuickAccentCharacterDialog -WindowHandle 10 -ManageButtonName 'Manage sets' -Action {throw 'Primary draft error'}} 'Primary draft error'
    Require ($error.Exception.Data['CharacterDialogCleanupFailure'] -match 'Cancel failed') 'Draft cleanup error replaced original'
}
"PASS: $($results.Count) Quick Accent composition groups; no desktop or clipboard access. $Workspace"
