@echo off
REM  Image-To-3D — KO'P SEED -> eng rasmga o'xshashini avtomatik tanlaydi
REM  Foydalanish:  generate_auto.bat rasm.png [n_seeds] [steps] [texture_steps] [bosh_seed]
REM  Masalan:     generate_auto.bat rasm.png 6 20 20
setlocal
set ROOT=%~dp0
set PY=%ROOT%.venv\Scripts\python.exe
if not exist "%PY%" (
  echo [XATO] Python muhiti yo'q. Avval setup.bat ni ishga tushiring.
  exit /b 1
)
"%PY%" "%ROOT%generate_auto.py" %*
exit /b %ERRORLEVEL%
