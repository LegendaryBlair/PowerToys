# Shortcut Guide entry transitions

Load `scripts\pt-shortcut-guide-entrypoints.ps1`. The checklist still defines the
assertions; these helpers only drive or observe the actual destination. Use recorded
attempts and include the helpers in the run's input snapshots.

## Quick Access

After changing SG enablement through the lifecycle helper, distinguish native HWND
existence from completion of SG startup. The resident overlay initially activates and
hides; summoning Quick Access during that sequence can let startup steal its foreground.
For a newly enabled SG process, call:

```powershell
$guide = Get-PtWindowIdentity (Get-PtShortcutGuideHost).Hwnd
$initialized = Wait-PtShortcutGuideInitialized -GuideTarget $guide
```

This checks the current process's timestamped `activation-event listener started`
receipt and hidden native window. It does not signal SG, restart it or wait an arbitrary
fixed number of seconds. Log reads share access with the writer; file modification times
are not a readiness signal. The parser rejects receipts older than the current process.
If the supported build does not expose this receipt, preserve the timeout instead of
pretending event existence proves consumer readiness.

Signal the runner's `Local\PowerToysQuickAccess_<RunnerPid>_Show` event once, using the
exact running instance. Resolve its real `PowerToys.QuickAccess.exe` window identity,
not an unrelated Settings window. Then:

```powershell
Wait-PtShortcutGuideQuickAccess -QuickAccessTarget $qa -Enabled $enabled
$capture = Save-PtSgEntryCapture -Attempt $attempt -Name quick-access `
    -Probe { Get-PtSgQuickAccessState $qa } `
    -Ready { param($state) Test-PtSgQuickAccessReady $state $enabled }
```

Readiness requires a non-minimized, uncloaked foreground window with observed controls
and the requested tile availability. `WS_VISIBLE` alone is insufficient: Quick Access
keeps its hidden window visible to Win32 while DWM-cloaked. The state must match on two
consecutive observations before capture.

Invoke the actual enabled tile once and observe the resulting full guide. Repeat the
enabled/disabled/re-enabled variants independently. Do not use SG's own named event to
claim that the Quick Access entry worked.

## Settings rail action

```powershell
$landing = Invoke-PtShortcutGuideSettings -Session $guideSession -SettingsTarget $settings
```

The helper clicks the uniquely resolved visible Settings rail item. The shipped rail
handles a mouse `Tapped` action; a UIA Invoke that only selects an item is not proof of
that action. After clicking, the helper only observes: the exact existing Settings HWND
must be foreground with its SG page selected. Guide visibility is retained as an observation,
not an extra close assertion added to L67. No foreground force
or Settings deep link is allowed to manufacture this result.

Use the same landing-state predicate for a screenshot. A previously selected SG page in
a background Settings window does not satisfy navigation.

The live acceptance driver may use `PowerToys.exe --open-settings=ShortcutGuide` to
arrange Settings controls when their navigation group is collapsed. That is setup only,
never the rail-action assertion. Avoid sending another deep link when the desired
Settings page is already foreground.

## Capture and cleanup

`Save-PtSgEntryCapture` repeats only read-only observation/capture within one timeout.
It never repeats the launch/click. Each rejected capture and sidecar is retained as
non-passing Evidence; only the final unchanged, ready capture is returned as Screenshot.
Other observer/IO/identity errors propagate. Timeout evidence includes actual foreground,
cloak and control states rather than an unexplained unavailable result.

Capture original Settings page and navigation-group expansion, window placement, foreground/pointer, enablement and
module/manifest files before mutation. Restore every resource even if another restoration
fails. SG enable/disable may replace its PID; do not claim old process/cache identity.

## Scoped acceptance and diagnosis

```powershell
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtShortcutGuideEntryContracts.ps1" -Workspace <new-folder>
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtShortcutGuideEntryPoints.ps1" `
    -Workspace <new-folder> -SettingsHwnd <existing-settings> -QuickAccessHwnd <actual-quick-access> `
    -ForegroundHwnd <stable-normal-app>
pwsh -NoProfile -File "$skill\scripts\tests\Test-PtShortcutGuideActivation.ps1" `
    -Workspace <new-folder> -ForegroundHwnd <stable-normal-app> -Iterations 2
```

The activation diagnostic compares one-shot NamedEvent/Chord with native-only/UIA
observation. It samples visibility, foreground and held control keys without input or
focus changes after activation, then closes its surface and restores the desktop.
Successful samples do not erase previous early-dismissal failures or establish their
cause. The entry acceptance's custom-chord check does not cover Settings close/reopen,
representative-module rows or a full Runner restart from SG-BINDINGS.
