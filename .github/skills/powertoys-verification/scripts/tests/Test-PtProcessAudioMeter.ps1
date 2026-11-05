# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE.txt in the skill directory.
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'fixtures\ProcessAudioMeter.cs')
$identity=Get-Process -Id $PID
$ticks=$identity.StartTime.ToUniversalTime().Ticks
$rejected=$false
try{$wrong=[PtProcessAudioMeter]::new($PID,$ticks+1,500);$wrong.Dispose()}
catch{if($_.Exception.ToString() -notmatch 'identity changed'){throw};$rejected=$true}
if(-not $rejected){throw 'Mismatched process identity was accepted.'}
for($i=0;$i -lt 2;$i++){
    $meter=[PtProcessAudioMeter]::new($PID,$ticks,500)
    try{
        $result=$meter.Finish()
        if(-not $result.Completed -or $result.Error -or $result.Polls -lt 2 -or
            $result.ProcessId -ne $PID -or $result.ProcessStartTicks -ne $ticks -or
            $result.EndpointFingerprint -notmatch '^[A-F0-9]{64}$'){
            throw 'Bounded audio lifecycle or exact identity observation failed.'
        }
    }finally{$meter.Dispose()}
}
'PASS: wrong process identity rejected; two bounded read-only observations completed and disposed. No sound-feedback claim.'
