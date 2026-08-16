# ik_llama.cpp-rtx5060ti-full (PRIVATE)

**Full mirror** of the public fork [`L-MORIA/ik_llama.cpp`](https://github.com/L-MORIA/ik_llama.cpp)
(RTX 5060 Ti, sm_120 build of `ikawrakow/ik_llama.cpp`, MIT) **plus** a
**personal environment layer** that is intentionally kept out of the public
repo because it is machine- and user-specific.

> GitHub does not allow *private forks* of public repositories, so this is a
> **separate private repository**, not a fork. Its `main` branch carries the
> entire public-fork tree (upstream code + the public docs) and adds the
> `personal/` directory below.

## What is in here

- **Everything from the public fork** — the full `ik_llama.cpp` source tree,
  `BUILDING_RTX5060Ti.md`, `ARCHITECTURE.md`, `AGENTS.md`, and the `*.bat`
  build/run scripts.
- **`personal/`** — the private layer:
  - `HERMES_INTEGRATION.md` — how Hermes Agent connects to the local server
    via the `ikllama` provider (`http://localhost:8080/v1`).
  - `DESKTOP_SHORTCUT.md` — recipe to recreate the one-click desktop launcher
    (with the `.lnk` binary excluded, paths are absolute).
  - `PERSONAL_NOTES.md` — machine specs, build summary, performance numbers,
    and the documented context-overflow incident + fix.
  - `assets/ik_qwen_icon.ico`, `assets/ik_qwen_icon.png` — the custom icon.

## License

MIT — inherited from `ikawrakow/ik_llama.cpp`. The original copyright notice
and `LICENSE` file are preserved. The personal additions here are likewise
released under MIT.

## Start here

1. Build: `build_ik_llama.bat` (see `BUILDING_RTX5060Ti.md`).
2. Run: `run_ik_qwen38.bat` → server on `:8080`.
3. Use: point Hermes at it (`personal/HERMES_INTEGRATION.md`) or any
   OpenAI-compatible client.
