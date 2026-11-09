#!/usr/bin/env bash
# Download the three model files used by the benchmark.
set -euo pipefail

pip install --user -U "huggingface_hub[cli]" >/dev/null 2>&1 || true

mkdir -p "${MODELS:-$HOME/models}"
cd "${MODELS:-$HOME/models}"

hf download bartowski/Qwen3.8-27B-GGUF              Qwen3.8-27B-Q4_K_M.gguf              --local-dir .
hf download aj9o9/Qwen3.8-27B-DSpine-b16-GGUF       Qwen3.8-27B-DSpine-b16-Q4_K_M.gguf   --local-dir .
hf download z-lab/Qwen3.8-27B-DFlash2-GGUF          Qwen3.8-27B-DFlash2-Q4_K_M.gguf      --local-dir .

sha256sum *.gguf | tee sha256.txt
