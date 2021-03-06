# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT
#

<#
.SYNOPSIS
Runs the 'Test Modified Ports' part of the vcpkg CI system for all platforms.

.PARAMETER Triplet
The triplet to test.

.PARAMETER ArchivesRoot
The location where the binary caching archives are stored. Shared across runs of this script.

.PARAMETER WorkingRoot
The location used as scratch space for 'installed', 'packages', and 'buildtrees' vcpkg directories.

.PARAMETER ArtifactStagingDirectory
The Azure Pipelines artifact staging directory. If not supplied, defaults to the current directory.

.PARAMETER ArtifactsDirectory
The Azure Pipelines artifacts directory. If not supplied, defaults to the current directory.

.PARAMETER BuildReason
The reason Azure Pipelines is running this script (controls whether Binary Caching is used). If not
supplied, binary caching will be used.
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$Triplet,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $ArchivesRoot,
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    $WorkingRoot,
    [ValidateNotNullOrEmpty()]
    $ArtifactStagingDirectory = '.',
    [ValidateNotNullOrEmpty()]
    $ArtifactsDirectory = '.',
    $BuildReason = $null
)

if (-Not (Test-Path "triplets/$Triplet.cmake")) {
    Write-Error "Incorrect triplet '$Triplet', please supply a valid triplet."
}

$env:VCPKG_DOWNLOADS = Join-Path $WorkingRoot 'downloads'
$buildtreesRoot = Join-Path $WorkingRoot 'buildtrees'
$installRoot = Join-Path $WorkingRoot 'installed'
$packagesRoot = Join-Path $WorkingRoot 'packages'
$commonArgs = @(
    "--x-buildtrees-root=$buildtreesRoot",
    "--x-install-root=$installRoot",
    "--x-packages-root=$packagesRoot"
)

$binaryCaching = $false
if ([string]::IsNullOrWhiteSpace($BuildReason)) {
    Write-Host 'Build reason not specified, defaulting to using binary caching.'
    $binaryCaching = $true
} elseif ($BuildReason -eq 'PullRequest') {
    Write-Host 'Build reason was Pull Request, using binary caching.'
    $binaryCaching = $true
}

if ($binaryCaching) {
    $commonArgs += @(
        '--binarycaching',
        "--x-binarysource=clear;files,$ArchivesRoot,upload"
    )
}

if ($Triplet -eq 'x64-linux') {
    $env:HOME = '/home/agent'
    $executableExtension = [string]::Empty
} elseif ($Triplet -eq 'x64-osx') {
    $executableExtension = [string]::Empty
} else {
    $executableExtension = '.exe'
}

$xmlResults = Join-Path $ArtifactsDirectory 'xml-results'
mkdir $xmlResults
$xmlFile = Join-Path $xmlResults "$Triplet.xml"

& "./vcpkg$executableExtension" x-ci-clean @commonArgs
$skipList = . "$PSScriptRoot/generate-skip-list.ps1" -Triplet $Triplet -BaselineFile "$PSScriptRoot/../ci.baseline.txt"

# WORKAROUND: the x86-windows flavors of these are needed for all cross-compilation, but they are not auto-installed.
# Install them so the CI succeeds:
if ($Triplet -in @('x64-uwp', 'arm64-windows', 'arm-uwp')) {
    .\vcpkg.exe install protobuf:x86-windows boost-build:x86-windows sqlite3:x86-windows @commonArgs
}

& "./vcpkg$executableExtension" ci $Triplet --x-xunit=$xmlFile --exclude=$skipList @commonArgs
& "$PSScriptRoot/analyze-test-results.ps1" -logDir $xmlResults -outputDir $ArtifactStagingDirectory `
    -failureLogDir (Join-Path $ArchivesRoot 'fail') -triplets $Triplet -errorOnRegression `
    -baselineFile .\scripts\ci.baseline.txt
