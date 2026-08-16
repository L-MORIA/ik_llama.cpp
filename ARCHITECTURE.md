# Архитектура: как функционирует ik_llama.cpp и гибридные модели

> Часть документации форка [L-MORIA/ik_llama.cpp](https://github.com/L-MORIA/ik_llama.cpp).
> Оригинал: [ikawrakow/ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp) (MIT).

---

## 1. Что такое ik_llama.cpp

ik_llama.cpp — форк llama.cpp (ветка от июня 2024, синхронизация с upstream в
августе 2024). Отличается от mainline llama.cpp:

- **Кастомные кванты** — IQ4_KT, IQ4_KS и другие (типы GGUF ≥ 144), которых нет в stock
- **Fused Gated Delta Net (GDN)** — аппаратные ядра для рекуррентных слоёв гибридных моделей
- **MLA, quant repacking, tensor parallel, MTP, DFlash** — фичи, появившиеся здесь раньше, чем в llama.cpp

Поддерживаемые бэкенды: **CPU** (AVX2/ARM_NEON) и **CUDA** (Turing и новее).
ROCm/Vulkan/Metal/старые GPU — не поддерживаются (см. upstream README).

## 2. Гибридная архитектура модели (на примере Qwen3.8-27B)

Qwen3.8 — **гибрид**: в стеке чередуются два типа слоёв.

```
┌─────────────────────────────────────────────┐
│              Qwen3.8-27B (27B params)        │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │  Standard Transformer layer            │  │
│  │  (self-attention + FFN)                │  │
│  │  → CUDA matmul (sm_120)                │  │
│  └────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────┐  │
│  │  Gated Delta Net (GDN) layer           │  │
│  │  (recurrent, linear attention)         │  │
│  │  → FUSED CUDA kernel (-khad -vhad)     │  │
│  └────────────────────────────────────────┘  │
│  ... чередование на всех N слоях ...         │
└─────────────────────────────────────────────┘
```

### 2.1 Standard Transformer layer

Классический self-attention + FFN. В ik_llama.cpp компилируется в CUDA-ядра
для sm_120 (Blackwell). Работает одинаково в stock и ik_llama.cpp.

### 2.2 Gated Delta Net (GDN) layer

Рекуррентный слой с линейным attention (как в Qwen3-Next). Ключевое отличие от
обычного attention:

- **Линейная сложность по длине контекста** (O(N) vs O(N²) у softmax attention)
- **Рекуррентное состояние** — вместо хранения всех K/V в KV-cache хранится
  компактное «состояние» (state), которое обновляется на каждом токене
- **Компактный KV** — это и даёт возможность 64K контекста в 16GB VRAM

### 2.3 Почему stock llama.cpp тормозит на гибридах

В stock llama.cpp **нет CUDA-ядер для GDN**. При загрузке:

```
resolve_fused_ops: layer 0 is assigned to device CPU but fused Gated Delta Net (chunked)
is assigned to device CUDA0 (usually due to missing support)
resolve_fused_ops: fused Gated Delta Net (chunked) not supported, set to disabled
```

→ GDN-слои сбрасываются на CPU. Каждый токен:
1. Состояние GDN живёт в CPU RAM
2. На каждом токене состояние тащится GPU→CPU→GPU через PCIe
3. PCIe bandwidth (~32 ГБ/с) — bottleneck, а не вычисления

Результат: 3-4 т/с независимо от кванта (уменьшение кванта не помогает —
bottleneck в PCIe, не в VRAM).

### 2.4 Что делает ik_llama.cpp

Fused GDN-ядра на GPU: состояние GDN живёт в VRAM, обновления happen on GPU.
Флаги `-khad -vhad --merge-qkv` включают эти ядра. Результат: 25+ т/с.

## 3. KV-cache и VRAM-бюджет

Для 27B-модели на 16GB VRAM:

| Компонент | Размер | Где |
|---|---|---|
| Веса модели (IQ4_KS) | ~14.7GB | VRAM |
| KV-cache K (q4_0) | ~0.5GB | VRAM |
| KV-cache V (q4_0) | ~0.5GB | VRAM |
| **Итого** | **~15.9GB** | **VRAM (16GB)** |

`--cache-type-k q4_0 --cache-type-v q4_0` — квантование KV-cache в q4_0.
Без этого (f16) KV@64K не лезет в 16GB.

## 4. Data flow при генерации одного токена

```
Input token
    │
    ▼
┌──────────────────────────────────┐
│  Embedding lookup (GPU)          │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  For each layer:                 │
│  ┌────────────────────────────┐  │
│  │  Transformer layer:        │  │
│  │  - QKV projection (CUDA)   │  │
│  │  - Attention (flash-attn)  │  │
│  │  - FFN (CUDA)              │  │
│  └────────────────────────────┘  │
│  ┌────────────────────────────┐  │
│  │  GDN layer:                │  │
│  │  - State update (FUSED)    │  │
│  │  - Linear attention        │  │
│  └────────────────────────────┘  │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  LM head → logits (GPU)          │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Sampling (temp, top-k, top-p,   │
│  min-p, repeat-penalty)          │
└──────────────┬───────────────────┘
               │
               ▼
          Output token
```

## 5. Speculative decoding (ngram-mod)

`--spec-type ngram-mod:n_max=2` — speculative decoding на n-граммах:

1. Модель генерирует N токенов «наугад» (draft)
2. Основной прогон проверяет draft
3. Если draft верен — N токенов за один шаг

Для n_max=2: до 3 токенов за шаг (1 + 2 draft). Ускоряет генерацию на 1.5-2×.

## 6. Flash attention

`--flash-attn on` — flash attention v2:

- O(N) VRAM вместо O(N²) для attention
- Быстрее на длинных контекстах
- Обязательно для 64K контекста в 16GB VRAM

## 7. Файловая структура репо (ключевое)

```
ik_llama.cpp/
├── CMakeLists.txt          # Корневой CMake
├── CMakePresets.json       # Пресеты CMake
├── ggml/                   # ggml (tensor library)
│   └── src/
│       └── ggml.c          # Ядро tensor ops
├── src/                    # llama.cpp source
├── common/                 # Общие утилиты
├── examples/
│   └── server/             # llama-server (HTTP API)
├── build/                  # Build dir (НЕ коммитится)
│   └── bin/
│       └── llama-server.exe
├── build_ik_llama.bat      # Наш рецепт сборки (Windows)
├── run_ik_qwen38.bat       # Наш рецепт запуска
├── BUILDING_RTX5060Ti.md   # Это руководство
├── ARCHITECTURE.md         # Этот файл
├── AGENTS.md               # Инструкции для AI-агентов
└── LICENSE                 # MIT
```

## 8. Как компилируется GDN (CUDA)

При сборке с `-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=120`:

1. nvcc компилирует `.cu`-файлы из `ggml/src/ggml-cuda/`
2. Флаги `-khad -vhad` (runtime) включают fused GDN-ядра
3. Ядра используют sm_120-специфичные инструкции (Blackwell)

Без `-khad -vhad` — GDN-слои выполняются через generic path (CPU или
медленные GPU-ядра) → 4-7 т/с.

## 9. Почему 16GB VRAM — минимум для 27B + 64K

- Веса IQ4_KS: ~14.7GB
- KV@64K (q4_0): ~1GB
- Активации + workspace: ~0.5GB
- **Итого: ~16.2GB** — впритык в 16GB

На 12GB GPU (RTX 4070/4080) 27B + 64K не влезет. Варианты:
- Снизить контекст до 32K
- Использовать более агрессивный квант (IQ3_K)
- Использовать MoE-модель (меньше активных параметров)

## 10. Сравнение с альтернативами

| Движок | GDN на GPU | KV q4_0 | 27B + 64K в 16GB | Скорость |
|---|---|---|---|---|
| LM Studio (stock) | ❌ | ❌ | ❌ | 3-4 т/с |
| **ik_llama.cpp** | ✅ | ✅ | ✅ | **25+ т/с** |
| vLLM | ❌ (нет GDN) | ✅ | ❌ | N/A |
| TensorRT-LLM | ❌ | ✅ | ❌ | N/A |

ik_llama.cpp — единственный движок, который поддерживает GDN на GPU +
кастомные кванты + компактный KV.
