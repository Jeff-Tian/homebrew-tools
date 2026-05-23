[CmdletBinding()]
param(
    [string] $InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\JeffTianTools\bin'),
    [switch] $InstallDependencies,
    [switch] $NoPathUpdate,
    [switch] $SkipDependencyCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$sourceBin = Join-Path $repoRoot 'bin'
$tools = @('git-auto-commit', 'git-auto-commit.cmd', 'git-dco', 'git-dco.cmd')

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string] $Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-RequiredDependencies {
    if (-not (Test-CommandAvailable 'scoop')) {
        Write-Host 'Installing Scoop for the current user...'
        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    }

    $packages = @('git', 'jq', 'curl')
    foreach ($package in $packages) {
        Write-Host "Ensuring Scoop package is installed: $package"
        scoop install $package | Out-Host
    }
}

function Assert-Dependencies {
    $missing = @()
    foreach ($command in @('git', 'bash', 'jq', 'curl')) {
        if (-not (Test-CommandAvailable $command)) {
            $missing += $command
        }
    }

    if ($missing.Count -gt 0) {
        $missingList = $missing -join ', '
        throw "Missing required command(s): $missingList. Re-run with -InstallDependencies or install them with: scoop install git jq curl"
    }
}

function Add-InstallDirToUserPath {
    param([Parameter(Mandatory = $true)][string] $PathToAdd)

    $fullPath = [System.IO.Path]::GetFullPath($PathToAdd)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $pathEntries = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $alreadyPresent = $false
    foreach ($entry in $pathEntries) {
        if ([string]::Equals([System.IO.Path]::GetFullPath($entry), $fullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $alreadyPresent = $true
            break
        }
    }

    if (-not $alreadyPresent) {
        $newUserPath = (($pathEntries + $fullPath) -join ';')
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        Write-Host "Added to user PATH: $fullPath"
    }

    if (($env:Path -split ';') -notcontains $fullPath) {
        $env:Path = "$fullPath;$env:Path"
    }
}

if ($InstallDependencies) {
    Install-RequiredDependencies
}

if (-not $SkipDependencyCheck) {
    Assert-Dependencies
}

foreach ($tool in $tools) {
    $sourcePath = Join-Path $sourceBin $tool
    if (-not (Test-Path $sourcePath)) {
        throw "Missing source file: $sourcePath"
    }
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
foreach ($tool in $tools) {
    Copy-Item -Force -Path (Join-Path $sourceBin $tool) -Destination (Join-Path $InstallDir $tool)
}

if (-not $NoPathUpdate) {
    Add-InstallDirToUserPath $InstallDir
}

Write-Host "Installed git-auto-commit and git-dco to: $InstallDir"
Write-Host 'Open a new terminal, then run:'
Write-Host '  git auto-commit --version'
Write-Host '  git dco --version'
