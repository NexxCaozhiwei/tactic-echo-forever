local _,T=...
local S,A,M=T.Safety,T.APL,{}
T.Maintenance=M
-- 精确身份只授权维护入口，运行仍要求独立已学、公开可用及失控解除门禁。
M.ControlBreakers={[1259718]=true}
local buffTypes={buff=true,armor=true,defense=true,cooldown=true}
function M:Rows(e) local config=e.db.maintenance and e.db.maintenance[e.classToken]; return config and config.rows or {} end
function M:Enabled(e) local config=e.db.maintenance and e.db.maintenance[e.classToken]; return config and config.enabled==true or false end
function M:RegisteredBuff(id)
 local catalog=A.CatalogByID[id]; local view=S.Spell(id,tostring(id))
 local key=view.reason=="PUBLIC" and A.AbilityNames[view.name] or catalog and catalog.key
 local ability=key and A.Abilities[key]
 return ability and buffTypes[ability.type] and (ability.target=="self" or ability.target=="friendly") or false
end
function M:BuffSpell(id)
 if self.ControlBreakers[id] then return true end
 if self:RegisteredBuff(id) then return true end
 local view=S.Spell(id,tostring(id)); local key=view.reason=="PUBLIC" and A.AbilityNames[view.name]
 if key and A.Abilities[key] and A.Abilities[key].target then return false end
 if A.State.Boolean("C_Spell.IsSpellHarmful",id)~=false then return false end
 -- 其他职业只接受增益目录中的精确身份，不把帮助类治疗等同于增益。
 for _,category in ipairs({2,3}) do
  local ok,list=S.Call("C_CooldownViewer.GetCooldownViewerCategorySet",category,true); list=ok and S.Public(list,"table")
  local got,size=pcall(function() return list and #list end)
  if got and size and size<=128 then for i=1,size do
   local key=S.ID(S.Field(list,i,"number")); if key then local read,info=S.Call("C_CooldownViewer.GetCooldownViewerCooldownInfo",key)
    if read and S.ID(S.Field(info,"spellID","number"))==id then return true end
   end
  end end
 end
 return false
end
function M:Initialize(e,old)
 e.db.maintenance={}
 local saved,savedType=S.Field(old,"maintenance","table"); local first=savedType=="NO_DATA"
 for _,class in ipairs({"MAGE","WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","SHAMAN","WARLOCK","DRUID","DEATHKNIGHT","MONK","DEMONHUNTER","EVOKER"}) do
  local config=S.Field(saved,class,"table")
  local rows=A.Custom.CleanRows(S.Field(config,"rows","table"))
  local seen={}; for _,row in ipairs(rows) do if row.spellID then seen[row.spellID]=true end end
  if first then
   -- 首次从既有配置提取已登记增益。原配置保留，可关闭维护恢复旧行为。
   local manual=e.db.classProfiles[class .. ":base"] or {}; local priority=e.db.apl.custom[class] or {}
   for _,source in ipairs({priority,manual}) do for _,slot in ipairs({"single","multi","third"}) do for _,row in ipairs(source[slot] or {}) do
    if row.spellID and not seen[row.spellID] and #rows<16 and self:RegisteredBuff(row.spellID) then
     local clean=A.Custom.CleanRows({{spellID=row.spellID,enabled=row.enabled~=false,strategies=row.strategies,targetMode=row.targetMode,
      moving=row.moving,activity=row.activity,distanceOp=row.distanceOp,distanceValue=row.distanceValue,cdmKind=row.cdmKind,cdmState=row.cdmState,cdmSpellID=row.cdmSpellID}})[1]
     if clean and not clean.invalid then
      A.Custom:UpgradeStrategies(clean)
      if #clean.strategies==0 then clean.strategies={{mode="use",conditions={{kind="cdmBuff",value=false,spellID=row.spellID}}}} end
      rows[#rows+1]=clean; seen[row.spellID]=true
     end
    end
   end end end
  end
  e.db.maintenance[class]={enabled=config and S.Field(config,"enabled","boolean")==true or (first and #rows>0),rows=rows}
 end
end
function M:Owns(e,id)
 if not self:Enabled(e) then return false end
 for _,row in ipairs(self:Rows(e)) do if row.enabled and not row.invalid and row.spellID==id then return true end end
 return false
end
function M:Context(e,state)
 state.maintenance=e.maintenanceActive==true
 if state.maintenance then state.maintenanceRows=self:Rows(e) else
  state.maintenanceOwned={}; if self:Enabled(e) then for _,row in ipairs(self:Rows(e)) do if row.enabled and not row.invalid then state.maintenanceOwned[row.spellID]=true end end end
 end
end
function M:OutsideAllowed(e)
 return e.maintenanceActive==true and T.Runtime.e==e and T.Runtime.intent==true and T.Runtime.maintenanceManual==true and self:Enabled(e)
end
function M:Restore(e,reason)
 local base=e.maintenanceBase; if not base then e.maintenanceActive=nil; return end
 local internal=T.Runtime.internal; T.Runtime.internal=true
 e:Invalidate(reason or "MAINTENANCE_BASE_RESTORED")
 T.Runtime.internal=internal
 e.maintenanceActive=nil; e.maintenanceBase=nil
 e.steps,e.index,e.stepCasts,e.completed,e.running=base.steps,base.index,base.stepCasts,base.completed,base.running
 e.skipStreak,e.policySkipStreak,e.usageProgress,e.shootHandoff=base.skipStreak,base.policySkipStreak,base.usageProgress,base.shootHandoff
 if e.shootHandoff then e.shootHandoff.generation=e.generation end
 e.aplCandidate=base.aplCandidate; e.aplSnapshot=nil; e.aplPreviewSnapshot=nil; A:Invalidate()
 if e.emergencyExitGroup then
  e.emergencyExitGroup=nil
  if e.groupRun then T.SkillGroups:Restore(e,"GROUP_EMERGENCY_EXIT",true) end
 end
end
function M:Save(e,rows)
 local clean=A.Custom.CleanRows(rows); local seen={}
 local valid,errors=A.Custom:Audit(clean); if not valid then return false,errors end
 for _,row in ipairs(clean) do
  if row.invalid or not self:BuffSpell(row.spellID) or seen[row.spellID] then return false,"仅接受可确认的增益或已支持的解控法术，且精确技能ID不得重复。" end
  seen[row.spellID]=true
 end
 T.Runtime:Stop("MAINTENANCE_EDITED"); e.db.maintenance[e.classToken]=e.db.maintenance[e.classToken] or {enabled=false,rows={}}
 e.db.maintenance[e.classToken].rows=clean; e.maintenanceDone={}; e.maintenanceSnapshot=nil; A:Invalidate()
 return true
end
function M:SetEnabled(e,value)
 T.Runtime:Stop("MAINTENANCE_SETTING_CHANGED")
 e.db.maintenance[e.classToken]=e.db.maintenance[e.classToken] or {rows={}}
 e.db.maintenance[e.classToken].enabled=value==true; e.maintenanceDone={}; e.maintenanceSnapshot=nil; A:Invalidate()
end
function M:Succeeded(e,id)
 local row=A.Custom:CurrentPolicyRow(e)
 if e.maintenanceActive and row and row.behavior and row.behavior.emergency and row.behavior.after=="exit" then e.emergencyExitGroup=true end
 if e.maintenanceActive then e.maintenanceDone=e.maintenanceDone or {}; e.maintenanceDone[id]=true; e.maintenanceSnapshot=nil; e:Log("match","MAINTENANCE_SUCCEEDED",id) end
end
function M:Refresh(e)
 local locked=T.UI.settingsOpen or e:RecommendationLocked()
 if not locked and e.maintenanceActive and e.emergencyExitGroup then self:Restore(e,"EMERGENCY_RETURN") end
 local combat=A.State.Boolean("InCombatLockdown")
 if not self:Enabled(e) or combat==nil or (combat==false and not T.Runtime.maintenanceManual) then
  if not locked and e.maintenanceActive then self:Restore(e) end; return
 end
 local now=A.State.Time(); local old=e.maintenanceSnapshot
 local state
 if old and now and old.sampledAt and now>=old.sampledAt and now-old.sampledAt<(A.State.dirty and .05 or .20)
  and old.revision==(A.State.revision or 0) and old.generation==e.generation and old.receiptSerial==(e.receiptSerial or 0) then state=old
 else
  state={sampledAt=now,generation=e.generation,receiptSerial=e.receiptSerial or 0,revision=A.State.revision or 0,scene=e.scene,
   actions={},gcd={},talents={},buildSignature={},moving=A.State.Boolean("IsPlayerMoving"),combat={in_combat=combat},maintenance=true,maintenanceRows=self:Rows(e)}
  A.Custom:Sample(e,state,self:Rows(e)); state.maintenance=true; state.maintenanceOwned=nil; state.maintenanceRows=self:Rows(e)
  if state.generation~=e.generation or state.receiptSerial~=(e.receiptSerial or 0) or state.revision~=(A.State.revision or 0) then return end
  e.maintenanceSnapshot=state
 end
 local candidate; local trace={}
 e.maintenanceDone=e.maintenanceDone or {}
 for pass=1,2 do for i,row in ipairs(self:Rows(e)) do
  local emergency=row.behavior and row.behavior.emergency==true or false
  if emergency==(pass==1) then
  local allowed,reason=A.Custom:Check(state,row,i)
  -- 锁定推荐只禁止替换和派发，不应漏掉成功后公开的条件复位。
  if allowed==false and e.maintenanceDone[row.spellID] then
   e.maintenanceDone[row.spellID]=nil; e:Log("observed","MAINTENANCE_REARMED",row.spellID)
  end
  trace[#trace+1]={rule="maintenance:" .. i,result=allowed==nil and "UNKNOWN" or allowed and "TRUE" or "FALSE",
   reason=allowed==true and e.maintenanceDone[row.spellID] and "MAINTENANCE_WAIT_REARM" or reason}
  if allowed==true and not e.maintenanceDone[row.spellID] and not candidate and self:BuffSpell(row.spellID) then
   local action=state.actions["custom_" .. i]
   candidate={spellID=row.spellID,name=action.name,target=action.target,action="custom_" .. i,customIndex=i,rule="maintenance:" .. i}
  end
  end
 end end
 if locked or T.UI.settingsOpen or e:RecommendationLocked() then
  A.Trace:Record(e,trace,"MAINTENANCE_WAIT_UNLOCK",nil,state,"maintenance"); return
 end
 if not candidate then
  A.Trace:Record(e,trace,"MAINTENANCE_IDLE",nil,state,"maintenance")
  if e.maintenanceActive then self:Restore(e) end; return
 end
 if not e.maintenanceActive then
  e.maintenanceBase={steps=e.steps,index=e.index,stepCasts=e.stepCasts,completed=e.completed,running=e.running,
   skipStreak=e.skipStreak,policySkipStreak=e.policySkipStreak,usageProgress=e.usageProgress,shootHandoff=e.shootHandoff,aplCandidate=e.aplCandidate}
  e.maintenanceActive=true
 end
 local current=e.steps and e.steps[e.index]
 if not current or current.spellID~=candidate.spellID or not e.aplCandidate or e.aplCandidate.rule~=candidate.rule then
  if not T.Runtime:ReplaceRecommendation({{spellID=candidate.spellID,name=candidate.name,matchIDs={candidate.spellID},repeatCount=1}}) then return end
 end
 state.generation=e.generation; state.receiptSerial=e.receiptSerial or 0
 e.aplCandidate=candidate; e.aplSnapshot=state; e.aplPreviewSnapshot=state; e.maintenanceSnapshot=state
 A.Trace:Record(e,trace,"MAINTENANCE_CANDIDATE",candidate,state)
end
