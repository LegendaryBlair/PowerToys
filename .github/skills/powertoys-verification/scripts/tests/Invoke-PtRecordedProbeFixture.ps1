param(
    [Parameter(Mandatory)][string]$EventName,
    [Parameter(Mandatory)][string]$ExpectedAttemptId
)
$catalog = @(Get-PtSharedEventCatalog)
if (@($catalog | Where-Object Name -eq 'ShortcutGuide.Trigger').Count -ne 1) {
    throw 'Inherited Named Event catalog is unavailable in the copied script.'
}
$active = Get-PtActiveVerificationAttempt
if (-not $active -or $active.Id -ne $ExpectedAttemptId) { throw 'The copied script lost its recording context.' }
if (-not (Test-PtSharedEvent -Name $EventName)) { throw 'Owned test event was not found.' }
if (-not (Invoke-PtSharedEvent -Name $EventName)) { throw 'Owned test event was not signaled.' }
$help = Invoke-PtWinApp -Arguments @('--help')
[pscustomobject]@{ AttemptId = $active.Id; CatalogCount = $catalog.Count; Help = $help }
