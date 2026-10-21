"""Coding benchmark for llama-server models: HumanEval subset with executable checks.

Usage:
    python bench_coding_8090.py --port 8090 --model Kwaipilot_KAT_Coder --limit 20

Each task is generated, the code is extracted and executed together with the
official HumanEval unit test in a separate process (timeout). A task passes
only if the test script exits with code 0.

Output: one JSON line per task -> bench_coding_<model>.jsonl
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "benchdata", "humaneval.jsonl")

INSTR = (
    "\n\nComplete the function above. "
    "Reply with a single Python code block containing the full implementation. "
    "No explanation, no tests, no example usage."
)

CODE_BLOCK = re.compile(r"```(?:python|py)?\s*(.*?)```", re.S | re.I)


def load_tasks(limit: int, seed: int) -> list:
    with open(DATA, encoding="utf-8") as f:
        rows = [json.loads(line) for line in f if line.strip()]
    rng = random.Random(seed)
    picked = rng.sample(range(len(rows)), min(limit, len(rows)))
    return [rows[i] for i in sorted(picked)]


def extract_code(text: str) -> str:
    """Take the last fenced block if several, else the raw text."""
    if not text:
        return ""
    blocks = CODE_BLOCK.findall(text)
    if blocks:
        return blocks[-1].strip()
    return text.strip()


def run_test(prompt: str, code: str, test: str, entry_point: str, timeout: int = 20) -> tuple:
    program = prompt + "\n" + code + "\n\n" + test + "\n\ncheck(" + entry_point + ")\n"
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "candidate.py")
        with open(path, "w", encoding="utf-8") as f:
            f.write(program)
        env = dict(os.environ)
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        try:
            p = subprocess.run([sys.executable, "-I", path], capture_output=True,
                               timeout=timeout, cwd=td, env=env)
        except subprocess.TimeoutExpired:
            return False, "timeout"
        if p.returncode == 0:
            return True, ""
        err = (p.stderr or b"").decode("utf-8", "replace").strip().splitlines()
        return False, err[-1][:200] if err else f"exit {p.returncode}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8090)
    ap.add_argument("--model", default="")
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--seed", type=int, default=1234)
    ap.add_argument("--max-tokens", type=int, default=1024)
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--think", action="store_true", help="keep the model's thinking mode on")
    ap.add_argument("--out", default="")
    ap.add_argument("--timeout", type=int, default=1200)
    args = ap.parse_args()

    base = f"http://127.0.0.1:{args.port}"
    ids = [m.get("id") for m in (requests.get(f"{base}/v1/models", timeout=15).json().get("data") or [])]
    if not ids:
        print("[ERROR] no models on port", args.port)
        return 2
    model = args.model if args.model in ids else ids[0]
    out = args.out or os.path.join(HERE, f"bench_coding_{model}.jsonl")
    print(f"port={args.port} model={model} ids={ids} tasks={args.limit} think={args.think}", flush=True)

    tasks = load_tasks(args.limit, args.seed)
    passed = 0
    for n, task in enumerate(tasks, 1):
        body = {
            "model": model,
            "messages": [{"role": "user", "content": task["prompt"] + INSTR}],
            "max_tokens": args.max_tokens,
            "temperature": args.temperature,
        }
        if not args.think:
            body["chat_template_kwargs"] = {"enable_thinking": False}

        rec = {"model": model, "port": args.port, "task_id": task["task_id"]}
        t0 = time.time()
        try:
            r = requests.post(f"{base}/v1/chat/completions", json=body, timeout=args.timeout)
            wall = time.time() - t0
            d = r.json()
        except Exception as e:
            rec.update({"passed": False, "error": f"request: {type(e).__name__}", "wall_s": round(time.time() - t0, 1)})
            print(json.dumps(rec, ensure_ascii=False), flush=True)
            with open(out, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            continue

        msg = (d.get("choices") or [{}])[0].get("message") or {}
        content = msg.get("content") or ""
        reasoning = msg.get("reasoning_content") or ""
        usage = d.get("usage") or {}
        timings = d.get("timings") or {}

        code = extract_code(content) or extract_code(reasoning)
        ok, err = run_test(task["prompt"], code, task["test"], task["entry_point"])
        passed += 1 if ok else 0
        rec.update({
            "passed": ok,
            "error": err,
            "wall_s": round(wall, 2),
            "gen_tokens": usage.get("completion_tokens"),
            "gen_tps": round(timings.get("predicted_per_second") or 0, 2),
            "prompt_tokens": usage.get("prompt_tokens"),
            "has_content": bool(content.strip()),
            "reasoning_chars": len(reasoning),
            "code_chars": len(code),
        })
        print(json.dumps(rec, ensure_ascii=False), flush=True)
        with open(out, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    print(f"\n=== {model}: pass@{args.limit} = {passed}/{len(tasks)} "
          f"({passed / max(1, len(tasks)) * 100:.1f}%) ===", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
