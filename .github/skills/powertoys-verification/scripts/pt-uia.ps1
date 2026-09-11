# Scoped control operations. No foreground/input injection or product verdicts are inferred.
if (-not (Get-Command Get-PtNativeWindow -ErrorAction Ignore)) { . "$PSScriptRoot\pt-desktop.ps1" }

function Initialize-PtUiAutomation {
    if (-not ('Windows.Automation.AutomationElement' -as [type])) {
        Add-Type -AssemblyName WindowsBase, UIAutomationClient, UIAutomationTypes -ErrorAction Stop
    }
}

function Select-PtUniqueUiElement {
    <# .SYNOPSIS
    Deduplicate actual runtime identities; distinct same-caption controls remain ambiguous.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Elements,
        [Parameter(Mandatory)][string]$Description)
    $byId = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($element in $Elements) {
        $runtime = @($element.GetRuntimeId())
        if (-not $runtime.Count) {
            $error=[InvalidOperationException]::new("UIA runtime identity unavailable: $Description")
            $error.Data['PtUiResolutionStatus']='ReadError'
            throw $error
        }
        $id = $runtime -join ','
        if (-not $byId.ContainsKey($id)) { $byId.Add($id, $element) }
    }
    if ($byId.Count -ne 1) {
        $error=[InvalidOperationException]::new("Expected one UIA identity for $Description; found $($byId.Count) distinct elements ($($Elements.Count) exposed).")
        $error.Data['PtUiResolutionStatus']=if($byId.Count){'Ambiguous'}else{'Missing'}
        throw $error
    }
    @($byId.Values)[0]
}

function Resolve-PtUiElement {
    <# .SYNOPSIS
    Resolve an exact AutomationId or name plus type within a native window or explicit container.
    #>
    [CmdletBinding(DefaultParameterSetName='AutomationId')]
    param([Parameter(Mandatory)][long]$Hwnd,
        [Parameter(Mandatory,ParameterSetName='AutomationId')][string]$AutomationId,
        [Parameter(Mandatory,ParameterSetName='Name')][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ComboBox','Button','Edit','Tab','TabItem','List','ListItem','Pane','Group','Text','Document','Custom','Hyperlink','CheckBox','RadioButton','Tree','TreeItem','Window','Slider','Spinner','ProgressBar')][string]$ControlType,
        [string]$WithinAutomationId)
    Initialize-PtUiAutomation
    $null = Get-PtNativeWindow -Hwnd $Hwnd
    $root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
    if ($WithinAutomationId) {
        $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,$WithinAutomationId)
        $root = Select-PtUniqueUiElement -Elements @($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)) -Description "container $WithinAutomationId"
    }
    $property = if($PSCmdlet.ParameterSetName -eq 'Name'){[Windows.Automation.AutomationElement]::NameProperty}else{[Windows.Automation.AutomationElement]::AutomationIdProperty}
    $value = if($PSCmdlet.ParameterSetName -eq 'Name'){$Name}else{$AutomationId}
    $idCondition = [Windows.Automation.PropertyCondition]::new($property,$value)
    $typeCondition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::$ControlType)
    $condition = [Windows.Automation.AndCondition]::new($idCondition,$typeCondition)
    Select-PtUniqueUiElement -Elements @($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition)) -Description "$ControlType $value in HWND $Hwnd"
}

function Get-PtComboBoxSelection {
    <# .SYNOPSIS
    Read SelectionPattern or actual ValuePattern; never substitute an accessible name.
    #>
    param([Parameter(Mandatory)]$Element)
    $pattern = $null
    if ($Element.TryGetCurrentPattern([Windows.Automation.SelectionPattern]::Pattern,[ref]$pattern)) {
        return @($pattern.Current.GetSelection() | ForEach-Object { $_.Current.Name })
    }
    if ($Element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$pattern)) {
        return @($pattern.Current.Value)
    }
    throw 'ComboBox SelectionPattern and ValuePattern are unsupported; selected value was not observed.'
}

function Select-PtComboBoxItem {
    <#
    .SYNOPSIS
    Expand a scoped ComboBox, select one runtime-unique option and verify actual selection.
    .NOTES
    Caller owns restoration of the original selection. This helper only closes the popup it opens.
    Returns Requested/Before/Actual/runtime identities, not a product PASS.
    #>
    [CmdletBinding(DefaultParameterSetName='AutomationId')]
    param(
        [Parameter(Mandatory)][long]$Hwnd,
        [Parameter(Mandatory,ParameterSetName='AutomationId')][string]$AutomationId,
        [Parameter(Mandatory,ParameterSetName='ControlName')][string]$ControlName,
        [Parameter(Mandatory)][string]$ItemName,
        [string]$WithinAutomationId,
        [ValidateRange(0.1,30)][double]$TimeoutSeconds = 4,
        [switch]$SkipRecording
    )
    $byName=$PSCmdlet.ParameterSetName -eq 'ControlName'
    $label=if($byName){$ControlName}else{$AutomationId}
    $selector=if($byName){@{Name=$ControlName}}else{@{AutomationId=$AutomationId}}
    $parameter=if($byName){'ControlName'}else{'AutomationId'}
    if (-not $SkipRecording -and (Get-Command Get-PtActiveVerificationAttempt -ErrorAction Ignore)) {
        $attempt = Get-PtActiveVerificationAttempt
        if ($attempt) {
            return Invoke-PtVerificationStep $attempt -Name 'Select ComboBox option' `
                -Command "Select-PtComboBoxItem -Hwnd $Hwnd -$parameter '$($label.Replace("'","''"))' -ItemName '$($ItemName.Replace("'","''"))' -WithinAutomationId '$($WithinAutomationId.Replace("'","''"))'" `
                -Implementation ${function:Select-PtComboBoxItem} -ArgumentList @($Hwnd,$label,$ItemName,$WithinAutomationId,$TimeoutSeconds,$parameter) -Action {
                    param($window,$control,$option,$container,$timeout,$property)
                    $selectionArgs=@{$property=$control}
                    Select-PtComboBoxItem -Hwnd $window @selectionArgs -ItemName $option -WithinAutomationId $container -TimeoutSeconds $timeout -SkipRecording
                }
        }
    }
    Initialize-PtUiAutomation
    $native = Get-PtNativeWindow -Hwnd $Hwnd
    if (-not $native.Visible -or $native.Minimized) { throw 'Target window is hidden or minimized; explicitly activate it before selecting a ComboBox.' }
    $combo = Resolve-PtUiElement -Hwnd $Hwnd @selector -ControlType ComboBox -WithinAutomationId $WithinAutomationId
    if (-not $combo.Current.IsEnabled -or $combo.Current.IsOffscreen) { throw "ComboBox $label is disabled or offscreen." }
    $before = @(Get-PtComboBoxSelection $combo)
    $result = [ordered]@{ Hwnd=$Hwnd; ProcessId=$native.ProcessId; Control=$label; SelectorProperty=$parameter; Requested=$ItemName
        Before=$before; Actual=$before; Changed=$false; ComboRuntimeId=@($combo.GetRuntimeId()); OptionRuntimeId=@() }
    if ($before.Count -eq 1 -and $before[0] -ceq $ItemName) { return [pscustomobject]$result }
    $expand = $null
    if (-not $combo.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$expand)) {
        throw "ComboBox $label cannot be expanded through its supported UIA patterns."
    }
    $opened = $false
    $original = $null
    try {
        if ($expand.Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Expanded) {
            $expand.Expand()
            $opened = $true
        }
        $option = Wait-PtCondition -Description "realized option '$ItemName' in $label" -TimeoutSeconds $TimeoutSeconds -Probe {
            $root = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
            $condition = [Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::NameProperty,$ItemName)
            $descendants = @($combo.FindAll([Windows.Automation.TreeScope]::Descendants,$condition) | Where-Object {
                $_.Current.ControlType -eq [Windows.Automation.ControlType]::ListItem -and -not $_.Current.IsOffscreen
            })
            if ($descendants.Count) { return Select-PtUniqueUiElement -Elements $descendants -Description "$ItemName inside $label" }
            $candidates = @($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition) | Where-Object {
                $_.Current.ControlType -eq [Windows.Automation.ControlType]::ListItem -and -not $_.Current.IsOffscreen
            })
            $scoped = @(foreach ($candidate in $candidates) {
                $selection = $null
                if ($candidate.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$selection)) {
                    $container = $selection.Current.SelectionContainer
                    if ($container -and (@($container.GetRuntimeId()) -join ',') -ceq ($result.ComboRuntimeId -join ',')) { $candidate }
                }
            })
            if ($scoped.Count) { Select-PtUniqueUiElement -Elements $scoped -Description "$ItemName owned by $label" }
        }
        if (-not $option.Current.IsEnabled) { throw "Option '$ItemName' is disabled." }
        $result.OptionRuntimeId = @($option.GetRuntimeId())
        $selection = $option.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
        $selection.Select()
        $actual = @(Wait-PtCondition -Description "selection '$ItemName' readback from $label" -TimeoutSeconds $TimeoutSeconds -Probe {
            $value = @(Get-PtComboBoxSelection $combo)
            if ($value.Count -eq 1 -and $value[0] -ceq $ItemName) { $value[0] }
        })
        $result.Actual = $actual
        $result.Changed = $true
        [pscustomobject]$result
    } catch { $original = $_; throw }
    finally {
        if ($opened) {
            try {
                if ($expand.Current.ExpandCollapseState -eq [Windows.Automation.ExpandCollapseState]::Expanded) { $expand.Collapse() }
            } catch {
                if ($original) {
                    $original.Exception.Data['PopupCleanupFailure'] = $_.Exception.Message
                    [Console]::Error.WriteLine("Popup cleanup failed: $($_.Exception.Message)")
                } else { throw }
            }
        }
    }
}
