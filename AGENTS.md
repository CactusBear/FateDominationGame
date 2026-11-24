# AGENTS.md

Fate 同人桌游 FateDomination 的电子游戏化项目。Godot 4.7（Mobile 渲染），主场景 `assets/scenes/main_menu/opening_background.tscn`，专用服务器入口 `assets/scenes/main_menu/server_bootstrap.tscn`。支持本地对局、局域网/联机、存档恢复、回放。

## 工作规矩（所有 agent 必须遵守）
- 回复和思考都用中文；修改代码前先给出所有代码的详细中文解释。
- 写代码前先想：当前实现耦合度是否过高、有没有更好的解耦方案，并报告给用户。
- 大改动前严格向用户对齐颗粒度；先读计划对应行再读代码，该读的文档必须读全。
- 写 operation：功能单一化，一个 operation 不做两件事，要考虑单独使用其中某个功能的情况，不随意加限制。计划新增前先想能否由现有 operation 组合替代；尽量不改现有 operation，多调几个能解决的就不要改。
- 写功能注重通用性，尽可能复用现有代码，减少冗余字段和可被现有功能替代的代码。
- 任何涉及规则的部分都不要写死，考虑例外情况；设计时必须考虑极限情况，不预设条件。
- 读图只用模型原生读图能力，不用 vision_analyze；做不到就告诉用户。
- 写新函数、新规则前，先在项目里搜有没有现成的。
- 提交被文件大小钩子拒了：照报错把文件按功能拆开再提交，不要绕过钩子。

## 目录路标
- `scripts/`：游戏逻辑。`match/`（对局会话、回放、命令分发）、`net/`（authority、server、session、transport 等联机层）、`system/`（`effects/`、`operations/`、`global/` 等规则与效果系统）、`game_scene/`、`main_menu/`、`debug/`。
- `assets/scenes/`：场景。`data/`、`game_data/`、`json_maker/`：卡牌数据与 JSON 编辑器。
- 仓库里没有常驻测试：`tests/`、`newtests/`、`newtools/` 已全部删除。有问题时现写测试、跑完就删，不留库。`tools/`：`release/`（发布打包链）、`hooks/`（pre-commit 文件大小钩子）、`check_layer_deps.py` 等 Python 脚本；`tools/diagnostics/` 与 `tools/tests/` 只剩发布冻结脚本依赖的几个文件，不是测试库。
- `docs/`：保留下来的设计与审计文档（重构计划见 `docs/refactoring-plan.md`，真人测试见 `docs/human-test-quickstart.md`）。涉及回放、存档或撤回时，先读 `docs/replay/当前进度.md`，实施前再读 `docs/replay/设计与实施方案.md` 对应章节；`docs/replay/历史记录.md` 仅按需查阅，进度原位更新，不追加流水。
- `GLOSSARY.md`：术语表（保存并退出、出错撤回等），用词以它为准。
- `.claude/`、`.agent/` 是本地 agent 脚手架，已在 .gitignore 中，与游戏无关。

## 项目特有的坑
- Windows 环境，现写的临时测试场景用 `--headless --path .` 跑（仓库里没有常驻测试，跑完就删）；脚本里 Windows 原生 Python 不认 `/e/...` 路径，用 `E:/...`。
- 仓库启用了 Git LFS（post-checkout/commit/merge、pre-push 钩子），不要改 `core.hooksPath`，否则 LFS 钩子失效。
- `tools/hooks/check_file_size.py` 是 pre-commit 钩子（阈值与跳过规则在 `tools/hooks/file_size_config.json`）：新增或变大的超标文件会被拒，历史超标但没变大的放行；`python tools/hooks/check_file_size.py --list-all` 列出现有超标文件。
- 删除 `scripts/` 内文件前先搜 `class_name` 和文件名引用；`.uid` 文件随 .gd 一起保留或一起删。
- 大扫除删掉的东西不一定都在 git 里：已提交过的可用 `git checkout <commit> -- <路径>` 找回；从没提交过的只在本地备份里，git 找不回。

## Agent skills

### Issue tracker

GitHub Issues（CactusBear/FateDominationGame，用 `gh` CLI 操作）。See `docs/agents/issue-tracker.md`.

### Triage labels

默认五角色词：`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`。See `docs/agents/triage-labels.md`.

### Domain docs

single-context（一个仓库共用根目录 `GLOSSARY.md`，架构决定放 `docs/adr/`）。See `docs/agents/domain.md`.
