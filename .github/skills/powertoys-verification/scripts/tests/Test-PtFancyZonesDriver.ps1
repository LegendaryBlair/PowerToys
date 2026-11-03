#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-fz-driver-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-fancyzones-driver.ps1"
function Require([bool]$Value,[string]$Message) { if(-not $Value) { throw $Message } }
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$module=Join-Path $Workspace 'module'
$recovery=Join-Path $Workspace 'recovery'
if((Test-Path $module) -or (Test-Path $recovery)) { throw 'Do not reuse a fixture.' }
[IO.Directory]::CreateDirectory($module)|Out-Null
[IO.Directory]::CreateDirectory($recovery)|Out-Null
$names=@('settings.json','applied-layouts.json','custom-layouts.json','default-layouts.json',
    'layout-hotkeys.json','layout-templates.json','app-zone-history.json','editor-parameters.json','last-used-virtual-desktop.json')
$script:driverTest=[pscustomobject]@{Visible=$false;Activations=0;Closes=0;Refreshes=0;Phase='Task1'}
$hostCreation=[pscustomobject]@{Id='host';State='Started';ProcessId=42;ProcessStartTicks=80L;ImagePath=(Join-Path $Workspace 'host.exe')}
function Get-PtActiveResourceSession { [pscustomobject]@{Processes=@($hostCreation)} }
function Get-PtResourceProcessIdentity { param($ProcessId) [pscustomobject]@{processStartTicks=80L;path=$hostCreation.ImagePath} }
function Get-PtActiveVerificationAttempt { [pscustomobject]@{Id='synthetic';Phase=$script:driverTest.Phase} }
function Assert-PtWindowIdentity { param($Identity) }
function Assert-PtForegroundOrAbort { param($Hwnd) }
function Register-PtCreatedProcessWindows { param($Creation) }
function Get-PtWindowIdentity { param($Hwnd) [pscustomobject]@{hwnd=$Hwnd;pid=43} }
function Get-PtFancyZonesDisplayModel {
    $rect=[pscustomobject]@{Left=0;Top=0;Right=1000;Bottom=800}
    [pscustomobject]@{CurrentDesktop=[guid]::Empty.ToString('B');Monitors=@(
        [pscustomobject]@{Handle=1;Name='OwnedDisplay';Instance='instance';Serial='';Number=1;Dpi=96;
            PhysicalBounds=$rect;PhysicalWork=$rect;LogicalBounds=$rect;LogicalWork=$rect}
    )}
}
function Get-PtFancyZonesCurrentEditorInput {
    param($Context,$Spanning)
    Require $Context.InMutation 'Host read-out escaped its mutation scope.'
    $script:driverTest.Refreshes++
    $document=New-PtFancyZonesEditorParameters -DisplayModel (Get-PtFancyZonesDisplayModel) -HostProcessId 42 -Spanning $Spanning -TargetMonitor 1
    [IO.File]::WriteAllText((Join-Path $Context.ModuleRoot 'editor-parameters.json'),($document|ConvertTo-Json -Depth 12))
    $document
}
function Write-TestAssignment($Type) {
    $parameters=New-PtFancyZonesEditorParameters -DisplayModel (Get-PtFancyZonesDisplayModel) -HostProcessId 42 -Spanning $false -TargetMonitor 1
    $doc=[pscustomobject]@{'applied-layouts'=@([pscustomobject]@{
        device=(ConvertTo-PtFancyZonesDevice $parameters.monitors[0])
        'applied-layout'=[pscustomobject]@{uuid=[guid]::Empty.ToString('B');type=$Type;'show-spacing'=$true;spacing=16;'zone-count'=3;'sensitivity-radius'=20}
    })}
    [IO.File]::WriteAllText("$module\applied-layouts.json",($doc|ConvertTo-Json -Depth 12))
}
function Invoke-PtSharedEvent {
    param($Name)
    Require ($Name -ceq 'FancyZones.ToggleEditor') 'Wrong activation route.'
    $script:driverTest.Visible=$true
    $script:driverTest.Activations++
    Write-TestAssignment 'columns'
}
function Invoke-PtOwnedProcessActivation {
    param($FilePath,$TimeoutSeconds,$Action)
    & $Action
    [pscustomobject]@{Id='editor';ProcessId=43;ProcessStartTicks=81L;ImagePath=$FilePath}
}
function Get-PtNativeWindow {
    param($ProcessId,[switch]$Visible,$ClassName)
    if($script:driverTest.Visible) { [pscustomobject]@{Hwnd=100L;Title='FancyZones Editor'} }
}
function Wait-PtCondition {
    param($Description,$TimeoutSeconds,$Probe)
    $result=& $Probe
    if(-not $result) { throw "Probe did not produce $Description" }
    $result
}
function Close-PtTrackedWindow {
    param($Window)
    $script:driverTest.Visible=$false
    $script:driverTest.Closes++
    Write-TestAssignment 'rows'
}
function Stop-PtOwnedProcess {
    param($Creation,$TimeoutSeconds,$ArgumentList,$RequestExit)
    & $RequestExit $Creation @ArgumentList
}
try {
    [IO.File]::WriteAllText("$module\settings.json",'{"properties":{"fancyzones_span_zones_across_monitors":{"value":false}}}')
    [IO.File]::WriteAllText("$module\applied-layouts.json",'{"applied-layouts":[]}')
    $baseline=Get-PtFileSetSnapshot -Path $module -FileNames $names
    $baselineText=$baseline|ConvertTo-Json -Depth 10 -Compress
    $context=New-PtFancyZonesDriverContext -ExpectedState $baseline -HostCreation $hostCreation `
        -Settings ([pscustomobject]@{hwnd=99L}) -EditorPath (Join-Path $Workspace 'editor.exe') -PrivateRecoveryDirectory $recovery
    Open-PtFancyZonesEditor $context|Out-Null
    Open-PtFancyZonesEditor $context|Out-Null
    Require ($script:driverTest.Activations -eq 1 -and $script:driverTest.Refreshes -eq 1) 'Repeated open toggled the existing editor or omitted the host acknowledgement.'
    Close-PtFancyZonesEditor $context
    Require ($script:driverTest.Closes -eq 1 -and -not $context.EditorCreation -and -not $context.InMutation) 'Normal editor close did not release the context.'
    $result=Restore-PtFileSetSnapshot -Snapshot $baseline -ExpectedState $context.ExpectedModule -OwnedFileNames $names
    Require $result.SelectedFilesMatchBaseline 'The integrated entry/close path could not restore its files.'
    Require (($baseline|ConvertTo-Json -Depth 10 -Compress) -ceq $baselineText) 'The original was replaced by a later snapshot.'
    $context.ExpectedModule=$baseline
    $context.StopFile=Join-Path $recovery 'stop.fixture'
    [IO.File]::WriteAllText($context.StopFile,'stop')
    $stopped=$false
    try {
        Invoke-PtFancyZonesDriverAction -Context $context -Scope @{} -Action {throw 'Stop marker was ignored.'}|Out-Null
    }catch{$stopped=$_.Exception.Message -match '^Stop requested'}
    Require $stopped 'The stop marker did not prevent new product input.'
    $script:driverTest.Phase='Cleanup'
    Invoke-PtFancyZonesDriverAction -Context $context -Scope @{} -Action {}|Out-Null
    $script:driverTest.Phase='Task1'
    [IO.File]::Delete($context.StopFile)
    $context.StopFile=$null
    [IO.File]::WriteAllText("$module\applied-layouts.json",'{"external":"change"}')
    $blocked=$false
    try { Open-PtFancyZonesEditor $context|Out-Null } catch {
        if($_.Exception.Message -notmatch 'Pre-action file conflict') { throw }
        $blocked=$true
    }
    Require ($blocked -and $script:driverTest.Activations -eq 1) 'Existing file conflict was bypassed before activation.'
    Require (-not $context.InMutation) 'Failed mutation retained an active scope.'
} finally {
    foreach($name in $names) { [IO.File]::Delete((Join-Path $module $name)) }
    [IO.File]::Delete((Join-Path $recovery 'driver-expected-module.json'))
    [IO.File]::Delete((Join-Path $recovery 'stop.fixture'))
    [IO.Directory]::Delete($module,$false)
    [IO.Directory]::Delete($recovery,$false)
}
@{EditorOpenClose='PASS';HostAcknowledgement='PASS';GuardedRestoration='PASS';ConflictBeforeInput='PASS';ProductStateTouched=$false}|
    ConvertTo-Json|Set-Content (Join-Path $Workspace 'results.json')
'PASS: integrated editor entry/close, persistent expected state, baseline restoration and pre-action conflict.'
