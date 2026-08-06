<#
.SYNOPSIS
    Validates that all C# projects in the repository import a required shared props file.

.DESCRIPTION
    Recursively searches for .csproj files under the given root directory and checks that
    each one imports either Common.Dotnet.CsWinRT.props or Common.Dotnet.props. These
    shared MSBuild props files enforce consistent build settings across all C# projects.

.PARAMETER sourceDir
    Root directory to recursively search for .csproj files.

.OUTPUTS
    Writes the path of any non-conforming or malformed .csproj file to the output stream.
    Exits with code 1 if any such files are found, and with code 0 otherwise.
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $True, Position = 1)]
    [string]$sourceDir
)

$hasInvalidCsProj = $false

$csprojFiles = [System.IO.Directory]::EnumerateFiles($sourceDir, '*.csproj', [System.IO.SearchOption]::AllDirectories)

foreach ($csprojFile in $csprojFiles) {
    $filename = [System.IO.Path]::GetFileName($csprojFile)

    # Skip the CmdPal extension template project, which doesn't require the shared props.
    if ($filename -eq 'TemplateCmdPalExtension.csproj') {
        continue
    }

    $importExists = $false

    try {
        $xml = [System.Xml.XmlDocument]::new()
        $xml.XmlResolver = $null
        $readerSettings = [System.Xml.XmlReaderSettings]::new()
        $readerSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $readerSettings.XmlResolver = $null
        $reader = [System.Xml.XmlReader]::Create($csprojFile, $readerSettings)

        try {
            $xml.Load($reader)
        }
        finally {
            $reader.Dispose()
        }

        # The '*' wildcard matches Import elements regardless of XML namespace.
        foreach ($importNode in $xml.GetElementsByTagName('Import', '*')) {
            $importProject = $importNode.GetAttribute('Project')

            if (-not [string]::IsNullOrEmpty($importProject)) {
                $importFilename = [System.IO.Path]::GetFileName($importProject)

                if ($importFilename -eq 'Common.Dotnet.CsWinRT.props' -or $importFilename -eq 'Common.Dotnet.props') {
                    $importExists = $true
                    break
                }
            }
        }
    }
    catch {
        Write-Output "Error parsing ${csprojFile}: $_"
        $hasInvalidCsProj = $true
        continue
    }

    if (-not $importExists) {
        Write-Output "$csprojFile needs to import 'Common.Dotnet.CsWinRT.props' or 'Common.Dotnet.props'."
        $hasInvalidCsProj = $true
    }
}

if ($hasInvalidCsProj) {
    exit 1
}

exit 0
