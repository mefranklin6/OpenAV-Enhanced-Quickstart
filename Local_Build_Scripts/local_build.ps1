# Windows dev script that removes any old container and rebuilds a new one with your changes
# Place this in the root of your microservice repository

param (
    [Parameter(Mandatory = $true)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

# Ensure Docker CLI is available
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker CLI not found in PATH."
    exit 1
}

# Run from the repo root (script directory)
Set-Location -Path $PSScriptRoot

# Find container(s) (running or stopped) for this Name
$containers = docker ps -aqf "ancestor=$Name"
if ($containers) {
    Write-Host "Stopping and removing existing containers for Name '$Name'..."
    $containers -split "\r?\n" | Where-Object { $_ } | ForEach-Object {
        try { docker stop $_ | Out-Null } catch {}
        try { docker rm $_   | Out-Null } catch {}
    }
}

# Rebuild and run
Write-Host "Building Name '$Name'..."
docker build -D -t $Name .
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker build failed."
    exit 1
}

Write-Host "Done."