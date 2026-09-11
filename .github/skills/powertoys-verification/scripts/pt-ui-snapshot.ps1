#requires -Version 7.2

function Test-PtUiSnapshot {
    <#
    .SYNOPSIS
    Assess structural landmarks in an already-parsed winapp inspect snapshot, without I/O.
    .DESCRIPTION
    Accepts windows[].elements[] with optional nested children[]; objects may be
    PSCustomObject or IDictionary. Arrays must be actual one-dimensional arrays.
    Each selected window needs a positive integer hwnd (a decimal string is also accepted).
    A multi-window capture requires WindowHwnd. Only the selected window's elements are assessed.

    RequiredLandmarks is a nonempty array of objects with Id, ControlType, exactly one
    AutomationId or Name, and optional WithinAutomationId. No other contract fields are allowed.
    Labels and selector values are case-sensitive. Field names and control types are
    case-insensitive; both Edit and ControlType.Edit are accepted. WithinAutomationId
    means any matching strict ancestor, not the element itself or a sibling.

    Node type is read from type or controlType; if both occur they must agree.
    winapp's captured Unknown(50025) spelling is recognized as UIA Custom.
    Captured name/automationId may be missing, null or empty; these do not match a
    required nonempty selector. Other non-string selector values are malformed.
    Capture filters, depth and elementCount are metadata, not readiness/enumeration gates.
    Omitted children means no further realized children were supplied, not full enumeration.
    A present children field must be an array, including [] for an empty container.
    Runtime IDs may be Int32-component arrays or decimal components separated by commas
    or dots. Missing IDs and empty arrays have no established runtime identity.
    Repeated nonempty runtime identities are deduplicated per landmark, never by caption
    or AutomationId; their children are still assessed.

    Truncation indicators checked on the envelope, selected window and every selected node:
    truncated, isTruncated, childrenTruncated, depthLimitReached, nodeLimitReached,
    maxDepthReached, maxNodesReached, hasMoreChildren, hasMore, partial, isPartial, incomplete.
    These must be booleans and false. complete/isComplete must be booleans and true.

    Returns one object: usableForContract, status, missingLandmarks (Id[]),
    landmarkCounts ({id, occurrenceCount, rawOccurrenceCount, withoutRuntimeIdCount}[]),
    dataScope, reason, nodeCount, warnings (string[]), diagnostics.
    diagnostics contains evaluationComplete, selectedWindowHwnd, location,
    nodesWithoutRuntimeId and duplicateRuntimeIdOccurrences.
    Counts are null and missingLandmarks is empty if evaluationComplete is false.
    nodeCount counts inspected object occurrences, including duplicate wrappers, up to MaxNodes.
    Counts describe realized occurrences, never business rows. Even Usable proves neither
    full enumeration, visibility, rendered pixels nor the absence of virtualized rows.

    Invalid API arguments throw ArgumentException. Bad captured data returns an explicit
    unusable status: MalformedSnapshot, UnsupportedShape, IncompleteSnapshot,
    AmbiguousWindow, WindowNotFound, MissingWindowHwnd, CycleDetected or NodeLimitExceeded.
    A completed assessment returns Usable or MissingLandmarks, not a product verdict.
    .EXAMPLE
    $contract = @(
        @{ Id='query'; ControlType='Edit'; AutomationId='SearchBox' },
        @{ Id='results'; ControlType='List'; AutomationId='Results'; WithinAutomationId='Page' }
    )
    Test-PtUiSnapshot -Tree $parsedInspectJson -RequiredLandmarks $contract -WindowHwnd 123L
    # An observable, empty Results list satisfies this structural contract.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Tree,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()]$RequiredLandmarks,
        $WindowHwnd,
        $MaxNodes = 20000
    )

    function Stop-PtSnapshotData([string]$Status, [string]$Location, [string]$Reason) {
        $exception = [IO.InvalidDataException]::new($Reason)
        $exception.Data['PtSnapshotStatus'] = $Status
        $exception.Data['PtSnapshotLocation'] = $Location
        throw $exception
    }

    function Read-PtSnapshotObject($Value, [string]$Location, [switch]$Contract) {
        $problem = $null
        $map = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($Value -is [Collections.IDictionary]) {
            foreach ($key in $Value.Keys) {
                if ($key -isnot [string] -or -not $map.TryAdd($key, $Value[$key])) {
                    $problem = 'JSON object fields must be strings with no case-duplicate names.'
                    break
                }
            }
        } elseif ($Value -is [pscustomobject]) {
            foreach ($property in $Value.PSObject.Properties) {
                if ($property.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty) {
                    $problem = 'Only parsed JSON data properties are supported.'
                    break
                }
                if (-not $map.TryAdd($property.Name, $property.Value)) {
                    $problem = 'JSON object fields must have no case-duplicate names.'
                    break
                }
            }
        } else {
            $problem = 'Expected a parsed JSON object (PSCustomObject or IDictionary).'
        }
        if ($null -ne $problem) {
            if ($Contract) { throw [ArgumentException]::new($problem, 'RequiredLandmarks') }
            Stop-PtSnapshotData UnsupportedShape $Location $problem
        }
        return ,$map
    }

    function Test-PtSnapshotArray($Value) {
        return ($Value -is [array] -and $Value.Rank -eq 1 -and $Value.GetLowerBound(0) -eq 0)
    }

    function Test-PtSnapshotInteger($Value, [decimal]$Minimum, [decimal]$Maximum) {
        $integer = $Value -is [sbyte] -or $Value -is [byte] -or
            $Value -is [int16] -or $Value -is [uint16] -or
            $Value -is [int32] -or $Value -is [uint32] -or
            $Value -is [int64] -or $Value -is [uint64]
        return ($integer -and $Value -ge $Minimum -and $Value -le $Maximum)
    }

    function ConvertTo-PtSnapshotControlType($Value, [switch]$Captured) {
        if ($Captured -and $Value -is [string] -and $Value -ceq 'Unknown(50025)') { return 'Custom' }
        if ($Value -is [string] -and $Value -imatch '^(?:ControlType\.)?(Button|Calendar|CheckBox|ComboBox|Edit|Hyperlink|Image|ListItem|List|Menu|MenuBar|MenuItem|ProgressBar|RadioButton|ScrollBar|Slider|Spinner|StatusBar|Tab|TabItem|Text|ToolBar|ToolTip|Tree|TreeItem|Custom|Group|Thumb|DataGrid|DataItem|Document|SplitButton|Window|Pane|Header|HeaderItem|Table|TitleBar|Separator|SemanticZoom|AppBar)$') {
            return $Matches[1]
        }
        return $null
    }

    function Assert-PtSnapshotComplete($Map, [string]$Location) {
        foreach ($field in @('truncated', 'isTruncated', 'childrenTruncated', 'depthLimitReached',
            'nodeLimitReached', 'maxDepthReached', 'maxNodesReached', 'hasMoreChildren', 'hasMore',
            'partial', 'isPartial', 'incomplete', 'complete', 'isComplete')) {
            if (-not $Map.ContainsKey($field)) { continue }
            if ($Map[$field] -isnot [bool]) {
                Stop-PtSnapshotData MalformedSnapshot "$Location.$field" 'Capture completeness flags must be boolean.'
            }
            $incomplete = if ($field -in @('complete', 'isComplete')) { -not $Map[$field] } else { $Map[$field] }
            if ($incomplete) {
                Stop-PtSnapshotData IncompleteSnapshot "$Location.$field" 'Capture explicitly reports incomplete or truncated data.'
            }
        }
    }

    function Read-PtSnapshotRuntimeId($Value, [string]$Location) {
        $parts = $Value
        if ($Value -is [string]) {
            if ($Value -cnotmatch '^-?[0-9]+(?:[,.]-?[0-9]+)*$') {
                Stop-PtSnapshotData MalformedSnapshot $Location 'runtimeId must contain decimal Int32 components.'
            }
            $parts = $Value -split '[,.]'
        } elseif (-not (Test-PtSnapshotArray $Value)) {
            Stop-PtSnapshotData MalformedSnapshot $Location 'runtimeId must be an Int32-component array or decimal-component string.'
        }
        if ($parts.Count -eq 0) { return $null }
        $normalized = [Collections.Generic.List[string]]::new()
        foreach ($part in $parts) {
            $number = 0
            if ($Value -is [string]) {
                if (-not [int]::TryParse($part, [Globalization.NumberStyles]::AllowLeadingSign,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
                    Stop-PtSnapshotData MalformedSnapshot $Location 'runtimeId components must fit Int32.'
                }
            } else {
                if (-not (Test-PtSnapshotInteger $part ([int]::MinValue) ([int]::MaxValue))) {
                    Stop-PtSnapshotData MalformedSnapshot $Location 'runtimeId array components must be Int32 integers, not coerced values.'
                }
                $number = [int]$part
            }
            $normalized.Add($number.ToString([Globalization.CultureInfo]::InvariantCulture))
        }
        return $normalized -join ','
    }

    if (-not (Test-PtSnapshotInteger $MaxNodes 1 ([int]::MaxValue))) {
        throw [ArgumentException]::new('MaxNodes must be a positive Int32 integer.', 'MaxNodes')
    }
    $targeted = $PSBoundParameters.ContainsKey('WindowHwnd')
    if ($targeted -and -not (Test-PtSnapshotInteger $WindowHwnd 1 ([long]::MaxValue))) {
        throw [ArgumentException]::new('WindowHwnd must be a positive Int64 integer.', 'WindowHwnd')
    }
    if (-not (Test-PtSnapshotArray $RequiredLandmarks) -or $RequiredLandmarks.Count -eq 0) {
        throw [ArgumentException]::new('RequiredLandmarks must be a nonempty array of structural landmarks.', 'RequiredLandmarks')
    }
    $labels = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $scopeLabels = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $landmarks = [Collections.Generic.List[object]]::new()
    foreach ($entry in $RequiredLandmarks) {
        $contract = Read-PtSnapshotObject $entry 'RequiredLandmarks' -Contract
        foreach ($field in $contract.Keys) {
            if ($field -notin @('Id', 'ControlType', 'AutomationId', 'Name', 'WithinAutomationId')) {
                throw [ArgumentException]::new("Unsupported landmark field '$field'; only structural selectors are accepted.", 'RequiredLandmarks')
            }
            if ($contract[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace($contract[$field])) {
                throw [ArgumentException]::new("Landmark field '$field' must be a nonempty string.", 'RequiredLandmarks')
            }
        }
        if (-not $contract.ContainsKey('Id') -or -not $contract.ContainsKey('ControlType') -or
            $contract.ContainsKey('AutomationId') -eq $contract.ContainsKey('Name')) {
            throw [ArgumentException]::new('Each landmark requires Id, ControlType and exactly one AutomationId or Name.', 'RequiredLandmarks')
        }
        if (-not $labels.Add($contract['Id'])) {
            throw [ArgumentException]::new('Landmark Id labels must be unique (case-sensitive).', 'RequiredLandmarks')
        }
        $type = ConvertTo-PtSnapshotControlType $contract['ControlType']
        if ($null -eq $type) {
            throw [ArgumentException]::new('Landmark ControlType must be a supported UIA control type name.', 'RequiredLandmarks')
        }
        $selector = if ($contract.ContainsKey('AutomationId')) { 'automationId' } else { 'name' }
        $scope = if ($contract.ContainsKey('WithinAutomationId')) { $contract['WithinAutomationId'] } else { $null }
        if ($null -ne $scope) { [void]$scopeLabels.Add($scope) }
        $landmarks.Add([pscustomobject]@{
            id = $contract['Id']; type = $type; selector = $selector; value = $contract[$selector]; scope = $scope
            count = 0; rawCount = 0; withoutRuntimeId = 0
            runtimeIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        })
    }

    $nodeCount = 0
    $nodesWithoutRuntimeId = 0
    $duplicateRuntimeIdOccurrences = 0
    $selectedHwnd = $null
    $evaluationComplete = $false
    $location = $null
    $missing = [Collections.Generic.List[string]]::new()
    try {
        if ($null -eq $Tree) {
            Stop-PtSnapshotData MalformedSnapshot 'tree' 'The captured tree is null.'
        }
        $envelope = Read-PtSnapshotObject $Tree 'tree'
        Assert-PtSnapshotComplete $envelope 'tree'
        if (-not $envelope.ContainsKey('windows')) {
            Stop-PtSnapshotData UnsupportedShape 'tree' 'Expected the windows[].elements[] inspect envelope.'
        }
        $windows = $envelope['windows']
        if (-not (Test-PtSnapshotArray $windows)) {
            Stop-PtSnapshotData MalformedSnapshot 'windows' 'windows must be an array, not null, an object or stringified JSON.'
        }
        if ($windows.Count -eq 0) {
            Stop-PtSnapshotData WindowNotFound 'windows' 'The capture contains no windows.'
        }
        if (-not $targeted -and $windows.Count -gt 1) {
            Stop-PtSnapshotData AmbiguousWindow 'windows' 'Multi-window captures require an explicit WindowHwnd.'
        }
        $selected = $null
        $windowLocation = $null
        for ($i = 0; $i -lt $windows.Count; $i++) {
            $window = Read-PtSnapshotObject $windows[$i] "windows[$i]"
            if (-not $window.ContainsKey('hwnd')) {
                Stop-PtSnapshotData MissingWindowHwnd "windows[$i].hwnd" 'Window metadata lacks hwnd; target selection cannot be established.'
            }
            $hwnd = $window['hwnd']
            if ($hwnd -is [string] -and $hwnd -cmatch '^[0-9]+$') {
                $parsedHwnd = 0L
                if ([long]::TryParse($hwnd, [ref]$parsedHwnd)) { $hwnd = $parsedHwnd }
            }
            if (-not (Test-PtSnapshotInteger $hwnd 1 ([long]::MaxValue))) {
                Stop-PtSnapshotData MalformedSnapshot "windows[$i].hwnd" 'Window metadata hwnd must be a positive Int64 integer or decimal string.'
            }
            if (-not $targeted -or $hwnd -eq $WindowHwnd) {
                if ($null -ne $selected) {
                    Stop-PtSnapshotData AmbiguousWindow 'windows' 'Multiple window records have the selected hwnd.'
                }
                $selected = $window
                $selectedHwnd = [long]$hwnd
                $windowLocation = "windows[$i]"
            }
        }
        if ($null -eq $selected) {
            Stop-PtSnapshotData WindowNotFound 'windows' 'The requested WindowHwnd is not present in this capture.'
        }
        Assert-PtSnapshotComplete $selected $windowLocation
        if (-not $selected.ContainsKey('elements') -or -not (Test-PtSnapshotArray $selected['elements'])) {
            Stop-PtSnapshotData MalformedSnapshot "$windowLocation.elements" 'Selected window elements must be an explicit array.'
        }

        $active = [Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
        $runtimeIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $scopes = [Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal)
        $stack = [Collections.Generic.Stack[object]]::new()
        $stack.Push([pscustomobject]@{ elements = $selected['elements']; next = 0; owner = $null; scope = $null })
        while ($stack.Count -gt 0) {
            $frame = $stack.Peek()
            if ($frame.next -eq $frame.elements.Count) {
                [void]$stack.Pop()
                if ($null -ne $frame.owner) { [void]$active.Remove($frame.owner) }
                if ($null -ne $frame.scope) {
                    $scopes[$frame.scope]--
                    if ($scopes[$frame.scope] -eq 0) { [void]$scopes.Remove($frame.scope) }
                }
                continue
            }
            if ($nodeCount -ge $MaxNodes) {
                Stop-PtSnapshotData NodeLimitExceeded 'elements' 'Selected element occurrences exceed MaxNodes; assessment stopped at the bound.'
            }
            $node = $frame.elements[$frame.next]
            $frame.next++
            $nodeLocation = "node[$nodeCount]"
            $map = Read-PtSnapshotObject $node $nodeLocation
            if (-not $active.Add($node)) {
                Stop-PtSnapshotData CycleDetected $nodeLocation 'A children edge refers to an active ancestor object.'
            }
            $nodeCount++
            Assert-PtSnapshotComplete $map $nodeLocation
            $type = $null
            foreach ($field in @('type', 'controlType')) {
                if (-not $map.ContainsKey($field)) { continue }
                $candidate = ConvertTo-PtSnapshotControlType $map[$field] -Captured
                if ($null -eq $candidate) {
                    Stop-PtSnapshotData UnsupportedShape "$nodeLocation.$field" 'Node control type must be a supported UIA control type string.'
                }
                if ($null -ne $type -and $type -ine $candidate) {
                    Stop-PtSnapshotData MalformedSnapshot $nodeLocation 'Node type and controlType disagree.'
                }
                $type = $candidate
            }
            if ($null -eq $type) {
                Stop-PtSnapshotData UnsupportedShape $nodeLocation 'Element lacks type/controlType; unsupported node shape.'
            }
            foreach ($field in @('automationId', 'name')) {
                if ($map.ContainsKey($field) -and $null -ne $map[$field] -and $map[$field] -isnot [string]) {
                    Stop-PtSnapshotData MalformedSnapshot "$nodeLocation.$field" 'Node selectors must be strings or null when present; empty strings are allowed.'
                }
            }
            $children = @()
            if ($map.ContainsKey('children')) {
                $children = $map['children']
                if (-not (Test-PtSnapshotArray $children)) {
                    Stop-PtSnapshotData MalformedSnapshot "$nodeLocation.children" 'children must be an array, not null, an object or stringified JSON.'
                }
            }
            $runtimeId = $null
            if ($map.ContainsKey('runtimeId')) { $runtimeId = Read-PtSnapshotRuntimeId $map['runtimeId'] "$nodeLocation.runtimeId" }
            if ($null -eq $runtimeId) {
                $nodesWithoutRuntimeId++
            } elseif (-not $runtimeIds.Add($runtimeId)) {
                $duplicateRuntimeIdOccurrences++
            }
            foreach ($landmark in $landmarks) {
                if ($type -ine $landmark.type -or -not $map.ContainsKey($landmark.selector) -or
                    $null -eq $map[$landmark.selector] -or
                    $map[$landmark.selector] -cne $landmark.value -or
                    ($null -ne $landmark.scope -and -not $scopes.ContainsKey($landmark.scope))) { continue }
                $landmark.rawCount++
                if ($null -eq $runtimeId) {
                    $landmark.withoutRuntimeId++
                    $landmark.count++
                } elseif ($landmark.runtimeIds.Add($runtimeId)) {
                    $landmark.count++
                }
            }
            $scope = $null
            if ($map.ContainsKey('automationId') -and $null -ne $map['automationId'] -and $scopeLabels.Contains($map['automationId'])) {
                $scope = $map['automationId']
                if ($scopes.ContainsKey($scope)) { $scopes[$scope]++ } else { $scopes.Add($scope, 1) }
            }
            # Keep ancestor identity/scope until its children finish; sibling aliases are not cycles.
            $stack.Push([pscustomobject]@{ elements = $children; next = 0; owner = $node; scope = $scope })
        }
        $evaluationComplete = $true
        foreach ($landmark in $landmarks) {
            if ($landmark.count -eq 0) { $missing.Add($landmark.id) }
        }
        if ($missing.Count -gt 0) {
            $status = 'MissingLandmarks'
            $reason = 'Required structural landmarks were not observed in the selected realized elements.'
        } else {
            $status = 'Usable'
            $reason = 'Required structural landmarks were observed; no business values or expected row counts were assessed.'
        }
    } catch [IO.InvalidDataException] {
        if (-not $_.Exception.Data.Contains('PtSnapshotStatus')) { throw }
        $status = [string]$_.Exception.Data['PtSnapshotStatus']
        $location = [string]$_.Exception.Data['PtSnapshotLocation']
        $reason = $_.Exception.Message
    }

    $counts = @(foreach ($landmark in $landmarks) {
        [pscustomobject]@{
            id = $landmark.id
            occurrenceCount = if ($evaluationComplete) { $landmark.count } else { $null }
            rawOccurrenceCount = if ($evaluationComplete) { $landmark.rawCount } else { $null }
            withoutRuntimeIdCount = if ($evaluationComplete) { $landmark.withoutRuntimeId } else { $null }
        }
    })
    $warnings = [Collections.Generic.List[string]]::new()
    $warnings.Add('RealizedElementsOnly: cannot prove full enumeration, visibility, rendered pixels or absence of virtualized rows.')
    $warnings.Add('Landmark counts describe captured occurrences with known runtime identities deduplicated, not product row counts.')
    if ($nodesWithoutRuntimeId -gt 0) { $warnings.Add('Some occurrences have no runtime identity; they are counted separately, never deduplicated by selectors.') }
    if ($duplicateRuntimeIdOccurrences -gt 0) { $warnings.Add('Repeated runtime identities were deduplicated per landmark; all wrapper children were still inspected.') }
    if (-not $evaluationComplete) { $warnings.Add('Assessment is incomplete: landmark counts are null and missingLandmarks is not an absence assessment.') }
    [pscustomobject]@{
        usableForContract = ($evaluationComplete -and $missing.Count -eq 0)
        status = $status
        missingLandmarks = $missing.ToArray()
        landmarkCounts = $counts
        dataScope = 'RealizedElementsOnly'
        reason = $reason
        nodeCount = $nodeCount
        warnings = $warnings.ToArray()
        diagnostics = [pscustomobject]@{
            evaluationComplete = $evaluationComplete
            selectedWindowHwnd = $selectedHwnd
            location = $location
            nodesWithoutRuntimeId = $nodesWithoutRuntimeId
            duplicateRuntimeIdOccurrences = $duplicateRuntimeIdOccurrences
        }
    }
}
