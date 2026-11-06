# Execution contract: one agent by default

The current agent authors and executes sequentially: **R0 -> material revisions -> full R1 -> exit**.
Author and executor are roles, not separate sessions. A fresh Runner, child CLI process, neutral handoff,
identity-only turn or acknowledgment is **not a default prerequisite**. Do not construct an orchestrator
to follow this workflow. The PowerToys runner (`PowerToys.exe`) is a product process, not an AI worker.

An independent verification agent is optional; use it only under the explicit request described below.
Same-agent confirmation can establish observed behavior and coverage, but not fresh-session reproducibility.

## 1. Select and record the actual inputs

Use the module worktree selected in [Step 0](../SKILL.md#0-start-from-the-published-verification-wip).
Preserve existing worktrees and unrelated changes. Reuse an existing task's module worktree rather than
creating another one because the round or execution role changed.

Record the following through the candidate engine's existing input/recording APIs:

| Input | Required identity |
|---|---|
| Material revision | Actual worktree, candidate commit/status, verification base and sources used |
| Execution engine | Candidate skill path and source snapshots, not the Author host's sibling engine |
| Coverage | Checklist/inventory IDs, assertion conditions, counts and round selection |
| Product/tool | Scenario/BITS, actual executable versions/paths/hashes and applicable tool documentation |
| Ownership | Affected files/windows/processes, private baselines and paired cleanup |
| Runtime | Actual session, relevant integrity/input conditions and effective tool/path permissions |
| Limits | Existing per-root counters, any explicit user/runtime limits and authorized round exit; no default cumulative cap |

Use `Get-PtVerificationInputs` and the recorder's source snapshots; declare additional references, fixtures
and assets actually used. Do not replace these with expected hashes or Git HEAD alone. Do not add a separate
duplicate whole-tree attestation/handshake service before the normal recorder can start.
Record authoring guidance separately from execution-engine inputs. Read the actual candidate files rather
than assuming a previously loaded skill has the same contents.

## 2. Execute finite actions directly

Use the selected `powertoys-verification` engine in the current agent. Follow its preflight, recorder,
resource/cleanup and archive contracts. Keep one live driver on the shared desktop.

- Establish actual prerequisites, then execute the authorized action directly; no Author-to-Runner round trip.
- Call identity/integrity guards before effects. Check input desktop and exact foreground for input delivery;
  do not impose keyboard-input prerequisites on independent read-only or supported UIA-only operations.
- Prefer short reviewable probes and finite scripts that compose the existing helpers. Keep related stateful
  actions in one bounded invocation with `try/finally` restoration. No queues executing unspecified future code.
- Tool calls may use fresh shell processes. Persist needed metadata with run/candidate identity; use the
  recorder's documented reopen API between completed attempts, never reconstruct live handles.
- Do not hot-edit frozen materials during execution. Restore affected state and close attempts before a
  formal revision. Record/checkpoint the new candidate and its inputs; a new candidate does not require
  another agent or reset diagnostic/repair allowances.
- Record original errors and raw observations. Review against the checklist, not remembered PASS labels.
  A successful command, prepared fixture or report row is not proof of product execution.

R0 discovers representative core mechanisms and verifies restoration. Revise materials from that evidence,
then run **all R1 inventory items and required conditions** as specified by the
[completion gate](stopping-policy.md#r1-completion-gate). Continue independent safe conditions when one is
unavailable. Restore/archive and exit after R1; later rounds need explicit authorization.

## 3. Preserve permissions, evidence and reporting

Task authorization and tool approval remain different. Switching execution roles or adopting this simpler
workflow does not clear an existing denial or authorize replaying its effect through a parent agent, another
session or a wrapper. Retain the exact operation/reason, honor effective policy and continue only genuinely
independent permitted work. Do not broaden grants, disable controls or infer authority from autopilot.

Keep private payloads out of model context and public evidence. Use authorized local preservation and verified
restoration; do not overwrite unexplained concurrent changes. Keep sealed reports immutable.

After execution and cleanup, collect statistics from the current executing session's exact log or captured
stream, limited to the run's fixed interval and tool/case metadata. Do not enumerate other sessions, import
their conversations or publish raw private payloads. Runtime access limits still apply. If statistics are
unavailable, record the reason and null metrics; do not invent zeros or make this a product-execution gate.

Return actual input identities, scoped observations, assessed/executed/unprocessed counts, remaining
conditions and causes, restoration receipts, repair accounting and archive paths. Separate R1 completion,
profile acceptance and product signoff. No new verdict taxonomy or reporting framework is needed.

## 4. Optional independent verification

Only an explicit request for independent/fresh-session verification selects this mode. It is not an implicit
requirement of R0, R1, a profile update or a later repair. If unavailable, report only the requested
independence claim as unestablished; do not retroactively invalidate otherwise valid same-agent evidence.

Use a fresh session with the committed candidate, neutral checklist/scope, known fixture/restoration plan
and declared runtime permissions. Do not pass Author reasoning, previous answer labels, excluded profiles
or private history. Verify actual input origins and the returned session identity. Keep models at the
user/runtime default unless specified. Check current CLI/SDK documentation before constructing launch flags;
do not infer child permissions from the parent's permissions or use unrestricted approvals as a shortcut.

Run serially on the shared desktop. Preserve the same coverage, evidence, cleanup and repair limits. Label
coached continuations as assisted diagnosis, not independent confirmation. A request for independence does
not itself authorize another test round, additional investment or a reset of earlier failures.
