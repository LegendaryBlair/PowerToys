#requires -Version 7.2
<#
.SYNOPSIS
Offline regression checks for retired CmdPal flows; no product, process or UI access.
#>
$ErrorActionPreference = 'Stop'
$script:calls = [Collections.Generic.List[string]]::new()
function Get-Process { $script:calls.Add('Get-Process'); throw 'Unexpected process access' }
function Stop-Process { $script:calls.Add('Stop-Process'); throw 'Unexpected process termination' }
function Start-Process { $script:calls.Add('Start-Process'); throw 'Unexpected process launch' }
function Wait-Process { $script:calls.Add('Wait-Process'); throw 'Unexpected process wait' }
function Start-Sleep { $script:calls.Add('Start-Sleep'); throw 'Unexpected retry delay' }
function Invoke-PtSharedEvent { $script:calls.Add('Invoke-PtSharedEvent'); throw 'Unexpected activation' }
function winapp { $script:calls.Add('winapp'); throw 'Unexpected UI access' }

. "$PSScriptRoot\..\pt-cmdpal-recycle.ps1"
if ($calls.Count) { throw 'Import accessed the product.' }
$cases = @(
    @{Name='Reset-CmdPalAppX'; Arguments=@{}},
    @{Name='Reset-CmdPalToHome'; Arguments=@{}},
    @{Name='Test-CmdPalDegraded'; Arguments=@{}},
    @{Name='Invoke-CmdPalQuery'; Arguments=@{Query='notepad';WaitMs=0}},
    @{Name='Invoke-CmdPalQuery'; Arguments=@{}}
)
foreach ($case in $cases) {
    $arguments = $case.Arguments
    try {
        & $case.Name @arguments | Out-Null
        throw "Retired entry returned successfully: $($case.Name)"
    } catch {
        if ($_.Exception -isnot [NotSupportedException] -or $_.Exception.Message -notmatch 'retired:') { throw }
    }
    if ($calls.Count) { throw "Retired entry accessed the product: $($case.Name)" }
}
"PASS: $($cases.Count) retired CmdPal call shapes reject before process, UI, navigation or retry effects."
