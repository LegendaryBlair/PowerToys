#requires -Version 7.2
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\..\pt-power-display.ps1"

function Require([bool]$Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}
function Reject([scriptblock]$Body, [string]$Pattern) {
    try { & $Body | Out-Null } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return
    }
    throw "Expected rejection: $Pattern"
}
function Get-CimInstance {
    [CmdletBinding()]
    param([string]$Namespace, [string]$ClassName)
    Require ($Namespace -ceq 'root\WMI' -and $ClassName -ceq 'WmiMonitorBrightness') 'Unexpected WMI query'
    if ($script:queryFailure) { throw 'Synthetic provider failure' }
    $script:panels
}

$script:queryFailure = $false
$first = 'DISPLAY\OWN0001\4&fixture&0&UID1_0'
$second = 'DISPLAY\OWN0001\4&fixture&0&UID2_12'
$id = '\\?\DISPLAY#OWN0001#4&fixture&0&UID1'
$script:panels = @(
    [pscustomobject]@{InstanceName=$second; Active=$true; CurrentBrightness=[byte]70; Level=@(0,50,70,100)}
    [pscustomobject]@{InstanceName=$first; Active=$true; CurrentBrightness=[byte]0; Level=@(0,50,100)}
)
Require ((ConvertTo-PtPowerDisplayMonitorId $first) -ceq $id) 'Wrong canonical identity'
Require ((ConvertTo-PtPowerDisplayMonitorId $second) -cne $id) 'Same-model panels were conflated'
Reject { ConvertTo-PtPowerDisplayMonitorId 'DISPLAY\OWN0001\bad' } 'Unsupported WMI instance'
$reading = Get-PtPowerDisplayWmiBrightness -MonitorId $id.ToLowerInvariant() -ExpectedInstanceName $first
Require ($reading.Brightness -eq 0 -and $reading.InstanceName -ceq $first) 'Zero or exact-target selection was lost'
$script:panels[1].CurrentBrightness = [byte]50
Require ((Get-PtPowerDisplayWmiBrightness $id).Brightness -eq 50) 'Read reused a stale observation'
Reject { Get-PtPowerDisplayWmiBrightness $id -ExpectedInstanceName $second } 'instance changed'
$script:panels[1].Active = $false
Reject { Get-PtPowerDisplayWmiBrightness $id } 'not observably active'
$script:panels[1].Active = $true
foreach ($invalid in @($null, '50', 101, -1)) {
    $script:panels[1].CurrentBrightness = $invalid
    Reject { Get-PtPowerDisplayWmiBrightness $id } 'missing or outside'
}
$script:panels[1].CurrentBrightness = [byte]50
$script:panels += $script:panels[1]
Reject { Get-PtPowerDisplayWmiBrightness $id } 'exactly one WMI'
$script:panels = @()
Reject { Get-PtPowerDisplayWmiBrightness $id } 'exactly one WMI'
$script:queryFailure = $true
Reject { Get-PtPowerDisplayWmiBrightness $id } 'Synthetic provider failure'

$profiles = @(
    [pscustomobject]@{id=7; name='duplicate'; createdDate='2026-01-02T00:00:00Z'}
    [pscustomobject]@{id=4; name='duplicate'; createdDate='2026-01-01T00:00:00Z'}
    [pscustomobject]@{id=9; name='unowned'; createdDate='2026-01-03T00:00:00Z'}
)
$before = ConvertTo-Json $profiles -Compress
Require ((Get-PtPowerDisplayOwnedProfile -Profiles $profiles -Id 4 -OwnedIds 4,7).createdDate -ceq '2026-01-01T00:00:00Z') 'Selected by name or position'
Reject { Get-PtPowerDisplayOwnedProfile -Profiles $profiles -Id 9 -OwnedIds 4,7 } 'not in this run'
Reject { Get-PtPowerDisplayOwnedProfile -Profiles $profiles -Id 5 -OwnedIds 5 } 'exactly one persisted'
Reject { Get-PtPowerDisplayOwnedProfile -Profiles @($profiles[0],$profiles[0]) -Id 7 -OwnedIds 7 } 'exactly one persisted'
Reject { Get-PtPowerDisplayOwnedProfile -Profiles @([pscustomobject]@{id='4';name='malformed'}) -Id 4 -OwnedIds 4 } 'exactly one persisted'
Require ((ConvertTo-Json $profiles -Compress) -ceq $before) 'Profile selection mutated its input'
'PASS: Power Display WMI identity/read failures and stable owned-profile selection'
