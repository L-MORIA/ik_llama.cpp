# Personal notes — ik_llama.cpp on RTX 5060 Ti

Environment-specific knowledge that did not go into the public fork. Combines
the build recipe (public: `BUILDING_RTX5060Ti.md`, `ARCHITECTURE.md`,
`AGENTS.md`) with the private operational layer.

## Machine

- **GPU:** NVIDIA RTX 5060 Ti, 16 GB VRAM (sm_120, compute 12.0).
- **Toolchain:** CUDA 13.1 (`nvcc`), Visual Studio 2022 `cl.exe` 19.44,
  Ninja generator. VS2019 (cl 18) **must not** be picked by CMake — it is
  incompatible with nvcc 13.1 ("No CUDA toolset found").
- **Drive layout:** source + build on `F:/` (KINGSPEC), model weights on `G:/`.
  `C:/Users/User` is the Windows profile.

## Build (summary; full recipe in `BUILDING_RTX5060Ti.md`)

```
build_ik_llama.bat  ->  Ninja + explicit cl.exe 14.44 + CUDA arch 120
                         fused Gated Delta Net: -khad -vhad --merge-qkv
run_ik_qwen38.bat   ->  llama-server.exe --ctx-size 65536 :8080, Qwen3_8-27B
```

Binary: `F:/ik_llama.cpp/build/bin/llama-server.exe` (~8 MB).
Build result marker: `BUILD_OK` printed at the end of `build_ik_llama.bat`.

## Performance

| Engine | tok/s | note |
|---|---|---|
| stock llama.cpp (LM Studio) | 3.31 | GDN layers on CPU, no CUDA kernels |
| **ik_llama.cpp (this build)** | **25.45** | ×7.7 — all layers + KV on GPU |

## ✅ Resolved incident — context overflow at ~47 K tokens (fixed 2026-08-16)

**Symptom was (Hermes):** `Context length exceeded (47,126 tokens). Cannot
compress further.`

**Root cause:** `run_ik_qwen38.bat` launched with
`--reasoning-budget 32000` **and** `--ctx-size 65536`. The reasoning budget
shares the *same* `n_ctx` pool as the input, so only ~30 K remained for
history + system prompt. Long chats filled that and the compressor (blocked by
`compression.protect_last_n: 20`) could not shrink further.

**Applied fix (agreed with user):**
- `run_ik_qwen38.bat`: `--reasoning-budget 32000` → **`16000`**
  (frees +16000 tokens for history).
- `hermes config set compression.protect_last_n 15` (from 20) —
  compressor can now pull 5 more tail messages.

**Effect:** crash threshold moved from ~47 K to ~63 K — effectively never
hits under the "ctx ≥64000" rule. Reasoning stays on (16000 is 2× smaller but
still enough for hard tasks). 15 latest messages remain compression-protected.

⚠️ Fix requires a **server restart** (`llama-server.exe`) to take effect —
the running instance still holds the old 32000 until then.

## Credits

- Engine: `ikawrakow/ik_llama.cpp` (MIT).
- Public fork: `L-MORIA/ik_llama.cpp`.
- This private repo is the full mirror of the public fork **plus** this
  `personal/` layer (Hermes integration, desktop shortcut, notes).
