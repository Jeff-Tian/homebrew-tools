Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

function Get-ToolVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ToolName
    )

    $scriptPath = Join-Path $repoRoot "bin/$ToolName"
    if (-not (Test-Path $scriptPath)) {
        throw "Missing tool script: $scriptPath"
    }

    $content = Get-Content -Raw $scriptPath
    if ($content -notmatch 'VERSION="(?<version>[^"]+)"') {
        throw "Could not find VERSION in $scriptPath"
    }

    return $Matches.version
}

function Assert-Wrapper {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ToolName
    )

    $wrapperPath = Join-Path $repoRoot "bin/$ToolName.cmd"
    if (-not (Test-Path $wrapperPath)) {
        throw "Missing Windows wrapper: $wrapperPath"
    }

    $content = Get-Content -Raw $wrapperPath
    if ($content -notmatch 'where bash') {
        throw "$wrapperPath should check that bash is available"
    }
    $expectedInvocation = 'bash "%~dp0{0}" %*' -f $ToolName
    if ($content -notmatch [regex]::Escape($expectedInvocation)) {
        throw "$wrapperPath should invoke the colocated Bash script"
    }
    if ($content -notmatch 'exit /b %ERRORLEVEL%') {
        throw "$wrapperPath should preserve the Bash script exit code"
    }

    $versionOutput = & $wrapperPath --version
    if ($LASTEXITCODE -ne 0) {
        throw "$wrapperPath --version failed with exit code $LASTEXITCODE"
    }

    $expectedVersion = Get-ToolVersion $ToolName
    if ($versionOutput -notmatch [regex]::Escape($expectedVersion)) {
        throw "$wrapperPath --version output '$versionOutput' did not include '$expectedVersion'"
    }
}

function Assert-Manifest {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ToolName,

        [Parameter(Mandatory = $true)]
        [string[]] $ExpectedDependencies
    )

    $manifestPath = Join-Path $repoRoot "bucket/$ToolName.json"
    if (-not (Test-Path $manifestPath)) {
        throw "Missing Scoop manifest: $manifestPath"
    }

    $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
    $expectedVersion = Get-ToolVersion $ToolName
    if ($manifest.version -ne $expectedVersion) {
        throw "$manifestPath version '$($manifest.version)' should match script version '$expectedVersion'"
    }

    foreach ($dependency in $ExpectedDependencies) {
        if ($manifest.depends -notcontains $dependency) {
            throw "$manifestPath should depend on '$dependency'"
        }
    }

    $urls = @($manifest.url)
    foreach ($fileName in @($ToolName, "$ToolName.cmd")) {
        $expectedUrl = "https://raw.githubusercontent.com/Jeff-Tian/homebrew-tools/main/bin/$fileName#/$fileName"
        if ($urls -notcontains $expectedUrl) {
            throw "$manifestPath should download $expectedUrl"
        }
    }

    $hashes = @($manifest.hash)
    $nonSkipHashes = @($hashes | Where-Object { $_ -ne 'skip' })
    if ($hashes.Count -ne 2 -or $nonSkipHashes.Count -ne 0) {
        throw "$manifestPath should use two 'skip' hashes for branch-based raw URLs"
    }

    $binEntries = @($manifest.bin)
    $hasAlias = $false
    foreach ($entry in $binEntries) {
        if ($entry[0] -eq "$ToolName.cmd" -and $entry[1] -eq $ToolName) {
            $hasAlias = $true
        }
    }
    if (-not $hasAlias) {
        throw "$manifestPath should expose '$ToolName' via the .cmd wrapper"
    }
}

Assert-Wrapper 'git-auto-commit'
Assert-Wrapper 'git-dco'
Assert-Manifest 'git-auto-commit' @('git', 'curl', 'jq')
Assert-Manifest 'git-dco' @('git')

Write-Host 'Windows packaging checks passed.'
