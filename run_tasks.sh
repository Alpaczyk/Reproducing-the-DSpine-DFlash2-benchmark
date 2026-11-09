#!/usr/bin/env bash
# Task benchmark: 10 chat prompts x {T=0,T=1} x {dspine,dflash2,ar}
# Env: PORT=8080  LLAMA_DIR=~/llama.cpp  MODELS=~/models  RESULTS=~/dspine-results
# Requires task_bench.py next to this script.
set -euo pipefail

PORT="${PORT:-8080}"
LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
MODELS="${MODELS:-$HOME/models}"
RESULTS="${RESULTS:-$HOME/dspine-results}"
mkdir -p "$RESULTS"
cd "$(dirname "$0")"

start_server () {
  local ARM="$1" TEMP="$2"; local ARGS=()
  case "$ARM" in
    dflash2) ARGS=(-md "$MODELS/Qwen3.8-27B-DFlash2-Q4_K_M.gguf" --spec-type draft-dflash
                   --spec-draft-n-max 7 --spec-draft-ngl 999
                   --spec-draft-type-k q8_0 --spec-draft-type-v q8_0) ;;
    dspine)  ARGS=(-md "$MODELS/Qwen3.8-27B-DSpine-b16-Q4_K_M.gguf" --spec-type draft-dflash
                   --spec-draft-n-max 15 --spec-draft-ngl 999
                   --spec-draft-type-k q8_0 --spec-draft-type-v q8_0) ;;
    ar)      ARGS=() ;;
  esac
  if [ "$ARM" != "ar" ] && [ "$TEMP" = "1" ]; then
    ARGS+=(--spec-draft-sampling probabilistic)
  fi
  "$LLAMA_DIR/build/bin/llama-server" \
    -m "$MODELS/Qwen3.8-27B-Q4_K_M.gguf" "${ARGS[@]}" \
    -ngl 999 -fa on --jinja -c 8192 -np 1 \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --alias qwen3.8-27b --port "$PORT" \
    > "$RESULTS/tasksrv-${ARM}-t${TEMP}.log" 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 60); do
    curl -sf "http://127.0.0.1:$PORT/health" > /dev/null && return 0
    kill -0 "$SERVER_PID" 2>/dev/null || { tail -n 30 "$RESULTS/tasksrv-${ARM}-t${TEMP}.log"; return 1; }
    sleep 5
  done
  return 1
}

for ARM in dspine dflash2 ar; do
  for TEMP in 0 1; do
    echo "=== task bench: arm=$ARM temp=$TEMP ==="
    start_server "$ARM" "$TEMP"
    python3 task_bench.py --base-url "http://127.0.0.1:$PORT" --temp "$TEMP" \
      --out "$RESULTS/tasks-${ARM}-t${TEMP}.csv"
    kill $SERVER_PID 2>/dev/null || true
    sleep 3
  done
done

echo; echo "=== acceptance summary ==="
for f in "$RESULTS"/tasksrv-*.log; do
  echo "--- $f"; grep -i accept "$f" | tail -n 11 || true
done
