# AGENTS.md — инструкции для AI-агентов в этом репозитории

Этот файл — контекст для LLM-агентов (Hermes, Claude Code, Codex и т.п.),
работающих с данным форком ik_llama.cpp.

## Что это за репозиторий

- **Форк** [ikawrakow/ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp)
  (сам — форк llama.cpp). Лицензия **MIT**, файл `LICENSE` не удалять.
- Назначение: локальный инференс **гибридных моделей** (transformer + Gated Delta Net,
  например Qwen3.8-27B) на NVIDIA GPU с **fused GDN-ядрами на GPU**.
- Целевая машина: Windows 11, RTX 5060 Ti 16GB (sm_120 / Blackwell),
  сборка MSVC 14.44 (VS2022 BuildTools) + CUDA 13.1 + Ninja.
- Рабочая сборка: `build/bin/llama-server.exe` (~8 МБ), сервер на `127.0.0.1:8080`.

## Ключевые файлы (не путать с upstream)

| Файл | Роль |
|---|---|
| `build_ik_llama.bat` | Рецепт сборки под Windows (Ninja + явный cl.exe 14.44 + arch 120) |
| `run_ik_qwen38.bat` | Рецепт запуска Qwen3.8-27B, 64K ctx, порт 8080 |
| `BUILDING_RTX5060Ti.md` | Полное руководство: сборка, флаги, интеграции, troubleshooting |
| `ARCHITECTURE.md` | Как функционирует движок и гибридные модели |
| `llama.log`, `nvcc_log_*.txt`, `testcu.cu`, `nul` | **Диагностические артефакты** локальной отладки. Не коммитить, но и не удалять без спроса владельца |

## Правила для агентов

1. **Не трогать upstream-исходники** (`src/`, `ggml/`, `examples/`, `common/`)
   без явной задачи. Это код оригинала; локальные изменения кастомизируют
   сборку, а не движок.
2. **`.bat`-файлы игнорируются upstream `.gitignore`** (`*.bat`). При добавлении
   использовать `git add -f`.
3. **Перед повторным cmake configure** — `rmdir /s /q build`
   (cmake кэш с неправильным компилятором ломает сборку).
4. **MSVC только 14.44 (VS2022)**. Если рядом VS2019 — cmake может взять его
   cl.exe 14.50 → `No CUDA toolset found` с nvcc 13.1. Обход: Ninja + явный путь.
5. **Критичные runtime-флаги**: `-khad -vhad --merge-qkv` (fused GDN на GPU).
   Без них скорость падает с 25 до 4-7 т/с. Не «оптимизировать» их удаление.
6. **KV-cache q4_0** (`--cache-type-k/v q4_0`) — обязателен для 27B + 64K в 16GB VRAM.
7. **Имя модели в Hermes-конфиге без точки**: `Qwen3_8-27B` (alias `-a Qwen3_8-27B`),
   т.к. `hermes config set` рвёт ключи по точке.
8. **Порт 8080** — не 1234 (конфликт с LM Studio).
9. **Перед push** — скан секретов (пути `C:\Users`, токены, ключи). Локальные
   пути дисков F:/G: в `.bat` — допустимы (это рабочая рецептура).
10. **Не пушить без явной команды владельца.**
11. **Первый запрос в новой сессии** может вернуть «модель не готова» — это
    прогрев слота/KV, не ошибка. Повторить запрос.
12. **Сервер должен быть запущен ДО обращения клиента.** Если он упал —
    клиент получит ошибку подключения, а не ответ модели.

## Полезные команды

```bat
:: Статус сервера
curl http://127.0.0.1:8080/health

:: Список моделей
curl http://127.0.0.1:8080/v1/models

:: GPU
nvidia-smi

:: Версия бинаря
build\bin\llama-server.exe --version

:: Замер скорости (Python, bc в git-bash нет)
python -c "import time,requests; t0=time.time(); r=requests.post('http://127.0.0.1:8080/v1/chat/completions', json={'model':'Qwen3_8-27B','messages':[{'role':'user','content':'привет'}],'max_tokens':600}); t1=time.time(); d=r.json(); print(f\"{d['usage']['completion_tokens']} tok / {t1-t0:.2f}s = {d['usage']['completion_tokens']/(t1-t0):.2f} tok/s\")"
```

## Диагностика

- **Низкая скорость (<10 т/с)**: проверить флаги `-khad -vhad --merge-qkv`,
  `--n-gpu-layers 99`, `--cache-type-k/v q4_0`; VRAM через `nvidia-smi`.
- **Сервер не стартует**: бинарь существует? модель существует? порт свободен
  (`netstat -an | findstr 8080`)? GPU доступен? LM Studio не держит VRAM (`lms ps`)?
- **Сборка падает**: `No CUDA toolset found` → конфликт MSVC (пункт 4 правил).
- **Модель не грузится (тип кванта)**: IQ4_KS/IQ4_KT (тип 144) — только
  ik_llama.cpp, в stock llama.cpp/LM Studio не грузятся.

## Ссылки

- Upstream: https://github.com/ikawrakow/ik_llama.cpp
- Оригинальный llama.cpp: https://github.com/ggml-org/llama.cpp
- Локальное руководство: `BUILDING_RTX5060Ti.md`
- Архитектура: `ARCHITECTURE.md`
