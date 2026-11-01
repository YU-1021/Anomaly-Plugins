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

这是 **Yu の Anomaly 插件源** 里的一个第三方插件：不在 Anomaly 主仓库里，通过本仓库的

```text
https://raw.githubusercontent.com/YU-1021/Anomaly-Plugins/main/pluginmaster.json
```

分发。安装与添加插件源的完整步骤见[仓库 README](../../README.md#安装)。

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

## 构建与验证

构建脚本在仓库根目录，按 `plugins.json` 找到本插件：

```powershell
$env:AnomalySDK_DIR = 'C:\AnomalySDK\lib\cmake\AnomalySDK'   # Anomaly-<版本>-sdk.zip 解压后的 lib/cmake/AnomalySDK
./build.ps1 -Plugin damage-source-recorder            # 构建 + anomaly-plugin validate + 离线 fixture
./build.ps1 -Plugin damage-source-recorder -Deploy    # 再复制到 Runtime 插件目录（-Enable 顺带启用）
./release.ps1 -Plugin damage-source-recorder          # 生成 dist\com.yu.damage-source-recorder-<版本>.zip
```

也可以只用这套 CMake 工程（`CMakeLists.txt` + `CMakePresets.json`）单独构建：

```powershell
cmake --preset default
cmake --build build --config RelWithDebInfo
```

产物是 `build/package/DamageSourceRecorder/`（`plugin.dll`、`manifest.json`，外加 MSVC 的 `.pdb`/`.lib`/`.exp`）。

离线 fixture 没有游戏适配器，NTE 服务保持不可用；此时插件应正常加载并显示“战斗服务不可用”，
不应崩溃或卡住。真实战斗与重放需要在游戏内验证。

## 部署（热重载）

`./build.ps1 -Plugin damage-source-recorder -Deploy` 会把 `plugin.dll`、`manifest.json` 与 `locales/`
复制到 `Anomaly\plugins\DamageSourceRecorder\`。Runtime 的插件监控会校验新代际、停止旧 Scope 并只重载该包。
首次安装还需要把插件打开（或用 `-Enable`）：

```json
{
  "defaultEnabled": false,
  "plugins": {
    "com.yu.damage-source-recorder": true
  },
  "schemaVersion": 1
}
```

## 目录结构

```text
plugins/DamageSourceRecorder/
├── CMakeLists.txt        # 消费 AnomalySDK，调用 anomaly_add_plugin
├── CMakePresets.json     # MSVC x64 RelWithDebInfo 预设（AnomalySDK_DIR 取自环境变量）
├── manifest.json         # 插件清单（schemaVersion 2）
├── locales/zh-CN.json    # 插件列表用的名称与简介
├── src/plugin.cpp        # 记录、分段、技能信息、重放调度与 UI
├── src/damage_apply.hpp  # 直接施加伤害效果：对象表解析、句柄→地址、反射校验、ProcessEvent 调用
└── README.md
```

发布、索引与插件源规则见仓库根 [README](../../README.md)。

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

AGPL-3.0-only，见 [LICENSE](../../LICENSE)，与 Anomaly 生态保持一致。
