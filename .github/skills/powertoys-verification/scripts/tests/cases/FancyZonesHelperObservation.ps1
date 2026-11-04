param($Attempt)
$ErrorActionPreference='Stop'
Initialize-PtFancyZonesCaseWindows
Set-PtFancyZonesCaseOption History $false
Set-PtFancyZonesCaseOption ActiveMonitor $false
Set-PtFancyZonesCaseOption Override $true
Set-PtFancyZonesCaseOption Across $false
Set-PtFancyZonesCaseOption Relayout $true
Set-CaseSpan $false
Set-PtFancyZonesCasePositionMode $false
$primary=@($FzCase.DisplayModel.Monitors|Where-Object Primary)[0]
if(-not $primary){throw 'No actual primary monitor.'}
$primaryIndex=[array]::IndexOf($FzCase.DisplayModel.Monitors,$primary)
function Apply-AcceptanceLayout($Layout) {
    Apply-PtFancyZonesCaseLayout -Name $Layout.name -MonitorNumber $primary.Number
    Close-PtFancyZonesEditor $FzCase.Driver
}
function Observe-AcceptanceFrame($Expected) {
    $frameObservation=@{Last=$null;Stable=0}
    try {
        Wait-PtCondition -Description 'expected relayout rectangle' -TimeoutSeconds 5 -Probe {
            $frameObservation.Last=Get-PtFancyZonesWindowState $FzCase.Target
            if(Test-PtFancyZonesFrameEqual $frameObservation.Last.Native.Frame $Expected){$frameObservation.Stable++}else{$frameObservation.Stable=0}
            if($frameObservation.Stable -ge 2){$frameObservation.Last}
        }
    } catch {
        if($_.Exception.Message -notmatch '^Timed out'){throw}
        if(-not $frameObservation.Last){throw}
        $frameObservation.Last
    }
}
function Capture-AcceptanceWindow($Name) {
    $client=[PtDesktop]::ClientBounds([IntPtr][long]$FzCase.Target.hwnd)
    Capture-CaseRegion $Attempt $Name $FzCase.Target ([pscustomobject]@{
        Left=$client.Left;Top=$client.Top;Width=($client.Right-$client.Left);Height=($client.Bottom-$client.Top)
    })
}
Set-PtFancyZonesCaseZoneCount -Template Columns -Count 3
$three=Copy-PtFancyZonesCaseTemplate Columns
Set-PtFancyZonesCaseZoneCount -Template Rows -Count 1
$one=Copy-PtFancyZonesCaseTemplate Rows
Apply-AcceptanceLayout $three
Reset-PtFancyZonesCaseWindow -Target $FzCase.Target -MonitorIndex $primaryIndex
Send-PtFancyZonesCaseKey -Target $FzCase.Target -Key 0x27|Out-Null
Set-PtFancyZonesCasePositionMode $true
Show-PtFancyZonesCaseWindow $FzCase.Target
$scope=New-PtFancyZonesDriverScope $FzCase.Driver
Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -Action {
    Invoke-PtHeldKeys -Hwnd $FzCase.Target.hwnd -Keys @(0x11,0x12,0x5B) -Action {
        Send-PtChord -Hwnd $FzCase.Target.hwnd -Key 0x27 -KeyDownMilliseconds 60|Out-Null
    }|Out-Null
}|Out-Null
$original=Wait-PtCondition -Description 'actual zones-1-2 assignment' -TimeoutSeconds 5 -Probe {
    $state=Get-PtFancyZonesWindowState $FzCase.Target
    if($state.Native.ZoneMask -eq 3){$state}
}
$beforeImage=Capture-AcceptanceWindow 'two-zones-before'
$work=$primary.PhysicalWork
$spacing=if($one.info.'show-spacing'){[int]$one.info.spacing}else{0}
$expectedOne=[pscustomobject]@{Left=($work.Left+$spacing);Top=($work.Top+$spacing)
    Right=($work.Right-$spacing);Bottom=($work.Bottom-$spacing)}
Apply-AcceptanceLayout $one
$reduced=Observe-AcceptanceFrame $expectedOne
$reducedImage=Capture-AcceptanceWindow 'one-zone-reduced'
Apply-AcceptanceLayout $three
$returned=Observe-AcceptanceFrame $original.Native.Frame
$returnedImage=Capture-AcceptanceWindow 'two-zones-returned'
$observation=Get-PtFancyZonesRelayoutObservation -Original $original.Native -Reduced $reduced.Native `
    -Returned $returned.Native -ExpectedOneZoneFrame $expectedOne
$match=$observation.FitsRemainingZone -and $observation.ReturnsToOriginalGeometry -and $observation.ReturnsToOriginalAssignment
Record-CaseCondition -Attempt $Attempt -ConditionId 'observation.relayout:off' -Category product -Executed $true `
    -Verdict $(if($match){'PASS'}else{'FAIL'}) -Actual "Reduced rectangle and returned geometry/index set match=$match; reduced mask=$($reduced.Native.ZoneMask) was observed, not forced to 1." `
    -Detail @{Observation=$observation;Before=$original.Native;Reduced=$reduced.Native;Returned=$returned.Native;ExpectedOneZoneFrame=$expectedOne} `
    -Evidence @($beforeImage,$reducedImage,$returnedImage)

function Capture-OpacitySample($Name) {
    $state=Get-PtFancyZonesWindowState $FzCase.Target
    $client=[PtDesktop]::ClientBounds([IntPtr][long]$FzCase.Target.hwnd)
    $region=[pscustomobject]@{Left=[int]($client.Left+100);Top=[int]($client.Top+100);Width=192;Height=128}
    $backgroundInfo=@($FzCase.SurfaceReady.BackgroundInfo|Where-Object {
        $_.Area.Left -le $region.Left -and $_.Area.Top -le $region.Top -and
        $_.Area.Right -ge $region.Left+$region.Width -and $_.Area.Bottom -ge $region.Top+$region.Height
    })
    if($backgroundInfo.Count -ne 1){throw 'Opacity sample is not contained in one owned patterned background.'}
    $background=Get-PtWindowIdentity $backgroundInfo[0].Hwnd
    $identities=@($background,$FzCase.Target)+@(Get-PtFancyZonesCaseOverlays|Where-Object {
        $_.Visible -and $_.Rect.Left -lt $region.Left+$region.Width -and $_.Rect.Right -gt $region.Left -and
        $_.Rect.Top -lt $region.Top+$region.Height -and $_.Rect.Bottom -gt $region.Top
    }|ForEach-Object {Get-PtWindowIdentity $_.Hwnd})
    $path=New-PtVerificationArtifactPath -Attempt $Attempt -Name "$Name.png"
    Save-PtOwnedScreenshot -Path $path -WindowIdentity $identities -OpaqueBackgroundIdentity $background -Region $region|Out-Null
    $image=Add-PtVerificationArtifact -Attempt $Attempt -Path $path -Kind Screenshot -Description 'Same owned client sampling rule over a source-defined 32-pixel checkerboard'
    Add-PtVerificationArtifact -Attempt $Attempt -Path "$path.state.json" -Kind Evidence -Description 'Original ownership/z-order capture evidence'|Out-Null
    $area=$backgroundInfo[0].Area
    $x=[int]($area.Left+16+32*[Math]::Ceiling(($region.Left-$area.Left-16)/32.0))
    $y=[int]($area.Top+16+32*[Math]::Ceiling(($region.Top-$area.Top-16)/32.0))
    $bitmap=[Drawing.Bitmap]::new($path)
    try {
        $colors=@($bitmap.GetPixel($x-$region.Left,$y-$region.Top).ToArgb(),
            $bitmap.GetPixel($x+32-$region.Left,$y-$region.Top).ToArgb(),
            $bitmap.GetPixel($x-$region.Left,$y+32-$region.Top).ToArgb(),
            $bitmap.GetPixel($x+32-$region.Left,$y+32-$region.Top).ToArgb())
    } finally {$bitmap.Dispose()}
    [pscustomobject]@{State=$state.Native;Image=$image;SampleColors=$colors
        Uniform=(@($colors|Sort-Object -Unique).Count -eq 1)
        CheckerVisible=($colors[0] -eq $colors[3] -and $colors[1] -eq $colors[2] -and $colors[0] -ne $colors[1])}
}
Reset-PtFancyZonesCaseWindow -Target $FzCase.Target -MonitorIndex $primaryIndex
Set-PtFancyZonesCaseOption ShowAll $false
Set-PtFancyZonesCaseOption Transparent $true
Show-PtFancyZonesCaseWindow -Target $FzCase.Target -Backgrounds
$before=Capture-OpacitySample 'opacity-before'
$FzCase.OpacitySample=$null
$scope=New-PtFancyZonesDriverScope $FzCase.Driver
Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -ArgumentList @($work) -Action {
    param($area)
    Invoke-PtHeldKeys -Hwnd $FzCase.Target.hwnd -Keys @(0x10) -Action {
        Invoke-PtFancyZonesCaseDrag -Target $FzCase.Target -X ([int]($area.Left+($area.Right-$area.Left)*0.235)) `
            -Y ([int]($area.Top+($area.Bottom-$area.Top)*0.55)) -Cancel -During {
                Wait-PtCondition -Description 'actual transparent drag state' -TimeoutSeconds 3 -Probe {
                    $state=(Get-PtFancyZonesWindowState $FzCase.Target).Native
                    $state.Layered -and $state.AlphaRead -and ($state.AlphaFlags -band 2) -ne 0 -and $state.Alpha -lt 255
                }|Out-Null
                $FzCase.OpacitySample=Capture-OpacitySample 'opacity-during'
            }
    }|Out-Null
}|Out-Null
$during=$FzCase.OpacitySample
$after=Capture-OpacitySample 'opacity-after-cancel'
$restored=$after.State.Layered -eq $before.State.Layered -and
    (-not $after.State.Layered -or $after.State.Alpha -eq $before.State.Alpha)
$match=$before.Uniform -and $during.CheckerVisible -and $after.Uniform -and $restored
Record-CaseCondition -Attempt $Attempt -ConditionId 'observation.transparency:off' -Category product -Executed $true `
    -Verdict $(if($match){'PASS'}else{'FAIL'}) -Actual "Owned checker visible during drag=$($during.CheckerVisible); opaque before/after=$($before.Uniform)/$($after.Uniform); native opacity restored=$restored." `
    -Detail @{Before=$before;During=$during;After=$after;MoveEvents=$FzCase.LastMoveEvents} `
    -Evidence @($before.Image,$during.Image,$after.Image)
