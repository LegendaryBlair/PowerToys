# Composed capture over an explicitly owned, known-opaque fixture, never a class-name exemption.
function Get-PtCaptureBackgroundInfo {
    param([Parameter(Mandatory)]$Identity)
    Assert-PtWindowIdentity $Identity
    $window=Get-PtNativeWindow -Hwnd $Identity.hwnd
    [pscustomobject]@{Window=$window;Client=[PtDesktop]::ClientBounds([IntPtr][long]$Identity.hwnd)
        ExtendedStyle=[PtDesktop]::ExtendedStyle([IntPtr][long]$Identity.hwnd)}
}

function Get-PtOwnedCaptureScene {
    param([Parameter(Mandatory)][object[]]$WindowIdentity,[Parameter(Mandatory)]$OpaqueBackgroundIdentity,$Region)
    $session=Get-PtActiveResourceSession
    if(-not $session){throw 'Owned capture requires an active resource session.'}
    Assert-PtResourceSession $session
    foreach($identity in @($WindowIdentity)+@($OpaqueBackgroundIdentity)){
        $record=@($session.Windows|Where-Object {$_.Ownership -eq 'Owned' -and -not $_.Closed -and $_.Identity.hwnd -eq $identity.hwnd})
        if($record.Count -ne 1 -or (ConvertTo-Json $record[0].Identity -Compress) -cne (ConvertTo-Json $identity -Compress)){
            throw 'Capture identities require exact recorded owned windows.'
        }
        Assert-PtWindowIdentity $identity
    }
    $scope=Get-PtCaptureWindowBounds -WindowIdentity $WindowIdentity
    $bounds=if($Region){$Region}else{[pscustomobject]@{Left=$scope.Left;Top=$scope.Top;Width=$scope.Width;Height=$scope.Height}}
    foreach($key in 'Left','Top','Width','Height'){
        if($bounds.$key -isnot [int]){throw 'Capture Region requires integer physical coordinates.'}
    }
    $right=[long]$bounds.Left+$bounds.Width;$bottom=[long]$bounds.Top+$bounds.Height
    if($bounds.Width -le 0 -or $bounds.Height -le 0 -or $bounds.Left -lt $scope.Left -or $bounds.Top -lt $scope.Top -or
        $right -gt ([long]$scope.Left+$scope.Width) -or $bottom -gt ([long]$scope.Top+$scope.Height)){
        throw 'Capture Region must be contained in the explicit window scope.'
    }
    $background=Get-PtCaptureBackgroundInfo $OpaqueBackgroundIdentity
    if(-not $background.Window.Visible -or $background.Window.Minimized -or
        (Test-PtWindowCloaked $OpaqueBackgroundIdentity.hwnd) -or ($background.ExtendedStyle -band 0x80020) -ne 0){
        throw 'Capture background must be visible, non-layered and non-transparent.'
    }
    $client=$background.Client
    if($client.Left -gt $bounds.Left -or $client.Top -gt $bounds.Top -or $client.Right -lt $right -or $client.Bottom -lt $bottom){
        throw 'Owned opaque client area must cover the whole capture region.'
    }
    $seen=$false;$above=@()
    foreach($window in @(Get-PtNativeWindow -Visible)){
        if(Test-PtWindowCloaked $window.Hwnd){continue}
        if($window.Hwnd -eq $OpaqueBackgroundIdentity.hwnd){$seen=$true;break}
        if($window.Minimized -or $window.Rect.Right -le $bounds.Left -or $window.Rect.Left -ge $right -or
            $window.Rect.Bottom -le $bounds.Top -or $window.Rect.Top -ge $bottom){continue}
        $record=@($session.Windows|Where-Object {$_.Ownership -eq 'Owned' -and -not $_.Closed -and $_.Identity.hwnd -eq $window.Hwnd})
        if($record.Count -ne 1){
            throw "Capture rejected unowned above-background HWND $($window.Hwnd), class $($window.ClassName)."
        }
        Assert-PtWindowIdentity $record[0].Identity
        $above+=@([pscustomobject]@{Identity=$record[0].Identity;Rect=$window.Rect})
    }
    if(-not $seen){throw 'Owned capture background is absent from visible z-order.'}
    foreach($identity in $WindowIdentity){
        if($identity.hwnd -ne $OpaqueBackgroundIdentity.hwnd -and $identity.hwnd -notin @($above.Identity.hwnd)){
            throw 'Capture target is behind the opaque background.'
        }
    }
    [pscustomobject]@{Bounds=$bounds;Background=$OpaqueBackgroundIdentity;Client=$client;Above=$above}
}

function Save-PtOwnedScreenshot {
    <#
    .SYNOPSIS
    Capture a composed region only over a known-opaque owned fixture; publish after both scene checks.
    .NOTES
    The caller must supply a fixture that actually paints its client area opaquely and whose content
    is safe to disclose. Native style/geometry checks are not a generic proof of application opacity.
    This function never foregrounds, hides or adopts a window. Rejected pixels are deleted privately.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object[]]$WindowIdentity,
        [Parameter(Mandatory)]$OpaqueBackgroundIdentity,$Region,[scriptblock]$Observe)
    if((Test-Path -LiteralPath $Path) -or (Test-Path -LiteralPath "$Path.state.json")){throw 'Capture output already exists.'}
    $scene=Get-PtOwnedCaptureScene -WindowIdentity $WindowIdentity -OpaqueBackgroundIdentity $OpaqueBackgroundIdentity -Region $Region
    $private=Join-Path ([IO.Path]::GetTempPath()) "pt-owned-capture-$([guid]::NewGuid().ToString('N'))"
    [IO.Directory]::CreateDirectory($private)|Out-Null
    $image=Join-Path $private 'capture.png'
    $published=$false
    $callerObservation=$Observe
    try{
        $state=Save-PtPassiveScreenshot -Path $image -WindowIdentity $WindowIdentity -Region $scene.Bounds -Observe {
            [ordered]@{
                Scene=Get-PtOwnedCaptureScene -WindowIdentity $WindowIdentity -OpaqueBackgroundIdentity $OpaqueBackgroundIdentity -Region $Region
                Observation=$(if($callerObservation){& $callerObservation})
            }

        }
        $state.path=[IO.Path]::GetFullPath($Path)
        $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $state -Depth 30))
        [IO.File]::WriteAllBytes("$image.state.json",$bytes)
        [IO.File]::Move($image,$Path)
        $published=$true
        [IO.File]::Move("$image.state.json","$Path.state.json")
        $state
    }catch{
        if($published -and [IO.File]::Exists($Path)){[IO.File]::Delete($Path)}
        throw
    }finally{
        foreach($file in @($image,"$image.state.json")){
            if([IO.File]::Exists($file)){[IO.File]::Delete($file)}
        }
        [IO.Directory]::Delete($private,$false)
    }
}

function Assert-PtControlWindowScope {
    param([Parameter(Mandatory)]$Element,[Parameter(Mandatory)]$WindowIdentity)
    if(-not(Get-Command Initialize-PtUiAutomation -ErrorAction Ignore)){. "$PSScriptRoot\pt-uia.ps1"}
    Initialize-PtUiAutomation
    $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$WindowIdentity.hwnd)
    $node=$Element
    for($depth=0;$node -and $depth -lt 64;$depth++){
        if([Windows.Automation.Automation]::Compare($node,$root)){return}
        $node=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($node)
    }
    throw 'Control is not in the declared window subtree.'
}

function Get-PtControlViewportBounds {
    param([Parameter(Mandatory)]$Element,[Parameter(Mandatory)]$WindowIdentity)
    $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$WindowIdentity.hwnd)
    $ancestor=[Windows.Automation.TreeWalker]::RawViewWalker.GetParent($Element)
    for($depth=0;$ancestor -and $depth -lt 64;$depth++){
        $scroll=$null
        $isRoot=[Windows.Automation.Automation]::Compare($ancestor,$root)
        if($isRoot -or $ancestor.TryGetCurrentPattern([Windows.Automation.ScrollPattern]::Pattern,[ref]$scroll)){
            $ancestor.Current.BoundingRectangle
        }
        if($isRoot){return}
        $ancestor=[Windows.Automation.TreeWalker]::RawViewWalker.GetParent($ancestor)
    }
    throw 'Control viewport ancestry did not reach the declared window.'
}

function Get-PtControlCaptureState {
    param([Parameter(Mandatory)]$Element,[Parameter(Mandatory)]$WindowIdentity)
    Assert-PtWindowIdentity $WindowIdentity
    $current=$Element.Current
    $runtime=@($Element.GetRuntimeId())
    $bounds=$current.BoundingRectangle
    if(-not $runtime.Count -or $current.ProcessId -ne $WindowIdentity.processId -or $current.IsOffscreen -or
        $bounds.Width -le 0 -or $bounds.Height -le 0){throw 'Control is unavailable, offscreen or belongs to another process.'}
    Assert-PtControlWindowScope -Element $Element -WindowIdentity $WindowIdentity
    foreach($viewport in @(Get-PtControlViewportBounds -Element $Element -WindowIdentity $WindowIdentity)){
        if($bounds.Left -lt $viewport.Left -or $bounds.Top -lt $viewport.Top -or
            $bounds.Right -gt $viewport.Right -or $bounds.Bottom -gt $viewport.Bottom){
            throw 'Control is clipped by an ancestor viewport; realize the complete control before capture.'
        }
    }
    $left=[Math]::Floor($bounds.Left);$top=[Math]::Floor($bounds.Top)
    $right=[Math]::Ceiling($bounds.Right);$bottom=[Math]::Ceiling($bounds.Bottom)
    [pscustomobject]@{RuntimeId=$runtime;AutomationId=$current.AutomationId;ControlType=$current.ControlType.ProgrammaticName
        Bounds=[pscustomobject]@{Left=$bounds.Left;Top=$bounds.Top;Right=$bounds.Right;Bottom=$bounds.Bottom}
        Region=[pscustomobject]@{Left=[int]$left;Top=[int]$top;Width=[int]($right-$left);Height=[int]($bottom-$top)}}
}

function Save-PtOwnedControlScreenshot {
    <#.SYNOPSIS
    Capture a complete actual control and reject identity/geometry changes during capture.
    .NOTES
    This proves crop association and ownership, not that the rendered content is correct.
    The caller must realize the control and establish the opaque background beforehand.
    #>
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$WindowIdentity,
        [Parameter(Mandatory)]$Element,[Parameter(Mandatory)]$OpaqueBackgroundIdentity)
    $controlElement=$Element
    $controlWindow=$WindowIdentity
    $initialControl=Get-PtControlCaptureState -Element $controlElement -WindowIdentity $controlWindow
    $controlSignature=ConvertTo-Json $initialControl -Depth 8 -Compress
    Save-PtOwnedScreenshot -Path $Path -WindowIdentity @($controlWindow) `
        -OpaqueBackgroundIdentity $OpaqueBackgroundIdentity -Region $initialControl.Region -Observe {
            $currentControl=Get-PtControlCaptureState -Element $controlElement -WindowIdentity $controlWindow
            if((ConvertTo-Json $currentControl -Depth 8 -Compress) -cne $controlSignature){
                throw 'Control identity or geometry changed; do not publish the stale crop.'
            }
            $currentControl
        }
}
