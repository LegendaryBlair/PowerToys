#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-capture-contracts-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-owned-capture.ps1"
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$script:target=[pscustomobject]@{hwnd=1L;processId=10;processStartTicks=100L;className='Target'}
$script:background=[pscustomobject]@{hwnd=2L;processId=10;processStartTicks=100L;className='Background'}
$script:foreign=[pscustomobject]@{hwnd=3L;processId=20;processStartTicks=200L;className='XamlExplorerHostIslandWindow'}
$script:records=@($target,$background)|ForEach-Object {[pscustomobject]@{Identity=$_;Ownership='Owned';Closed=$false}}
$script:rect=[pscustomobject]@{Left=0;Top=0;Right=500;Bottom=500}
$script:order=@($target,$background,$foreign)
$script:cloaked=@()
$script:style=0L
$script:captures=0
$script:lateForeign=$false
function Require($Condition,$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){
    try{& $Action|Out-Null}catch{if($_.Exception.Message -notmatch $Message){throw};return}
    throw "Expected rejection: $Message"
}
function Get-PtActiveResourceSession {[pscustomobject]@{Windows=$script:records}}
function Assert-PtResourceSession {param($Session)}
function Assert-PtWindowIdentity {param($Identity)}
function Test-PtWindowCloaked {param($Hwnd) $Hwnd -in $script:cloaked}
function Get-PtNativeWindow {
    param([switch]$Visible)
    foreach($identity in $script:order){
        [pscustomobject]@{Hwnd=$identity.hwnd;ProcessId=$identity.processId;ClassName=$identity.className
            Rect=$script:rect;Visible=$true;Minimized=$false}
    }
}
function Get-PtCaptureWindowBounds {
    param($WindowIdentity)
    [pscustomobject]@{Left=100;Top=100;Width=200;Height=150}
}
function Get-PtCaptureBackgroundInfo {
    param($Identity)
    [pscustomobject]@{Window=[pscustomobject]@{Visible=$true;Minimized=$false};Client=$script:rect;ExtendedStyle=$script:style}
}
function Save-PtPassiveScreenshot {
    param($Path,$WindowIdentity,$Region,$Observe)
    $script:captures++
    $script:privateImage=$Path
    $before=& $Observe
    [IO.File]::WriteAllText($Path,'synthetic capture bytes')
    if($script:lateForeign){$script:order=@($script:foreign,$script:target,$script:background)}
    $after=& $Observe
    if((ConvertTo-Json $before -Depth 20 -Compress) -cne (ConvertTo-Json $after -Depth 20 -Compress)){throw 'Capture scene changed'}
    [pscustomobject]@{before=$before;after=$after;path=$Path}
}
$options=@{WindowIdentity=@($target);OpaqueBackgroundIdentity=$background}
$groups=[Collections.Generic.List[string]]::new()
$script:observerCalls=0
Save-PtOwnedScreenshot @options -Path "$Workspace\safe.png" -Observe {$script:observerCalls++;'stable'}|Out-Null
Require ($script:captures -eq 1 -and $script:observerCalls -eq 2) 'Caller observation was lost or recursively invoked'
Require ((Get-Content "$Workspace\safe.png.state.json" -Raw|ConvertFrom-Json).path -eq "$Workspace\safe.png") 'Private path leaked into published receipt'
Require (-not(Test-Path (Split-Path $script:privateImage))) 'Private staging directory survived'
$groups.Add('Owned scene publishes only after stable observation; unowned window below background is excluded')
Reject {Save-PtOwnedScreenshot @options -Path "$Workspace\safe.png"} 'already exists'
$script:order=@($foreign,$target,$background)
Reject {Save-PtOwnedScreenshot @options -Path "$Workspace\foreign.png"} 'unowned above-background'
Require ($script:captures -eq 1 -and -not(Test-Path "$Workspace\foreign.png")) 'Rejected Shell-class window reached capture'
$groups.Add('No Shell class whitelist, no capture on unowned occlusion, no overwrite')
$script:order=@($background,$target)
Reject {Get-PtOwnedCaptureScene @options} 'behind the opaque background'
$script:order=@($target,$background)
$script:style=0x80000
Reject {Get-PtOwnedCaptureScene @options} 'non-layered'
$script:style=0
Reject {Get-PtOwnedCaptureScene @options -Region @{Left=0;Top=100;Width=200;Height=150}} 'contained'
$groups.Add('Background opacity, target z-order and region containment are mandatory')
$script:lateForeign=$true
Reject {Save-PtOwnedScreenshot @options -Path "$Workspace\late.png"} 'unowned above-background'
Require (-not(Test-Path "$Workspace\late.png") -and -not(Test-Path (Split-Path $script:privateImage))) 'Untrusted pixels were published or retained'
$groups.Add('A post-capture ownership change deletes private pixels and publishes nothing')
$groups|ConvertTo-Json|Set-Content "$Workspace\results.json"
"PASS: $($groups.Count) owned capture contract groups; no desktop access. $Workspace"
