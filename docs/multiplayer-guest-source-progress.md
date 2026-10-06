# 客机条目来源接线

## 已实现并实测

- 大厅客机用共享条目弹窗显式勾选并共享，真实连接 ID 绑定来源。
- 上报索引校验类别、模板身份、目录归属、文件路径、预算和内容指纹；不信任自报 provider。
- 房主数据弹窗按提供者和类别展示；新客机来源默认不选，同名不同内容由房主取消多余来源后应用。
- 主机只按已接受来源清单拉取哈希；复用 BlobReceiver 接收预算、分块与 SHA-256 校验。
- 客机只响应主动共享的字节，没有按远端路径读取文件的接口。
- 拉取成功核对真实 JSON 身份、requires 和牌库查询；后续仍进入独立进程校验、主机加载、全员再分发与版本屏障。
- 换房清除旧勾选；下载等待预算按新偏移更新。

## 工具证据

- net_catalog_exchange_test：RESULT checks=15 failures=[]，exit 0，无引擎错误。
- net_data_selection_window_test -- window：RESULT checks=14 failures=[]，exit 0，无引擎错误。
- 后者真实点击共享与应用按钮，个别来源勾选由测试夹具设置，不宣称逐项复选框鼠标命中已验。
- 原生检查 tests/runtime_reports/net_data_selection.png；弹窗按钮可见，无越屏布局。
- 上一批 selected-data-regression：42 套，470 检查；唯一 ERROR 定位到 net_transport_test:17 端口占用反例。headless 跳过的窗口套件不计作画面验证。

## 尚未验收

- 多客机同时上传、完整大清单分片、上传共享的内存总预算仍需扩展。
- 提供者中断与并行缓存清理的完整交错矩阵未覆盖。
- 跨设备、跨公网、Linux 导出未实测。
- 服务端、P2P、随机预检、运行时保护及存档菜单仍未完成。
