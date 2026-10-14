# 部署启动期限声明（`startup_seconds`）

## 声明本身

- **`assets/config/server.cfg:25` 改为 `startup_seconds = 600.0`**（改前 `30.0`）。
- 归因更正：**不是用户指定的数值**。依据是用户口径"期限由**部署入口**显式声明、取'无论机器忙不忙都能起来'的保守安全值"，数值由主代理按实测定为 600.0。
- 依据的实测（同一冻结、两轮、独占空应用缓存根）：**缓存阶段 17.049–25.484 秒；创建请求到主管确认 READY 35.189–45.567 秒**。600.0 相对实测最大值留约 **13 倍**余量，是**有限安全上限，不是典型耗时，也不是无限等待**。
- 代码侧**未动**：`scripts/net/server/server_room_manager.gd:9` 的默认 `30.0` 保留；`scripts/net/server/server_cli.gd:101` 的缺键回退 30.0 与 `:59` 的校验未改。故"改配置"不等于"改生产默认"。
- CFG **未新增注释**（未先证明解析器跳过注释前不加）。

## 夹具侧对齐（不是产品改动）

- `newtests/round74_gateway_relisten_diagnostic_runner.py` 改为通过正式 `ServerBootstrap.read_configuration()` 读取冻结副本的 CFG，把该声明注入验收主管；READY 观察预算 = **声明值 + 10 秒**观察余量；外层 Job 看门狗 1200 秒。
- 原**业务断言全部保留**，未改成无限轮询；原 40000ms 硬编码 READY 门（短于实测最大值 45.567s）被替换。

## 结果

| 套件 | CHECK | exit | ERROR | Job |
|---|---:|---:|---:|---:|
| **gateway relisten acceptance** | **40/40** | **0** | 0 | 0 |
| worker startup error | 9/9 | 0 | 0 | 0 |
| worker startup stages | 9/9 | 0 | 0 | 0 |
| save_restore observation | **14/18** | 1 | 0 | 0 |

- 三个断言"`manager.startup_seconds == 30.0`（生产 30 秒未改）"**均为 true**。
- **限定（子代理自陈，必须保留）**：后两套使用了本次 acceptance **预热过的应用缓存**，**不等于默认 30 秒冷启动的认证**。
- **限定**：`save_restore observation` 的 4 条失败**不是启动超时**，首因是 `empty_lobby_save_rejected_not_saved`，另有回执绑定、保存阶段标记、日志身份披露失败——属保存路径观测缺口（见 `docs/round74-small-integration-queue.md` 的 F16 观测排队项）。

## 指纹（改前 → 改后）

```text
assets/config/server.cfg
  351798e5909021fa472f2206bdc63c1a9271322c5800cbfdffb96e2b491301d5
→ fcfff41958186aafa5139906ad4450fa8dcf82b69e7283558897bc230a9bd4e4

newtests/round74_gateway_relisten_diagnostic_runner.py
  260033c3a64a2cffd8d6f95e555cb5f00b98e4ea74f67d1f5faa0d1ca1e8c658
→ 21c1e828296f0b5e03d22cd6e0e7ad5f9ebbbe38b2cfb0db7c0e20c9fc2fe807
```

## 边界

- **人测包将随冻结副本带上 600s 声明**；本任务**未执行导出或打包**，不声称打包已完成。
- 原始证据目录：`E:/scratch/startup-declaration-evidence-a712403878d84fc997be7c1a9a22df01/`（`minimal.diff`、`commands.txt`、`verified-receipt.json`、`acceptance-report.md`）。
- 首轮新增守卫误用 void `check()` 的错误证据保留。
