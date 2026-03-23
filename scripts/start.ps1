Set-Location (Join-Path $PSScriptRoot "..")

if (-not (Test-Path .env)) {
  Copy-Item .env.example .env
}

& .\scripts\render-flow.ps1

docker compose up --build -d
