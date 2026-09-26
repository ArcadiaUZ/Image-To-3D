@echo off
REM ============================================================
REM  Image-To-3D — tez yo'l (server kerak emas):
REM  rasm -> sodda OBJ mesh, matovasiz, ~70 soniya
REM  Foydalanish:  run_stage1.bat rasm.png [seed]
REM ============================================================
setlocal
set ROOT=%~dp0
if "%ROOT:~-1%"=="\" set ROOT=%ROOT:~0,-1%
set EXE=%ROOT%\workspace\trellis2cpp\build\examples
set M=%ROOT%\models

if "%~1"=="" ( echo [XATO] Rasm ko'rsating: run_stage1.bat rasm.png & exit /b 1 )
if not exist "%~1" ( echo [XATO] Fayl topilmadi: %~1 & exit /b 1 )
if "%~2"=="" ( set SEED=0 ) else ( set SEED=%~2 )
for %%F in ("%~1") do set NAME=%%~nF

if not exist "%ROOT%\work" mkdir "%ROOT%\work"
if not exist "%ROOT%\out"   mkdir "%ROOT%\out"

echo [1/3] DINOv3 conditioning...
"%EXE%\dino_encode.exe" "%M%\dino_f16.gguf" "%~1" "%ROOT%\work\%NAME%.dinodata" || goto fail
echo [2/3] Sparse-structure sampling...
"%EXE%\ss_sample.exe" "%M%\ss_flow_f16.gguf" "%ROOT%\work\%NAME%.dinodata" "%ROOT%\work\%NAME%.latent" --seed %SEED% || goto fail
echo [3/3] Mesh extraction...
"%EXE%\ss_mesh.exe" "%M%\ss_dec_f16.gguf" "%ROOT%\work\%NAME%.latent" "%ROOT%\out\%NAME%.obj" --iso 0 --normalize || goto fail

echo.
echo TAYYOR:  %ROOT%\out\%NAME%.obj
timeout /t 6
exit /b 0
:fail
echo [XATO] Pipeline muvaffaqiyatsiz. Avval setup.bat ni ishga tushiring.
exit /b 1
