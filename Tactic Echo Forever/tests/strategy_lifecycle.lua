local _,T,F=...
local C,A=T.APL.Custom,T.APL
local count=0
local function eq(a,b) assert(a==b,"策略生命周期：预期 " .. tostring(b) .. "，实际 " .. tostring(a)) end
local function test(name,fn) fn(); count=count+1 end
local function row(id,trigger,scope)
 return {spellID=id or 143,name="测试技能",matchIDs={id or 143},repeatCount=1,enabled=true,moving="any",activity="any",cdmKind="none",distanceOp="any",
  strategies={},behavior={trigger=trigger or "continuous",scope=scope or "entry",emergency=false,after="resume"}}
end
local function use(... ) return {{mode="use",conditions={...}}} end
local function setup()
 local e=F.runtime(); T.UI.settingsOpen=false; T.Runtime.intent=true
 InCombatLockdown=function() return true end; C:LifecycleContext(e)
 e.db.apl.custom[e.classToken]=e.db.apl.custom[e.classToken] or {single={},multi={},third={}}
 return e
end
local function sample(e,r,moving)
 return {engine=e,readOnly=false,moving=moving,combat={in_combat=true},actions={custom_1={spellID=r.spellID,known=true,usable=true,power_ok=true,in_range=true,loss_control_clear=true}}}
end
local function cast(id,guid)
 F.receipt("UNIT_SPELLCAST_SENT",id,guid); F.receipt("UNIT_SPELLCAST_SUCCEEDED",id,guid)
end

test("行为清洗拒绝受限字段与不支持的共享触发",function()
 local r=row(); r.behavior.trigger=F.secret; local _,why=C.CleanBehavior(r); eq(why,"BEHAVIOR_INVALID")
 r=row(); r.behavior=F.secret; _,why=C.CleanBehavior(r); eq(why,"BEHAVIOR_INVALID")
 r=row(143,"edge","spell"); _,why=C.CleanBehavior(r); eq(why,"BEHAVIOR_INVALID")
 r=row(); r.behavior.extra=true; _,why=C.CleanBehavior(r); eq(why,"BEHAVIOR_INVALID")
end)
test("使用策略跨条目的布尔与数值矛盾被体检",function()
 local r=row(); r.strategies={{mode="use",conditions={{kind="moving",value=true}}},{mode="use",conditions={{kind="moving",value=false}}}}
 eq(C:Audit({r}),false)
 r.strategies=use({kind="distance",min=30},{kind="distance",max=20}); eq(C:Audit({r}),false)
 r.strategies={{mode="skip",conditions={{kind="moving",value=true},{kind="moving",value=false}}}}
 local ok,_,warnings=C:Audit({r}); eq(ok,true); assert(warnings~="")
end)
test("体检失败不会停止运行或覆盖已保存方案",function()
 local e=setup(); local old=C:Rows(e)
 local r=row(); r.strategies=use({kind="combat",value=true},{kind="combat",value=false})
 local generation=e.generation
 eq(C:Save(e,{r},"single",e.classToken),false); eq(e.generation,generation); eq(C:Rows(e),old); eq(T.Runtime.intent,true)
end)
test("未知与暂时不可用不重新武装条件触发",function()
 local e=setup(); local r=row(143,"edge"); r.strategies=use({kind="moving",value=true})
 C:PolicySucceeded(e,r); eq(C:PolicyAllowed(e,r),false)
 local state=sample(e,r,nil); C:ObservePolicy(e,r,state,1); eq(C:PolicyAllowed(e,r),false)
 state=sample(e,r,true); state.actions.custom_1.usable=false; C:Check(state,r,1); eq(C:PolicyAllowed(e,r),false)
 state=sample(e,r,false); C:ObservePolicy(e,r,state,1); eq(C:PolicyAllowed(e,r),true)
end)
test("只读解释不消耗或重新武装触发且不建立输入请求",function()
 local e=setup(); local r=row(143,"edge"); r.strategies=use({kind="moving",value=true})
 e.db.apl.custom[e.classToken][e.scene]={r}; C:PolicySucceeded(e,r)
 local records,requests,generation,index=e.policyRecords,T.Runtime.requestSerial,e.generation,e.index
 IsPlayerMoving=function() return false end
 local text=C:Explain(e); assert(text:find("要求",1,true)); assert(text:find("不满足",1,true))
 eq(C:PolicyAllowed(e,r),false); eq(e.policyRecords,records); eq(T.Runtime.requestSerial,requests); eq(e.generation,generation); eq(e.index,index)
end)
test("每战斗共享额度由成功消费且未知不制造新战斗",function()
 local e=setup(); local first,other=row(143,"combat","spell"),row(143,"combat","spell")
 eq(C:PolicyAllowed(e,first),true); C:PolicySucceeded(e,first); eq(C:PolicyAllowed(e,other),false)
 InCombatLockdown=function() return F.secret end; C:LifecycleContext(e); eq(C:PolicyAllowed(e,other),nil)
 InCombatLockdown=function() return true end; C:LifecycleContext(e)
 e.db.apl.custom[e.classToken]=e.db.apl.custom[e.classToken] or {single={},multi={},third={}}; eq(C:PolicyAllowed(e,other),false)
 InCombatLockdown=function() return false end; C:LifecycleContext(e)
 InCombatLockdown=function() return true end; C:LifecycleContext(e)
 e.db.apl.custom[e.classToken]=e.db.apl.custom[e.classToken] or {single={},multi={},third={}}; eq(C:PolicyAllowed(e,other),true)
end)
test("每目标额度记住返回旧目标且GUID受限时保守回退",function()
 local e=setup(); local r=row(143,"target"); UnitExists=function() return true end
 local target="Creature-A"; UnitGUID=function() return target end
 eq(C:PolicyAllowed(e,r),true); C:PolicySucceeded(e,r); eq(C:PolicyAllowed(e,r),false)
 e:UsageTargetChanged(); target="Creature-B"; eq(C:PolicyAllowed(e,r),true)
 e:UsageTargetChanged(); target="Creature-A"; eq(C:PolicyAllowed(e,r),false)
 e:UsageTargetChanged(); target=F.secret; eq(C:PolicyAllowed(e,r),true); C:PolicySucceeded(e,r); eq(C:PolicyAllowed(e,r),false)
 target="Creature-C"; eq(C:PolicyAllowed(e,r),false)
end)
test("额度饱和后未知阻断且不淘汰旧记录",function()
 local e=setup(); local r=row(143,"target"); UnitExists=function() return true end; UnitGUID=function() return "Creature-limit" end
 local record=C:PolicyRecord(e,r,true); record.targetCount=256; record.targets={}
 eq(C:PolicyAllowed(e,r),nil); eq(record.targetCount,256)
 e.policyRecords={}; e.policyRecordCount=256; eq(C:PolicyAllowed(e,row(143,"edge")),nil)
end)
test("行为字段在列表组内优先级清洗和重载保留",function()
 local e=setup(); local r=row(143,"combat","spell")
 local manual=T.Profiles:Clean({r}); eq(manual[1].behavior.scope,"spell")
 local steps=T.Engine.Validate(manual); eq(steps[1].behavior.trigger,"combat")
 local group={name="测试",rounds=2,steps={r},maintain=true,exit="stop"}
 local g=T.SkillGroups:Clean(group); eq(g.maintain,true); eq(g.exit,"stop"); eq(g.steps[1].behavior.trigger,"combat")
 local clean=C.CleanRows({r}); eq(clean[1].behavior.scope,"spell")
 eq(T.SkillGroups:Clean({name="测试",rounds=1,steps={r},maintain=F.secret}),nil)
end)
test("固定列表只有精确成功消费额度失败不消耗",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{row(143,"combat"),row(205)})); T.Runtime:SetIntent(true)
 local current=e.steps[1]
 F.receipt("UNIT_SPELLCAST_SENT",143,"policy-failed"); F.receipt("UNIT_SPELLCAST_FAILED",143,"policy-failed")
 eq(C:PolicyAllowed(e,current),true); T.Runtime:Reconcile()
 cast(143,"policy-success"); eq(C:PolicyAllowed(e,current),false); eq(e.index,2)
end)
test("目标上下文变化的迟到成功不能推进或消耗",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 UnitExists=function() return true end; local id="Creature-old"; UnitGUID=function() return id end
 assert(T.Profiles:Save(e,"single",{row(143,"target"),row(205)})); T.Runtime:SetIntent(true)
 F.receipt("UNIT_SPELLCAST_SENT",143,"policy-target-old")
 id="Creature-new"; e:UsageTargetChanged()
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"policy-target-old"); eq(e.index,1); eq(e.stepCasts,0)
 eq(C:PolicyAllowed(e,e.steps[1]),true)
end)
test("人工跳过不写成功记录并拒绝锁定施法",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{row(143),row(205)})); T.Runtime:SetIntent(true)
 F.receipt("UNIT_SPELLCAST_SENT",143,"manual-skip-lock"); eq(T.Runtime:Intervene("skip"),false); eq(e.index,1)
 F.receipt("UNIT_SPELLCAST_FAILED",143,"manual-skip-lock")
 assert(T.Runtime:Intervene("skip")); eq(e.index,2); eq(e:StrategySucceeded(143),false)
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"manual-skip-lock"); eq(e.index,2)
end)
test("技能组保持未知等待明确不满足退出",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 local g={name="保持组",rounds=2,steps={row(143)},maintain=true,exit="next"}
 local parent=T.SkillGroups:Row(g,use({kind="moving",value=false}))
 IsPlayerMoving=function() return false end
 assert(T.Profiles:Save(e,"single",{parent,row(205)})); T.Runtime:SetIntent(true); assert(e.groupRun)
 IsPlayerMoving=function() return F.secret end; A:Invalidate(); T.Runtime:Reconcile(); assert(e.groupRun); eq(e.groupPolicyBlocked,"GROUP_KEEP_UNKNOWN")
 IsPlayerMoving=function() return true end; A:Invalidate(); T.Runtime:Reconcile(); eq(e.groupRun,nil); eq(e.index,2); eq(e:StrategySucceeded(143),false)
end)
test("保持条件退出可显式停止而不记录组成功",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 local g={name="保持停止",rounds=1,steps={row(143)},maintain=true,exit="stop"}
 local parent=T.SkillGroups:Row(g,use({kind="moving",value=false})); parent.behavior=row(143,"edge").behavior
 IsPlayerMoving=function() return false end
 assert(T.Profiles:Save(e,"single",{parent,row(205)})); T.Runtime:SetIntent(true); local original=e.groupRun.row
 IsPlayerMoving=function() return true end; A:Invalidate(); T.Runtime:Reconcile()
 eq(T.Runtime.intent,false); eq(e.groupRun,nil); eq(C:PolicyAllowed(e,original),true)
end)
test("人工结束组和重新判断不伪造成功",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row({name="人工结束",rounds=1,steps={row(143)}}),row(205)}))
 T.Runtime:SetIntent(true); assert(e.groupRun); assert(T.Runtime:Intervene("endgroup")); eq(e.groupRun,nil); eq(e.index,2); eq(e:StrategySucceeded(143),false)
 local index=e.index; assert(T.Runtime:Intervene("recheck")); eq(e.index,index)
end)
test("人工偏离可暂停并保留技能组进度",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row({name="人工接管",rounds=1,steps={row(143),row(205)}})}))
 e.db.dispatch.takeover="pause"; T.Runtime:SetIntent(true); assert(e.groupRun)
 F.receipt("UNIT_SPELLCAST_SENT",2136,"manual-other-spell")
 eq(T.Runtime.intent,false); assert(e.groupRun); eq(e.index,1)
end)
test("紧急规则优先于普通维护且等待当前施法",function()
 local e=setup(); T.Runtime:Stop()
 local info=C_Spell.GetSpellInfo
 C_Spell.GetSpellInfo=function(id) return {name=id==168 and "霜甲术" or id==7302 and "冰甲术" or "技能" .. id} end
 C_SpellBook.IsSpellKnown=function() return true end
 local ordinary,emergency=row(7302),row(168)
 emergency.behavior.emergency=true; emergency.behavior.trigger="edge"
 assert(T.Maintenance:Save(e,{{spellID=ordinary.spellID,strategies=ordinary.strategies,behavior=ordinary.behavior},{spellID=emergency.spellID,strategies=emergency.strategies,behavior=emergency.behavior}})); T.Maintenance:SetEnabled(e,true)
 T.Runtime:SetIntent(true); eq(e.aplCandidate.spellID,168)
 cast(168,"emergency-once"); A:Invalidate(); T.Runtime:Reconcile(); eq(e.aplCandidate.spellID,7302)
 C_Spell.GetSpellInfo=info
end)
test("紧急成功后可结束原组且失败不提前结束",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row({name="紧急退出",rounds=1,steps={row(143)}}),row(205)}))
 T.Runtime:SetIntent(true); assert(e.groupRun)
 local info=C_Spell.GetSpellInfo; C_Spell.GetSpellInfo=function(id) return {name=id==168 and "霜甲术" or "技能" .. id} end
 C_SpellBook.IsSpellKnown=function() return true end
 local emergency=row(168,"edge"); emergency.behavior.emergency=true; emergency.behavior.after="exit"
 -- 开启维护是配置编辑，会停止旧运行；随后重新进入组再激活已保存配置。
 e.db.maintenance[e.classToken]={enabled=false,rows={emergency}}; e.db.maintenance[e.classToken].enabled=true
 A:Invalidate(); T.Runtime:Reconcile(); assert(e.maintenanceActive); assert(e.groupRun)
 F.receipt("UNIT_SPELLCAST_SENT",168,"emergency-fail"); F.receipt("UNIT_SPELLCAST_FAILED",168,"emergency-fail"); assert(e.groupRun); T.Runtime:Reconcile()
 cast(168,"emergency-exit"); A:Invalidate(); T.Runtime:Reconcile(); eq(e.groupRun,nil); eq(e.index,2)
 C_Spell.GetSpellInfo=info
end)
test("暂停候选替换不清额度重置才清除",function()
 local e=setup(); local r=row(143,"combat"); C:PolicySucceeded(e,r)
 T.Runtime:Stop(); eq(C:PolicyAllowed(e,r),false)
 assert(T.Runtime:ReplaceRecommendation({row(205)})); eq(C:PolicyAllowed(e,r),false)
 T.Runtime:Reset(); C:LifecycleContext(e); eq(C:PolicyAllowed(e,r),true)
end)
test("严格距离边界矛盾与未学提示不等同未知",function()
 local e=setup(); local r=row(); r.strategies=use({kind="distance",op="gt",threshold=20},{kind="distance",op="le",threshold=20})
 eq(C:Audit({r}),false)
 r.strategies={}; C_SpellBook.IsSpellKnown=function() return F.secret end
 local valid,_,warnings=C:Audit({r},e); eq(valid,true); assert(not warnings:find("当前未学",1,true))
 C_SpellBook.IsSpellKnown=function() return false end
 valid,_,warnings=C:Audit({r},e); eq(valid,true); assert(warnings:find("当前未学",1,true))
end)
test("重载保留配置并清除会话额度",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{row(143,"target")})); local reload=T.Engine.New(T.Config,e.db)
 eq(reload.db.profiles.single[1].behavior.trigger,"target"); eq(reload.policyRecords,nil)
end)
test("紧急规则不会抢占锁定的当前施法",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{row(143),row(205)})); T.Runtime:SetIntent(true)
 F.receipt("UNIT_SPELLCAST_SENT",143,"emergency-cast-lock")
 local info=C_Spell.GetSpellInfo; C_Spell.GetSpellInfo=function(id) return {name=id==168 and "霜甲术" or "技能" .. id} end
 C_SpellBook.IsSpellKnown=function() return true end
 local r=row(168,"edge"); r.behavior.emergency=true
 e.db.maintenance[e.classToken]={enabled=true,rows={r}}; A:Invalidate(); T.Runtime:Reconcile(); eq(e.maintenanceActive,nil)
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"emergency-cast-lock"); A:Invalidate(); T.Runtime:Reconcile(); eq(e.maintenanceActive,true); eq(e.aplCandidate.spellID,168)
 C_Spell.GetSpellInfo=info
end)
test("技能组额度只在正常完成后消费",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 local parent=T.SkillGroups:Row({name="组完成额度",rounds=1,steps={row(143),row(205)}})
 parent.behavior=row(143,"combat").behavior
 assert(T.Profiles:Save(e,"single",{parent,row(143)})); T.Runtime:SetIntent(true)
 local original=e.groupRun.row; cast(143,"group-quota-first"); eq(C:PolicyAllowed(e,original),true)
 cast(205,"group-quota-last"); T.Runtime:Reconcile(); eq(e.groupRun,nil); eq(C:PolicyAllowed(e,original),false)
end)
test("策略编辑可设置触发额度且保存重载保留技能替换入口",function()
 local e=setup(); T.Runtime:Stop(); T.UI:ShowPage("customapl"); assert(T.UI:AddCustomSpell(143))
 T.UI.strategyTriggerControls.combat.scripts.OnClick(); T.UI.strategyScopeControls.spell.scripts.OnClick()
 assert(T.UI:CommitCustomNumbers()); eq(T.UI.customDraft[1].behavior.trigger,"combat"); eq(T.UI.customDraft[1].behavior.scope,"spell")
 assert(C:Save(e,T.UI.customDraft,T.UI.customLoadedScene,T.UI.customClass))
 local reload=T.Engine.New(T.Config,e.db); eq(C:Rows(reload,"single")[1].behavior.trigger,"combat")
 assert(T.UI.strategyReplaceID.shown); assert(T.UI.strategyUpgrade.shown)
 T.UI:ShowPage("diagnostics"); assert(T.UI.studioActivities.diagnostics.shown~=false)
 eq(T.UI.readouts.diagnostics.point[5],-104)
end)
test("重新开始组的拒绝操作保留原进度",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 local parent=T.SkillGroups:Row({name="重开组",rounds=2,steps={row(143),row(205)}},use({kind="moving",value=false}))
 IsPlayerMoving=function() return false end
 assert(T.Profiles:Save(e,"single",{parent,row(143)})); T.Runtime:SetIntent(true); cast(143,"restart-progress")
 local run,index=e.groupRun,e.index; eq(index,2)
 IsPlayerMoving=function() return true end; A:Invalidate(); eq(T.Runtime:Intervene("restartgroup"),false); eq(e.groupRun,run); eq(e.index,index)
 IsPlayerMoving=function() return false end; A:Invalidate(); assert(T.Runtime:Intervene("restartgroup")); eq(e.groupRun,run); eq(e.index,1); eq(run.round,1)
end)
test("时间线关联同一次公开起始和精确成功且重载保留",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{row(143),row(205)})); T.Runtime:SetIntent(true); cast(143,"timeline-attempt")
 local first,last
 for _,log in ipairs(e.db.diagnostics) do if log.reason=="PUBLIC_INITIATION" and log.spellID==143 then first=log elseif log.reason=="CURRENT_MATCH" then last=log end end
 assert(first and last); assert(first.attempt); eq(first.attempt,last.attempt); eq(first.attemptRequest,last.attemptRequest)
 assert(C:Timeline(e):find("起始身份",1,true)); local reload=T.Engine.New(T.Config,e.db)
 local retained=false; for _,log in ipairs(reload.db.diagnostics) do if log.attempt==first.attempt then retained=true end end; assert(retained)
end)
test("部分次数不得跨目标累计",function()
 local e=setup(); T.Runtime:Stop(); assert(T.Recommendation:SetSource(e,"manual","single"))
 UnitExists=function() return true end; local target="Creature-partial-A"; UnitGUID=function() return target end
 local first=row(143,"target"); first.repeatCount=2
 assert(T.Profiles:Save(e,"single",{first,row(205)})); T.Runtime:SetIntent(true)
 cast(143,"partial-target-A"); eq(e.stepCasts,1)
 target="Creature-partial-B"; e:UsageTargetChanged(); eq(C:PolicyAllowed(e,e.steps[1]),nil)
 T.Runtime:Reconcile(); eq(e.stepCasts,0); eq(e.index,1)
 cast(143,"partial-target-B1"); eq(e.stepCasts,1); eq(e.index,1)
 cast(143,"partial-target-B2"); eq(e.index,2)
end)
test("共享额度不能扩展为技能组首技能身份",function()
 local parent=T.SkillGroups:Row({name="组身份",rounds=1,steps={row(143)}})
 parent.behavior=row(143,"combat","spell").behavior
 local _,why=C.CleanBehavior(parent); eq(why,"BEHAVIOR_INVALID")
end)
return count
