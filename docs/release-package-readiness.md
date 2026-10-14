# Windows 三角色人测包：封包就绪静态核对（未导出、未启动 Godot）

来源：2026-10-10 只读静态核对（读文件/哈希/引用，未冻结、未导出、未写文件）。**本文件不构成"导出已通过"或"发行准入"。**
范围已由用户确定：**仅 Windows 三角色（client/server/signaling）+ 含一键启动脚本**；无凭据声明已由用户批准（见 `docs/credential-free-evidence.md` §6）。

## 1. 六项核对结论

| 项 | 结论 | 关键证据 |
|---|---|---|
| ① 三角色角色声明 / EXE / 发布库映射 | **已具备** | `release_contract.json:5–18`(client, `FateDomination.exe`)、`:21–34`(server, `FateServer.exe`)、`:37–46`(signaling, `FateSignaling.exe`)；`round56_three_role_freeze.py:420–430` 生成声明/导出/复制；`signaling_prepare.py:25–31,39,46–48,67–70`、`round56_three_role_freeze.py:469–472` |
| ② 隐私排除 | **声明已接消费者；剩"审计未跑"一面** | `role_privacy_audit.py` 状态串：`DECLARATIONS_AUDITABLE_PRIVACY_ENFORCEMENT_INCOMPLETE` → **`PRIVACY_PACKAGE_CONSUMER_WIRED_AUDIT_NOTRUN`**（消费者已接线，`checks_removed=[]`，真实 exit 0）；`DECLARED_NOT_WIRED` 标记已消失（命中 0）。**注意 exit 0 ≠ 隐私门全完，状态串才是判据**；剩余"审计未跑"随冻结包一起完成。声明与消费者见 `freeze_prepare.py:13–22,82–87,55–63,153–168`、`package_audit.py`、`release_privacy_policy.json` |
| ③ 包内启动脚本 | **已接线并核验（2026-10-11）** | 模板已移出 `tools/`：现于 `release/human-test/START-{CLIENT,SERVER,SIGNALING}.cmd` + `Launch-HumanTest.ps1`（`aa7a7999…`/`ee818ccd…`/`efb47b65…`/`90165efe…`，原字节不变，**旧目录已清空**）；根白名单 `freeze_prepare.py:23`，三角色**各自显式声明**对应 CMD + 共享 helper（不按目录扫描猜测）；旧覆盖逻辑 `human_test_candidate.py:364`、旧文本校验 `:545` 已不再覆盖 CMD；冷冻结清单含 CMD/helper **1442/1442/16**，严格显式清单 **1901/1901/17**；**主代理独立重跑** `python -B tools/release/role_privacy_audit.py` → **exit 0**、`checks_removed=[]`、`godot_invoked=false`；Python 专项 29 tests OK。新路径已确认**不在** freeze/package 的 `deny_components`（含 `tools`/`newtools`/`docs`/`tests`/…）内 |
| ④ formal 回执阶段 | **已具备 `client-startup`** | `round56_three_role_freeze.py:496–497` 的 `RUN_PHASES`/`ALL_RUN_PHASES`；消费者 `human_test_candidate.py:28`；精确匹配门 `:169–177`（错误常量 `FORMAL_RECEIPT_EXACT_PHASES_REQUIRED`） |
| ⑤ 冻结前必等写者 | **必须等；已观察到真实漂移** | `lobby_session.gd` `7a192df7…` → `e07db399…`；漂移拒绝点 `round56_three_role_freeze.py:131–148,378–383`、`freeze_prepare.py:219,226,233` |
| ⑥ 是否还有阻断导出的未决项 | **是（见第 3 节）** | 旧 `NOTIMPLEMENTED` 已不再阻止阶段执行（`:957–960`、`:875–896`）；`exit3` 仍可能正确出现（`:588–591` `INCOMPLETE_NOTRUN`） |

### 两种信令布局不可混用

- 根声明 `release_contract.json:37–46` 是"signals DLL 放角色根"的**通用布局**；
- round56 实际走**外置 `native/` 布局**（`round56_three_role_freeze.py:444–460`、`signaling_prepare.py:25–31`）。
- 开发游戏工程直接选 signaling 被正确拒绝（"纯信令工程禁止游戏/其他 autoload"）；**必须走既有转换入口，不直接导出开发工程**。

## 2. 隐私侧：消费者已接线（`PRIVACY_PACKAGE_CONSUMER_WIRED_AUDIT_NOTRUN`），剩"审计未跑"；当前冷选集未命中禁入名

仍会被选择/复制、而本不应允许的条件路径：

| 路径类型 | 缺口证据 |
|---|---|
| `data/<任意名>.pem/.key/.log/.dmp` | `freeze_prepare.py:86` 对 `data` 不限扩展名；外置 copier 只跳过 `.import` |
| `data/validation-probe-*.json` | 无最终文件模式拒绝；策略仅声明于 `release_privacy_policy.json:134–136` |
| 显式 `runtime_files` 指向已排目录的文件 | `freeze_prepare.py:73–77` 直接加入；依赖也会另行加入（`88–99,122–125`） |
| 任意额外包文件 / 重新封入运行后的 `test-users/**` | `package_audit.py:142` 只记录集合不强制完整白名单；`human_test_candidate.py:29,61–66` 禁入项仅有限集合 |

**当前实际冷选集未发现上述禁入名命中**——既不能因此说"存在凭据泄漏"，也不能把"当前没命中"当成完整防护。

## 3. 出包前必须先完成

1. **写者交接**：等 `lobby_session.gd` 等全部写者停止，并检查整个冻结闭包（不只那三个文件）。
2. ~~**隐私最终集合门接线**~~ → **声明已接到实际消费者**（`PRIVACY_PACKAGE_CONSUMER_WIRED_AUDIT_NOTRUN`、真实 exit 0、`checks_removed=[]`）；**剩"审计未跑"一面，随正式冻结包一起完成**。不得为让审计过而删检查（不改导出过滤语义）。
3. ~~**启动模板与配置的封包接线**~~ → **启动脚本部分已完成并核验（2026-10-11）**：`human_test_candidate.py` 不再生成旧 `%*` 透传 CMD（旧生成 `:364`、旧文本校验 `:545` 已改），三角色按显式声明各自取对应启动脚本；`docs/human-test-quickstart.md` 已改为"双击对应启动脚本"并写明环境/临时目录隔离与 host、guest 独立身份目录。**已完成（2026-10-11 主代理核验）**：①部署配置**已声明并进冻结目标**——`release_contract.json:51–52` server→`server.cfg`、`:75–76` signaling→`signaling.json`；新增 `assets/config/signaling.json`（`{"roles":["relay"],"p2p_signaling":true,"port":24680,"bind_address":"127.0.0.1"}`，SHA `1ec13ce74ad8851fa5bd29e5cd364757832bb6dff7d8e33cca50149bfc4db0c7`；**端口 24680 取自 `assets/scenes/main_menu/multiplayer_lobby.tscn:111`，不是发明数字**，且运行时确实要求显式 `port`：`server_cli.gd:56–57`）；`round56_three_role_freeze.py:477–481` 信令精确目标集合现为 **3 项**（`START-SIGNALING.cmd`/`Launch-HumanTest.ps1`/`signaling.json`）；三角色 dry-run **全 exit 0**（server `target_config_entries=["server.cfg"]`、signaling `["signaling.json"]`、client 无配置目标，均 `DRY_RUN_NO_COPY`、`godot_invoked=false`）；`server.cfg` 走 include_filter 且既有排除保持、`signaling.json` **不进 PCK** 只走外置映射 → **隐私过滤语义未变**（主代理独立跑 `role_privacy_audit.py` **exit 0**、`checks_removed=[]`）；Python 单测 11/15/27 OK。②quickstart `:63/:66/:67` 与 `human_test_candidate.py:308/:316` 五处文案**已按 2改落地**（逐处前后原文见任务回执）。**仍未验**：未导出、未启动 Godot、未执行 EXE/启动脚本；包内最终哈希、真实监听/READY/停机与真人联机仍待后续。**不能组包后手工替换绕过 manifest。**

## 4. 精确命令顺序（仅清单，本轮未执行）

```bash
set -euo pipefail
cd 'E:/Projects/Godot/FateDominationGame-master'
APPROVED_ROOT='E:/Caches/Hermes/cache/scratch'
ID=$(python -B -c 'import uuid; print(uuid.uuid4().hex)')
BUILD_ROOT="$APPROVED_ROOT/$ID-build-only-diagnostic"
RUNTIME_ROOT="$APPROVED_ROOT/$ID-formal-runtime"
PACKAGE_ROOT="$APPROVED_ROOT/$ID-human-test-candidate"
GODOT='D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe'
TEMPLATES='C:/Users/Administrator/AppData/Roaming/Godot/export_templates/4.7.2.stable'
SIGNAL_RUNNER='E:/FateCandidates/round53-signaling-runtime-entry-sa1/diagnostic-tools/runner.exe'
SIGNAL_RUNNER_SHA='6d4e5e6bb6ada3020513c3159660aee824435b15e09249cf920074a40ae75ded'
export PYTHONDONTWRITEBYTECODE=1
export TMPDIR="$APPROVED_ROOT" TEMP="$APPROVED_ROOT" TMP="$APPROVED_ROOT"

python -B tools/release/round56_three_role_freeze.py --build-only-diagnostic \
  --source 'E:/Projects/Godot/FateDominationGame-master' \
  --root "$BUILD_ROOT" --approved-root "$APPROVED_ROOT" --godot "$GODOT" --templates "$TEMPLATES"
# 取 manifest.json 与其 SHA256 后：
python -B tools/release/round56_three_role_freeze.py --run-formal --run-phase all \
  --artifact-manifest "$BUILD_ROOT/manifest.json" --artifact-manifest-sha256 "$MANIFEST_SHA" \
  --root "$RUNTIME_ROOT" --approved-root "$APPROVED_ROOT" --godot "$GODOT" \
  --signal-runner "$SIGNAL_RUNNER" --signal-runner-sha256 "$SIGNAL_RUNNER_SHA"
# 取 formal-runtime.json 与其 SHA256 后（须先完成第 3 节的接线）：
python -B tools/release/human_test_candidate.py \
  --artifact-manifest "$BUILD_ROOT/manifest.json" --artifact-manifest-sha256 "$MANIFEST_SHA" \
  --formal-runtime "$RUNTIME_ROOT/formal-runtime.json" --formal-runtime-sha256 "$FORMAL_SHA" \
  --roles client,server,signaling --output-dir "$PACKAGE_ROOT"
python -B tools/release/human_test_candidate.py \
  --artifact-manifest "$BUILD_ROOT/manifest.json" --artifact-manifest-sha256 "$MANIFEST_SHA" \
  --formal-runtime "$RUNTIME_ROOT/formal-runtime.json" --formal-runtime-sha256 "$FORMAL_SHA" \
  --roles client,server,signaling --verify-zip "$PACKAGE_ROOT.zip"
```

走 **build-only human-test-candidate**，不签发正式发行准入。

## 5. unknown（不得写成通过）

- 走正式 `--build` 时本轮**未取得并验证同源码 ready-token 与五依赖报告**（门在 `round56_three_role_freeze.py:247–270`）。
- 当前转换副本的**首次 import/export、真实 PCK 隐私、包内启动、worker/保存恢复/正常停止**均未验。
- 开发工程 `project.godot` = `986a066a…`，内存冻结转换结果 = `7386c817…`——**这是预期转换，不要求字节相等**（`freeze_prepare.py:42–67`、`round56_three_role_freeze.py:409–411`）。
