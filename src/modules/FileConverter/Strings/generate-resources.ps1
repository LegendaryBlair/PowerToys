param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path

function Get-ResourceSymbol {
    param([string]$Name)

    return "IDS_" + [regex]::Replace($Name.ToUpperInvariant(), "[^A-Z0-9_]", "_")
}

function Escape-RcString {
    param([string]$Value)

    $escaped = $Value.Replace("\", "\\")
    $escaped = $escaped.Replace('"', '""')
    $escaped = $escaped.Replace("`r", "")
    return $escaped.Replace("`n", "\n")
}

function Write-FileIfChanged {
    param(
        [string]$Path,
        [string]$Content
    )

    if ((Test-Path -LiteralPath $Path) -and (Get-Content -LiteralPath $Path -Raw) -eq $Content) {
        return
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true))
}

$baseResourcePath = Join-Path $SourceRoot "en-us\Resources.resx"
if (-not (Test-Path -LiteralPath $baseResourcePath)) {
    throw "Base FileConverter resources were not found at '$baseResourcePath'."
}

New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null

[xml]$baseResources = Get-Content -LiteralPath $baseResourcePath -Raw
$resourceIds = [ordered]@{}
$nextResourceId = 101
foreach ($entry in $baseResources.root.data) {
    $name = [string]$entry.name
    $symbol = Get-ResourceSymbol -Name $name
    if ($resourceIds.Contains($name)) {
        throw "Duplicate FileConverter resource key '$name'."
    }

    if ($resourceIds.Values -contains $symbol) {
        throw "FileConverter resource key '$name' maps to duplicate symbol '$symbol'."
    }

    $resourceIds[$name] = [pscustomobject]@{
        Id = $nextResourceId
        Symbol = $symbol
    }
    $nextResourceId++
}

$headerLines = @(
    "// This file is generated from FileConverter Strings resources.",
    "#pragma once",
    ""
)
foreach ($resource in $resourceIds.Values) {
    $headerLines += "#define $($resource.Symbol) $($resource.Id)"
}
$headerContent = ($headerLines -join "`r`n") + "`r`n"

$resourceFiles = @(
    Get-Item -LiteralPath $baseResourcePath
    Get-ChildItem -LiteralPath $SourceRoot -Recurse -Filter Resources.resx |
        Where-Object { $_.FullName -ne $baseResourcePath } |
        Sort-Object FullName
)

$rcLines = @(
    "// This file is generated from FileConverter Strings resources.",
    "#include <windows.h>",
    '#include "FileConverterResources.h"',
    "#pragma code_page(65001)",
    ""
)

foreach ($resourceFile in $resourceFiles) {
    $cultureName = $resourceFile.Directory.Name
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo($cultureName)
    $languageId = $culture.LCID -band 0xFFFF
    $primaryLanguage = $languageId -band 0x03FF
    $subLanguage = ($languageId -shr 10) -band 0x003F

    [xml]$resources = Get-Content -LiteralPath $resourceFile.FullName -Raw
    $rcLines += "LANGUAGE $primaryLanguage, $subLanguage"
    $rcLines += "STRINGTABLE"
    $rcLines += "BEGIN"
    foreach ($entry in $resources.root.data) {
        $name = [string]$entry.name
        if (-not $resourceIds.Contains($name)) {
            throw "Localized FileConverter resource '$name' is missing from the en-us resource set."
        }

        $symbol = $resourceIds[$name].Symbol
        $value = Escape-RcString -Value ([string]$entry.value)
        $rcLines += "    $symbol L`"$value`""
    }
    $rcLines += "END"
    $rcLines += ""
}

$rcContent = ($rcLines -join "`r`n") + "`r`n"
Write-FileIfChanged -Path (Join-Path $OutputDirectory "FileConverterResources.h") -Content $headerContent
Write-FileIfChanged -Path (Join-Path $OutputDirectory "FileConverterResources.rc") -Content $rcContent
