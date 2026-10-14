# Round37 特殊令咒中断任务主代理接管

## 代码与语义边界

子代理上游超时后，主代理读取完整执行记录、当前MasterManager、LoadCommandSpell解析器及两个实际测试。子代理已经修改生产绑定为全部声明卡，并留下Node不存在get_global_mouse_position导致的解析错误，不能按失败摘要假定文件未改变。

现有LoadCommandSpell明确约定：解析列表第一个是主令咒，效果绑定仅取第一个。当前正式数据无多特殊令咒声明支持变更自动登记政策。主代理只精确撤回该子代理引入的MasterManager补丁，保留原有其他代码，没有整文件git还原。展示卡种声明不等同实际持有/可发动卡。

测试改为复用CloneObject、玩家实际command_spell区域与RegisterObjectEffects构造明确的多卡持有夹具；清退使用UnregisterObjectEffects并移除实际持有对象。没有给UI塞raw模板或伪造mirror，也没有改变生产规则的自动绑定范围。

## 实际验证

- newspecial_spell_materialization_test：真实headless 13 checks、exit0、无SCRIPT ERROR/ERROR。覆盖声明不自动授予、主令咒原契约、显式克隆及登记、独立效果身份、私有完整卡面与公开种类、观察者隐私、稳定ID及清退后重新材料化。
- local_spell_restore_test：真实非headless 25 checks、exit0、无SCRIPT ERROR/ERROR。多特殊卡折叠/展开/滚轮、稳定节点、真实卡面点击、取消不消耗与移除清理均执行。截图已原生读取：正式蓝色背景、资源、令咒主卡与特殊卡条实际可见，未见替代异常纯色块；不扩大成整个UI/OS裁切验收。
- command_spell_source_activation_test：真实headless 54 checks、exit0、无SCRIPT ERROR/ERROR；既有单机/ENet发动回归保持。
- local_spell_restore_test在headless仍有四个鼠标悬浮展开断言失败，19 checks/exit1但无脚本错误。该测试依赖warp_mouse与实际全局鼠标状态；不能把headless失败改成跳过或自动通过。它需作为窗口专项执行；纯状态/隐私由上述13项headless专项承担。补齐motion.global_position不解决headless鼠标能力边界，保留真实红日志。

原始日志：reports/refactoring/main-review/round37-*.log；最终两个专项日志为round37-final-newspecial_spell_materialization_test.log、round37-final-local_spell_restore_test.log。前期成员ID错误仅测试夹具原因：GameStart.game_start([0,1])后原本使用默认本地6，已改明确参与者0，不对生产身份逻辑作修改。

没有将原窗口99项pending为空归因于同一根因，也没有将新增显式材料化夹具冒充正式数据的自动多令咒政策。最终发行/多机/跨网仍未验收。
