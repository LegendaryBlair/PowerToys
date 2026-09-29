#requires -Version 7.2
param([string]$Workspace=(Join-Path $env:TEMP "pt-inventory-$([guid]::NewGuid().ToString('N'))"))
$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\pt-assertion-inventory.ps1"
$skill=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
[IO.Directory]::CreateDirectory($Workspace)|Out-Null
$results=@()
function Require([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Reject([scriptblock]$Body,[string]$Pattern){
    try{& $Body|Out-Null}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected rejection: $Pattern"
}
foreach($name in 'color-picker','workspaces','shortcut-guide'){
    $source="$skill\references\release-checklist\$name.md"
    $path="$skill\references\assertion-inventories\$name.json"
    $inventory=Import-PtAssertionInventory $path $source
    $again=Import-PtAssertionInventory $path $source
    Require ((ConvertTo-Json $inventory -Depth 20 -Compress) -ceq (ConvertTo-Json $again -Depth 20 -Compress)) 'Inventory is nondeterministic'
    $expected=switch($name){'color-picker'{@(17,25)} 'workspaces'{@(40,72)} default{@(19,96)}}
    Require ($inventory.Items.Count -eq $expected[0] -and @($inventory.Items.Assertions).Count -eq $expected[1]) 'Inventory count changed without reviewed test update'
    $edited=Join-Path $Workspace "$name.md"
    [IO.File]::WriteAllText($edited,[IO.File]::ReadAllText($source)+' changed')
    Reject {Import-PtAssertionInventory $path $edited} 'hash mismatch'
    [IO.File]::WriteAllText($edited,[IO.File]::ReadAllText($source).Replace("`r`n","`n").Replace("`n","`r`n"))
    Require ((Import-PtAssertionInventory $path $edited).SourceSha256 -ceq $inventory.SourceSha256) 'Line endings changed source identity'
    $manifest=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($path))
    $manifest.Items[0].Assertions=@()
    $bad=Join-Path $Workspace "$name-empty.json"
    Write-PtReportText $bad (ConvertTo-Json $manifest -Depth 20)
    Reject {Import-PtAssertionInventory $bad $source} 'nonempty'
    $manifest=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($path))
    $manifest.Items[1].Id=$manifest.Items[0].Id
    $bad=Join-Path $Workspace "$name-duplicate.json"
    Write-PtReportText $bad (ConvertTo-Json $manifest -Depth 20)
    Reject {Import-PtAssertionInventory $bad $source} 'unique IDs'
    $results+=@(@{Module=$name;Scenarios=$expected[0];Assertions=$expected[1];Status='PASS'})
}
$fixture=ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$skill\references\assertion-inventories\color-picker-cielab-fixture.json"))
$linear=@(foreach($component in $fixture.Rgb){
    $v=$component/255.0
    if($v -le 0.04045){$v/12.92}else{[Math]::Pow(($v+0.055)/1.055,2.4)}
})
# Independent sRGB -> XYZ D65 -> Lab reference, not the product's conversion output.
$x=(0.4124564*$linear[0]+0.3575761*$linear[1]+0.1804375*$linear[2])/0.95047
$y=0.2126729*$linear[0]+0.7151522*$linear[1]+0.0721750*$linear[2]
function F([double]$Value){if($Value -gt [Math]::Pow(6.0/29,3)){[Math]::Pow($Value,1.0/3)}else{$Value/(3*[Math]::Pow(6.0/29,2))+4.0/29}}
$a=500*((F $x)-(F $y))
Require ($a -ge $fixture.ExpectedARange[0] -and $a -le $fixture.ExpectedARange[1] -and $a -gt -0.5 -and $a -lt 0) 'CP16 fixture does not reach negative-fraction rounding-to-zero'
Require ([Math]::Round($a) -eq 0 -and $fixture.ExpectedIntegerA -ceq '0' -and $fixture.RejectedIntegerA -ceq '-0') 'CP16 oracle lost signed-zero distinction'
$results+=@(@{Name='Independent CP16 negative-zero fixture';ActualA=$a;Status='PASS'})
Write-PtReportText "$Workspace\results.json" (ConvertTo-Json $results -Depth 10)
"PASS: frozen inventory coverage and independent CP16 oracle. $Workspace"
