local _,T,F=...
local X,U=T.PlanShare,T.UI
local n=0
local function eq(a,b) assert(a==b,"分享期望 "..tostring(b).."，实际 "..tostring(a)) end
local function test(name,fn) fn(); n=n+1 end
local function spell(id)
 return {spellID=id,name="技能"..id,matchIDs={id},repeatCount=2,enabled=true,usagePolicy="target",skipUnavailable=true,
  targetMode="enemy",strategies={{mode="use",conditions={{kind="cdmBuff",spellID=400588,value=true}}}}}
end
local function rows(source)
 local steps={}; for i=1,36 do steps[i]=spell(i%2==0 and 205 or 143) end
 local g={name="三十六步组",rounds=3,steps=steps,maintain=true,exit="stop"}
 if source=="manual" then return {T.SkillGroups:Row(g),spell(143)} end
 return {{group=g,spellID=143,enabled=true,strategies={}},{spellID=205,enabled=true,targetMode="enemy",strategies={}}}
end

test("两种方案含36步组与策略完整往返且不带运行设置",function()
 for _,source in ipairs({"manual","apl"}) do
  local e=F.runtime(); local intent,generation=T.Runtime.intent,e.generation
  local code,reason=X:Export("MAGE",source,"中文测试方案",rows(source)); assert(code,reason)
  local plan,message=X:Import(code,"MAGE",source); assert(plan,message)
  eq(#plan.rows[1].group.steps,36); eq(plan.rows[1].group.rounds,3); eq(plan.rows[1].group.maintain,true)
  eq(plan.rows[1].group.steps[36].repeatCount,2); eq(plan.rows[1].group.steps[36].usagePolicy,"target")
  eq(plan.rows[1].group.steps[36].strategies[1].conditions[1].spellID,400588)
  eq(X:Export(plan.class,plan.source,plan.name,plan.rows),code)
  eq(plan.dispatch,nil); eq(plan.hud,nil); eq(plan.selectedPlans,nil)
  eq(T.Runtime.intent,intent); eq(e.generation,generation)
 end
end)

test("损坏过长错职业错类型与超容量拒绝",function()
 local code=assert(X:Export("MAGE","manual","测试",rows("manual")))
 eq(X:Import(code,"SHAMAN","manual"),nil); eq(X:Import(code,"MAGE","apl"),nil)
 eq(X:Import(code:sub(1,-4),"MAGE","manual"),nil)
 eq(X:Import(code:sub(1,10)..(code:sub(11,11)=="a" and "b" or "a")..code:sub(12),"MAGE","manual"),nil)
 eq(X:Import(F.secret,"MAGE","manual"),nil)
 eq(X:Import(code:gsub("TEFPLAN:1:","TEFPLAN:99:",1),"MAGE","manual"),nil)
 eq(X:Import(string.rep("a",X.MaxCode+1),"MAGE","manual"),nil)
 local input=rows("manual"); input[1].group.steps[37]=spell(143)
 eq(X:Export("MAGE","manual","测试",input),nil)
 input=rows("manual"); input[1].group.steps[1].group={name="嵌套",steps={},rounds=1}
 eq(X:Export("MAGE","manual","测试",input),nil)
 input=rows("manual"); input[2].dispatch={permission=true}
 eq(X:Export("MAGE","manual","测试",input),nil)
 input=rows("manual"); input[2].skipUnavailable="true"
 eq(X:Export("MAGE","manual","测试",input),nil)
 for _,text in ipairs({"return {}","m1:s1:an:","s9999999:a","m2:s1:ats1:af","n1/0:","m1:m0:t"}) do
  assert(not pcall(X.Deserialize,X,text))
 end
 local many={}; for i=1,17 do many[i]=spell(143) end
 eq(X:Export("MAGE","manual","测试",many),nil)
end)

test("分享界面导入只改草稿且名称随显式保存落盘",function()
 for _,source in ipairs({"manual","apl"}) do
  local e=F.runtime(); InCombatLockdown=function() return false end; U:OpenSettings(); U:ShowPage(source=="manual" and "profiles" or "customapl")
  local code=assert(X:Export("MAGE",source,"导入名称",rows(source)))
  local before=X:Serialize(source=="manual" and e.db.profiles.multi or T.APL.Custom:Rows(e,"multi"))
  local intent,generation=T.Runtime.intent,e.generation
  assert(U:OpenPlanShare("import"),"open "..source.." page="..tostring(U.page).." slot="..tostring(U.editScene).." group="..tostring(U.groupEditing))
  U:Paint(U.shareBox,"SetText",code); assert(U:ParsePlanShare(),"parse "..source.." "..tostring(U.sharePreview.text))
  local tx=assert(U:PreparePlanImport("multi")); assert(U:ApplyPlanImport(tx))
  eq(X:Serialize(source=="manual" and e.db.profiles.multi or T.APL.Custom:Rows(e,"multi")),before)
  eq(U:SharePlanName(source,"multi"),"导入名称"); assert(T.Profiles:PlanName("multi",e,source)~="导入名称")
  eq(T.Runtime.intent,intent); eq(e.generation,generation)
  local draft=U:StudioPlanDraft(source,"multi"); eq(#draft[1].group.steps,36)
  assert(U:OpenPlanShare("export")); assert(U.shareBox.text:find("TEFPLAN:1:",1,true)); U:ClosePlanShare()
  U:StudioAction(source=="manual" and U.manualSave or U.customSave)
  eq(T.Profiles:PlanName("multi",e,source),"导入名称")
  U:CloseSettings()
 end
end)

test("取消解析失败及过期目标不替换草稿",function()
 local e=F.runtime(); InCombatLockdown=function() return false end; U:OpenSettings(); U:ShowPage("profiles")
 local before=U:StudioFingerprint(U:DraftRows(),"manual")
 assert(U:OpenPlanShare("import")); U:Paint(U.shareBox,"SetText","坏码"); eq(U:ParsePlanShare(),false)
 eq(U:PreparePlanImport(U.editScene),nil); U:ClosePlanShare()
 eq(U:StudioFingerprint(U:DraftRows(),"manual"),before)
 assert(U:OpenPlanShare("import")); U:Paint(U.shareBox,"SetText",assert(X:Export("MAGE","manual","新方案",rows("manual"))))
 assert(U:ParsePlanShare()); local tx=assert(U:PreparePlanImport(U.editScene))
 U:WriteDraft({spell(205)}); local changed=U:StudioFingerprint(U:DraftRows(),"manual")
 eq(U:ApplyPlanImport(tx),false); eq(U:StudioFingerprint(U:DraftRows(),"manual"),changed)
 U:ClosePlanShare()
 local frame=U.sharePanel; local controls=#U.controls
 for i=1,25 do assert(U:OpenPlanShare("import")); eq(U.sharePanel,frame); U:ClosePlanShare() end
 eq(#U.controls,controls)
 U:CloseSettings()
end)

test("空白导入区固定高度且导出复用同一外框",function()
 local e=F.runtime(); InCombatLockdown=function() return false end; U:OpenSettings(); U:ShowPage("profiles")
 U:WriteDraft({spell(143)})
 assert(U:OpenPlanShare("import")); local area=U.shareInputArea
 eq(area.height,164); eq(U.shareInputScroll.height,148); eq(U.shareBox.text,"")
 assert(area.scripts.OnMouseDown); U:ClosePlanShare()
 assert(U:OpenPlanShare("export")); eq(U.shareInputArea,area); eq(area.height,164)
 U:ClosePlanShare(); U:CloseSettings()
end)
local policies={{mode="use",conditions={{kind="moving",value=false}}},{mode="skip",conditions={{kind="cdmBuff",spellID=400588,value=false}}}}
test("单项策略码往返及命名空间职业检查",function()
 local code=assert(X:ExportPolicy("MAGE",policies))
 local policy=assert(X:ImportPolicy(code,"MAGE")); eq(#policy.strategies,2)
 eq(policy.strategies[2].conditions[1].spellID,400588)
 eq(X:ExportPolicy(policy.class,policy.strategies),code)
 eq(X:ImportPolicy(code,"ROGUE"),nil); eq(X:Import(code,"MAGE","manual"),nil)
 eq(X:ImportPolicy(assert(X:Export("MAGE","manual","测试",{spell(143)})),"MAGE"),nil)
end)
test("四种编辑来源导入策略仅修改条件草稿",function()
 for _,source in ipairs({"manual","apl","groupStep","maintenance"}) do
  local e=F.runtime(); InCombatLockdown=function() return false end; U:OpenSettings()
  if source=="manual" or source=="groupStep" then
   U:ShowPage("profiles")
   if source=="manual" then U:WriteDraft({spell(143),spell(205)}); assert(U:SelectStudioRule("manual",1))
   else U:WriteDraft({T.SkillGroups:Row({name="分享组",rounds=1,steps={spell(143),spell(205)}})}); U:OpenSkillGroup("manual",1); assert(U:SelectStudioRule("group",1)) end
  else
   U:ShowPage(source=="maintenance" and "maintenance" or "customapl")
   U.customDraft=T.APL.Custom.CleanRows({{spellID=source=="maintenance" and 1460 or 143,enabled=true,targetMode=source=="maintenance" and "self" or "enemy",strategies={}}})
   U:RefreshCustomAPL(); assert(U:SelectStudioRule("apl",1))
  end
  local row=U:CustomRow(); row.behavior={trigger="edge",scope="entry",after="resume"}
  if source=="manual" then assert(U:StoreSequencePolicy()) end
  local id,count,mode,behavior=row.spellID,row.repeatCount,row.targetMode,X:Serialize(row.behavior)
  local intent,generation=T.Runtime.intent,e.generation
  assert(U:OpenPolicyShare("import")); U:Paint(U.shareBox,"SetText",assert(X:ExportPolicy("MAGE",policies)))
  assert(U:ParsePlanShare()); local tx=assert(U:PreparePolicyImport()); assert(U:ApplyPolicyImport(tx))
  row=U:CustomRow(); eq(#row.strategies,2); eq(row.spellID,id); eq(row.repeatCount,count); eq(row.targetMode,mode); eq(X:Serialize(row.behavior),behavior)
  eq(T.Runtime.intent,intent); eq(e.generation,generation)
  assert(U:OpenPolicyShare("export")); assert(U.shareBox.text:find("TEFPOLICY:1:",1,true)); U:ClosePlanShare()
  if source=="groupStep" then U:CloseSkillGroup(true) end
  U:CloseSettings()
 end
end)
test("六套整包往返原子保存且保留本机设置",function()
 local e=F.runtime(); InCombatLockdown=function() return false end; U:OpenSettings(); U:ShowPage("profiles")
 local bundle=U:BundleDraft()
 for _,source in ipairs({"manual","apl"}) do for _,slot in ipairs({"single","multi","third"}) do
  bundle.plans[source][slot].name=source.."-"..slot
  bundle.plans[source][slot].rows=rows(source)
 end end
 local code=assert(X:ExportBundle(bundle)); local decoded=assert(X:ImportBundle(code,"MAGE"))
 eq(X:ExportBundle(decoded),code); eq(X:ImportBundle(code,"ROGUE"),nil)
 local incomplete=U:BundleDraft(); incomplete.plans.apl.third=nil; eq(X:ExportBundle(incomplete),nil)
 local before=X:Serialize(e.db.profiles); local intent,generation=T.Runtime.intent,e.generation
 local settings=X:Serialize({enabled=e.db.enabledPlans,selected=e.db.selectedPlans,dispatch=e.db.dispatch,hud=e.db.hud})
 assert(U:OpenBundleShare("import")); U:Paint(U.shareBox,"SetText",code); assert(U:ParsePlanShare())
 local tx=assert(U:PrepareBundleImport()); assert(U:ApplyBundleImport(tx))
 eq(X:Serialize(e.db.profiles),before); eq(T.Runtime.intent,intent); eq(e.generation,generation)
 for _,source in ipairs({"manual","apl"}) do for _,slot in ipairs({"single","multi","third"}) do
  eq(#U:PlanShareRows(source,slot)[1].group.steps,36); eq(U:SharePlanName(source,slot),source.."-"..slot)
 end end
 assert(U:SaveBundleDraft())
 eq(X:Serialize({enabled=e.db.enabledPlans,selected=e.db.selectedPlans,dispatch=e.db.dispatch,hud=e.db.hud}),settings)
 local copy=T.Engine.New(T.Config,e.db)
 for _,slot in ipairs({"single","multi","third"}) do
  eq(#copy.db.profiles[slot][1].group.steps,36); eq(#T.APL.Custom:Rows(copy,slot)[1].group.steps,36)
  eq(T.Profiles:PlanName(slot,copy,"manual"),"manual-"..slot); eq(T.Profiles:PlanName(slot,copy,"apl"),"apl-"..slot)
 end
 -- 任一槽无效时，整包保存不得部分覆盖。
 local bad=U:BundleDraft(); bad.plans.apl.third.rows[1].group.steps[37]=spell(143)
 before=X:Serialize(e.db.profiles); eq(T.Profiles:SaveBundle(e,bad),false); eq(X:Serialize(e.db.profiles),before)
 U:CloseSettings()
end)

local function barFixture()
 local original={bar=C_ActionBar,info=C_Spell.GetSpellInfo,known=C_SpellBook.IsSpellKnown,passive=C_Spell.IsSpellPassive,resolve=T.Dispatch.Resolve}
 local actions={[1]=133,[2]=116,[3]=133}
 C_ActionBar={GetActionInfo=function(slot) if actions[slot] then return "spell",actions[slot] end end}
 C_Spell.GetSpellInfo=function(id) return {name=(id==143 or id==133) and "火球术" or "寒冰箭"} end
 C_SpellBook.IsSpellKnown=function() return true end; C_Spell.IsSpellPassive=function() return false end
 T.Dispatch.Resolve=function(_,id) return {spellID=id,key="1"} end
 return actions,function()
  C_ActionBar=original.bar; C_Spell.GetSpellInfo=original.info; C_SpellBook.IsSpellKnown=original.known
  C_Spell.IsSpellPassive=original.passive; T.Dispatch.Resolve=original.resolve
 end
end
test("动作条精确等级不按最高等级猜测且歧义未知未绑定拒绝",function()
 F.runtime(); local actions,restore=barFixture()
 eq(T.ActionSources:FindBarRank(143),133)
 actions[4]=143; eq(T.ActionSources:FindBarRank(143),nil); actions[4]=nil
 C_SpellBook.IsSpellKnown=function() return F.secret end; eq(T.ActionSources:FindBarRank(143),nil)
 C_SpellBook.IsSpellKnown=function() return true end
 T.Dispatch.Resolve=function() return nil end; eq(T.ActionSources:FindBarRank(143),nil)
 restore()
end)
test("批量等级替换包含组内技能且只改草稿保留观察ID",function()
 for _,source in ipairs({"manual","apl"}) do
  local e=F.runtime(); InCombatLockdown=function() return false end; U:OpenSettings(); U:ShowPage(source=="manual" and "profiles" or "customapl")
  local actions,restore=barFixture()
  local g={name="等级组",rounds=2,steps={spell(205)}}
  if source=="manual" then U:WriteDraft({spell(143),T.SkillGroups:Row(g)})
  else U.customDraft=T.APL.Custom.CleanRows({{spellID=143,enabled=true,strategies=policies},{group=g,spellID=205,enabled=true,strategies={}}}); U:RefreshCustomAPL() end
  local before=X:Serialize(e.db.profiles); local intent,generation=T.Runtime.intent,e.generation
  assert(U:DetectPlanBarRanks()); assert(U.pendingConfirmation); U:StudioAction(U.confirmAccept)
  local draft=U:StudioActiveRows(); eq(draft[1].spellID,133); eq(draft[2].group.steps[1].spellID,116); eq(draft[2].spellID,116)
  eq(draft[2].group.steps[1].repeatCount,2); eq(draft[2].group.steps[1].strategies[1].conditions[1].spellID,400588)
  eq(X:Serialize(e.db.profiles),before); eq(T.Runtime.intent,intent); eq(e.generation,generation)
  restore(); U:CloseSettings()
 end
end)
test("确认期间动作条变更不应用旧替换计划",function()
 local e=F.runtime(); InCombatLockdown=function() return false end; U:OpenSettings(); U:ShowPage("profiles"); U:WriteDraft({spell(143)})
 local actions,restore=barFixture()
 assert(U:DetectPlanBarRanks()); actions[1]=143; actions[3]=nil
 U:StudioAction(U.confirmAccept); eq(U:DraftRows()[1].spellID,143)
 restore(); U:CloseSettings()
end)

test("新版整包含维护策略与紧急行为且保留维护总开关",function()
 for _,enabled in ipairs({false,true}) do
  local e=F.runtime(); InCombatLockdown=function() return false end; U:OpenSettings(); U:ShowPage("maintenance")
  e.db.maintenance.MAGE={enabled=enabled,rows={}}
  local bundle=U:BundleDraft()
  bundle.maintenance.rows={{spellID=1259718,enabled=true,targetMode="self",strategies={{mode="use",conditions={{kind="lossOfControl",control="stun",value=true}}}},behavior={trigger="edge",scope="entry",emergency=true,after="exit"}}}
  local code=assert(X:ExportBundle(bundle)); assert(code:find("TEFBUNDLE:2:",1,true))
  local decoded=assert(X:ImportBundle(code,"MAGE")); eq(decoded.maintenance.rows[1].behavior.emergency,true)
  assert(U:OpenBundleShare("import")); U:Paint(U.shareBox,"SetText",code); assert(U:ParsePlanShare())
  assert(U:ApplyBundleImport(assert(U:PrepareBundleImport())))
  eq(#T.Maintenance:Rows(e),0); eq(T.Maintenance:Enabled(e),enabled)
  eq(U.customDraft[1].spellID,1259718); assert(U:SaveBundleDraft())
  eq(T.Maintenance:Rows(e)[1].spellID,1259718); eq(T.Maintenance:Enabled(e),enabled)
  local copy=T.Engine.New(T.Config,e.db); eq(T.Maintenance:Rows(copy)[1].behavior.after,"exit"); eq(T.Maintenance:Enabled(copy),enabled)
  U:CloseSettings()
 end
end)
test("旧版整包导入保存不会清空已有维护列表",function()
 local e=F.runtime(); InCombatLockdown=function() return false end; U:OpenSettings(); U:ShowPage("maintenance")
 e.db.maintenance.MAGE={enabled=true,rows=T.APL.Custom.CleanRows({{spellID=1259718,enabled=true,targetMode="self",strategies={}}})}
 U.customDraft=T.APL.Custom.CleanRows(T.Maintenance:Rows(e)); U:RefreshCustomAPL()
 local before=X:Serialize(e.db.maintenance.MAGE)
 local bundle=U:BundleDraft(); bundle.schema=1; bundle.maintenance=nil
 local code=assert(X:ExportBundle(bundle)); assert(code:find("TEFBUNDLE:1:",1,true))
 assert(U:OpenBundleShare("import")); U:Paint(U.shareBox,"SetText",code); assert(U:ParsePlanShare())
 assert(U:ApplyBundleImport(assert(U:PrepareBundleImport()))); assert(U:SaveBundleDraft())
 eq(X:Serialize(e.db.maintenance.MAGE),before); U:CloseSettings()
end)
test("维护无效时整包保存不部分写入且拒绝携带总开关",function()
 local e=F.runtime(); InCombatLockdown=function() return false end; U:OpenSettings(); U:ShowPage("profiles")
 local bundle=U:BundleDraft(); bundle.maintenance={rows={{spellID=143,enabled=true,targetMode="enemy",strategies={}}}}
 local buff=T.Maintenance.BuffSpell; T.Maintenance.BuffSpell=function() return false end
 local before=X:Serialize({profiles=e.db.profiles,apl=e.db.apl.custom.MAGE,maintenance=e.db.maintenance.MAGE})
 eq(T.Profiles:SaveBundle(e,bundle),false)
 eq(X:Serialize({profiles=e.db.profiles,apl=e.db.apl.custom.MAGE,maintenance=e.db.maintenance.MAGE}),before)
 T.Maintenance.BuffSpell=buff
 bundle.maintenance.enabled=true; eq(X:ExportBundle(bundle),nil)
 U:CloseSettings()
end)
return n
