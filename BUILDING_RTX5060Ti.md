# Сборка ik_llama.cpp под RTX 5060 Ti (sm_120, Blackwell) — Windows

> **Благодарность:** этот репозиторий — форк проекта
> [ikawrakow/ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp)
> (кастомные кванты IQ4_KT/IQ4_KS, fused Gated Delta Net на GPU).
> Оригинальный проект и его авторы — [ikawrakow](https://github.com/ikawrakow)
> и сообщество ggml/llama.cpp. Лицензия **MIT** — см. файл `LICENSE`.
> Все заслуги оригинальных авторов сохранены и не оспариваются.

## Зачем это нужно

Qwen3.8-27B — гибридная архитектура (transformer + рекуррентные слои Gated Delta Net).
Stock llama.cpp (в т.ч. в LM Studio) **не имеет CUDA-ядер** для этих слоёв →
рекуррентные слои падают на CPU → 3-4 т/с.

В ik_llama.cpp есть fused Gated Delta Net на GPU → **25+ т/с** на RTX 5060 Ti 16GB.

## Измеренный результат (2026-08-15, RTX 5060 Ti 16GB, контекст 65536)

| Движок | Скорость генерации |
|---|---|
| LM Studio (stock llama.cpp) | 3.31 т/с |
| **ik_llama.cpp (этот форк)** | **25.45 т/с (×7.7)** |

## Требования

- Windows 10/11
- VS2022 BuildTools (cl.exe **14.44** — НЕ 2019! см. грабли ниже)
- CMake 4.x
- CUDA toolkit 13.1 (nvcc)
- GPU: NVIDIA с compute capability ≥ 7.5 (проверено на sm_120 / Blackwell)

## Сборка

Файл `build_ik_llama.bat` (в корне репо):

```bat
call "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Auxiliary/Build/vcvars64.bat"
set CL14=C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe
cmake -B build -G Ninja -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=120 ^
  -DLLAMA_CUDA_ARCHITECTURES=120 -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_C_COMPILER="%CL14%" -DCMAKE_CXX_COMPILER="%CL14%"
cmake --build build -j 16
```

Результат: `build/bin/llama-server.exe` (~8 МБ, сборка ~20-40 мин).

## Запуск

Файл `run_ik_qwen38.bat` (в корне репо) — пример запуска Qwen3.8-27B
(cHunter789 IQ4_KS_KT-квант) на порту 8080 с контекстом 65536.

Ключевые флаги:
- `-khad -vhad --merge-qkv` — **включают fused Gated Delta Net на GPU** (без них 4-7 т/с)
- `--cache-type-k q4_0 --cache-type-v q4_0` — компактный KV для 16GB VRAM
- `--ctx-size 65536` — контекст 64K

## Грабли (проверено)

1. **VS2019 рядом с VS2022** — cmake берёт cl.exe 14.50, с которым nvcc 13.1 несовместим
   (`No CUDA toolset found`). Фикс: Ninja-генератор + явный путь к cl.exe 14.44.
2. **Перед повторным configure** — `rmdir /s /q build` (иначе cmake переиспользует кэш
   с неправильным компилятором).
3. **Файлы IQ4_KS_KT (тип кванта 144)** не грузятся в stock llama.cpp / LM Studio —
   только в ik_llama.cpp.
4. **16GB VRAM** не держит 27B + KV@64K в LM Studio — только в ik_llama.cpp
   (компактный KV q4_0 + fused ops).

## Лицензия

MIT — см. `LICENSE`. Разрешены: копирование, модификация, публикация,
коммерческое использование. Обязательное условие — сохранение copyright-notice.
