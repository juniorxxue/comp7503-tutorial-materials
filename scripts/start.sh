#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  cp .env.example .env
fi

./scripts/render-flow.sh

docker compose up --build -d
