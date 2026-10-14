# TEF 1.1.11 基线

日期：2026-10-14。

复用现有Runtime／Transport心跳，每0.20秒探测一次相关职业的资源，即使运行意图关闭也可观察；派发信号关闭后心跳停止，不新增定时器、事件钩子或输入路径。战士读取公开Enum.PowerType.Rage，盗贼读取Energy及ComboPoints，分别调用UnitPower及UnitPowerMax。盗贼公开确认目标存在时，对照GetComboPoints(player,target)。

数值与原因独立经Safety规范化后保存，Secret值不比较、不格式化、不持久化。缺失或未知不是0，不作为策略或派发条件。日志TEF_DB.resourceDiagnostics最多256条，仅值、原因、战斗或目标状态变化时写入；resourceEvicted记录淘汰数，resourceProbeSummary保存本会话采样次数和最新快照。重载历史记录再次按白名单清洗，不恢复活动状态。

## 实测步骤

执行/reload，保留派发信号开启；可以关闭派发意图，手动完成测试。战士脱战观察初始怒气，进战获得／消耗怒气，再脱战。盗贼脱战观察能量，进战消耗并恢复能量，用生成连击点与终结技能测试，切换目标及清除目标作为对照。每个阶段都可/reload或正常退出使数据落盘，勿将技能成功等同于资源数值公开。

核对resources.rage／energy／comboPoints／targetComboPoints的value与reason，并对照maximum与maxReason。PUBLIC说明该次返回公开；SECRET或UNKNOWN保留原因，不能用于数值资格。当前值公开不证明最大值或另一种资源也公开。离线测试不证明当前客户端游戏内资源可读。
