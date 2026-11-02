# Copyright (c) Microsoft Corporation
# The Microsoft Corporation licenses this file to you under the MIT license.
# See the LICENSE file in the project root for more information.

function ConvertTo-PtPowerDisplayMonitorId {
    <#.SYNOPSIS
    Map a modern WMI brightness instance to Power Display's device-path identity.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$InstanceName)
    $match = [regex]::Match($InstanceName, '\A([^\\]+)\\([^\\]+)\\([^\\]+)_[0-9]+\z')
    if (-not $match.Success) {
        throw 'Unsupported WMI instance identity; no EDID-only or first-panel fallback.'
    }
    '\\?\' + $match.Groups[1].Value + '#' + $match.Groups[2].Value + '#' + $match.Groups[3].Value
}

function Get-PtPowerDisplayWmiBrightness {
    <#.SYNOPSIS
    Read one exact active WMI panel independently of Power Display's UI/cache.
    .NOTES
    Returns private device identities. Project safe fields inside an outer recorded step;
    do not serialize the result into shared evidence. No hardware writes or verdicts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$MonitorId,
        [ValidateNotNullOrEmpty()][string]$ExpectedInstanceName
    )
    $rows = @(Get-CimInstance -Namespace 'root\WMI' -ClassName WmiMonitorBrightness -ErrorAction Stop)
    $matches = @(foreach ($row in $rows) {
        if ((ConvertTo-PtPowerDisplayMonitorId -InstanceName $row.InstanceName) -ieq $MonitorId) {
            $row
        }
    })
    if ($matches.Count -ne 1) {
        throw 'Expected exactly one WMI brightness instance for the declared monitor identity.'
    }
    $panel = $matches[0]
    if ($panel.Active -isnot [bool] -or -not $panel.Active) {
        throw 'The selected WMI brightness instance is not observably active.'
    }
    if ($PSBoundParameters.ContainsKey('ExpectedInstanceName') -and
        $panel.InstanceName -ine $ExpectedInstanceName) {
        throw 'WMI instance changed since the baseline; re-establish identity before further input.'
    }
    $value = $panel.CurrentBrightness
    if (($value -isnot [byte] -and $value -isnot [int] -and $value -isnot [uint16]) -or
        $value -lt 0 -or $value -gt 100) {
        throw 'WMI brightness is missing or outside its percentage contract; no placeholder substituted.'
    }
    [pscustomobject]@{
        MonitorId = $MonitorId
        InstanceName = [string]$panel.InstanceName
        Brightness = [int]$value
        Levels = @($panel.Level | Where-Object { $null -ne $_ })
        ObservedUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Get-PtPowerDisplayOwnedProfile {
    <#.SYNOPSIS
    Resolve an owned profile by stable numeric ID, never by name or array position.
    .NOTES
    Profiles is the current parsed profiles.json profiles array. OwnedIds must come from
    the caller's UI-creation receipts; this selector does not establish ownership itself.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Profiles,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Id,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][int[]]$OwnedIds
    )
    if ($Id -notin $OwnedIds) {
        throw 'Requested profile ID is not in this run''s owned creation receipts.'
    }
    $matches = @($Profiles | Where-Object {
        ($_.id -is [int] -or $_.id -is [long]) -and $_.id -eq $Id
    })
    if ($matches.Count -ne 1) {
        throw 'Expected exactly one persisted profile for the owned stable ID.'
    }
    $matches[0]
}
