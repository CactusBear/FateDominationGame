# Windows 服务端控制台包装器

基于 Godot 4.7.2 `platform/windows/console_wrapper_windows.cpp`，MIT 许可全文保留在源码头部。修改：消费 CtrlC/CtrlBreak，去掉 JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE，正确引用相邻引擎路径，等待并返回真实引擎退出码。不负责强杀后代；子进程生命周期由服务端原生所有权管理器负责。

在 VS2022 x64 Native Tools 环境编译：
`cl /nologo /std:c++17 /O2 /MT /EHsc console_wrapper_windows.cpp /Fe:FateServer.console.exe /link shlwapi.lib version.lib`

Windows 服务端导出并复制外部 data 后必须执行：
`python tools/replace_windows_server_console_wrapper.py --server-dir <独立服务包目录> --wrapper tools/windows_server_console/FateServer.console.exe`

工具校验已验证二进制SHA，仅替换FateServer.console.exe，保留官方wrapper备份，不替换FateServer.exe或官方Godot安装。重新编译需先运行真实信号验收，再显式提供新的SHA参数。
