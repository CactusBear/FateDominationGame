# Round72：四组关闭后切区——双输入单变量对照与一次 current 验收

## 结论

- **当前冻结复现，不是 nonrepro。** 干净第二对照：原 warp+push **67 checks / 3 failures / exit1**；仅删两处 `get_viewport().warp_mouse(point)` **69 / 0 / exit0**。生产 board/presenter/builder/mirror、点击坐标、等待帧、sleep、refresh、选区和断言完全相同，两个观察夹具逐字移除这两行后相等。
- 旧版真实 GUI `hover` 命中、down=1、pressed=1；关闭按钮释放后 index 仍0。随后额外非零 MouseMotion 到达 `_input`，index0→1；单路版没有该额外事件且保持0。不是“pressed 没有命中”，不是默认目标计时器切区。
- 只改夹具，不改任何生产方法或规则，不增加输入缓存、防抖、强 refresh、重新选区或固定延时。
- 一次最终 current：**65 + 69 + 59 + 55 + 19 = 267 checks，五专项全部 exit0 / failures=[]**；全部日志零 SCRIPT ERROR/SHADER ERROR/ERROR/WARNING；8个自有Job均退出、ActiveProcesses=0、log_handles_released=true。fixture scene预检的 exit1 是原合同明确要求 headless 拒绝，非业务失败。
- **modalregression PASS；geometry PASS；fullvisual PASS** 分开记录。已原生读取同一次最终深山/工房全1920×1080 PNG及裁片：每区四组十槽，真实头像展开两组，六牌可见5+1，无模态或 tooltip 盖住牌区。
- 独立正常 CardBrowser **19 checks**：真实 loader `jewel_card` 专属宝石背、攻击实例 `yin_qi_bullet` 已声明 Skill 背、未觉醒 `caliburn` 升华技背；正常 source→正式 renderer，三槽 source.back_image 与真实 texture.resource_path 均非空且完全相等，正面/名称/说明不公开。没有构造类型fallback。

## 唯一 current 与生产冻结

```text
python -B tools/tests/round69_modal_hover.py --source E:/scratch/round72-complete-source-current --label round72-current-final --current-final
```

完整生产源2108文件；最终只在测试拥有范围overlay。不拿早期不完整冻结的通过信用拼入最终。最终 `freeze_drift={}`、`owned_source_drift={}`、`outside_drift_observation={}`；末尾四个生产文件再次实读与冻结相等。

|生产文件|SHA256|
|---|---|
|board|6a6cecf4f5eb4672f5af77f4d9ac28d62543a0260e3d786f0bcd7781db52bc5d|
|presenter|dd409f9d35d6be0078fc83c6198dd1c1deed9c7f35e4a98be34812e39bf464b6|
|builder|9a7ed25688ded565bce41b0a8b7473f8067553b55629fbb7d7ce88a276ec831e|
|mirror|8007a3cc6e2e1ed0bb319ba3e1b3bd21fb825e7b9bc24f3f212a724c514eef20|

最终证据根：`E:/scratch/round69-modal-hover-round72-current-final/isolated-1b8da5c153464e80aa535ecedfa7aa64/`

- 原始 `manifest.json` SHA：`47159343507e82ce9c498873fb412219eae18f771d33d306106c6a23436f0b86`。
- 原生全图/裁片与独立最终读回：`round72-readback.json`，SHA `d2a66f0d3b46488c0bc3f664edc3b900f93f0a5bb873035a0ca57e2e12bb5936`。
- 原manifest遗留的scope文案仍说隐私需future freeze，**该句不符合本次实际输入**；读回receipt明确修正语义并绑定真实current builder/mirror，不篡改已归档原manifest字节。

|实际业务专项|checks|failures|exit|PID|秒|
|---|---:|---:|---:|---:|---:|
|groups-headless|65|0|0|见manifest|10.618|
|groups-window|69|0|0|见manifest|14.025|
|modal-current-window|59|0|0|见manifest|13.914|
|browsing-window（原事件浏览）|55|0|0|见manifest|13.910|
|special-viewer-window|19|0|0|见manifest|7.297|

此267是五个实际专项之和，**不是 full99/101 candidate**。原Godot和旧正式DLL没有替换；未操作用户28100；generated均按既有owned清理门回收，源快照和证据保留。

## 两对照与精简事件因果

实际控制命令：`python -B E:/scratch/round71_modal_input_controls.py`；最多两个旧/新对照，没有更多业务重试。有效第二对照根：

`E:/scratch/round71-modal-input-controls/isolated-ada4ce1953664dcd8ba82374d486a5c9/`

其manifest SHA：`7d2bbb00522ada5ef4794fdad42b183047cb77f94d0795be0071271106322fc5`。原始 stdout/stderr、`fixture-versions/old-warp-push.gd`、`remove-two-warps.gd`、runner及独立SHA读回均保留；共同观察只读取事件、鼠标及board状态，不修改生产。设备号两路均32，**不使用device区分合成与原生**。

|旧版 timestamp_usec|事件/状态|
|---:|---|
|11279512|分发motion前：position(1084,555.5)，relative(1,0)，modal=true，index=0，default=0，viewport实际鼠标(1084,555)|
|11289336|按钮释放分发后：modal=false，index仍0|
|11290721|只读frame：index0，default0，leave_time0|
|11295581|额外 `_input` MouseMotion：position(1084,555)，relative(1032,245)，modal=false，index已1|
|随后|TACTICAL_ALERT_AFTER：hover命中，pressed1，motion_index0，target0，active1；关闭守恒失败|

|单路 timestamp_usec|事件/状态|
|---:|---|
|11048222|同坐标motion前：relative(1,0)，modal=true，index0，default0，实际viewport鼠标(1084,555)|
|11058164|按钮释放后：modal=false，index0|
|11059653|只读frame：index0，default0，leave_time0.0333333|
|随后|TACTICAL_ALERT_AFTER：hover命中、pressed1、motion_index0、target0、active0；两处原生头像展开和完整geometry继续通过|

这个单变量对照支持“旧夹具warp产生第二路延后motion并在模态关闭后切区”的机制；不外推真实硬件鼠标也有同样问题，更不能据此修改生产吞掉关闭后的合法新motion。默认目标始终0，而旧异常切到1；不把该现象猜成 `_update_default_area` 回退。

## 自有代码解释与耦合

### tests/battle_play_groups_test.gd

- `gui_click`：只删warp；仍由Viewport分发motion，等待原一帧，核验hover链、真实gui_input down，再按原顺序push按下/释放。没有信号emit替代输入。
- `expand_and_verify`：只删移出头像处warp；保留原目的坐标、相对移动、原settle入口。两处删除是对照唯一变量。
- `concealed_evidence`：保留视觉门，改为正式声明背验证：source back非空、资源能加载、实际非空纹理路径等于解析声明和原声明、不是已知正面；不增加CHECK以改变原headless65，只增强独立VISUAL_GATE。

该夹具已经耦合正式source/renderer是有意集成测试；无需新增生产adapter、规则或防抖组件。观察器只在控制副本内，两版完全相同，最终生产测试不残留观察器。

### tools/tests/round69_modal_hover.py

- `--current-final`：复用原冻结、环境/probe/import、Windows Job执行、日志门和owned回收；跳过已单独归档的guard移除RED，不把另一次guard mutant混成当前最终。
- 独立viewer生成在本次generated，来自真实loader模型克隆，经正常source读到敌方隐藏弃牌，再交既有CardBrowser渲染；没有人工设置牌背或类型fallback。生成GD/scene纳入证据归档。
- 五专项计数从实际RESULT求和；modalregression、geometry、fullvisual分开。原生图片判断另有同manifest SHA的readback receipt，不把PNG保存成功等同视觉通过。
- `tools/tests/round64_shared_browsing.py` 未改。生产board/presenter/builder/mirror全只读。

当前测试SHA：`5238a6b955e7f1136c19b641277e29d823e279dc2bca321b5c34091354acfedb`；runner SHA：`2adcc81e097f273d0eb7337099b5143d099cf9c78bb2e764d5af40b6f779dc8b`。Python compile、git diff --check exit0。

## 预备执行器错误及保留边界

- 初次执行器失败：`isolated-b9b1427037064a2c9618d6b0d9176965` 的真实error为 `PatternError('unterminated character set at position 36')`；**processes=[]、suites=[]，没有启动Godot，不是GUI RED**。finally又因manifest漏generated引发ownership mismatch。只补自有真实身份，保留error、单独finalize并清理；generic门未改。
- 第一业务对照 `isolated-8757e50a4e9c483b88def450fdf83e87`：沿用旧依赖清单缺新 `host_match_request_inbox.gd`，两个窗口均含依赖编译ERROR；即使新单路exit0/69/0也不算干净PASS。补齐明确缺失的两项生产依赖到**新独立完整冻结**后才作第二且最后对照。第一批日志不删除、不冒称同冻结零错误。
- 初次scratch源复制误用hardlink，overlay使旧round69源目录同inode内容改变。生产仓和旧证据archive未改。随后用真正独立copy创建2108文件源并全SHA核验；旧目录六个生产文件从既有round69归档恢复。旧 `source-manifest.json` 已重建，不再宣称保持原manifest字节或初始测试字节，**旧源目录不应继续当原始不可变输入**；本次最终和有效对照仅用独立新源，证据无该共享inode问题。
- 原生裁片归档第一次system Python缺PIL；改用已有Hermes Python PIL完成同PNG裁片与hash读回，没有重新运行GUI。

## 仍未覆盖

- **Round71个人弃牌/公共局势弃牌迁移的真实GUI入口专项未运行。** 原事件browsing55与独立直接正常viewer不能代偿其pile命中、empty、滚轮、外部关闭、菜单开合等迁移边界；保留为 next UI gap，不再扩大本轮执行矩阵。
- 没有full99/101、导出、真实OS硬件鼠标、多机或跨网验收。真实ENet证据只属于同进程回环模态/事件浏览专项。
- 没有发现需要越权修改生产的新根因；给main的最小建议就是采用这两处夹具warp删除和声明背visualgate，不加生产输入防抖。
