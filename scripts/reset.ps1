Set-Location (Join-Path $PSScriptRoot "..")

docker compose down -v --remove-orphans
