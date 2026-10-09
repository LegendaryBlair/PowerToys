# winapp CLI version and documentation policy

Use the **latest published stable winapp CLI by default at the start of a new verification
run**, then keep that resolved tool version fixed for the run. A user-specified version or
an explicit reproducibility/Runner input manifest takes precedence over this default.
Tool preparation does not authorize changing the installed PowerToys artifact under test.

## 1. Resolve and prepare the tool before UI execution

1. Run `Get-Command winapp -All` and `winapp --version`. Identify the actual installation
   channel, not just a PATH entry. A WindowsApps execution alias or shell shim is not the
   executable whose contents should be hashed.
2. Resolve the official [latest release](https://github.com/microsoft/winappCli/releases/latest),
   for example with `gh api repos/microsoft/winappCli/releases/latest`. Require `draft=false`
   and `prerelease=false`; record the release tag, URL and check time. "Stable" here names
   the release channel, not a claim that the overall CLI product has left public preview.
   Do not substitute `main`, nightly artifacts or a PR build.
3. If the installed tool is older or missing, update/install it using the existing channel
   and the selected release's README installation guidance (tagged URLs below),
   within the task's authorization and runtime policy. Reuse WinGet, a managed npm install
   or a signed MSIX as appropriate; do not silently add a second conflicting PATH entry.
   Ordinary permitted user-scoped setup is preparation, not another blanket approval gate.
   Elevation, new certificate trust, changes to another user's installation or a real tool
   denial still require the corresponding authority. Never force-close another workflow.
4. For a direct release download, select the correct architecture, check its published
   digest and Microsoft signature/package identity before installation. A failure is an
   explicit setup error, not a reason to disable trust checks or import a development certificate.
5. In a **fresh shell**, confirm the resolved path/package, `winapp --version`, and the
   needed command's `--help` / `--cli-schema`. A successful installer exit or release notice
   alone does not prove the invocation now selects the updated binary.

Do not upgrade while another workflow is using the CLI or while a verification run has
live mutations/cleanup pending. Do not upgrade every installed SDK/application, alter
project dependency manifests, or silently downgrade a deliberately pinned/newer build
merely to satisfy this policy. Resolve the relevant tool setup only.

If release lookup/update is unavailable, record the concrete network, permission or
installation limitation and the actual installed version. Do not call it "latest verified".
Continue independent cases whose required capabilities are present; explicitly block or
use a documented compatible route for affected cases. A pinned/offline exception is not
permission to use syntax unsupported by the installed executable.

## 2. Read the documentation matching the executable

The bundled [UI mechanics reference](winapp-ui-testing.md) contains PowerToys-specific
integration and examples; it is **not a continuously synchronized upstream CLI manual**.
After resolving the tool, read the official documents for its exact release tag:

```text
https://raw.githubusercontent.com/microsoft/winappCli/<release-tag>/README.md
https://raw.githubusercontent.com/microsoft/winappCli/<release-tag>/docs/ui-automation.md
https://raw.githubusercontent.com/microsoft/winappCli/<release-tag>/docs/usage.md
```

Substitute the verified tag, such as `v0.7.1`, rather than treating that example as a
permanent latest version. Read the applicable sections and release notes, especially
changes to selectors, actions, capture and workflow coordination.

- Actual executable help/schema establishes which parameters exist. Matching tagged docs
  explain their semantics. If they disagree, diagnose installation/source selection before
  using the feature; do not invent a flag or assume an unreleased feature is installed.
- PowerToys safety, privacy, ownership and evidence requirements still apply. Upstream
  examples do not authorize broad desktop changes or disclosure of environment values.
- Snapshot the fetched documents and relevant help/schema output with URL/tag, hash and
  retrieval time as run inputs. If unavailable, identify the cached version and limitation.
- Do not rewrite the tracked skill/reference tree during a run to mirror upstream. Refresh
  the external documentation input each run; reconcile stale local examples as a separate
  reviewed skill change. A static example must not override newly verified tool semantics.

## 3. Fix the tool identity for the run

Complete tool setup before initializing the scored execution input set. Retain setup
receipts, including before/after versions, with the run. Record the resolved command path,
actual executable SHA256, package identity where applicable, selected release and docs.
The [recording workflow](recording-workflow.md#initialize-once-before-driving) supports
external document/help snapshots as explicit `Other` inputs.

Once execution begins, do not auto-upgrade between cases or on `-Resume`. Check the recorded
version/path/package identity again on resume and before final export; compare the actual
binary hash where accessible. If the alias/package changed, stop dependent execution and
report tool-input drift. Do not merge results across tool versions as one unchanged baseline.
Switching versions requires an explicitly identified new run/input set after safe cleanup.

This is a per-run preparation policy, not a background updater or a new execution framework.
