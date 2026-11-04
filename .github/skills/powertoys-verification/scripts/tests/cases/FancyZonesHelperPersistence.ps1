param($Attempt)
$ErrorActionPreference='Stop'
Set-CaseSpan $false
function Set-AcceptanceHorizontalDefault([string]$Name,[string]$ExpectedType,[string]$ExpectedUuid) {
    Open-PtFancyZonesCaseLayoutProperties $Name
    $FzCase.Driver.DefaultOrientations=@('horizontal')
    $scope=New-PtFancyZonesDriverScope $FzCase.Driver
    Invoke-PtFancyZonesDriverAction -Context $FzCase.Driver -Scope $scope -ArgumentList @($ExpectedType,$ExpectedUuid) -Action {
        param($type,$uuid)
        $root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$FzCase.Driver.Editor.hwnd)
        $set=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,
            [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'SetLayoutAsHorizontalDefaultButton'))|
            Where-Object {-not $_.Current.IsOffscreen})
        if($set.Count -gt 1){throw 'Ambiguous horizontal-default control.'}
        if($set.Count -eq 1){$set[0].GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()}
        else{
            $selected=Resolve-PtUiElement -Hwnd $FzCase.Driver.Editor.hwnd -AutomationId HorizontalDefaultLayoutButton -ControlType Button
            if($selected.Current.IsOffscreen){throw 'Neither default state is visible.'}
        }
        Invoke-PtFancyZonesCaseButton PrimaryButton
        Wait-PtFancyZonesPersistence -Context $FzCase.Driver -ArgumentList @($type,$uuid) -Ready {
            param($snapshot,$layoutType,$layoutUuid)
            $defaults=Get-PtFancyZonesSnapshotJson $snapshot 'default-layouts.json'
            $row=@($defaults.'default-layouts'|Where-Object 'monitor-configuration' -CEQ 'horizontal')
            $row.Count -eq 1 -and $row[0].layout.type -ceq $layoutType -and
                (-not $layoutUuid -or $row[0].layout.uuid -ieq $layoutUuid)
        }|Out-Null
    }|Out-Null
}
Set-AcceptanceHorizontalDefault -Name Columns -ExpectedType columns
$before=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'default-layouts.json'
$templates=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'layout-templates.json'
$columns=@($templates.'layout-templates'|Where-Object type -CEQ columns)
if($columns.Count -ne 1){throw 'Template model is not unique.'}
$requested=if($columns[0].'zone-count' -eq 3){4}else{3}
$prediction=ConvertFrom-PtReportJson ($before|ConvertTo-Json -Depth 20)
$references=@($prediction.'default-layouts'|Where-Object {$_.layout.type -ceq 'columns'})
if(-not $references.Count){throw 'Referencing-default prerequisite was not established.'}
foreach($reference in $references){$reference.layout.'zone-count'=$requested}
Set-PtFancyZonesCaseZoneCount -Template Columns -Count $requested
$actualDefaults=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'default-layouts.json'
$actualTemplates=Get-PtFancyZonesSnapshotJson $FzCase.Driver.ExpectedModule 'layout-templates.json'
$actualColumns=@($actualTemplates.'layout-templates'|Where-Object type -CEQ columns)
$matches=$actualColumns.Count -eq 1 -and $actualColumns[0].'zone-count' -eq $requested -and
    (Test-PtFancyZonesJsonEqual $prediction $actualDefaults)
$detail=Case-Proof $Attempt 'linked-default-persistence' @{
    RequestedCount=$requested;TemplateCount=$actualColumns[0].'zone-count'
    ReferencingOrientations=@($references.'monitor-configuration')
    ExactPredictedDefaultDocumentMatches=(Test-PtFancyZonesJsonEqual $prediction $actualDefaults)
}
Record-CaseCondition -Attempt $Attempt -ConditionId 'persistence.linked-default:off' -Category product -Executed $true `
    -Verdict $(if($matches){'PASS'}else{'FAIL'}) -Actual "Template and all referencing defaults reached count $requested; complete predicted default document matches=$matches." -Evidence @($detail)
$owned=Copy-PtFancyZonesCaseTemplate Columns
Set-AcceptanceHorizontalDefault -Name $owned.name -ExpectedType custom -ExpectedUuid $owned.uuid
Close-PtFancyZonesEditor $FzCase.Driver
Open-PtFancyZonesEditor $FzCase.Driver|Out-Null
$observation=Save-PtFancyZonesDefaultEvidence -Attempt $Attempt -LayoutId $owned.uuid -Orientation Horizontal
$matches=$observation.Selected -and $observation.ControlId -ceq 'HorizontalDefaultLayoutButton'
Record-CaseCondition -Attempt $Attempt -ConditionId 'persistence.control-crop:off' -Category product -Executed $true `
    -Verdict $(if($matches){'PASS'}else{'FAIL'}) -Actual "Reopened owned default selected=$($observation.Selected); exact captured control=$($observation.ControlId)." `
    -Evidence $observation.Evidence -Detail @{ControlId=$observation.ControlId;Selected=$observation.Selected;OwnedLayoutId=$owned.uuid}
