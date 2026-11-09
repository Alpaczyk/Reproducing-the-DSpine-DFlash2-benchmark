#!/usr/bin/env python3
"""
Task benchmark: 10 fixed chat prompts, up to 1024 new tokens, thinking disabled.
T=0 and T=1 (T=1 uses top_p 0.95 / top_k 20 per Qwen's recommendation).

Usage:
  python3 task_bench.py --base-url http://127.0.0.1:8080 --temp 0 --out tasks-dspine-t0.csv

The server must be started with --alias qwen3.8-27b (scripts in this pack do that).
tok/s is computed benchy-style: content tokens divided by the interval between the
first and last streamed content token.
"""

import argparse
import csv
import json
import sys
import time
import urllib.request

PROMPTS = [
    ("math", "A rectangle's length is 3 more than twice its width. Its perimeter is 36. What is its area?"),
    ("math", "Solve for x: 2^(x+1) = 8^(x-1). Show your steps."),
    ("writing", "Write a 200-word story about a lighthouse keeper who finds a message in a bottle."),
    ("writing", "Write a short professional email politely declining a meeting invitation."),
    ("summarize", "Summarize the plot of Romeo and Juliet in five sentences."),
    ("summarize", "Translate into French: 'The quick brown fox jumps over the lazy dog.'"),
    ("code", "Write a Python function that returns the n-th Fibonacci number using memoization."),
    ("code", "Write a C++ function that reverses a singly linked list in place."),
    ("code", "Write a JavaScript debounce function with TypeScript types."),
    ("code", "Write a SQL query that finds the top 5 customers by total order value in 2024."),
]


def bench_one(base_url: str, prompt: str, temp: float, max_tokens: int):
    body = {
        "model": "qwen3.8-27b",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": temp,
        "stream": True,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    if temp > 0:
        body["top_p"] = 0.95
        body["top_k"] = 20

    req = urllib.request.Request(
        base_url.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )

    n_chunks = 0
    first_ts = None
    last_ts = None
    with urllib.request.urlopen(req, timeout=1200) as resp:
        for raw in resp:
            if not raw.startswith(b"data: "):
                continue
            payload = raw[6:].strip()
            if payload == b"[DONE]":
                break
            chunk = json.loads(payload)
            choices = chunk.get("choices") or []
            if not choices:
                continue
            delta = choices[0].get("delta") or {}
            if delta.get("content"):
                now = time.time()
                first_ts = first_ts or now
                last_ts = now
                n_chunks += 1

    gen_interval = (last_ts - first_ts) if (first_ts and last_ts and last_ts > first_ts) else None
    tps = n_chunks / gen_interval if gen_interval else 0.0
    return n_chunks, gen_interval, tps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://127.0.0.1:8080")
    ap.add_argument("--temp", type=float, default=0.0, choices=[0.0, 1.0])
    ap.add_argument("--max-tokens", type=int, default=1024)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    rows = []
    for category, prompt in PROMPTS:
        print(f"[{category}] {prompt[:60]} ...", flush=True)
        tokens, interval, tps = bench_one(args.base_url, prompt, args.temp, args.max_tokens)
        print(f"    -> {tokens} tokens in {interval and round(interval, 1)}s = {tps:.1f} tok/s", flush=True)
        rows.append({
            "category": category,
            "prompt": prompt,
            "temperature": args.temp,
            "tokens": tokens,
            "gen_interval_s": round(interval, 2) if interval else None,
            "tok_s": round(tps, 2),
        })

    with open(args.out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    mean_tps = sum(r["tok_s"] for r in rows) / len(rows)
    print(f"\nwrote {args.out}")
    print(f"mean tok/s: {mean_tps:.1f}")
    for cat in ("math", "writing", "summarize", "code"):
        cat_rows = [r for r in rows if r["category"] == cat]
        if cat_rows:
            m = sum(r["tok_s"] for r in cat_rows) / len(cat_rows)
            print(f"  {cat:<10} {m:.1f} tok/s")


if __name__ == "__main__":
    sys.exit(main())
