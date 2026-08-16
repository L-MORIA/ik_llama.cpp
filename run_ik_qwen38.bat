@echo off
REM Обёртка запуска ik_llama.cpp сервера для Qwen3.8-27B (RTX 5060 Ti 16GB, 64k ctx) на :8080
REM Гермес цепляется к нему как к OpenAI-совместимому провайдеру ikllama (base_url http://localhost:8080/v1)
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
echo === (перед запуском выгрузите модель из LM Studio: lms unload) ===
"%IK%" ^
  -m "%MODEL%" ^
  -a Qwen3_8-27B ^
  --ctx-size 65536 --n-gpu-layers 99 ^
  --cache-type-k q4_0 --cache-type-v q4_0 ^
  --spec-type ngram-mod:n_max=2 ^
  --batch-size 512 --ubatch-size 128 ^
  --flash-attn on --merge-qkv -khad -vhad ^
  --host 127.0.0.1 --port 8080 --metrics --jinja ^
  --reasoning on --reasoning-format none --reasoning-budget 32000 ^
  --chat-template-kwargs "{\"preserve_thinking\": true, \"reasoning_effort\": \"medium\"}" ^
  --temp 0.6 --top-k 20 --min-p 0.05 --top-p 0.95 --repeat-penalty 1.05
endlocal
