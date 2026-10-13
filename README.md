<div align="center">

![Tactic Echo Forever 项目展示与工作流程](docs/media/tef-overview.png)

**为魔兽世界无限版打造的技能序列、优先级推荐与输入联动工具。**

![版本](https://img.shields.io/badge/版本-1.0.15-64d8cb?style=flat-square)
![客户端](https://img.shields.io/badge/客户端-Forever%20%2F%20Infinite-b9a5ff?style=flat-square)
![桌面端](https://img.shields.io/badge/桌面端-Windows-8ab4f8?style=flat-square)
![进度](https://img.shields.io/badge/进度-持续开发与实机验证-f4bf75?style=flat-square)

[现在能做什么](#现在能做什么) · [项目进度](#项目进度) · [快速上手](#快速上手) · [更新记录](CHANGELOG.md)

</div>

## 把你的施法计划，变成清楚的下一步

**Tactic Echo Forever（TEF）** 让你在游戏内编排技能、查看下一步推荐，再通过独立的 **TEF TEK** 桌面程序联动键盘输入。HUD 展示当前技能、两张后续预览卡与阻断原因；固定序列依据精确施法成功回执推进，让重复次数和步骤有据可查。

项目面向 Forever / Infinite 的经典 60 级式职业、天赋与已学技能模型。游戏插件和桌面工具均包含在本仓库，已从 Tactic Echo 独立开发，可单独安装和构建。

## 现在能做什么

| 能力 | 你可以怎样使用 |
| :--- | :--- |
| **人工技能序列** | 按顺序编排技能，每套最多 **16 步**、每步 **1–99 次**，支持循环、暂停、恢复与重置。每行可选“不可用跳过”。 |
| **自定义 APL** | 按优先级选择满足公开条件的技能，每个场景最多 **16 条规则**；支持拖入、排序和启停。当前支持法师，使用已登记的精确技能 ID。 |
| **条件与场景配置** | 分别保存单体／多目标配置；自定义规则可设置移动、法力百分比、目标距离及冷却管理器活动等条件，未知状态会阻断相关规则。 |
| **可调整的 HUD** | 查看当前技能与两张后续预览卡、键位、公开冷却及阻断原因；调整图标大小、间距与标签样式，并在派发启停时播放提示音。 |
| **距离提示** | 显示目标的估测距离区间；精确技能范围接口公开确认超距时，图标与键位标红。估测区间仅用于显示。 |
| **桌面输入联动** | `TEK-TEF.exe` 读取插件信号，经前台、手动输入、信号新鲜度等检查后发送键盘输入；提供托盘与状态窗口。 |
| **读条末尾排队 · 实验** | 固定序列的普通读条可预留下一次尝试，提前量 **0–0.50 秒**，默认 **0.20 秒**，受客户端排队窗口限制；功能默认关闭。 |

> 默认使用人工序列，自定义 APL 需要主动选择。当前设置页不提供内置职业 APL 模板；自定义 APL 也不代表所有职业已经适配。

### 从配置到回执

**编排序列／规则 → HUD 推荐 → 插件发布请求 → TEF TEK 发送输入 → 游戏施法回执**

固定序列按匹配的成功回执计次，失败或迟到事件不会直接推进。自定义 APL 在成功后重新评估优先级；暂停、临时阻断和主动重置有各自的处理方式，HUD 会说明当前状态。

## 项目进度

**当前版本：1.0.15。核心链路已实现，正在持续修复交互、完善显示并补充实机验收。**

| 阶段 | 当前状态 |
| :--- | :--- |
| **独立项目与桌面构建** | 插件、TEF TEK、构建和打包脚本已独立；桌面程序输出为 `TEK-TEF.exe`。 |
| **序列与自定义 APL** | 编排、条件求值、HUD、请求与精确回执链路已实现，已有离线回归与历史实机记录。各新增路径仍需分别验收。 |
| **最近的界面改进** | 设置页精简、HUD 布局与阻断提示、启停音效、不可用跳过及排队诊断已落地。 |
| **1.0.15 距离显示** | 实机记录显示，同一目标接近时估测区间逐步缩小；超距变色收到初步正向反馈。各物品档位尚未完成精确距离校准。 |
| **继续验证** | 读条末尾排队、不可用跳过、引导中断后的恢复、固定次数魔杖射击交接，以及受限数据场景下的表现。 |

最近一次本地构建（2026-10-13）通过 **229 项 Lua 模拟、235 项 pytest 测试及 17 项子测试**，并完成项目检查和 **39 个 Lua 文件的 Lua 5.1 语法检查**。这些结果说明离线回归通过，桌面输入和客户端行为仍以实机证据为准。

[查看 1.0.15 基线](docs/baselines/tef/BASELINE_1.0.15.md) · [距离显示初步实测](docs/FIELD_REPORT_2026-10-12_TEF_1015_S19.md) · [历史战斗链路实测](<Tactic Echo Forever/docs/FIELD_REPORT_2026-10-11_TEF_0143_S76.md>)

## 快速上手

### 1 · 安装游戏插件

下载本仓库，将 **`Tactic Echo Forever` 文件夹**放入无限版客户端的 `Interface/AddOns/`，保持文件夹与 TOC 的名称一致：

```text
无限版客户端/
└─ Interface/
   └─ AddOns/
      └─ Tactic Echo Forever/
         ├─ Tactic Echo Forever.toc
         ├─ Config.lua
         └─ …
```

在角色选择界面的插件列表启用 **Tactic Echo Forever**。当前目标客户端为 **1.60.1 / Interface 16001**。替换旧安装时，请将旧目录移出 AddOns，并且只启用一个 TE／TEF 信号源。

### 2 · 在游戏里配置

输入 **`/tefui`** 打开设置：

1. 先选人工序列，添加技能并设置次数；需要条件优先级时再选择自定义 APL。
2. 核对技能的实际动作栏键位，保存配置，按需要调整 HUD。
3. 在派发总览和 TEK 页检查启停模式、请求许可及控制快捷键，再进行一次受控尝试。

配置编辑会停止旧派发，关闭设置后需重新开启。旧名称插件的设置不会随文件夹重命名自动迁移。

### 3 · 构建桌面 TEK

**仓库提供源码，可执行文件需要本地构建。** 在 Windows 上准备 **64 位 Python 3.11 或更新版本**与 **PowerShell 7**，在项目目录安装依赖：

```powershell
python -m pip install -r requirements-dev.txt
```

然后双击根目录的 `TEKEXEBUILD.CMD`，它会运行项目检查并构建。成功后运行：

```text
dist/standalone-build/TEK-TEF.exe
```

TEF TEK 是独立桌面程序，放在工具目录运行即可。打开游戏并确认它位于前台，再结合 TEK 状态窗口与游戏 HUD 检查联动；首次使用建议从单步验证开始。

<details>
<summary><strong>使用前了解这几项边界</strong></summary>

- 未知或受限值不等于条件满足；相关信息无法公开确认时，会等待或阻断。
- “不可用跳过”默认关闭，未知状态、目标／距离阻断与等待回执不能据此跳过。
- 末尾排队只支持固定序列普通读条及重复次数，不提前预测自定义 APL、引导、魔杖射击或循环边界。
- HUD 的物品距离区间只是估测，不参与 APL 或派发判断；技能超距标红使用独立的精确范围接口。
- 插件发布请求、桌面发送输入和游戏确认施法是不同环节，需要分别确认。
- 插件使用 `TEF_DB` 保存数据；TEK 的设置、日志和缓存位于 `%LOCALAPPDATA%/TacticEchoForever`。桌面端首次迁移只复制旧配置并保留备份，启用状态和信号布局需要重新确认。

</details>

## 深入了解

| 想了解什么 | 从这里开始 |
| :--- | :--- |
| 版本变化与修复 | [更新记录](CHANGELOG.md) |
| 当前行为与验证范围 | [1.0.15 基线](docs/baselines/tef/BASELINE_1.0.15.md) |
| 更多使用说明与历史证据 | [文档目录](docs/README.md) |
| 桌面工具 | [TEF TEK 说明](tek/README.md) |
| 项目来源与独立开发 | [项目拆分说明](docs/PROJECT_SPLIT.md) |
| APL 底层约定 | [APL 契约](<Tactic Echo Forever/docs/APL_FOUNDATION_FIX_1.0.1.md>) |

<details>
<summary><strong>开发者：本地检查、构建与打包</strong></summary>

安装 `requirements-dev.txt` 后，在项目根目录执行：

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python "Tactic Echo Forever/tests/run.py"
python -m pytest -q tek/tests tests
python -m unittest discover -s tek/tests -q
python -m unittest discover -s "Tactic Echo Forever/tests" -q
python -m compileall -q tek/src tek/app tek/runtime
```

Lua 模拟使用 `lupa.lua51`；交付前还需完成 Lua 5.1 语法检查。Windows 构建入口：

```powershell
pwsh.exe -NoLogo -NoProfile -File scripts/build-tek-exe.ps1 -OutputDirectory dist/standalone-build -SkipSmokeTest
```

输出为 `TEK-TEF.exe`，构建成功不代表真实输入验收通过。桌面输入验收入口为 `scripts/verify-tek-sendinput.ps1`，需要按提示进行人工观察。

插件源码打包：`python "Tactic Echo Forever/scripts/deliver.py"`。完整源码与 Windows 发行包分别打包，参数见 `python scripts/package-tef-release.py --help`。

项目从 Tactic Echo 的源提交 `3e57b9d1713ad3c9d821b416dc073452289c2691`（2026-10-12）独立发展；TEF TEK 不自动同步正式服 TE TEK。TEAP 命名空间为 `TEF`，使用现有 v3 线格式，一次只能启用一个插件信号源。

</details>
