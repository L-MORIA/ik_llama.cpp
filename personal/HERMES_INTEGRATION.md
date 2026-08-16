# Hermes integration — ik_llama.cpp as the local model provider

This is the **personal** part of the setup: how Hermes Agent talks to the
ik_llama.cpp server built in this repo. It is intentionally kept out of the
public fork because it is environment-specific (localhost port, local model id).

## What runs

- **Server:** `llama-server.exe` (built by `build_ik_llama.bat`), started by
  `run_ik_qwen38.bat`, listening on `http://localhost:8080/v1`
  (OpenAI-compatible API).
- **Model served:** `Qwen3_8-27B` (hybrid Gated Delta Net + attention), loaded
  into the RTX 5060 Ti 16 GB VRAM with KV-cache on GPU.
- **Measured throughput:** ~25.45 tok/s (vs 3.31 tok/s in stock llama.cpp → ×7.7).

## Hermes provider config (`config.yaml`)

The relevant block in the Hermes profile `old-laptop`:

```yaml
model:
  base_url: ''
  default: Qwen3_8-27B
  provider: ikllama
  context_length: 1000000

providers:
  ikllama:
    api_key_env: ''
    base_url: http://localhost:8080/v1
    discover_models: false
```

**Rules that were learned the hard way (do not deviate):**

1. When switching `model.provider` to `ikllama`, the previous `model.base_url`
   MUST be cleared first (`hermes config set model.base_url ''`), otherwise the
   stale base_url silently breaks the new provider.
2. The `ikllama` provider points at the local server on `:8080`. No API key is
   needed (LAN/localhost only).
3. `discover_models: false` — the model id `Qwen3_8-27B` is fixed in the server
   launch, so auto-discovery is off.

## Cold start (after a PC reboot)

1. Start the server: double-click **`Qwen3.8 ik-server.lnk`** on the desktop
   (see `DESKTOP_SHORTCUT.md`). The window minimizes; the model loads in
   ~40–60 s.
2. Confirm `:8080` is up:
   ```bash
   curl -s http://127.0.0.1:8080/v1/models
   ```
3. Open Hermes and chat normally — it answers through `Qwen3_8-27B` at ~25 tok/s.

## Stopping

Close the minimized server window (taskbar) or kill `llama-server.exe`.
LM Studio is **not** required at all.

## Known incident (context overflow) — see `PERSONAL_NOTES.md`

`--reasoning-budget 32000` in `run_ik_qwen38.bat` shares the single `n_ctx`
pool with the input, leaving only ~30 K for history. Long chats overflow at
~47 K tokens. Fix (not yet applied): lower the budget to `8192` or reduce
`compression.protect_last_n`.
