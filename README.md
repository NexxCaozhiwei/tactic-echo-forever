# Tactic Echo Forever

面向魔兽世界 Forever / Infinite 的独立项目，采用经典60级式职业、天赋和已学技能模型，包含 APL、Secret Value、TEAP 与 TEF TEK。

项目源自 Tactic Echo，自2026-10-12、源提交 `3e57b9d1713ad3c9d821b416dc073452289c2691` 起独立开发。不是 Tactic Echo 的子模块，不需要相邻仓库。当前版本为 **1.0.13**。

- 插件目录：`Tactic Echo Forever/`；SavedVariables：`TEF_DB`。
- TEF TEK目录：`tek/`；配置、日志和缓存根目录：`%LOCALAPPDATA%/TacticEchoForever`。
- 首次启动迁移只复制旧设置和配置，不修改或删除旧数据。原设置会在本地备份；启用状态和信号布局提示会重置，需在新项目明确确认。
- TEAP命名空间为 **TEF**；现有v3线格式不变，无法在线上区分项目。一次只能启用一个插件信号源。
- TEF TEK独立于正式服TE TEK演进，不自动同步。

## 本地检查

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python "Tactic Echo Forever/tests/run.py"
python -m pytest -q tek/tests tests
python -m unittest discover -s tek/tests -q
python -m unittest discover -s "Tactic Echo Forever/tests" -q
python -m compileall -q tek/src tek/app tek/runtime
```

Lua模拟需要 `lupa`（Lua 5.1）。Windows构建依赖见 `requirements-windows.txt`。构建TEF TEK：
`pwsh -File scripts/build-tek-exe.ps1 -OutputDirectory dist/standalone-build -SkipSmokeTest`。
输出为 `TEK-TEF.exe`；构建成功不代表真实输入验收通过。
插件源码打包使用 `python "Tactic Echo Forever/scripts/deliver.py"`。完整源码与Windows发行包分别打包，参数见 `scripts/package-tef-release.py --help`。

[项目拆分说明](docs/PROJECT_SPLIT.md) · [当前APL契约](<Tactic Echo Forever/docs/APL_FOUNDATION_FIX_1.0.1.md>)

插件目录和TOC均名为 `Tactic Echo Forever`。替换旧安装时只启用一个TEF插件。游戏按新插件文件名保存TEF_DB；本次重命名不会迁移旧名称数据。

## 推荐与设置

设置仅提供人工序列和自定义APL。循环/重置位于派发总览，标签样式位于HUD外观；两页均可滚动。旧代码模式使用已保存人工行；迁移停用内置APL，自定义规则保留。

人工序列每行可开启“不可用跳过”，默认关闭，编辑后需保存。仅按公开不可用证据跳过剩余次数；UNKNOWN或已派发待回执时不跳过。高级文本示例：`205:205*3!skip`。自身冷却必须能公开区别于GCD，否则等待。

在TEK设置页开启“读条末尾提前排队（实验）”，关闭设置后再启动派发。默认关闭，仅支持固定序列普通读条及重复次数，不预测APL、引导、魔杖射击或循环边界；时间未知时阻断。
提前时间滑块范围0–0.5秒、步进0.05秒、默认0.20秒；0不提前。实际窗口取配置值与公开客户端SpellQueueWindow的较小值。修改会停止派发，关闭设置后需重新开启；游戏接受排队的行为需实测。

排队诊断独立保存在 `TEF_DB.queueDiagnostics`（最多512条），淘汰数为 `queueEvicted`。保存公开时间、GUID、事件与请求/回执关联。`TOKEN_PUBLISHED`只证明插件发布，不证明桌面输入；`remaining`是发起排队时的快照。记录不改变派发逻辑。
