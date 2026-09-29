. "$PSScriptRoot\pt-verification-report.ps1"

function Import-PtAssertionInventory {
    <#.SYNOPSIS
    Load reviewed assertion IDs against an exact LF-normalized checklist, never generate IDs per run.
    .NOTES
    String assertions resolve verbatim named checklist assertions. Objects explicitly split prose.
    Keep the inventory and checklist as recorded run inputs. No product result is inferred.
    #>
    param([Parameter(Mandatory)][string]$InventoryPath,[Parameter(Mandatory)][string]$ChecklistPath)
    $manifest=ConvertFrom-PtReportJson ([IO.File]::ReadAllText($InventoryPath))
    $source=[IO.File]::ReadAllText($ChecklistPath).Replace("`r`n","`n")
    $hash=Get-PtReportHash ([Text.Encoding]::UTF8.GetBytes($source))
    if($manifest.Schema -cne 'PtAssertionInventory.v1' -or $manifest.Revision -isnot [long] -and $manifest.Revision -isnot [int] -or
        $manifest.Revision -lt 1 -or $manifest.SourceSha256 -cne $hash){
        throw 'Assertion inventory schema/revision/checklist hash mismatch; review the inventory instead of regenerating IDs.'
    }
    $blocks=@([regex]::Matches($source,'(?ms)^- \[ \].*?(?=^- \[ \]|^#{2,3} |\z)')|ForEach-Object Value)
    if(-not $manifest.Items.Count -or $manifest.Items.Count -ne $blocks.Count){throw 'Inventory must cover every checklist scenario exactly once.'}
    $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $assertionIds=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $items=@(for($index=0;$index -lt $blocks.Count;$index++){
        $item=$manifest.Items[$index];$block=$blocks[$index]
        if([string]::IsNullOrWhiteSpace($item.Id) -or -not $ids.Add($item.Id) -or -not $item.Assertions.Count){
            throw 'Inventory scenarios require unique IDs and nonempty assertion sets.'
        }
        $sourceId=[regex]::Match($block,'\[ID: ([^\]]+)\]')
        $cpId=[regex]::Match($block,'^- \[ \] \*\*(CP-[A-Z-]+) ')
        if(($sourceId.Success -and $sourceId.Groups[1].Value -cne $item.Id) -or
            ($cpId.Success -and $cpId.Groups[1].Value -cne $item.Id)){
            throw 'Inventory scenario does not match its checklist ID/order.'
        }
        $assertions=@(foreach($entry in $item.Assertions){
            if($entry -is [string]){
                $id=$entry
                $pattern='(?ms)^  - \*\*'+[regex]::Escape($id)+'(?::|\s+\[).*?(?=^  - \*\*|\n\s*\n|\z)'
                $matches=[regex]::Matches($block,$pattern)
                if($matches.Count -ne 1){throw "Named assertion missing/ambiguous: $id"}
                $description=$matches[0].Value.Trim()
            }else{$id=$entry.Id;$description=$entry.Description}
            if([string]::IsNullOrWhiteSpace($id) -or -not $assertionIds.Add($id) -or [string]::IsNullOrWhiteSpace($description)){
                throw 'Inventory assertions require globally unique IDs and retained descriptions.'
            }
            [pscustomobject]@{Id=$id;Description=$description}
        })
        $named=@([regex]::Matches($block,'(?m)^  - \*\*((?:L\d+\.[a-z-]+)|(?:CP\d{2}))(?::|\s+\[)')|ForEach-Object {$_.Groups[1].Value})
        foreach($required in $named){if($required -cnotin $assertions.Id){throw "Inventory omitted named assertion: $required"}}
        $admin=[regex]::Match($block,'\[ADMIN: (NO|YES|COND)\]').Groups[1].Value
        if(-not $admin){throw "Missing admin metadata for $($item.Id)"}
        $clarity=if($block.Contains('[CLARITY: REWRITTEN]')){'REWRITTEN'}else{'CLEAR'}
        [pscustomobject]@{Id=$item.Id;Description=$block.Trim();Admin=$admin;Clarity=$clarity;UserVisible=$true;Assertions=$assertions}
    })
    [pscustomobject]@{Schema=$manifest.Schema;Revision=$manifest.Revision;SourceSha256=$hash
        InventorySha256=Get-PtReportHash ([IO.File]::ReadAllBytes($InventoryPath));Items=$items}
}
