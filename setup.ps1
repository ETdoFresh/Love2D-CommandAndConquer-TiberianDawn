#!/usr/bin/env pwsh
# Setup script for LoveCommandAndConquer2D
# Clones the CnC Remastered Collection source code if not already present

$repo_url = "https://github.com/electronicarts/CnC_Remastered_Collection"
$target_dir = "temp/CnC_Remastered_Collection"

if (Test-Path $target_dir) {
    Write-Host "Source code already exists at $target_dir" -ForegroundColor Green
} else {
    Write-Host "Cloning CnC Remastered Collection..." -ForegroundColor Yellow

    # Create temp directory if it doesn't exist
    if (-not (Test-Path "temp")) {
        New-Item -ItemType Directory -Path "temp" | Out-Null
    }

    git clone $repo_url $target_dir

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully cloned to $target_dir" -ForegroundColor Green
    } else {
        Write-Host "Failed to clone repository" -ForegroundColor Red
        exit 1
    }
}
