# Windows 真人测试交付记录

## 当前包

- 测试目录：`E:/Projects/Godot/FateDomination/test/feedback-v14/release/Windows-v14-human-test/`
- 整包：`E:/Projects/Godot/FateDomination/test/feedback-v14/release/Windows-v14-human-test-full.zip`
- SHA-256：`88162e1a9baed685393bda317fe8cc79440852d9a92fed545508a3d8687ac2ce`，并以 `sha256sum` 复核结果为准。
- 启动说明：包内 `README-真人测试.md`。

## 已实际验证

- 当前源码 Godot 导入 exit 0，修复了文档 CSV 被翻译导入器误识别造成的导入 ERROR。
- 当前源码重新导出 Client Windows release 与 Server Windows release，均 exit 0。
- 导出的服务端实际启动并输出 `SERVER_GATEWAY_READY`。
- 导出的客户端启动探针存活超过12秒。
- ZIP CRC、条目数和交付文件清单通过。
- UI 与联机专项：原生待答50项、残留/阶段34项、BUFF/浏览55项、手牌57项、真实worker回合46项。
- 本轮新增：终局战果摘要、显式 token 图像 BUFF 放大、事件/地图/部署/移动窗口30项；浏览总计62项。

## 真人测试边界

必须由真人补充验证：两台电脑局域网完整流程、跨公网可达性、信令 Starter 在目标 Windows 环境的 READY/停止、服务端 Ctrl+Break 优雅关服、恢复后的私有提示去重、终局返回、部署移动地点金框、事件悬浮动画、所有图像 BUFF 放大说明和完整战报结算。

自动化信令 Starter 在当前 Hermes bash 中执行 PowerShell 时返回 exit 127，尚未证明信令包失败；因此包可交真人测试，但信令部分不能标为自动化通过。服务端探针超时结束时有 Godot 退出资源诊断，不能替代 Ctrl+Break 优雅关服证据。
