# 房间专属素材解析

## 已实现与实测

- RoomAssets 从明确批准的文件清单及本机目录建立解析表，安装时逐文件核对 SHA-256。
- 网络视图只对显式 image/back_image/avatar 字段转换图片地址；房间 data 内的批准文件变成 room:// 相对引用，客机解析到自己已校验的目录。不查同名本机模板，不允许将主机绝对 data 路径作为回退。
- 大厅组装完成后安装素材目录，安装通过才确认当前版本。清单更换与关闭会话清除映射。
- 正式窗口专项经真实 ENet 下载卡图，核对正式卡位及已有放大入口的图片路径都指向客机独立目录，再用真实指针打开大图。已原生查看 net_room_assets.png，卡图可见。
- net_room_assets 12 checks、net_data_barrier_window 11 checks、net_v2_hand_window 31 checks、net_room_assets_window 7 checks 均 exit 0、failures=[]、无运行错误。

## 边界与仍未完成

- 当前未安装清单的旧会话保持原始路径行为，普通建房尚未安装全量选择清单，不能称所有房间已统一切换。
- 主机需要显式 install_room_assets 绑定经校验的素材源目录，不推断其他提供者的文件位置。
- 目前只映射图片数据，不改变规则根目录。房主选择后的引擎加载、隔离校验与恢复原始单机数据仍待接线。
- 共同 UI 包内的 res://assets/ 资源保留原路径；跨版本 UI 包一致性尚未做握手检查。
- RefCounted 自带 reference() 方法，新解析器采用 encode_path 名称，避免原生方法签名冲突；首次运行报错已通过 Godot --check-only 定位并修复。
