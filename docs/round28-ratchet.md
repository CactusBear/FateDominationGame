# Round28 棘轮核验

## 已修改与核验

- 唯一代码写入：`tools/check_layer_deps.py`、`tools/check_inventory_drift.py`、新增 `tools/tests/test_round28_ratchet.py`。未改 production、manifest 或80条既有许可。
- manifest 原格式：顶层 `method/script_count/global_file_references/files`；每个文件条目以 `path/sha256` 为核验依据，其他统计字段不参与哈希门槛。仅覆盖 `scripts/**/*.gd`，不能将忽略 tests 的 inventory 范围误认成私有访问规则的范围。
- allowlist 原格式：`ExceptionSite(rule, path, target, code, evidence_line)`；词法锚点多重集合，重复项保留出现次数。此次未扩大、去重或退休许可。
- 两个工具新增只读 `--json`：输出实际退出码、PASS/FAIL/ERROR、授权根目录及精确 NEW/STALE 或 new/gone/drift，保留原文本 CLI。输入错误为2，变化为1，通过为0。
- `.gd` 同名目录不再错误当成脚本读取；非法 UTF-8 manifest 统一返回 ERROR/2；扫描文件的解析目标必须处于显式授权根目录。没有自动搜父工程、自动捕获许可或自动更新 manifest。

## 真实负向验证

所有新增夹具在仓库外 E 盘 `round28-ratchet-*` 临时目录真实落盘，测试退出自动删除；不在 production 注入，未启动 Godot 或窗口。

1. 从当前80条许可涉及的真实源码复制工程，实跑 CLI 基线通过。
2. `.gitignore` 忽略 tests/reports 仍捕获新增 helper 的私有访问；注释、普通字符串中的私有成员名不误报。
3. freeze 副本中真实私有访问报 NEW，删除 freeze 目录后恢复通过；不保留已删目录虚假 findings，不扩大许可。
4. 删除真实独占锚点只报一个精确 STALE，无 NEW；同一许可多重集合与新增真实重复访问分别验证次数。
5. 显式授权工程通过；其父目录、scripts 子目录及不存在路径均 ERROR/2，不回退到旁边工程。目录前缀 `scripts/systematic/` 不误认成 `scripts/system/`。
6. inventory 新 helper 为 new、旧文件改字节为 drift、删除为 gone；tests helper 不纳入 scripts manifest；重复路径、越级路径、非法 UTF-8 拒绝。
7. 原有测试同时覆盖类名、preload/load、路由字面量、同一行重复访问、owner 自访问、文本模块 Node 继承及每一条真实许可的单独退休。

## 实际命令与结果

```text
python -m unittest tools.tests.test_round28_ratchet tools.tests.test_check_layer_deps -v
退出0：23项，OK，1项 skipped。
python tools/check_layer_deps.py --root E:/Projects/Godot/FateDominationGame-master --json
退出0：findings=80，allowlist=80，NEW=0，STALE=0；layer=7，private=73。
python tools/check_inventory_drift.py --root E:/Projects/Godot/FateDominationGame-master --json
退出1：基线383，当前402；真实并行生产改动保留为new/drift，没有更新manifest掩盖变化。
```

机器证据：`docs/round28-ratchet-verification.json`，包含完整命令、stdout/stderr、实际退出码、两门槛 JSON，以及工具/专项测试/只读 manifest 的SHA256；供最终冻结整合读取。当前是工作树快照，不替代主代理在最终冻结版本重跑。

## 未验收与静态边界

- Windows 创建符号链接失败（WinError 1314，无所需权限），因此越出根目录的真实 symlink 专项跳过；有路径防护，但不宣称该场景已实机通过。
- 动态别名、反射、字符串拼接及访问授权语义仍不属于词法证明范围。资源路径字面量依据原规则视为依赖；不因其位于字符串就删掉路由/子进程依赖。
- 两工具未提供新写入口，不把并行 tree gate 暂红自动修成白名单。inventory 当前红色为预期检测结果，需主代理冻结整合处理。
