#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-env-ui-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-environment-variables-ui.ps1"
if (Test-Path $Workspace) { throw 'Use a new test workspace.' }
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
foreach($name in 'Resolve-PtEnvNativeList','Read-PtEnvNativeVariable','Read-PtEnvDraftText'){
    if(-not (Get-Command $name -ErrorAction Ignore)){throw "Import did not define $name"}
}
function Require([bool]$Value,[string]$Message) { if(-not $Value){throw $Message} }
function Reject([scriptblock]$Action,[string]$Status) {
    try { & $Action|Out-Null }
    catch { Require ($_.Exception.Data['PtEnvUiStatus'] -ceq $Status) "Expected $Status; got $($_.Exception.Message)";return }
    throw "Expected rejection $Status"
}
function Check([string]$Name,[scriptblock]$Action) {
    try { & $Action|Out-Null;$results.Add(@{Name=$Name;Status='PASS'}) }
    catch { $results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace});throw }
    finally { $results|ConvertTo-Json -Depth 6|Set-Content "$Workspace\results.json" }
}
function Node($Type,$Id,$Name,$Selector,$Children=@(),$Class='') {
    [pscustomobject]@{type=$Type;automationId=$Id;name=$Name;selector=$Selector;children=@($Children)
        className=$Class;isOffscreen=$false;isEnabled=$true;value=$Name}
}
function Row($Name,$Selector) {
    Node Custom '' '' $Selector @(
        (Node Text '' $Name "$Selector-name"),
        (Node Text '' 'value' "$Selector-value"),
        (Node Button VariableOptionsButton '' "$Selector-options")
    ) SettingsCard
}
$user=Node Group UserVariablesExpander '' user @((Row 'PT_EV_ONE' one),(Row 'TMP' other))
$user.className='SettingsCard'
$profile=Node Group '' 'PT_EV_PROFILE' profile @(
    (Node Button ProfileOptionsButton '' profile-options),(Row 'PT_EV_ONE' profile-one)
) SettingsExpander
$tree=Node Window '' '' root @($user,$profile)

Check 'Rows remain scoped to their group/profile and names ignore case only' {
    $envelope=[pscustomobject]@{depth=20;windows=@([pscustomobject]@{hwnd=7;elementCount=12;elements=@($tree)})}
    Require ((Resolve-PtEnvUiRow $envelope User pt_ev_one).selector -ceq 'one') 'CLI windows/elements envelope lost'
    Require ((Resolve-PtEnvUiRow $tree User pt_ev_one).selector -ceq 'one') 'Wrong User row'
    Require ((Resolve-PtEnvUiRow $tree ProfileVariable PT_EV_ONE -ProfileName PT_EV_PROFILE).selector -ceq 'profile-one') 'Wrong profile variable'
    Require ((Resolve-PtEnvUiRow $tree Profile PT_EV_PROFILE).selector -ceq 'profile') 'Wrong profile'
    Reject {Resolve-PtEnvUiRow $tree Profile pt_ev_profile} Missing
    $duplicate=Node Window '' '' root @($user,(Node Group UserVariablesExpander '' other-user @()))
    Reject {Resolve-PtEnvUiRow $duplicate User PT_EV_ONE} Ambiguous
    $user.children+=@(Row 'pt_ev_one' duplicate)
    Reject {Resolve-PtEnvUiRow $tree User PT_EV_ONE} Ambiguous
    $user.children=@($user.children|Where-Object selector -NE duplicate)
}
Check 'Visible menu resolution rejects distinct duplicates and excludes cached hidden peers' {
    $hidden=Node MenuItem RemoveVariableMenuItem '' hidden;$hidden.isOffscreen=$true
    $visible=Node MenuItem RemoveVariableMenuItem '' visible
    $menu=Node Menu '' '' menu @($hidden,$visible,$visible)
    Require ((Resolve-PtEnvUiMenu $menu RemoveVariableMenuItem).selector -ceq 'visible') 'Wrong menu target'
    $menu.children+=@(Node MenuItem RemoveVariableMenuItem '' second)
    Reject {Resolve-PtEnvUiMenu $menu RemoveVariableMenuItem} Ambiguous
    $menu.children=@($visible,(Node MenuItem RemoveVariableMenuItem '' visible))
    Reject {Resolve-PtEnvUiMenu $menu RemoveVariableMenuItem} Ambiguous
    $menu.children=@($hidden,$visible);$visible.isEnabled=$false
    Reject {Resolve-PtEnvUiMenu $menu RemoveVariableMenuItem} Disabled
}
Check 'Applied observations retain PATH casing, empty values, and value case sensitivity' {
    $observation=ConvertFrom-PtEnvAppliedPairs @('Path','C:\Tools;D:\Bin','PT_EV_EMPTY','') PATH
    Require ($observation.Status -ceq 'Observed' -and $observation.Value -ceq 'C:\Tools;D:\Bin') 'PATH value lost'
    Require (Compare-PtEnvUiValue $observation $true 'C:\Tools;D:\Bin').Matches 'Exact match lost'
    Require (-not (Compare-PtEnvUiValue $observation $true 'c:\tools;D:\Bin').Matches) 'Value was case folded'
    Require (Compare-PtEnvUiValue (ConvertFrom-PtEnvAppliedPairs @('PT_EV_EMPTY','') PT_EV_EMPTY) $true '').Matches 'Empty treated as absent'
    Require (Compare-PtEnvUiValue (ConvertFrom-PtEnvAppliedPairs @('Path','x') PT_EV_ABSENT) $false).Matches 'Complete absence lost'
    $safe=Compare-PtEnvUiValue $observation $true 'private-original'
    Require (-not ($safe|ConvertTo-Json).Contains('private-original') -and -not ($safe|ConvertTo-Json).Contains('C:\Tools')) 'Comparison leaked text'
    $missing=[pscustomobject]@{Status='Incomplete';Present=$null;Method='Not fully exposed'}
    Require ($null -eq (Compare-PtEnvUiValue $missing $false).Matches) 'Incomplete became a successful absence'
}
Check 'Malformed or duplicate Applied pairs never become absence' {
    Reject {ConvertFrom-PtEnvAppliedPairs @() missing} Incomplete
    Reject {ConvertFrom-PtEnvAppliedPairs @('Name') missing} Incomplete
    Reject {ConvertFrom-PtEnvAppliedPairs @('Name',$null) missing} Incomplete
    Reject {ConvertFrom-PtEnvAppliedPairs @('Path','a','PATH','b') Path} Ambiguous
}
function DraftTree($Kind,$Name) {
    $layout=Get-PtEnvDraftLayout $Kind
    $children=@()
    if($layout.Name){$children+=@(Node Edit $layout.Name $Name name)}
    if($layout.Value){$children+=@(Node Edit $layout.Value value value)}
    $children+=@((Node Button $layout.Commit '' commit),(Node Button $layout.Cancel '' cancel))
    Node Window '' $Name draft $children Popup
}
Check 'Drafts bind their own buttons and recognize actual confirmation Popup titles' {
    foreach($kind in 'AddVariable','EditVariable','Profile','ProfileVariable','Confirmation'){
        $draft=DraftTree $kind PT_EV_ONE
        $outer=Node Window '' '' root @((Node Button PrimaryButton '' unrelated),$draft)
        Require ((Resolve-PtEnvDraft $outer $kind PT_EV_ONE).Commit.selector -ceq 'commit') "Wrong commit for $kind"
    }
    Reject {Resolve-PtEnvDraft (DraftTree Confirmation other) Confirmation PT_EV_ONE} Missing
    $nested=DraftTree Profile PT_EV_PROFILE
    $nested.children+=@(DraftTree ProfileVariable PT_EV_ONE)
    Reject {Resolve-PtEnvDraft $nested Profile PT_EV_PROFILE} WrongState
    Require ((Resolve-PtEnvDraft $nested ProfileVariable PT_EV_ONE).Commit.selector -ceq 'commit') 'Inner flyout not resolved'
    $structural=DraftTree AddVariable ''
    $structural.isOffscreen=$true;$structural.selector=''
    Require ((Resolve-PtEnvDraft $structural AddVariable '').Commit.selector -ceq 'commit') 'Structural parent visibility hid an interactive draft'
}

$script:target=[pscustomobject]@{hwnd=7;processId=8;processStartTicks=9;className='SyntheticWindow'}
$script:liveTree=DraftTree EditVariable PT_EV_ONE
$script:actions=[Collections.Generic.List[string]]::new()
$script:stale=$false
function Assert-PtUiObservationTarget($Target) {
    if($script:stale){Stop-PtEnvUiOperation Stale 'Synthetic identity changed'}
}
function Read-PtEnvPrivateTree($Target) { Assert-PtUiObservationTarget $Target; $script:liveTree }
$draftReader=${function:Read-PtEnvDraftText}
function Read-PtEnvDraftText($Target,$Node) { Assert-PtUiObservationTarget $Target; $Node.value }
$privateAction=${function:Invoke-PtEnvPrivateAction}
function Invoke-PtEnvPrivateAction($Target,$Verb,$Selector,$Text) {
    Assert-PtUiObservationTarget $Target
    $script:actions.Add("$Verb/$Selector")
    if($Verb -eq 'scroll-into-view'){
        $row=Resolve-PtEnvUiRow $script:liveTree User PT_EV_ONE
        $button=@(Get-PtEnvUiDescendants $row|Where-Object automationId -EQ VariableOptionsButton)[0]
        $button.isOffscreen=$false;$button.selector='revealed-options'
    }
    if($Verb -eq 'get-value'){
        $nodes=@(Get-PtEnvUiDescendants $script:liveTree|Where-Object selector -CEQ $Selector)
        if($nodes.Count -ne 1){Stop-PtEnvUiOperation Ambiguous 'Synthetic field'}
        return $nodes[0].value
    }
}
function Read-PtEnvJournal {
    param($JournalPath)
    @{Resources=@{owned=@{Type='UserVariable';Name='PT_EV_ONE'}}}
}
Check 'Owned menu APIs reuse registered names and issue exactly one scoped action' {
    $script:liveTree=$tree;$script:actions.Clear()
    Open-PtEnvOwnedMenu -Target $script:target -JournalPath synthetic -ResourceId owned|Out-Null
    Require (($script:actions -join ',') -ceq 'invoke/one-options') 'Variable options action was repeated or unscoped'
    $button=@(Get-PtEnvUiDescendants (Resolve-PtEnvUiRow $tree User PT_EV_ONE)|Where-Object automationId -EQ VariableOptionsButton)[0]
    $button.isOffscreen=$true;$script:actions.Clear()
    Open-PtEnvOwnedMenu -Target $script:target -JournalPath synthetic -ResourceId owned|Out-Null
    Require (($script:actions -join ',') -ceq 'scroll-into-view/one-options,invoke/revealed-options') 'Offscreen action control was not revealed and re-resolved exactly once'
    $button.selector='one-options'
    $script:actions.Clear()
    Open-PtEnvOwnedMenu -Target $script:target -OwnedProfileName PT_EV_PROFILE|Out-Null
    Require (($script:actions -join ',') -ceq 'invoke/profile-options') 'Profile options action was repeated or unscoped'
    Require ((Get-PtEnvUserVariableOptionsSelector -Tree $tree -JournalPath synthetic -ResourceId owned) -ceq 'one-options') 'Existing variable API did not use the scoped adapter'
    $script:liveTree=Node Menu '' '' menu @((Node MenuItem EditVariableMenuItem '' edit-current))
    $script:actions.Clear()
    Invoke-PtEnvMenuAction -Target $script:target -AutomationId EditVariableMenuItem|Out-Null
    Require (($script:actions -join ',') -ceq 'invoke/edit-current') 'Menu action replayed'
    $script:liveTree=DraftTree EditVariable PT_EV_ONE
    $script:actions.Clear()
    Reject {Open-PtEnvOwnedMenu -Target $script:target -JournalPath synthetic -ResourceId owned} WrongState
    Require ($script:actions.Count -eq 0) 'Menu opened underneath a draft'
}
Check 'Wrong modal target, disabled commit and stale HWND cause no write' {
    $script:actions.Clear()
    Reject {Complete-PtEnvDraft $script:target EditVariable OTHER Commit} WrongTarget
    Require (@($script:actions|Where-Object {$_ -like 'invoke/*'}).Count -eq 0) 'Wrong draft committed'
    $script:liveTree.children[-2].isEnabled=$false
    Reject {Complete-PtEnvDraft $script:target EditVariable PT_EV_ONE Commit} Disabled
    Complete-PtEnvDraft $script:target EditVariable PT_EV_ONE Cancel|Out-Null
    Require ($script:actions[-1] -ceq 'invoke/cancel') 'Explicit cancel not used'
    $script:stale=$true
    Reject {Complete-PtEnvDraft $script:target EditVariable PT_EV_ONE Cancel} Stale
    $script:stale=$false
}
Initialize-PtUiAutomation
$script:truncate=$false
function Resolve-PtUiElement {
    param($Hwnd,$AutomationId,$ControlType)
    $node=@(Get-PtEnvUiDescendants $script:liveTree|Where-Object automationId -CEQ $AutomationId)[0]
    $element=[pscustomobject]@{Current=[pscustomobject]@{IsOffscreen=$node.isOffscreen;IsEnabled=$node.isEnabled};Node=$node}
    $element|Add-Member ScriptMethod GetCurrentPattern {
        param($id)
        $pattern=[pscustomobject]@{Current=[pscustomobject]@{Value=$this.Node.value};Node=$this.Node}
        $pattern|Add-Member ScriptMethod SetValue {
            param($text)
            $value=if($script:truncate){$text.Substring(0,1)}else{$text}
            $this.Node.value=$value;$this.Current.Value=$value
        }
        return $pattern
    }
    $element
}
Check 'Draft field input is read back, not assumed, and long values avoid command-line limits' {
    $script:liveTree=DraftTree EditVariable PT_EV_ONE
    $value='x'*32767
    $result=Set-PtEnvDraftField $script:target EditVariable PT_EV_ONE Value $value
    Require ($result.Actual.Length -eq 32767 -and $result.InputPreserved) 'Large field value lost'
    $script:truncate=$true
    $result=Set-PtEnvDraftField $script:target EditVariable PT_EV_ONE Name 'PT_EV_NEW'
    Require ($result.Actual -ceq 'P' -and -not $result.InputPreserved) 'Provider truncation became success'
    $script:truncate=$false
    Require (@($script:actions|Where-Object {$_ -eq 'invoke/commit'}).Count -eq 0) 'Typing implicitly committed'
}
Check 'Empty draft values use ValuePattern instead of accessible labels' {
    $mock=${function:Read-PtEnvDraftText}
    try {
        Set-Item Function:\Read-PtEnvDraftText $draftReader
        $script:liveTree=DraftTree AddVariable ''
        $script:liveTree.children[0].name='Variable name'
        $result=Read-PtEnvDraft $script:target AddVariable ''
        Require ($result.Name -ceq '') 'Accessible label replaced the empty draft value'
    } finally { Set-Item Function:\Read-PtEnvDraftText $mock }
}
Check 'Private provider failures cannot expose their payload through public errors' {
    Set-Item Function:\Invoke-PtEnvPrivateAction $privateAction
    function Invoke-PtWinApp { throw 'PRIVATE_SECRET_VALUE' }
    try { Invoke-PtEnvPrivateAction $script:target get-value field | Out-Null; throw 'Expected provider failure' }
    catch {
        Require ($_.Exception.Data['PtEnvUiStatus'] -eq 'ActionError') 'Wrong failure class'
        Require (-not ($_|Out-String).Contains('PRIVATE_SECRET_VALUE')) 'Provider payload leaked'
        Require ($null -eq $_.Exception.InnerException) 'Private provider error retained as inner exception'
    }
}
$script:nativeOpened=$false;$script:nativeCanceled=$false;$script:nativeReadFails=$false
$script:nativeCancelFails=$false;$script:nativeCancelLeavesOpen=$false;$script:nativeChildStale=$false
$script:nativeCancelCalls=0;$script:nativeCloseProbes=0;$script:nativeDelayedClose=$false
$script:creation=[pscustomobject]@{Id='owned-native';ProcessId=8;ProcessStartTicks=9}
function Assert-PtUiObservationTarget($Target) {
    if($script:stale -or ($Target.hwnd -eq 11 -and (-not $script:nativeOpened -or $script:nativeChildStale))){
        Stop-PtEnvUiOperation Stale 'Synthetic identity changed'
    }
}
function Get-PtActiveResourceSession {
    [pscustomobject]@{Windows=@([pscustomobject]@{Identity=$script:target;Ownership='Owned';Creation='owned-native'})}
}
function NativeRow($Name) {
    $node=Node ListItem '' $Name.Substring(0,[Math]::Min(96,$Name.Length)) ('native-row-'+[guid]::NewGuid().ToString('N'))
    $node|Add-Member NoteProperty FullName $Name
    $node
}
function Read-PtEnvPrivateTree($Target) {
    Assert-PtUiObservationTarget $Target
    if($Target.hwnd -eq 7){
        Node Window '' '' parent @((Node List '402' '' native-list $script:nativeRows SysListView32))
    }else{
        Node Window '' '' wrapper @($script:liveTree,(Node Button '2' '' native-cancel))
    }
}
function Get-PtNativeWindow {
    param($ProcessId,$ClassName,[switch]$Visible)
    if($script:nativeCanceled -and $script:nativeOpened){
        Require (-not $Visible) 'A hidden native child must not count as closed'
        $script:nativeCloseProbes++
        if($script:nativeDelayedClose -and $script:nativeCloseProbes -ge 2){$script:nativeOpened=$false}
    }
    [pscustomobject]@{Hwnd=7}
    if($script:nativeOpened){[pscustomobject]@{Hwnd=11}}
}
function Get-PtWindowIdentity { param($Hwnd) [pscustomobject]@{hwnd=$Hwnd;processId=8;processStartTicks=9;className='#32770'} }
function Register-PtCreatedWindow { param($Identity,$Creation) }
function Wait-PtCondition {
    param($Description,$TimeoutSeconds,$Probe)
    for($i=0;$i -lt 3;$i++){
        $result=& $Probe
        if($result){return $result}
    }
    throw [TimeoutException]::new('Synthetic readiness condition failed')
}
Set-Item Function:\Invoke-PtEnvPrivateAction $privateAction
function Invoke-PtWinApp {
    param($Arguments,[switch]$SkipRecording)
    Require $SkipRecording 'Native provider payload must remain private'
    Require ($Arguments[2] -ceq '-w') 'Native action is not HWND scoped'
    $verb=$Arguments[0];$selector=$Arguments[1]
    if($verb -eq 'invoke'){
        if($selector -eq 'native-cancel'){
            Require ($Arguments[3] -ceq '11') 'Cancel targeted a window other than the child'
            $script:nativeCancelCalls++
            if($script:nativeCancelFails){throw 'PRIVATE_CANCEL_SECRET'}
            $script:nativeCanceled=$true
            if(-not $script:nativeCancelLeavesOpen -and -not $script:nativeDelayedClose){$script:nativeOpened=$false}
        }else{$script:nativeOpened=$true}
        return
    }
    if($script:nativeReadFails){throw 'PRIVATE_READ_SECRET'}
    $nodes=@(Get-PtEnvUiDescendants $script:liveTree|Where-Object selector -CEQ $selector)
    if($nodes.Count -ne 1){Stop-PtEnvUiOperation Ambiguous 'Synthetic native field'}
    @{text=$nodes[0].value}|ConvertTo-Json -Compress
}
function Read-PtEnvPrivateName($Target,$Selector) {
    if($Target.hwnd -eq 7){
        if($script:nativeNameFails){Stop-PtEnvUiOperation Incomplete 'Full Name property unavailable'}
        ($script:nativeRows|Where-Object selector -CEQ $Selector).FullName
    }else{
        if($script:nativeReadFails){Stop-PtEnvUiOperation ReadError 'Synthetic entry field failure'}
        (Get-PtEnvUiDescendants $script:liveTree|Where-Object selector -CEQ $Selector).name
    }
}
Check 'Native 529-character names use complete text and cancel without saving even for mismatches' {
    $name='PT_EV_'+('L'*523)
    $script:nativeRows=@(NativeRow $name)
    $script:nativeRows[0].FullName=$name.Substring(0,260)
    $script:liveTree=Node Window '' '' native @((Node Edit 100 $name name),(Node Edit 101 'actual-not-expected' value))
    $script:nativeOpened=$false;$script:nativeCanceled=$false
    $read=Read-PtEnvNativeVariable $script:target $script:creation $name
    Require ($name.Length -eq 529 -and $read.Status -eq 'Observed' -and $read.Value -ceq 'actual-not-expected') 'Long native observation was truncated or fabricated'
    Require (-not (Compare-PtEnvUiValue $read $true 'expected').Matches) 'Mismatch was treated as incomplete or expected value returned'
    Require ($script:nativeCanceled) 'Read-only native child not canceled'
}
Check 'A clipped native prefix is never accepted as the complete variable identity' {
    $name='PT_EV_'+('N'*523)
    $script:nativeRows=@(NativeRow $name)
    $script:nativeRows[0].FullName=$name.Substring(0,260)
    $script:liveTree=Node Window '' '' native @((Node Edit 100 ($name+'OTHER') name),(Node Edit 101 'private-other-value' value))
    $script:nativeOpened=$false;$script:nativeCanceled=$false
    $read=Read-PtEnvNativeVariable $script:target $script:creation $name
    Require ($read.Status -ceq 'Absent' -and $null -eq $read.Value) 'Prefix match exposed an unrelated value'
    Require ($script:nativeCanceled) 'Prefix candidate not canceled after exact-name mismatch'
}
Check 'Native PATH entries preserve order, duplicates and empty trailing entries' {
    $script:nativeRows=@(NativeRow 'Path')
    $script:liveTree=Node Window '' '' native @((Node List '' '' path-list @(
        (Node ListItem '' 'C:\one' entry-one),(Node ListItem '' 'C:\one' entry-two),(Node ListItem '' '' entry-empty))))
    $script:nativeOpened=$false;$script:nativeCanceled=$false
    $read=Read-PtEnvNativeVariable $script:target $script:creation PATH
    Require ($read.Value -ceq 'C:\one;C:\one;') 'Native ordered value was normalized or lost empty entries'
    Require ($script:nativeCanceled) 'PATH child not canceled'
}
Check 'Native absence, truncation and observation errors remain distinct and preserve cleanup' {
    $script:nativeOpened=$false;$script:nativeCanceled=$false
    $script:nativeRows=@(NativeRow 'Other')
    $read=Read-PtEnvNativeVariable $script:target $script:creation MISSING
    Require ($read.Status -eq 'Absent' -and -not $script:nativeOpened) 'Native absence opened an unrelated row'
    $script:nativeNameFails=$true
    Reject {Read-PtEnvNativeVariable $script:target $script:creation MISSING} Incomplete
    $script:nativeNameFails=$false
    $script:nativeRows=@(NativeRow 'Path')
    $script:nativeReadFails=$true
    Reject {Read-PtEnvNativeVariable $script:target $script:creation PATH} ReadError
    Require ($script:nativeCanceled) 'Native child was leaked after failed read'
    $script:nativeReadFails=$false
    $wrong=[pscustomobject]@{Id='unowned';ProcessId=8;ProcessStartTicks=9}
    Reject {Read-PtEnvNativeVariable $script:target $wrong PATH} WrongTarget
}
Check 'Native Cancel waits for disappearance without replaying the action' {
    $script:nativeRows=@(NativeRow 'PT_EV_DELAYED')
    $script:liveTree=Node Window '' '' native @((Node Edit 100 PT_EV_DELAYED name),(Node Edit 101 value value))
    $script:nativeOpened=$false;$script:nativeCanceled=$false;$script:nativeDelayedClose=$true
    $script:nativeCancelCalls=0;$script:nativeCloseProbes=0
    try {
        $read=Read-PtEnvNativeVariable $script:target $script:creation PT_EV_DELAYED
        Require ($read.Status -ceq 'Observed' -and -not $script:nativeOpened) 'Read returned before the native child closed'
        Require ($script:nativeCancelCalls -eq 1 -and $script:nativeCloseProbes -eq 2) 'Cancel replayed or disappearance was not observed'
    } finally {$script:nativeDelayedClose=$false}
}
Check 'A surviving native child is a cleanup failure, not a successful read' {
    $script:nativeOpened=$false;$script:nativeCanceled=$false;$script:nativeCancelLeavesOpen=$true
    $script:nativeCancelCalls=0;$script:nativeCloseProbes=0
    try {
        Reject {Read-PtEnvNativeVariable $script:target $script:creation PT_EV_DELAYED} CleanupError
        Require ($script:nativeOpened -and $script:nativeCloseProbes -eq 3) 'Surviving child was not observed'
        Require ($script:nativeCancelCalls -eq 1) 'Failed close was retried'
    } finally {$script:nativeCancelLeavesOpen=$false;$script:nativeOpened=$false}
}
Check 'Native Cancel provider errors stay private and retain an earlier read failure' {
    $script:nativeOpened=$false;$script:nativeCanceled=$false;$script:nativeCancelFails=$true
    try {
        Reject {Read-PtEnvNativeVariable $script:target $script:creation PT_EV_DELAYED} CleanupError
        $script:nativeOpened=$false;$script:nativeReadFails=$true
        try {Read-PtEnvNativeVariable $script:target $script:creation PT_EV_DELAYED|Out-Null;throw 'Expected native failure'}
        catch {
            Require ($_.Exception.Data['PtEnvUiStatus'] -ceq 'ActionError') 'Original field-read failure was replaced'
            Require (-not [string]::IsNullOrWhiteSpace($_.Exception.Data['NativeCleanupFailure'])) 'Secondary cleanup failure was lost'
            Require (-not ($_|Out-String).Contains('PRIVATE_')) 'Private native provider payload leaked'
            Require ($null -eq $_.Exception.InnerException) 'Private provider exception retained'
        }
    } finally {$script:nativeCancelFails=$false;$script:nativeReadFails=$false;$script:nativeOpened=$false}
}
Check 'Stale native child identity prevents Cancel and ordinary actions still require live targets' {
    $reader=${function:Read-PtEnvPrivateTree}
    function Read-PtEnvPrivateTree($Target) {
        $tree=& $reader $Target
        if($Target.hwnd -eq 11 -and $script:nativeReadFails){$script:nativeChildStale=$true}
        $tree
    }
    $script:nativeOpened=$false;$script:nativeCanceled=$false;$script:nativeCancelCalls=0
    $script:nativeReadFails=$true
    try {
        Reject {Read-PtEnvNativeVariable $script:target $script:creation PT_EV_DELAYED} Stale
        Require ($script:nativeCancelCalls -eq 0) 'Cancel was sent after the child identity changed'
    } finally {$script:nativeChildStale=$false;$script:nativeReadFails=$false;$script:nativeOpened=$false}
    $script:nativeOpened=$true
    $child=Get-PtWindowIdentity 11
    Reject {Invoke-PtEnvPrivateAction $child invoke native-cancel} Stale
    Require (-not $script:nativeOpened) 'Ordinary action no longer verifies its post-action target'
}
"PASS: $($results.Count) Environment Variables UI adapter groups; synthetic providers only. $Workspace"
