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
$expectedInventories=[ordered]@{
    'advanced-paste'=@(29,32); 'color-picker'=@(17,25); 'crop-and-lock'=@(13,14)
    'environment-variables'=@(29,135); 'file-locksmith'=@(10,10); 'image-resizer'=@(12,18)
    'keyboard-manager'=@(24,135)
    'new-plus'=@(9,9); 'peek'=@(18,18); 'power-display'=@(33,138); 'power-rename'=@(16,17); 'settings'=@(25,50)
    'shortcut-guide'=@(19,96); 'workspaces'=@(38,72); 'zoomit'=@(39,39); 'quick-accent'=@(18,57)
}
$checklists=@(Get-ChildItem "$skill\references\release-checklist" -Filter '*.md' |
    Where-Object Name -NE 'index.md' | ForEach-Object BaseName)
Require (@(Compare-Object @($expectedInventories.Keys) $checklists).Count -eq 0) 'A supplied checklist lacks reviewed inventory coverage'
foreach($name in $expectedInventories.Keys){
    $source="$skill\references\release-checklist\$name.md"
    $path="$skill\references\assertion-inventories\$name.json"
    $inventory=Import-PtAssertionInventory $path $source
    $again=Import-PtAssertionInventory $path $source
    Require ((ConvertTo-Json $inventory -Depth 20 -Compress) -ceq (ConvertTo-Json $again -Depth 20 -Compress)) 'Inventory is nondeterministic'
    $expected=$expectedInventories[$name]
    Require ($inventory.Items.Count -eq $expected[0] -and @($inventory.Items.Assertions).Count -eq $expected[1]) 'Inventory count changed without reviewed test update'
    $text=[IO.File]::ReadAllText($source).Replace("`r`n","`n")
    Require ($text -match '(?s)## Legend.*## Fixtures & conventions.*## [^\n]+ \(\d+ items\).*### ') "Functional layout missing: $name"
    Require ($text -notmatch '(?m)^## (Scope and provenance|Provenance and applicability|Original baseline|PR disposition|Coverage accounting|Scenario IDs and assertion coverage)' -and
        $text -notmatch '(?m)^### .*PR-derived|^\s+\*\*(Covers|Arrange|Act|Assert|Restore):\*\*') "Checklist mixes operating/history sections: $name"
    $manifest=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($path))
    Require (@($manifest.Items.Assertions | Where-Object {$_ -is [string]}).Count -eq 0) "Current child definitions still depend on inline Markdown: $name"
    Require (@($manifest.Items.Assertions | Where-Object {$_.Description -match '^- \*\*[^*]+\*\*'}).Count -eq 0) "Legacy child identity wrapper leaked into an explicit expectation: $name"
    foreach($item in $inventory.Items){
        Require ($item.Description -match ('\A- \[ \] \*\*[^\r\n]+\*\* \[ID: '+[regex]::Escape($item.Id)+'\] \[ADMIN: ')) "Explicit case header missing: $name/$($item.Id)"
    }
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
$source=Join-Path $Workspace 'legacy-named-source.md'
$text="- [ ] **Legacy named source** [ID: legacy] [ADMIN: NO]`n  - **CP01 [ADMIN: NO]** First required behavior.`n  - **CP04 [ADMIN: NO]** Second required behavior.`n"
Write-PtReportText $source $text
$manifest=@{Schema='PtAssertionInventory.v1';Revision=1
    SourceSha256=Get-PtReportHash ([Text.Encoding]::UTF8.GetBytes($text))
    Items=@(@{Id='legacy';Assertions=@('CP01','CP04')})}
$legacy=Join-Path $Workspace 'legacy-named-source.json'
Write-PtReportText $legacy (ConvertTo-Json $manifest -Depth 20)
Require (@((Import-PtAssertionInventory $legacy $source).Items.Assertions).Count -eq 2) 'Legacy recorded string definitions no longer load'
$manifest.Items[0].Assertions=@('CP04')
$bad=Join-Path $Workspace 'omitted-named-source.json'
Write-PtReportText $bad (ConvertTo-Json $manifest -Depth 20)
Reject {Import-PtAssertionInventory $bad $source} 'omitted named assertion: CP01'
$source="$skill\references\release-checklist\environment-variables.md"
$path="$skill\references\assertion-inventories\environment-variables.json"
$manifest=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($path))
$applied=@($manifest.Items|Where-Object Id -EQ 'EV-APPLIED-EDIT')[0]
$child=@($applied.Assertions|Where-Object Id -EQ 'EV-P07.absent-edit')[0]
$applied.Assertions+=@($child)
$bad=Join-Path $Workspace 'env-duplicate-child.json'
Write-PtReportText $bad (ConvertTo-Json $manifest -Depth 20)
Reject {Import-PtAssertionInventory $bad $source} 'globally unique'
$manifest=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($path))
$manifest.Items[0].Assertions[0].Description=''
$bad=Join-Path $Workspace 'env-empty-description.json'
Write-PtReportText $bad (ConvertTo-Json $manifest -Depth 20)
Reject {Import-PtAssertionInventory $bad $source} 'retained descriptions'
$manifest=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($path))
$swap=$manifest.Items[0];$manifest.Items[0]=$manifest.Items[1];$manifest.Items[1]=$swap
$bad=Join-Path $Workspace 'env-reordered-scenario.json'
Write-PtReportText $bad (ConvertTo-Json $manifest -Depth 20)
Reject {Import-PtAssertionInventory $bad $source} 'ID/order'
$results+=@(@{Name='Named-source retention and explicit child description/uniqueness/order contracts';Status='PASS'})
$mergeCases=@(
    @{Module='workspaces';Case='WS14';Children=@('WS14.menu-edit','WS15.card-edit')},
    @{Module='workspaces';Case='WS17';Children=@('WS17.remove-app','WS18.add-back')},
    @{Module='image-resizer';Case='IR-FIT-MODES';Children=@('IR-FILL.behavior','IR-FIT.behavior','IR-STRETCH.behavior')},
    @{Module='image-resizer';Case='IR-UNITS';Children=@('IR-CENTIMETERS.behavior','IR-INCHES.behavior','IR-PERCENT.behavior','IR-PIXELS.behavior')},
    @{Module='power-rename';Case='PR-REGEX';Children=@('PR-REGEX-MATCH.behavior','PR-REGEX-BACKREFERENCE.behavior')},
    @{Module='settings';Case='SET-DASHBOARD-SORT';Children=@('SET-DASHBOARD-SORT.behavior','SET-QUICK-ACCESS-SORT.behavior')},
    @{Module='settings';Case='SET-WHATS-NEW-ENTRY';Children=@('SET-WHATS-NEW-ENTRY.behavior','SET-SECONDARY-LIFETIME.behavior')},
    @{Module='quick-accent';Case='QA-ARROWS';Children=@('QA-ARROWS-LEFT','QA-ARROWS-RIGHT','QA-SPACE-FORWARD','QA-SPACE-BACKWARD')
        PreviousScenarioIds=@('QA-ARROWS','QA-SPACE')},
    @{Module='quick-accent';Case='QA-DESCRIPTIONS';Children=@('QA-DESCRIPTIONS-OFF','QA-DESCRIPTIONS-ON','QA-OVERFLOW-OFF','QA-OVERFLOW-ON')
        PreviousScenarioIds=@('QA-DESCRIPTIONS','QA-OVERFLOW')}
)
foreach($case in $mergeCases){
    $inventory=Import-PtAssertionInventory "$skill\references\assertion-inventories\$($case.Module).json" `
        "$skill\references\release-checklist\$($case.Module).md"
    $item=@($inventory.Items|Where-Object Id -CEQ $case.Case)
    Require ($item.Count -eq 1 -and @(Compare-Object $case.Children @($item[0].Assertions.Id)).Count -eq 0) "Merged case lost an independent observation: $($case.Case)"
    if($case.PreviousScenarioIds){
        $manifest=ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$skill\references\assertion-inventories\$($case.Module).json"))
        $merged=@($manifest.Items|Where-Object Id -CEQ $case.Case)[0]
        Require (@(Compare-Object $case.PreviousScenarioIds @($merged.PreviousScenarioIds)).Count -eq 0) "Merged scenario mapping is incomplete: $($case.Case)"
        Require (@($inventory.Items|Where-Object {$_.Id -in $case.PreviousScenarioIds -and $_.Id -cne $case.Case}).Count -eq 0) "Merged source scenario remains duplicated: $($case.Case)"
    }
}
$results+=@(@{Name='Merged workflows retain original independent observations';Status='PASS'})
$settings=ConvertFrom-PtReportJson ([IO.File]::ReadAllText("$skill\references\assertion-inventories\settings.json"))
$localization=@($settings.Items|Where-Object Id -CEQ 'SET-LOCALIZATION')
Require (@($settings.Items|Where-Object Id -CEQ 'SET-RESTART-MEDIUM').Count -eq 0) 'Ambiguous standalone restart scenario returned'
Require ($localization.Count -eq 1 -and
    @($localization[0].Assertions|Where-Object Id -CEQ 'SET-RESTART-MEDIUM.behavior').Count -eq 1 -and
    @($localization[0].Assertions|Where-Object Id -CEQ 'SET-LOCALIZATION.behavior').Count -eq 1) 'Language workflow lost its independent restart or localization observation'
Require (@(Compare-Object @('SET-LOCALIZATION','SET-RESTART-MEDIUM') @($localization[0].PreviousScenarioIds)).Count -eq 0) 'Settings scenario merge mapping is incomplete'
$results+=@(@{Name='Language restart retains medium-integrity coverage without a standalone restart scenario';Status='PASS'})
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
