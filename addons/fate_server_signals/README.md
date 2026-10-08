# 服务端系统信号适配层

此扩展只把 Windows Ctrl+C 与 Linux SIGINT/SIGTERM 转为主循环可读取的标记。
保存、广播、房间关闭和失败处理仍由 GDScript 的 `server_shutdown.gd` 负责。
普通客户端不启用信号接管。房间工作进程通过 `protect_worker` 吸收同控制台或进程组中的中断，等待网关的保存后关闭请求，防止中断先杀掉权威进程。
强杀、Windows 关闭控制台窗口与断电不在保障范围内。原生处理器也识别 Ctrl+Break，但 Godot 控制台包装器可能先终止，未提供与 Ctrl+C 相同的退出保障。

## 构建

依赖 godot-cpp `godot-4.4-stable`，固定提交 `714c9e2c165db2dcb7e6ea57e62a04204d3cfbfa`。
库的 MIT 许可需随发行包提供；构建依赖源码无需随包分发。
在本目录运行，`CPP_DIR` 替换为依赖的实际路径：

```sh
scons platform=linux target=template_release arch=x86_64 godot_cpp_dir="$CPP_DIR" build_profile=build_profile.json -j2
scons platform=windows use_mingw=yes target=template_release arch=x86_64 godot_cpp_dir="$CPP_DIR" build_profile=build_profile.json -j2
```

Windows 使用 MinGW-w64 交叉编译并静态链接 C++ 运行库；Linux 使用系统 C++ 编译器。
使用 Godot 4.4 的 GDExtension 接口以兼容本项目的 Godot 4.7.2。
测试必须发送真实操作系统信号，不能用直接调用 `shutdown.start()` 代替。
