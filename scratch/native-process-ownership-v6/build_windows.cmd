@echo off
call D:\VS2022\VC\Auxiliary\Build\vcvars64.bat
if errorlevel 1 exit /b 1
tools-env\Scripts\python.exe -m SCons -C overlay\addons\fate_server_signals platform=windows use_mingw=no target=template_release arch=x86_64 godot_cpp_dir=E:/Projects/Godot/FateDominationGame-master/scratch/native-process-ownership-v6/deps/godot-cpp-714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa build_profile=E:/Projects/Godot/FateDominationGame-master/addons/fate_server_signals/build_profile.json -j2
