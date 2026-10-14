# Round29 — 真实 LAN 恢复终局完整正确性

## 结论

**同一冻结版本完整正确性 PASS；不宣称 180 秒性能 PASS。**

最终 `run-complete`：Godot **exit 0，288.096s，RESULT checks=77 failures=[]**；外部预算600s，未触发取消，189次实际seq/journal进度样本。原局两个认证真人席位录制至中局，正式管理save、正常停止、创建另一个真实独立worker、显式身份恢复、数据ACK屏障、两观察者投影等价、六类负向、真实续写至自然round11终局、最终正式管理save回执及两次journal读取全部通过。没有缩回合、删动作候选、跳终局或改变规则预算/隐私。

`refactoring-gates.md` 第3节“长回放性能验证”区分用户批准的性能门与执行器看门狗。Round28的180s来自外层run.py取消；本轮只在独占冻结测试副本将两个测试deadline 180000改为600000，生产测试仍保留180000，规则保护声明不变。600s是本轮正确性上限，不是性能放宽或优化结论。

## 修改与根因

仅改本代理拥有的两份测试；`match_authority.gd`、`net_server_match_test.gd`未改，Session/引擎/manager只读，未提交。

- `tests/lan_restore_live_test.gd`：停滞计时只认权威seq或实际journal字节增长，不认decisions/预览/重复尝试。12s停滞保存完整view/pending/actions/group、Agent sent_seq/attempted/命令登记号、权威请求关联回执；所有续行退出及cleanup同样存证。正式终局save后新增第二次Godot Journal.read_all，比较全体记录与磁盘SHA256，保存`terminal-journal.json`。
- 同文件LiveEquivalent：正式`residue_cards`由ViewBuilder的card_view产生，原分类遗漏其id/effects，导致真实恢复ID重建误报。新增明确residue路径及image/back_image内容校验，沿用跨观察者同一双向映射，不删除字段、不排序、不机械忽略id。
- `tests/net_process_full_game_test.gd`：记录公开request登记号；修复首候选GroupSelection.add的实际朝向契约调用。仍选择同一首候选，只用其已声明modes中与本人held_cards.concealed一致的值，不新增翻牌/移动等动作、不放宽所有权或生产规则。

真实停滞证据：第一轮206.652s主动失败于round7，seq302/303与journal停住。当前行动者sent_seq300而seq303，pending为空、播报pending=false、连接/guard/管理员均未暂停，group未waiting/submitted。真实续写档用正式MatchReplay重放到round7/action（76.276s、exit0），首候选“瞬间的一击”实际concealed=true，但旧Agent固定传modes[0]=false，正式GroupSelection.add拒绝；每帧重复同一失败选择。不是Agent sent_seq锁，也不是播报确认屏障。未找到需要修复的生产恢复缺陷，因此未猜测性改生产。

紧反馈环：真实失败journal产生的正式投影作为输入，运行真实Agent和GroupSelection；旧调用RED exit1，修复GREEN exit0/3 checks；错误朝向和未持有牌仍拒绝。残留区比较器真实失败镜像RED（仅3处ID/effect路径），修复GREEN exit0/3 checks，残留card/effect冲突映射两项负向仍拒绝。正式整链rule/observer/privacy/asset/reference/barrier六类真实镜像变异全部拒绝。

## 终局证据

- 原局19条，新档200条；两客户端game_over均true，seq542/543，自然round11。
- 正式save回执：saved=true、records=200、真实worker PID11992，已按确切request_id/instance/room读回原`.response.json`，另归档`terminal-save.response.json`。
- 回执state_hash = journal尾after：`31efa1187401f7e52de21752fcce55a4fbbeced468e18de5ebec50bee60c064a`。
- 两次Godot完整读取均200条、未截断、记录完全一致；磁盘SHA256两次及归档后重读均为 `4e9361743afba6b3a4cd903b6cf87dcd672de45e082af065cf4d9e50d06e5af1`。
- 原档字节未改变，客户端不启动本地规则、不修改本地规则池，私有手牌持续过滤；两套真实worker与父进程全日志无SCRIPT ERROR/SHADER ERROR/ERROR，最终无CHECK false。

实际命令（冻结副本已按本轮所有权清理，须按归档指纹重建后重放）：

```text
python E:/Caches/Hermes/cache/scratch/round29-live-recovery-complete/run.py run-complete
D:/Godot4/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe
 --headless --fixed-fps 60
 --path E:/Caches/Hermes/cache/scratch/round29-live-recovery-complete/project
 --scene res://tests/lan_restore_live_test.tscn
```

APPDATA/LOCALAPPDATA、fixture与live根均为本次独占物理E目录；父进程真实user日志及两真实worker独立engine日志、matches日志均已落在该根。路径经no_links/physical_e检查，无junction；进程以挂起启动后绑定Windows Job再恢复，所有六次运行最终active_owned_processes=0；未按进程名清理，无其它PID被杀。未对worker额外打印OS.get_user_data_dir，不把仅环境声明说成此项独立探针已验证。

## 失败过程与保留风险

| 运行 | 秒 | 实际结果 |
|---|---:|---|
| run | 206.652 | 69 checks；12s seq/journal停滞，根因如上 |
| run-green | 219.489 | 推进round11，但终局条件前失败；旧版本未保存具体会话错误，原因未定位，不冒称修复 |
| run-diagnostic | 18.055 | 原worker房主认证/IPC就绪失败 |
| run-diagnostic-2 | 76.487 | 原局正式管理pause镜像条件失败 |
| run-final | 132.135 | 恢复残留区ID分类遗漏；真实镜像已保留并修复比较器 |
| run-complete | 288.096 | **77 checks，exit0，完整正确性PASS** |

辅助重放初次选择了恢复冻结中局档，并因空candidate访问错误挂到240s；这不是主验收。修正空候选保护及确切stall journal路径后，真实失败局重放76.276s成功。此诊断失误不作为恢复生产缺陷或推荐流程。

最终验收前仍有正式v2窗口PID13560及godot-ai attach进程存在；没有并发长perf测试记录，但不宣称全系统空闲或独占性能通过。启动/IPC/pause的间歇前置失败及run-green原因未定位仍是稳定性风险。当前工作树Session、v2及其它只读测试相对初始冻结有漂移；`final-source-hashes.json`保留准确差异。**PASS绑定本轮冻结生产版本+最终两份测试补丁，不等于其它代理后续整合版本已通过**，最终整合仍须按主代理冻结复核。

## 归档与清理

- 报告：`docs/refactoring-golden/round29-live-recovery-complete.md`。
- 证据：`reports/refactoring/round29-live-recovery-complete/`；88份初始归档及额外终局原save回执，完整stdout/worker日志、进度、失败pending诊断、比较投影、原/新journal、source-manifest、最终源码哈希、RED/GREEN、清理逐文件hash清单。测试与reports路径被git忽略，主代理须显式纳入交付，普通git status不会列出。
- scratch：`E:/Caches/Hermes/cache/scratch/round29-live-recovery-complete/`。真实原档与续写档的正式data仍保留；只移除本任务已结束的冻结工程、冗余worker运行data/cache及客户端副本，删除前逐文件大小/SHA256留账、删除后读回不存在，回收12403文件/4771125023字节；未触碰project20池或其它代理产物。
- `git diff --check -- tests/lan_restore_live_test.gd tests/net_process_full_game_test.gd` exit0。
- 技能`godot-live-recovery-projection`补充seq/journal看门狗、所有退出取证、Agent朝向契约和residue显式引用路径教训。
