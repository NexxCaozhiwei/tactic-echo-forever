local _,T=...
local S,G=T.Safety,{}
T.SkillGroups=G
function G:LogName(row)
 local name=S.Field(row,"groupName","string"); return name and #name<=64 and not name:find("[|%c]") and name or nil
end
function G:LogNumber(row,field,limit)
 local value=S.Field(row,field,"number"); return value and value>=1 and value<=limit and value%1==0 and value or nil
end
local function target()
 local ok,raw=S.Call("UnitGUID","target"); return ok and S.Identity(raw) or nil
end
-- 配置嵌入父列表，不增加输入链；组内不允许嵌套。
function G:Clean(raw)
 local record,why=S.Public(raw,"table"); if not record then return nil,why end
 local name=S.Field(record,"name","string")
 local rounds,status=S.Field(record,"rounds","number"); if status=="NO_DATA" then rounds=1 end
 if not name or #name<1 or #name>64 or name:find("[|%c]") or not rounds or rounds<1 or rounds>99 or rounds%1~=0 then return nil,"GROUP_INVALID" end
 local rows=S.Field(record,"steps","table"); local got,size=pcall(function() return rows and #rows end)
 if not got or not size or size>8 then return nil,"GROUP_CAPACITY" end
 for i=1,size do local _,kind=S.Field(S.Field(rows,i,"table"),"group","table"); if kind~="NO_DATA" then return nil,"GROUP_NESTED" end end
 local clean=T.Profiles:Clean(rows,8); if not clean then return nil,"GROUP_STEPS_INVALID" end
 local maintain,maintainType=S.Field(record,"maintain","boolean")
 local exit,exitType=S.Field(record,"exit","string")
 if (maintainType~="PUBLIC" and maintainType~="NO_DATA") or (exitType~="PUBLIC" and exitType~="NO_DATA")
  or (exit and exit~="next" and exit~="stop") then return nil,"GROUP_POLICY_INVALID" end
 return {name=name,rounds=rounds,steps=clean,maintain=maintain==true,exit=exit or "next"}
end
function G:Row(group,strategies,enabled)
 local first=group.steps[1]
 return {group=group,name=group.name,spellID=first and first.spellID or 0,matchIDs=first and first.matchIDs or {},
  unverified=not first or first.unverified or nil,repeatCount=1,usagePolicy="always",enabled=enabled~=false,strategies=strategies or {}}
end
function G:Restore(e,reason,finished)
 local run=e.groupRun; if not run then return end
 local prior=T.Runtime.internal; T.Runtime.internal=true; e:Invalidate(reason or "GROUP_RESTORED"); T.Runtime.internal=prior
 e.groupRun=nil; e.groupPolicyBlocked=nil; e.groupKeepSnapshot=nil
 e.steps,e.index,e.stepCasts,e.completed,e.running=run.steps,run.index,run.count,run.completed,run.running
 e.usageProgress,e.shootHandoff=run.usageProgress,run.shootHandoff
 e.skipStreak,e.policySkipStreak,e.attackActivationStreak=run.skipStreak,run.policySkipStreak,run.attackActivationStreak
 if e.shootHandoff then e.shootHandoff.generation=e.generation end
 e.aplCandidate=run.candidate; e.aplSnapshot=nil; e.aplPreviewSnapshot=nil; T.APL:Invalidate()
 if finished and run.source=="manual" then
  e.index=run.index+1; e.stepCasts=0; e.usageProgress=nil
  if e.index>#e.steps then if e.db.loop then e.index=1 else e.index=run.index; e.completed=true; e.running=false end end
 elseif finished then
  e.groupConsumed=e.groupConsumed or {}; e.groupConsumed[run.row]=true
 end
 if reason=="GROUP_FINISHED" and run.successful and run.policyStamp==T.APL.Custom:PolicyStamp(e,run.row) then T.APL.Custom:PolicySucceeded(e,run.row) end
 e:Log("observed",reason=="GROUP_TARGET_CHANGED" and "GROUP_TARGET_ABORTED" or reason=="GROUP_FINISHED" and "GROUP_COMPLETED" or reason or "GROUP_RESTORED")
end
function G:Begin(e,row,source,observedGUID)
 local combat=T.APL.State.Boolean("InCombatLockdown")
 if combat~=true and (not observedGUID or combat~=false) then return false end
 if e.groupRun or e.maintenanceActive or (not observedGUID and e:RecommendationLocked()) or not row.group or #row.group.steps==0 then return false end
 local group=self:Clean(row.group); if not group then return false end
 for i,step in ipairs(group.steps) do T.APL.Custom.PolicyIdentities[step]=row.group.steps[i] end
 local steps=T.Engine.Validate(group.steps); if not steps then return false end
 local run={row=row,group=group,source=source,steps=e.steps,index=e.index,count=e.stepCasts,completed=e.completed,running=e.running,
  usageProgress=e.usageProgress,shootHandoff=e.shootHandoff,candidate=e.aplCandidate,round=1,
  skipStreak=e.skipStreak,policySkipStreak=e.policySkipStreak,attackActivationStreak=e.attackActivationStreak,
  target=target(),targetSerial=e.usageTargetSerial or 0}
 run.policyStamp=T.APL.Custom:PolicyStamp(e,row)
 e.groupRun=run
 if observedGUID then
  -- 仅接续公开起始，输入仍由战斗门禁阻断；不在锁定施法中改选其他候选。
  local prior=T.Runtime.internal; T.Runtime.internal=true; e:Invalidate("GROUP_MANUAL_START_ADOPTED"); T.Runtime.internal=prior
  e.steps=steps; e.index=1; e.stepCasts=0; e.completed=false; e.running=true
  T.Dispatch.initiation={generation=e.generation,index=1,spellID=steps[1].spellID,guid=observedGUID}
 elseif not T.Runtime:ReplaceRecommendation(group.steps) then e.groupRun=nil; return false end
 e.skipStreak=0; e.policySkipStreak=0; e.attackActivationStreak=0
 e:Log("observed","GROUP_ENTERED"); return true
end
function G:ObserveStart(e,event,unit,id,guid)
 if (event~="UNIT_SPELLCAST_SENT" and event~="UNIT_SPELLCAST_START") or unit~="player" or not id or not guid then return false end
 local runtime=T.Runtime
 if runtime.e~=e or not runtime.intent or e.groupRun or e.maintenanceActive or T.UI.settingsOpen
  or e.identitySaturated or e.seen[guid] or e.associationCount>0 or T.Dispatch.castQueue then return false end
 local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
 local source=T.Recommendation:BaseSource(e); local row,allowed
 if source=="manual" then
  row=e.steps and e.steps[index]
  if not row or not row.group or row.spellID~=id then return false end
  allowed=T.Dispatch:ManualPolicy(e,row,true,true)
 else
  -- 公开起始必须匹配此刻最高优先级规则，不能从成功事件倒推进入。
  local state=T.APL.State:Sample(e)
  if not state then return false end
  local candidate=T.APL:Evaluate(state,e.db.apl,e.classToken)
  row=candidate and T.APL.Custom:Rows(e)[candidate.customIndex]
  allowed=candidate and candidate.spellID==id and row and row.group~=nil
 end
 local first=row and row.group and row.group.steps[1]
 if allowed~=true or not first or first.enabled==false or first.unverified or first.spellID~=id then return false end
 if source=="manual" and T.Dispatch:ManualPolicy(e,first,true)~=true then return false end
 if source=="apl" then
  local state={actions={},moving=T.APL.State.Boolean("IsPlayerMoving"),combat={in_combat=T.APL.State.Boolean("InCombatLockdown")}}
  T.APL.Custom:Sample(e,state,{first})
  if T.APL.Custom:CheckStrategies(state,first,1)~=true then return false end
 end
 if runtime.e~=e or T.engine~=e or not runtime.intent or generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0) then return false end
 return self:Begin(e,row,source,guid)
end
function G:Refresh(e)
 if e.maintenanceActive or T.UI.settingsOpen then return end
 local identity=target()
 if e.groupConsumedSerial~=(e.usageTargetSerial or 0) then e.groupConsumed={}; e.groupConsumedSerial=e.usageTargetSerial or 0 end
 if identity and identity~=e.groupConsumedTarget then e.groupConsumed={}; e.groupConsumedTarget=identity end
 local run=e.groupRun
 if run then
  if e:RecommendationLocked() then return end
  local exists=T.APL.State.Boolean("UnitExists","target")
  local dead=T.APL.State.Boolean("UnitIsDeadOrGhost","target")
  if run.targetSerial~=(e.usageTargetSerial or 0) or (run.target and identity and run.target~=identity) or exists==false or dead==true then self:Restore(e,"GROUP_TARGET_CHANGED",true); return end
  if run.group.maintain then
   local allowed=self:KeepAllowed(e,run)
   e.groupPolicyBlocked=allowed==nil and "GROUP_KEEP_UNKNOWN" or nil
   if allowed==nil then return end
   if allowed==false then
    local stop=run.group.exit=="stop"
    self:Restore(e,"GROUP_KEEP_ENDED",true)
    if stop then T.Runtime:Stop("GROUP_KEEP_STOPPED") end
    return
   end
  end
  if e.completed then
   if run.round<run.group.rounds then
    if not T.Runtime:ReplaceRecommendation(run.group.steps) then return end
    run.round=run.round+1; e.completed=false; e.index=1; e.stepCasts=0
    e.skipStreak=0; e.policySkipStreak=0; e.attackActivationStreak=0
    e:Log("observed","GROUP_NEXT_ROUND")
   else self:Restore(e,"GROUP_FINISHED",true) end
  end
  return
 end
 if T.Recommendation:BaseSource(e)=="manual" then
  local row=e.steps and e.steps[e.index]
  if row and row.group then
   local allowed,why=T.Dispatch:ManualPolicy(e,row,true,true)
   if allowed==true then self:Begin(e,row,"manual")
   elseif allowed==false and not e:RecommendationLocked() then
    local prior=T.Runtime.internal; T.Runtime.internal=true; e:SkipUnavailable("STRATEGY_STEP_SKIPPED"); T.Runtime.internal=prior
   end
  end
 elseif e.aplCandidate then
  local rows=T.APL.Custom:Rows(e); local row=rows[e.aplCandidate.customIndex]
  if row and row.group and T.APL:Allowed(e,e.aplCandidate.spellID)==true then self:Begin(e,row,"apl") end
 end
end
function G:KeepAllowed(e,run)
 local now=T.APL.State.Time(); local old=e.groupKeepSnapshot
 if old and now and old.sampledAt and now>=old.sampledAt and now-old.sampledAt<(T.APL.State.dirty and .05 or .20)
  and old.generation==e.generation and old.receiptSerial==(e.receiptSerial or 0) and old.revision==(T.APL.State.revision or 0) then return old.result end
 local row={spellID=run.row.spellID,enabled=true,strategies=run.row.strategies,moving="any",activity="any",cdmKind="none"}
 local state={sampledAt=now,generation=e.generation,receiptSerial=e.receiptSerial or 0,revision=T.APL.State.revision or 0,
  actions={},moving=T.APL.State.Boolean("IsPlayerMoving")}
 T.APL.Custom:Sample(e,state,{row})
 if state.generation~=e.generation or state.receiptSerial~=(e.receiptSerial or 0) or state.revision~=(T.APL.State.revision or 0) then return nil end
 state.result=T.APL.Custom:CheckStrategies(state,row,1); e.groupKeepSnapshot=state
 return state.result
end
function G:Admission(state,row,index)
 if row.behavior then return true end
 local e=T.engine
 if not row.group or not e or not e.groupConsumed or not e.groupConsumed[row] then return true end
 if state.readOnly then return false end
 local allowed=T.APL.Custom:CheckStrategies(state,row,index)
 if allowed==false then e.groupConsumed[row]=nil; return false end
 return false
end
