#requires -Version 7.0
<#
.SYNOPSIS
H05 schema/ownership contracts, optionally followed by serial installed Settings round trips.
.NOTES
Interactive mode needs an existing Settings HWND, changes only SG/Color Picker shortcut
controls, restores their original values and Settings navigation, and never activates modules.
#>
param([string]$Workspace=(Join-Path $env:TEMP "pt-shortcut-contracts-$([Guid]::NewGuid().ToString('N'))"),
    [switch]$Interactive,[long]$SettingsHwnd)
$ErrorActionPreference='Stop'
$helpers=Split-Path $PSScriptRoot -Parent
. "$helpers\pt-shortcut-recorder.ps1"
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message;Stack=$_.ScriptStackTrace});throw}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
function Chord([bool]$Win,[bool]$Ctrl,[bool]$Alt,[bool]$Shift,[int]$Code){
    [pscustomobject]@{win=$Win;ctrl=$Ctrl;alt=$Alt;shift=$Shift;code=$Code;key=''}
}
Check 'All six fields are explicit; absent, extra, invalid and unrestorable values fail' {
    $valid=Chord $true $false $false $true 191
    $text=ConvertTo-PtShortcutKey $valid
    Require ((ConvertFrom-PtReportJson $text).win -eq $true) 'Windows modifier was lost'
    $changed=Chord $false $true $true $false 122
    Require ((ConvertTo-PtShortcutKey $changed) -cne $text) 'Distinct modifier combinations compare equal'
    foreach($field in 'win','ctrl','alt','shift','code','key'){
        $copy=ConvertFrom-PtReportJson $text
        $copy.PSObject.Properties.Remove($field)
        Reject {Assert-PtShortcutBinding $copy} 'explicit Boolean|integer virtual-key|complete six-field'
    }
    $copy=ConvertFrom-PtReportJson $text;$copy.win='true'
    Reject {Assert-PtShortcutBinding $copy} 'explicit Boolean'
    $copy=ConvertFrom-PtReportJson $text;$copy.key='legacy-name'
    Reject {Assert-PtShortcutBinding $copy} 'legacy key'
    $copy=ConvertFrom-PtReportJson $text;$copy|Add-Member NoteProperty unknown 1
    Reject {Assert-PtShortcutBinding $copy} 'Unsupported shortcut fields'
    Reject {Assert-PtShortcutBinding (Chord $false $false $false $false 0)} 'empty shortcut'
}
Check 'Reserved system gestures, modifier-only and unmodified chords are rejected before input' {
    foreach($bad in @((Chord $true $false $false $false 76),(Chord $true $false $false $false 9),
        (Chord $false $true $true $false 46),(Chord $false $false $false $true 9))){
        Reject {Assert-PtShortcutBinding $bad} 'Reserved system/navigation'
    }
    Reject {Assert-PtShortcutBinding (Chord $false $false $false $false 65)} 'include a modifier'
    Reject {Assert-PtShortcutBinding (Chord $true $false $false $false 17)} 'Unsupported main key'
}
Check 'JSON segment paths preserve literal dots and do not rewrite the settings file' {
    $path=Join-Path $Workspace 'schema.json'
    $binding=Chord $true $false $true $false 79
    [IO.File]::WriteAllText($path,(ConvertTo-Json @{properties=@{'entry.with.dot'=$binding}} -Depth 8))
    $before=(Get-FileHash $path).Hash
    $actual=Get-PtShortcutBinding $path @('properties','entry.with.dot')
    Require ((ConvertTo-PtShortcutKey $actual) -ceq (ConvertTo-PtShortcutKey $binding)) 'JSON property addressing changed fields'
    Reject {Get-PtShortcutBinding $path @('properties','missing')} 'Missing shortcut property'
    Require ((Get-FileHash $path).Hash -ceq $before) 'Read-only binding helper wrote settings'
}
Check 'Persisted receipts protect original values, target addressing and concurrent writes' {
    function Get-PtWindowIdentity {param($Hwnd) [pscustomobject]@{hwnd=$Hwnd;processId=1;processStartTicks=1;className='Synthetic'}}
    function Get-PtShortcutEditor {param($Snapshot) [pscustomobject]@{Current=[pscustomobject]@{HelpText='Win + Shift + F11'}}}
    function Get-PtShortcutKeyName {param($Code,$Hwnd) 'F11'}
    $path=Join-Path $Workspace 'snapshot-settings.json'
    [IO.File]::WriteAllText($path,(ConvertTo-Json @{properties=@{shortcut=(Chord $true $false $false $true 122)}} -Depth 8))
    $snapshot=Get-PtShortcutSnapshot -Hwnd 1 -PageAutomationId fixture -SettingsPath $path -PropertyPath properties,shortcut -Workspace $Workspace
    $loaded=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($snapshot.ReceiptPath))
    Assert-PtShortcutSnapshot $loaded
    $loaded.Original.win=$false
    Reject {Assert-PtShortcutSnapshot $loaded} 'baseline/target differs'
    $loaded=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($snapshot.ReceiptPath))
    $loaded.ReceiptPath=Join-Path $Workspace 'unowned.json'
    Reject {Assert-PtShortcutSnapshot $loaded} 'Invalid shortcut ownership'
    $foreign=Chord $false $true $false $true 123
    [IO.File]::WriteAllText($path,(ConvertTo-Json @{properties=@{shortcut=$foreign}} -Depth 8))
    Reject {Set-PtShortcutBinding $snapshot (Chord $true $true $false $false 121)} 'outside this transaction'
    Reject {Restore-PtShortcutSnapshot $snapshot} 'outside this transaction'
    Require ((ConvertTo-PtShortcutKey (Get-PtShortcutBinding $path @('properties','shortcut'))) -ceq (ConvertTo-PtShortcutKey $foreign)) 'Concurrent state was overwritten'
}
Check 'Recorded commands use the real public signature and retain escaped snapshot/binding values' {
    function Get-PtActiveVerificationAttempt {[pscustomobject]@{Id='synthetic'}}
    function Invoke-PtVerificationStep {
        param($Attempt,$Name,$Command,$Implementation,$Action,$ArgumentList)
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseInput($Command,[ref]$tokens,[ref]$errors)
        if($errors){throw 'Recorded shortcut command is not valid PowerShell'}
        $call=$ast.Find({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Set-PtShortcutBinding'},$true)
        if(-not $call){throw 'Recorded shortcut command is missing'}
        $parameters=@($call.CommandElements|Where-Object {$_ -is [Management.Automation.Language.CommandParameterAst]}|ForEach-Object ParameterName)
        if(@($parameters|Where-Object {$_ -notin (Get-Command Set-PtShortcutBinding).Parameters.Keys}).Count){throw 'Recorded command invented unsupported parameters'}
        [pscustomobject]@{Command=$Command;Arguments=$ArgumentList}
    }
    $receipt=Get-ChildItem $Workspace -Filter 'shortcut-*.json'|Select-Object -First 1
    $snapshot=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($receipt.FullName))
    $result=Set-PtShortcutBinding $snapshot (Chord $true $true $false $false 121)
    Require ($result.Command.Contains('-Snapshot (ConvertFrom-PtReportJson') -and $result.Arguments[1].code -eq 121) 'Snapshot/binding were not retained'
}
Check 'Failed receipt replacement leaves the original recovery record intact' {
    $file=Get-ChildItem $Workspace -Filter 'shortcut-*.json'|Select-Object -First 1
    $snapshot=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($file.FullName))
    $bytes=[IO.File]::ReadAllBytes($file.FullName)
    $attributes=[IO.File]::GetAttributes($file.FullName)
    $snapshot.ExpectedCurrent=Chord $false $true $false $true 123
    try{
        [IO.File]::SetAttributes($file.FullName,($attributes -bor [IO.FileAttributes]::ReadOnly))
        Reject {Save-PtShortcutSnapshot $snapshot} 'denied|read.only|access'
        Require ([Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName)) -ceq [Convert]::ToBase64String($bytes)) 'Failed update destroyed the original receipt'
    }finally{[IO.File]::SetAttributes($file.FullName,$attributes)}
    Save-PtShortcutSnapshot $snapshot
    $saved=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($file.FullName))
    Require ($saved.ExpectedCurrent.code -eq 123 -and (ConvertTo-PtShortcutKey $saved.Original) -ceq (ConvertTo-PtShortcutKey $snapshot.Original)) 'Atomic receipt update lost original or expected state'
    Require (@(Get-ChildItem $Workspace -Filter 'shortcut-write-*.tmp').Count -eq 0) 'Receipt temporary file remained'
}
if(-not $Interactive){"PASS: $($results.Count) offline shortcut groups. $Workspace";return}
if(-not $SettingsHwnd){throw 'Interactive mode requires an explicit existing SettingsHwnd.'}
Initialize-PtUiAutomation
$desktop=Get-PtDesktopSnapshot -WindowHwnd $SettingsHwnd
$desktop|ConvertTo-Json -Depth 15|Set-Content "$Workspace\desktop-before.json"
$identity=Get-PtWindowIdentity $SettingsHwnd
$root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$SettingsHwnd)
$condition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::ListItem)
$selected=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)|Where-Object{
    $_.Current.AutomationId.EndsWith('NavItem') -and $_.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
})
$page=Select-PtUniqueUiElement -Elements $selected -Description 'original Settings navigation selection'
$originalPage=$page.Current.AutomationId
$generalPath=Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\settings.json'
$generalBefore=Get-PtFileSnapshot $generalPath
$generalBefore|ConvertTo-Json -Depth 8|Set-Content "$Workspace\general-before.json"
$targets=@(
    @{Name='ShortcutGuide';Page='ShortcutGuideNavItem';Relative='Shortcut Guide\settings.json';Property='open_shortcutguide';ToggleName='Shortcut Guide';EnabledKey='Shortcut Guide'}
    @{Name='ColorPicker';Page='ColorPickerNavItem';Relative='ColorPicker\settings.json';Property='ActivationShortcut';ToggleName='Color Picker';EnabledKey='ColorPicker'}
)
$inputs=@(
    @{Name='SKILL.md';Role='Skill';Path="$helpers\..\SKILL.md"}
    @{Name='Test-PtShortcutRecorder.ps1';Role='Checklist';Path=$PSCommandPath}
    foreach($name in 'pt-shortcut-recorder','pt-uia','pt-desktop','pt-state-snapshot','pt-foreground-guard','pt-sendinput-chord','pt-verification-report','pt-verification-operation','pt-verification-render'){
        @{Name="$name.ps1";Role='Helper';Path="$helpers\$name.ps1"}
    }
)
$recordedRun=New-PtVerificationRun -Workspace "$Workspace\recorded" -Module 'H05 common shortcut recorder acceptance' `
    -Bits "Installed Settings $((Get-Process -Id $identity.processId).FileVersion), immutable; helper acceptance only, no module activation" `
    -Scenario InfrastructureAcceptance -Inputs $inputs -Items @(foreach($target in $targets){
        @{Id=$target.Name;Description="Common recorder assigns and restores the $($target.Name) shortcut";Admin='NO';Clarity='CLEAR';UserVisible=$true
            Assertions=@(@{Id='roundtrip';Description='Captured UI, exact persisted fields and original restoration agree'})}
    })
Invoke-PtVerificationCase -Run $recordedRun -Context Preflight -Name 'Owned scope and original snapshots' `
    -Command 'Inspect retained desktop/Settings baselines before positive recorded round trips' -ArgumentList @($SettingsHwnd) -Action {
        param($attempt,$window) Get-PtWindowIdentity $window
    }|Out-Null
try{
    foreach($target in $targets){
        Check "$($target.Name): save, cancel, observer failure and original field/document restoration" {
            Invoke-PtWinApp -Arguments @('invoke',$target.Page,'-w',"$SettingsHwnd")|Out-Null
            $settings=Join-Path "$env:LOCALAPPDATA\Microsoft\PowerToys" $target.Relative
            $baseline=Get-PtFileSnapshot $settings
            $baseline|ConvertTo-Json -Depth 8|Set-Content "$Workspace\$($target.Name)-file-before.json"
            $toggle=Resolve-PtUiElement -Hwnd $SettingsHwnd -Name $target.ToggleName -ControlType Button
            $pattern=$toggle.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
            $wasEnabled=$pattern.Current.ToggleState -eq [Windows.Automation.ToggleState]::On
            $fixtureTouched=$false
            try{
            if(-not $wasEnabled){
                Reject {
                    Get-PtShortcutSnapshot -Hwnd $SettingsHwnd -PageAutomationId $target.Page `
                        -SettingsPath $settings -PropertyPath properties,$target.Property -Workspace $Workspace
                } 'disabled or offscreen'
                $fixtureTouched=$true
                $pattern.Toggle()
                Wait-PtCondition -Description 'explicit module fixture enablement' -TimeoutSeconds 5 -Probe {
                    $document=Get-Content $generalPath -Raw|ConvertFrom-Json
                    $button=Resolve-PtUiElement -Hwnd $SettingsHwnd -AutomationId EditButton -ControlType Button
                    $document.enabled.($target.EnabledKey) -eq $true -and $button.Current.IsEnabled
                }|Out-Null
            }
            $binding=Get-PtShortcutBinding $settings @('properties',$target.Property)
            Wait-PtCondition -Description 'selected page and shortcut editor contents' -TimeoutSeconds 5 -Probe {
                $c=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'EditButton')
                $buttons=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,$c))
                $buttons.Count -eq 1 -and $buttons[0].Current.HelpText -ieq (Get-PtShortcutDisplay $binding $SettingsHwnd)
            }|Out-Null
            $snapshot=Get-PtShortcutSnapshot -Hwnd $SettingsHwnd -PageAutomationId $target.Page `
                -SettingsPath $settings -PropertyPath properties,$target.Property -Workspace $Workspace
            $roundtrips=[Collections.Generic.List[object]]::new()
            try{
                $externalDialog=$null
                try{
                    $button=Get-PtShortcutEditor $snapshot
                    $button.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
                    $externalDialog=Wait-PtCondition -Description 'test-owned dialog outside the edit helper' -TimeoutSeconds 3 -Probe {
                        Find-PtShortcutDialog $snapshot $button.Current.Name
                    }
                    Reject {Set-PtShortcutBinding $snapshot $snapshot.Original} 'dialog already exists|disabled or offscreen'
                    Require (-not $externalDialog.Current.IsOffscreen) 'Helper dismissed a dialog it did not own'
                }finally{if($externalDialog){Close-PtShortcutDialog $snapshot $externalDialog}}
                $cancel=Set-PtShortcutBinding $snapshot (Chord $false $true $false $true 123) -Mode Cancel
                Require (-not $cancel.Changed -and (ConvertTo-PtShortcutKey $cancel.Actual) -ceq (ConvertTo-PtShortcutKey $snapshot.Original)) 'Cancel persisted a shortcut'
                Reject {
                    Set-PtShortcutBinding $snapshot (Chord $false $true $false $true 123) -CapturedObserver {
                        param($capture) throw 'Deliberate read-only observer failure before commit'
                    }
                } 'Deliberate read-only observer failure'
                Require ((ConvertTo-PtShortcutKey (Get-PtShortcutBinding $settings @('properties',$target.Property))) -ceq (ConvertTo-PtShortcutKey $snapshot.Original)) 'Observer exception changed persistence'
                foreach($desired in @((Chord $false $true $true $true 122),(Chord $true $true $false $false 121))){
                    $result=Set-PtShortcutBinding $snapshot $desired -CapturedObserver {
                        param($facts) $facts.Requested.win=-not $facts.Requested.win
                    }
                    Require ($result.Changed -and (ConvertTo-PtShortcutKey $result.Actual) -ceq (ConvertTo-PtShortcutKey $desired)) 'Saved fields differ from the requested chord'
                    $roundtrips.Add($result)
                }
                $same=Set-PtShortcutBinding $snapshot (Chord $true $true $false $false 121)
                Require (-not $same.Changed) 'Matching binding was rewritten'
            }finally{
                $persisted=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($snapshot.ReceiptPath))
                Restore-PtShortcutSnapshot $persisted|ConvertTo-Json -Depth 12|Set-Content "$Workspace\$($target.Name)-restored.json"
            }
            $roundtrips|ConvertTo-Json -Depth 12|Set-Content "$Workspace\$($target.Name)-roundtrips.json"
            $recordSnapshot=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($snapshot.ReceiptPath))
            $recordFacts=@{Evidence=[Collections.Generic.List[object]]::new()}
            $recordedCase=Invoke-PtVerificationCase -Run $recordedRun -ItemId $target.Name -Name 'Recorded generic Save and original restore' `
                -Stage Drive -Command 'Set-PtShortcutBinding through the shared recorder; restore the captured original in cleanup' `
                -ArgumentList @($recordSnapshot,(Chord $true $true $false $true 123),$recordFacts) -Action {
                    param($attempt,$capturedSnapshot,$wanted,$facts)
                    $assigned=Set-PtShortcutBinding $capturedSnapshot $wanted -ObserverArgumentList @($facts) -CapturedObserver {
                        param($capture,$sharedFacts)
                        $active=Get-PtActiveVerificationAttempt
                        $image=New-PtVerificationArtifactPath $active captured-shortcut.png
                        Save-PtPassiveScreenshot -Path $image|Out-Null
                        $sharedFacts.Evidence.Add((Add-PtVerificationArtifact $active $image Screenshot 'Actual recorder before commit; Windows artwork is not exposed by UIA'))
                        Add-PtVerificationArtifact $active "$image.state.json" Evidence 'Passive screenshot foreground/state comparison'|Out-Null
                    }
                    $path=New-PtVerificationArtifactPath $attempt assigned.json
                    $assigned|ConvertTo-Json -Depth 12|Set-Content $path
                    $facts.Evidence.Add((Add-PtVerificationArtifact $attempt $path Evidence 'Requested, captured and persisted shortcut fields'))
                } -CleanupArgumentList @($recordSnapshot,$recordFacts) -Cleanup {
                    param($capturedSnapshot,$facts)
                    $restored=Restore-PtShortcutSnapshot $capturedSnapshot
                    $active=Get-PtActiveVerificationAttempt
                    $path=New-PtVerificationArtifactPath $active restored.json
                    $restored|ConvertTo-Json -Depth 12|Set-Content $path
                    $facts.Evidence.Add((Add-PtVerificationArtifact $active $path Evidence 'Original shortcut fields and UI HelpText restored'))
                }
            Add-PtVerificationAssertion $recordedCase.Attempt roundtrip PASS 'Installed common WinUI recorder and exact persisted field comparison' `
                'Assigned the requested six-field chord, observed the recorder, and restored the captured original through UI.' -Evidence $recordFacts.Evidence.ToArray()
            Complete-PtVerificationItem $recordedRun $target.Name -Reason 'Normal recorded assignment and restoration completed'
            $after=Get-PtFileSnapshot $settings
            $after|ConvertTo-Json -Depth 8|Set-Content "$Workspace\$($target.Name)-file-after.json"
            $beforeJson=ConvertFrom-PtReportJson ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($baseline.base64)))
            $afterJson=ConvertFrom-PtReportJson ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($after.base64)))
            Require ((ConvertTo-Json $beforeJson -Depth 50 -Compress) -ceq (ConvertTo-Json $afterJson -Depth 50 -Compress)) 'Module setting values differ after UI restoration'
            @{AllSettingValuesRestored=$true;ByteExact=($baseline.base64 -ceq $after.base64)
                ByteRollback='Caller owns original file bytes; UI serialization can change whitespace.'}|ConvertTo-Json|Set-Content "$Workspace\$($target.Name)-file-comparison.json"
            foreach($key in 0x5B,0x5C,0x11,0x10,0x12,121,122,123){
                Require (([PtChord]::GetAsyncKeyState($key) -band 0x8000) -eq 0) "Injected key $key is still down"
            }
            }finally{
                if($fixtureTouched){
                    if($pattern.Current.ToggleState -eq [Windows.Automation.ToggleState]::On){$pattern.Toggle()}
                    Wait-PtCondition -Description 'original disabled module fixture state' -TimeoutSeconds 5 -Probe {
                        (Get-Content $generalPath -Raw|ConvertFrom-Json).enabled.($target.EnabledKey) -eq $false
                    }|Out-Null
                }
                @{OriginallyEnabled=$wasEnabled;TemporaryEnablement=$fixtureTouched
                    FinalEnabled=(Get-Content $generalPath -Raw|ConvertFrom-Json).enabled.($target.EnabledKey)}|
                    ConvertTo-Json|Set-Content "$Workspace\$($target.Name)-enabled-restoration.json"
            }
        }
    }
    $generalAfter=Get-PtFileSnapshot $generalPath
    $generalAfter|ConvertTo-Json -Depth 8|Set-Content "$Workspace\general-after.json"
    $beforeValue=ConvertFrom-PtReportJson ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($generalBefore.base64)))
    $afterValue=ConvertFrom-PtReportJson ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($generalAfter.base64)))
    Require ((ConvertTo-Json $beforeValue -Depth 50 -Compress) -ceq (ConvertTo-Json $afterValue -Depth 50 -Compress)) 'General settings values changed during fixture enablement'
    Check 'Composed H09/H10 invocation retains successful recorder, observer and restoration steps' {
        $state=Get-PtReportState $recordedRun
        Require (@($state.Items|Where-Object Verdict -ne PASS).Count -eq 0) 'Recorded round-trip coverage is incomplete'
        Require (@($state.Steps|Where-Object Status -ne Completed).Count -eq 0) 'Recorded helper invocation contains an error'
        Require (@($state.Steps|Where-Object Name -eq 'Edit scoped shortcut binding').Count -eq 4) 'Assignment/restoration helper calls did not inherit recording context'
        Require (@($state.Operations).Count -eq 2) 'Shared operation boundaries were not recorded'
    }
}finally{
    try{
        Assert-PtWindowIdentity $identity
        Invoke-PtWinApp -Arguments @('invoke',$originalPage,'-w',"$SettingsHwnd")|Out-Null
    }finally{
        Restore-PtDesktopSnapshot $desktop|ConvertTo-Json -Depth 15|Set-Content "$Workspace\desktop-restored.json"
    }
}
"PASS: $($results.Count) shortcut groups including both installed Settings controls. $Workspace"
"Recorded run awaits the caller's final exact-byte/owned-window cleanup: $Workspace\recorded"
