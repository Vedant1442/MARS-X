# MARS-X Backend Startup Script for Windows PowerShell
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Check virtual environment
$VenvPython = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $VenvPython)) {
    Write-Host "[MARS-X] Creating Python virtual environment..." -ForegroundColor Cyan
    uv venv (Join-Path $ProjectRoot ".venv")
    & (Join-Path $ProjectRoot ".venv\Scripts\uv.exe") pip install -r (Join-Path $ScriptDir "requirements.txt")
}

Write-Host "[MARS-X] Starting FastAPI server on http://localhost:8000..." -ForegroundColor Green
Write-Host "[MARS-X] API Docs available at http://localhost:8000/docs" -ForegroundColor Yellow

Set-Location $ProjectRoot
& $VenvPython -m uvicorn app.main:app --app-dir backend --host 0.0.0.0 --port 8000 --reload
