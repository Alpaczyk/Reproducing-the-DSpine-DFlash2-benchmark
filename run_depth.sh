#!/usr/bin/env bash
# Depth benchmark for one arm: starts llama-server, runs llama-benchy, saves results.
#
# Usage:  ./run_depth.sh <ar|dflash2|dspine> [tag] [book-url]
# Env:    RUNS=1  PORT=8080  CTX=131072  LLAMA_DIR=~/llama.cpp  MODELS=~/models  RESULTS=~/dspine-results
#
# Outputs (in $RESULTS):
#   depth-<arm>-<tag>.md     llama-benchy table
#   server-<arm>-<tag>.log   server log, incl. "draft acceptance ... mean len" lines
#   power-<arm>-<tag>.csv    nvidia-smi power/temp samples (skipped if nvidia-smi absent)

set -euo pipefail

ARM="${1:?usage: run_depth.sh <ar|dflash2|dspine> [tag] [book-url]}"
TAG="${2:-default}"
BOOK_URL="${3:-}"

PORT="${PORT:-8080}"
CTX="${CTX:-131072}"
RUNS="${RUNS:-1}"
LLAMA_DIR="${LLAMA_DIR:-$HOME/llama.cpp}"
MODELS="${MODELS:-$HOME/models}"
RESULTS="${RESULTS:-$HOME/dspine-results}"
mkdir -p "$RESULTS"
SERVER_LOG="$RESULTS/server-${ARM}-${TAG}.log"

case "$ARM" in
  ar) DRAFT_ARGS=() ;;
  dflash2)
    DRAFT_ARGS=(-md "$MODELS/Qwen3.8-27B-DFlash2-Q4_K_M.gguf"
                --spec-type draft-dflash --spec-draft-n-max 7
                --spec-draft-ngl 999
                --spec-draft-type-k q8_0 --spec-draft-type-v q8_0) ;;
  dspine)
    DRAFT_ARGS=(-md "$MODELS/Qwen3.8-27B-DSpine-b16-Q4_K_M.gguf"
                --spec-type draft-dflash --spec-draft-n-max 15
                --spec-draft-ngl 999
                --spec-draft-type-k q8_0 --spec-draft-type-v q8_0) ;;
  *) echo "unknown arm: $ARM (ar | dflash2 | dspine)" >&2; exit 1 ;;
esac

echo "=== arm=$ARM tag=$TAG ctx=$CTX runs=$RUNS ==="

"$LLAMA_DIR/build/bin/llama-server" \
  -m "$MODELS/Qwen3.8-27B-Q4_K_M.gguf" "${DRAFT_ARGS[@]}" \
  -ngl 999 -fa on --jinja \
  -c "$CTX" -np 1 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --alias qwen3.8-27b \
  --port "$PORT" > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

echo "waiting for server (log: $SERVER_LOG) ..."
for _ in $(seq 1 120); do
  if curl -sf "http://127.0.0.1:$PORT/health" > /dev/null; then break; fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "server died, last 50 log lines:" && tail -n 50 "$SERVER_LOG"; exit 1
  fi
  sleep 5
done
curl -sf "http://127.0.0.1:$PORT/health" > /dev/null || { echo "server never became healthy"; exit 1; }
echo "server is up"

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=timestamp,power.draw,temperature.gpu,clocks.current.sm,memory.used \
    --format=csv -l 5 > "$RESULTS/power-${ARM}-${TAG}.csv" 2>/dev/null &
  POWER_PID=$!
fi

BENCH_ARGS=(
  --base-url "http://127.0.0.1:$PORT/v1"
  --model qwen3.8-27b
  --tokenizer Qwen/Qwen3.8-27B
  --pp 0 --tg 256 --runs "$RUNS"
  --depth 0 8192 16384 32768 63488
  --save-result "$RESULTS/depth-${ARM}-${TAG}.md"
  --format md
)
if [ -n "$BOOK_URL" ]; then
  BENCH_ARGS+=(--book-url "$BOOK_URL")
fi

uvx llama-benchy "${BENCH_ARGS[@]}"

[ -n "${POWER_PID:-}" ] && kill "$POWER_PID" 2>/dev/null || true
echo
echo "done: $RESULTS/depth-${ARM}-${TAG}.md"
echo "acceptance lines:"
grep -i accept "$SERVER_LOG" | tail -n 20 || true
