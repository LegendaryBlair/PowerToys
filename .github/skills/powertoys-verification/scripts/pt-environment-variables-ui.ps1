# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license. See LICENSE in the project root.

<#
.SYNOPSIS
Environment Variables row, draft and private observation adapters.
.NOTES
Call live functions inside an outer recorded step. Trees and text stay private; publish only
Compare-PtEnvUiValue receipts. No product verdict, retry of a write, registry change or
implicit product restart. Resolve targets afresh with the common window identity APIs.
#>
foreach ($dependency in 'pt-environment-variables-state','pt-ui-observation','pt-session-safety') {
    . "$PSScriptRoot\$dependency.ps1"
}

function Stop-PtEnvUiOperation {
    param([string]$Status, [string]$Operation)
    $error = [InvalidOperationException]::new("Environment UI ${Status}: $Operation. Private provider payload withheld.")
    $error.Data['PtEnvUiStatus'] = $Status
    throw $error
}

function Get-PtEnvUiChildren {
    param($Node)
    if ($Node -is [Collections.IList]) { $Node; return }
    foreach ($field in 'windows','children','elements') {
        if ($Node -and $Node.PSObject.Properties[$field]) { $Node.$field }
    }
}

function Get-PtEnvUiDescendants {
    param($Node)
    if ($null -eq $Node) { return }
    if ($Node -is [Collections.IList]) {
        foreach ($child in $Node) { Get-PtEnvUiDescendants $child }
    } else {
        if ($Node.PSObject.Properties['type']) { $Node }
        foreach ($child in @(Get-PtEnvUiChildren $Node)) { Get-PtEnvUiDescendants $child }
    }
}

function Select-PtEnvUiNode {
    param([AllowEmptyCollection()][object[]]$Nodes, [switch]$Visible)
    $unique = [Collections.Generic.List[object]]::new()
    $references = [Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    $runtimeIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($node in $Nodes) {
        if ($Visible) {
            if ($node.isOffscreen -isnot [bool]) { Stop-PtEnvUiOperation Incomplete 'Visibility not exposed' }
            if ($node.isOffscreen) { continue }
        }
        if ([string]::IsNullOrWhiteSpace($node.selector)) { Stop-PtEnvUiOperation Incomplete 'Runtime selector missing' }
        if (-not $references.Add($node)) { continue }
        if ($node.PSObject.Properties['runtimeId'] -and @($node.runtimeId).Count) {
            if (-not $runtimeIds.Add((@($node.runtimeId) -join ','))) { continue }
        }
        $unique.Add($node)
    }
    if ($unique.Count -ne 1) {
        Stop-PtEnvUiOperation $(if ($unique.Count) { 'Ambiguous' } else { 'Missing' }) 'Unique scoped control required'
    }
    $unique[0]
}

function Read-PtEnvPrivateTree {
    param([Parameter(Mandatory)]$Target)
    Assert-PtUiObservationTarget $Target
    try {
        $raw = Invoke-PtWinApp -Arguments @('inspect','--depth','20','-w',"$($Target.hwnd)",'--json') -SkipRecording
        $tree = ConvertFrom-PtReportJson $raw
    } catch { Stop-PtEnvUiOperation ReadError 'Inspect target' }
    Assert-PtUiObservationTarget $Target
    if (-not @(Get-PtEnvUiDescendants $tree).Count) { Stop-PtEnvUiOperation Incomplete 'Empty provider tree' }
    $tree
}

function Resolve-PtEnvUiRow {
    <#.SYNOPSIS
    Resolve an exact variable in an explicit group, or an exact profile; no tree output is evidence.
    #>
    param([Parameter(Mandatory)]$Tree,
        [Parameter(Mandatory)][ValidateSet('User','System','Profile','ProfileVariable')][string]$Scope,
        [Parameter(Mandatory)][string]$Name, [string]$ProfileName)
    $nodes = @(Get-PtEnvUiDescendants $Tree)
    if ($Scope -in 'Profile','ProfileVariable') {
        $owner = if ($Scope -eq 'Profile') { $Name } else { $ProfileName }
        if ([string]::IsNullOrWhiteSpace($owner)) { Stop-PtEnvUiOperation InvalidInput 'Profile name required' }
        $container = Select-PtEnvUiNode @($nodes | Where-Object {
            $_.className -ceq 'SettingsExpander' -and $_.name -ceq $owner
        }) -Visible
        if ($Scope -eq 'Profile') { return $container }
    } else {
        $id = switch ($Scope) { User {'UserVariablesExpander'} System {'SystemVariablesExpander'} }
        $container = Select-PtEnvUiNode @($nodes | Where-Object automationId -CEQ $id) -Visible
    }
    $rows = @(Get-PtEnvUiDescendants $container | Where-Object {
        -not [object]::ReferenceEquals($_,$container) -and $_.className -ceq 'SettingsCard' -and
        @(Get-PtEnvUiDescendants $_ | Where-Object {
            $_.type -ceq 'Text' -and [string]::Equals($_.name,$Name,[StringComparison]::OrdinalIgnoreCase)
        }).Count -eq 1
    })
    Select-PtEnvUiNode $rows
}

function Resolve-PtEnvUiMenu {
    <#.SYNOPSIS
    Select the one visible enabled menu item, not a cached hidden peer with the same ID.
    #>
    param([Parameter(Mandatory)]$Tree, [Parameter(Mandatory)][string]$AutomationId)
    $node = Select-PtEnvUiNode @(Get-PtEnvUiDescendants $Tree | Where-Object {
        $_.type -ceq 'MenuItem' -and $_.automationId -ceq $AutomationId
    }) -Visible
    if ($node.isEnabled -cne $true) { Stop-PtEnvUiOperation Disabled 'Menu action unavailable' }
    $node
}

function Invoke-PtEnvPrivateAction {
    param($Target, [ValidateSet('invoke','set-value','get-value','scroll-into-view')][string]$Verb,
        [string]$Selector, [AllowEmptyString()][string]$Text)
    Assert-PtUiObservationTarget $Target
    $arguments = @($Verb,$Selector)
    if ($Verb -eq 'set-value') { $arguments += $Text }
    $arguments += @('-w',"$($Target.hwnd)")
    if ($Verb -eq 'get-value') { $arguments += '--json' }
    try { $result = Invoke-PtWinApp -Arguments $arguments -SkipRecording }
    catch { Stop-PtEnvUiOperation ActionError "Private $Verb operation" }
    Assert-PtUiObservationTarget $Target
    if ($Verb -eq 'get-value') {
        try { $value = ConvertFrom-PtReportJson $result }
        catch { Stop-PtEnvUiOperation ReadError 'Invalid value response' }
        if ($value.text -isnot [string]) { Stop-PtEnvUiOperation Incomplete 'Text property not exposed' }
        return $value.text
    }
}

function Open-PtEnvOwnedMenu {
    <#.SYNOPSIS
    Open one owned row/profile menu. Profile ownership is supplied by the caller's fixture.
    .NOTES
    For a variable, its journal resource is mandatory. Returns no cached control for later actions.
    #>
    [CmdletBinding(DefaultParameterSetName='Variable')]
    param([Parameter(Mandatory)]$Target,
        [Parameter(Mandatory,ParameterSetName='Variable')][string]$JournalPath,
        [Parameter(Mandatory,ParameterSetName='Variable')][string]$ResourceId,
        [Parameter(ParameterSetName='Variable')][string]$ProfileName,
        [Parameter(Mandatory,ParameterSetName='Profile')][string]$OwnedProfileName)
    $tree = Read-PtEnvPrivateTree $Target
    if (@(Get-PtEnvUiDescendants $tree | Where-Object {
        ($_.className -eq 'Popup' -and $_.type -eq 'Window' -or $_.automationId -in
            'ProfileNameTextBox','EditVariableDialogNameTxtBox','DefaultVariableNameTextBox','AddNewVariableName') -and $_.isOffscreen -eq $false
    }).Count) { Stop-PtEnvUiOperation WrongState 'Close the explicit owned modal before opening a row menu' }
    if ($PSCmdlet.ParameterSetName -eq 'Profile') {
        $row = Resolve-PtEnvUiRow $tree Profile $OwnedProfileName
        $buttonId = 'ProfileOptionsButton'
    } else {
        $resource = (Read-PtEnvJournal $JournalPath).Resources[$ResourceId]
        if (-not $resource -or $resource.Type -ne 'UserVariable') { Stop-PtEnvUiOperation InvalidInput 'Registered variable required' }
        $scope = if ($ProfileName) { 'ProfileVariable' } else { 'User' }
        $row = Resolve-PtEnvUiRow $tree $scope $resource.Name -ProfileName $ProfileName
        $buttonId = 'VariableOptionsButton'
    }
    $button = Select-PtEnvUiNode @(Get-PtEnvUiDescendants $row | Where-Object automationId -CEQ $buttonId)
    if ($button.isOffscreen -eq $true) {
        Invoke-PtEnvPrivateAction $Target scroll-into-view $button.selector
        $tree = Read-PtEnvPrivateTree $Target
        $row = if ($PSCmdlet.ParameterSetName -eq 'Profile') { Resolve-PtEnvUiRow $tree Profile $OwnedProfileName }
            else { Resolve-PtEnvUiRow $tree $scope $resource.Name -ProfileName $ProfileName }
    }
    $button = Select-PtEnvUiNode @(Get-PtEnvUiDescendants $row | Where-Object automationId -CEQ $buttonId) -Visible
    if ($button.isEnabled -cne $true) { Stop-PtEnvUiOperation Disabled 'Owned row options unavailable' }
    Invoke-PtEnvPrivateAction $Target invoke $button.selector
    [pscustomobject]@{ Action='OpenOwnedMenu'; Invoked=$true; ProductOutcome='NotObserved' }
}

function Invoke-PtEnvMenuAction {
    param([Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][ValidateSet('EditVariableMenuItem','RemoveVariableMenuItem','EditProfileMenuItem','RemoveProfileMenuItem')][string]$AutomationId)
    $node = Resolve-PtEnvUiMenu (Read-PtEnvPrivateTree $Target) $AutomationId
    Invoke-PtEnvPrivateAction $Target invoke $node.selector
    [pscustomobject]@{ Action=$AutomationId; Invoked=$true; ProductOutcome='NotObserved' }
}

function Get-PtEnvDraftLayout {
    param([ValidateSet('AddVariable','EditVariable','Profile','ProfileVariable','Confirmation')][string]$Kind)
    switch ($Kind) {
        AddVariable { @{Name='DefaultVariableNameTextBox';Value='DefaultVariableValueTextBox';Commit='PrimaryButton';Cancel='SecondaryButton'} }
        EditVariable { @{Name='EditVariableDialogNameTxtBox';Value='EditVariableDialogValueTxtBox';Commit='PrimaryButton';Cancel='SecondaryButton'} }
        Profile { @{Name='ProfileNameTextBox';Value=$null;Commit='PrimaryButton';Cancel='SecondaryButton'} }
        ProfileVariable { @{Name='AddNewVariableName';Value='AddNewVariableValue';Commit='ConfirmAddVariableBtn';Cancel='CancelAddVariableBtn'} }
        Confirmation { @{Name=$null;Value=$null;Commit='PrimaryButton';Cancel='CloseButton'} }
    }
}

function Resolve-PtEnvDraft {
    param([Parameter(Mandatory)]$Tree,
        [Parameter(Mandatory)][ValidateSet('AddVariable','EditVariable','Profile','ProfileVariable','Confirmation')][string]$Kind,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ExpectedName)
    $layout = Get-PtEnvDraftLayout $Kind
    $nodes = @(Get-PtEnvUiDescendants $Tree)
    if ($Kind -ne 'ProfileVariable' -and @($nodes | Where-Object {
        $_.automationId -ceq 'ConfirmAddVariableBtn' -and $_.isOffscreen -eq $false
    }).Count) { Stop-PtEnvUiOperation WrongState 'An inner profile-variable flyout is still open' }
    if ($Kind -eq 'Confirmation') {
        $root = Select-PtEnvUiNode @($nodes | Where-Object {
            $_.type -ceq 'Window' -and $_.className -ceq 'Popup' -and $_.name -ceq $ExpectedName
        }) -Visible
    } else {
        $field = Select-PtEnvUiNode @($nodes | Where-Object automationId -CEQ $layout.Name) -Visible
        # Smallest ancestor exposing both the draft name and its own commit control.
        $candidates = @(foreach ($node in $nodes) {
            $desc = @(Get-PtEnvUiDescendants $node)
            if (@($desc | Where-Object {[object]::ReferenceEquals($_,$field)}).Count -and @($desc | Where-Object {
                $_.automationId -ceq $layout.Commit -and $_.isOffscreen -eq $false
            }).Count) { [pscustomobject]@{Node=$node;Count=$desc.Count} }
        })
        if (-not $candidates.Count) { Stop-PtEnvUiOperation Incomplete 'Draft container not exposed' }
        $size = ($candidates | Measure-Object Count -Minimum).Minimum
        $roots = @($candidates | Where-Object Count -EQ $size | ForEach-Object Node)
        if ($roots.Count -ne 1) { Stop-PtEnvUiOperation Ambiguous 'Draft structural ancestry differs' }
        $root = $roots[0]
    }
    $desc = @(Get-PtEnvUiDescendants $root)
    $commit = Select-PtEnvUiNode @($desc | Where-Object automationId -CEQ $layout.Commit) -Visible
    $cancel = Select-PtEnvUiNode @($desc | Where-Object automationId -CEQ $layout.Cancel) -Visible
    [pscustomobject]@{Kind=$Kind;Root=$root;Name=$(if ($layout.Name) {
        Select-PtEnvUiNode @($desc | Where-Object automationId -CEQ $layout.Name) -Visible
    });Value=$(if ($layout.Value) {
        Select-PtEnvUiNode @($desc | Where-Object automationId -CEQ $layout.Value) -Visible
    });Commit=$commit;Cancel=$cancel}
}

function Read-PtEnvDraft {
    <#.SYNOPSIS
    Read an explicitly selected live owned draft. Contains private text; do not archive raw output.
    #>
    param([Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][ValidateSet('AddVariable','EditVariable','Profile','ProfileVariable','Confirmation')][string]$Kind,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ExpectedName)
    $draft = Resolve-PtEnvDraft (Read-PtEnvPrivateTree $Target) $Kind $ExpectedName
    $name = if ($draft.Name) { Read-PtEnvDraftText $Target $draft.Name } else { $ExpectedName }
    if ($name -cne $ExpectedName) { Stop-PtEnvUiOperation WrongTarget 'Draft name differs; no input permitted' }
    $value = if ($draft.Value) { Read-PtEnvDraftText $Target $draft.Value } else { $null }
    if ($draft.Commit.isEnabled -isnot [bool]) { Stop-PtEnvUiOperation Incomplete 'Commit state not exposed' }
    [pscustomobject]@{Kind=$Kind;Name=$name;Value=$value;CommitEnabled=$draft.Commit.isEnabled;Draft=$draft}
}

function Read-PtEnvDraftText {
    param($Target,$Node)
    Assert-PtUiObservationTarget $Target
    try {
        $element = Resolve-PtUiElement -Hwnd $Target.hwnd -AutomationId $Node.automationId -ControlType Edit
        $value = $element.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value
    } catch { Stop-PtEnvUiOperation ReadError 'Read draft ValuePattern, without accessible-name fallback' }
    Assert-PtUiObservationTarget $Target
    if ($value -isnot [string]) { Stop-PtEnvUiOperation Incomplete 'Draft text is not exposed' }
    $value
}

function Set-PtEnvDraftField {
    <#.SYNOPSIS
    Set one guarded draft field once and return actual readback, including rejected/truncated input.
    .NOTES
    Caller supplies owned fixture names and synthetic text; this does not save or infer validation PASS.
    #>
    param([Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][ValidateSet('AddVariable','EditVariable','Profile','ProfileVariable')][string]$Kind,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ExpectedName,
        [Parameter(Mandatory)][ValidateSet('Name','Value')][string]$Field,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $before = Read-PtEnvDraft $Target $Kind $ExpectedName
    $node = $before.Draft.$Field
    if (-not $node) { Stop-PtEnvUiOperation InvalidInput 'This draft has no requested field' }
    Assert-PtUiObservationTarget $Target
    try {
        $element = Resolve-PtUiElement -Hwnd $Target.hwnd -AutomationId $node.automationId -ControlType Edit
        if ($element.Current.IsOffscreen -or -not $element.Current.IsEnabled) { Stop-PtEnvUiOperation WrongState 'Draft field not interactive' }
        $pattern = $element.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
        $pattern.SetValue($Text)
        $actual = $pattern.Current.Value
    } catch { Stop-PtEnvUiOperation ActionError 'Set draft field through ValuePattern' }
    Assert-PtUiObservationTarget $Target
    if ($actual -isnot [string]) { Stop-PtEnvUiOperation Incomplete 'Draft readback unavailable' }
    $nextName = if ($Field -eq 'Name') { $actual } else { $ExpectedName }
    $after = Read-PtEnvDraft $Target $Kind $nextName
    [pscustomobject]@{Kind=$Kind;Field=$Field;Actual=$after.$Field;InputPreserved=($after.$Field -ceq $Text);CommitEnabled=$after.CommitEnabled}
}

function Complete-PtEnvDraft {
    <#.SYNOPSIS
    Explicitly commit or cancel one target-checked draft; never blindly dismiss every modal.
    #>
    param([Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][ValidateSet('AddVariable','EditVariable','Profile','ProfileVariable','Confirmation')][string]$Kind,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ExpectedName,
        [Parameter(Mandatory)][ValidateSet('Commit','Cancel')][string]$Decision)
    $draft = Read-PtEnvDraft $Target $Kind $ExpectedName
    $button = $draft.Draft.$Decision
    if ($button.isEnabled -cne $true) { Stop-PtEnvUiOperation Disabled 'Draft action disabled' }
    Invoke-PtEnvPrivateAction $Target invoke $button.selector
    [pscustomobject]@{Kind=$Kind;Decision=$Decision;Invoked=$true;ProductOutcome='NotObserved'}
}

function Compare-PtEnvUiValue {
    <#.SYNOPSIS
    Create a safe comparison receipt. Absence, incomplete observation and mismatching values differ.
    #>
    param([Parameter(Mandatory)]$Observation, [Parameter(Mandatory)][bool]$ExpectedPresent,
        [AllowNull()][AllowEmptyString()][string]$ExpectedValue)
    if ($Observation.Status -notin 'Observed','Absent','Incomplete') { Stop-PtEnvUiOperation InvalidInput 'Unknown observation status' }
    if ($ExpectedPresent -and -not $PSBoundParameters.ContainsKey('ExpectedValue')) { Stop-PtEnvUiOperation InvalidInput 'Present expectation requires an explicit value' }
    if (($Observation.Status -eq 'Observed' -and $Observation.Present -cne $true) -or
        ($Observation.Status -eq 'Absent' -and $Observation.Present -cne $false)) { Stop-PtEnvUiOperation InvalidInput 'Inconsistent presence status' }
    $match = $null
    if ($Observation.Status -eq 'Absent') { $match = -not $ExpectedPresent }
    elseif ($Observation.Status -eq 'Observed') {
        if ($Observation.Value -isnot [string]) { Stop-PtEnvUiOperation InvalidInput 'Observed value must be text' }
        $match = $ExpectedPresent -and $Observation.Value -ceq $ExpectedValue
    }
    $receipt=[ordered]@{Status=$Observation.Status;Present=$Observation.Present;Complete=($Observation.Status -ne 'Incomplete')
        ExpectedPresent=$ExpectedPresent;Matches=$match;Method=$Observation.Method}
    foreach($field in 'NameLength','ListNameLength'){
        if($Observation.PSObject.Properties[$field]){$receipt[$field]=$Observation.$field}
    }
    [pscustomobject]$receipt
}

function Read-PtEnvAppliedVariable {
    <#.SYNOPSIS
    Read the nonvirtualized Applied name/value TextBlock pairs privately, without CLI text truncation.
    #>
    param([Parameter(Mandatory)]$Target, [Parameter(Mandatory)][string]$Name)
    Assert-PtUiObservationTarget $Target
    try {
        $panel = Resolve-PtUiElement -Hwnd $Target.hwnd -AutomationId AppliedVariablesScrollViewer -ControlType Pane
        $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::Text)
        $texts = @($panel.FindAll([Windows.Automation.TreeScope]::Descendants,$condition) | ForEach-Object { $_.Current.Name })
        $result = ConvertFrom-PtEnvAppliedPairs -Texts $texts -Name $Name
    } catch {
        if ($_.Exception.Data['PtEnvUiStatus']) { throw }
        Stop-PtEnvUiOperation ReadError 'Applied name/value pairs'
    }
    Assert-PtUiObservationTarget $Target
    $result
}

function ConvertFrom-PtEnvAppliedPairs {
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Texts, [Parameter(Mandatory)][string]$Name)
    if (-not $Texts.Count -or $Texts.Count % 2 -ne 0) { Stop-PtEnvUiOperation Incomplete 'Applied text pairs are not complete' }
    $matches = @()
    for ($i=0; $i -lt $Texts.Count; $i+=2) {
        if ($Texts[$i] -isnot [string] -or [string]::IsNullOrWhiteSpace($Texts[$i]) -or $Texts[$i+1] -isnot [string]) {
            Stop-PtEnvUiOperation Incomplete 'Applied pair has an invalid name or value'
        }
        if ([string]::Equals($Texts[$i],$Name,[StringComparison]::OrdinalIgnoreCase)) { $matches += $i }
    }
    if ($matches.Count -gt 1) { Stop-PtEnvUiOperation Ambiguous 'Duplicate Applied names' }
    [pscustomobject]@{Status=$(if ($matches.Count) {'Observed'} else {'Absent'});Present=($matches.Count -eq 1)
        Value=$(if ($matches.Count) {$Texts[$matches[0]+1]} else {$null});Method='Nonvirtualized Applied TextBlock pairs'}
}

function Read-PtEnvPrivateName {
    param($Target,[string]$Selector)
    Assert-PtUiObservationTarget $Target
    try {
        $raw=Invoke-PtWinApp -Arguments @('get-property',$Selector,'--property','Name','-w',"$($Target.hwnd)",'--json') -SkipRecording
        $result=ConvertFrom-PtReportJson $raw
    } catch { Stop-PtEnvUiOperation ReadError 'Native complete Name property' }
    if ($result.properties.Name -isnot [string]) { Stop-PtEnvUiOperation Incomplete 'Native full Name property not exposed' }
    Assert-PtUiObservationTarget $Target
    $result.properties.Name
}

function Resolve-PtEnvNativeList {
    param($Target,[ValidateSet('User','System')][string]$Scope)
    $id=if($Scope -eq 'User'){'402'}else{'400'}
    $list=Wait-PtCondition -Description 'native environment list provider ready' -TimeoutSeconds 5 -Probe {
        $nodes=@(Get-PtEnvUiDescendants (Read-PtEnvPrivateTree $Target)|Where-Object automationId -CEQ $id)
        if($nodes.Count){Select-PtEnvUiNode $nodes -Visible}
    }
    if ($list.className -cne 'SysListView32') { Stop-PtEnvUiOperation Incomplete 'Unexpected native list class' }
    $list
}

function Read-PtEnvNativeRow {
    param($Target,$Creation,$Row,[string]$ListName,[bool]$ExactName)
    $child = $null; $failure = $null; $stage = 'invoke-row'
    try {
        if (-not $Row.isEnabled) { Stop-PtEnvUiOperation Disabled 'Native variable cannot be opened' }
        $before = @(Get-PtNativeWindow -ProcessId $Target.processId -ClassName '#32770' | ForEach-Object Hwnd)
        Invoke-PtEnvPrivateAction $Target invoke $Row.selector
        $stage = 'wait-child'
        $window = Wait-PtCondition -Description 'new owned native variable editor' -TimeoutSeconds 5 -Probe {
            $found = @(Get-PtNativeWindow -ProcessId $Target.processId -ClassName '#32770' -Visible | Where-Object Hwnd -NotIn $before)
            if ($found.Count -gt 1) { Stop-PtEnvUiOperation Ambiguous 'Multiple new native editors' }
            if ($found.Count -eq 1) { $found[0] }
        }
        $child = Get-PtWindowIdentity -Hwnd $window.Hwnd
        Register-PtCreatedWindow -Identity $child -Creation $Creation | Out-Null
        $stage = 'read-child'
        $tree = Read-PtEnvPrivateTree $child
        $edits = @(Get-PtEnvUiDescendants $tree | Where-Object { $_.type -ceq 'Edit' -and $_.isOffscreen -eq $false })
        if ($edits.Count -eq 2) {
            $values = @(foreach ($field in $edits) { Invoke-PtEnvPrivateAction $child get-value $field.selector })
            if ([string]::IsNullOrEmpty($values[0])) { Stop-PtEnvUiOperation Incomplete 'Native Edit name is empty; identity unproven' }
            $actualName = $values[0]; $value = $values[1]; $method = 'Native complete Edit name and value through winapp'
        } else {
            if (-not $ExactName) { Stop-PtEnvUiOperation Incomplete 'Ordered-entry dialog cannot confirm a clipped variable name' }
            $actualName = $ListName
            $lists = @(Get-PtEnvUiDescendants $tree | Where-Object { $_.type -eq 'List' -and $_.isOffscreen -eq $false })
            $pathList = Select-PtEnvUiNode $lists -Visible
            $entries = @(Get-PtEnvUiChildren $pathList | Where-Object type -CEQ ListItem)
            if (-not $entries.Count) { Stop-PtEnvUiOperation Incomplete 'Native ordered entries not exposed' }
            $value = (@(foreach ($entry in $entries) { Read-PtEnvPrivateName $child $entry.selector })) -join ';'
            $method = 'Native ordered entries from selected exact row'
        }
        [pscustomobject]@{Name=$actualName;Value=$value;Method=$method;NameLength=$actualName.Length;ListNameLength=$ListName.Length}
    } catch {
        $status = $_.Exception.Data['PtEnvUiStatus']
        if (-not $status) { $status = $_.Exception.Data['PtUiResolutionStatus'] }
        $frame = ($_.ScriptStackTrace -split "`n")[0]
        $failure = [InvalidOperationException]::new("Environment UI native observation failed at $stage ($($_.Exception.GetType().Name), status=$status, $frame); private provider payload withheld.")
        $failure.Data['PtEnvUiStatus'] = if ($status) { $status } else { 'ReadError' }
        throw $failure
    } finally {
        if ($child) {
            try {
                $cancel = Select-PtEnvUiNode @(Get-PtEnvUiDescendants (Read-PtEnvPrivateTree $child) |
                    Where-Object { $_.type -ceq 'Button' -and $_.automationId -ceq '2' }) -Visible
                Assert-PtUiObservationTarget $child
                Invoke-PtWinApp -Arguments @('invoke',$cancel.selector,'-w',"$($child.hwnd)") -SkipRecording | Out-Null
                Wait-PtCondition -Description 'native child canceled without saving' -TimeoutSeconds 5 -Probe {
                    -not @(Get-PtNativeWindow -ProcessId $child.processId -ClassName $child.className |
                        Where-Object Hwnd -EQ $child.hwnd).Count
                } | Out-Null
            } catch {
                if ($failure) {
                    $failure.Data['NativeCleanupFailure'] = 'Native child cancellation failed; retain owned window for cleanup.'
                } else { Stop-PtEnvUiOperation CleanupError 'Native child cancellation failed; retain owned window for cleanup' }
            }
        }

    }
}

function Read-PtEnvNativeVariable {
    <#.SYNOPSIS
    Read one native User/System variable, confirming clipped list names in a canceled Edit dialog.
    .NOTES
    Requires a registered owned dedicated native dialog. Each candidate is read without saving.
    Never substitute registry data, expected text, or a prefix match for the actual full name.
    #>
    param([Parameter(Mandatory)]$Target, [Parameter(Mandatory)]$Creation,
        [Parameter(Mandatory)][string]$Name, [ValidateSet('User','System')][string]$Scope='User')
    Assert-PtUiObservationTarget $Target
    $session = Get-PtActiveResourceSession
    if (-not $session -or $Creation.ProcessId -ne $Target.processId) { Stop-PtEnvUiOperation WrongTarget 'Owned native creation required' }
    $owned = @($session.Windows | Where-Object { $_.Identity.hwnd -eq $Target.hwnd -and $_.Ownership -eq 'Owned' })
    if ($owned.Count -ne 1 -or $Creation.ProcessStartTicks -ne $Target.processStartTicks -or $owned[0].Creation -cne $Creation.Id) {
        Stop-PtEnvUiOperation WrongTarget 'Native window/creation identity differs'
    }
    $list = Resolve-PtEnvNativeList $Target $Scope
    $rows = @(Get-PtEnvUiDescendants $list|Where-Object type -CEQ ListItem)
    if (-not $rows.Count) { Stop-PtEnvUiOperation Incomplete 'Native row provider has no observed item peers' }
    $candidates = @(foreach($row in $rows){
        $listName=Read-PtEnvPrivateName $Target $row.selector
        if ([string]::IsNullOrEmpty($listName)) { Stop-PtEnvUiOperation Incomplete 'Native row name unavailable' }
        $prefix=$listName.TrimEnd([char]0x2026).TrimEnd('.')
        $exact=[string]::Equals($listName,$Name,[StringComparison]::OrdinalIgnoreCase)
        if ($exact -or ($Name.Length -gt 259 -and $prefix.Length -gt 0 -and $Name.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase))) {
            [pscustomobject]@{Row=$row;Name=$listName;Exact=$exact}
        }
    })
    $exactCandidates=@($candidates|Where-Object Exact)
    if($exactCandidates.Count){$candidates=$exactCandidates}
    $observations = @(foreach($candidate in $candidates){
        $actual=Read-PtEnvNativeRow $Target $Creation $candidate.Row $candidate.Name $candidate.Exact
        if ([string]::Equals($actual.Name,$Name,[StringComparison]::OrdinalIgnoreCase)) { $actual }
        elseif ($candidate.Exact) { Stop-PtEnvUiOperation WrongTarget 'Native identity changed between list and Edit dialog' }
    })
    if ($observations.Count -gt 1) { Stop-PtEnvUiOperation Ambiguous 'Multiple native full names match' }
    if (-not $observations.Count) {
        return [pscustomobject]@{Status='Absent';Present=$false;Value=$null;Method='Native name enumeration with prefix candidates independently checked'}
    }
    [pscustomobject]@{Status='Observed';Present=$true;Value=$observations[0].Value;Method=$observations[0].Method
        NameLength=$observations[0].NameLength;ListNameLength=$observations[0].ListNameLength}
}
