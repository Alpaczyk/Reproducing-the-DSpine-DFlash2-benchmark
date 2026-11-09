# Reproducing the DSpine / DFlash2 benchmark (DGX Spark or any CUDA GPU)

This pack reproduces the benchmark from
[discussion #2](https://huggingface.co/aj9o9/Qwen3.8-27B-DSpine-b16-GGUF/discussions/2):
DSpine vs DFlash2 vs plain autoregressive decoding for Qwen3.8-27B,
on the `dspine` branch of [Ajay9o9/llama.cpp](https://github.com/Ajay9o9/llama.cpp/tree/dspine),
using [llama-benchy](https://github.com/eugr/llama-benchy).

Absolute tok/s will differ on your hardware. **Acceptance (tokens per verify step) should match
almost exactly** — it is a property of the models, not the GPU. Use it to validate your setup.

## Requirements

- Linux (or WSL) with an NVIDIA GPU and a working CUDA toolkit (`nvcc --version`)
- ~30 GB free disk, git, cmake, Python 3.11+
- Internet access (models + llama-benchy's corpus download)

## 1. Build llama.cpp (dspine branch)

```bash
git clone -b dspine https://github.com/Ajay9o9/llama.cpp.git
cd llama.cpp
# Let CMake detect your GPU architecture. On a DGX Spark (GB10) add
#   -DCMAKE_CUDA_ARCHITECTURES=121
cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/bin/llama-server --help >/dev/null && echo "build OK"
```

## 2. Download models (~20 GB)

```bash
./fetch_models.sh          # or copy the commands from that file
```

## 3. Install llama-benchy

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uvx llama-benchy --help    # first run installs it
```

## 4. Smoke test first (the acceptance gate)

Start the DSpine server in one terminal:

```bash
~/llama.cpp/build/bin/llama-server \
  -m ~/models/Qwen3.8-27B-Q4_K_M.gguf \
  -md ~/models/Qwen3.8-27B-DSpine-b16-Q4_K_M.gguf \
  --spec-type draft-dflash --spec-draft-n-max 15 \
  -ngl 999 --spec-draft-ngl 999 \
  -fa on --jinja -c 8192 -np 1 \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --spec-draft-type-k q8_0 --spec-draft-type-v q8_0 \
  --alias qwen3.8-27b --port 8080 > ~/smoke.log 2>&1 &
```

In another terminal, send one code prompt:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" -d '{
    "model": "qwen3.8-27b",
    "messages": [{"role": "user", "content": "Write a Python function that returns the n-th Fibonacci number using memoization."}],
    "max_tokens": 256, "temperature": 0,
    "chat_template_kwargs": {"enable_thinking": false}
  }' > /dev/null

grep -i accept ~/smoke.log | tail -1
```

Expected on code: **mean len ~7–14**. Prose prompts give ~2–3. If your mean len is
stuck near 1, the draft isn't being used (check the flags, and that the log shows
`adding speculative implementation 'draft-dflash'` with `n_max=15`).

Kill that server before benchmarking (port conflict): `pkill -f llama-server`

## 5. Depth benchmark

`run_depth.sh` starts the right server per arm, waits for it, and runs llama-benchy
at depths 0 / 8k / 16k / 32k / 63k on the **prose corpus** (llama-benchy's default
Sherlock Holmes text). Results land in `~/dspine-results/`.

```bash
chmod +x run_depth.sh
./run_depth.sh dspine      # ~10-15 min
./run_depth.sh dflash2
./run_depth.sh ar
```

Options (env vars): `RUNS=3 ./run_depth.sh dspine r3` (3 runs per cell, recommended),
`MODELS=...`, `RESULTS=...`, `CTX=...`, `PORT=...`.

For the **code corpus**, build a text file from llama.cpp sources, serve it, and pass its URL:

```bash
mkdir -p ~/corpora
cat ~/llama.cpp/src/*.cpp ~/llama.cpp/src/*.h ~/llama.cpp/common/*.cpp ~/llama.cpp/common/*.h > ~/corpora/code.txt
(cd ~/corpora && python3 -m http.server 8000 &)
./run_depth.sh dspine code http://127.0.0.1:8000/code.txt
```

Raw benchy equivalent:

```bash
uvx llama-benchy --base-url http://127.0.0.1:8080/v1 \
  --model qwen3.8-27b --tokenizer Qwen/Qwen3.8-27B \
  --pp 0 --tg 256 --runs 3 --depth 0 8192 16384 32768 63488
```

## 6. Task benchmark (code / math / prose, T=0 and T=1)

Ten fixed prompts, up to 1024 new tokens, thinking disabled, at temperature 0 and 1
(T=1 uses top_p 0.95 / top_k 20 and probabilistic draft sampling), for all three arms:

```bash
chmod +x run_tasks.sh
./run_tasks.sh
```

Results: `~/dspine-results/tasks-<arm>-t<temp>.csv` and per-run acceptance in
`tasksrv-<arm>-t<temp>.log`.

## 7. Compare your results

See `expected-results.md` for the reference tables. The important checks, in order:

1. **Acceptance** (mean len in the server logs): should match within ~±0.3. If it doesn't,
   your build or flags differ — stop and check the smoke test.
2. **Step time**: `tok/s ÷ mean len` (per generation). It should be constant across
   prompts for one drafter; that constant is what your hardware sets.
3. **The winner per prompt** then follows from acceptance vs step-time ratio — that's the
   whole finding, and it may well flip on your GPU (see the card's tuning section).

Use `--runs 3` for anything you plan to publish: single 256-token generations on the
prose corpus vary by up to ±20% because each run draws different text and acceptance.

## Troubleshooting

- **`error: invalid argument: --served-model-name`** — this fork uses `--alias`.
- **`dflash requires ctx_other to be set`** during memory fitting — printed by the fork,
  normal; the server continues.
- **Mean len ≈ 1** — drafter not active; check `--spec-type draft-dflash`,
  `--spec-draft-n-max`, `-md`, and the server log's spec-init lines.
- **Non-NVIDIA or non-CUDA backends** — adjust the build (`-DGGML_VULKAN=ON`,
  `-DGGML_METAL=ON`, `-DGGML_HIP=ON`) and sweep `--spec-draft-n-max` (15 on CUDA/ROCm;
  2–4 on Vulkan per the model card's tuning section). Power logging requires `nvidia-smi`
  and is skipped harmlessly if absent.
- **`-fa on` fails** — on some backends use `-fa off` (slower) and note it.
