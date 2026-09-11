<#
.SYNOPSIS
Defines an offline, dependency-free compact verification report renderer.
.DESCRIPTION
Importing this file only defines functions. Rendering reads the supplied state, never the
machine or artifacts, and returns one Markdown string without writing files or changing gates.
.EXAMPLE
ConvertTo-PtVerificationSummary -State $state -DetailsName details.md -ResultsName results.json -ManifestName artifact-manifest.json
#>
function ConvertTo-PtVerificationSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateNotNull()]$State,
        [Parameter(Mandatory)][string]$DetailsName,
        [Parameter(Mandatory)][string]$ResultsName,
        [Parameter(Mandatory)][string]$ManifestName
    )

    function Get-Field($Object, [string]$Name) {
        if ($null -eq $Object) { return $null }
        if ($Object -is [Collections.IDictionary]) { return $Object[$Name] }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -ne $property) { return $property.Value }
        return $null
    }
    function Escape-Text([AllowNull()][AllowEmptyString()][string]$Text) {
        $encoded = [Net.WebUtility]::HtmlEncode($Text)
        $encoded = [regex]::Replace($encoded, '[\\|`*_\[\]!~]|(?<!&)#', { param($match) '&#' + [int][char]$match.Value + ';' })
        $encoded.Replace("`r`n", '<br>').Replace("`n", '<br>').Replace("`r", '<br>')
    }
    function Link([string]$Label, [string]$Path, [string]$Anchor = '') {
        $url = (($Path.Replace('\', '/') -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
        if ($Anchor) { $url += '#' + [Uri]::EscapeDataString($Anchor) }
        "[$(Escape-Text $Label)]($url)"
    }
    function Evidence-Links($Evidence) {
        $files = @($Evidence | Where-Object { $null -ne $_ })
        $ordered = @($files | Where-Object Kind -eq 'Screenshot') + @($files | Where-Object Kind -ne 'Screenshot')
        if ($ordered.Count -gt 1 -and $ordered[0].Kind -eq 'Screenshot') {
            $other = @($files | Where-Object Kind -ne 'Screenshot' | Select-Object -First 1)
            if ($other.Count) { $ordered = @($ordered[0], $other[0]) }
        }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $links = @(
            foreach ($file in $ordered) {
                if (-not $file.Path) { throw 'Evidence reference is missing its Path.' }
                if (-not $seen.Add($file.Path)) { continue }
                $label = switch ($file.Kind) {
                    'Screenshot' { 'Screenshot' }
                    'Restoration' { 'Restoration receipt' }
                    'Source' { 'Source' }
                    default { 'Evidence' }
                }
                if (Get-Field $file 'Synthetic') { $label += ' (synthetic)' }
                if (Get-Field $file 'ReferenceOnly') { $label += ' (history only)' }
                Link $label $file.Path
                if ($seen.Count -eq 2) { break }
            }
        )
        if ($links.Count) { $links -join '; ' } else { 'No evidence recorded.' }
    }
    function Verdict-Counts($Rows) {
        $rowsArray = @($Rows | Where-Object { $null -ne $_ })
        $parts = @(
            foreach ($verdict in 'PASS', 'FAIL', 'BLOCKED', 'NOT-OBSERVED') {
                "**${verdict}**: $(@($rowsArray | Where-Object Verdict -eq $verdict).Count)"
            }
            foreach ($group in @($rowsArray | Where-Object { $_.Verdict -notin 'PASS', 'FAIL', 'BLOCKED', 'NOT-OBSERVED' } | Group-Object Verdict)) {
                "**$(Escape-Text $group.Name)**: $($group.Count)"
            }
        )
        "**Total**: $($rowsArray.Count); " + ($parts -join '; ')
    }

    foreach ($name in $DetailsName, $ResultsName, $ManifestName) {
        if ([string]::IsNullOrWhiteSpace($name) -or $name -in '.', '..' -or $name -match '[\\/:*?"<>|\x00-\x1f]') {
            throw 'Report targets must be nonempty basenames, not paths.'
        }
    }
    $metadata = Get-Field $State 'Metadata'
    if ($null -eq $metadata -or $null -eq (Get-Field $State 'Items') -or -not (Get-Field $State 'Signoff')) {
        throw 'State must supply Metadata, Items and Signoff from Get-PtReportState or results.json.'
    }
    $items = @($State.Items)
    $attempts = @(Get-Field $State 'Attempts' | Where-Object { $null -ne $_ })
    $events = @(Get-Field $State 'Events' | Where-Object { $null -ne $_ })
    $corrections = @($events | Where-Object Type -eq 'AssertionInvalidated')
    if (-not $events.Count) {
        $corrections = @($items | ForEach-Object { Get-Field $_ 'Corrections' } | Where-Object { $null -ne $_ })
    }
    $latestCleanup = @($attempts | Where-Object { $_.Phase -eq 'Cleanup' -and $_.Kind -eq 'Normal' } | Select-Object -Last 1)
    $restoration = @(Get-Field $State 'Restoration' | Where-Object { $null -ne $_ })
    $hasCurrent = if ($State -is [Collections.IDictionary]) { $State.Contains('CurrentRestoration') } else { $null -ne $State.PSObject.Properties['CurrentRestoration'] }
    $hasHistory = if ($State -is [Collections.IDictionary]) { $State.Contains('HistoricalRestorationFailures') } else { $null -ne $State.PSObject.Properties['HistoricalRestorationFailures'] }
    $current = @(
        if ($latestCleanup.Count) {
            $receipts = if ($hasCurrent) { @(Get-Field $State 'CurrentRestoration') } else { $restoration }
            $receipts | Where-Object { $null -ne $_ -and $_.AttemptId -ceq $latestCleanup[0].Id }
        }
    )
    $historicalFailures = @(
        if ($hasHistory) { Get-Field $State 'HistoricalRestorationFailures' }
        else {
            $restoration | Where-Object {
                $_.Data.Verdict -ne 'PASS' -and (-not $latestCleanup.Count -or $_.AttemptId -cne $latestCleanup[0].Id)
            }
        }
    )
    $historicalFailures = @($historicalFailures | Where-Object { $null -ne $_ })
    $restorationStatus = if (-not $current.Count) { 'MISSING' }
        elseif (@($current | Where-Object { $_.Data.Verdict -ne 'PASS' }).Count -or -not $latestCleanup[0].Complete) { 'BLOCKED' }
        else { 'PASS' }

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("# $(Escape-Text $metadata.Module) verification report")
    $lines.Add('')
    $lines.Add('## Summary')
    $lines.Add("**Signoff**: **$(Escape-Text $State.Signoff)** (as recorded).")
    $lines.Add('')
    $lines.Add("**BITS**: $(Escape-Text $metadata.Bits)")
    $lines.Add('')
    $lines.Add("**Scenario**: $(Escape-Text $metadata.Scenario)")
    if ($metadata.Scenario -eq 'InfrastructureAcceptance') {
        $lines.Add('**SYNTHETIC INFRASTRUCTURE ACCEPTANCE ONLY. Not a product signoff.**')
    }
    $created = Get-Field $metadata 'Created'
    if ($created) {
        if ($created -is [DateTimeOffset]) {
            $created = $created.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        } elseif ($created -is [DateTime]) {
            # Do not derive a local UTC offset from the rendering machine.
            $suffix = if ($created.Kind -eq [DateTimeKind]::Utc) { 'Z' } else { '' }
            $created = $created.ToString('yyyy-MM-ddTHH:mm:ss.fffffff', [Globalization.CultureInfo]::InvariantCulture) + $suffix
        }
        $lines.Add("**Recorded at**: $(Escape-Text $created)")
    }
    $lines.Add('')
    $lines.Add("**Items** - $(Verdict-Counts $items)")
    $product = @($items | Where-Object { $_.Verdict -eq 'FAIL' -and $_.Category -eq 'product' }).Count
    $checklist = @($items | Where-Object { $_.Verdict -eq 'FAIL' -and $_.Category -like 'checklist*' }).Count
    $other = @($items | Where-Object { $_.Verdict -eq 'FAIL' -and $_.Category -ne 'product' -and $_.Category -notlike 'checklist*' }).Count
    $lines.Add("FAIL categories: product $product; checklist $checklist; other $other.")
    $lines.Add('')
    $lines.Add("**Subassertions** - $(Verdict-Counts @($items | ForEach-Object Assertions))")
    $blockers = @($items | Where-Object Verdict -eq 'BLOCKED' | Group-Object Category | Sort-Object Name)
    if ($blockers.Count) {
        $lines.Add('')
        $lines.Add('**Blockers**: ' + (($blockers | ForEach-Object { "$(Escape-Text $_.Name): $($_.Count)" }) -join '; '))
    }
    $lines.Add('')
    $lines.Add("**Current restoration**: **$restorationStatus**; historical unsuccessful receipts: $(@($historicalFailures).Count). $(Link 'Cleanup receipts and history' $DetailsName 'cleanup-performed').")
    $lines.Add('')
    $lines.Add('**Recorded signoff reasons (unchanged)**')
    $reasons = @(Get-Field $State 'SignoffReasons' | Where-Object { $null -ne $_ })
    if ($reasons.Count) { foreach ($reason in $reasons) { $lines.Add("- $(Escape-Text $reason)") } }
    else { $lines.Add('None supplied.') }
    $lines.Add('')
    $lines.Add("**History**: $($attempts.Count) attempts; $(@($attempts | Where-Object Kind -eq 'Diagnostic').Count) diagnostic; $($corrections.Count) correction/invalidation events. $(Link 'Complete trace and history' $DetailsName). Diagnostic success does not replace Normal coverage.")
    $operations=@(Get-Field $State 'Operations' | Where-Object {$null -ne $_})
    if($operations.Count){
        $lines.Add('')
        $lines.Add("**Operation boundaries**: $($operations.Count) shared keys; $(@($operations|Where-Object Blocked).Count) stopped. $(Link 'Budgets, interruptions and cleanup errors' $DetailsName 'operation-boundaries'). These are infrastructure facts, not product verdicts.")
    }
    $lines.Add('')
    $lines.Add("Review the $(Link 'pre-flight trace' $DetailsName 'pre-flight'), $(Link 'structured results' $ResultsName) and $(Link 'integrity manifest' $ManifestName). Exact commands, raw observations and remaining artifacts are in the full traces, not repeated here.")
    $lines.Add('')
    $lines.Add('## Items')
    foreach ($item in $items) {
        $lines.Add('')
        $lines.Add("### $(Escape-Text $item.Id) - **$(Escape-Text $item.Verdict)**")
        $lines.Add('')
        $lines.Add((Escape-Text $item.Description))
        $lines.Add('')
        $lines.Add("**Category**: $(Escape-Text $item.Category); **Admin**: $(Escape-Text $item.Admin); **Clarity**: $(Escape-Text $item.Clarity).")
        if (Get-Field $item 'Reason') { $lines.Add("**Reason**: $(Escape-Text $item.Reason)") }
        foreach ($issue in @(Get-Field $item 'Issues')) {
            if ($null -ne $issue) { $lines.Add("- **Coverage note**: $(Escape-Text $issue)") }
        }
        $itemAttempts = @($attempts | Where-Object ItemId -CEQ $item.Id)
        $itemCorrections = @($corrections | Where-Object ItemId -CEQ $item.Id)
        $lines.Add('')
        $lines.Add("$(Link 'Full trace and remaining evidence' $DetailsName "item-$($item.Id)") - $($itemAttempts.Count) attempts; $(@($itemAttempts | Where-Object Kind -eq 'Diagnostic').Count) diagnostic; $($itemCorrections.Count) correction/invalidation events.")
        foreach ($child in $item.Assertions) {
            $lines.Add('')
            $lines.Add("- **$(Escape-Text "$($item.Id)/$($child.Id)") - $(Escape-Text $child.Verdict)**; required: $(Escape-Text ([string]$child.Required)). **Expected**: $(Escape-Text $child.Description)<br>**Actual / reason**: $(Escape-Text $child.Reason)<br>**Category**: $(Escape-Text $child.Category). $(Evidence-Links (Get-Field $child 'Evidence'))")
        }
        if (Get-Field $item 'Caveats') {
            $lines.Add('')
            $lines.Add("**Caveats**: $(Escape-Text $item.Caveats)")
        }
    }
    $lines.Add('')
    $lines.Add('## Cleanup performed')
    $lines.Add('')
    $lines.Add("**Current restoration**: **$restorationStatus**. Only receipts from the latest Normal Cleanup attempt are current.")
    if ($latestCleanup.Count) {
        $lines.Add("Latest Normal Cleanup: $(Escape-Text $latestCleanup[0].Name); completed: $(Escape-Text ([string]$latestCleanup[0].Complete)).")
    }
    if (-not $current.Count) { $lines.Add('No restoration receipt was recorded for that attempt (or no Normal Cleanup attempt exists). Earlier PASS receipts do not fill this gap.') }
    foreach ($receipt in $current) {
        $lines.Add("- **$(Escape-Text $receipt.Data.Verdict)**: $(Escape-Text $receipt.Data.Reason) $(Evidence-Links $receipt.Data.Evidence)")
    }
    $lines.Add('')
    $lines.Add("**Historical unsuccessful receipts**: $(@($historicalFailures).Count). These are history, not a claim that current restoration failed. $(Link 'All cleanup attempts and receipts' $DetailsName 'cleanup-performed').")
    $lines.Add('Current PASS covers only the comparisons stated in its receipts; no broader state equality is inferred. The supplied signoff and reasons above remain unchanged.')
    $lines.Add('')
    $lines.Add('## Retrospective')
    $lines.Add('')
    $completion = Get-Field $State 'Completion'
    if (Get-Field $completion 'NoFriction') {
        $lines.Add("Everything was smooth $([char]0x2014) no friction encountered.")
    } else {
        $rows = @(Get-Field $completion 'Retrospective' | Where-Object { $null -ne $_ })
        if (-not $rows.Count) { $lines.Add('**NOT-OBSERVED**: no retrospective was supplied.') }
        foreach ($row in $rows) {
            $lines.Add("- **$(Escape-Text $row.Source) / $(Escape-Text $row.Severity)** - $(Escape-Text $row.Friction)<br>**Cost**: $(Escape-Text $row.Cost)<br>**Suggested fix**: $(Escape-Text $row.SuggestedFix)")
        }
    }
    $lines.Add('')
    $lines.Add("$(Link 'Full retrospective' $DetailsName 'retrospective'). Both this review and the exhaustive details are integrity-covered exports; this renderer does not validate files or change recorded judgments.")
    $lines.Add('')
    return ($lines -join "`n")
}
