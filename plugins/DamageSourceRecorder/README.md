# 伤害来源记录（Damage Source Recorder）

面向 Anomaly 2.4.3 / NTE 的独立插件。它把角色战斗伤害逐条记下来——**伤害类型、来源效果、数值与标志**——
并把连续命中合并成「一段伤害」，可以选中某段并把**记录到的那一个伤害效果重新施加到记录的目标上**。

- 插件 ID：`com.yu.damage-source-recorder`
- 包目录：`DamageSourceRecorder`（`plugin.dll` + `manifest.json`）
- 依赖服务：`anomaly.ui`（必需）；`anomaly.nte.combat`、`anomaly.nte.skills`、
  `anomaly.nte.skill-invocation`、`anomaly.ue5.objects`、`anomaly.ue5.names`、
  `anomaly.interop.signature`、`anomaly.core`（可选，缺失时界面照常打开并给出原因）
- 声明 capability：`ui`、`nte-combat-read`、`nte-skills-read`、`nte-skill-invocation`、
  `ue5-objects`、`ue5-names`、`interop-signature`、`memory-read`

这是**第三方插件**：它不在 Anomaly 主仓库里，通过独立的插件源分发，自行构建、自行发布。

## 安装

需要 Anomaly **2.4.3** 或更新的 Runtime（Plugin API 1），目标游戏为 `nte`。

**方式一：添加插件源（推荐，能收到更新）**

1. `Insert` 打开管理界面 → **Plugins > 第三方插件** → 添加插件源：

   ```text
   https://raw.githubusercontent.com/YU-1021/Anomaly-Plugin-DamageSourceRecorder/main/pluginmaster.json
   ```

2. 回到 **Plugins > 可用** 刷新，找到「伤害来源记录」点 **安装**。
3. 在 **Plugins > 已安装** 中启用。之后有新版本会出现在 **Plugins > 更新**。

**方式二：手动安装**

1. 从 [Releases](https://github.com/YU-1021/Anomaly-Plugin-DamageSourceRecorder/releases) 下载
   `com.yu.damage-source-recorder-<版本>.zip`。
2. 解压到 `Anomaly\plugins\DamageSourceRecorder\`，确认 `manifest.json` 直接位于这一层。
3. 重启 Runtime（或在插件界面重载），再在插件列表里启用。

ZIP 内是 `plugin.dll`、`manifest.json`、`package.sha256` 和 `locales\`。第三方插件是在游戏进程里
运行的原生 DLL，只安装你信任的来源。

## 功能

1. **记录伤害类型**
   读取 `anomaly.nte.combat` 的伤害事件流（`AHTAbilityCharacter::CharacterOnDamaged`，由
   `FHTDamageTextInfo` 补全），每条命中记录：

   | 字段 | 说明 |
   | --- | --- |
   | 伤害类型 | `HTGame.EExecutionDamageTypeEX`（普通/宇宙/自然/咒术/混沌/心灵/业相/精神/真实/Fons/龙焰/圣焰/暗焰/黑鸟） |
   | 显示类型 | `EDamageDisPlayType`（免疫、抵抗、弱点、秒杀、格挡……） |
   | 反应类型 | `EReactionResultType` / `EReactionDisplayType` |
   | 数值 | 客户端展示值、基础值、最终值（`FHTDamageEvent::Damage` 取整） |
   | 标志 | 暴击、头部命中、失衡（带 `CRITICAL_VALID` 时才把“未暴击”当确认结果） |
   | 来源 | `source_id` → `source_name_utf8`：技能显示名或 `GameplayEffect` 对象路径 |
   | 目标 | 受击角色的显示名称/对象路径 |

2. **合并成“一段伤害”**
   同一伤害来源、相邻两次命中间隔不超过「记录间隔」（0.3–3.0 秒，默认 1.0 秒）的命中归入同一段。
   每段显示：技能/来源、主伤害类型、命中次数、总伤害、起始时间，展开后是逐次命中明细。
   重放按钮下方还有一行按伤害类型的累计（例如「类型总计：宇宙 12 · 真实 3」），清空记录时一并清零。

3. **重放那一段伤害（直接施加记录的伤害效果）**
   选中片段后点击「重放已选的伤害」——**点一次施加一次**，没有次数/间隔设置，也不受技能冷却限制。

   重放不再“再放一次技能”，而是把记录到的那个 **GameplayEffect 重新施加到记录到的目标**上，
   与 b1anktool 自动攻击走同一条路径（`K2_ApplyGameplayEffectToTargetWithClass`）：

   - 记录时保存 `source_id` 对应的 GameplayEffect 对象路径，以及受击目标的 generation handle；
   - 重放时用 `anomaly.interop.signature` 解析 GObjects，用 `anomaly.ue5.objects` 把句柄换成
     UObject 地址，再经对象 vtable 的 `ProcessEvent` 槽位调用伤害结算函数；
   - 每一层都先校验再调用：对象表签名、函数参数个数/大小、每个参数的属性名+偏移+大小、
     `HTAbilitySystemComponent` 偏移、`ProcessEvent` 槽位里的指令字节；任何一项对不上就拒绝调用，
     并在界面上说明原因。

   因为施加的是同一个效果、同一个目标，数值会由游戏按同一套公式重新结算——与原来接近，但暴击、
   浮动与目标身上的临时状态仍可能让数字不同；**插件不会把记录的数字直接写进目标**。

   如果某段的来源不是可解析的 GameplayEffect（例如只有名字没有对象路径），或者记录的目标都已消失，
   会自动退回「按技能重放」并在状态栏说明，避免什么都不做。

   技能信息（技能名 / 路径 / 关联依据）仍然记录并显示，但它只用于说明“这段伤害是谁打出来的”和退化重放；
   界面会如实标注关联依据（`伤害来源` / `来源名推断` / `唯一激活` / `最近激活`）。

   每次重放后打开约 1 秒的观测窗口，统计新打出的命中与伤害，结果显示为
   「已对 N 个目标重新施加 … · 观测到 X 次命中、伤害 Y」。

4. **角色受到的伤害也能重放**
   打开「包含受到的伤害」后，怪物打在角色身上的伤害也会被记录成段（列表里带「受击 ·」前缀，
   详情显示「方向：角色受到」）。重放这类片段时，插件用**记录到的攻击者**当施加方、**角色自己**当目标，
   把那个怪物的伤害效果重新施加回来——也就是“再挨一下同样的伤害”，会真的掉血。
   如果记录时攻击你的那只怪已经不在了，这一段无法复现（不会用别的角色/技能顶替）。

## 使用

1. 在 Anomaly 插件列表启用「伤害来源记录」。
2. 进入世界后窗口自动出现（由 Anomaly 窗口层管理，不会误关后找不回来）。顶部一行显示：
   战斗 / 技能 / 施伤 / 角色快照是否可用、记录开关、片段与命中计数。
3. 打一套连招，下方「伤害记录」里会出现若干段（最新在最上面）。点某段的「选择」，上方「选中片段」
   就会显示它的技能、来源效果、目标数、类型分布与逐次命中。
4. 点「重放已选的伤害」，点一次施加一次；连点就是连续施加，不需要等冷却。

窗口从上到下的顺序是：**开关 → 重放按钮 → 选中片段详情 → 伤害记录列表**。记录再多也是列表自己在
底部增长/滚动，不会把重放按钮和当前片段的详情顶出去。

开关说明：

- **记录伤害**：总开关；关闭时仍会推进事件游标，重新打开不会灌入旧事件。
- **包含受到的伤害**：默认只记角色打出去的伤害；打开后也记录角色承受的伤害，这类片段才能重放。
- **含召唤物伤害**：默认只认攻击者是本地角色的命中。召唤物、联动效果等攻击者不是本地角色的伤害
  需要打开此项才会记录。
- **记录间隔**：越小分段越细（每次命中一段），越大越容易把一套连招合成一段。

## 重放机制与风险

| 路径 | 行为 | 何时使用 |
| --- | --- | --- |
| 直接施加伤害效果 | 把记录的 GameplayEffect 施加到记录的目标，数值由游戏重新结算 | 默认；来源是可解析的 GE 对象路径且目标还在 |
| 按技能重放 | 经 `anomaly.nte.skill-invocation` 重新激活技能 | 兜底；直接施加不可用时，状态栏会说明原因 |

直接施加需要 `memory-read` / `ue5-objects` / `ue5-names` / `interop-signature` 能力，以及一份与当前
游戏 build 匹配的反射布局（`HTAbilitySystemComponent` 偏移、伤害结算函数的参数布局）。这些布局来自
Anomaly Runtime Profile 与 2026-10-23 游戏 build 的 dump，与 b1anktool 校验过的是同一份。
布局一旦变化，插件只会拒绝调用并显示原因，不会带着错误偏移去调用游戏函数。

这也是第三方插件的灰色地带：它直接调用游戏函数。风险由使用者承担，与 b1anktool 等插件相同。

## 构建

需要 Windows x64、Visual Studio 2022（C++20）、CMake ≥ 3.22，以及 Anomaly SDK。

SDK 不必从源码构建，直接从 [Anomaly Releases](https://github.com/AnomalyNTE/Anomaly/releases) 下载
`Anomaly-<版本>-sdk.zip`（例如 `Anomaly-2.4.3-sdk.zip`），解压后把 `AnomalySDK_DIR` 指向
`<解压目录>/lib/cmake/AnomalySDK`：

```powershell
$env:AnomalySDK_DIR = 'C:\AnomalySDK\lib\cmake\AnomalySDK'
cmake --preset default
cmake --build build --config RelWithDebInfo
```

产物：`build/package/DamageSourceRecorder/`（`plugin.dll`、`manifest.json`；MSVC 还会生成 `.pdb`、
`.lib`、`.exp`，运行时只需要前两个）。

`build.ps1` 把上面两步和「校验 + 离线加载测试 + 复制到 Runtime」串起来：

```powershell
./build.ps1                                  # 构建 + 校验 + 测试
./build.ps1 -Deploy                          # 再复制到默认 Runtime 插件目录
./build.ps1 -Deploy -RuntimePlugins "D:\path\to\Anomaly\plugins"
./build.ps1 -SdkDir "C:\AnomalySDK\lib\cmake\AnomalySDK"   # 显式指定 SDK（也可用 $env:AnomalySDK_DIR）
```

`Anomaly-tools` 与部署目标同样可以用参数或环境变量覆盖：`-ToolsDir` / `$env:AnomalyToolsDir`、
`-RuntimePlugins` / `$env:AnomalyRuntimePlugins`。找不到 `anomaly-plugin` / `anomaly-test-host`
时会跳过校验与离线测试并给出警告。

## 验证

```powershell
# Manifest / 入口 / 依赖校验
Anomaly-tools\anomaly-plugin.exe validate build\package\DamageSourceRecorder

# 无游戏离线 fixture：加载、tick、绘制、热重载、资源回收
Anomaly-tools\anomaly-test-host.exe --plugin build\package\DamageSourceRecorder --reload 10 --ticks 60
```

离线 fixture 没有游戏适配器，NTE 服务保持不可用；此时插件应正常加载并显示“战斗服务不可用”，
不应崩溃或卡住。真实战斗与重放需要在游戏内验证。

## 发布新版本

1. 改 `manifest.json` 的 `version`（`pluginmaster.json` 也同步）。
2. `./release.ps1` —— 构建、`validate`、离线 fixture、`pack`，并在 `dist\` 下生成
   `com.yu.damage-source-recorder-<版本>.zip`（ZIP 根直接是 `manifest.json`、`plugin.dll`、
   `package.sha256`、`locales\`），最后打印 SHA256。
3. 把 ZIP 传到不可变的版本地址：`gh release create v<版本> dist\<zip>`（或推 `v<版本>` 标签，
   `.github/workflows/release.yml` 会自己构建并上传资源）。
4. 最后改 `pluginmaster.json` 的 `Version`、`DownloadLinkInstall` / `DownloadLinkUpdate`。
5. 从公网重新拉一遍，确认索引能解析、下载的确实是 ZIP：

   ```powershell
   $index = 'https://raw.githubusercontent.com/YU-1021/Anomaly-Plugin-DamageSourceRecorder/main/pluginmaster.json'
   $entry = @(Invoke-RestMethod $index) | Where-Object InternalName -eq 'com.yu.damage-source-recorder'
   $entry.Version
   Invoke-WebRequest $entry.DownloadLinkInstall -OutFile .\dist\online.zip
   ```

先发 ZIP、后改索引，用户就不会看到指向空资源的版本。

## 在这个源里放更多插件

`pluginmaster.json` 就是「YU-1021 的插件源」本身，根是**数组**，一个插件一个对象。以后再加插件，
只在同一个数组里追加对象、保持这个 URL 不变，用户不用重新加源，「可用」和「更新」会自动显示新条目。

给新插件增加一条的步骤：

1. 新插件有自己的仓库和 Release，包里 `manifest.json` 必须在 ZIP 根目录；
2. 在 `pluginmaster.json` 里追加一个对象：`InternalName` 与包内 `manifest.id` **完全相同**，
   `Version` 与 `manifest.version` 完全相同，`DownloadLinkInstall` 指向该版本的 Release ZIP；
3. 跑一遍本仓库的检查脚本；
4. 提交并推送，然后回 **Plugins > 可用** 刷新。

```jsonc
[
  { /* 伤害来源记录（现有条目） */ },
  {
    "Name": "另一个插件",
    "InternalName": "com.yu.another-plugin",
    "Version": "0.1.0",
    "Author": "YU-1021",
    "Punchline": "一句话说明用途。",
    "Games": ["nte"],
    "ApiMajor": 1,
    "RepoUrl": "https://github.com/YU-1021/another-plugin",
    "DownloadLinkInstall": "https://github.com/YU-1021/another-plugin/releases/download/v0.1.0/com.yu.another-plugin-0.1.0.zip"
  }
]
```

Runtime 的解析规则（`src/repository/plugin_list.cpp`、`BuildCatalog`）决定了这几条硬约束：

| 规则 | 后果 |
| --- | --- |
| 根必须是 JSON 数组 | 写成对象或 JSON 语法错误 → **整个源刷新失败**，该源下所有插件一起消失 |
| 缺少 `Name` / `InternalName` / `Version` / `DownloadLinkInstall` | 只跳过这一条，其余照常 |
| `InternalName` 必须是小写点分 ID（段可用 `-` 与数字，不含大写/下划线） | 该条被跳过 |
| `Version` 必须是 SemVer（`1.0.0`，`1.0` 不行） | 该条被跳过 |
| 同一个 `InternalName` 出现多条（含跨源同名插件） | 只保留**版本最高**的一条，其余忽略 |
| `Games` / `ApiMajor` | 下载前判断兼容性；缺失时界面拿不到兼容信息 |

字段名区分大小写，JSON 不支持注释和尾随逗号。索引里缺一个逗号，所有插件都会从「可用」里消失——
所以改完先本地过一遍，别直接推：

```powershell
./check-index.ps1 -IndexPath .\pluginmaster.json                          # 本地：结构 / 必填字段 / ID / SemVer
./check-index.ps1 -Validate -ToolsDir "D:\path\to\Anomaly-tools"          # 线上：再下载每个 ZIP，核对 manifest 并 validate
```

脚本按上面那张表的规则检查，一条不通过就以退出码 1 结束，可直接放进 CI。

## 部署（热重载）

把 `build/package/DamageSourceRecorder/` 里的 `plugin.dll` 与 `manifest.json` 复制到
`Anomaly\plugins\DamageSourceRecorder\`。Runtime 的插件监控会校验新代际、停止旧 Scope 并只重载该包。
首次安装还需要在 `config/plugin-enablement.json` 里把插件打开：

```json
{
  "defaultEnabled": false,
  "plugins": {
    "com.yu.damage-source-recorder": true
  },
  "schemaVersion": 1
}
```

（或者直接在 Anomaly 管理界面的插件列表里勾选启用。）

## 目录结构

```text
.
├── CMakeLists.txt              # 消费 AnomalySDK，调用 anomaly_add_plugin
├── CMakePresets.json           # MSVC x64 RelWithDebInfo 预设（AnomalySDK_DIR 取自环境变量）
├── build.ps1                   # 构建 / 校验 / 测试 / 部署
├── release.ps1                 # 构建 + 校验 + pack + 生成发布 ZIP
├── check-index.ps1             # 检查 pluginmaster.json（结构 / 字段 / ID / SemVer / 下载地址 / 包内容）
├── manifest.json               # 插件清单（schemaVersion 2）
├── pluginmaster.json           # 在线插件源索引（第三方插件页读取，根节点是数组）
├── locales/zh-CN.json          # 插件列表用的名称与简介
├── src/plugin.cpp              # 记录、分段、技能信息、重放调度与 UI
├── src/damage_apply.hpp        # 直接施加伤害效果：对象表解析、句柄→地址、反射校验、ProcessEvent 调用
├── .github/workflows/release.yml   # 标签触发的构建与资源上传
└── README.md
```

## 已知限制

- **数值不会逐位相同**：施加的是同一个伤害效果、同一个目标，但伤害仍由游戏重新结算，
  暴击、浮动与目标当前状态都会影响结果；插件也不会把记录的数字直接写进目标。
- **强度参数**：重放按「效果等级 1、倍率 1、附加 0」施加，记录里没有原始命中时的强度/加成，
  所以带加成的一击重放后可能偏低。
- **目标**：对记录中的受击目标（最多 8 个）施加；出伤片段的目标都消失时退到当前攻击目标，
  受伤片段退到当前角色。已死亡的目标会被跳过（通过 `GetHP` 反射读取，读不到时不跳过）。
- **受伤重放的施加方**：必须用记录时的那只攻击者，它消失后这一段就重放不了；换角色也会让出伤片段
  的攻击力变化。
- **换角色**：直接施加用的是当前角色的能力系统，换角色后攻击力不同，数值会跟着变。
- **退化重放**：来源不是可解析的 GameplayEffect 时退回技能激活，那一档可能被技能冷却/动作拒绝
  （界面显示「游戏接受=否」，可再点一次），并且重放的是技能而不是同一段伤害。
- **分段是启发式**：同一 `source_id` 的连续命中视为一段。持续伤害（DoT）会按记录间隔切成多段；
  多目标同一次技能命中会归入同一段。
- **缓存上限**：32 段（每段最多 64 条命中明细，超出后保留最新的，累计计数仍然准确）。
- **伤害类型名称**取自 `EExecutionDamageTypeEX` 枚举；游戏内文本表中的官方译名若不同，以枚举语义为准。

## 许可

AGPL-3.0-only，见 [LICENSE](LICENSE)，与 Anomaly 生态保持一致。
