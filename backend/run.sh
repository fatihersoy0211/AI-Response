#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo ".env olusturuldu. OPENAI_API_KEY degerini guncelleyin."
fi

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

HOST=${APP_HOST:-0.0.0.0}
PORT=${APP_PORT:-8080}

uvicorn app.main:app --host "$HOST" --port "$PORT" --reload
