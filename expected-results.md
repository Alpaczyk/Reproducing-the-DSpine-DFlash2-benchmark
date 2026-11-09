# Reference results (DGX Spark, GB10)

Use these to check your run. **Acceptance is hardware-independent** — it should match.
Absolute tok/s is hardware-dependent — it will not match unless you are on a GB10.

## Acceptance gate (10 task prompts, T=0)

Tokens per verify step (mean len) from the server logs:

| Prompt | DSpine (15) | DFlash2 (7) |
|---|---|---|
| math (rectangle) | 7.98 | 7.14 |
| math (solve x) | 6.24 | 6.51 |
| writing (lighthouse) | 2.08 | 2.54 |
| writing (email) | 2.72 | 3.44 |
| summarize (R&J) | 1.91 | 2.44 |
| summarize (translate) | 1.78 | 2.29 |
| code (Python fib) | 14.06 | 7.47 |
| code (C++ list) | 8.33 | 6.30 |
| code (JS debounce) | 6.28 | 4.89 |
| code (SQL) | 11.60 | 7.67 |

On the upstream RTX 3090 the same prompts gave DSpine ~7.3 (math) / 7.6 (code) / 2.5 (prose)
— matching within prompt differences.

## Depth benchmark, DGX Spark (tok/s)

Prose corpus, 3-run means ± std (single-run cells on this corpus are noisy to ±20%):

| Depth | No speculation | DFlash2 (7) | DSpine (15) |
|---|---|---|---|
| 0 | 12.59 | 25.05 ± 3.70 | 25.39 ± 0.44 |
| 8,192 | 12.08 | 24.22 ± 1.34 | 18.92 ± 2.62 |
| 16,384 | 11.77 | 23.04 ± 3.48 | 20.10 ± 1.44 |
| 32,768 | 11.30 | 20.94 ± 2.53 | 16.69 ± 1.26 |
| 63,488 | 10.43 | 17.75 ± 1.90 | 17.67 ± 2.20 |

AR was identical across independent runs (<1%), no throttling; SM clocks 2366–2541 MHz.

## Task benchmark, DGX Spark (tok/s, T=0)

| Task | No speculation | DFlash2 (7) | DSpine (15) |
|---|---|---|---|
| Code | 12.4 | 61.3 | **76.7** |
| Math | 12.4 | **64.5** | 54.5 |
| Summarize / translate | 12.8 | **22.3** | 14.3 |
| Prose / story | 12.4 | **28.4** | 18.6 |

## How to compare your results

1. Acceptance per prompt (mean len) — expected to match within ~±0.3.
2. Step time = tok/s ÷ mean len. It should be constant across prompts for one drafter;
   its *value* is set by your hardware but its *ratio* between drafters is what decides
   the winner: DSpine wins a prompt when its acceptance ratio over DFlash2 exceeds the
   step-time ratio (~1.23 on GB10, ~0.66 on an RTX 3090).
3. Report the ratio and the winner per task, not just absolute tok/s — that part is
   portable across machines.
