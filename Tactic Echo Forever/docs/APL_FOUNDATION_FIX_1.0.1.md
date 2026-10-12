# TEF 1.0.1 当前 APL 基础契约

本轮修复独立 TEF。TE 仍为 1.5.12；TEK、TEAP v3、固定序列与输入授权保持原契约。默认推荐来源仍是固定序列，APL 由用户显式选择。本文件是当前事实；旧文档正文是历史记录。

## 冷却策略

Ability 默认 `readinessPolicy="usable_only"`。内置普通动作要求公开 known、usable、power_ok、in_range；不请求冷却数值。规则显式 `requireReady=true`、自身 `action.ready` 条件或 Ability `public_cooldown_required` 时才读取 ready。只有公开合法 isEnabled=true、startTime=duration=0 才通过；Secret/缺失仍 UNKNOWN。不查询 61304，不声称独立自身 CD，也不以 isActive、时钟或视觉对象代替 ready。

自定义 APL 既有 requireReady 默认 false 保持。通用动作与移动条件复用 Conditions:ActionTerms / All，敌人数边界复用 Conditions:One；自定义 mana/distance/CDM 仍沿用已授权 PublicConditions，不把这些条件加入内置 WotLK 规则。

## RankResolver

输入仅限公开法术书身份及逐个 IsSpellKnown 确认的 exact ID。显式 exactID 是用户覆盖，必须独立校验已学且名称属于同一语义能力；无效覆盖阻断，不静默回退。未覆盖时依次选唯一实时校核的直接动作条等级、唯一已学 ID、全部候选均有公开同能力 rank 且不重复时的最高 rank。多个直接绑定等级维持 AMBIGUOUS，即使有 rank 元数据也不猜用户选择。

公开 rank 来自同一法术书条目的 numeric rank，或同一 slot 的 GetSpellBookItemName 已校核名称及严格 `Rank N` / `等级 N` 文本；缺失、其他本地化、重复或未知 rank 不按顺序猜。最高 SpellID 和静态目录 rank/learnLevel 永不授权。返回 selected spellID、status、reason、candidates；不存在新宏解析路径。实时派发仍需原 Dispatch 的当前来源及 BindingToken 复核。

## 职业配置与迁移

Identity 仅 UnitClass → CLASS:base，不调用 GetSpecialization / GetSpecializationInfo。已有 base 优先；base 不存在且仅一个有数据的旧 CLASS:数字配置时，复制两场景及来源，保留旧配置。多个有数据旧配置时保留全部、创建空 base、记录冲突并在推荐配置页提示人工编辑保存；不会覆盖或猜当前专精。冲突标志 reload 保留，用户保存后清除。未知职业保持 UNKNOWN，不回退法师。

## 来源策略与BuildSelector

默认 template=auto；旧有效手选 arcane/fire/frost/custom 保留；无效/缺失模板归 auto，不依 filler 推断。自动选择只观察当前实际关键天赋 rank/known：奥术 arcane_power / presence_of_mind，火焰 pyroblast / combustion，冰霜 cold_snap / ice_barrier / fingers_of_frost。全部关键项公开、只有一组有正 rank 才可自动选择；多个合理策略为 AMBIGUOUS，缺项为 UNKNOWN。已采样关键技能若 known 不明确也阻断自动确认。BuildSignature 点数仅诊断。用户可手选策略覆盖；规则仍逐条校核自己的天赋条件。

UI 分类称 APL 策略模板，显示选择依据；未解析提示手选。此 selector 不宣称覆盖无限服全部混合构筑或提供最优 DPS。

## 候选生命周期

候选变化调用 Runtime:ReplaceRecommendation → 原 Engine:ReplaceRecommendation，复用原身份退休、请求撤销和代次隔离；保持 Runtime.intent，index=1，不记用户 RESET，不改保存的固定序列。运行标志只由 Engine/Runtime 管理。已经 SENT/START 且关联当前身份，或施法/引导存在/未知时，替换被拒绝，直至原成功/失败收据与公开读条恢复。精确成功仍只确认当前 ID，失败仍沿原重试路径；不新增 Dispatch 状态机。

## 刷新

沿现有 Runtime heartbeat，dirty 后距离上次采样最少 0.05 秒合并，无事件 0.20 秒 fallback；收据/代次变化立即重新取证。动态读取只限现有 12 个 RuleActions 或最多16个自定义规则；法术书/天赋静态缓存仅相应生命周期事件失效。新鲜度和事件 revision 栅栏保持，合并期间旧请求不能借过期 revision 派发。没有新的 OnUpdate、计时器或全动作条轮询。

ACTION_USABLE_CHANGED 未加入注册：当前没有该事件在 70338 的实机有效证据，usable/range 用现有有界 fallback 更新。

## WotLK 与 Condition Capability Matrix

完整84条源规则、原顺序/条件/开关保留：10 KEEP、4 ADAPT、33 BLOCKED、37 DROP。14/84（约16.7%）是允许评估的分类子集，包含列表调用，并非14个全部可执行动作。窗口/天赋/开关/实际技能条件仍可能进一步阻断。UI 明确“完整源规则已导入；当前只执行已闭合子集”。

| 条件 | 当前能力 |
| --- | --- |
| known / usable / power_ok / range | 公开 exact ID 与布尔，UNKNOWN 不授权 |
| ready | 显式可选，仅公开0/0 |
| moving | 公开布尔 |
| enemy_count | 仅可见实验计数及手动多目标，不代表命中数量 |
| talent known / rank | 当前已校核 Provider 的实际 rank |
| buff/debuff/stack、精确 cooldown.remains | 内置 BLOCKED |
| mana.pct、目标生命、TTD、in_flight、prev_gcd、glyph、pet | 内置 BLOCKED；不新增支持 |

Abilities 的 capability/readinessPolicy/ruleStatus 为显式诊断声明，Registry 存在不等于资格。PARTIAL 只表明有闭合子集规则引用，UNVERIFIED 不因目录存在而授权。

## 验证与实机边界

Lua5.1 模拟、TOC、版本一致性、84条源规则及五份引用 SHA256 校验；新增27项基础回归。验证结果：`python tests/run.py` 为196项固定/生命周期 + 130项APL，共327项，包含27项新增基础回归；TEK互操作6项dry-run、3项包编码及既有手动交接模拟通过。仓库pytest为614 passed、182 skipped、17 subtests passed；TEK unittest 234项通过，AddOn unittest 244项（4项跳过）通过；TEF验收脚本2项mock通过；91个Lua文件通过Lua5.1语法检查。baseline contract及compileall通过。系统无luac/texluac，语法检查使用lupa.lua51。源码 ZIP 包括新模块、全部 TEF 源码、测试、脚本、文档和基线，只有一个项目根；未部署游戏目录，未构建或替换活动 TEK。

待实机验收：70338 公开等级元数据与天赋覆盖、Secret冷却下普通填充、混合天赋手选、配置冲突提示、SENT/成功/失败候选锁定、实际刷新响应、真实 BindingToken → TEK 输入和游戏收据。离线测试不代替这些证据，历史 S76 不证明本版成功。

## 修改文件

- APL：Engine、State、Conditions、Custom、Registry、Trace、Mage60；新增 RankResolver 与 Mage/BuildSelector。
- 生命周期/配置/UI：Sequence、Runtime、Profiles、UI；TEF VERSION、Config、TOC、Bootstrap 同步1.0.1。
- 测试：run.py、run.lua、apl.lua、custom_apl.lua；新增 foundation.lua。
- 交付：scripts/deliver.py 同步加载模块、打包新增测试；移除打包器硬编码历史验证数量，指向本报告，避免将打包当作验证。
- 文档：独立/根CHANGELOG、README、三个旧APL文档当前契约导引、本报告及 docs/baselines/tef/BASELINE_1.0.1.md。
