# Pre-flight checks, bootstrap, and state hygiene

This doc covers the **agent-runtime** environment probing and lifecycle hooks. Read alongside `SKILL.md` (the playbook) and `references/environment-setup.md` (one-time user env prep).

## Pre-flight checks (do these first)

1. **Admin check — skip admin-required coverage by default when not elevated.** Run `Test-PtAdmin` and record the result. If it returns `False`, skip `[ADMIN: YES]` items and continue all `[ADMIN: NO]` items. For `[ADMIN: COND]`, run the non-admin portions and skip only the variants that require elevation. Do not abort the module, request additional authorization to skip, or attempt elevation just to run those checks.

   Retain every item in the inventory. Record each skipped check as `BLOCKED` with `BLK-ENV (requires elevation; current session is not elevated)` and the `Test-PtAdmin=False` evidence. For a conditional item, preserve the non-admin results and identify the skipped variants; if any required coverage remains skipped, the item cannot be a PASS. Do not claim full sign-off with skipped coverage. This known prerequisite skip does not require trying privileged entry-paths.

2. **PT runner present** — `Test-PtRunnerAdmin` should show the runner exists. If it doesn't exist, start PowerToys (`Start-Process "$env:LOCALAPPDATA\PowerToys\PowerToys.exe"`).

3. **Module installed** — `Get-PtModuleSettings -ModuleDir <ModuleDir>` (or `Get-CmdPalSettings` for CmdPal) returns non-null.

4. **Interactive-desktop availability + session attachment** — the single most common cause of false-BLOCKED reports is a session mismatch where the agent runs in an elevated **non-console session** (e.g. RDP that's been disconnected/minimized, fast user switching, run-as-different-user, or scheduled-task-with-highest-privilege). In that scenario `Test-PtAdmin=True` but `GetForegroundWindow()=0` and `SendInput` returns `ERROR_ACCESS_DENIED (5)` — input injection cannot reach the active desktop.

   ```powershell
   # Sessions
   $agentSession   = [Diagnostics.Process]::GetCurrentProcess().SessionId
   $consoleSession = (Get-Process explorer -EA SilentlyContinue | Select-Object -First 1).SessionId
   "Agent session=$agentSession  Console explorer session=$consoleSession"

   # Foreground + Shell COM probe (use scripts/pt-session-diagnose.ps1 for the full version)
   Add-Type 'using System; using System.Runtime.InteropServices; public class FG4 { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); }'
   $hasFg = $false
   for ($i = 0; $i -lt 5; $i++) { if ([FG4]::GetForegroundWindow() -ne [IntPtr]::Zero) { $hasFg=$true; break }; Start-Sleep -Milliseconds 200 }
   $shellOk = $false
   try { $shellOk = (@((New-Object -ComObject Shell.Application).Windows()).Count -ge 0) } catch {}
   "Interactive desktop: ForegroundOk=$hasFg  ShellComOk=$shellOk"

   if (-not $hasFg -and $agentSession -ne $consoleSession) {
       Write-Host "===========================================================" -ForegroundColor Red
       Write-Host "NON-INTERACTIVE SESSION DETECTED" -ForegroundColor Red
       Write-Host "Agent is in Session $agentSession but the active console is Session $consoleSession." -ForegroundColor Red
       Write-Host "SendInput, global hotkeys, and arrow-key navigation will NOT work here." -ForegroundColor Red
       Write-Host "Items requiring input injection will be marked BLK-ENV up-front." -ForegroundColor Red
       Write-Host "Mitigation: see references/environment-setup.md, or relaunch in console session:" -ForegroundColor Yellow
       Write-Host "  psexec -accepteula -h -i $consoleSession -s pwsh.exe" -ForegroundColor Yellow
       Write-Host "===========================================================" -ForegroundColor Red
       # Continue verification — schema/UIA/CLI-based tests still produce real evidence
   }
   ```

   **Key distinction** (all rows assume `Admin=True`):
   - **ForegroundOk + ShellComOk** → Everything works — interactive elevated session.
   - **ShellComOk only (ForegroundOk false)** → Non-interactive (e.g. Session ≠ console, RDP minimized, screen locked, screensaver). Only schema / UIA-invoke / CLI / Named-Event tests work. Mark input-injection items as `BLK-ENV` and **cite `references/environment-setup.md` in the report** so the user can fix env and re-run.
   - **Neither (ShellComOk false)** → Session 0 / service context — even Shell COM fails. Very few tests possible.

5. **Discipline: try AT LEAST 2 distinct entry-paths before marking a drivable item BLOCKED.** The default missing-elevation skips in check 1 are exempt; do not attempt privileged operations to satisfy this rule. For Peek/FZ/Workspaces/Image Resizer/PowerRename/File Locksmith specifically, the obvious entry-path is the global hotkey but Shell.Application COM driving Explorer also works — see per-module profiles under `references/modules/`. Marking BLOCKED after trying only the CLI launch (a common trap) hides easily-PASS-able items in an interactive session.

6. **Match each required child to an observer before mutation.** Identify UIA, pixels, time-series/video,
   speech, process or persistence evidence as appropriate. Record an unavailable observer as a specific
   coverage limitation; do not spend repeated static captures trying to prove animation, first-frame
   flashes or complete speech. Immediately check the first capture for occlusion and missing landmarks.

7. **Verify rollback capability, not just backup existence.** Identify every affected resource, ownership,
   integrity level, restore operation and comparison. On a shared non-admin desktop, do not use Show
   Desktop or equivalent broad mutations if any affected user/elevated window cannot safely be restored.
   Block that variant or use an already authorized disposable environment; never close user windows
   or expand privileges to simplify fixtures. Capture page/tab/IME state when it will be changed.

## One run, bounded work, incremental review

- Keep one assessment run; use local reopen/correction for observer mistakes rather than creating a
  replacement full run. Preserve valid failures and all original evidence.
- Review 3-5 related items at a time, before broad state changes. Record raw data first, inspect
  capture quality and exact saved values (including every shortcut modifier), then commit judgments.
  Use `Get-PtVerificationReview`, not repeated full evidence validation, to locate pending reviews.
- Use the [operation boundary](operation-boundaries.md) for recorded execution and cleanup.
  Calls need no operation key, and old labels/policies never control later execution.
  Do not use failure counters or an unrelated recording error to mark other cases unavailable.
  No automatic retry is added. Keep per-call timeouts, target/input guards and explicit
  restoration. For interrupted or untrustworthily recorded execution, inspect and recover
  the actual affected resources before requesting a new invocation; do not replay the old gesture.
- If a shared host disappears, stop dependent driving. Diagnose the originating transition once;
  recover explicitly as Diagnostic. Start later independent Normal cases only after
  readiness is demonstrated. If recovery fails, reference the same obstacle instead of repeated waits.
- Aim for approximately 30 minutes of eligible driving on a prepared module. At that point report
  achieved coverage, recurring obstacles and remaining work; stop infrastructure debugging rather than
  silently extending it for hours. This is not permission to omit inventory, change criteria or abandon
  restoration, nor a hard stop for independent eligible cases. Account separately for driving,
  review, cleanup and archive time, and report their total.

## Bootstrap (paste at start of your verification script)

Use PowerShell 7. Prepare the explicit item/subassertion inventory and actual source-input
list from [recording-workflow.md](recording-workflow.md) before any UI discovery.
Do not create a report generator or append report Markdown during driving.
The optional [thin run template](../templates/verification-run.ps1) owns the common lifecycle;
`Invoke-PtVerificationCase` handles per-case attempts without hand-built or serialized handles.

```powershell
$skill = '<this skill folder>'   # the folder containing SKILL.md
Get-ChildItem "$skill\scripts" -Filter '*.ps1' |
    Where-Object Name -ne 'pt-session-diagnose.ps1' | ForEach-Object { . $_.FullName }

$workspace = "$env:TEMP\verify-<Module>-$(Get-Date -Format yyyyMMdd-HHmmss)"
$run = New-PtVerificationRun -Workspace $workspace -Module $module -Bits $bits `
    -Scenario $scenario -Items $items -Inputs $inputs
$preflight = Start-PtVerificationAttempt -Run $run -Context Preflight `
    -Kind Normal -Name 'Environment probes' -Activate
Invoke-PtVerificationStep -Attempt $preflight -Name 'Session and elevation' `
    -Command "& '$skill\scripts\pt-session-diagnose.ps1'; Test-PtAdmin; Test-PtRunnerAdmin" `
    -ArgumentList @($skill) -Action {
        param($skillRoot)
        & "$skillRoot\scripts\pt-session-diagnose.ps1"
        Test-PtAdmin
        Test-PtRunnerAdmin
    }
Stop-PtVerificationAttempt $preflight -Reason 'Prerequisites recorded'

# Record the other prerequisites and subsequent operations in explicit attempts.
# Invoke-PtWinApp records internal discovery/probe commands automatically while active.
```

## State hygiene (CRITICAL — always restore)

Wrap any settings/registry mutation in try/finally:

Prefer the [paired snapshot helpers](helper-workflow.md#pair-snapshots-with-restoration-before-changing-state).
Prepare and persist capture/restore pairs before mutation, including original absence. Native
window placement is not a backup of application page/tab/IME state. The scenario's UI-only
mutation contract still applies; do not overwrite unrelated state.

```powershell
$bk = Get-PtFileSnapshot -Path $explicitOwnedSettingsPath
# Persist the snapshot before the authorized mutation.
try {
    # Drive the documented user flow and collect observations.
} finally {
    Restore-PtFileSnapshot $bk
    # Register the comparison as Restoration evidence; do not infer it from exit code.
}
```

Close only tracked test-owned windows/tabs, not shared host processes. Restore only the specific
files/registry values the case owned; never remove whole policy trees as a cleanup shortcut.

## Final wrap-up (after incremental item review)

1. **Run state-hygiene cleanup** in a Normal Cleanup recording context for everything not restored
   per-item. Register the baseline comparisons as Restoration evidence; a successful command is
   not proof of restored state. Record every required subassertion, including NOT-OBSERVED parts
   of failed items, and complete the inventory without promoting diagnostic recovery to PASS.
2. **Finalize using the fixed exporter**, with the actual §G retrospective:
   ```powershell
   $export = Complete-PtVerificationRun -Run $run -Retrospective $frictionRows
   # Use -NoFriction instead only when explicitly justified.
   Test-PtVerificationArchive -Workspace $workspace
   ```
   The exporter generates compact `report.md`, complete `details.md` and machine-readable results,
   and rejects missing/changed evidence. Historical cleanup failures and the latest restoration
   receipts are shown separately; the overall signoff gate remains conservative.
   Use `Export-PtVerificationReport` for an interrupted/partial run; do not erase its failed steps.
3. **Move the workspace to the sign-off archive**, only after validation succeeds:
   ```powershell
   $signoff = "$env:OneDrive\PowerToys\Module-Signoff"
   New-Item -ItemType Directory -Path $signoff -Force | Out-Null
   $final = Join-Path $signoff (Split-Path $workspace -Leaf)
   if (Test-Path -LiteralPath $final) { throw 'Archive already exists; do not merge or overwrite.' }
   Move-Item -LiteralPath $workspace -Destination $final -ErrorAction Stop
   Test-PtVerificationArchive -Workspace $final
   $report = Join-Path $final (Split-Path $export.Report -Leaf)
   ```
   Relative evidence paths remain valid after the move.
4. **Print the FINAL report path** under `Module-Signoff`, not the temporary path.

## Hard rules

- **Never silently send keys via SendInput** without a foreground guard. Prefer `-Hwnd <exact-window>`
  or `Send-PtChord -Hwnd`; `-AppId` alone cannot distinguish multiple windows of one process.
- **Try at least 2 distinct entry-paths from the drive-stack before marking BLOCKED** (SKILL.md §2), except for the default missing-elevation skips in pre-flight check 1. Always name the specific obstacle and retain the skipped coverage in the report.
- **Never assume any external repo is cloned locally.** The helpers under `scripts/` are self-contained. Use `Test-Path` guards before referencing any external path.
- **Never invent test steps for a `[CLARITY: VAGUE-*]` item** — mark it **FAIL (cause: checklist-ambiguous)** and quote the original wording so the user can fix the checklist. The checklist is test code; an undefinable test is a broken test.
- **Always restore state** before exiting (even on error). State hygiene wraps every mutation in try/finally.
- **Separate the two FAIL causes**: *product* FAILs are bugs to file; *checklist* FAILs (stale feature or ambiguous spec) are items to rewrite/prune. If a large share of a module's items are checklist-FAILs, the checklist needs an overhaul before re-verifying — don't punt drivable items into a FAIL.
- **Never treat failure counters as proof that other cases cannot run.** Record the actual
  failed operation and affected prerequisites, preserve its error, and continue independent
  coverage when safe. Missing execution records and interrupted gestures are not ordinary
  completed failures: restore owned state and retain those evidence gaps.
