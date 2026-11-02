# Fresh Runner session and exact-input contract

The purpose is experimental independence: can a new Runner use the committed verification materials without
the Author's private knowledge? This is not a claim of OS-level sandboxing or infallible judgment.

## 1. Prepare an execution worktree

The Author works on a new branch based on the freshly fetched published verification WIP selected in
[Step 0](../SKILL.md#0-start-from-the-published-verification-wip), not the old authoring branch or upstream main.
The minimal serial workflow uses that same clean worktree for the Runner, with **all Author edits paused
until it returns**. A new session is mandatory; a new checkout on every iteration is not. Keep Author
notes/raw runs outside this worktree.

Select one committed candidate and verify its clean state:

```powershell
$candidate = git -C $authorWorktree rev-parse HEAD
$runnerWorktree = $authorWorktree
git -C $runnerWorktree status --porcelain
```

For a stronger filesystem separation, optionally use
`git -C $authorWorktree worktree add --detach $runnerWorktree $candidate` with a new inspected path instead.
This still does not isolate conversation/memory by itself.

Preserve existing worktrees and check each exit code. Do not use a dirty Author tree as the Runner's inputs or
change candidate files while it is active. Ignored build outputs are not permission to edit tested materials.
Do not force-remove a dirty Runner worktree; retain unexpected changes as diagnostic evidence.

Create a neutral handoff directory outside the Author's private session/notes. It contains only the brief,
input manifest and necessary task data. It must not itself contribute another `.github\skills` tree.
Put raw observations in a separate run workspace; never commit that workspace wholesale.

## 2. Attest the whole tested input set

Record:

| Field | Meaning |
|---|---|
| Module, run/round ID | Scope and unique execution identity |
| Candidate SHA and Runner worktree | Immutable repository revision and actual cwd |
| Verification base | Published remote/ref and resolved base SHA; not inferred from the current branch name |
| Verification skill canonical path | The intended `.github\skills\powertoys-verification\SKILL.md`, not merely its name |
| Material manifest | Relative path + SHA256 for the skill, profile or explicit absence, checklist, helpers, fixtures and references/assets used |
| Product identity | Scenario/BITS contract, actual executable paths/versions/hashes, relevant commit/tag inclusion |
| Environment/permissions | Host, Runner, module and foreground-fixture integrity; desktop/locale/DPI/display constraints; allowed state changes |
| Scope | Round, full inventory identity/counts and matrix conditions; R1 selects all IDs, R0/R2+ record explicit selections; source mappings and visual references |
| Executable foundations | Versioned helpers/fixtures, private backup/restore plan, mechanical validation receipts and remaining runtime checks |
| Repair/exit policy | Approved root/batch limits and remaining counters; R1 exits by default, R2/later rounds require explicit authorization and selection |
| Artifact locations | Where to write run output and its final archive |
| Effective runtime policy | Existing tool/path permissions, task-authorized scope, model choice if supplied and applicable limits |

Product source/tag and verification base are independent. If the authoring skill is loaded from another
worktree, that supplies guidance only: do not inherit its sibling execution skill, helpers or old templates.
Identify the [round coverage mode](stopping-policy.md#required-round-coverage) explicitly: R0 samples core
mechanisms; R1 includes the full frozen inventory and every required matrix condition; R2+ may be targeted.
Unavailable conditions stay in the inventory. Neither a bounded R0 nor a later subset counts as full R1.
Before dispatching R1, compare its selection/counts with the frozen inventory and reject omitted IDs/conditions.
Before dispatching R2 or later work, verify explicit task authorization and its fixed repair/regression scope;
R1's remaining findings are not authorization. Transfer remaining budget counters neutrally, not Author
hypotheses or private diagnosis transcripts.

For the small verification skill, snapshot/hash its complete tree to avoid missing indirect references.
If another skill/tool supplies an input, add that dependency rather than silently mixing versions.
Hash changes require a new candidate or an explicit invalidated run, not an amended handshake after testing.
The checklist/profile format contracts are Author inputs. If the Runner also reads either contract (including through a
README link), include the exact file/hash as an input dependency; do not supply the Author's private review
notes or assume the verification-skill tree contains a sibling skill's reference file.

Before mutation, the Runner returns a handshake with **actual** cwd, Git SHA/status, runtime/session ID,
resolved skill origin/path/hash, loaded instruction/skill sources and independently observed product identity.
The Author checks it against the manifest. A matching skill name, an echoed expected hash or a normal exit code
does not establish which files were actually loaded.

Make this a **two-turn gate**, not a header the Runner prints while continuing to click:
the first turn performs identity/read-only preflight only and returns. The Author validates it **automatically**,
then sends an execution authorization in the same newly created Runner session. Do not ask the user to approve
this routine handshake or R0 again: their explicit workflow-execution request supplies the task authorization.
A mismatch stops the dispatch; a match proceeds under the effective runtime policy. Use runtime permission
controls where available; a prompt is not a sandbox. This neutral acknowledgment contains no Author coaching.

Also check the Author's [executable foundations](execution-readiness.md). During identity-only preflight,
observe existing processes and record planned fixture requirements; do not create a product state to fill a
missing field. After authorization, verify the newly created fixture's actual identity/integrity before input.
A discovered repairable gap returns to the Author rather than becoming a blanket environment failure.
R0 still performs safe discovery; prioritize known prerequisite gaps within the approved repair allowance.
Do not repeatedly drive a known broken path. Keep unrepaired gaps explicit, continue independent R1 coverage,
and report incomplete readiness without treating those gaps as external exemptions or commands to loop forever.

In Copilot CLI, inspect available sources without running a test:

```powershell
copilot -C $runnerWorktree skill list --json
copilot -C $runnerWorktree instruction list --json
```

These list what that process discovers, not a full proof of a future session's reads. Retain the actual skill
load receipt and helper invocation/source paths too. Compare source hashes and tracked diffs after execution.
Do not treat a helper from the Author's old WIP directory as the same revision.

If an unexpected personal/plugin/additional-directory skill shadows the project skill, stop that dispatch.
Resolve its origin using supported per-session configuration or an explicitly reviewed environment; do not
disable global skills/settings silently. If the runtime cannot guarantee the intended load, mark the attempt
as an input-isolation failure, not product verification.

## 3. Fresh means no inherited conversation

Use a new runtime session for **every** scored iteration:

- No Author conversation/messages, summaries, private scratch files, previous reasoning or predicted verdicts.
- No `/fork`, `--continue`, reused round ID or resumption of the Author/previous round's session.
  Continuing this round's new session from its identity-only handshake into execution is allowed; it has no
  Author conversation or previous test-run history.
- Do not rely on renaming an agent or switching its role prompt within the same conversation.
- Disable optional memory/cross-session retrieval for the Runner where supported; do not let it retrieve Author
  history through session-search tools. Expose only the tools needed for the task.
- Retain required repository/organization instructions. List unavoidable ambient inputs rather than bypassing
  policy or claiming a stronger isolation level than the runtime provides.

An ordinary subagent is acceptable only if its runtime contract actually guarantees fresh context and the
required source selection. "Separate context window" alone does not prove those conditions.
If unavailable, use a fresh standalone CLI/SDK session or return `blocked: session isolation unavailable`.

### Copilot CLI launch shape

Check installed help before applying flags. In CLI 1.0.86, `-C`, `--session-id`, `--name` and `-p` are supported.
Prompt mode leaves memory disabled by default; do not add `--enable-memory`.

The Author constructs `$preflightPermissionArguments` and `$executionPermissionArguments` from the selected
runtime's effective configuration and the already-authorized task. They are **not user-input fields or an
additional approval prerequisite**. Keep the child scope no broader than the task and existing grants; do not
assume an independent CLI process automatically inherits another session's tool approvals.

If existing configuration is sufficient, no additional permission arguments are needed. Otherwise resolve
supported tool/path configuration before dispatch within the existing authorization. Inspect permission help
and actual runtime responses; do not conclude that approval is unavailable merely because these example
variables have not been populated. A genuine request for new authority must still be surfaced.

```powershell
$sessionId = [guid]::NewGuid().ToString()
$launch = @(
    '-C', $runnerWorktree,
    '--session-id', $sessionId,
    '--name', "verify-$module-$round",
    '-p', $preflightBrief,
    '--output-format', 'json',
    '--no-remote', '--no-remote-export'
) + $preflightPermissionArguments
& copilot @launch
```

After automatically validating the identity-only response, continue **only that newly created dispatch session**:

```powershell
$execute = @(
    '-C', $runnerWorktree,
    '--resume', $sessionId,
    '-p', $executionAuthorization,
    '--output-format', 'json',
    '--no-remote', '--no-remote-export'
) + $executionPermissionArguments
& copilot @execute
```

The authorization identifies the accepted handshake/manifest and permitted work, without Author analysis.
The next candidate test uses a different new UUID, not this continuation.

Do not insert `--allow-all`, disable mandatory instructions, or broaden access to evade a real permission
request/denial. Keep three decisions separate: the user authorizes the task, the Author checks input identity,
and the runtime enforces tool permissions. Fresh-session isolation itself does not add a human approval step.

If an actual runtime policy prevents launch/execution, record the exact command/tool, requested authority and
returned error or approval prompt. Report only the affected work as blocked; do not substitute "desktop/runtime
approval unavailable" for this evidence. Respect the denial rather than trying another route around it.

`--session-id` can resume an existing session, so generate a new UUID and verify the returned session really
started for this dispatch. `--add-dir` also loads skills/agents from that directory: do not add the Author's
worktree/session directory. For SDK use, create a new session with no parent message history and record the
equivalent controls; installing an SDK is not a prerequisite of this skill.

Keep model selection at the user's/runtime default unless explicitly specified. Do not start a factory,
fleet or parallel desktop workers. A new conversation is not a sandbox: permissions and ownership checks remain necessary.

## 4. Neutral brief template

Fill this brief with concrete paths/IDs. Do not append "the Author fixed this; it should PASS."

```text
Role: verification Runner, execution only.
Phase: identity-only preflight; do not start product verification in this turn.
Run/round: <id>
Coverage mode: <R0 discovery / R1 full inventory / R2+ targeted regression>
Module: <module>
Working directory and candidate commit: <absolute path>, <sha>
Input manifest: <manifest path and hash>
Verification engine: <canonical SKILL.md path and hash>
Checklist and inventory: <paths, hashes, revision, scenario/assertion counts>
Selection: <ALL inventory IDs and required matrix conditions for R1; explicit IDs for R0/R2+>
Module profile: <path and hash, or explicitly absent for initial discovery>
Executable foundations: <versioned fixture/helper plan, preservation method, validation and runtime checks>
Accepted visual references: <paths and provenance, or none>
Product/BITS target: <identity to independently verify>
Environment and authorized state changes: <scope from the user's workflow request and effective policy>
Input integrity: <host/Runner/module identities and required foreground-fixture level; verify actual tokens>
Coverage: <complete requirements, actual prerequisites and conditional matrix; never remove unavailable IDs>
Privacy: <no private payload exposure; permitted local programmatic preservation and owned-data plan>
Output workspace/archive: <paths>
Resource/stop policy: <existing runtime limits, explicit user ceilings and declared round scope>
Repair allowance: <root: 2 different approaches or 20 minutes; batch: 60 minutes; explicit overrides, batch/root IDs and remaining counters>
Round exit: <R0: return discovery; R1: restore/archive/return; authorized R2: one targeted confirmation then return, no automatic R3>

Return the actual session/cwd/revision/source-loading/BITS handshake and end the preflight turn.
The Author checks this handshake automatically and sends the execution acknowledgment; do not request another
human approval simply to run R0. Until that acknowledgment, no product activation, input injection, recording,
clipboard writes or settings changes. Actual runtime permission requirements still apply.
Use the exact candidate engine, checklist and profile. Do not load the Author's conversation, history or notes.
For a new-profile initial run, discover using the generic engine. For explicit refinement/reuse, use only the
profile pinned in this packet; do not recover an excluded old profile to fill an absent one.
Do not modify tracked checklist/profile/skill/helpers, expectations or product code. Do not commit/push.
The engine's normal profile-maintenance instruction is assigned to the Author for this workflow.
Run-local scripts are allowed, with source snapshots, exact calls, errors and cleanup evidence.
Observe before judging. Preserve every required assertion and distinguish product, checklist, driver and
environment problems. Continue independent eligible work when a conditional check is unavailable.
For R1, process every inventory assertion and matrix condition and actually execute all safely available
independent conditions. Do not stop after a sample, silently narrow scope or count assigned verdicts as execution.
Give concrete evidence for unexecuted external conditions or product dependencies. Driver/observer failures
remain infrastructure gaps. Prioritize traversing the inventory over deeply debugging one case: charge
diagnostic corrections to the supplied allowance, record an exhausted/no-progress root and continue independent
safe conditions. A local repair limit does not cancel the rest of R1. If a task-wide limit stops execution,
archive remaining IDs and report R1 incomplete. Do not retry without a new hypothesis and discriminating observation.
Non-empty clipboard/history is not itself a permission denial or inability: use the supplied tested local
preservation plan without exposing its private payload. Do not improvise unsafe writes if that plan is missing.
Before hotkey judgments, verify actual foreground ownership and compatible integrity; input acceptance alone
does not prove product delivery. Keep unsupported setup as a setup gap, not a product FAIL.
Report normal and special conditions separately. Do not invent a defect in a dependent action that could not
be reached. Missing accepted visual references does not forbid collecting valid candidate observations.
Record and restore all owned mutations; stop dependent actions if restoration is uncertain.
Reserve planned cleanup when a limit is reached; report unresolved recovery instead of attempting an unbounded
repair experiment. At the R1 or authorized R2 exit boundary, restore/archive and return regardless of verdict
colors; do not start another repair batch or round without explicit authorization.
Return the archive, assessed/executed/unprocessed counts, blocker causes, restoration result and round
completion status, not an improved profile or expected PASS narrative.
```

The checklist necessarily supplies expected behavior; excluding the Author's context does not mean withholding
the specification. Supply safe fixtures and known environment facts neutrally. For an explicitly authorized
targeted rerun, provide the selected assertions and current materials, not the preceding agent's answer key.

## 5. Runner output and Author review

Require a durable result containing:

- Actual session/dispatch identity, input provenance and BITS identity.
- Per-assertion observations, verdicts or explicit unexecuted/dependent coverage.
- Full inventory totals, assessed versus actually executed conditions, unprocessed IDs, blockers by cause
  and partial matrix coverage; for R1, the [completion-gate outcome](stopping-policy.md#r1-completion-gate).
- Root/batch diagnostic approaches and time consumed, remaining allowances, stop reasons and deferred work.
- Actual eligibility/matrix conditions, helper/fixture gaps and measured input/environment prerequisites.
- Exact commands, screenshots/recordings, original errors and run-local source.
- Restoration receipts/conflicts, archive validation and post-run material hashes/diff.
- Friction by layer, discovery facts and missing capabilities; visual candidates stay labeled candidates.
- Any departures from the supplied methods or unexpected loaded inputs.

Reject stale/mismatched dispatch results and mutated input materials. Repeated identical delivery is not another
confirmation run. Preserve invalid attempts as diagnostics, but do not count them toward convergence.
Apply the [finite exit policy](stopping-policy.md#finite-exit-policy) independently of quality acceptance:
an unmet gate does not authorize another round. Report unresolved findings and required authority/scope for
follow-up instead of continuing until PASS.
Review raw evidence before accepting a summary; fresh context reduces contamination, not all shared blind spots.
For R1, reconcile every inventory ID and required matrix condition against execution evidence or an explicit
supported limitation. A report that selected only a subset, merely filled rows with BLOCKED, or left unexplained
NOT-OBSERVED conditions cannot establish completion. Apply the
[coverage accounting rules](claims-and-verdicts.md#6-report-and-compare-like-for-like) without changing engine verdicts.
The Author also checks the archived candidate profile against the recorded
[format contract](module-profile-format.md#9-author-review-gate), not a later edited profile or older template.
Keep format conformance, executable readiness and product findings separate. A profile-absent R0 has no
profile-conformance prerequisite, and the Runner must not hot-edit a profile to repair its format.
Apply [claims-and-verdicts.md](claims-and-verdicts.md) when reviewing product attribution, ambiguous legacy
wording, incomplete conditions and comparison denominators. Keep a shared blocker's affected IDs together
so the Author can repair one capability rather than repeatedly documenting the same failure.

If the Runner needs author coaching halfway through, either stop and record that gap, or label the continuation
as **assisted diagnosis**. Do not count it as an unassisted fresh-session confirmation. Commit material changes
before any authorized fresh-session confirmation; needing unassisted evidence does not itself authorize a
further round.
