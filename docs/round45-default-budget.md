# Round45：历史默认30秒真实证据（已被15秒需求取代）

当前默认与当前完成链以[Round48](round48-countdown-completion.md)为准。本页仅保留用户先前30秒决定的实际结果，不以历史30秒通过冒充当前15秒验证。

- 完整正式68条目/204文件，95,949,242 bytes：未修改的validation_stage_timing_test单次23项、exit0、failures=[]、无ERROR；模拟budget30、elapsed30.108s；准备49.033176s，场景总墙钟58.055680s，满足180s。
- 原真实CLI默认契约子链24项成功；测试自己的长stdout JSON回执解析失败，保留原红。改为落盘回执后独立专项13项通过、exit0、34.735s；三种真实房间预算30/0/7.5原样传输与preparation.room_options消费，已有显式61.25配置不覆盖，pool20。
- 两次freeze仅新测试回执方式有差异；不将不同freeze称作一个统一候选PASS。首次导入cursor preload错误和父测试JSON解析错误都保留，不归因生产规则。
- 完整204原manifest：E:/scratch/isolated-dc2d3d96825f4e578d31edf12da48186/manifest.json，SHA256=ce86ff2886c1907c48ce6d8a31c35f6f249aefe530bbf02e8e98c8195fb1831a。
- 修复后默认契约原manifest：E:/scratch/isolated-f844fd8fc869412ab9dc76d5d71c3ed7/manifest.json，SHA256=378ae1a38389a5d4e31377cacde9eb738e8c195a92e8c5e98ac47375bc61787a。
- 当时cfg SHA256=63b1f3f6ad1864496617ff3250b53ea7a570fe0ab13ff6b65b41431fa6a87088；当前改15后的cfg不是这个hash。既有stage测试SHA256=ba2049018699690c48b9e9aed42b74422c4c2cb9cb50b68d0bec8c1b84ede97e，未修改。
- 初检204成功hash；组件登记/组装612次来源重验、无中间store；准备store204/fetch668；完整预算/guard、静态图、正式组装和隔离加载、安全路径均保留，详细timings.json与原报告在上述证据树。
- 主/真实child user回执物理E独占，所有自有Job退出、句柄释放、生成树已回收。没有换Godot、retry发布冒绿、触碰用户身份/存档/部署；历史Round43发布根因仍未根治。

模板只影响新建配置；已有显式配置不改。运行旧server不能仅改模板指望生效；当前CLI data不支持reload，须修改自己实例实际配置并重启自己实例，测试未操作用户server。
