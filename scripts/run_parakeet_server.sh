#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PATH="${PROJECT_ROOT}/nemo-env/bin/activate"
DEFAULT_MODEL="${PROJECT_ROOT}/models/parakeet/parakeet-tdt-0.6b-v2.nemo"

if [[ ! -f "${VENV_PATH}" ]]; then
  echo "Virtual environment not found at ${VENV_PATH}." >&2
  echo "Create it with: python3 -m venv nemo-env && source nemo-env/bin/activate && pip install nemo-toolkit[asr] fastapi uvicorn[standard]" >&2
  exit 1
fi

if [[ ! -f "${DEFAULT_MODEL}" && -z "${MODEL_PATH:-}" ]]; then
  cat >&2 <<'EOF'
No Parakeet model found.
Download it with:
  mkdir -p models/parakeet
  curl -L https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2/resolve/main/parakeet-tdt-0.6b-v2.nemo \
       -o models/parakeet/parakeet-tdt-0.6b-v2.nemo
EOF
  exit 1
fi

source "${VENV_PATH}"

export MODEL_PATH="${MODEL_PATH:-${DEFAULT_MODEL}}"
PORT="${PORT:-8000}"
HOST="${HOST:-0.0.0.0}"

echo "Using MODEL_PATH=${MODEL_PATH}"
echo "Starting Parakeet FastAPI server on ${HOST}:${PORT}"

if command -v lsof >/dev/null 2>&1; then
  if lsof -ti tcp:"${PORT}" >/dev/null 2>&1; then
    echo "A process is already listening on port ${PORT}. Skipping new server launch." >&2
    exit 0
  fi
fi

exec uvicorn parakeet_fastapi.server:app \
  --host "${HOST}" \
  --port "${PORT}" \
  --log-level info
