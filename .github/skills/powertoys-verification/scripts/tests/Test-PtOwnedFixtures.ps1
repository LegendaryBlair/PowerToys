param([Parameter(Mandatory)][string]$Workspace)
$ErrorActionPreference='Stop'
. "$(Split-Path $PSScriptRoot -Parent)\pt-owned-fixtures.ps1"
. "$(Split-Path $PSScriptRoot -Parent)\pt-sendinput-chord.ps1"
if(Test-Path $Workspace){throw 'Use a new workspace.'}
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=[Collections.Generic.List[object]]::new()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function ReadNotepadState {
    @(foreach($window in @(Get-PtNotepadWindows)){
        [pscustomobject]@{Identity=Get-PtWindowIdentity $window.Hwnd;Window=Get-PtWindowSnapshot $window.Hwnd
            Tabs=@(Get-PtNotepadTabs $window.Hwnd|ForEach-Object{[pscustomobject]@{
                RuntimeId=@($_.GetRuntimeId());Name=$_.Current.Name
                Selected=$_.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
            }})}
    })|ConvertTo-Json -Depth 15 -Compress
}
$desktop=Get-PtDesktopSnapshot
$before=ReadNotepadState
$before|Set-Content "$Workspace\notepad-before.json"
$desktop|ConvertTo-Json -Depth 15|Set-Content "$Workspace\desktop-before.json"
try{
    for($cycle=1;$cycle -le 2;$cycle++){
        $fixture=$null
        try{
            $fixture=New-PtNotepadFixture -Workspace $Workspace
            Require ($fixture.Identity.hwnd -gt 0) 'Actual Notepad identity missing'
            $fixture|ConvertTo-Json -Depth 20|Set-Content "$Workspace\notepad-open-$cycle.json"
        }finally{
            if($fixture){
                $persisted=Get-Content $fixture.ReceiptPath -Raw|ConvertFrom-Json
                Remove-PtNotepadFixture $persisted|Out-Null
                Remove-PtNotepadFixture $persisted|Out-Null
            }
        }
        $after=ReadNotepadState
        $after|Set-Content "$Workspace\notepad-after-$cycle.json"
        Require ($before -ceq $after) 'Notepad baseline did not match after owned-tab cleanup'
        Require (-not (Test-Path $fixture.Path)) 'Notepad file remained'
        $results.Add(@{Name="Notepad create/JSON receipt/close/idempotence cycle $cycle";Status='PASS';SharedWindow=(-not $fixture.OwnsWindow)})
    }
    $fixture=$null
    try{
        $fixture=New-PtNotepadFixture -Workspace $Workspace
        $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fixture.Identity.hwnd)
        $condition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::Document)
        $editor=Select-PtUniqueUiElement -Elements @($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)|Where-Object{-not $_.Current.IsOffscreen}) -Description 'owned tab text editor'
        $value=$editor.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
        Assert-PtForegroundOrAbort -Hwnd $fixture.Identity.hwnd
        $editor.SetFocus()
        Send-PtChord -Hwnd $fixture.Identity.hwnd -Key 0x58|Out-Null
        Wait-PtCondition -Description 'actual modified state on the owned Notepad tab' -TimeoutSeconds 2 -Probe {
            @(Get-PtNotepadTabs $fixture.Identity.hwnd|Where-Object{
                (@($_.GetRuntimeId()) -join ',') -ceq ($fixture.TabRuntimeId -join ',') -and $_.Current.Name.EndsWith('. Modified.')
            }).Count -eq 1
        }|Out-Null
        $rejected=$false
        try{Remove-PtNotepadFixture $fixture|Out-Null}catch{
            if($_.Exception.Message -notmatch 'save prompts require explicit ownership consent'){throw}
            $rejected=$true
        }
        Require $rejected 'Unsaved fixture edits were silently discarded'
    }finally{
        if($fixture){Remove-PtNotepadFixture $fixture -DiscardFixtureEdits|Out-Null}
    }
    Require ($before -ceq (ReadNotepadState)) 'Modified fixture cleanup changed original Notepad state'
    $results.Add(@{Name='Unsaved owned tab requires explicit discard; pending-close receipt supports retry';Status='PASS'})
    $explorerBefore=@(Get-PtExplorerFixtureWindows|ForEach-Object{[pscustomobject]@{Hwnd=[long]$_.HWND;Path=$_.Document.Folder.Self.Path}}|Sort-Object Hwnd)|ConvertTo-Json -Depth 8 -Compress
    $explorerBefore|Set-Content "$Workspace\explorer-before.json"
    $fixture=$null
    try{
        $fixture=New-PtExplorerFixture -Workspace $Workspace
        $fixture|ConvertTo-Json -Depth 20|Set-Content "$Workspace\explorer-open.json"
        $untracked=Join-Path $fixture.Path 'untracked.txt'
        [IO.File]::WriteAllText($untracked,'Test-owned negative fixture; must not be recursively deleted.')
        $rejected=$false
        try{Remove-PtExplorerFixture $fixture|Out-Null}catch{
            if($_.Exception.Message -notmatch 'untracked contents'){throw}
            $rejected=$true
        }
        Require ($rejected -and (Test-Path $untracked)) 'Unknown content was not preserved'
        [IO.File]::Delete($untracked)
    }finally{
        if($fixture){Remove-PtExplorerFixture $fixture|Out-Null;Remove-PtExplorerFixture $fixture|Out-Null}
    }
    $explorerAfter=@(Get-PtExplorerFixtureWindows|ForEach-Object{[pscustomobject]@{Hwnd=[long]$_.HWND;Path=$_.Document.Folder.Self.Path}}|Sort-Object Hwnd)|ConvertTo-Json -Depth 8 -Compress
    $explorerAfter|Set-Content "$Workspace\explorer-after.json"
    Require ($explorerBefore -ceq $explorerAfter) 'User Explorer window/path set changed'
    Require (-not (Test-Path $fixture.Path)) 'Explorer folder remained'
    $results.Add(@{Name='Explorer isolated HWND/unknown-content preservation/partial cleanup retry';Status='PASS'})
}catch{
    $results.Add(@{Name='Owned fixture acceptance';Status='FAIL';Error=$_.Exception.Message;Details="$($_.Exception.Data|Out-String)"})
    throw
}finally{
    try{Restore-PtDesktopSnapshot $desktop|ConvertTo-Json -Depth 15|Set-Content "$Workspace\desktop-restored.json"}
    finally{$results|ConvertTo-Json -Depth 8|Set-Content "$Workspace\results.json"}
}
"PASS: $($results.Count) real application fixture groups. $Workspace"
