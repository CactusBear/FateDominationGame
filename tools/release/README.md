# 显式发行角色契约

`release_prepare.py` 保留原 CLI 参数、默认 Windows/client；新增 `--role signaling`。
`package_audit.py` 保留原 CLI，新增可选 `--platform/--role`；省略 role 时只接受
该 preset/platform 在工程声明中唯一匹配的 target。没有声明不再按 dedicated_server
或 data 目录存在推测职责；缺声明必须拒绝，不是兼容性回退。

待冻结的源工程必须提供 `release_contract.json`（生产工程/presets 不由工具自动改写）：

```json
{
  "version": 1,
  "targets": [
    {
      "preset": "FateServer Windows",
      "platform": "windows",
      "role": "signaling",
      "executable": "FateSignaling.exe",
      "runtime_files": [
        {
          "source": "addons/fate_server_signals/bin/libfate_server_signals.windows.template_release.x86_64.dll",
          "target": "libfate_server_signals.windows.template_release.x86_64.dll"
        },
        {
          "source": "addons/webrtc_native/lib/libwebrtc_native.windows.template_release.x86_64.dll",
          "target": "libwebrtc_native.windows.template_release.x86_64.dll"
        }
      ]
    }
  ]
}
```

- target 用精确 preset/platform/role 联合键；全部字段必填。runtime_files 可以显式为空，
  但包内每个信令 GDExtension 的 Windows x64 release/fallback 库必须在其中声明。
- client/server 必须有 data 目录，继续使用原 `copy_data_after_export.py` 完整复制运行文件，
  audit 比对缺失/额外/修改。没有 data 不能作为免复制理由；独立 data 复制 CLI 完全不变。
- signaling 必须是独立工程：`[network] signaling_only=true`，无有效 autoload。
  不调用游戏 data copier；只复制 runtime_files 的明确映射。已存在依赖必须 SHA 相同，
  不覆写不同内容；所有路径须为无重定向的工程内相对路径，目标不能覆盖 EXE/PCK/data。
- freeze 将声明及其依赖纳入精确集合/哈希验证，且只在冻结副本的 exclude_filter
  排除发行声明。纯信令源工程本身应只包含实际运行资源，不复制整个游戏工程。
- audit 对独立非加密 PCK 使用现有 v3/v4 索引与全内容 MD5/SHA 验证；信令额外核对
  descriptor SHA、实际 release DLL 声明映射/SHA、拒绝包内 data/tests/tools/发行元数据。
  信令不接受嵌入 PCK；原游戏 embed_pck 契约保留，本工具不声称校验其内部资源。
- 所有 execute 仍必须提供冻结清单及显式无凭据确认，新输出必须不存在且位于 scratch。
  `STATIC_PASS_RUNTIME_PENDING` 不是 READY/原生加载/启动成功；这些必须另做运行任务。