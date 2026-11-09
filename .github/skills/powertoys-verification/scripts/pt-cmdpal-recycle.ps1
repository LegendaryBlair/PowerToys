# Retained names reject old callers before any product access. Use scoped shared UIA/input
# operations; recovery requires a separate identity-checked preservation and lifecycle plan.

function Reset-CmdPalAppX {
    throw [NotSupportedException]::new('Reset-CmdPalAppX is retired: automatic process termination and package relaunch are not supported. Use an explicit authorized lifecycle plan.')
}

function Reset-CmdPalToHome {
    throw [NotSupportedException]::new('Reset-CmdPalToHome is retired: automatic navigation cannot preserve borrowed palette state. Observe the current page and invoke an explicit scoped action.')
}

function Test-CmdPalDegraded {
    throw [NotSupportedException]::new('Test-CmdPalDegraded is retired: diagnostic queries and node counts do not establish process health. Record current observations without mutating or recovering the app.')
}

function Invoke-CmdPalQuery {
    param([string]$Query, [int]$WaitMs = 800)
    throw [NotSupportedException]::new('Invoke-CmdPalQuery is retired: use an explicit scoped UIA or guarded input action and independent result observation. No automatic navigation, recovery or retry is performed.')
}
