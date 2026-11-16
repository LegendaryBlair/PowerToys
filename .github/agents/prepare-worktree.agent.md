---
description: 'Prepares an exact PowerToys PR revision in an isolated worktree, builds required projects, and records output provenance.'
name: 'PrepareWorktree'
tools: ['read', 'edit', 'search', 'execute']
infer: true
---

# PrepareWorktree

Prepare source and build outputs only. Do not launch PowerToys, close installed instances,
register packages or shell extensions, run behavioral tests, or publish to GitHub.
Deployment, verification and restoration belong to the caller.

Use the [build guidelines](../../tools/build/BUILD-GUIDELINES.md) and the **tested revision's**
build scripts. This repository definition owns PR worktree/build preparation; callers reference
it rather than maintaining another build recipe.

## Inputs and result

Accept the PR number, existing repository path, reviewed commit SHA, new worktree path,
platform/configuration, required product/test projects and an external evidence directory.
Resolve missing revision/project details from the PR and source. Default to the host-supported
architecture and Release when not specified; record the choice. Honor the caller's unattended
policy and existing permissions.

Return the worktree path and a build summary in the evidence directory, outside the worktree:
reviewed/tested SHA, source status, toolchain, project/configuration, exact commands and exit codes,
log paths, required outputs and their hashes, plus any blocked dependencies. Preparation is not
proof that a product behavior passed. Retain the summary and logs even when a build fails.

## 1. Resolve source and create the worktree

- Inspect the caller's repository, remotes, status and worktree list. Do not switch its branch,
  reset/stash changes, or adopt another run's worktree.
- Read PR metadata/diff with `gh` and explicit `--repo`. For an open PR, pin the reviewed head;
  for merged-but-unreleased validation, use the caller's reviewed merge/integration revision.
  Do not merge the latest base into the target or equate merge conflicts with an unbuildable head.
- Prefer a short, space-free worktree root. A prior summary file alone does not establish reusable
  outputs: reuse only with explicit caller authorization and matching ownership, revision,
  configuration, clean source and verified output hashes. Otherwise create a fresh worktree.

For an open PR, after resolving `$repo`, `$worktree`, `$prNumber` and `$headSha`:

```powershell
if (-not [IO.Path]::IsPathFullyQualified($repo) -or
    -not [IO.Path]::IsPathFullyQualified($worktree) -or
    (Test-Path -LiteralPath $worktree) -or $headSha -notmatch '^[0-9a-fA-F]{40}$') {
    throw 'Supply an existing repository, a new absolute worktree path and the reviewed commit.'
}
git -C $repo fetch https://github.com/microsoft/PowerToys.git "pull/$prNumber/head"
if ($LASTEXITCODE -ne 0) { throw 'PR fetch failed.' }
$fetchedSha = git -C $repo rev-parse FETCH_HEAD
if ($LASTEXITCODE -ne 0 -or $fetchedSha -cne $headSha) { throw 'PR head changed; review the new revision first.' }
git -C $repo worktree add --detach $worktree $headSha
if ($LASTEXITCODE -ne 0) { throw 'Worktree creation failed.' }
git -C $worktree submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw 'Submodule initialization failed.' }
```

For an explicitly selected merge/integration revision, fetch and verify that exact commit instead
of substituting the PR head, then use the same detached-worktree boundary.

## 2. Establish the build boundary

Read `global.json`, project dependencies and the revision's build wrappers before executing them.
Use the pinned SDK and required Visual Studio/MSVC capabilities, not a silently substituted SDK.
Restore/install missing dependencies only when required by a failed prerequisite/build or a changed
manifest, within the caller's permissions.

Inspect restore/build/post-build targets for machine side effects. For example,
`ImageResizerExt.vcxproj` can enable `RegisterOutput`. Use a supported no-registration build option
or return the affected build as blocked; a worktree does not isolate COM/MSIX or user settings.
Do not run the full environment-setup or installer scripts as a generic repair.

Resolve the minimum coherent project set from the caller's runtime requirements and the diff.
For a Runner-based deployment, include Runner, Settings, affected modules and required dependencies.
Include module-interface projects and explicitly requested test projects. Do not build every project
in the solution or omit a required runtime dependency merely because its source is unchanged.

### Long-path handling

Read and record `LongPathsEnabled` from the 64-bit registry view at
`HKLM\SYSTEM\CurrentControlSet\Control\FileSystem` before the first build.

- If it is `1`, leave the repository prerequisite check enabled.
- If it is disabled or absent and machine setup is not authorized, use the documented
  **per-build** `/p:SkipLongPathsCheck=true` fallback with the short worktree path. This is not a
  machine-policy change and does not enable Windows long-path support. Do not stop at `PTLONGPATH`
  without attempting this supported local-build route.
- If the read is denied, record it as unknown rather than claiming the setting is disabled.
  The same per-build fallback can be used if the caller permits it.
- Do not change the registry, reboot, or suppress actual path-length/build failures. An explicit
  caller prohibition on the fallback takes precedence; block only dependent builds in that case.

Verify argument forwarding in the tested revision. The current `build-essentials.ps1` accepts
platform/configuration but does **not** forward arbitrary MSBuild properties. Appending the flag
to `build-essentials.cmd` is insufficient. Use the supported targeted `build.ps1 -ExtraArgs` route
below for Runner and Settings as well as modules when the essentials wrapper cannot carry it.

## 3. Restore and build the required projects

Use one build terminal with the same explicit platform/configuration throughout.
Set `$longPathsEnabled` to the observed registry value (`$null` if unknown), and
`$projectDirectories` to the ordered required project directories, including essentials and
dependencies. Apply any reviewed no-registration properties to `$buildArgs` too.
Check the revision's wrappers: use explicit restore targets for individual projects rather than
assuming `-RestoreOnly` works for every wrapper version.

```powershell
$buildArgs = @("/p:SolutionDir=$worktree\")
if ($longPathsEnabled -ne 1) {
    $buildArgs += '/p:SkipLongPathsCheck=true'
}

foreach ($projectDirectory in $projectDirectories) {
    Set-Location -LiteralPath $projectDirectory
    & "$worktree\tools\build\build.ps1" -Path $projectDirectory `
        -Platform $platform -Configuration $configuration `
        -ExtraArgs ($buildArgs + @('/t:Restore', '/p:RestorePackagesConfig=true'))
    if ($LASTEXITCODE -ne 0) { throw 'Project restore failed; retain and inspect its logs.' }

    & "$worktree\tools\build\build.ps1" -Path $projectDirectory `
        -Platform $platform -Configuration $configuration -ExtraArgs $buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'Project build failed; retain and inspect its logs.' }
}
```

Resolve the actual project files before invoking the wrapper; some versions exit zero when no
project is found. Check the printed MSBuild invocation contains the intended properties.
Use Visual Studio MSBuild through the repository wrappers, not `dotnet build`/`dotnet test`.

On failure, read the errors log and preserve the original failure before a justified retry.
Determine log locations from that revision's wrapper/output; versions differ between project-local
logs and `artifacts\logs`. Do not assume one layout or rebuild solely to find a log.
If broad solution restore fails in unrelated projects, prefer scoped restore of the required graph.
An unresolved prerequisite blocks its dependent projects, not independent preparations.

## 4. Verify outputs and hand back

Require exit zero, evidence that the intended targets ran, and expected fresh outputs for each
required project. Record paths and hashes of executables, managed/native dependencies and relevant
resources; never adopt installed binaries or stale outputs as the target build.

Record source status again and explain any generated/untracked files. Copy build logs and the
summary to the caller's evidence directory. Return successful and blocked components separately,
with the exact tested revision and long-path decision. Do not clean up the worktree or start
deployment unless separately requested.
