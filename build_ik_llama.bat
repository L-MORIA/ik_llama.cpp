@echo off
REM Сборка ik_llama.cpp под RTX 5060 Ti (sm_120, Blackwell) — Qwen3.8 гибрид
REM Установка на диск F:
REM Используем Ninja-генератор + явные пути к cl.exe 14.44 (VS2022).
REM Ninja заставляет cmake брать компилятор напрямую, минуя путаницу со старым VS2019 (папка 18).
setlocal
call "C:/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Auxiliary/Build/vcvars64.bat"
set PATH=C:/Program Files/CMake/bin;C:/Python314/Scripts;%PATH%

cd /d F:/ik_llama.cpp

REM Удаляем кэш прошлого неудачного configure
if exist build rmdir /s /q build

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
