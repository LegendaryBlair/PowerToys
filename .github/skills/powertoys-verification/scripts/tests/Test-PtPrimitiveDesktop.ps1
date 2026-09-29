#requires -Version 7.2
<#
.SYNOPSIS
Exercise only synthetic windows/clipboard data. Requires an interactive STA desktop.
.NOTES
Does not launch PowerToys. Preserves the original clipboard, foreground and pointer.
#>
param([string]$Workspace=(Join-Path $env:TEMP "pt-primitive-$([guid]::NewGuid().ToString('N'))"),
    [switch]$DisposableClipboard)
$ErrorActionPreference='Stop'
if(-not $DisposableClipboard){throw 'This test writes the real session clipboard. Run only in an explicitly disposable test session with -DisposableClipboard.'}
foreach($name in 'pt-desktop','pt-state-snapshot','pt-foreground-guard','pt-clipboard-session'){
    . "$PSScriptRoot\..\$name.ps1"
}
if([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'){throw 'Use pwsh -STA.'}
if(Test-Path $Workspace){throw 'Use a new output directory.'}
$baseline=Get-PtDesktopSnapshot
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$baseline|ConvertTo-Json -Depth 20|Set-Content "$Workspace\desktop-baseline.json"
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$results=[Collections.Generic.List[object]]::new()
function Require($Value,$Message){if(-not $Value){throw $Message}}
function Check($Name,[scriptblock]$Body){
    try{& $Body|Out-Null;$results.Add(@{Name=$Name;Status='PASS'})}
    catch{$results.Add(@{Name=$Name;Status='FAIL';Error=$_.Exception.Message});throw}
    finally{ConvertTo-Json -InputObject @($results) -Depth 6|Set-Content "$Workspace\results.json"}
}
function Reject([scriptblock]$Body,$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
$owner=[Windows.Forms.Form]::new()
$owner.Text='Owned primitive acceptance'
$owner.StartPosition='Manual';$owner.Location=[Drawing.Point]::new(260,180)
$owner.ClientSize=[Drawing.Size]::new(360,200);$owner.BackColor=[Drawing.Color]::DarkBlue
$popup=[Windows.Forms.Form]::new()
$popup.Text='Owned popup acceptance'
$popup.StartPosition='Manual';$popup.Location=[Drawing.Point]::new(610,230)
$popup.ClientSize=[Drawing.Size]::new(180,100);$popup.BackColor=[Drawing.Color]::DarkGreen
$guard=$null;$bitmap=$null;$png=$null;$testError=$null
$writerStart=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
function WriteTestClipboard([scriptblock]$Action){
    Invoke-PtClipboardWrite -Guard $guard -WriterProcessId $PID -WriterStartTicks $writerStart -Action $Action
}
try{
    $guard=New-PtClipboardSession -Workspace $Workspace
    Check 'Text image and registered formats survive an owned round trip' {
        $bitmap=[Drawing.Bitmap]::new(12,12)
        $g=[Drawing.Graphics]::FromImage($bitmap)
        try{$g.Clear([Drawing.Color]::Red)}finally{$g.Dispose()}
        $png=[IO.MemoryStream]::new();$bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png)
        $data=[Windows.Forms.DataObject]::new()
        $data.SetImage($bitmap);$data.SetText('synthetic unicode')
        $data.SetData('HTML Format',$false,'<html><body>synthetic</body></html>')
        $data.SetData('Rich Text Format',$false,'{\rtf1 synthetic}')
        $data.SetData('PNG',$false,[IO.MemoryStream]::new($png.ToArray()))
        WriteTestClipboard {[Windows.Forms.Clipboard]::SetDataObject($data,$true)}
        $inner=New-PtClipboardGuard -OwnerHwnd $owner.Handle.ToInt64()
        try{
            $sequence=$inner.ExpectedSequence
            WriteTestClipboard {[Windows.Forms.Clipboard]::SetText('synthetic replacement')}
            $null=Register-PtClipboardWrite $inner $sequence $PID $writerStart
            WriteTestClipboard {$inner.Restore()}
            Require $inner.Restored 'Native clipboard comparison did not succeed'
            Require ([Windows.Forms.Clipboard]::GetText() -ceq 'synthetic unicode') 'Text not restored'
        }finally{$inner.Dispose()}
    }
    Check 'Unacknowledged synthetic write is not overwritten' {
        $inner=New-PtClipboardGuard -OwnerHwnd $owner.Handle.ToInt64()
        try{
            WriteTestClipboard {[Windows.Forms.Clipboard]::SetText('simulated external data')}
            Reject {$inner.Restore()} 'conflict'
            Require ([Windows.Forms.Clipboard]::GetText() -ceq 'simulated external data') 'Conflicting content overwritten'
        }finally{$inner.Dispose()}
    }
    Check 'Empty clipboard baseline restores to empty' {
        WriteTestClipboard {
            [Windows.Forms.Clipboard]::Clear()
            $empty=New-PtClipboardGuard -OwnerHwnd $owner.Handle.ToInt64()
            try{
                [Windows.Forms.Clipboard]::SetText('temporary owned text')
                $null=Register-PtClipboardWrite $empty $empty.ExpectedSequence $PID $writerStart
                $empty.Restore()
                Require $empty.Restored 'Empty baseline not restored'
                # Finish with an attributable synthetic writer; the nested guard proves absence.
                [Windows.Forms.Clipboard]::SetText('outer test segment')
            }finally{$empty.Dispose()}
        }
    }
    $guard.Restore();Assert-PtClipboardRestored $guard
    Check 'Owner and popup produce only the requested physical capture union' {
        $owner.Show();$popup.Show($owner);$owner.Activate()
        [Windows.Forms.Application]::DoEvents()
        $identities=@(Get-PtWindowIdentity $owner.Handle.ToInt64();Get-PtWindowIdentity $popup.Handle.ToInt64())
        $capture=Save-PtPassiveScreenshot -Path "$Workspace\owned-union.png" -WindowIdentity $identities
        $image=[Drawing.Image]::FromFile("$Workspace\owned-union.png")
        try{
            Require ($image.Width -eq $capture.before.scope.Width -and $image.Height -eq $capture.before.scope.Height) 'Image/physical scope mismatch'
        }finally{$image.Dispose()}
        $popup.Hide()
        Reject {Save-PtPassiveScreenshot -Path "$Workspace\hidden.png" -WindowIdentity $identities} 'hidden'
        $popup.Show($owner)
        $count=@{Value=0}
        Reject {Save-PtPassiveScreenshot -Path "$Workspace\moved-invalid.png" -WindowIdentity $identities -Observe {
            $count.Value++
            if($count.Value -eq 2){$popup.Left+=25;[Windows.Forms.Application]::DoEvents()}
            'stable-probe'
        }} 'Observation changed'
        Require (Test-Path "$Workspace\moved-invalid.png.state.json") 'Invalid capture sidecar missing'
    }
}catch{$testError=$_}
finally{
    $cleanupErrors=[Collections.Generic.List[string]]::new()
    try{
        if($guard -and -not $guard.Restored){$guard.Restore()}
        if($guard){Assert-PtClipboardRestored $guard;$guard.Dispose()}
    }catch{$cleanupErrors.Add("Clipboard: $($_.Exception.Message)")}
    # Always restore independent desktop state; a clipboard failure must not skip it.
    if(-not $guard -or $guard.Restored){$popup.Dispose();$owner.Dispose()}
    if($bitmap){$bitmap.Dispose()};if($png){$png.Dispose()}
    try{Restore-PtDesktopSnapshot $baseline|ConvertTo-Json -Depth 10|Set-Content "$Workspace\desktop-restored.json"}
    catch{$cleanupErrors.Add("Desktop: $($_.Exception.Message)")}
    @{ClipboardRestored=($guard -and $guard.Restored);DesktopRestored=(Test-Path "$Workspace\desktop-restored.json")
        Errors=@($cleanupErrors);OriginalError=$(if($testError){$testError.Exception.Message}else{$null})
        RecoveryReceipt=$(if($guard.PSObject.Properties['PipeName']){$guard.Path}else{$null})
        BackupKeeperProcessId=$(if($guard.PSObject.Properties['PipeName']){$guard.ProcessId}else{$null})
    }|ConvertTo-Json -Depth 6|Set-Content "$Workspace\restoration-status.json"
    if($cleanupErrors.Count){
        if($testError){$testError.Exception.Data['CleanupFailures']=@($cleanupErrors)}
        else{$testError=[InvalidOperationException]::new(($cleanupErrors -join '; '))}
        [Console]::Error.WriteLine("Restoration unresolved: $($cleanupErrors -join '; '). Do not rerun or claim restoration. Reconnect using restoration-status.json's keeper receipt; never terminate an unresolved keeper.")
    }
}
if($testError){throw $testError}
"PASS: $($results.Count) synthetic desktop groups; clipboard and desktop restored. $Workspace"
