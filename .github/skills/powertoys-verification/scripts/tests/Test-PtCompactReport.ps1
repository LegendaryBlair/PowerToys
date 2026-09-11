#requires -Version 7.0
<#
.SYNOPSIS
Offline compact-renderer acceptance with optional read-only archived results.
.DESCRIPTION
Only imports the renderer. No recorder, desktop, product state, or archived scripts run.
Writes reports and acceptance-results.json only inside a new, explicitly supplied workspace.
An archived compact report is a rendering sample, not a complete integrity-checked export.
.EXAMPLE
pwsh -NoProfile -File .\Test-PtCompactReport.ps1 -Workspace C:\temp\compact-report-new
.EXAMPLE
pwsh -NoProfile -File .\Test-PtCompactReport.ps1 -Workspace C:\temp\compact-archive-new -ArchivedResults C:\archive\results.json -OriginalReport C:\archive\report.md
#>
param(
    [Parameter(Mandatory)][string]$Workspace,
    [string]$ArchivedResults,
    [string]$OriginalReport
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($OriginalReport -and -not $ArchivedResults) { throw '-OriginalReport requires -ArchivedResults.' }
$Workspace = [IO.Path]::GetFullPath($Workspace)
if (Test-Path -LiteralPath $Workspace) { throw 'Use a new test workspace; existing paths are never overwritten.' }
$renderer = [IO.Path]::GetFullPath("$PSScriptRoot\..\pt-verification-render.ps1")
$checks = [Collections.Generic.List[object]]::new()
$metrics = [ordered]@{}
[IO.Directory]::CreateDirectory($Workspace) | Out-Null

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Check([string]$Name, [scriptblock]$Action) {
    try {
        & $Action | Out-Null
        $checks.Add([pscustomobject]@{ Name = $Name; Status = 'PASS' })
    } catch {
        $checks.Add([pscustomobject]@{ Name = $Name; Status = 'FAIL'; Error = $_.ToString(); Stack = $_.ScriptStackTrace })
        throw
    } finally {
        $result = [ordered]@{ Checks = $checks.ToArray(); Metrics = $metrics }
        [IO.File]::WriteAllText((Join-Path $Workspace 'acceptance-results.json'), (ConvertTo-Json -InputObject $result -Depth 12))
    }
}
function Render($State) {
    $before = ConvertTo-Json -InputObject $State -Depth 60 -Compress
    $output = @(ConvertTo-PtVerificationSummary -State $State -DetailsName details.md -ResultsName results.json -ManifestName artifact-manifest.json)
    Require ($output.Count -eq 1 -and $output[0] -is [string]) 'Renderer must return exactly one string.'
    Require ($before -ceq (ConvertTo-Json -InputObject $State -Depth 60 -Compress)) 'Renderer changed its input state.'
    $output[0]
}
function Visible([string]$Text) {
    $Text.Replace("`r`n", '<br>').Replace("`n", '<br>').Replace("`r", '<br>')
}
function Assert-Coverage($State, [string]$Report) {
    $decoded = [Net.WebUtility]::HtmlDecode($Report)
    $children = @($State.Items | ForEach-Object Assertions)
    Require ([regex]::Matches($Report, '(?m)^### ').Count -eq $State.Items.Count) 'Item count changed in report.'
    Require ([regex]::Matches($Report, '(?m)^- \*\*.*\*\*; required: ').Count -eq $children.Count) 'Child count changed in report.'
    foreach ($item in $State.Items) {
        Require ($decoded.Contains("### $($item.Id) - **$($item.Verdict)**")) "Missing item verdict: $($item.Id)"
        Require ($decoded.Contains((Visible $item.Description))) "Missing item description: $($item.Id)"
        Require ($Report.Contains("(details.md#item-$($item.Id))")) "Missing full trace: $($item.Id)"
        foreach ($child in $item.Assertions) {
            $key = "$($item.Id)/$($child.Id)"
            $row = @($decoded -split "`n" | Where-Object { $_.StartsWith("- **$key - ") })
            Require ($row.Count -eq 1) "Missing or duplicated child: $key"
            Require ($row[0].Contains("**$key - $($child.Verdict)**; required: $($child.Required).")) "Verdict or required flag changed: $key"
            Require ($row[0].Contains("**Expected**: $(Visible $child.Description)<br>")) "Expected description changed: $key"
            Require ($row[0].Contains("**Actual / reason**: $(Visible $child.Reason)<br>")) "Actual reason changed: $key"
            $rawRow = @($Report -split "`n" | Where-Object { [Net.WebUtility]::HtmlDecode($_).StartsWith("- **$key - ") })
            Require ([regex]::Matches($rawRow[0], '\]\(').Count -le 2) "More than two evidence links: $key"
        }
    }
    foreach ($anchor in 'pre-flight', 'cleanup-performed', 'retrospective') {
        Require ($Report.Contains("(details.md#$anchor)")) "Missing trace reference: $anchor"
    }
    Require ($decoded.Contains("**Signoff**: **$($State.Signoff)** (as recorded).")) 'Signoff was reinterpreted.'
    foreach ($reason in $State.SignoffReasons) {
        Require ($decoded.Contains((Visible $reason))) 'A supplied signoff reason was dropped or rewritten.'
    }
}
function Copy-State($State) { ConvertTo-Json -InputObject $State -Depth 60 | ConvertFrom-Json }

Check 'Definitions-only import without output or dependencies' {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($renderer, [ref]$tokens, [ref]$parseErrors)
    Require ($parseErrors.Count -eq 0) 'Renderer has parse errors.'
    Require (@($ast.EndBlock.Statements | Where-Object { $_ -isnot [Management.Automation.Language.FunctionDefinitionAst] }).Count -eq 0) 'Import executes non-definition statements.'
    Require (@(. $renderer).Count -eq 0) 'Import produced output.'
}
. $renderer

$unicode = ([string][char]0x4E2D) + [char]0x6587 + ' ' + [char]0x00E9 + ' ' + [char]::ConvertFromUtf32(0x1F9EA)
$text = "$unicode | `"quoted`" 'single' <tag> & [link](url) ``ticks`` *stars* _under_ \path" + "`r`n# new line"
$artifactPath = 'attempts\11111111111111111111111111111111\22222222222222222222222222222222\screen (1) #"quote"|.png'
$evidence = @(
    @{ Path = 'attempts\11111111111111111111111111111111\probe.txt'; Kind = 'Evidence'; Synthetic = $true }
    @{ Path = $artifactPath; Kind = 'Screenshot'; Synthetic = $true }
    @{ Path = 'attempts\11111111111111111111111111111111\extra.png'; Kind = 'Screenshot'; Synthetic = $true }
    @{ Path = 'attempts\11111111111111111111111111111111\extra.txt'; Kind = 'Evidence'; Synthetic = $true }
)
$fixture = [pscustomobject]@{
    Metadata = @{ Module = 'Offline fixture'; Bits = "SYNTHETIC ONLY $text"; Scenario = 'InfrastructureAcceptance' }
    Signoff = 'WITHHELD'
    SignoffReasons = @('Prior execution errors remain recorded.', $text)
    Items = @(
        @{
            Id = 'L1'; Description = "Failing item $text"; Verdict = 'FAIL'; Category = 'product'; Admin = 'NO'; Clarity = 'CLEAR'
            Reason = 'Observed failure does not hide unfinished children.'; Issues = @('Required child remains NOT-OBSERVED.'); Caveats = $text
            Assertions = @(
                @{ Id = 'fail'; Description = "Expected $text"; Reason = "Actual $text"; Required = $true; Verdict = 'FAIL'; Category = 'product'; Evidence = $evidence }
                @{ Id = 'unseen'; Description = 'A separate unobserved expectation'; Reason = 'No Normal observation recorded.'; Required = $true; Verdict = 'NOT-OBSERVED'; Category = 'not-observed'; Evidence = @() }
                @{ Id = 'optional'; Description = 'Optional expectation'; Reason = 'Fixture prerequisite missing.'; Required = $false; Verdict = 'BLOCKED'; Category = 'BLK-ENV'; Evidence = @() }
            )
        }
        @{
            Id = 'L2'; Description = 'Passing synthetic item'; Verdict = 'PASS'; Category = 'fixture'; Admin = 'NO'; Clarity = 'CLEAR'; Reason = 'Fixture comparison only.'
            Assertions = @(@{ Id = 'pass'; Description = 'Fixture output matches'; Reason = 'Fixture output matched.'; Required = $true; Verdict = 'PASS'; Category = 'fixture'; Evidence = @() })
        }
    )
    Attempts = @(
        @{ Id = 'old-item'; ItemId = 'L1'; Kind = 'Normal'; Phase = 'Verification'; Complete = $true }
        @{ Id = 'new-item'; ItemId = 'L1'; Kind = 'Normal'; Phase = 'Verification'; Complete = $true }
        @{ Id = 'diagnostic'; ItemId = 'L1'; Kind = 'Diagnostic'; Phase = 'Verification'; Complete = $true }
        @{ Id = 'old-cleanup'; ItemId = ''; Kind = 'Normal'; Phase = 'Cleanup'; Complete = $true; Name = 'Earlier cleanup' }
        @{ Id = 'new-cleanup'; ItemId = ''; Kind = 'Normal'; Phase = 'Cleanup'; Complete = $true; Name = 'Latest cleanup' }
    )
    Events = @(@{ Type = 'AssertionInvalidated'; ItemId = 'L1'; Data = @{ Sequence = 7; Reason = 'Reviewed correction.' } })
    Restoration = @(
        @{ AttemptId = 'old-cleanup'; Data = @{ Verdict = 'FAIL'; Reason = 'Earlier fixture mismatch.'; Evidence = @() } }
        @{ AttemptId = 'new-cleanup'; Data = @{ Verdict = 'PASS'; Reason = 'Only the named fixture bytes matched.'; Evidence = @() } }
    )
    Completion = @{ NoFriction = $false; Retrospective = @(@{ Friction = $text; Source = 'HELPER-FLAW'; Severity = 'LOW'; Cost = '2 attempts'; SuggestedFix = "Preserve $text" }) }
}
$fixture = Copy-State $fixture

Check 'Complete child coverage including FAIL plus NOT-OBSERVED; bounded decisive evidence' {
    $report = Render $fixture
    Assert-Coverage $fixture $report
    Require ($report.Contains('SYNTHETIC INFRASTRUCTURE ACCEPTANCE ONLY. Not a product signoff.')) 'Missing synthetic warning.'
    Require ($report.Contains('**Total**: 2; **PASS**: 1; **FAIL**: 1; **BLOCKED**: 0; **NOT-OBSERVED**: 0')) 'Item counts are incorrect.'
    Require ($report.Contains('**Total**: 4; **PASS**: 1; **FAIL**: 1; **BLOCKED**: 1; **NOT-OBSERVED**: 1')) 'Child counts are incorrect.'
    Require ($report -match '\[Screenshot \(synthetic\)\]\([^)]+%28[^)]+\); \[Evidence \(synthetic\)\]') 'Screenshot must precede other decisive evidence.'
    Require (-not $report.Contains('extra.png') -and -not $report.Contains('extra.txt')) 'Mechanical artifact list leaked into summary.'
    Require ($report -notmatch '\[[^\]\r\n]*11111111111111111111111111111111') 'GUID path was used as a link label.'
    [IO.File]::WriteAllText((Join-Path $Workspace 'synthetic-report.md'), $report)
}
Check 'Unicode, HTML, Markdown and link destinations are safely escaped' {
    $report = Render $fixture
    $decoded = [Net.WebUtility]::HtmlDecode($report)
    Require ($decoded.Contains((Visible $text))) 'Unicode or original text was lost.'
    foreach ($escaped in '&quot;', '&#39;', '&#124;', '&lt;tag&gt;', '&amp;', '&#91;', '&#96;', '<br>') {
        Require ($report.Contains($escaped)) "Missing escaping: $escaped"
    }
    Require (-not $report.Contains('<tag>') -and -not $report.Contains('[link](url)')) 'Untrusted text rendered as markup.'
    Require ($report.Contains('%23%22quote%22%7C.png')) 'Link destination was not encoded.'
    $named = ConvertTo-PtVerificationSummary $fixture 'review (1).md' 'results #1.json' 'manifest &1.json'
    Require ($named.Contains('(review%20%281%29.md#item-L1)')) 'Details basename encoding failed.'
    Require ($named.Contains('(results%20%231.json)')) 'Results basename encoding failed.'
}
Check 'Historical failure then current PASS preserves signoff, scoped claims and history' {
    $report = Render $fixture
    Require ($report.Contains('**Current restoration**: **PASS**; historical unsuccessful receipts: 1.')) 'Old failure incorrectly made current restoration fail.'
    Require ($report.Contains('Only the named fixture bytes matched.')) 'Current receipt reason was rewritten.'
    Require ($report.Contains('5 attempts; 1 diagnostic; 1 correction/invalidation events.')) 'Run history is hidden.'
    Require ($report.Contains('3 attempts; 1 diagnostic; 1 correction/invalidation events.')) 'Item history is hidden.'
    Require ($report.Contains('no broader state equality is inferred')) 'Missing restoration scope disclaimer.'
    $modern = Copy-State $fixture
    $modern | Add-Member CurrentRestoration @($modern.Restoration[1])
    $modern | Add-Member HistoricalRestorationFailures @($modern.Restoration[0])
    Require ((Render $modern) -ceq $report) 'Modern and archived restoration projections differ.'
}
Check 'Missing latest receipt cannot inherit an older PASS, including explicit empty current state' {
    $missing = Copy-State $fixture
    $missing.Restoration = @($missing.Restoration[0])
    $missing.Restoration[0].Data.Verdict = 'PASS'
    Require ((Render $missing).Contains('**Current restoration**: **MISSING**; historical unsuccessful receipts: 0.')) 'Old PASS was mistaken for current receipt.'
    $modern = Copy-State $fixture
    $modern | Add-Member CurrentRestoration @()
    $modern | Add-Member HistoricalRestorationFailures @($modern.Restoration[0])
    Require ((Render $modern).Contains('**Current restoration**: **MISSING**;')) 'Explicitly empty current projection was ignored.'
}
Check 'Current FAIL or BLOCKED remains unsuccessful; diagnostic cleanup is not latest Normal cleanup' {
    foreach ($verdict in 'FAIL', 'BLOCKED') {
        $failed = Copy-State $fixture
        $failed.Restoration[1].Data.Verdict = $verdict
        $report = Render $failed
        Require ($report.Contains('**Current restoration**: **BLOCKED**;')) 'Current unsuccessful restoration appeared green.'
        Require ($report.Contains("- **${verdict}**: Only the named fixture bytes matched.")) 'Raw receipt verdict was rewritten.'
    }
    $diagnostic = Copy-State $fixture
    $diagnostic.Attempts += [pscustomobject]@{ Id = 'diagnostic-cleanup'; ItemId = ''; Kind = 'Diagnostic'; Phase = 'Cleanup'; Complete = $true }
    $diagnostic.Restoration += [pscustomobject]@{ AttemptId = 'diagnostic-cleanup'; Data = @{ Verdict = 'FAIL'; Reason = 'Diagnostic receipt.'; Evidence = @() } }
    Require ((Render $diagnostic).Contains('**Current restoration**: **PASS**; historical unsuccessful receipts: 2.')) 'Diagnostic receipt displaced latest Normal cleanup.'
}
Check 'Retrospective is preserved and never invents no-friction or dates' {
    $report = [Net.WebUtility]::HtmlDecode((Render $fixture))
    foreach ($field in 'Friction', 'Source', 'Severity', 'Cost', 'SuggestedFix') {
        Require ($report.Contains((Visible $fixture.Completion.Retrospective[0].$field))) "Missing retrospective field: $field"
    }
    Require (-not $report.Contains('Everything was smooth') -and -not $report.Contains('**Recorded at**')) 'Renderer invented no-friction or a timestamp.'
    $missing = Copy-State $fixture
    $missing.Completion = $null
    Require ((Render $missing).Contains('**NOT-OBSERVED**: no retrospective was supplied.')) 'Missing retrospective is not explicit.'
    $smooth = Copy-State $fixture
    $smooth.Completion = @{ NoFriction = $true }
    Require ((Render $smooth).Contains("Everything was smooth $([char]0x2014) no friction encountered.")) 'Explicit no-friction was not preserved.'
}
Check 'Portable dictionary input and invalid basename rejection' {
    $dictionary = ConvertTo-Json -InputObject $fixture -Depth 60 | ConvertFrom-Json -AsHashtable
    Require ((Render $dictionary) -ceq (Render $fixture)) 'Dictionary input differs from JSON object.'
    try {
        ConvertTo-PtVerificationSummary $fixture '..\details.md' results.json artifact-manifest.json | Out-Null
    } catch {
        Require ($_.Exception.Message -match 'basenames') 'Unexpected rejection error.'
        return
    }
    throw 'Unsafe basename was accepted.'
}
Check 'Recorded timestamps do not depend on rendering culture or a machine-derived offset' {
    $dated = Copy-State $fixture
    $dated.Metadata | Add-Member Created ([datetime]::new(2020, 1, 2, 3, 4, 5, [DateTimeKind]::Unspecified))
    Require ((Render $dated).Contains('**Recorded at**: 2020-01-02T03:04:05.0000000')) 'Typed timestamp was rendered using a machine-specific format.'
    $dated.Metadata.Created = [datetimeoffset]::new(2020, 1, 2, 3, 4, 5, [TimeSpan]::FromHours(8))
    Require ((Render $dated).Contains('**Recorded at**: 2020-01-02T03:04:05.0000000+08:00')) 'Supplied timestamp offset was lost.'
    $dated.Metadata.Created = '2020-01-02T03:04:05.1234567+08:00'
    Require ((Render $dated).Contains('**Recorded at**: 2020-01-02T03:04:05.1234567+08:00')) 'String timestamp was rewritten.'
}

if ($ArchivedResults) {
    Check 'Read-only authentic 27-item / 111-child archive and report-size acceptance' {
        $archivePath = [IO.Path]::GetFullPath($ArchivedResults)
        $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        $archived = Get-Content -LiteralPath $archivePath -Raw | ConvertFrom-Json
        $report = Render $archived
        Assert-Coverage $archived $report
        Require ($archived.Items.Count -eq 27) 'Expected the authentic 27-item acceptance archive.'
        Require (@($archived.Items | ForEach-Object Assertions).Count -eq 111) 'Expected the authentic 111-child acceptance archive.'
        Require ($report.Contains('**Total**: 27; **PASS**: 9; **FAIL**: 7; **BLOCKED**: 11; **NOT-OBSERVED**: 0')) 'Authentic item verdict counts changed.'
        Require ($report.Contains('**Total**: 111; **PASS**: 69; **FAIL**: 9; **BLOCKED**: 30; **NOT-OBSERVED**: 3')) 'Authentic child verdict counts changed.'
        Require ($report.Contains('**Current restoration**: **PASS**; historical unsuccessful receipts: 3.')) 'Authentic current and historical restoration were conflated.'
        $bytes = [Text.Encoding]::UTF8.GetByteCount($report)
        Require ($bytes -le 200KB) "Compact report exceeds 200 KiB: $bytes bytes."
        $metrics.ArchivedItems = $archived.Items.Count
        $metrics.ArchivedChildren = @($archived.Items | ForEach-Object Assertions).Count
        $metrics.CompactBytes = $bytes
        $metrics.ItemVerdicts = @($archived.Items | Group-Object Verdict | Select-Object Name, Count)
        $metrics.ChildVerdicts = @($archived.Items | ForEach-Object Assertions | Group-Object Verdict | Select-Object Name, Count)
        if ($OriginalReport) {
            $originalPath = [IO.Path]::GetFullPath($OriginalReport)
            $originalHash = (Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash
            $originalBytes = (Get-Item -LiteralPath $originalPath).Length
            Require ($bytes -lt 0.30 * $originalBytes) "Compact report must be less than 30% of original: $bytes / $originalBytes."
            $metrics.OriginalBytes = $originalBytes
            $metrics.PercentOfOriginal = [Math]::Round(100 * $bytes / $originalBytes, 3)
            $metrics.ReductionPercent = [Math]::Round(100 * (1 - $bytes / $originalBytes), 3)
            Require ((Get-FileHash -LiteralPath $originalPath -Algorithm SHA256).Hash -ceq $originalHash) 'Original report changed.'
        }
        Require ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ceq $archiveHash) 'Archived results changed.'
        [IO.File]::WriteAllText((Join-Path $Workspace 'archived-compact-report.md'), $report)
    }
}
[pscustomobject]@{ Passed = $checks.Count; Workspace = $Workspace; Metrics = $metrics } | ConvertTo-Json -Depth 6
