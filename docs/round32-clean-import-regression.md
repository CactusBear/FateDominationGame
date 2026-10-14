# Round32 clean import regression

结论：**top passed=true**（本次同一新 freeze 的当前13套与干净 import 均严格通过）

证据 manifest：`E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\manifest.json`
仅运行当前明确的13套；不读取旧 manifest 计数，不拼接旧39套；全程 headless、单套180秒、同一独占E freeze。
生产 project.godot、production/game tests、generic runner 和 MCP 均未修改；GitPlugin 错误没有全局忽略规则。

## 隔离 project.godot transformation
授权范围仅为副本 `[editor]` 的 `version_control/plugin_name` 与 `version_control/autoload_on_startup`；源工程保持原 hash。
原/冻 hash 与逐字段 transformation：
```json
{
  "scope": "isolated_project_copy_only",
  "authorized_section": "[editor]",
  "authorized_fields": [
    "version_control/plugin_name",
    "version_control/autoload_on_startup"
  ],
  "reason": "Disable development VCS autoload only in the isolated freeze before import.",
  "operations": [
    {
      "field": "version_control/plugin_name",
      "action": "remove",
      "original": "version_control/plugin_name=\"GitPlugin\"",
      "transformed": null
    },
    {
      "field": "version_control/autoload_on_startup",
      "action": "replace",
      "original": "version_control/autoload_on_startup=true",
      "transformed": "version_control/autoload_on_startup=false"
    }
  ],
  "source_sha256": "986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a",
  "transformed_sha256": "72e82db409d55d2ba67c4402b8ecf80a0804ca9129308793bc1a15b4352deb7b",
  "editor_before_sha256": "08c164108100adfbea21181b36809c1949ce3602325b6f44dfd63a2061706380",
  "editor_after_sha256": "0955fbdf9e85c7b3f880b2e3a76460cbe90c1c50f05f1d6ab48c961d160da192",
  "changed_sections": [
    "[editor]"
  ],
  "unauthorized_changes": [],
  "path": "project.godot",
  "source_file_sha256": "986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a",
  "frozen_before_sha256": "986a066adc6f0d1346d19612538780abaf2ce4d3cdfef4342db653a0b53d8c8a",
  "frozen_after_sha256": "72e82db409d55d2ba67c4402b8ecf80a0804ca9129308793bc1a15b4352deb7b",
  "authorized_paths": [
    "project.godot"
  ],
  "source_unchanged_after_transform": true,
  "threading_before": "[threading]\n\nworker_pool/max_threads=20\n",
  "threading_after": "[threading]\n\nworker_pool/max_threads=20\n",
  "threading_unchanged": true,
  "worker_pool_max_threads_20": true,
  "verified": true
}
```
freeze 比较中唯一允许的 source→frozen 差异：`["project.godot"]`。其余 freeze/source/frozen 漂移均严格拒绝。
20线程保持：True；threading 原文与变换后原文相同：True。

## Clean import
import exit=0；ERROR 行数=0；错误内容：[]

## 13 suites
|套件|真实 exit|checks|严格判定|错误/原因|
|---|---:|---:|---|---|
|net_validation_task_test|0|31|True||
|net_validation_simulation_test|0|35|True||
|net_validation_hard_timeout_test|0|37|True||
|net_parallel_validation_feedback_test|0|9|True||
|room_data_preparation_consumer_test|0|50|True||
|room_data_preparation_dependencies_test|0|34|True||
|lobby_content_environment_restore_test|0|1544|True||
|net_data_sync_test|0|14|True||
|net_blob_test|0|42|True||
|net_blob_authorization_test|0|58|True||
|net_blob_send_authorization_test|0|14|True||
|net_blob_concurrent_test|0|20|True||
|net_worker_startup_contract_test|0|15|True||

同一 freeze 的最终源码漂移：`[]`；套件期间源码并行漂移/冻结漂移见 manifest，未降级比较。
## Raw logs
raw stdout/stderr/import/probe 日志均保留在独占 evidence 目录，以下为逐文件读回 hash：
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\import.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\import.stdout.log` sha256=`abbd9675d21fbb93d1e66153a5945e70091814c9bd983d61c7c80bd3e52054a0` bytes=94076
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\lobby_content_environment_restore_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\lobby_content_environment_restore_test.stdout.log` sha256=`a87e6096263c7b067a1d4968cd7f4cc197a485755a0927029f846201f0bca310` bytes=68158
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_blob_authorization_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_blob_authorization_test.stdout.log` sha256=`8f633071f19cf6e04e5c9afbd5d924fb5bb0867c744a613e694cc74336a4e4b3` bytes=3690
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_blob_concurrent_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_blob_concurrent_test.stdout.log` sha256=`18fdcf15424820c503dc76c6578f877ff63392e22127d06b3c619ce7ad3c9344` bytes=1154
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_blob_send_authorization_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_blob_send_authorization_test.stdout.log` sha256=`468114130c4920efcde55c76b620a3d8c9024b1cae2f2fcce7d552fabd437d86` bytes=748
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_blob_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_blob_test.stdout.log` sha256=`20999db7009c3bda22b64beee81f5b181617644f06ee80e4c8c9cc76b2de4996` bytes=1564
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_data_sync_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_data_sync_test.stdout.log` sha256=`6a105ba39568364406ebc17300bc93826d00fcaa5336e3290c6573ae1a5a617c` bytes=886
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_parallel_validation_feedback_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_parallel_validation_feedback_test.stdout.log` sha256=`33510567930e70d8b060719dbbbaa70da33aac1ade881b8747fea9ab958e46e3` bytes=670
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_validation_hard_timeout_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_validation_hard_timeout_test.stdout.log` sha256=`b2efe95c32673383156db32b5526724bca060b649f68c715fe9e3f6c7ff2d7f8` bytes=2589
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_validation_simulation_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_validation_simulation_test.stdout.log` sha256=`20d02d613fc7ccb83514d933f37280d48d6e86a0d60f551d1e6a4ad73917f745` bytes=2426
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_validation_task_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_validation_task_test.stdout.log` sha256=`4a29e7266a7cfbff863f89807c8ebe6d1e084cd01e41b4cf84f57d8e7efa6896` bytes=2160
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_worker_startup_contract_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\net_worker_startup_contract_test.stdout.log` sha256=`7e8e5fbfc0bde6610c8ccfc3e944a3d9023e2bb664a0de1a51a42f931e96c851` bytes=874
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\probe.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\probe.stdout.log` sha256=`c74e1d52ddba713dd3c614326b1e3bcfb0f1c15484363b5fc3a62cc19d09eb48` bytes=653
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\room_data_preparation_consumer_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\room_data_preparation_consumer_test.stdout.log` sha256=`647b51e910c3c67a71b88db1f3b74c11afb9092bf297cf9e67ba77436f78eaa1` bytes=3266
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\room_data_preparation_dependencies_test.stderr.log` sha256=`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` bytes=0
- `E:\scratch\isolated-b4cf8faad56442b7af9fc7d50c6da696\evidence\room_data_preparation_dependencies_test.stdout.log` sha256=`fb9bd3f177b93c057f5debb71fc1428f9bdd5c13af47db949d2a7e8cb343c7b4` bytes=2076

## Cleanup
清理状态：`generated_removed`；generated 删除后存在性=False；源 Godot hash 未变=True。
transformation 单元已完成 RED（无函数时 AttributeError）→GREEN（当前测试 PASS）；真实 Godot clean import 与13套重跑结果以 manifest 为准。
