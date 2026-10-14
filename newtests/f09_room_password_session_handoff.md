# 密码请求 Session 生产接线交付

完成后释放 `scripts/net/session/lobby_session.gd` 写权；主代理可继续下一小任务。

## 范围

- Session 仅新增复用 `_host_room_password_request` 实例，并替换 `room_password` 分支原 set/persist/rollback。
- 保留 sender==owner / phase==lobby / String 前置拒绝、原失败文案、revision += 1、ok=true 及末尾 `_publish()`。
- recovery_state_path 判断仍属 Session：空路径显式成功 noop；非空绑定原 `_persist_recovery_state`。
- 模块 `host_room_password_request.gd` 只读，未修改。
- identity_ack 与其它分支未修改。与接线前快照逐字核对 identity_ack 相同；该 ack 仍未迁出接线，不宣称 F09 全完成。

## 验收

命令（工作目录仓库根）：

- `python -B newtests/f09_room_password_session_runner.py red`：wrapper exit 0；真实 Godot PID 38992 exit 1，预期缺少接线失败，无 engine_error。
- `python -B newtests/f09_room_password_session_runner.py final-green E:/scratch/pw-9051221c`：wrapper exit 0；真实 Godot PID 32548 exit 0；唯一 RESULT，48 checks，failures=[]，无 engine_error。
- `git diff --check -- scripts/net/session/lobby_session.gd`：exit 0。

覆盖公开 request() 的成功、三种前置拒绝、persist失败回滚、setter失败短路、空密码取消、无路径显式noop、实例复用、真实request_rejected/rejected/error及seq。另以 super._persist_recovery_state 实际创建恢复文件读回、真实目录目标保存失败、取消密码落盘空verifier。测试凭据不输出。

计数测试仅观察 `_publish` 边界，保留生产发布函数不改，未宣称完整远端发布验收；未跑恢复/full/测速/GUI/监听端口/模块38专项。

E短路径隔离，Godot主程序和console均复制到独占 E/engine；原DLL复制未重建；APPDATA/LOCALAPPDATA/TEMP/TMP/TMPDIR 都为 E；实际USER_PATH在E；Job active_owned_processes=0。首次runner仅复制console导致缺主exe，已修复，不能把该失败算业务RED。

## 证据与 SOURCE SHA256

证据：`E:/scratch/pw-9051221c/evidence/final-green-verified.json`、`source-final.json`、`red-verified.json`、各 stdout/stderr 日志；最终生产/测试源码与冻结副本hash相同。

- Session：`7041f1c384c91f52d6a4e854be9f12e83e507871976355ec72a0e272685a353e`
- 只读事务模块：`71106339b98abd39bbed6cce3d6dc1afba83c8c24698dc57e8b2a6a2ee38e615`
- `newtests/f09_room_password_session_test.gd`：`5ef96a49f50e562460f59d8d8c358c0ae089a630514b9ca4474ad9db932a21a1`
- `newtests/f09_room_password_session_test.tscn`：`fcce126c3c364e55a3bd85150eb5185937b3f348535e0af0593747344d13c894`
- `newtests/f09_room_password_session_runner.py`：`420f2fb905c1300a83f3f5ae1482b5fba62f464e428e0221dba3db186c705fb5`
