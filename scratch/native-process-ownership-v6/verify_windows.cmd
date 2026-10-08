@echo off
call D:\VS2022\VC\Auxiliary\Build\vcvars64.bat
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /Ioverlay\addons\fate_server_signals\src native_test.cpp overlay\addons\fate_server_signals\src\process_owner_core.cpp /Fe:native_test_windows.exe /link bcrypt.lib
if errorlevel 1 exit /b 1
native_test_windows.exe
