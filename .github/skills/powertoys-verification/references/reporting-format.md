# Reporting format

This doc defines the **required** report shape for every per-module verification run.
`report.md` is the concise human review view; `details.md` retains the exhaustive, reproducible
trace modeled on `PR-validation\Round1\PR-47211-validation\report.md`. Compact presentation
never removes registered assertions, changes verdicts, or replaces the detailed record.

Use the reusable recorder and exporter in [Recording workflow](recording-workflow.md)
instead of building a report generator during each run. Initialize its explicit item and
subassertion inventory before discovery; snapshot the actual source inputs, including
dirty-worktree helper versions. The templates below describe the rendered report, not
permission to reconstruct commands or observations after the fact.

Daily review uses `Get-PtVerificationReview`, an explicitly unvalidated incremental view.
It is not a substitute for either exported report. Large raw observations belong in
registered attachments, not `Actual`/`Reason` fields; new observation and assertion text
has a 4096-byte UTF-8 limit. Export continues to include every registered child and all
evidence links, with unchanged verdict/signoff rules. Identical execution source bytes
may share a hash-addressed path while each step retains its exact command and arguments.
Runs using operation boundaries also include per-invocation execution history and
operation error history in `details.md`, linked from the compact summary. Pending or
recording-failed operations add an explicit infrastructure signoff hold; they do not
assign or rewrite product assertions.
Operations have no label-based locks or cumulative limits. Pending/uncertain invocation
evidence can withhold signoff without prohibiting later actions by label. Old limit
policies and stops remain historical evidence, never active execution rules.

## Compact review and exhaustive details

The exporter writes both views from the same recorded state:

- **`report.md`**: BITS, scenario, supplied signoff and reasons, counts covering every item,
  blockers, all item descriptions, and every registered child's expected description, actual
  reason and verdict. Every newly registered assertion needs an outcome; there is no
  optional/required choice. Keep **NOT-OBSERVED** visible even under a **FAIL** item.
  Show at most two decisive evidence links per child, preferring a screenshot then other
  evidence, with short labels rather than repeated GUID-heavy directory names. Link each
  item to its full trace for exact commands, all evidence and historical observations.
  Link current assertion results to their Normal judgment/observation sequence; partial
  attempts can contribute different assertions without hiding their origins.
  For recognized frozen checklist blocks, show the scenario title and setup/source notes,
  then each expected condition once in its verdict row. Remove checkbox/metadata and repeated
  bold-ID wrappers only when every source child exactly matches a rendered child.
  Functional prose checklists with explicit inventory children show the full case paragraph
  and the unchanged child descriptions; an omitted clarity tag means the recorded CLEAR default.
  Unknown shapes or mismatches retain the original escaped description; no condition is guessed away.
- **`details.md`**: the exact per-item step/artifact template in §A, §C and §F, full Normal
  and Diagnostic attempts, raw observations, corrected/invalidated judgments, pre-flight,
  cleanup and retrospective. Do not abbreviate this view to meet compact-report size limits.
  Full checklist source descriptions remain unchanged here and in `results.json`; compact
  presentation does not modify the inventory, source hash or recorded outcomes.
- **`results.json`** and **`artifact-manifest.json`**: the structured record and
  integrity inventory. Mandatory integrity validation covers **both Markdown files**, results,
  the journal, input snapshots and every referenced artifact. The manifest records `DetailsPath`
  as well as `ReportPath`; the exporter returns `Details` as well as `Report`.
- **`statistics.json`**: the required structured statistics for new runs, collected under
  [the statistics contract](#agent-origin-execution-statistics) and registered as evidence
  before final export. The recorder loads the latest registered JSON, validates its hash
  and run identity, and includes it as `ExecutionStatistics` in the exported state.
  **`report.md` displays the module summary, agent tool distribution and per-case table
  inline**; a raw JSON link is supplementary. A separate `statistics.md` is not required.
  Neither the exporter nor renderer scans session logs or expands helper-internal calls.

The compact renderer is a definitions-only, dependency-free script:
`scripts\pt-verification-render.ps1`. Its exact API is:

```powershell
ConvertTo-PtVerificationSummary -State $state -DetailsName details.md `
    -ResultsName results.json -ManifestName artifact-manifest.json
```

It accepts a `Get-PtReportState` object or a previously exported `results.json` object and
returns **one Markdown string**, without reading the live machine, reading artifact files,
writing files, or changing state/signoff gates. The caller supplies the output basenames,
including partial-export prefixes. Render paths as URL paths; escape text and link destinations
without rewriting descriptions or evidence claims. Synthetic infrastructure acceptance must
say **not a product signoff**. Never invent a date, build, assertion or no-friction conclusion.
Current exported states carry the loaded statistics, so the same pure renderer can reproduce
their inline tables. An older exported state with only artifact references must be reloaded
through `Get-PtReportState` to display the JSON data; otherwise it explicitly reports that
statistics are unavailable in the supplied state. Do not modify the original archive.

Keep history visible in the compact view: report attempt, Diagnostic and correction/invalidation
counts and link to details. Full details expose `<a id="item-<Id>"></a>` before each item and
the `Pre-flight`, `Cleanup performed` and `Retrospective` headings as stable link targets.

**Restoration is scoped, not inferred.** Use the current restoration projection when supplied;
for older results, select the last **Normal Cleanup** attempt ID and only its receipts. An
earlier PASS never fills a missing latest receipt. Display current **PASS / BLOCKED / MISSING**,
the current receipts' original verdicts/reasons, and the count of historical unsuccessful
receipts separately. Historical FAIL/BLOCKED receipts remain in details; their presence is not
a statement that current restoration failed. A current PASS proves only the receipt's stated
comparisons, not broader state equality. Keep the supplied signoff and its reasons unchanged,
even when an older result's withheld-signoff explanation refers to historical cleanup failures.

Run the portable offline acceptance without product/desktop interaction:

```powershell
& .\scripts\tests\Test-PtCompactReport.ps1 -Workspace C:\temp\compact-report-new
```

The workspace must be new. Optional `-ArchivedResults <results.json>` exercises the authentic
27-item/111-child reference case read-only; optional `-OriginalReport <report.md>` additionally
compares sizes. Require all descriptions and children to remain present, compact output at most
200 KiB, and output less than 30% of the original report when supplied. The test writes samples
only under its workspace, never into the archive; a sample alone is not a complete signed-off
export.

## §A — Per-item table in details.md (one per checklist item)

```markdown
## Item L<line_num> — <verbatim description from the module's checklist> — **<PASS|FAIL|BLOCKED>** <emoji>

**Admin**: <NO|COND|YES>  |  **Clarity**: <CLEAR|VAGUE-*|REWRITTEN>  |  **Category**: <PASS: verification method (free text)  ·  FAIL: cause = product | checklist-stale | checklist-ambiguous  ·  BLOCKED: a BLK-* reason>

### Verification steps performed

| # | Step | winapp / probe commands | Evidence / result |
|---|---|---|---|
| 1 | <what step 1 does> | `<exact command>`<br>`<another command if multiple>` | <what you observed; reference artifact filename> |
| 2 | <what step 2 does> | `<command>` | <evidence>; screenshot: `artifacts/L<line>/step-02-<name>.png` |
| 3 | ... | ... | ... |

### Artifacts produced
- `artifacts/L<line>/step-01-<name>.png` — <one-line description>
- `artifacts/L<line>/step-02-<name>.txt` — full inspect dump
- ...

### Verdict reasoning
- ✅ <assertion 1 that PASSed, with reference to the line of code / settings key / log line that proves it>
- ✅ <assertion 2>
- ❌ <if BLOCKED, the specific obstacle: "BLK-HARDWARE because MWB needs 2 physical PCs; this session has 1 ([System.Windows.Forms.Screen]::AllScreens.Count = 1)">

### Caveats (optional)
- <Any deviation from the user-documented flow, e.g. "Tested via settings.json write rather than UI checkbox because SelectionItemPattern.Select clobbers other selections in ListView.">
```

## §B — Exhaustive details summary (write LAST, after all per-item tables)

This is the full-trace template, not a requirement to duplicate step tables in `report.md`.
The compact view follows the contract above and links to these sections.

```markdown
# <Module> verification report — <YYYY-MM-DD HH:MM>

## Summary
- **PASS**: <n>  ·  **FAIL (product)**: <n>  ·  **FAIL (checklist)**: <n>  ·  **BLOCKED**: <n>  ·  **Total**: <n>  ·  **PASS%**: <n>
- **Top blocker categories**: <category>: <count>, <category>: <count>, ...
- **Items needing follow-up**: L<line> (<reason>), L<line> (<reason>), ...
- **State mutations performed + restored**: <count> settings.json edits restored, <count> registry keys removed, <count> fixture files deleted

## Pre-flight
- IsAdmin: <true|false>
- PT runner: PID=<n> Elevated=<true|false>
- <Module> settings file: <path> (exists=<true|false>)
- Interactive desktop: ForegroundOk=<true|false>  ShellComOk=<true|false>

## Items
<all per-item tables here, in line_num order>

## Cleanup performed
- <list of every restore action taken>

## Execution statistics
<inline module totals, agent tools and per-case execution table; no click-through required>

## Retrospective (self-reflection on the run — write LAST)
<Per §G. If the whole run was frictionless, write exactly: **Everything was smooth — no friction encountered.**>
```

## §C — Required rules for step tables in details.md

1. **Every `winapp ui ...` command goes in the "winapp / probe commands" cell, verbatim, in backticks**, including `-w <hwnd>` / `-a <appId>` arguments and full selector strings. Reviewers will paste these into their own shell to reproduce.
2. **Every screenshot path goes in the "Evidence" cell** of the step that produced it, formatted as `screenshot: artifacts/L<line>/step-NN-<name>.png`. Never embed screenshots as `![...](...)` in the table body (breaks GitHub markdown rendering inside cells); just give the path.
3. **If a step has multiple commands**, separate them in the same cell with `<br>` so they render as one cell with multiple lines.
4. **PowerShell scriptlets > 3 lines**: write them to a separate `.ps1` in the artifacts folder and reference as ``script: `artifacts/L<line>/step-NN.ps1` `` in the cell. Keep the table cell to 1-3 lines.
5. **`—` (em dash) is allowed for non-CLI steps** like "Read sign-off entry + diff", "Create validation folder", "Cleanup notepad". Don't fabricate a command for steps that were purely cognitive or file-system level.
6. **Numbered steps must be contiguous** (1, 2, 3, ...). Don't skip numbers.
7. **At least one screenshot per PASS item if the item is a user-visible behavioral test**. Schema-only assertions (settings.json key check) don't need screenshots; behavioral tests (popup shown, dialog appeared, theme switched) do.

### Recorded-report rules

- Record **every** winapp command, including discovery, diagnostics and helper-internal
  probes, through the ambient attempt integration in [Recording workflow](recording-workflow.md).
  Preflight/cleanup use non-item contexts. Preserve the executed script version, resolved
  command, raw outputs/errors, timestamps, duration and unique artifact paths for each step.
- Retain **Normal and Diagnostic attempts separately**. A restart-recovered diagnostic
  PASS does not prove normal reopen. Normal product/checklist failures remain failures
  in that run; command completion/exit zero never assigns a product verdict.
- Select results per assertion, not per whole scenario. Only an attempt addressing that
  assertion can replace its result; a partial continuation leaves unrelated coverage intact.
  Delayed review is not a new execution. Keep source attempt/judgment IDs in structured
  results and details, and preserve pending review rather than reusing an older PASS.
- Show every registered child as **PASS / FAIL / BLOCKED / NOT-OBSERVED**, with its reason
  and evidence, even under a failing parent. Missing observations cannot produce
  item PASS. Unfinished items remain **BLOCKED / BLK-INCOMPLETE**; command/capture errors
  are **BLK-INFRASTRUCTURE**, not inferred product defects. These two recording categories
  supplement, rather than replace, the existing environment/hardware BLOCKED reasons.
  Explicit child `BLOCKED / BLK-INCOMPLETE` is supported for unfinished coverage;
  `NOT-OBSERVED / not-observed` remains distinct. Neither establishes an infrastructure
  root cause. Describe proven test bugs as test bugs in the reason and retrospective;
  do not relabel a wrong selector, return-property misuse or recursive serialization as
  merely unclear documentation. Unexplained errors remain untriaged until evidence
  separates test defects from unavailable external conditions.
- An unmet condition is a stated execution/observation limitation, not an "optional"
  assertion. Unfinished work is not a product FAIL. Do not omit either from the inventory.
  New reports need no Required column; historical `Required=false` values, if present,
  are labeled as legacy metadata rather than offered as a current configuration. Current
  calculations include every declared assertion, even when reading an older inventory.
  Never rewrite an existing archived report to apply these rules retrospectively.
- Include **BITS**, explicit cleanup/restoration receipts and **Signoff: APPROVED or
  WITHHELD** in the summary. Withhold signoff for failed, blocked, unobserved or incomplete
  coverage, execution/cleanup errors, missing evidence or unrecorded restoration.
- Use the latest complete Normal Cleanup scope to judge restoration. Historical failures
  remain in the trace but do not veto a later verified full recovery. One current PASS
  cannot hide another current FAIL/BLOCKED, and old receipt imports are not fresh evidence.
- Never overwrite a screenshot or script revision. Associate screenshots with their
  producing step and Normal-path assertion. Synthetic fixtures are labeled and cannot
  substantiate a product signoff.
- When literal pipes/backticks/newlines would break the table, use safely encoded code
  spans and line breaks plus a link to the **unchanged raw command/script artifact** for
  copy/paste. Keep raw output outside Markdown. The structured results retain verbatim
  descriptions, observations and Unicode text.
- Export the mandatory full inventory, machine-readable results and artifact manifest.
  Validate every referenced file and SHA256, including **report.md and details.md** and input
  snapshots, before accepting the report and again after moving the whole workspace. A missing/corrupt artifact
  invalidates the export; an interrupted step remains explicitly incomplete.

## §D — Reporting style

- Be specific. "Verified via UIA inspect returned `itm-calculator-XXXX`" beats "verified UIA".
- Include exact UIA selectors, log line text, settings.json keys, and screenshot filenames so the user can audit.
- For BLOCKED items, the 1-sentence reason should name **what specifically blocks**, e.g.:
  - "BLK-HARDWARE: requires 2nd monitor; session has 1 (verified via `[System.Windows.Forms.Screen]::AllScreens.Count`)."
  - "BLK-DRAG-REQUIRED: synthetic mouse drag insufficient for FZ snap-and-drag; needs real cursor motion."
  - "BLK-ENV: SendInput returned ACCESS_DENIED (5) because Session $agentSession ≠ console Session $consoleSession. See `references/environment-setup.md`."
  - "BLK-EXTERNAL-APP: requires real OpenAI API key; no key provisioned in test env."

## §E — Reporting anti-patterns (extra strict)

- Do NOT collapse multiple probe commands in **details.md** into a single English sentence like "verified via UIA". List every `winapp ui ...` command verbatim in a step row. The compact view links to this trace instead of duplicating it.
- Do NOT skip the **details.md** step table for "trivial" items. Even a 1-step item (e.g. "Get-CmdPalSettings shows EnableDock=true") gets a 1-row table.
- Do NOT write screenshot references as `![alt](path)` inside table cells (GitHub renders markdown images poorly in cells). Write them as plain text path: `screenshot: artifacts/L<line>/step-NN-<name>.png`.
- Do NOT use "the test passed" as a screenshot caption — describe what's visible (e.g. "Settings page with FZ template grid showing 7 templates").
- Do NOT reference screenshots that you didn't actually capture. The final wrap-up `Test-Path` loop (see `references/pre-flight.md` §Final wrap-up step 3) will catch missing files; failing that check means the report is invalid.
- Do NOT cite source code line numbers (e.g. `CharacterMappings.cs:273`) without having actually read that line. If you cite source, the path must be real and the line number must contain what you claim.

## §F — Example details.md item (reference: PR-47211 validation report style)

```markdown
## Item L455 — Activate Quick Accent (left Alt + arrow key) on a character, verify accents popup — **PASS** ✅

**Admin**: NO  |  **Clarity**: CLEAR  |  **Category**: drove full UIA flow + asserted accents popup

### Verification steps performed

| # | Step | winapp / probe commands | Evidence / result |
|---|---|---|---|
| 1 | Locate Settings window | `winapp ui list-windows --json` | `hwnd=263304`, `PowerToys.Settings` PID 31740 |
| 2 | Navigate to Quick Accent + expand language flyout | `winapp ui invoke QuickAccentNavItem -w 263304`<br>`winapp ui invoke btn-choosecharacter-1c4d -w 263304` | Page loaded; flyout expanded |
| 3 | Enumerate language list + screenshot | `winapp ui inspect btn-choosecharacter-1c4d -w 263304 --depth 5`<br>`winapp ui screenshot -w 263304 -o "artifacts/L455/step-03-language-list.png"` | 38 spoken + 6 special languages, alphabetic. screenshot: `artifacts/L455/step-03-language-list.png` |
| 4 | Single-language (French) popup test | `winapp ui invoke itm-french-1cac -w 263304`<br>`winapp ui inspect characters -w <popupHwnd> --depth 3`<br>`winapp ui screenshot -w <popupHwnd> -o "artifacts/L455/step-04-popup-FR-E.png"` | Popup chars for **E** = `é è ê ë €` (5), matches `FR.VK_E` in `CharacterMappings.cs:273`. screenshot: `artifacts/L455/step-04-popup-FR-E.png` |
| 5 | Restore baseline | — | settings.json reverted to `selected_lang="ALL"` |

### Artifacts produced
- `artifacts/L455/step-03-language-list.png` — Settings page with expanded language flyout
- `artifacts/L455/step-03-language-list.txt` — full UIA inspect dump of the list
- `artifacts/L455/step-04-popup-FR-E.png` — Popup with French only: `é è ê ë €`

### Verdict reasoning
- ✅ Popup characters match `CharacterMappings.cs` entries exactly (5/5 for FR.VK_E)
- ✅ Popup appeared within 500ms of hold-A; no crash
- ✅ Language list ordering is alphabetic by localized name
```

## Agent-origin execution statistics

For every new module run, the **executing agent** must extract basic statistics from its
own session log before writing the final report and retrospective. This is a reporting
responsibility, not another coordinator, agent or product test. Use a small local read-only
extraction script if needed; do not create another report generator or instrument every
PowerShell function. Produce `statistics.json`; the fixed renderer presents the useful
statistics directly in `report.md`.

### Execution and reporting boundaries

Treat these as two logical stages in the same agent session:

1. **Task 1 - execution:** module preparation, preflight, cases, necessary recovery and
   cleanup. Record the session ID, first execution event and a cutoff event/time after
   the last execution/cleanup operation has completed or reached an explicitly recorded
   interrupted state. A tool returning while its shell continues is not that shell's
   completion; reconcile the related background operation before claiming a closed interval.
   Retained product processes or a recovery keeper are not new calls merely because they
   remain alive.
2. **Task 2 - reporting:** read only the closed Task 1 event range, derive the statistics,
   then explain the expensive/repeated operations in the retrospective. Exclude the log
   reads, extraction, report writing, final export and archive work performed in Task 2
   from Task 1 totals. The overall session need not have ended.

A single controller tool request may contain both stages (for example the template's
`-Report` callback). Count that Task 1-origin request once, but do not charge its eventual
Task 2 completion time to execution. Use an explicit phase boundary to clip its Task 1
interval, or leave the phase-specific duration unavailable. Tool-response duration is
not necessarily child-process duration, especially for asynchronous shells.

If reporting discovers a need for additional execution, record another bounded Task 1
segment and regenerate the statistics before final sealing. Do not include the intervening
reporting work by extending one unqualified whole-session time range. Completed prior
sessions can be read too, but include only sessions and ranges actually belonging to
this run; do not combine unrelated work or guess missing subagent activity.

Select boundaries from recorded operations, not a regex that happens to match one spelling
of a recovery script command. Preparing statistics, reviewing old evidence, assigning final
verdicts and writing BLOCKED dispositions are **Task 2**, even if a run-local script recorded
them under `Phase=Verification` or gave them an `ItemId`. They must not extend case execution
spans or count as new execution attempts. Show bookkeeping separately when it cannot be
cleanly separated; do not present it as measured driving time.

Read a bounded, complete-line prefix of the active log with shared read access. Preserve
the selected boundary even while the log grows; do not repeatedly scan the whole history.
An unfinished last JSON line, missing completion or unavailable session log must be
reported as a coverage limitation, never silently treated as zero activity.

### What a call means

**Count calls requested directly by the agent, not calls made inside a script/helper.**
The statistics describe agent-origin requests, not the total number of internal runtime
executions. Pair session events such as `tool.execution_start` and
`tool.execution_complete` by `(sessionId, toolCallId)`; use their timestamps, not message
length or narrative estimates. The current CLI stores these in its per-session
`events.jsonl`; inspect the available schema rather than assuming every version has the
same fields. Read metadata locally and never copy the raw session log into the archive.

### Log schemas and timezone-safe parsing

Do not confuse these two files, both commonly named `events.jsonl`:

| Source | Structure and intended use |
|---|---|
| Agent session log, under `.copilot\session-state\<session-id>` | Direct JSON records: `type`, `id`, `timestamp`, `data`. Start events have `data.toolCallId`, `data.toolName` and `data.arguments`; completion events have the same call ID and `data.success`. Obtain a completion's tool name from its matching start, not an assumed completion field. |
| Verification run journal, under the run workspace | Hash-protected envelopes with a JSON-string `Payload`; use `Read-PtReportEvents -Run $run` to validate/decode them. Its events have `Type`, `Timestamp`, `ItemId`, `AttemptId`, `StepId` and `Data`. Use them for case/operation attribution, not extra agent request counts. |

Check the actual schema before filtering and retain counts of decoded records and tool-start
records before/after selecting the execution segments. A schema/read error is an unavailable
statistic, not an empty successful result.

Use `ConvertFrom-PtReportJson` from the existing recorder so ISO timestamps remain strings
on supported PowerShell versions. Plain `ConvertFrom-Json` can turn them into `DateTime`.
Passing that value to `DateTimeOffset.Parse` then implicitly formats a zone-less string,
losing its UTC kind and fractional precision. On a UTC+8 host, `07:40Z` can be interpreted
as `07:40+08:00` and shift outside the chosen range. This is a parsing bug, not a different
session-log format.

The following reporting-script snippet preserves offsets and rejects ambiguous time values:

```powershell
# Statistics UTC parsing
function ConvertTo-StatisticsUtc {
    param([Parameter(Mandatory)]$Value)
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) {
            throw 'Statistics timestamp has no timezone.'
        }
        return ([DateTimeOffset]$Value).ToUniversalTime()
    }
    if ($Value -isnot [string] -or $Value -cnotmatch '(Z|[+-][0-9]{2}:[0-9]{2})$') {
        throw 'Statistics timestamp must contain an explicit timezone.'
    }
    [DateTimeOffset]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None).ToUniversalTime()
}

# $line is one complete raw agent-session JSONL record; the recorder helper is loaded.
$sessionEvent = ConvertFrom-PtReportJson $line
$eventUtc = ConvertTo-StatisticsUtc $sessionEvent.timestamp
```

Normalize boundaries with the same function and serialize with `.ToString('o')`. Never
format to local display text and parse it back, compare timestamp strings with different
offsets, or truncate to whole seconds before counting. Use start-inclusive/end-exclusive
execution segments; the end marks the first excluded reporting activity, after included
execution completions. Retain event IDs/order for records sharing a boundary timestamp.

```powershell
# Statistics execution segments
function Test-StatisticsExecutionTime {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][object[]]$Segments)
    if (-not $Segments.Count) { throw 'Statistics execution segments are missing.' }
    $time = ConvertTo-StatisticsUtc $Value
    $previousEnd = $null
    $included = $false
    foreach ($segment in $Segments) {
        $start = ConvertTo-StatisticsUtc $segment.StartUtc
        $end = ConvertTo-StatisticsUtc $segment.EndUtc
        if ($end -le $start -or ($null -ne $previousEnd -and $start -lt $previousEnd)) {
            throw 'Statistics execution segments must be ordered, nonempty and nonoverlapping.'
        }
        if ($time -ge $start -and $time -lt $end) { $included = $true }
        $previousEnd = $end
    }
    $included
}
```

These are small extraction examples, not an automatic collector or new runtime protocol.
Their timestamp/segment behavior is exercised by `scripts\tests\Test-PtStatisticsGuidance.ps1`.

### Agent workload by tool type

The primary workload metric is the **actual agent tool name** from the session log.
Count distinct `(SessionId, ToolCallId)` pairs and group by `ToolName`:

| Metric | Counting rule |
|---|---|
| Agent tool requests | One actual leaf tool request per `toolCallId`. Do not also count a parallel-dispatch wrapper as each of its children. |
| `powershell` | Agent shell requests, whether they launch a script, invoke helpers or submit a command batch. This is not a count of `.ps1` file launches. |
| `view` | Agent requests to read files/images; not a count of all files a script opened. |
| `apply_patch` | Agent edit requests; not the number of files, lines or hunks changed. |
| `rg`, `glob`, `read_powershell`, other tools | Keep each actual tool type as its own row, including output polling. Do not collapse all of these into an opaque Other total. |

Do not relabel a PowerShell tool request as winapp merely because its command invokes
winapp. Do not multiply by the number of statements or loop iterations in the request.
Legacy direct script/winapp/helper categories may remain in raw historical JSON, but are
not required metrics or columns in the report. In particular, do not fill the main table
with zero winapp/helper columns when an agent launches a batch controller.

Examples:

| Agent-submitted request | Agent workload |
|---|---|
| PowerShell runs `& .\case.ps1`, which invokes winapp 30 times | `powershell`: 1; no internal calls added |
| PowerShell runs `Invoke-PtWinApp -Arguments @('inspect', ...)` | `powershell`: 1 |
| One PowerShell request runs two helper methods | `powershell`: 1, not two method requests |
| PowerShell submits a loop invoking `case.ps1` | `powershell`: 1, independent of loop count |
| `read_powershell` polls an existing shell | `read_powershell`: 1; not another script launch |

Repeated agent requests count again, including failed requests. Keep three different
outcomes separate: runtime tool-call success, the command's actual exit status, and the
product assertion verdict. A successfully returned PowerShell tool response can contain a
failed command. Unknown exit status is not zero.

### Per-case attribution and time

Use explicit case IDs in the agent's submitted operation/phase mapping and the existing
verification journal's `ItemId`/`AttemptId`/timestamps. Record the association while
executing when possible. The journal supplies case boundaries and Normal/Diagnostic
attempts; its nested winapp/helper records are **not** added to agent-origin call counts.
Do not infer case ownership from an arbitrary nearby conversation message.

For each checklist case report:

| Field | Meaning |
|---|---|
| Start / end (UTC) | First and last explicitly associated Task 1 operation/attempt boundaries; null if unavailable |
| Case span | Last minus first associated boundary within each Task 1 segment; sum segments, excluding intervening Task 2 time. Includes gaps inside a segment and is not CPU time. |
| Normal / Diagnostic attempts | Separate counts from the run journal; repeated calls alone do not prove a new attempt |
| Recorded driver time | Duration of outer case execution steps only (`ParentStepId` empty), intersected with Task 1 segments. Includes waits; do not add nested step durations again. |
| Driver errors | Number of those outer case execution steps with `Status=Error`. Retain recovered errors in this cost metric; it is not a count of product defects. Inner fallback errors remain in the detailed trace. |
| Verdict | The existing case verdict from the recorder, not recomputed from statistics |

If one agent-launched script handles several cases, assign that launch once to a
`MULTI-CASE` row; do not credit the same launch or its whole duration to each case. Retain
case spans from explicit inner case boundaries if available, while identifying that their
operations were inside the batch rather than direct agent calls. With no case boundary,
duration is unavailable, not a proportional split. Per-case direct tool/winapp/helper
counts are not core columns: a batch controller must not produce a misleading all-zero
per-case workload table.

Also report module-level execution wall time (the total length of the selected nonoverlapping
Task 1 segments, not reporting gaps) and separate rows for **Preparation,
Cleanup, Diagnostic/shared work, MULTI-CASE and UNASSIGNED** as applicable. Attribute each
direct action once. Case spans can overlap and must not be summed into module wall time.
Subtracting tool wait from wall time does not prove "model thinking time"; that remainder
can include user waits, code authoring, queue idle or uninstrumented activity.

### Required artifacts and report view

`statistics.json` must contain the run ID, counting mode `agent-origin-requests`, source
session IDs/event ranges/cutoff, collection time, module totals, per-case rows, non-case
rows and explicit limitations. Use the following field names for inline rendering:

| JSON field | Required content |
|---|---|
| `RunId`, `CountingMode`, `Coverage` | Current run ID, `agent-origin-requests`, and `complete` / `partial` / `unavailable` |
| `ExecutionSegments` | Ordered `{StartUtc, EndUtc}` boundaries excluding Task 2 |
| `ModuleTotals` | `AgentToolRequests`, `ExecutionLifecycleWallSeconds`, `ToolResponseWaitUnionSeconds`; optional `ReportingSeconds` is separate from execution |
| `AttributionRecords` | One sanitized `{SessionId, ToolCallId, ToolName, StartUtc, CompletionUtc, Phase, CaseId}` record per selected agent request; preserve unknown completion/case as null |
| `Cases` | One `{CaseId, NormalAttempts, DiagnosticAttempts, RecordedDriverSeconds, CaseSpanSeconds, FailedDriverSteps}` row per checklist entry |
| `NonCaseRows` | `{Phase, AgentToolRequests}` for preparation, cleanup, MULTI-CASE or UNASSIGNED when applicable |
| `Limitations` | Explicit source/attribution/measurement gaps |

`FailedDriverSteps` supplies the Driver errors column. For unexecuted or unavailable case
measurements, retain null durations/error metrics, not a fabricated zero-second execution.
Retain start/end boundaries and excluded bookkeeping IDs as additional source metadata.
Legacy attribution rows with multiple direct-action indices for one call are deduplicated
by session/call ID when building the tool distribution; conflicting tool names are rejected.
Omit private argument/output payloads and sensitive command text. The statistics renderer
uses actual tool names, not raw command strings, to build the workload table.

Missing values are JSON `null` with a reason and display as **unavailable**, not `0`.
Zero is valid only when the recorded interval was covered and no matching request exists.
If only some activity can be attributed, label the statistics **partial** and show the
unassigned count. An unavailable statistic does not create a new product FAIL or change
existing case verdicts.

Before publishing the statistics, perform these semantic checks, not just JSON/Markdown
format validation:

- Verify the selected source session and time range against at least one known agent request
  from this run, such as its controller launch `toolCallId`. If that request is missing or
  the total is zero despite known activity, stop publishing the numeric result, diagnose
  parsing/boundaries and emit unavailable values with a concrete reason if unresolved.
- The distinct in-scope tool-start IDs must equal the total attributed agent tool requests,
  including `MULTI-CASE`, preparation and `UNASSIGNED`. Unknown classification goes into
  an explicit residual bucket; it does not disappear. The per-tool distribution must sum
  to the distinct tool-call total, not the count of inner script operations.
- A known controller launch must be retained once in its actual tool type and MULTI-CASE
  attribution even when it has not returned yet. Leave unknown completion
  or per-case duration unavailable. Do not require a completion to count a start.
- If the inline report says a MULTI-CASE launch or unassigned activity was retained, the matching
  JSON rows/records must exist. The report and JSON must describe the same totals, ranges and
  limitations; `Coverage=partial` does not excuse contradictory zero totals.
- Check that recovery after a reporting phase creates a second execution segment, and that
  final judgment/disposition-only events are excluded. A case with only a final BLOCKED
  entry was not executed for zero seconds; its execution duration is unavailable.
- Check the earliest/latest selected timestamps, fractional precision, nonnegative intervals
  and overlap handling. Do not sum per-case spans into wall time or use runtime `success=true`
  as proof of a zero command exit code.

Record the extraction script as a source artifact or execute it through
`Invoke-PtVerificationStep -ScriptFile`. Merely recording a wrapper that calls a mutable,
unarchived statistics script is insufficient to reproduce the calculations.

The **Execution statistics** section is part of `report.md`, not a separate click-through
summary. It begins with the Task 1 boundary/coverage notes and module totals, followed by:

```markdown
## Execution statistics
Execution window: <start> to <cutoff>; reporting/export excluded.
Wall time: <duration>; statistics coverage: <complete/partial/unavailable>.

| Agent tool | Requests |
|---|---:|
| powershell | <n> |
| view | <n> |
| apply_patch | <n> |
| <each other observed tool> | <n> |

| Case | Verdict | Normal / Diagnostic attempts | Driver time (s) | Span (s) | Driver errors |
|---|---|---:|---:|---:|---:|
| <case ID> | <recorded verdict> | <n / n> | <measured/unavailable> | <measured/unavailable> | <n/unavailable> |
```

Use these measured rows to identify the slowest cases, repeated direct requests and
substantial preparation/cleanup overhead in §G. Preserve uncertainty; do not label all
time spent on a failing case as wasted time.

Register `statistics.json` using the existing recorder in a reporting-only **Diagnostic**
attempt before `Complete-PtVerificationRun`; see
[the reporting step](recording-workflow.md#statistics-before-final-sealing).
Do not create a new Cleanup attempt just to attach statistics: that would replace the
latest actual restoration scope. Do not edit a sealed Markdown report afterward.
The fixed exporter includes the registered JSON in the integrity manifest and loads it
for inline rendering; an optional raw-data link is not a substitute for the tables.
Do not append Markdown after sealing. Older archives remain unchanged; do not invent historical
statistics when the source logs/attribution are unavailable.

## §G — Retrospective (self-reflection)

After the run, reflect on the **process** (not the product) so the skill itself gets better over time. **If nothing slowed you down, write exactly one line: `Everything was smooth — no friction encountered.`** Otherwise, list each friction as a row and assign a source + severity.

```markdown
## Retrospective

| # | Friction (what slowed you / what was wrong) | Source | Severity | Cost | Suggested fix |
|---|---|---|---|---|---|
| 1 | <concrete description — what you expected vs what happened> | <one source tag below> | <HIGH/MED/LOW> | <~min wasted · N attempts> | <the doc line / helper function / tool behavior to change> |
```

**Source** — classify each friction into exactly one bucket so the right owner can fix it:

| Source tag | Meaning |
|---|---|
| `SKILL-UNCLEAR` | This skill's `SKILL.md` / `references/pre-flight.md` / module profile guidance was missing, ambiguous, or wrong. |
| `WINAPP-TOOL-BUG` | The `winapp` CLI itself misbehaved (crash, wrong output, flag not honored) — a product defect in the tool. |
| `WINAPP-DOC-UNCLEAR` | `references/winapp-ui-testing.md` was unclear/incorrect about how to use the tool (the tool worked; the docs misled you). |
| `HELPER-FLAW` | A shipped `scripts/*.ps1` had a logic bug, bad default, or wrong assumption. Name the function. |
| `PT-PRODUCT` | A PowerToys behavior/quirk made driving hard (distinct from a product **FAIL** — this is friction, not a checklist failure). |
| `CHECKLIST` | The checklist item itself was wrong/stale/ambiguous (e.g. describes a renamed or removed control). Note: this usually *also* produces a `FAIL (cause: checklist-*)` verdict on the item; log it here too so the checklist owner sees it as a process-improvement signal. |
| `ENVIRONMENT` | RDP/session/desktop/elevation friction not already covered by `references/environment-setup.md`. |

**Severity** — judge by *impact on future agents*, not just yourself:
- **HIGH** — most agents will hit it; blocks progress or wastes >10 min, or you needed a non-obvious workaround.
- **MED** — many agents may hit it; cost a few minutes or 2-3 retries; workaround exists once known.
- **LOW** — edge case or cosmetic; <1 min; noted for completeness.

**Cost** — be concrete: approximate minutes wasted **and** number of attempts (e.g. `~8 min · 3 attempts`). This is the raw signal for prioritizing skill fixes.
Use the execution statistics below to identify expensive cases and repeated agent actions.
Separate measured intervals from estimated wasted time; call counts alone do not establish
whether the cause was the product, driver, reporting or environment.

**Suggested fix** — point at the specific artifact to change: a doc line/section, a helper function name, or a `winapp` behavior to file. Vague reflections ("docs could be clearer") are not actionable — cite the line.

Example:
```markdown
## Retrospective

| # | Friction | Source | Severity | Cost | Suggested fix |
|---|---|---|---|---|---|
| 1 | `winapp ui inspect --depth 7 -w $hwnd` threw "Cannot bind argument" until I moved `-w` after `--depth`. | `WINAPP-TOOL-BUG` | MED | ~6 min · 3 attempts | Already noted in pitfall #8, but the tool should parse flag order — file against winapp. |
| 2 | SKILL.md §2.A says "wait 4s debounce" but PowerRename needed a full `Restart-PtRunner`; the module-owned-file note (pitfall #12) wasn't cross-linked from §2.A. | `SKILL-UNCLEAR` | HIGH | ~12 min · 4 attempts | Add an explicit "shell-ext modules → see pitfall #12" pointer inside §2.A. |
```
