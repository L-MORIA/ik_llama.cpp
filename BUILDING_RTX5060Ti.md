# Полное руководство: сборка и эксплуатация ik_llama.cpp на Windows (RTX 5060 Ti, sm_120)

> **Благодарность:** этот репозиторий — форк проекта
> [ikawrakow/ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp)
> (кастомные кванты IQ4_KT/IQ4_KS, fused Gated Delta Net на GPU).
> Оригинальный проект и его авторы — [ikawrakow](https://github.com/ikawrakow)
> и сообщество ggml/llama.cpp. Лицензия **MIT** — см. файл `LICENSE`.
> Все заслуги оригинальных авторов сохранены и не оспариваются.

---

## Содержание

1. [Зачем это нужно](#1-зачем-это-нужно)
2. [Измеренные результаты](#2-измеренные-результаты)
3. [Требования](#3-требования)
4. [Установка зависимостей](#4-установка-зависимостей)
5. [Клонирование](#5-клонирование)
6. [Сборка](#6-сборка)
7. [Запуск сервера](#7-запуск-сервера)
8. [Разбор всех флагов](#8-разбор-всех-флагов)
9. [Как работает сервер (архитектура](#9-как-работает-сервер)
10. [Интеграция с Hermes Agent](#10-интеграция-s-hermes-agent)
11. [Интеграция с LM Studio (почему НЕ работает)](#11-интеграция-s-lm-studio)
12. [Замер скорости](#12-замер-скорости)
13. [Диагностика и troubleshooting](#13-диагностика-и-troubleshooting)
14. [Грабли (проверено на практике)](#14-грабли)
15. [Лицензия](#15-лицензия)

---

## 1. Зачем это нужно

Qwen3.8-27B — **гибридная архитектура**: обычный transformer + рекуррентные слои
«Gated Delta Net» (GDN, как в Qwen3-Next).

Stock llama.cpp (в т.ч. движок LM Studio) **не имеет CUDA-ядер** для GDN-слоёв.
При загрузке модели в логе видно:

```
resolve_fused_ops: layer 0 is assigned to device CPU but fused Gated Delta Net (chunked)
is assigned to device CUDA0 (usually due to missing support)
resolve_fused_ops: fused Gated Delta Net (chunked) not supported, set to disabled
```

→ рекуррентные слои сбрасываются на CPU, каждый токен тащит тензор GPU↔CPU
через PCIe → bottleneck. Это **не** проблема VRAM, драйвера или offload —
ядер физически нет в сборке.

В ik_llama.cpp есть **fused Gated Delta Net на GPU** → все слои на GPU → 25+ т/с.

Вторичная проблема: кванты `IQ4_KT` (тип GGUF 144) — кастомные, stock llama.cpp
падает: `np.uint32(144) is not a valid GGMLQuantizationType`.

## 2. Измеренные результаты

RTX 5060 Ti 16GB, Qwen3.8-27B, контекст 65536, замер 2026-08-15:

| Движок | Скорость генерации | Комментарий |
|---|---|---|
| LM Studio (stock llama.cpp), 16K ctx | 3.31 т/с | GDN на CPU |
| **ik_llama.cpp (этот форк), 64K ctx** | **25.45 т/с** | GDN fused на GPU |

Ускорение **×7.7**. Prompt processing в обоих случаях быстрый (~148 т/с).

## 3. Требования

- Windows 10/11 x64
- GPU: NVIDIA с compute capability ≥ 7.5 (проверено на RTX 5060 Ti, sm_120 / Blackwell)
- VRAM: ≥ 16GB для 27B-модели с 64K контекстом (веса ~14.7GB + KV q4_0)
- Свободный диск: ~3GB (репо + build)

## 4. Установка зависимостей

### 4.1 CMake 4.x

```bat
winget install Kitware.CMake
```

### 4.2 MSVC — VS2022 BuildTools (ВАЖНО: только 2022, НЕ 2019!)

```bat
winget install Microsoft.VisualStudio.2022.BuildTools --override "--wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
```

Если winget падает на `stdin is not a tty` — качать инсталлятор напрямую:

```bat
curl -L -o vs_BuildTools.exe https://aka.ms/vs/17/release/vs_BuildTools.exe
cmd /c "vs_BuildTools.exe --wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
```

После установки проверить версию cl.exe:

```bat
"C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe"
```

Ожидается `14.44.x`. **Если у тебя параллельно стоит VS2019 (папка `18`)** —
cmake может взять его cl.exe (14.50), с которым nvcc 13.1 несовместим
(`No CUDA toolset found`). Решение — Ninja-генератор + явный путь к cl.exe 14.44
(см. раздел 6).

### 4.3 CUDA toolkit 13.1

Установить с https://developer.nvidia.com/cuda-downloads (версия 13.1).
Проверить:

```bat
nvcc --version
```

## 5. Клонирование

```bat
git clone https://github.com/ikawrakow/ik_llama.cpp
cd ik_llama.cpp
```

Submodules встроены (`.gitmodules` пустой) — `git submodule update` не нужен.

## 6. Сборка

Файл `build_ik_llama.bat` в корне репо. Что он делает:

```bat
@echo off
setlocal
call "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Auxiliary/Build/vcvars64.bat"
set PATH=C:/Program Files/CMake/bin;C:/Python314/Scripts;%PATH%

cd /d F:/ik_llama.cpp

REM Удаляем кэш прошлого configure (обязательно!)
if exist build rmdir /s /q build

REM Явный путь к cl.exe 14.44 — обходит конфликт с VS2019
set CL14=C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/cl.exe

echo === [1/3] CMake configure (Ninja, cl 14.44, CUDA arch 120) ===
cmake -B build -G Ninja ^
  -DGGML_CUDA=ON ^
  -DCMAKE_CUDA_ARCHITECTURES=120 ^
  -DLLAMA_CUDA_ARCHITECTURES=120 ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_C_COMPILER="%CL14%" ^
  -DCMAKE_CXX_COMPILER="%CL14%"
if errorlevel 1 (
  echo CONFIGURE_FAILED
  exit /b 1
)

echo === [2/3] Build llama-server (Release) ===
cmake --build build -j 16
if errorlevel 1 (
  echo BUILD_FAILED
  exit /b 1
)

echo === [3/3] Проверка бинаря ===
if exist build\bin\llama-server.exe (
  echo BUILD_OK
  dir build\bin\llama-server.exe
) else (
  echo BUILD_OK_BUT_BINARY_MISSING
)
endlocal
```

### Ключевые моменты сборки

| Параметр | Значение | Почему |
|---|---|---|
| `-G Ninja` | Ninja-генератор | VS-генератор падает из-за конфликта версий MSVC; Ninja заставляет cmake брать компилятор напрямую |
| `-DGGML_CUDA=ON` | Включить CUDA | Без этого — CPU-only сборка |
| `-DCMAKE_CUDA_ARCHITECTURES=120` | sm_120 | RTX 5060 Ti = Blackwell = sm_120. Для других GPU: 86 (RTX 30xx), 89 (RTX 40xx), 90 (H100) |
| `-DLLAMA_CUDA_ARCHITECTURES=120` | То же для llama-слоев | Дублирует для безопасности |
| `-DCMAKE_BUILD_TYPE=Release` | Release | О3-оптимизации |
| `-DCMAKE_C_COMPILER/-DCMAKE_CXX_COMPILER` | Явный cl.exe 14.44 | Обходит авто-детект, который может взять VS2019 |

### Результат

- Бинарь: `build/bin/llama-server.exe` (~8 МБ)
- Время сборки: ~20-40 мин на 16-поточном CPU
- Проверка: `build\bin\llama-server.exe --version` → `version: 1 (commit) built with MSVC 19.44.x`

### Повторная сборка

**Обязательно** `rmdir /s /q build` перед повторным configure — иначе cmake
переиспользует кэш с неправильным компилятором/архитектурой. `build_ik_llama.bat`
делает это автоматически.

## 7. Запуск сервера

Файл `run_ik_qwen38.bat` в корне репо (пример для Qwen3.8-27B):

```bat
@echo off
setlocal
set PATH=C:/Program Files/CMake/bin;C:/Python314/Scripts;%PATH%

set IK=F:/ik_llama.cpp/build/bin/llama-server.exe
set MODEL=G:/MODEL-LM-STUDIO/cHunter789/Qwen3.8-27B-i1-IQ4_KS_KT-GGUF/Qwen3.8-27B.i1-IQ4_KT-attn_qkv-IQ4_KS.gguf

if not exist "%IK%" (
  echo [ERROR] llama-server.exe не собран: %IK%
  echo Сначала запустите build_ik_llama.bat
  pause
  exit /b 1
)
if not exist "%MODEL%" (
  echo [ERROR] Модель не найдена: %MODEL%
  exit /b 1
)

echo === Запуск ik_llama.cpp сервера: Qwen3.8-27B, ctx 65536, порт 8080 ===
"%IK%" ^
  -m "%MODEL%" ^
  -a Qwen3_8-27B ^
  --ctx-size 65536 --n-gpu-layers 99 ^
  --cache-type-k q4_0 --cache-type-v q4_0 ^
  --batch-size 512 --ubatch-size 128 ^
  --flash-attn on --merge-qkv -khad -vhad ^
  --host 127.0.0.1 --port 8080 --metrics --jinja ^
  --reasoning on --reasoning-format none --reasoning-budget 16000 ^
  --chat-template-kwargs "{\"preserve_thinking\": true, \"reasoning_effort\": \"medium\"}" ^
  --temp 0.6 --top-k 20 --min-p 0.05 --top-p 0.95 --repeat-penalty 1.05
endlocal
```

### Что означает «сервер готов»

В консоли появляется:

```
HTTP server listening at http://127.0.0.1:8080
```

Холодный старт (загрузка 27B в VRAM): 30-60 секунд. Проверка:

```bat
curl http://127.0.0.1:8080/health
```

Ожидается: `{"status":"ok","slots_idle":1,"slots_processing":0}`

### Остановка

Ctrl+C в окне консоли, либо:

```bat
taskkill /F /IM llama-server.exe
```

## 8. Разбор всех флагов

| Флаг | Значение | Зачем |
|---|---|---|
| `-m <путь.gguf>` | Путь к модели | GGUF-файл |
| `-a Qwen3_8-27B` | Alias модели | Имя в API. **Без точки** — Hermes config рвёт ключи по точке |
| `--ctx-size 65536` | Контекст 64K | Жёсткое требование для Hermes |
| `--n-gpu-layers 99` | Все слои на GPU | 99 = «все». Меньше = часть на CPU (медленнее) |
| `--cache-type-k q4_0` | KV-cache K в q4_0 | Компактный KV: 16GB VRAM не держит 27B + KV@64K в f16 |
| `--cache-type-v q4_0` | KV-cache V в q4_0 | То же |
| *`--spec-type ngram-mod`* | ~~Speculative decoding~~ | **УБРАН 2026-08-16** — см. раздел 14, п.10 |
| `--batch-size 512` | Размер батча prompt | Быстрый prompt processing |
| `--ubatch-size 128` | Размер под-батча | Баланс скорость/память |
| `--flash-attn on` | Flash attention | Экономия VRAM + скорость |
| `--merge-qkv` | Объединить Q/K/V | Оптимизация для гибридных моделей |
| **`-khad`** | **Fused GDN K на GPU** | **КЛЮЧЕВОЙ флаг: без него GDN на CPU → 4-7 т/с** |
| **`-vhad`** | **Fused GDN V на GPU** | **КЛЮЧЕВОЙ флаг: без него GDN на CPU → 4-7 т/с** |
| `--host 127.0.0.1` | Локальный хост | Только локальный доступ |
| `--port 8080` | Порт | 8080, чтобы не конфликтовать с LM Studio :1234 |
| `--metrics` | Включить метрики | `/metrics` endpoint |
| `--jinja` | Jinja-шаблоны | Чат-шаблоны модели |
| `--reasoning on` | Включить reasoning | Для reasoning-моделей |
| `--reasoning-format none` | Формат reasoning | Без специальных маркеров |
| `--reasoning-budget 16000` | Бюджет reasoning | Максимум токенов на reasoning (снижен с 32000 → 16000 для предотвращения переполнения ctx, см. раздел 14) |
| `--chat-template-kwargs` | Параметры шаблона | `preserve_thinking` + `reasoning_effort` |
| `--temp 0.6` | Температура | Баланс креативность/детерминизм |
| `--top-k 20` | Top-K | 20 лучших токенов |
| `--min-p 0.05` | Min-P | Отбросить токены с p < 0.05 |
| `--top-p 0.95` | Top-P (nucleus) | 95% вероятностной массы |
| `--repeat-penalty 1.05` | Штраф за повтор | Лёгкое подавление повторов |

### Критически важные флаги

**`-khad -vhad --merge-qkv`** — без них GDN-слои падают на CPU → 4-7 т/с.
С ними — 25+ т/с. Это главное отличие от stock llama.cpp.

## 9. Как работает сервер

### Архитектура

```
┌─────────────────────────────────────────────────────────┐
│                    llama-server.exe                     │
│                                                         │
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐ │
│  │  HTTP Server   │  │   Slot Mgr    │  │   Metrics   │ │
│  │  (OpenAI API)  │  │  (1 slot)     │  │   (/metrics)│ │
│  └───────┬───────┘  └───────┬───────┘  └─────────────┘ │
│          │                  │                           │
│  ┌───────▼──────────────────▼──────────────────────────┐│
│  │              Model Runtime (ik_llama.cpp)            ││
│  │                                                      ││
│  │  ┌────────────────────────────────────────────────┐ ││
│  │  │  Qwen3.8-27B (гибрид: transformer + GDN)       ││
│  │  │                                                ││
│  │  │  Transformer layers: CUDA (sm_120)             ││
│  │  │  GDN layers: FUSED CUDA (-khad -vhad)          ││
│  │  │  KV cache: q4_0 (K+V)                          ││
│  │  │  Flash attention: on                           ││
│  │  └────────────────────────────────────────────────┘││
│  └──────────────────────────────────────────────────────┘│
│                                                         │
│  VRAM: ~15.9GB / 16GB (модель + KV)                     │
└─────────────────────────────────────────────────────────┘
```

### API endpoints

| Endpoint | Метод | Описание |
|---|---|---|
| `/health` | GET | Статус сервера |
| `/v1/models` | GET | Список моделей |
| `/v1/chat/completions` | POST | Чат (OpenAI-совместимый) |
| `/v1/completions` | POST | Completions (OpenAI-совместимый)
| `/metrics` | GET | Prometheus-метрики |

### Пример запроса

```bash
curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3_8-27B",
    "messages": [{"role": "user", "content": "Привет"}],
    "temperature": 0.6,
    "max_tokens": 100
  }'
```

## 10. Интеграция с Hermes Agent

Hermes цепляется к OpenAI-API endpoint, а не к движку. ik_llama.cpp поднимает
тот же `/v1` контракт, что LM Studio → переключение тривиально.

### Шаги

1. Сервер уже слушает `:8080` (не :1234, чтобы не конфликтовать с LM Studio).

2. Добавить провайдер через `hermes config set` (НЕ patch config.yaml напрямую):

```bat
hermes config set providers.ikllama.base_url "http://localhost:8080/v1"
hermes config set providers.ikllama.discover_models false
hermes config set providers.ikllama.models.Qwen3_8-27B.context_length 65536
```

> ⚠️ Имя модели **БЕЗ ТОЧКИ** (`Qwen3_8-27B`) — `hermes config set` рвёт ключ по точке!
> Поэтому на сервере alias `-a Qwen3_8-27B`, а не `-a Qwen3.8-27B`.

3. Переключить основной provider:

```bat
hermes config set model.provider ikllama
hermes config set model.default Qwen3_8-27B
```

4. Откат (вернуть LM Studio):

```bat
hermes config set model.provider lmstudio
hermes config set model.default nvidia/nemotron-3-nano-omni
```

### Результат

- Новая сессия Hermes отвечает через Qwen3.8 (ik_llama.cpp)
- Русский UTF-8 корректен
- Chat работает
- Первый запрос в сессии может дать «модель не готова» — это прогрев слота/KV,
  просто повторите запрос (второй ответит нормально)

## 11. Интеграция с LM Studio (почему НЕ работает)

LM Studio использует stock llama.cpp, который **не имеет CUDA-ядер для GDN**.

### Что происходит

1. `lms load X --gpu max --context-length 65536` → `Failed to allocate buffer for kv cache`
   (16GB VRAM не хватает на веса 16GB + KV@64K)
2. `lms load X --gpu 0.9 --context-length 65536` → crash `exitCode=3221226505`
   (0xC0000005, access violation — mixed-device для гибрида нестабилен)
3. `lms load X --gpu max --context-length 16384` → загрузился, но **3.31 т/с**
   (KV в VRAM, но GDN-слои всё равно на CPU)

### Вывод

Через настройки LM Studio >10 т/с на 64K контексте **НЕ получить**.
ik_llama.cpp — единственный путь к 25+ т/с.

### Альтернатива без сборки (если 3-7 т/с достаточно)

Оставить LM Studio, принять: при 64K контексте стабильно 3-7 т/с (KV unified в RAM).

## 12. Замер скорости

```bash
# Python-замер (bc нет в git-bash)
python -c "
import time, requests
t0 = time.time()
r = requests.post('http://127.0.0.1:8080/v1/chat/completions',
    json={'model': 'Qwen3_8-27B',
          'messages': [{'role': 'user', 'content': 'Напиши стих'}],
          'max_tokens': 600})
t1 = time.time()
data = r.json()
tokens = data['usage']['completion_tokens']
print(f'{tokens} tokens in {t1-t0:.2f}s = {tokens/(t1-t0):.2f} tok/s')
"
```

## 13. Диагностика и troubleshooting

### GPU/драйвер

```bat
nvidia-smi
```

Смотреть: Name, Driver Version, Memory-Usage.

### Лог сервера

Сервер пишет в консоль. Если запущен через `.bat` — окно консоли.
Можно перенаправить: `run_ik_qwen38.bat > server.log 2>&1`

### Свободная RAM

```bat
wmic OS get FreePhysicalMemory
```

### Загруженные модели (LM Studio)

```bat
lms ps
lms ls
```

### Если сервер не стартует

1. Проверить, что `llama-server.exe` существует: `dir build\bin\llama-server.exe`
2. Проверить, что модель существует: `dir "%MODEL%"`
3. Проверить, что порт 8080 свободен: `netstat -an | findstr 8080`
4. Проверить, что GPU доступен: `nvidia-smi`
5. Проверить, что LM Studio не грузит модель (конфликт VRAM): `lms ps`

### Если скорость низкая (< 10 т/с)

1. Проверить, что флаги `-khad -vhad --merge-qkv` присутствуют
2. Проверить, что `--n-gpu-layers 99` (все слои на GPU)
3. Проверить, что `--cache-type-k q4_0 --cache-type-v q4_0`
4. Проверить VRAM: `nvidia-smi` (должно быть ~15.9GB занято)
5. Если VRAM < 15GB — модель частично на CPU → снизить контекст

## 14. Грабли

1. **VS2019 рядом с VS2022** — cmake берёт cl.exe 14.50, с которым nvcc 13.1 несовместим
   (`No CUDA toolset found`). Фикс: Ninja-генератор + явный путь к cl.exe 14.44.
2. **Перед повторным configure** — `rmdir /s /q build` (иначе cmake переиспользует кэш
   с неправильным компилятором).
3. **Файлы IQ4_KS_KT (тип кванта 144)** не грузятся в stock llama.cpp / LM Studio —
   только в ik_llama.cpp.
4. **16GB VRAM** не держит 27B + KV@64K в LM Studio — только в ik_llama.cpp
   (компактный KV q4_0 + fused ops).
5. **bc нет в git-bash** — замер скорости через `python` (time.time()), не через `time`/`bc`.
6. **Electron LM Studio не кликабелен через computer_use SOM** — управлять через
   `lms` CLI / REST API :1234.
7. **GPU offload 0.9 падает на гибриде** — только 100% GPU (но тогда KV@64K не лезет в 16GB)
   или 100% CPU.
8. **Имя модели с точкой** — `hermes config set` рвёт ключ по точке. Использовать
   `Qwen3_8-27B`, не `Qwen3.8-27B`.
9. **Первый запрос в новой сессии** может вернуть «модель не готова» — это прогрев
   слота/KV, второй запрос уже отвечает нормально. Не путать с ошибкой.
10. **`--spec-type ngram-mod` убран (инцидент 2026-08-16).** При запуске с
   `--spec-type ngram-mod:n_max=2` сервер выдавал предупреждение
   `ngram_mod n=12 is too small - poor quality is possible` (длина шаблона
   n-граммы взялась дефолтная `n=12`, а `n_max=2` — только 2 токена спекуляции
   за шаг). Суть: спекулятивная декодинг n-граммами НЕ меняет вывод модели
   (текст бит-в-бит тот же), влияет только на скорость. Но при `n_max=2`
   выигрыша почти нет, а накладные расходы на согласование черновиков могут
   замедлять. Бенчмарки (unsloth, Qwen3.6-35B, апрель 2026) показали, что ngram-SD
   на Qwen-семействе **часто net-negative** (декод −3…12 %). Симптомы/варианты:
   - **Симптом:** не ошибка, а мягкое предупреждение; на качество ответа и
     стабильность сервера НЕ влияет; VRAM — +16 МБ под буфер ngram.
   - **Вариант А (ПРИНЯТ):** убрать флаг `--spec-type ngram-mod:n_max=2` совсем →
     честная однотокенная генерация; вероятно чуть быстрее + чище конфиг.
   - **Вариант Б:** настроить «по науке» — `--spec-type ngram-mod:n_max=16,n_min=2,ngram_size_n=24`
     (реальный шанс угадывать длинные куски, но профит на Qwen не гарантирован).
   - **Вариант В:** оставить как есть (предупреждение безвредно).
   **Итог:** выбран Вариант А — флаг удалён из `run_ik_qwen38.bat`; сервер
   перезапущен, предупреждение исчезло.

## 15. Лицензия

MIT — см. `LICENSE`. Разрешены: копирование, модификация, публикация,
коммерческое использование. Обязательное условие — сохранение copyright-notice.

**Благодарность оригинальным авторам:**
- [ikawrakow](https://github.com/ikawrakow) — автор ik_llama.cpp, кастомных квантов и fused GDN
- [ggml-org](https://github.com/ggml-org) — ggml/llama.cpp
- [ggerganov](https://github.com/ggerganov) — автор оригинального llama.cpp
