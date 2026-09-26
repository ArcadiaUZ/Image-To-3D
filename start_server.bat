@echo off
REM ============================================================
REM  Image-To-3D — serverni mustaqil (detached) ishga tushirish
REM  Oynani yopishingiz mumkin, server ishlashda davom etadi.
REM ============================================================
setlocal
set ROOT=%~dp0
set EXE=%ROOT%workspace\trellis2cpp\server\trellis2-server.exe
set LOG=%ROOT%server.log
if "%ROOT:~-1%"=="\" set ROOT=%ROOT:~0,-1%

if not exist "%EXE%" (
  echo [XATO] Server topilmadi: %EXE%
  echo        Avval setup.bat ni ishga tushiring.
  exit /b 1
)
if not exist "%ROOT%\trellis2.dll" (
  echo [XATO] trellis2.dll topilmadi. Avval setup.bat ni ishga tushiring.
  exit /b 1
)

for /f %%i in ('curl.exe -s -m 3 -o nul -w "%%{http_code}" http://127.0.0.1:8742/api/jobs 2^>nul') do set CODE=%%i
if "%CODE%"=="200" (
  echo Server allaqachon ishlayapti: http://127.0.0.1:8742/
  exit /b 0
)

echo Server ishga tushmoqda (modellar yuklanadi, ~10-20 soniya)...

REM start /b oynadan mustaqil ishga tushiradi; dll papkasi PATH ga qo'shiladi
start "" /min cmd /c "set PATH=%ROOT%;%%PATH%% & "%EXE%" -lib "%ROOT%\trellis2.dll" -ggufs "%ROOT%\models" -store "%ROOT%\generations" -addr 127.0.0.1:8742 -no-1024 > "%LOG%" 2>&1"

for /l %%n in (1,1,40) do (
  for /f %%i in ('curl.exe -s -m 3 -o nul -w "%%{http_code}" http://127.0.0.1:8742/api/jobs 2^>nul') do set CODE=%%i
  if "%%CODE%%"=="200" goto ok
  ping -n 2 127.0.0.1 >nul
)

echo [XATO] Server ishga tushmadi. Jurnal: %LOG%
exit /b 1

:ok
echo.
echo ============================================================
echo   Server ishlayapti!
echo   Web UI :  http://127.0.0.1:8742/
echo   CLI    :  generate_auto.bat rasm.png
echo   To'xtatish: taskkill /IM trellis2-server.exe /F
echo ============================================================
timeout /t 4
exit /b 0
