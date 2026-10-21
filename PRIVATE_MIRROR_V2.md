# Private mirror v2 (continuation of ik_llama.cpp-rtx5060ti-full)

This repository is the **continuation** of the earlier private mirror
`ik_llama.cpp-rtx5060ti-full` by the same owner (L-MORIA).

## Why a new repository

On 2026-10-21 the old mirror was found to be **broken on the GitHub side**: every
push was rejected by the server with

```
remote: fatal: did not receive expected object 1794846f ("Fix Gemma4 MTP (#2324)")
error: remote unpack failed: index-pack failed
```

That object is not an ancestor of any ref in the mirror and cannot be fetched
from it (`upload-pack: not our ref`), while it does exist in the upstream
repository. The mirror's own object store on GitHub therefore references a
missing object, and `index-pack` fails for every incoming pack. No client side
workaround exists (`--no-thin`, `--negotiation-tip`, `--unshallow` and fetching
the object by SHA were all tried).

The old repository is **left untouched** on purpose - it is not deleted, not
force-pushed and not modified in any way.

## What this repository contains

- `main` = the current state of the local working copy
  (`ik_llama.cpp` on the owner machine, branch `perf/upstream-1019`),
  including the personal notes under `personal/`.
- Public counterpart with the same content: `L-MORIA/ik_llama.cpp`
  (branch `main`).
- The local history is a **shallow clone** (boundary commit `8337e4cd`),
  so the root of the imported history is truncated on purpose.

## One file that lives only in the old mirror

`testcu.cu` (a two line CUDA diagnostic stub) exists only in
`ik_llama.cpp-rtx5060ti-full` and is deliberately **not** copied here:
per the repository AGENTS.md it is a local debug artifact that must not be
committed. It remains available in the old mirror.
