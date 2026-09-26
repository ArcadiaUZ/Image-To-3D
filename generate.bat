@echo off
REM  Image-To-3D — bitta rasm -> teksturali 3D GLB
REM  Foydalanish:  generate.bat rasm.png [seed] [steps] [texture_steps]
setlocal
set ROOT=%~dp0
set PY=%ROOT%.venv\Scripts\python.exe
if not exist "%PY%" (
  echo [XATO] Python muhiti yo'q. Avval setup.bat ni ishga tushiring.
  exit /b 1
)
"%PY%" "%ROOT%generate.py" %*
exit /b %ERRORLEVEL%
