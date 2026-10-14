@echo off
setlocal DisableDelayedExpansion
if not "%~1"=="" goto unexpected
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-HumanTest.ps1" -Role client
set "launch_exit=%ERRORLEVEL%"
echo LAUNCHER_EXIT_CODE=%launch_exit%
if not defined FD_LAUNCH_NO_PAUSE pause
endlocal & exit /b %launch_exit%
:unexpected
echo LAUNCHER_ERROR=ARGUMENTS_NOT_ACCEPTED_USE_FD_CLIENT_PROFILE
set "launch_exit=2"
echo LAUNCHER_EXIT_CODE=%launch_exit%
if not defined FD_LAUNCH_NO_PAUSE pause
endlocal & exit /b %launch_exit%
