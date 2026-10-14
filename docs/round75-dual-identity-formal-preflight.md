# round75 同机双客户端身份隔离：执行前入口与授权边界

## 已亲读
- 仓库 hermesWarning.txt、CLAUDE.md；fate-domination-engine 的 multiplayer-human-test-release 与 godot-e-scratch-headless。
- docs/round71-dual-identity-readonly.md 与对应 evidence.json（旧两侧 net_identity 均不存在，不能空集判成功）。
- 候选 E:/Caches/Hermes/cache/scratch/round71-human-test-candidate-validation-v3 的 docs/human-test-quickstart.md、client/START-CLIENT.cmd；客户端 PCK 索引/完整摘要。
- 旧包对应 project-client/scripts/net/ui/lobby_screen.gd、scripts/main_menu/main_menu.gd、opening_warp.gd、load_game.gd；现存正式身份实现。

## 正式入口
`开始游戏 → 联机大厅 → Identity/Apply（身份资料应用按钮）.pressed`。
绑定位于旧 project-client/scripts/net/ui/lobby_screen.gd:42–44；调用 `_prepare_identity()` → `session.configure_identity()` → `player_identity.open()`。
正常路径 `user://net_identity/private.pem`；不存在时正式实现生成 RSA 身份，存在时正式实现加载且拒绝无效密钥覆盖。驱动不直接调用这些方法，不自己生成/复制身份、不输出 session/公钥/指纹/票据或节点全集。

用户名及昵称仅填写 `hostproof75` / `guestproof75`（昵称各对应角色）；无服务器连接、无建房、无内容批准、无开局。仅填写用户名并不会调用身份生成；必须按应用按钮，或未来创建/加入房间时才准备。离线准备不保证生成 profile.json，私钥文件非空即可检查本任务。

## 批准与命令
用户本轮已明确要求在 E 盘独立 APPDATA/LOCALAPPDATA 各生成一份身份；此离线 UI 入口无 approved-data-root 或 identity-root 生产参数，不引入此类猜测参数。
为防误写，runner 自己要求精确批准其隔离根（这是测试 runner 参数，不是产品 CLI）：

```bash
TMPDIR='E:/Caches/Hermes/cache/scratch' TEMP='E:/Caches/Hermes/cache/scratch' TMP='E:/Caches/Hermes/cache/scratch' PYTHONDONTWRITEBYTECODE=1 python -B newtests/round75_dual_identity_formal.py --approve-root E:/Caches/Hermes/cache/scratch/round75-dual-identity-formal-20261010-saidentity
```

固定根必须原先不存在；原候选只读，复制其 client/（排除任何运行数据）到该根 client/，校验复制前后 EXE/PCK/DLL/launcher SHA。
各角色变量：

```bat
set "APPDATA=E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\test-users\<role>\appdata"
set "LOCALAPPDATA=E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\test-users\<role>\localappdata"
set "TEMP=E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\test-users\<role>\temp"
set "TMP=%TEMP%"
set "TMPDIR=%TEMP%"
```

第一、二次角色为 host、guest；第三次 guest-reopen 复用 guest 环境，以验证 host 退出后的先后启动。runner 额外设置仅驱动使用的 `FD_PROOF_ROLE`、`FD_PROOF_CONTROL`，分别为本轮角色标签及根下 controls/<label>/。不存在产品身份 root 重定向。

真实进程命令模板（执行回执记录展开后的完整字符串）：

```bat
"C:\Windows\System32\cmd.exe" /d /s /c ""E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\client\START-CLIENT.cmd" --headless --audio-driver Dummy --rendering-method gl_compatibility --max-fps 30 --script "E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\identity_formal_driver.gd" --log-file "E:\Caches\Hermes\cache\scratch\round75-dual-identity-formal-20261010-saidentity\<label>.engine.log""
```

`--script` 是本轮外置 SceneTree 测试驱动，不替换 PCK/生产脚本；由它加载 PCK 声明的正式主场景，再通过正式开场键盘事件、菜单按钮 pressed 信号及大厅身份应用按钮 pressed 信号进入生成链。不会使用 --quit-after 冒充生成，不直接调用私有准备方法。正常退出由驱动收到 runner 的自有控制文件后执行 SceneTree.quit(0)。因此能证明正式按钮处理链与磁盘身份隔离，**不等价于非 headless 鼠标/窗口人测**。

## 写入与安全
唯一仓库写入 newtests/ 新 runner/驱动和 docs/ 新报告。所有执行副本、临时文件、身份及日志均在上述 E 根；不清理、不上传身份目录。身份字节只流式计算 SHA-256，绝不文本读取/解析/打印；日志只输出白名单驱动标记及错误计数。
复用 tools/run_isolated_godot_test.py 的 OwnedJob，不复制生产进程管理；CMD 以 suspended 创建，加入本轮 Job 后才 resume。只枚举自有 Job 的 PID，不终止 PID 17120/28100；看门狗只停止自有 Job，任何强制收尾使验收失败。

## 验收序列
1. 空目录基线 → host 经正式按钮生成 → 保存非空 SHA。
2. host 保持存活 → guest 经同入口生成 → host SHA 未变、同名文件 SHA 不同，保存 Job 共存 PID。
3. 两侧重复应用 → SHA 均不变；guest 正常退出 → host 再应用 → host 正常退出。
4. 完全退出后 guest-reopen 经同一主场景/按钮入口重新读取身份 → guest SHA 不变、host SHA 不变 → 正常退出。
5. 核对所有观察 PID 真实退出码、Job active=0、无强杀、全日志 SCRIPT ERROR/Parse Error/ERROR: 计数；失败/缺证标未证实，不能空集 PASS。
