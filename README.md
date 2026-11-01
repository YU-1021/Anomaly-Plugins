# Yu の Anomaly 插件源

Anomaly 的第三方插件源：`pluginmaster.json` 是 Runtime **Plugins > 可用** 直接读取的插件列表，
插件源码、构建脚本和发布包都由这个仓库维护。

- **插件源地址**（在 Anomaly 里添加这一条就行）

  ```text
  https://raw.githubusercontent.com/YU-1021/Anomaly-Plugins/main/pluginmaster.json
  ```

- 维护者：YU-1021 · 许可：AGPL-3.0-only · 需要 Anomaly **2.4.3**+（Plugin API 1）与 `nte`

## 安装

1. `Insert` 打开管理界面 → **Plugins > 第三方插件** → 添加插件源，填上面那条地址；
2. **Plugins > 可用** → 刷新 → 找到插件点 **安装**；
3. **Plugins > 已安装** → 启用。之后有新版本会出现在 **Plugins > 更新**。

不想用插件源也可以手动装：从 [Releases](../../releases) 下载 `com.yu.*-<版本>.zip`，解压到
`Anomaly\plugins\<包名>\`（`manifest.json` 必须在 ZIP 根 / 该目录根），重启 Runtime 或在插件界面重载即可。

第三方插件是在游戏进程里运行的原生 DLL，Anomaly 只校验格式与一致性、不校验代码安全，只装你信任的来源。

## 插件

| 插件 | ID | 版本 | 说明 |
| --- | --- | --- | --- |
| [伤害来源记录](plugins/DamageSourceRecorder/README.md) | `com.yu.damage-source-recorder` | 1.0.3 | 记录每一下伤害的类型/来源/数值，按「一段伤害」合并，可把记录到的 GameplayEffect 重新施加到原目标；角色受到的伤害同样能记录与重放 |

## 新增插件

`pluginmaster.json` 的根是**数组**，一个插件一个对象。加插件时数组里追加一条、URL 保持不变，
用户不用重新加源，**可用** 与 **更新** 会自动带上新条目。

1. 插件放在 `plugins/<名字>/`，自带 `manifest.json` 与 CMake 工程；
2. 在 `plugins.json` 登记短名（供 `build.ps1` / `release.ps1` / CI 使用）：

   ```json
   { "short": "damage-source-recorder", "name": "伤害来源记录", "dir": "plugins/DamageSourceRecorder", "package": "DamageSourceRecorder" }
   ```

3. 发布 ZIP 后在 `pluginmaster.json` 追加条目：`InternalName` 与包内 `manifest.id` **完全相同**，
   `Version` 与 `manifest.version` 完全相同，`DownloadLinkInstall` 指向该版本 Release 里的 ZIP；
4. 改完先跑一遍检查脚本，再提交推送。

```jsonc
{
  "Name": "另一个插件",
  "InternalName": "com.yu.another-plugin",
  "Version": "0.1.0",
  "Author": "YU-1021",
  "Punchline": "一句话说明用途。",
  "Games": ["nte"],
  "ApiMajor": 1,
  "RepoUrl": "https://github.com/YU-1021/Anomaly-Plugins/tree/main/plugins/AnotherPlugin",
  "DownloadLinkInstall": "https://github.com/YU-1021/Anomaly-Plugins/releases/download/another-plugin-v0.1.0/com.yu.another-plugin-0.1.0.zip"
}
```

### Runtime 的解析规则

来自 `src/repository/plugin_list.cpp` 与 `BuildCatalog`，这些是会直接影响「可用」页面的硬约束：

| 规则 | 后果 |
| --- | --- |
| 根必须是 JSON 数组 | 写成对象、或多一个逗号 → **整个源刷新失败**，本源所有插件一起消失 |
| 缺 `Name` / `InternalName` / `Version` / `DownloadLinkInstall` | 只跳过这一条，其余照常 |
| `InternalName` 必须是小写点分 ID（段内可用 `-` 与数字，不能有大写/下划线） | 该条被跳过 |
| `Version` 必须是完整 SemVer（`1.0` 不行） | 该条被跳过 |
| 同一 `InternalName` 出现多条（含跨源同名） | 只保留**版本最高**的一条 |
| `Games` / `ApiMajor` | 下载前判断兼容性，缺失则拿不到兼容信息 |

字段名区分大小写，JSON 不支持注释与尾随逗号。索引写错会连累全部插件，所以改完先本地过一遍：

```powershell
./check-index.ps1 -IndexPath .\pluginmaster.json                          # 结构 / 必填字段 / ID / SemVer
./check-index.ps1 -Validate -ToolsDir "D:\path\to\Anomaly-tools"          # 线上：下载每个 ZIP，核对 manifest 并 validate
```

任何一条不通过都会以退出码 1 结束，可以直接放进 CI。

## 构建与测试

需要 Windows x64、Visual Studio 2022（C++20）、CMake ≥ 3.22 和 Anomaly SDK。SDK 不用自己编，
从 [Anomaly Releases](https://github.com/AnomalyNTE/Anomaly/releases) 下载 `Anomaly-<版本>-sdk.zip`，
解压后指向其中的 `lib/cmake/AnomalySDK`。

```powershell
$env:AnomalySDK_DIR = 'C:\AnomalySDK\lib\cmake\AnomalySDK'   # 或每次传 -SdkDir

./build.ps1                                     # 构建 + validate + 离线 fixture（全部插件）
./build.ps1 -Plugin damage-source-recorder      # 只做一个
./build.ps1 -Plugin damage-source-recorder -Deploy -Enable    # 部署到 Runtime 并启用
```

`Anomaly-tools` 与部署目标可用 `-ToolsDir` / `$env:AnomalyToolsDir`、
`-RuntimePlugins` / `$env:AnomalyRuntimePlugins` 覆盖；工具缺失时会跳过校验与离线测试并给出警告。

## 发布新版本

1. 改插件 `manifest.json` 的 `version`；
2. `./release.ps1 -Plugin damage-source-recorder -Publish` —— 构建、`validate`、离线 fixture、`pack`，
   产出 `dist\<id>-<version>.zip`（ZIP 根是 `manifest.json`、`plugin.dll`、`package.sha256`、`locales\`），
   然后创建标签 `<短名>-v<版本>` 的 Release 并上传（已是同内容资源时不覆盖）；
3. 最后改 `pluginmaster.json` 的 `Version` 与 `DownloadLinkInstall` / `DownloadLinkUpdate`；
4. 从公网复核一次：

   ```powershell
   ./check-index.ps1 -Validate -ToolsDir "D:\path\to\Anomaly-tools"
   ```

先发 ZIP、后改索引，用户就不会看到指向空资源的版本。

## 目录结构

```text
.
├── pluginmaster.json              # 插件源索引（Runtime 读取，根节点必须是数组）
├── plugins.json                   # 插件登记表：短名 ↔ 目录 ↔ 包名
├── plugins/
│   └── DamageSourceRecorder/      # 各插件源码（各自独立的 CMake 工程）
├── build.ps1                      # 构建 / 校验 / 离线测试 / 部署
├── release.ps1                    # 生成发布 ZIP，可选 -Publish 建 Release
├── check-index.ps1                # 检查 pluginmaster.json
├── .github/workflows/build.yml    # CI：下载官方 SDK 构建全部插件，并检查索引
├── LICENSE                        # AGPL-3.0-only
└── README.md
```

每个插件的功能与限制写在自己的 `plugins/<名字>/README.md` 里。

## CI

`.github/workflows/build.yml` 在 push、PR 和手动触发时：按运行器上实际安装的 Visual Studio 选择生成器 →
从 Anomaly Releases 下载 SDK 与 `anomaly-tools` → `check-index.ps1` 检查索引 → `build.ps1` 构建并跑
`validate` 与离线 fixture → 上传产物。发布 Release 是人工步骤（`release.ps1 -Publish`），避免 CI 覆盖已发布资源。

## 许可

AGPL-3.0-only，见 [LICENSE](LICENSE)。
