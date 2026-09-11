#requires -Version 7.2
<#
.SYNOPSIS
Run standalone offline snapshot tests and write evidence into a new caller-owned workspace.
.EXAMPLE
.\Test-PtUiSnapshot.ps1 -Workspace 'C:\session\files\h07-snapshot-unique'
#>
param([Parameter(Mandatory)][string]$Workspace)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$helper = Join-Path (Split-Path $PSScriptRoot -Parent) 'pt-ui-snapshot.ps1'
if (Test-Path -LiteralPath $Workspace) { throw 'Use a new, unique workspace; existing evidence is not overwritten.' }
[void][IO.Directory]::CreateDirectory($Workspace)
$results = [Collections.Generic.List[object]]::new()
$examples = [ordered]@{}
function Require([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Reject([scriptblock]$Action) {
    try { & $Action | Out-Null } catch [ArgumentException] { return }
    throw 'Expected ArgumentException for an invalid API argument.'
}
function Check([string]$Name, [scriptblock]$Action) {
    try {
        & $Action | Out-Null
        $results.Add([pscustomobject]@{ name = $Name; status = 'PASS' })
    } catch {
        $results.Add([pscustomobject]@{ name = $Name; status = 'FAIL'; error = $_.Exception.Message; stack = $_.ScriptStackTrace })
        throw
    } finally {
        ConvertTo-Json -InputObject $results.ToArray() -Depth 6 | Set-Content -LiteralPath "$Workspace\results.json"
    }
}
function Node([string]$Type = 'List', [string]$Id = 'Results', [object[]]$Children = @()) {
    return @{ type = $Type; automationId = $Id; children = $Children }
}
function Tree([object[]]$Elements = @((Node))) {
    return @{ windows = @(@{ hwnd = 123L; elements = $Elements }) }
}
function Assess($Capture, $Contract = $script:contract) {
    return Test-PtUiSnapshot -Tree $Capture -RequiredLandmarks $Contract
}
function Unusable($Capture, [string]$Status) {
    $result = Assess $Capture
    Require (-not $result.usableForContract -and $result.status -ceq $Status) "Expected $Status, got $($result.status)."
    Require ($result.dataScope -ceq 'RealizedElementsOnly' -and $result.reason.Length -gt 0) 'Unusable result lost scope/reason.'
    if ($Status -cne 'MissingLandmarks') {
        Require (-not $result.diagnostics.evaluationComplete) 'Bad capture appeared complete.'
        Require ($result.missingLandmarks.Count -eq 0) 'Incomplete evaluation claimed structural absence.'
        foreach ($count in $result.landmarkCounts) {
            Require ($null -eq $count.occurrenceCount -and $null -eq $count.rawOccurrenceCount -and $null -eq $count.withoutRuntimeIdCount) 'Incomplete counts became success-shaped zeros.'
        }
        Require ($result.diagnostics.location.Length -gt 0) 'Bad capture lost diagnostic location.'
    }
    return $result
}
$contract = @(@{ Id = 'results'; ControlType = 'List'; AutomationId = 'Results' })

Check 'Definitions-only import has no output or helper imports' {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($helper, [ref]$tokens, [ref]$errors)
    Require ($errors.Count -eq 0) 'Helper has parser errors.'
    Require ($ast.EndBlock.Statements.Count -eq 1 -and
        $ast.EndBlock.Statements[0] -is [Management.Automation.Language.FunctionDefinitionAst]) 'Helper import executes non-definition statements.'
    $output = @(. $helper)
    Require ($output.Count -eq 0) 'Dot-sourcing emitted output.'
}
. $helper

Check 'Empty-list structure is usable with exact compact result shape' {
    $capture = Tree @((Node Pane Page @((Node Edit SearchBox), (Node))))
    $required = @(
        @{ Id = 'query'; ControlType = 'Edit'; AutomationId = 'SearchBox' },
        @{ Id = 'results'; ControlType = 'List'; AutomationId = 'Results'; WithinAutomationId = 'Page' }
    )
    $result = Assess $capture $required
    Require ($result.usableForContract -and $result.status -ceq 'Usable' -and $result.nodeCount -eq 3) 'An empty observable list was gated on business rows.'
    Require ($result.missingLandmarks -is [array] -and $result.missingLandmarks.Count -eq 0) 'missingLandmarks is not an empty array.'
    Require (($result.PSObject.Properties.Name -join ',') -ceq 'usableForContract,status,missingLandmarks,landmarkCounts,dataScope,reason,nodeCount,warnings,diagnostics') 'Result schema changed.'
    Require (($result.landmarkCounts[0].PSObject.Properties.Name -join ',') -ceq 'id,occurrenceCount,rawOccurrenceCount,withoutRuntimeIdCount') 'Count schema changed.'
    Require (($result.diagnostics.PSObject.Properties.Name -join ',') -ceq 'evaluationComplete,selectedWindowHwnd,location,nodesWithoutRuntimeId,duplicateRuntimeIdOccurrences') 'Diagnostic schema changed.'
    Require ($result.landmarkCounts[0].occurrenceCount -eq 1 -and $result.landmarkCounts[1].occurrenceCount -eq 1) 'Structural occurrence counts were lost.'
    $examples['emptyListContract'] = $required
    $examples['emptyListResult'] = $result
}
Check 'Genuinely absent business rows remain a usable structural capture' {
    $empty = Assess (Tree)
    $populated = Assess (Tree @((Node List Results @((Node ListItem BusinessRow)))))
    Require ($empty.usableForContract -and $populated.usableForContract) 'Expected business content leaked into readiness.'
    Require ($empty.landmarkCounts[0].occurrenceCount -eq $populated.landmarkCounts[0].occurrenceCount) 'Container count became row count.'
}
foreach ($hostName in @('Host', 'PopupHost')) {
    Check "$hostName-only capture is unusable when structural markers are absent" {
        $hostNode = Node Window ''
        $hostNode['name'] = $hostName
        $result = Unusable (Tree @($hostNode)) MissingLandmarks
        Require ($result.diagnostics.evaluationComplete -and $result.missingLandmarks[0] -ceq 'results') 'Host-only failure lost missing markers.'
        $examples['hostOnlyResult'] = $result
    }
}
foreach ($representation in @('PSCustomObject', 'Hashtable', 'OrderedDictionary', 'Mixed')) {
    Check "$representation JSON objects are supported consistently" {
        $json = '{"windows":[{"hwnd":123,"elements":[{"type":"ControlType.List","automationId":"Results","children":[]}]}]}'
        $capture = switch ($representation) {
            PSCustomObject { ConvertFrom-Json -InputObject $json }
            Hashtable { Tree }
            OrderedDictionary { [ordered]@{ windows = @([ordered]@{ hwnd = 123L; elements = @([ordered]@{ type = 'List'; automationId = 'Results'; children = @() }) }) } }
            Mixed { @{ windows = @([pscustomobject]@{ hwnd = 123L; elements = @([ordered]@{ type = 'List'; automationId = 'Results'; children = @() }) }) } }
        }
        $required = @(if ($representation -eq 'PSCustomObject') { [pscustomobject]$contract[0] } else { $contract })
        $result = Assess $capture $required
        Require ($result.usableForContract -and $result.landmarkCounts[0].occurrenceCount -eq 1) 'Object representation changed assessment.'
    }
}
Check 'ConvertFrom-Json -AsHashtable preserves canonical arrays and false/empty values' {
    $capture = '{"windows":[{"hwnd":"123","elements":[{"controlType":"ControlType.List","automationId":"Results","name":"","value":"","isEnabled":false,"children":[]}]}]}' | ConvertFrom-Json -AsHashtable
    Require (Assess $capture).usableForContract 'Parsed IDictionary representation was rejected.'
}
Check 'Single window selection and positive decimal-string metadata hwnd are retained' {
    $capture = Tree
    $capture.windows[0].hwnd = '123'
    $result = Test-PtUiSnapshot -Tree $capture -RequiredLandmarks $contract -WindowHwnd 123L
    Require ($result.usableForContract -and $result.diagnostics.selectedWindowHwnd -is [long] -and $result.diagnostics.selectedWindowHwnd -eq 123) 'Selected hwnd was not retained.'
}
Check 'Multi-window input requires a target, not a first-window fallback' {
    $capture = Tree
    $capture.windows += @{ hwnd = 456L; elements = @((Node)) }
    Unusable $capture AmbiguousWindow
}
Check 'Selected hwnd restricts traversal and cannot borrow another window landmarks' {
    $capture = @{ windows = @(
        @{ hwnd = 123L; elements = @((Node Window Host)) },
        @{ hwnd = 456L; elements = @((Node)) }
    ) }
    $missing = Test-PtUiSnapshot -Tree $capture -RequiredLandmarks $contract -WindowHwnd 123L
    $usable = Test-PtUiSnapshot -Tree $capture -RequiredLandmarks $contract -WindowHwnd 456L
    Require ($missing.status -ceq 'MissingLandmarks' -and -not $missing.usableForContract) 'Unselected window supplied a landmark.'
    Require ($usable.usableForContract -and $usable.nodeCount -eq 1) 'Selected target was not isolated.'
    $capture.windows[0].elements = 'malformed unselected nodes'
    Require (Test-PtUiSnapshot -Tree $capture -RequiredLandmarks $contract -WindowHwnd 456L).usableForContract 'Unselected descendants were assessed.'
}
Check 'Wrong target hwnd is explicit, with null counts' {
    $result = Test-PtUiSnapshot -Tree (Tree) -RequiredLandmarks $contract -WindowHwnd 999L
    Require ($result.status -ceq 'WindowNotFound' -and -not $result.usableForContract -and
        $null -eq $result.landmarkCounts[0].occurrenceCount) 'Wrong hwnd became an empty success.'
    $examples['wrongWindowResult'] = $result
}
Check 'Missing hwnd metadata is unusable with or without a requested hwnd' {
    $capture = @{ windows = @(@{ elements = @((Node)) }) }
    Unusable $capture MissingWindowHwnd
    $result = Test-PtUiSnapshot -Tree $capture -RequiredLandmarks $contract -WindowHwnd 123L
    Require ($result.status -ceq 'MissingWindowHwnd' -and -not $result.usableForContract) 'Targeted selection accepted missing hwnd.'
}
Check 'Duplicate selected window hwnd is ambiguous' {
    $capture = Tree
    $capture.windows += @{ hwnd = 123L; elements = @((Node)) }
    $result = Test-PtUiSnapshot -Tree $capture -RequiredLandmarks $contract -WindowHwnd 123L
    Require ($result.status -ceq 'AmbiguousWindow' -and -not $result.usableForContract) 'Duplicate hwnd selected the first record.'
}
foreach ($badHwnd in @($null, 0, -1L, $false, 123.0, 'abc', '0x7B', '9223372036854775808', @())) {
    Check "Malformed window hwnd value $($results.Count)" {
        $capture = Tree
        $capture.windows[0].hwnd = $badHwnd
        Unusable $capture MalformedSnapshot
    }
}
Check 'Control type alias/prefix/casing normalize, but conflicting aliases are rejected' {
    foreach ($nodeType in @('List', 'ControlType.List', 'list')) {
        $capture = Tree @(@{ controlType = $nodeType; automationId = 'Results' })
        Require (Assess $capture @(@{ id = 'results'; controltype = 'ControlType.LIST'; automationid = 'Results' })).usableForContract 'Control type normalization failed.'
    }
    $node = Node
    $node.controlType = 'ControlType.List'
    Require (Assess (Tree @($node))).usableForContract 'Equivalent aliases disagreed.'
    $node.controlType = 'Edit'
    Unusable (Tree @($node)) MalformedSnapshot
}
Check 'Captured winapp Unknown(50025) is UIA Custom without dropping its descendants' {
    $node = Node 'Unknown(50025)' CustomHost @((Node))
    $node.controlType = 'ControlType.Custom'
    $required = @($contract[0], @{ Id = 'host'; ControlType = 'Custom'; AutomationId = 'CustomHost' })
    $result = Assess (Tree @($node)) $required
    Require ($result.usableForContract -and $result.nodeCount -eq 2 -and
        $result.landmarkCounts[0].occurrenceCount -eq 1 -and $result.landmarkCounts[1].occurrenceCount -eq 1) 'Known winapp Custom spelling invalidated structural assessment.'
    $node.controlType = 'Group'
    Unusable (Tree @($node)) MalformedSnapshot
    Unusable (Tree @((Node 'Unknown(99999)' CustomHost))) UnsupportedShape
    Reject { Assess (Tree) @(@{ Id = 'host'; ControlType = 'Unknown(50025)'; AutomationId = 'CustomHost' }) }
}
Check 'AutomationId and name match case-sensitively without wildcard/regex/whitespace folding' {
    $node = Node List 'Results.* '
    $node.name = 'Same Caption'
    Require (Assess (Tree @($node)) @(@{ Id = 'n'; ControlType = 'List'; Name = 'Same Caption' })).usableForContract 'Name selector failed.'
    foreach ($selector in @(
        @{ Id = 'n'; ControlType = 'List'; Name = 'same caption' },
        @{ Id = 'n'; ControlType = 'List'; AutomationId = 'Results.*' },
        @{ Id = 'n'; ControlType = 'List'; AutomationId = 'results.* ' }
    )) {
        Require ((Assess (Tree @($node)) @($selector)).status -ceq 'MissingLandmarks') 'Selector was normalized or pattern-matched.'
    }
    Require (Assess (Tree @($node)) @(@{ Id = 'n'; ControlType = 'List'; AutomationId = 'Results.* ' })).usableForContract 'Literal selector was not matched.'
}
Check 'Same-ID containers are scoped by strict ancestors, not by siblings or self' {
    $capture = Tree @(
        (Node Pane First @((Node))),
        (Node Pane Second @((Node), (Node)) ),
        (Node List Results)
    )
    $required = @(
        @{ Id = 'first'; ControlType = 'List'; AutomationId = 'Results'; WithinAutomationId = 'First' },
        @{ Id = 'second'; ControlType = 'List'; AutomationId = 'Results'; WithinAutomationId = 'Second' }
    )
    $result = Assess $capture $required
    Require ($result.usableForContract -and $result.landmarkCounts[0].occurrenceCount -eq 1 -and $result.landmarkCounts[1].occurrenceCount -eq 2) 'Scoped counts leaked across containers.'
    foreach ($scope in @('first', 'Results', 'Missing')) {
        $required[0].WithinAutomationId = $scope
        Require ((Assess $capture @($required[0])).status -ceq 'MissingLandmarks') 'Scope matched self, wrong case or nonexistent ancestor.'
    }
}
Check 'Nested and repeated matching ancestor scopes use a union without scope leakage' {
    $capture = Tree @(
        (Node Pane Scope @((Node Pane Scope @((Node))), (Node))),
        (Node Pane Scope @((Node))),
        (Node)
    )
    $result = Assess $capture @(@{ Id = 'scoped'; ControlType = 'List'; AutomationId = 'Results'; WithinAutomationId = 'Scope' })
    Require ($result.usableForContract -and $result.landmarkCounts[0].occurrenceCount -eq 3) 'Nested/repeated scope counted twice or leaked into sibling.'
}
Check 'Repeated runtime wrappers deduplicate counts but never discard descendants' {
    $one = Node
    $one.runtimeId = @(42, 1)
    $two = Node
    $two.runtimeId = '42.1'
    $two.children = @((Node Edit Search))
    $three = Node
    $three.runtimeId = '042,01'
    $result = Assess (Tree @($one, $two, $three)) @(
        $contract[0], @{ Id = 'query'; ControlType = 'Edit'; AutomationId = 'Search' }
    )
    Require ($result.usableForContract -and $result.nodeCount -eq 4) 'Duplicate wrapper children were pruned.'
    Require ($result.landmarkCounts[0].occurrenceCount -eq 1 -and $result.landmarkCounts[0].rawOccurrenceCount -eq 3 -and
        $result.diagnostics.duplicateRuntimeIdOccurrences -eq 2) 'Known runtime identity deduplication failed.'
    $examples['runtimeDedupResult'] = $result
}
Check 'Same-caption same-ID controls with distinct or missing runtime IDs are not deduplicated' {
    $nodes = @((Node), (Node), (Node), (Node))
    foreach ($node in $nodes) { $node.name = 'Duplicate caption' }
    $nodes[0].runtimeId = @(42, 1)
    $nodes[1].runtimeId = @(42, 2)
    $nodes[3].runtimeId = @()
    $result = Assess (Tree $nodes)
    Require ($result.landmarkCounts[0].occurrenceCount -eq 4 -and $result.landmarkCounts[0].rawOccurrenceCount -eq 4 -and
        $result.landmarkCounts[0].withoutRuntimeIdCount -eq 2) 'Nonunique selectors were treated as identities.'
}
Check 'Reference alias among siblings is an occurrence, not a cycle or inferred identity' {
    $node = Node
    $result = Assess (Tree @($node, $node))
    Require ($result.usableForContract -and $result.landmarkCounts[0].occurrenceCount -eq 2) 'Object reference was claimed as runtime identity.'
}
Check 'False/empty/zero business values are preserved and never used as structural gates' {
    $capture = Tree @(@{
        type = 'List'; automationId = 'Results'; name = ''; value = ''; isEnabled = $false
        isOffscreen = $true; isSelected = $false; x = 0; y = 0; width = 0; height = 0
        businessRows = @(); children = @(); truncated = $false; complete = $true
    })
    $before = ConvertTo-Json -InputObject $capture -Depth 12 -Compress
    $result = Assess $capture
    Require ($result.usableForContract -and $result.dataScope -ceq 'RealizedElementsOnly') 'Business/visibility data became a readiness predicate.'
    Require ((ConvertTo-Json -InputObject $capture -Depth 12 -Compress) -ceq $before) 'False/empty/zero fields were changed.'
}
foreach ($asHashtable in @($false, $true)) {
    Check "Nullable captured selectors remain unavailable data, not malformed or substituted ($asHashtable)" {
        $json = '{"windows":[{"hwnd":123,"elements":[{"type":"Pane","automationId":null,"name":null,"children":[{"type":"List","automationId":"Results","name":null,"children":[]},{"type":"List","automationId":null,"name":"Named list","children":[]}]}]}]}'
        $capture = ConvertFrom-Json -InputObject $json -AsHashtable:$asHashtable
        $before = ConvertTo-Json -InputObject $capture -Depth 10 -Compress
        $required = @(
            $contract[0],
            @{ Id = 'named'; ControlType = 'List'; Name = 'Named list' }
        )
        $result = Assess $capture $required
        Require ($result.usableForContract -and $result.nodeCount -eq 3 -and
            $result.landmarkCounts[0].occurrenceCount -eq 1 -and $result.landmarkCounts[1].occurrenceCount -eq 1) 'Null optional selector invalidated another available selector.'
        foreach ($missing in @(
            @{ Id = 'no-id'; ControlType = 'List'; AutomationId = 'Named list' },
            @{ Id = 'no-name'; ControlType = 'List'; Name = 'Results' },
            @{ Id = 'no-scope'; ControlType = 'List'; AutomationId = 'Results'; WithinAutomationId = 'null' }
        )) {
            Require ((Assess $capture @($missing)).status -ceq 'MissingLandmarks') 'Null selector was substituted from another property or used as scope.'
        }
        Require ((ConvertTo-Json -InputObject $capture -Depth 10 -Compress) -ceq $before) 'Nullable captured data was changed.'
    }
}
Check 'SG structural context works with empty/populated results and no processId metadata' {
    $required = @(
        @{ Id = 'searchGroup'; ControlType = 'Group'; AutomationId = 'ShortcutGuide_SearchBox' },
        @{ Id = 'searchInput'; ControlType = 'Edit'; AutomationId = 'TextBox'; WithinAutomationId = 'ShortcutGuide_SearchBox' },
        @{ Id = 'navigation'; ControlType = 'Group'; AutomationId = 'MenuItemsHost' }
    )
    $capture = @{
        depth = 14; interactive = $false; hideDisabled = $false; hideOffscreen = $false
        windows = @(@{
            hwnd = 328248L; title = 'Shortcut Guide'; elementCount = 4
            elements = @(@{
                type = 'Pane'; automationId = $null; name = 'Shortcut Guide'; isOffscreen = $false
                children = @(
                    @{ type = 'Group'; automationId = 'ShortcutGuide_SearchBox'; name = $null; children = @(
                        @{ type = 'Edit'; automationId = 'TextBox'; name = 'Search shortcuts'; selector = 'TextBox'; value = '' }
                    ) },
                    @{ type = 'Group'; automationId = 'MenuItemsHost'; name = $null; children = @() }
                )
            })
        })
    }
    $empty = Assess $capture $required
    Require ($empty.usableForContract -and $empty.nodeCount -eq 4) 'Empty SG result structure was not usable.'
    $capture.windows[0].elements[0].children[1].children = @(
        @{ type = 'Text'; automationId = $null; name = 'Arbitrary business result'; selector = 'text-generated' }
    )
    $populated = Assess $capture $required
    Require ($populated.usableForContract -and
        ($empty.landmarkCounts.occurrenceCount -join ',') -ceq ($populated.landmarkCounts.occurrenceCount -join ',')) 'SG business content or elementCount became a readiness gate.'
    $capture.windows[0].elements[0].children = @()
    $hostOnly = Assess $capture $required
    Require ($hostOnly.status -ceq 'MissingLandmarks' -and $hostOnly.missingLandmarks.Count -eq 3) 'SG host-only capture appeared ready.'
    $examples['shortcutGuideContract'] = $required
    $examples['shortcutGuideEmptyResult'] = $empty
}
foreach ($children in @('[]', '[{"type":"List"}]', 'System.Object[]', $null, $false, 0, @{}, [pscustomobject]@{})) {
    Check "Malformed children field $($results.Count)" {
        $node = Node
        $node.children = $children
        Unusable (Tree @($node)) MalformedSnapshot
    }
}
foreach ($badNode in @($null, $false, 1, 'node', @(@(), @()), [datetime]::MinValue)) {
    Check "Malformed element type $($results.Count)" {
        Unusable (Tree @($badNode)) UnsupportedShape
        Unusable (Tree @((Node List Results @($badNode)))) UnsupportedShape
    }
}
Check 'Missing children leaf is supported but has only realized-element scope' {
    $result = Assess (Tree @(@{ type = 'List'; automationId = 'Results' }))
    Require ($result.usableForContract -and $result.dataScope -ceq 'RealizedElementsOnly') 'An omitted leaf children field implied full enumeration or invalid structure.'
}
Check 'Explicit empty elements is a completed missing-landmark assessment, not malformed data' {
    $result = Unusable (Tree @()) MissingLandmarks
    Require ($result.nodeCount -eq 0 -and $result.landmarkCounts[0].occurrenceCount -eq 0) 'Valid empty array became unknown/malformed.'
}
Check 'Null tree is explicit malformed data' { Unusable $null MalformedSnapshot }
foreach ($badTree in @('{"windows":[]}', @(), @(@{}), $false, 1, @{}, @{ elements = @((Node)) }, @{ root = (Node) })) {
    Check "Unsupported envelope $($results.Count)" { Unusable $badTree UnsupportedShape }
}
foreach ($windows in @($null, $false, '{}', @{}, [Collections.Generic.List[object]]::new())) {
    Check "Malformed windows array $($results.Count)" { Unusable @{ windows = $windows } MalformedSnapshot }
}
Check 'Empty window array has an explicit missing-window status' { Unusable @{ windows = @() } WindowNotFound }
Check 'Malformed window object is explicit' { Unusable @{ windows = @('window') } UnsupportedShape }
foreach ($elements in @($null, $false, '[]', @{}, [Collections.Generic.List[object]]::new())) {
    Check "Malformed elements array $($results.Count)" {
        Unusable @{ windows = @(@{ hwnd = 123L; elements = $elements }) } MalformedSnapshot
    }
}
Check 'Missing elements field cannot become zero children' {
    Unusable @{ windows = @(@{ hwnd = 123L }) } MalformedSnapshot
}
Check 'Non-one-dimensional arrays are rejected' {
    $array = [object[,]]::new(1, 1)
    Unusable @{ windows = $array } MalformedSnapshot
    Unusable @{ windows = @(@{ hwnd = 123L; elements = $array }) } MalformedSnapshot
    $node = Node
    $node.children = $array
    Unusable (Tree @($node)) MalformedSnapshot
    Reject { Assess (Tree) $array }
}
Check 'Unsupported node shapes and non-string selectors cannot silently disappear' {
    foreach ($node in @(@{}, @{ properties = @{ type = 'List'; automationId = 'Results' } },
        @{ type = 50008; automationId = 'Results' }, @{ type = 'TextBox'; automationId = 'Results' })) {
        Unusable (Tree @($node)) UnsupportedShape
    }
    foreach ($value in @($false, 0, @())) {
        foreach ($selector in @('automationId', 'name')) {
            $node = Node
            $node[$selector] = $value
            Unusable (Tree @($node)) MalformedSnapshot
        }
    }
}
foreach ($flag in @('truncated', 'isTruncated', 'childrenTruncated', 'depthLimitReached', 'nodeLimitReached',
    'maxDepthReached', 'maxNodesReached', 'hasMoreChildren', 'hasMore', 'partial', 'isPartial', 'incomplete', 'complete', 'isComplete')) {
    Check "Explicit $flag completeness indicator at each supported scope" {
        foreach ($level in @('tree', 'window', 'node')) {
            $capture = Tree
            $object = switch ($level) {
                tree { $capture }
                window { $capture.windows[0] }
                node { $capture.windows[0].elements[0] }
            }
            $object[$flag] = $flag -notin @('complete', 'isComplete')
            Unusable $capture IncompleteSnapshot
            $object[$flag] = -not $object[$flag]
            Require (Assess $capture).usableForContract 'A genuine boolean completeness value was misinterpreted.'
            $object[$flag] = 'false'
            Unusable $capture MalformedSnapshot
        }
    }
}
foreach ($runtime in @($null, $false, 0, '', 'abc', '[42,1]', '1,,2', '1.2.5x', '2147483648', @{}, @(42, $false), @(42, '1'), @(42, 1.5), @([long]2147483648))) {
    Check "Malformed runtimeId $($results.Count)" {
        $node = Node
        $node.runtimeId = $runtime
        Unusable (Tree @($node)) MalformedSnapshot
    }
}
Check 'Signed Int32 runtime components and singleton arrays remain valid identities' {
    foreach ($runtime in @(@([int]::MinValue, 0, [int]::MaxValue), @(42), '42', '-1,0,2147483647')) {
        $node = Node
        $node.runtimeId = $runtime
        Require (Assess (Tree @($node))).usableForContract 'Valid runtimeId was rejected.'
    }
}
Check 'Invalid contract top-level arguments throw instead of creating vacuous readiness' {
    foreach ($required in @($null, @(), @{}, $false, 'contract', [Collections.Generic.List[object]]::new())) {
        Reject { Assess (Tree) $required }
    }
    foreach ($entry in @($null, $false, 1, 'landmark', @())) {
        Reject { Assess (Tree) @($entry) }
    }
}
Check 'Landmark required/exclusive fields and strict string values are enforced' {
    foreach ($required in @(
        @{ ControlType = 'List'; AutomationId = 'Results' },
        @{ Id = 'x'; AutomationId = 'Results' },
        @{ Id = 'x'; ControlType = 'List' },
        @{ Id = 'x'; ControlType = 'List'; AutomationId = 'Results'; Name = 'Results' },
        @{ Id = 'x'; ControlType = 'TextBox'; AutomationId = 'Results' }
    )) { Reject { Assess (Tree) @($required) } }
    foreach ($field in @('Id', 'ControlType', 'AutomationId', 'WithinAutomationId', 'Name')) {
        foreach ($value in @($null, '', ' ', $false, 0, @())) {
            $required = @{ Id = 'x'; ControlType = 'List'; AutomationId = 'Results' }
            if ($field -eq 'Name') { $required.Remove('AutomationId') }
            $required[$field] = $value
            Reject { Assess (Tree) @($required) }
        }
    }
}
foreach ($field in @('ExpectedCount', 'MinCount', 'MaxCount', 'RowCount', 'Value', 'ExpectedValue', 'Predicate', 'IsEnabled', 'Optional', 'Typo')) {
    Check "Unsupported $field contract field throws rather than gating on expected values" {
        $required = @{ Id = 'x'; ControlType = 'List'; AutomationId = 'Results' }
        $required[$field] = $false
        Reject { Assess (Tree) @($required) }
    }
}
Check 'Duplicate landmark labels throw, while case-distinct labels remain distinct' {
    Reject { Assess (Tree) @($contract[0], $contract[0]) }
    $result = Assess (Tree) @($contract[0], @{ Id = 'RESULTS'; ControlType = 'List'; AutomationId = 'Results' })
    Require ($result.landmarkCounts.Count -eq 2 -and $result.usableForContract) 'Case-sensitive labels were collapsed.'
}
Check 'Case-duplicate dictionary fields and non-string keys are explicit errors' {
    $required = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $required.Add('Id', 'x'); $required.Add('id', 'y')
    $required.Add('ControlType', 'List'); $required.Add('AutomationId', 'Results')
    Reject { Assess (Tree) @($required) }
    $node = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $node.Add('type', 'List'); $node.Add('TYPE', 'Edit')
    Unusable (Tree @($node)) UnsupportedShape
    Reject { Assess (Tree) @(@{ 1 = 'bad' }) }
    Unusable (Tree @(@{ 1 = 'bad' })) UnsupportedShape
}
Check 'PSCustomObject script properties are rejected without invoking getters' {
    $node = [pscustomobject]@{ type = 'List'; automationId = 'Results' }
    $node | Add-Member ScriptProperty children { throw 'Getter must never execute.' }
    Unusable (Tree @($node)) UnsupportedShape
    $required = [pscustomobject]@{ Id = 'x'; ControlType = 'List' }
    $required | Add-Member ScriptProperty AutomationId { throw 'Contract getter must never execute.' }
    Reject { Assess (Tree) @($required) }
}
Check 'Invalid WindowHwnd and MaxNodes API arguments throw without coercion' {
    foreach ($hwnd in @($null, 0, -1L, $false, '123', 1.2, [uint64]::MaxValue)) {
        Reject { Test-PtUiSnapshot -Tree (Tree) -RequiredLandmarks $contract -WindowHwnd $hwnd }
    }
    foreach ($bound in @($null, 0, -1, $false, '1', 1.2, [long]2147483648)) {
        Reject { Test-PtUiSnapshot -Tree (Tree) -RequiredLandmarks $contract -MaxNodes $bound }
    }
}
foreach ($representation in @('Hashtable', 'PSCustomObject')) {
    Check "$representation cycles are explicit, bounded and do not mutate references" {
        $parent = Node Pane Parent
        $child = Node
        if ($representation -eq 'PSCustomObject') {
            $parent = [pscustomobject]$parent; $child = [pscustomobject]$child
        }
        $parent.children = @($child); $child.children = @($parent)
        $result = Unusable (Tree @($parent)) CycleDetected
        Require ($result.nodeCount -eq 2 -and [object]::ReferenceEquals($child.children[0], $parent)) 'Cycle detection changed input or count.'
        $examples['cycleResult'] = $result
    }
}
Check 'Exact node bound is usable; one more occurrence is explicitly incomplete' {
    $capture = Tree @((Node), (Node))
    $exact = Test-PtUiSnapshot -Tree $capture -RequiredLandmarks $contract -MaxNodes 2
    $bounded = Test-PtUiSnapshot -Tree $capture -RequiredLandmarks $contract -MaxNodes 1
    Require ($exact.usableForContract -and $exact.nodeCount -eq 2) 'Exact MaxNodes boundary failed.'
    Require ($bounded.status -ceq 'NodeLimitExceeded' -and -not $bounded.usableForContract -and
        $bounded.nodeCount -eq 1 -and $null -eq $bounded.landmarkCounts[0].occurrenceCount) 'Bound became a partial success.'
    $examples['boundedResult'] = $bounded
}
Check 'Default 20000-node bound is measured exactly, including identityless occurrences' {
    $node = Node
    $nodes = [object[]]::new(20001)
    for ($i = 0; $i -lt $nodes.Count; $i++) { $nodes[$i] = $node }
    $exact = Assess (Tree $nodes[0..19999])
    $bounded = Assess (Tree $nodes)
    Require ($exact.usableForContract -and $exact.nodeCount -eq 20000 -and
        $exact.landmarkCounts[0].occurrenceCount -eq 20000) 'Default exact threshold/count changed.'
    Require ($bounded.status -ceq 'NodeLimitExceeded' -and $bounded.nodeCount -eq 20000) 'Default node threshold did not stop at 20000.'
}
Check 'Deep trees use iterative traversal with bounded diagnostic paths' {
    $node = Node
    for ($i = 0; $i -lt 1500; $i++) { $node = Node Pane Parent @($node) }
    $result = Assess (Tree @($node))
    Require ($result.usableForContract -and $result.nodeCount -eq 1501) 'Deep tree traversal failed or recursed.'
    $bounded = Test-PtUiSnapshot -Tree (Tree @($node)) -RequiredLandmarks $contract -MaxNodes 1500
    Require ($bounded.status -ceq 'NodeLimitExceeded' -and $bounded.diagnostics.location.Length -lt 100) 'Deep diagnostic expanded full ancestry.'
}
Check 'Malformed later nodes invalidate early matches, even after all landmarks matched' {
    $capture = Tree @((Node), @{ type = 'Pane'; children = '[]' })
    $result = Unusable $capture MalformedSnapshot
    Require ($result.nodeCount -eq 2 -and $null -eq $result.landmarkCounts[0].occurrenceCount) 'Early success hid later malformed data.'
}
Check 'Input and contract immutability hold for JSON object/dictionary success and failure' {
    foreach ($asHashtable in @($false, $true)) {
        $json = '{"windows":[{"hwnd":123,"elements":[{"type":"List","automationId":"Results","children":[],"isEnabled":false,"value":""}]}]}'
        $capture = ConvertFrom-Json -InputObject $json -AsHashtable:$asHashtable
        $required = ConvertFrom-Json -InputObject '[{"Id":"r","ControlType":"ControlType.List","AutomationId":"Results"}]' -AsHashtable:$asHashtable -NoEnumerate
        foreach ($malformed in @($false, $true)) {
            if ($malformed) { $capture.windows[0].elements[0].children = '[]' }
            $beforeTree = ConvertTo-Json -InputObject $capture -Depth 10 -Compress
            $beforeContract = ConvertTo-Json -InputObject $required -Depth 10 -Compress
            Assess $capture $required | Out-Null
            Require ((ConvertTo-Json -InputObject $capture -Depth 10 -Compress) -ceq $beforeTree) 'Capture mutated.'
            Require ((ConvertTo-Json -InputObject $required -Depth 10 -Compress) -ceq $beforeContract) 'Contract mutated.'
        }
    }
}
Check 'Compact result never contains the full tree or arbitrary captured property values' {
    $node = Node
    $node['payload'] = 'PRIVATE_CAPTURE_PAYLOAD_' + ('x' * 100000)
    $node.name = 'UNRETURNED_CAPTION'
    $result = Assess (Tree @($node))
    $serialized = ConvertTo-Json -InputObject $result -Depth 8 -Compress
    Require ($serialized.Length -lt 2500 -and $serialized -cnotmatch 'PRIVATE_CAPTURE_PAYLOAD_|UNRETURNED_CAPTION') 'Returned arbitrary tree content or unbounded diagnostics.'
    Require ($result.landmarkCounts -is [array] -and $result.warnings -is [array] -and
        $result.usableForContract -is [bool] -and $result.nodeCount -is [int]) 'Compact output types changed.'
    Require ($serialized -cnotmatch '"(?:PASS|FAIL)"') 'Assessment emitted a product verdict.'
    $examples['compactJsonLength'] = $serialized.Length
}

ConvertTo-Json -InputObject $examples -Depth 10 | Set-Content -LiteralPath "$Workspace\examples.json"
$summary = [pscustomobject]@{
    testGroups = $results.Count
    passed = @($results | Where-Object status -CEQ 'PASS').Count
    failed = @($results | Where-Object status -CEQ 'FAIL').Count
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    sources = @(
        [pscustomobject]@{ path = $helper; sha256 = (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash },
        [pscustomobject]@{ path = $PSCommandPath; sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash }
    )
}
ConvertTo-Json -InputObject $summary -Depth 6 | Set-Content -LiteralPath "$Workspace\summary.json"
"PASS: $($results.Count) offline snapshot test groups. Evidence: $Workspace"
