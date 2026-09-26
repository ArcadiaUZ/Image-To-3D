@echo off
REM ============================================================
REM  Image-To-3D — TO'LIQ O'RNATISH
REM  Vositalar, manba kodi, Vulkan, build, modellar (~15 GB), Python
REM
REM  Ishga tushgandan keyin:  start_server.bat  ->  generate_auto.bat rasm.png
REM  Birinchi marta VS Build Tools o'rnatilsa, terminalni QAYTA ochib
REM  setup.bat ni yana ishga tushiring.
REM ============================================================
setlocal
cd /d "%~dp0"
echo.
echo   Image-To-3D — o'rnatish boshlandi
echo   Bu bir necha daqiqa davom etadi, modellarning yuklanishi uzoq turadi.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0provision.ps1"
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="2" goto reopen
if not "%RC%"=="0" goto failed

echo  [+] O'rnatish yakunlandi. Endi quyidagilarni bajarish kerak:
echo        1.  start_server.bat
echo        2.  generate_auto.bat rasm.png 6 20 20
pause
exit /b 0

:reopen
echo  [!] Visual Studio o'rnatildi.
echo      Terminalni QAYTA oching va setup.bat ni yana ishga tushiring.
pause
exit /b 0

:failed
echo  [!] Ba'zi qadamlar muvaffaqiyatsiz bo'ldi. Yuqoridagi xabarlarni o'qing.
echo      Batafsil jurnallar: provision.log, build.log
pause
exit /b %RC%
