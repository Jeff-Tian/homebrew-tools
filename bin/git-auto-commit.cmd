@echo off
setlocal

where bash >nul 2>nul
if errorlevel 1 (
  echo git-auto-commit requires Git for Windows ^(bash^) on PATH. Install it with: scoop install git 1>&2
  exit /b 127
)

bash "%~dp0git-auto-commit" %*
exit /b %ERRORLEVEL%
