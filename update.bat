@echo off
REM ============================================================
REM  Image-To-3D — TEKSHIRUV va YETISHMAYOTGANNI YUKLASH
REM
REM  update.bat          yetishmagan elementlarni yuklaydi
REM  update.bat -Check   faqat hisobot beradi, hech nima yuklamaydi
REM  update.bat -Force   hammasini qayta yuklash
REM ============================================================
setlocal
cd /d "%~dp0"

set MODE=
if /i "%~1"=="-Check" set MODE=-Check
if /i "%~1"=="-Force" set MODE=-Force

echo.
if "%MODE%"=="-Check" (
  echo   Image-To-3D — tekshiruv, hech nima yuklanmaydi
) else (
  echo   Image-To-3D — yetishmaganlarni yuklash
)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0provision.ps1" %MODE%
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" (
  echo  [!] Muvaffaqiyatsiz bo'lgan qadamlar bor. provision.log ni ko'ring.
  pause
  exit /b %RC%
)
pause
exit /b 0
