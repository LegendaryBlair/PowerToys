#requires -Version 7.0
<#
.SYNOPSIS
Dependency-free, offline reporter acceptance. All evidence is synthetic; no desktop/state access.
.EXAMPLE
pwsh -NoProfile -File .\Test-PtVerificationReport.ps1 -Workspace C:\temp\pt-report-acceptance-unique
#>
param(
    [string]$Workspace = (Join-Path $env:TEMP "pt-report-acceptance-$([Guid]::NewGuid().ToString('N'))")
)

function Invoke-PtVerificationReportAcceptance {
    param([Parameter(Mandatory)][string]$Workspace)
    $ErrorActionPreference = 'Stop'
    . "$PSScriptRoot\..\pt-verification-report.ps1"
    $Workspace = [IO.Path]::GetFullPath($Workspace)
    if (Test-Path -LiteralPath $Workspace) { throw 'Use a new acceptance workspace.' }
    [IO.Directory]::CreateDirectory($Workspace) | Out-Null
    $results = [Collections.Generic.List[object]]::new()
    function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
    function Reject([scriptblock]$Action, [string]$Pattern) {
        try { & $Action | Out-Null }
        catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; return }
        throw "Expected rejection: $Pattern"
    }
    function Check([string]$Name, [scriptblock]$Action) {
        $clock = [Diagnostics.Stopwatch]::StartNew()
        try {
            & $Action | Out-Null
            $results.Add([pscustomobject]@{ Name = $Name; Status = 'PASS'; Milliseconds = $clock.ElapsedMilliseconds })
        } catch {
            $results.Add([pscustomobject]@{ Name = $Name; Status = 'FAIL'; Milliseconds = $clock.ElapsedMilliseconds; Error = $_.ToString(); Stack = $_.ScriptStackTrace })
            throw
        } finally {
            [IO.File]::WriteAllText("$Workspace\acceptance-results.json", (ConvertTo-Json -InputObject $results.ToArray() -Depth 10))
        }
    }
    $unicode = ([string][char]0x4E2D) + [char]0x6587 + ' | `ticks` <tag> & [link](url)' + "`r`nsecond line"
    $source = "$Workspace\source.txt"
    [IO.File]::WriteAllText($source, $unicode)
    $fixture = "$Workspace\probe.txt"
    [IO.File]::WriteAllText($fixture, "SYNTHETIC OFFLINE OBSERVATION ONLY`n$unicode")
    $png = "$Workspace\synthetic.png"
    [IO.File]::WriteAllBytes($png, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWZkAAAAASUVORK5CYII='))
    $inputs = @(
        @{ Name = 'skill.txt'; Role = 'Skill'; Path = $source }
        @{ Name = 'profile.txt'; Role = 'Profile'; Path = $source }
        @{ Name = 'checklist.txt'; Role = 'Checklist'; Path = $source }
        @{ Name = 'reporter.ps1'; Role = 'Helper'; Path = "$PSScriptRoot\..\pt-verification-report.ps1" }
    )
    function Item([string]$Id, [bool]$Visible = $false) {
        @{ Id = $Id; Description = $unicode; Admin = 'NO'; Clarity = 'CLEAR'; UserVisible = $Visible
           Assertions = @(
               @{ Id = 'opens'; Description = "Observed opening: $unicode"; Required = $true }
               @{ Id = 'content'; Description = 'Observed content'; Required = $true }
           ) }
    }
    function NewRun([string]$Name, [object[]]$Items = @((Item 'L1'))) {
        New-PtVerificationRun -Workspace "$Workspace\$Name" -Module 'Synthetic reporter acceptance' -Bits 'SYNTHETIC files only; no installed product exercised' `
            -Scenario InfrastructureAcceptance -Items $Items -Inputs $inputs
    }
    function Observe($Attempt, [switch]$Image) {
        Invoke-PtVerificationStep -Attempt $Attempt -Name 'Synthetic probe' -Command $unicode -Action { $unicode } | Out-Null
        $evidence = Add-PtVerificationArtifact $Attempt $fixture Evidence 'Synthetic probe result, not product behavior' -Synthetic
        $proof = @($evidence)
        if ($Image) {
            $proof += Invoke-PtVerificationStep $Attempt -Name 'Import synthetic PNG, not a product capture' `
                -Command 'Add-PtVerificationArtifact -Path synthetic.png -Kind Screenshot -Synthetic' -Action {
                    Add-PtVerificationArtifact $Attempt $png Screenshot 'Synthetic 1x1 PNG, not a product capture' -Synthetic
                }
        }
        foreach ($id in 'opens','content') {
            Add-PtVerificationAssertion $Attempt $id PASS 'synthetic fixture comparison' 'Explicit offline fixture observation' -Evidence $proof
        }
        $evidence
    }
    function Preflight($Run) {
        $attempt = Start-PtVerificationAttempt $Run -Context Preflight -Kind Normal -Name 'Offline fixture preflight'
        Invoke-PtVerificationStep $attempt -Name 'Synthetic preflight' -Command "'offline, not an interactive session probe'" -Action { 'offline' } | Out-Null
        Stop-PtVerificationAttempt $attempt -Reason 'Synthetic preflight recorded'
    }
    function Cleanup($Run, [string]$Verdict = 'PASS') {
        $attempt = Start-PtVerificationAttempt $Run -Context Cleanup -Kind Normal -Name 'Offline fixture restoration receipt'
        Invoke-PtVerificationStep $attempt -Name 'Synthetic baseline comparison' -Command "'No product state was touched'" -Action { 'No product state was touched' } | Out-Null
        $proof = Add-PtVerificationArtifact $attempt $fixture Restoration 'Synthetic no-mutation baseline comparison' -Synthetic
        Add-PtVerificationRestoration $attempt -Verdict $Verdict -Reason 'Offline fixture receipt; no desktop or settings interaction' -Evidence @($proof)
        Stop-PtVerificationAttempt $attempt -Reason 'Synthetic cleanup context completed'
    }

    Check 'Definitions only when dot-sourced; validates explicit inventory, real inputs and safe paths' {
        Require ($null -eq (Get-PtActiveVerificationAttempt)) 'Ambient context must be opt-in'
        Reject { NewRun 'bad-empty' @() } 'empty|inventory'
        $bad = Item 'L1'
        $bad.UserVisible = 'true'
        Reject { NewRun 'bad-bool' @($bad) } 'boolean'
        Reject { NewRun 'bad-duplicate' @((Item 'L1'),(Item 'L1')) } 'Duplicate item'
        Reject { NewRun 'bad-path' @((Item '..\escape')) } 'Unsafe name'
        $badInputs = @($inputs) + @(@{ Name = 'SKILL.txt'; Role = 'Other'; Path = $source })
        Reject { New-PtVerificationRun -Workspace "$Workspace\bad-inputs" -Module fixture -Bits fixture -Scenario InfrastructureAcceptance -Items @((Item 'L1')) -Inputs $badInputs } 'Duplicate input'
        $badInputs = @(@{ Name = 'source'; Role = 'Skill'; Path = "$Workspace\absent" })
        Reject { New-PtVerificationRun -Workspace "$Workspace\missing-input" -Module fixture -Bits fixture -Scenario InfrastructureAcceptance -Items @((Item 'L1')) -Inputs $badInputs } 'real file'
        Require (-not (Test-Path "$Workspace\bad-duplicate")) 'Invalid inventory created a workspace'
    }

    Check 'Mixed inventory: Normal pass, sticky Normal failure, diagnostic recovery, unobserved children' {
        $script:mixed = NewRun 'mixed' @((Item 'L1' $true),(Item 'L2'),(Item 'L3'),(Item 'L4'))
        Preflight $mixed
        $a = Start-PtVerificationAttempt $mixed -ItemId L1 -Kind Normal -Name 'Synthetic visible Normal path'
        Observe $a -Image | Out-Null
        Stop-PtVerificationAttempt $a -Reason done
        Complete-PtVerificationItem $mixed L1 -Reason 'Observed both synthetic assertions'
        $normal = Start-PtVerificationAttempt $mixed -ItemId L2 -Kind Normal -Name 'Normal reopen failed'
        Invoke-PtVerificationStep $normal -Name 'Synthetic normal reopen' -Command "'normal returned wrong state'" -Action { 'wrong state' } | Out-Null
        $proof = Add-PtVerificationArtifact $normal $fixture Evidence 'Synthetic wrong-state observation' -Synthetic
        Add-PtVerificationAssertion $normal opens FAIL product 'Normal reopen is wrong in this synthetic fixture' -Evidence @($proof)
        Stop-PtVerificationAttempt $normal -Reason 'Failure retained'
        $diagnostic = Start-PtVerificationAttempt $mixed -ItemId L2 -Kind Diagnostic -Name 'Diagnostic restart recovery only'
        Observe $diagnostic | Out-Null
        Stop-PtVerificationAttempt $diagnostic -Reason 'Diagnostic success is not Normal reopen'
        Complete-PtVerificationItem $mixed L2 -Reason 'Normal failed; restart only diagnosed recovery'
        $a = Start-PtVerificationAttempt $mixed -ItemId L3 -Kind Normal -Name 'Only first subassertion observed'
        Invoke-PtVerificationStep $a -Name probe -Command "'fixture'" -Action { 'fixture' } | Out-Null
        $proof = Add-PtVerificationArtifact $a $fixture Evidence 'Synthetic observation' -Synthetic
        Add-PtVerificationAssertion $a opens PASS 'synthetic comparison' 'First child observed' -Evidence @($proof)
        Stop-PtVerificationAttempt $a -Reason 'Second child not observed'
        Complete-PtVerificationItem $mixed L3 -Reason 'Not all coverage performed'
        Cleanup $mixed
        $script:mixedExport = Complete-PtVerificationRun $mixed -Retrospective @(
            @{ Friction = $unicode; Source = 'HELPER-FLAW'; Severity = 'LOW'; Cost = 'synthetic: 0 minutes, 1 fixture'; SuggestedFix = 'No product fix; exercise report escaping' }
        )
        $state = Get-Content $mixedExport.Results -Raw | ConvertFrom-Json
        Require ($state.Items.Count -eq 4) 'Inventory item disappeared'
        Require ($state.Items[0].Verdict -eq 'PASS') 'Normal visible fixture should pass'
        Require ($state.Items[1].Verdict -eq 'FAIL') 'Diagnostic pass erased Normal failure'
        Require ($state.Items[1].Assertions[1].Verdict -eq 'NOT-OBSERVED') 'Unobserved child disappeared under FAIL'
        Require ($state.Items[2].Verdict -eq 'BLOCKED') 'Unobserved child allowed PASS'
        Require ($state.Items[3].Verdict -eq 'BLOCKED') 'Untouched inventory item allowed PASS'
        Require ($state.Signoff -eq 'WITHHELD') 'Mixed run incorrectly approved'
        Require (Test-PtVerificationArchive $mixed.Workspace).Valid 'Mixed archive did not validate'
        Reject { NewRun 'mixed' } 'already exist'
        Reject { Start-PtVerificationAttempt $mixed -ItemId L1 -Kind Normal -Name late } 'completed'
    }

    Check 'Unicode and Markdown preserved in raw artifacts; all commands and attempts rendered' {
        $state = Get-Content $mixedExport.Results -Raw | ConvertFrom-Json
        Require ($state.Metadata.Items[0].Description -ceq $unicode) 'Verbatim Unicode inventory lost'
        Require ($state.Steps[0].Name -eq 'Synthetic preflight') 'Step name was overwritten by recorder locals'
        $report = [IO.File]::ReadAllText($mixedExport.Report)
        Require ($report.Contains('&#124;') -and $report.Contains('&#96;') -and $report.Contains('&lt;tag&gt;')) 'Markdown metacharacters not escaped'
        Require ($report.Contains('**NOT-OBSERVED**')) 'Unobserved assertions not prominent'
        Require ($report.Contains('**Diagnostic**')) 'Diagnostic attempts hidden'
        foreach ($step in $state.Steps) {
            $command = $step.Sources | Where-Object { $_.Path.EndsWith('\command.txt') }
            Require ([IO.File]::ReadAllText((Join-Path $mixed.Workspace $command.Path)) -ceq $step.Command) 'Exact command artifact mismatch'
            Require ($report.Contains($command.Path.Replace('\','/'))) 'Command missing from report'
            Require ($report.Contains($step.AttemptId)) 'Attempt missing from command table'
        }
        $step = $state.Steps | Where-Object Command -CEQ $unicode | Select-Object -First 1
        $stdout = $step.Outputs | Where-Object { $_.Path.EndsWith('\stdout.txt') }
        Require ([IO.File]::ReadAllText((Join-Path $mixed.Workspace $stdout.Path)) -ceq $unicode) 'Raw stdout Unicode/newlines changed'
        foreach ($line in $report -split "`n" | Where-Object { $_.StartsWith('|') }) {
            Require (-not $line.Contains('<tag>')) 'Unsafe HTML in table'
        }
    }

    Check 'Source snapshots survive edits; finalized archive remains portable after moving' {
        [IO.File]::WriteAllText($source, 'SOURCE CHANGED AFTER INITIALIZATION')
        Require ([IO.File]::ReadAllText("$($mixed.Workspace)\inputs\skill.txt") -ceq $unicode) 'Source snapshot changed with source'
        $destination = "$Workspace\moved-mixed"
        Move-Item -LiteralPath $mixed.Workspace -Destination $destination
        Require (Test-PtVerificationArchive $destination).Valid 'Moved relative-path archive failed'
        $script:moved = Open-PtVerificationRun $destination
        $state = Get-Content "$destination\results.json" -Raw | ConvertFrom-Json
        foreach ($reference in $state.References) {
            Require (-not [IO.Path]::IsPathRooted($reference.Path)) 'Absolute evidence path leaked'
            Require (-not $reference.Path.Contains('..')) 'Parent traversal in evidence path'
        }
    }

    Check 'Missing, changed, omitted and traversing evidence reject export/archive without overwrites' {
        $file = "$($moved.Workspace)\inputs\profile.txt"
        $bytes = [IO.File]::ReadAllBytes($file)
        [IO.File]::WriteAllText($file, 'corrupted')
        Reject { Export-PtVerificationReport $moved } 'Changed evidence'
        Reject { Test-PtVerificationArchive $moved.Workspace } 'Changed evidence'
        [IO.File]::WriteAllBytes($file, $bytes)
        Move-Item $file "$file.missing"
        Reject { Export-PtVerificationReport $moved } 'Missing evidence'
        Move-Item "$file.missing" $file
        Require (@(Get-ChildItem $moved.Workspace -Filter 'export-failure-*.txt').Count -eq 2) 'Export failures lost diagnostic artifacts'
        Reject { Export-PtVerificationReport $moved -Final } 'overwrite'
        $manifestPath = "$($moved.Workspace)\artifact-manifest.json"
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $manifest.Files = @($manifest.Files | Where-Object Path -ne 'inputs\profile.txt')
        [IO.File]::WriteAllText("$($moved.Workspace)\omitted.json", ($manifest | ConvertTo-Json -Depth 15))
        Reject { Test-PtVerificationArchive $moved.Workspace -ManifestName omitted.json } 'omits'
        $manifest.Files[0].Path = '..\escape'
        [IO.File]::WriteAllText("$($moved.Workspace)\traversal.json", ($manifest | ConvertTo-Json -Depth 15))
        Reject { Test-PtVerificationArchive $moved.Workspace -ManifestName traversal.json } 'Unsafe'
    }

    Check 'Unique artifact names, reservations, and cross-attempt evidence isolation' {
        $run = NewRun 'unique'
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name first
        $first = New-PtVerificationArtifactPath $a -Name screenshot.png
        [IO.File]::WriteAllBytes($first, [IO.File]::ReadAllBytes($png))
        $proof = Add-PtVerificationArtifact $a $first Screenshot 'Synthetic screenshot' -Synthetic
        Reject { Add-PtVerificationArtifact $a $first Screenshot duplicate -Synthetic } 'already registered'
        $second = New-PtVerificationArtifactPath $a -Name screenshot.png
        [IO.File]::WriteAllBytes($second, [IO.File]::ReadAllBytes($png))
        Add-PtVerificationArtifact $a $second Screenshot 'Second synthetic screenshot' -Synthetic | Out-Null
        Stop-PtVerificationAttempt $a -Reason done
        $b = Start-PtVerificationAttempt $run -ItemId L1 -Kind Diagnostic -Name second
        $third = New-PtVerificationArtifactPath $b -Name screenshot.png
        Require ($first -ne $second -and $second -ne $third) 'Repeated screenshot name overwrote artifact'
        $long = New-PtVerificationArtifactPath $b -Name (('a' * 90) + '.png')
        Require ($long.EndsWith(('.png'))) 'Long safe friendly artifact name rejected'
        Require ([IO.File]::Exists($first)) 'First screenshot disappeared'
        Reject { Add-PtVerificationAssertion $b opens PASS fixture 'Cross-attempt reference' -Evidence @($proof) } 'this attempt'
        Reject { New-PtVerificationArtifactPath $b '..\screenshot.png' } 'Unsafe'
        Reject { Add-PtVerificationAssertion $b opens FAIL infrastructure wrong } 'taxonomy'
        Reject { Add-PtVerificationAssertion $b opens BLOCKED invented wrong } 'taxonomy'
        Reject { Add-PtVerificationAssertion $b opens PASS fixture 'Command success only' } 'evidence'
        Reject { Add-PtVerificationAssertion $b unknown NOT-OBSERVED not-observed wrong } 'Unknown inventory'
        Require ((Export-PtVerificationReport $run).Signoff -eq 'WITHHELD') 'Unwritten reservations must stay incomplete'
    }

    Check 'Throwing step retains stdout/error/source, rethrows original, and does not imply product FAIL' {
        $run = NewRun 'throw'
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name throwing -Activate
        Require ((Get-PtActiveVerificationAttempt).Id -eq $a.Id) 'Ambient context not set'
        Reject {
            Invoke-PtVerificationStep $a -Name throws -Command "'before'; throw 'original fixture error'" -Action {
                'before'
                Write-Warning 'synthetic warning'
                throw 'original fixture error'
            }
        } 'original fixture error'
        Stop-PtVerificationAttempt $a -Reason 'Caught original fixture error'
        Require ($null -eq (Get-PtActiveVerificationAttempt)) 'Ambient context not cleared'
        $export = Export-PtVerificationReport $run
        $state = Get-Content $export.Results -Raw | ConvertFrom-Json
        Require ($state.Steps.Count -eq 1 -and $state.Steps[0].Status -eq 'Error') 'Throwing step not recorded'
        Require ($state.Steps[0].Error.Message -eq 'original fixture error') 'Original error replaced'
        Require ($state.Items[0].Verdict -eq 'BLOCKED' -and $state.Items[0].Category -eq 'BLK-INFRASTRUCTURE') 'Execution error was treated as product result'
        $raw = $state.Steps[0].Outputs
        Require ([IO.File]::ReadAllText((Join-Path $run.Workspace ($raw | Where-Object Path -Like '*stdout.txt').Path)) -eq 'before') 'Partial stdout lost'
        Require ([IO.File]::ReadAllText((Join-Path $run.Workspace ($raw | Where-Object Path -Like '*error.txt').Path)).Contains('original fixture error')) 'Raw error missing'
        Require ([IO.File]::ReadAllText((Join-Path $run.Workspace ($raw | Where-Object Path -Like '*streams.jsonl').Path)).Contains('synthetic warning')) 'Warning stream missing'
        Require ($state.Signoff -eq 'WITHHELD') 'Partial run approved'
    }

    Check 'Recording failure in finally never masks original action error' {
        $run = NewRun 'finally-error'
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Synthetic capture failure'
        $caught = $null
        try {
            Invoke-PtVerificationStep $a -Name 'Remove only owned stdout fixture' -Command 'synthetic recorder fault; throw original' -Action {
                $stepPath = Join-Path $a.Run.Workspace "attempts\$($a.Id)\$($a.StepStack[-1])\stdout.txt"
                [IO.File]::Delete($stepPath)
                throw 'root action error survives'
            }
        } catch { $caught = $_ }
        Require ($caught.Exception.Message -eq 'root action error survives') 'Finally masked original action error'
        Require ([bool]$caught.Exception.Data['PtVerificationRecordingFailure']) 'Secondary recording failure was swallowed'
        $events = @(Read-PtReportEvents $run)
        Require (@($events | Where-Object Type -eq 'StepStarted').Count -eq 1) 'Interrupted step start missing'
        Require (@($events | Where-Object Type -eq 'StepEnded').Count -eq 0) 'Recording failure fabricated completed step'
    }

    Check 'Actual process interruption leaves incomplete start and raw output in portable partial report' {
        $run = NewRun 'interrupted'
        $childFile = "$Workspace\interrupt-fixture.ps1"
        $helperLiteral = ("$PSScriptRoot\..\pt-verification-report.ps1").Replace("'", "''")
        $rootLiteral = $run.Workspace.Replace("'", "''")
        $childText = @"
. '$helperLiteral'
`$run = Open-PtVerificationRun '$rootLiteral'
`$attempt = Start-PtVerificationAttempt `$run -ItemId L1 -Kind Normal -Name interrupted
Invoke-PtVerificationStep `$attempt -Name interruption -Command '[Environment]::Exit(23)' -Action { 'before interruption'; [Environment]::Exit(23) }
"@
        [IO.File]::WriteAllText($childFile, $childText)
        & (Get-Command pwsh -ErrorAction Stop).Source -NoProfile -File $childFile
        Require ($LASTEXITCODE -eq 23) 'Offline child did not interrupt as intended'
        $run = Open-PtVerificationRun $run.Workspace
        $export = Export-PtVerificationReport $run
        $state = Get-Content $export.Results -Raw | ConvertFrom-Json
        Require ($state.Steps[0].Status -eq 'INCOMPLETE') 'Interrupted step vanished'
        Require ($null -eq $state.Steps[0].End -and $null -eq $state.Steps[0].DurationMs) 'Interrupted step invented completion'
        Require (-not $state.Attempts[0].Complete -and $state.Signoff -eq 'WITHHELD') 'Interrupted attempt approved'
    }

    Check 'Nested ambient command recording preserves every helper probe, output type and implementation' {
        $run = NewRun 'nested'
        $a = Start-PtVerificationAttempt $run -Context Diagnostic -Kind Diagnostic -Name 'Synthetic helper probes' -Activate
        function Invoke-FakeWinApp {
            param([string[]]$Arguments, [int]$TimeoutSeconds = 17, [switch]$SkipRecording)
            $active = Get-PtActiveVerificationAttempt
            if ($active -and -not $SkipRecording) {
                return Invoke-PtVerificationStep -Attempt $active -Name 'winapp (synthetic)' `
                    -Command ('winapp ' + (($Arguments | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ' ')) `
                    -Implementation ${function:Invoke-FakeWinApp} -ArgumentList @($Arguments, $TimeoutSeconds) `
                    -Action { param($argv, $timeout) Invoke-FakeWinApp -Arguments $argv -TimeoutSeconds $timeout -SkipRecording }
            }
            if ($TimeoutSeconds -ne 17) { throw 'Timeout argument was changed or lost' }
            "SYNTHETIC raw: $($Arguments -join '|')"
        }
        $output = @(Invoke-PtVerificationStep $a -Name 'Outer helper script' -Command 'Invoke-FakeWinApp discovery; Invoke-FakeWinApp internal-probe' -Action {
            Invoke-FakeWinApp -Arguments @('list-windows',"a'b",$unicode)
            Invoke-FakeWinApp -Arguments @('inspect','internal-probe')
        })
        Require ($output.Count -eq 2 -and $output[0] -is [string]) 'Wrapper altered returned stdout type/count'
        Require ($output[0] -ceq "SYNTHETIC raw: list-windows|a'b|$unicode") 'Winapp integration changed Unicode/quoted arguments'
        Stop-PtVerificationAttempt $a -Reason 'All synthetic nested probes captured'
        $export = Export-PtVerificationReport $run
        $state = Get-Content $export.Results -Raw | ConvertFrom-Json
        Require ($state.Steps.Count -eq 3) 'Helper-generated discovery/probe command was lost'
        Require (@($state.Steps | Where-Object ParentStepId).Count -eq 2) 'Nested parent IDs missing'
        Require (@($state.References | Where-Object Path -Like '*implementation.ps1').Count -eq 2) 'Executed helper implementation missing'
    }

    Check 'Script-file snapshots execute the archived version; native failure is infrastructure only' {
        $run = NewRun 'script-files'
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name scripts
        $scriptFile = "$Workspace\version.ps1"
        [IO.File]::WriteAllText($scriptFile, "param(`$value) 'version-one:' + `$value")
        $output = Invoke-PtVerificationStep $a -Name version-one -Command '.\version.ps1 payload' -ScriptFile $scriptFile -ArgumentList @('payload')
        Require ($output -eq 'version-one:payload') 'Archived script not executed'
        [IO.File]::WriteAllText($scriptFile, "'version-two'")
        $output = Invoke-PtVerificationStep $a -Name version-two -Command '.\version.ps1' -ScriptFile $scriptFile
        Require ($output -eq 'version-two') 'Second script revision not executed'
        Reject {
            Invoke-PtVerificationStep $a -Name 'Synthetic native nonzero' -Command 'pwsh -NoProfile -Command exit 7' -Action {
                & (Get-Command pwsh).Source -NoProfile -Command 'exit 7'
            }
        } '7|non-zero'
        Stop-PtVerificationAttempt $a -Reason 'Versions and native failure recorded'
        $state = Get-Content (Export-PtVerificationReport $run).Results -Raw | ConvertFrom-Json
        $versions = @($state.References | Where-Object Path -Like '*executed.ps1')
        Require ($versions.Count -eq 3 -and $versions[0].Sha256 -ne $versions[1].Sha256) 'Script revisions collapsed'
        Require ($state.Items[0].Verdict -eq 'BLOCKED') 'Native exit code implied a product verdict'
    }

    Check 'Successful finalization requires explicit cleanup; missing screenshots and cleanup failures withhold' {
        $run = NewRun 'approved' @((Item 'L1' $true))
        Preflight $run
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name pass
        Observe $a -Image | Out-Null
        Stop-PtVerificationAttempt $a -Reason done
        Complete-PtVerificationItem $run L1 -Reason observed
        $partial = Get-Content (Export-PtVerificationReport $run).Results -Raw | ConvertFrom-Json
        Require ($partial.Signoff -eq 'WITHHELD') 'Missing cleanup approved'
        $snapshot = Export-PtVerificationReport $run
        Cleanup $run
        $export = Complete-PtVerificationRun $run -NoFriction
        Require ($export.Signoff -eq 'APPROVED') 'Complete synthetic fixture run not approved'
        Require (Test-PtVerificationArchive $run.Workspace).Valid 'Approved archive invalid'
        Require (Test-PtVerificationArchive $run.Workspace -ManifestName ([IO.Path]::GetFileName($snapshot.Manifest))).Valid 'Partial snapshot invalidated by later journal entries'
        $run = NewRun 'no-screenshot' @((Item 'L1' $true))
        Preflight $run
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name pass
        Observe $a | Out-Null
        Stop-PtVerificationAttempt $a -Reason done
        Complete-PtVerificationItem $run L1 -Reason observed
        Cleanup $run 'FAIL'
        $state = Get-Content (Complete-PtVerificationRun $run -NoFriction).Results -Raw | ConvertFrom-Json
        Require ($state.Items[0].Verdict -eq 'BLOCKED') 'Visible item passed without screenshot'
        Require ($state.Signoff -eq 'WITHHELD') 'Cleanup failure approved'
        Require (@($state.SignoffReasons | Where-Object { $_ -match 'cleanup failed' }).Count -eq 1) 'Cleanup failure hidden'
    }

    Check 'Cleanup retry requires its own restoration evidence, not an earlier PASS receipt' {
        $run = NewRun 'cleanup-retry-evidence'
        Preflight $run
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Observed Normal flow'
        Observe $a | Out-Null
        Stop-PtVerificationAttempt $a -Reason observed
        Complete-PtVerificationItem $run L1 -Reason observed
        $cleanup = Start-PtVerificationAttempt $run -Context Cleanup -Kind Normal -Name 'Cleanup later interrupted'
        Invoke-PtVerificationStep $cleanup -Name 'Initial comparison' -Command "'synthetic baseline matches'" -Action { 'baseline matches' } | Out-Null
        $proof = Add-PtVerificationArtifact $cleanup $fixture Restoration 'Earlier synthetic restoration receipt' -Synthetic
        Add-PtVerificationRestoration $cleanup -Verdict PASS -Reason 'Initial comparison only' -Evidence @($proof)
        Reject { Invoke-PtVerificationStep $cleanup -Name 'Cleanup error' -Command 'synthetic-cleanup-error' -Action { throw 'cleanup interrupted' } } 'cleanup interrupted'
        Stop-PtVerificationAttempt $cleanup -Reason 'Retry must verify the final state'
        $retry = Start-PtVerificationAttempt $run -Context Cleanup -Kind Normal -Name 'Driver probe only'
        Invoke-PtVerificationStep $retry -Name 'Driver ready' -Command "'driver available'" -Action { 'driver available' } | Out-Null
        Stop-PtVerificationAttempt $retry -Reason 'No final restoration observation yet'
        $state = Get-PtReportState $run
        Require (@($state.SignoffReasons | Where-Object { $_ -match 'Latest Normal Cleanup' }).Count -eq 1) 'Stale PASS receipt satisfied the current cleanup gate'
        $missing = Complete-PtVerificationRun $run -NoFriction
        Require ($missing.Signoff -eq 'WITHHELD') 'Cleanup retry without its own evidence was approved'
        Require ((Test-PtVerificationArchive $run.Workspace).Signoff -eq 'WITHHELD') 'Archive validation lost the missing-restoration gate'

        $run = NewRun 'cleanup-retry-verified'
        Preflight $run
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Observed Normal flow'
        Observe $a | Out-Null
        Stop-PtVerificationAttempt $a -Reason observed
        Complete-PtVerificationItem $run L1 -Reason observed
        $cleanup = Start-PtVerificationAttempt $run -Context Cleanup -Kind Normal -Name 'Failed driver'
        Reject { Invoke-PtVerificationStep $cleanup -Name 'Driver error' -Command 'synthetic-driver-error' -Action { throw 'driver unavailable' } } 'driver unavailable'
        Stop-PtVerificationAttempt $cleanup -Reason 'Driver repaired before repeating complete cleanup'
        Cleanup $run
        Require ((Complete-PtVerificationRun $run -NoFriction).Signoff -eq 'APPROVED') 'A retry with its own successful restoration evidence was rejected'
    }

    Check 'Frozen partial archive validates independently of damaged or absent live journal' {
        $run = NewRun 'partial-journal-isolation'
        Preflight $run
        $partial = Export-PtVerificationReport $run
        $manifestName = [IO.Path]::GetFileName($partial.Manifest)
        $live = Join-Path $run.Workspace 'events.jsonl'
        [IO.File]::AppendAllText($live, '{"Payload":')
        Require (Test-PtVerificationArchive $run.Workspace -ManifestName $manifestName).Valid 'Later interrupted append invalidated the frozen partial'
        Move-Item -LiteralPath $live -Destination "$live.interrupted"
        Require (Test-PtVerificationArchive $run.Workspace -ManifestName $manifestName).Valid 'Frozen partial depends on live journal existence'
        $manifest = Get-Content $partial.Manifest -Raw | ConvertFrom-Json
        $frozen = Join-Path $run.Workspace $manifest.JournalPath
        [IO.File]::AppendAllText($frozen, '{"Payload":')
        Reject { Test-PtVerificationArchive $run.Workspace -ManifestName $manifestName } 'JSON|parse|invalid'
    }

    Check 'ISO-looking verbatim text survives parsing; finalization corruption preserves diagnostics' {
        $inventory = Item 'L1'
        $inventory.Description = '2020-01-02T03:04:05.678Z'
        $run = NewRun 'verbatim-date' @($inventory)
        Preflight $run
        $state = Get-PtReportState $run
        Require ($state.Items[0].Description -is [string] -and $state.Items[0].Description -ceq $inventory.Description) 'ISO text was coerced into a date'
        Require ($state.Steps[0].Start -is [string] -and $state.Steps[0].Start.Contains('+00:00')) 'Event timestamp lost UTC offset/precision'
        $elapsed = ([DateTimeOffset]::Parse($state.Steps[0].End) - [DateTimeOffset]::Parse($state.Steps[0].Start)).TotalMilliseconds
        Require ([Math]::Abs($state.Steps[0].DurationMs - $elapsed) -lt 0.01) 'Step duration disagrees with start/end'
        [IO.File]::WriteAllText("$($run.Workspace)\inputs\skill.txt", 'corrupt')
        Reject { Complete-PtVerificationRun $run -NoFriction } 'Changed evidence'
        Require (@(Get-ChildItem $run.Workspace -Filter 'finalization-failure-*.txt').Count -eq 1) 'Finalization failure lost persistent error'
        Require (-not (Test-Path "$($run.Workspace)\report.md")) 'Invalid final report was produced'
        Require (@(Read-PtReportEvents $run | Where-Object Type -eq 'RunCompleted').Count -eq 0) 'Corrupt run was marked complete'
    }

    Check 'No implicit verdicts; Normal failures stay sticky and Diagnostic failures withhold signoff' {
        $run = NewRun 'verdict-gates' @((Item 'L1'),(Item 'L2'))
        Preflight $run
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Successful command without product observation'
        Invoke-PtVerificationStep $a -Name 'Command only' -Command "'zero exit code is not PASS'" -Action { 0 } | Out-Null
        Stop-PtVerificationAttempt $a -Reason 'No behavioral assertions made'
        Complete-PtVerificationItem $run L1 -Reason 'Commands alone do not prove product behavior'
        $a = Start-PtVerificationAttempt $run -ItemId L2 -Kind Normal -Name 'Normal failed'
        $proof = Observe $a
        Add-PtVerificationAssertion $a opens FAIL checklist-ambiguous 'Synthetic ambiguity is unresolved' -Evidence @($proof)
        Stop-PtVerificationAttempt $a -Reason failed
        $a = Start-PtVerificationAttempt $run -ItemId L2 -Kind Normal -Name 'Later Normal pass must not erase failure'
        Observe $a | Out-Null
        Stop-PtVerificationAttempt $a -Reason 'Later successful observation preserved separately'
        Complete-PtVerificationItem $run L2 -Reason 'Original checklist failure retained'
        Cleanup $run
        $state = Get-Content (Complete-PtVerificationRun $run -NoFriction).Results -Raw | ConvertFrom-Json
        Require ($state.Items[0].Verdict -eq 'BLOCKED') 'Successful command inferred PASS'
        Require ($state.Items[1].Verdict -eq 'FAIL' -and $state.Items[1].Category -eq 'checklist-ambiguous') 'Later Normal PASS erased earlier failure'
        $run = NewRun 'diagnostic-failure'
        Preflight $run
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Normal successful'
        Observe $a | Out-Null
        Stop-PtVerificationAttempt $a -Reason done
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Diagnostic -Name 'Additional diagnostic failed'
        $proof = Observe $a
        Add-PtVerificationAssertion $a content FAIL product 'Synthetic diagnostic failure must remain visible' -Evidence @($proof)
        Stop-PtVerificationAttempt $a -Reason failed
        Complete-PtVerificationItem $run L1 -Reason 'Normal observations intact; diagnostic failure retained'
        Cleanup $run
        $export = Complete-PtVerificationRun $run -NoFriction
        Require ($export.Signoff -eq 'WITHHELD') 'Diagnostic failure silently discarded'
    }

    Check 'Sealed evidence metadata cannot be relabeled; synthetic screenshots never prove product behavior' {
        $run = New-PtVerificationRun -Workspace "$Workspace\synthetic-product-gate" -Module 'Synthetic gate fixture only' `
            -Bits 'Synthetic offline fixture, not installed PowerToys' -Scenario A -Items @((Item 'L1' $true)) -Inputs $inputs
        Preflight $run
        $a = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Synthetic gate fixture'
        $proof = Observe $a -Image
        $forged = $proof | ConvertTo-Json | ConvertFrom-Json
        $forged.Kind = 'Screenshot'
        Reject { Add-PtVerificationAssertion $a opens PASS fake 'Forged screenshot label' -Evidence @($forged) } 'metadata differs'
        $forged = $proof | ConvertTo-Json | ConvertFrom-Json
        $forged.Synthetic = $false
        Reject { Add-PtVerificationAssertion $a opens PASS fake 'Removed synthetic label' -Evidence @($forged) } 'metadata differs'
        Stop-PtVerificationAttempt $a -Reason 'Synthetic observations deliberately cannot prove product behavior'
        Complete-PtVerificationItem $run L1 -Reason 'Product screenshot requirement not met by synthetic PNG'
        Cleanup $run
        $state = Get-Content (Complete-PtVerificationRun $run -NoFriction).Results -Raw | ConvertFrom-Json
        Require ($state.Items[0].Verdict -eq 'BLOCKED' -and $state.Signoff -eq 'WITHHELD') 'Synthetic screenshot approved product signoff'
    }

    Check 'Complete Normal rerun supersedes driver errors, never product failures or missing coverage' {
        $run = NewRun 'driver-recovery'
        Preflight $run
        $failed = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Driver not ready'
        Reject { Invoke-PtVerificationStep $failed -Name 'Broken driver' -Command 'synthetic-invalid-HWND' -Action { throw 'synthetic driver error' } } 'synthetic driver error'
        Stop-PtVerificationAttempt $failed -Reason 'Driver repaired; no product assertion was possible'
        $diagnostic = Start-PtVerificationAttempt $run -ItemId L1 -Kind Diagnostic -Name 'Unsupported probe'
        Reject { Invoke-PtVerificationStep $diagnostic -Name 'Unsupported pattern' -Command 'synthetic-unsupported-pattern' -Action { throw 'unsupported probe' } } 'unsupported probe'
        Stop-PtVerificationAttempt $diagnostic -Reason 'Probe did not support this path'
        $retry = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Complete ordinary-path rerun'
        Observe $retry | Out-Null
        Stop-PtVerificationAttempt $retry -Reason 'All required coverage repeated'
        Complete-PtVerificationItem $run L1 -Reason 'Normal flow observed after driver repair, not diagnostic recovery'
        Cleanup $run
        $export = Complete-PtVerificationRun $run -NoFriction
        $state = Get-Content $export.Results -Raw | ConvertFrom-Json
        Require ($state.Items[0].Verdict -eq 'PASS' -and $state.Signoff -eq 'APPROVED') 'Closed driver errors permanently blocked a complete Normal rerun'
        Require (@($state.Steps | Where-Object Status -eq 'Error').Count -eq 2) 'Earlier error evidence was erased'

        $run = NewRun 'no-cross-attempt-coverage'
        foreach ($child in 'opens','content') {
            $attempt = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name "Only $child observed"
            Invoke-PtVerificationStep $attempt -Name 'Partial probe' -Command $child -Action { 'partial evidence' } | Out-Null
            $proof = Add-PtVerificationArtifact $attempt $fixture Evidence 'Partial observation' -Synthetic
            Add-PtVerificationAssertion $attempt $child PASS 'synthetic comparison' 'Only this child observed' -Evidence @($proof)
            Stop-PtVerificationAttempt $attempt -Reason 'Partial attempt'
        }
        Complete-PtVerificationItem $run L1 -Reason 'Cannot combine stale attempts into full coverage'
        $state = Get-PtReportState $run
        Require ($state.Items[0].Verdict -eq 'BLOCKED' -and $state.Items[0].Assertions[0].Verdict -eq 'NOT-OBSERVED') 'Stale assertions were combined across attempts'
    }

    Check 'Unwritten reservations remain exportable as incomplete, not missing registered evidence' {
        $run = NewRun 'unwritten-reservation'
        $attempt = Start-PtVerificationAttempt $run -ItemId L1 -Kind Normal -Name 'Capture aborted before file creation'
        New-PtVerificationArtifactPath $attempt 'never-captured.png' | Out-Null
        $export = Export-PtVerificationReport $run
        Require ($export.Signoff -eq 'WITHHELD') 'Unwritten reservation was approved'
        Require (Test-PtVerificationArchive $run.Workspace -ManifestName ([IO.Path]::GetFileName($export.Manifest))).Valid 'Partial reservation export is not portable'
    }

    Check 'Final export bypasses a live cache even for same-size same-timestamp journal edits' {
        $run = NewRun 'cache-integrity'
        Preflight $run
        Read-PtReportEvents $run | Out-Null
        $journal = Join-Path $run.Workspace 'events.jsonl'
        $original = [IO.File]::ReadAllText($journal)
        $timestamp = [IO.File]::GetLastWriteTimeUtc($journal)
        $changed = $original.Replace('Offline fixture preflight','Changed fixture preflight')
        Require ($changed -cne $original -and $changed.Length -eq $original.Length) 'Tamper fixture must preserve length'
        [IO.File]::WriteAllText($journal, $changed)
        [IO.File]::SetLastWriteTimeUtc($journal, $timestamp)
        Reject { Export-PtVerificationReport $run } 'hash mismatch'
    }

    Check 'Filesystem junctions remain rejected while cloud-placeholder support is enabled' {
        $target = Join-Path $Workspace 'junction-target'
        $link = Join-Path $Workspace 'junction-link'
        [IO.Directory]::CreateDirectory($target) | Out-Null
        New-Item -ItemType Junction -Path $link -Target $target -ErrorAction Stop | Out-Null
        try { Reject { Assert-PtReportNoLink $link } 'reparse point' }
        finally { [IO.Directory]::Delete($link) }
        Require ([IO.Directory]::Exists($target)) 'Removing the test junction affected its target'
    }

    Check 'Hash-chained journal detects missing/reordered/changed commands' {
        $run = NewRun 'corrupt-journal'
        Preflight $run
        $journal = "$($run.Workspace)\events.jsonl"
        $lines = [IO.File]::ReadAllLines($journal)
        [IO.File]::WriteAllLines($journal, @($lines[0]) + @($lines[2..($lines.Count - 1)]))
        Reject { Export-PtVerificationReport $run } 'missing/reordered'
        [IO.File]::WriteAllLines($journal, $lines)
        $envelope = $lines[2] | ConvertFrom-Json
        $envelope.Payload = $envelope.Payload.Replace('Synthetic preflight','FALSIFIED command')
        $changed = @($lines)
        $changed[2] = $envelope | ConvertTo-Json -Compress
        [IO.File]::WriteAllLines($journal, $changed)
        Reject { Export-PtVerificationReport $run } 'hash mismatch'
        [IO.File]::WriteAllLines($journal, $lines)
    }
    "PASS: $($results.Count) offline groups. Synthetic evidence: $Workspace"
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-PtVerificationReportAcceptance -Workspace $Workspace
}
