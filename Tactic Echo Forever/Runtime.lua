local _,TEF=...
local S,C=TEF.Safety,{intent=false,state="paused",requestSerial=0,cycle=0}
TEF.Runtime=C
local modes={auto=true,manual=true,stop=true}
local names={paused="暂停",standby="待命",running="运行",blocked="阻断",completed="完成",error="异常"}
function C:PlayIntentSound(enabled)
    local file=enabled and "te-armed-123.wav" or "te-paused-321.wav"
    S.Call("PlaySoundFile","Interface\\AddOns\\Tactic Echo Forever\\Media\\" .. file,"SFX")
end
function C.Clean(raw)
    local mode=S.Field(raw,"mode","string")
    local key=S.Field(raw,"hotkey","string")
    local lead=S.Field(raw,"castQueueLead","number")
    local ordinary,ordinaryReason=S.Field(raw,"ordinaryContinuous","boolean")
    return {mode=modes[mode] and mode or "auto",autoStart=S.Field(raw,"autoStart","boolean")~=false,
        permission=S.Field(raw,"permission","boolean")~=false,signal=S.Field(raw,"signal","boolean")~=false,
        takeover=S.Field(raw,"takeover","string")=="pause" and "pause" or "continue",
        hotkey=key and #key<=40 and key:match("^[A-Z0-9%-=]+$") and key or "",
        ordinaryContinuous=ordinary==true or ordinaryReason=="NO_DATA",
        castQueue=S.Field(raw,"castQueue","boolean")==true,
        castQueueLead=lead and math.max(0,math.min(.5,lead)) or .2}
end
function C:SetLoopMode(mode)
    if mode~="none" and mode~="normal" and mode~="target" and mode~="combat" then return false end
    self:Stop("RUNTIME_LOOP_CONFIGURATION_CHANGED")
    self.e:SetLoopMode(mode); self:EngineCall("Reset"); return true
end
function C:ResetCycle(reason)
    -- Reset through the sole runtime owner: preserve intention, invalidate all
    -- old receipts/requests, and let live gates decide when execution resumes.
    local usage=self.e.usage
    local records,count,context=self.e.policyRecords,self.e.policyRecordCount,self.e.policyContext
    if not self:EngineCall("Reset") then return false end
    self.e.usage,self.e.usageProgress=usage,nil
    self.e.policyRecords,self.e.policyRecordCount,self.e.policyContext=records,count,context
    self:Changed("paused",reason); return true
end
function C:Changed(state,reason)
    local changed=self.state~=state or self.reason~=reason
    self.state,self.reason=state,reason
    if not changed then return end
    local step=self.e.steps and self.e.steps[self.e.index]
    self.e:Log("transport",reason,step and step.spellID)
    if self.notifying then return end
    self.notifying=true
    if TEF.HUD and TEF.HUD.engine==self.e then pcall(TEF.HUD.RefreshState,TEF.HUD) end
    if TEF.UI and TEF.UI.engine==self.e and TEF.UI.settingsOpen and TEF.UI.readouts then pcall(TEF.UI.RefreshPage,TEF.UI) end
    self.notifying=false
end
function C:EngineCall(method)
    if method=="Reset" and self.e.groupRun then TEF.SkillGroups:Restore(self.e,"GROUP_RESET") end
    if method=="Reset" and self.e.maintenanceActive then TEF.Maintenance:Restore(self.e,"MAINTENANCE_RESET") end
    self.internal=true
    local ok=pcall(self.e[method],self.e)
    self.internal=false
    if not ok then
        -- Last-resort containment belongs to Runtime, never to presentation.
        self.intent=false; self.e.running=false
        self.e.generation=self.e.generation+1; self.e.associations={}; self.e.associationCount=0
        TEF.Dispatch:StopContinuous("RUNTIME_ENGINE_FAILED"); TEF.Dispatch:Cancel("RUNTIME_ENGINE_FAILED")
        self:Changed("error","RUNTIME_ENGINE_FAILED")
    end
    return ok
end
function C:ReplaceRecommendation(rows)
    self.internal=true
    local ok,result=pcall(self.e.ReplaceRecommendation,self.e,rows)
    self.internal=false
    if not ok then self:Fault("RUNTIME_ENGINE_FAILED"); return false end
    return result
end
function C:Initialize(e)
    self.maintenanceManual=false
    self.e=e; self.intent=false; self.worldSeen=false; self.state="paused"
    self.reason=nil; self.displayBlock=nil; self.cycle=0; self.requestSerial=0
    e.db.dispatch=self.Clean(e.db.dispatch)
    TEF.Dispatch:SetEnabled(e.db.dispatch.permission)
end
function C:Invalidated(e)
    -- Explicit edits/reset and the retained developer Engine API stop intent.
    if e==self.e and not self.internal then
        self.maintenanceManual=false
        if e.maintenanceActive then TEF.Maintenance:Restore(e,"MAINTENANCE_INVALIDATED") end
        if e.groupRun then TEF.SkillGroups:Restore(e,"GROUP_INVALIDATED") end
        e.groupConsumed={}
        self.intent=false; self:Changed("paused","RUNTIME_CONFIGURATION_INVALIDATED")
    end
end
function C:Stop(reason,state)
    self.maintenanceManual=false
    if self.e.maintenanceActive then TEF.Maintenance:Restore(self.e,"MAINTENANCE_STOPPED") end
    if self.e.groupRun and reason~=nil and reason~="USER_TOGGLE_DISPATCH" and reason~="RUNTIME_MANUAL_PAUSE" and reason~="MANUAL_TAKEOVER_PAUSED" then TEF.SkillGroups:Restore(self.e,"GROUP_STOPPED") end
    self.e.groupConsumed={}
    local wasEnabled=self.intent
    self.intent=false
    if wasEnabled then self:PlayIntentSound(false) end
    if not self:EngineCall("Pause") then return end
    TEF.Dispatch:StopContinuous(reason or "RUNTIME_MANUAL_PAUSE")
    TEF.Dispatch:Cancel(reason or "RUNTIME_MANUAL_PAUSE")
    self:Changed(state or "paused",reason or "RUNTIME_MANUAL_PAUSE")
end
function C:Fault(reason) self:Stop(reason or "RUNTIME_FATAL_ERROR","error") end
function C:OnDispatchFault(reason)
    -- A game failure yields the ordinary candidate; only fatal errors stop intent.
    if self.e~=TEF.engine then return end
    if reason=="CONTINUOUS_FAILURE_STOP" then self:Suspend("CONTINUOUS_FAILURE_RETRY")
    else self:Fault(reason) end
end
function C:Suspend(reason,state)
    if not self.e then return end
    local detail=TEF.Dispatch:BlockDetail(reason)
    if self.e.running and not self:EngineCall("Pause") then return end
    self.displayBlock=detail and {engine=self.e,generation=self.e.generation,index=self.e.index,serial=self.e.receiptSerial or 0,reason=reason,
        title=detail.title,description=detail.description,unknown=detail.unknown} or nil
    TEF.Dispatch:StopContinuous(reason); TEF.Dispatch:Cancel(reason)
    self:Changed(self.intent and (state or "blocked") or "paused",reason)
end
-- 仅用户手动开启且选择手动启停时授予普通来源脱战资格。
function C:OutsideCombatAllowed(e)
 return self.e==e and TEF.engine==e and self.intent==true and self.maintenanceManual==true and e.db.dispatch.mode=="manual"
end
function C:CombatAllowed(e,combat)
 return combat==true or (combat==false and (self:OutsideCombatAllowed(e) or TEF.Maintenance:OutsideAllowed(e)))
end
function C:SetIntent(enabled,reason)
    if enabled~=true then self:Stop(reason); return true end
    self.maintenanceManual=reason~="RUNTIME_AUTO_WORLD"
    if self.intent then return true,"RUNTIME_ALREADY_ENABLED" end
    self.e.maintenanceDone={}; self.e.maintenanceSnapshot=nil
    if self.e.identitySaturated then self:Fault("RUNTIME_IDENTITY_CAPACITY_RELOAD_REQUIRED"); return false end
    if self.e.clientValidated==false then self:Fault("RUNTIME_CLIENT_UNVERIFIED"); return false end
    if not TEF.Recommendation:Configured(self.e) and not TEF.Maintenance:Enabled(self.e) then self:Stop("RUNTIME_PROFILE_UNCONFIGURED"); return false end
    if self.e.completed and not self:ResetCycle("RUNTIME_COMPLETION_RESTART") then return false end
    self.intent=true
    if self.e.db.dispatch.signal and not TEF.Transport.enabled then
        if not TEF.Transport:SetEnabled(true) then self:Fault("RUNTIME_SIGNAL_FAILED"); return false end
    end
    self:Changed("standby",reason or "RUNTIME_ENABLED")
    self:Reconcile()
    if self.intent then self:PlayIntentSound(true) end
    return self.intent
end
function C:ToggleIntent(reason) return self:SetIntent(not self.intent,reason) end
-- 人工操作通过Runtime撤销旧身份；跳过不等于成功，不写成功额度。
function C:Intervene(action)
 local e=self.e
 if not e or TEF.UI.settingsOpen or e:RecommendationLocked() or e.maintenanceActive then return false,"请关闭设置，并等待当前施法及回执结束。" end
 if action=="endgroup" then
  if not e.groupRun then return false,"当前没有活动技能组。" end
  TEF.SkillGroups:Restore(e,"GROUP_USER_ENDED",true)
 elseif action=="restartgroup" then
  local run=e.groupRun; if not run then return false,"当前没有活动技能组。" end
  if not self.intent then return false,"派发已暂停；请先继续，再重新开始技能组。" end
  local row=run.row
  local probe={spellID=row.spellID,group=row.group,enabled=row.enabled~=false,strategies=row.strategies,behavior=row.behavior,targetMode=row.targetMode,
   moving=row.moving or "any",activity=row.activity or "any",distanceOp=row.distanceOp or "any",distanceValue=row.distanceValue,cdmKind=row.cdmKind or "none",cdmState=row.cdmState,cdmSpellID=row.cdmSpellID}
  local state={readOnly=true,policyOwner=row,generation=e.generation,receiptSerial=e.receiptSerial or 0,revision=TEF.APL.State.revision or 0,
   actions={},moving=TEF.APL.State.Boolean("IsPlayerMoving")}
  TEF.APL.Custom:Sample(e,state,{probe})
  if state.combat.in_combat~=true or TEF.APL.Custom:Check(state,probe,1)~=true then return false,"当前组入口条件未满足或未知。" end
  if e.groupRun~=run or e.generation~=state.generation or (e.receiptSerial or 0)~=state.receiptSerial or (TEF.APL.State.revision or 0)~=state.revision or e:RecommendationLocked() then return false,"状态已变化，请重新操作。" end
  if not self:ReplaceRecommendation(run.group.steps) then return false,"无法重新开始当前组。" end
  run.round=1; run.successful=nil; run.policyStamp=TEF.APL.Custom:PolicyStamp(e,row)
  local ok,raw=TEF.Safety.Call("UnitGUID","target"); run.target=ok and TEF.Safety.Identity(raw) or nil; run.targetSerial=e.usageTargetSerial or 0
  e.groupKeepSnapshot=nil; e.groupPolicyBlocked=nil; e.skipStreak=0; e.policySkipStreak=0; e.attackActivationStreak=0
  e:Log("observed","GROUP_USER_RESTARTED")
 elseif action=="skip" then
  if TEF.Recommendation:Source(e)~="manual" or not e.steps or not e.steps[e.index] or e.steps[e.index].group then return false,"仅支持跳过当前普通列表步骤；技能组请使用结束组。" end
  self.internal=true
  local ok,result=pcall(e.SkipUnavailable,e,"STRATEGY_STEP_SKIPPED")
  self.internal=false
  if not ok then self:Fault("RUNTIME_INTERVENTION_FAILED"); return false,"人工操作失败，已停止。" end
  if not result then return false,"当前步骤无法跳过。" end
  e:Log("observed","USER_STEP_SKIPPED")
 elseif action=="recheck" then
  if e.groupRun then TEF.SkillGroups:Restore(e,"GROUP_USER_RECHECK",true) end
  if TEF.Recommendation:Source(e)=="manual" then
   self.internal=true; e:Invalidate("USER_RECHECK"); self.internal=false
  elseif not self:ReplaceRecommendation(nil) then return false,"重新判断失败。" end
  TEF.APL:Invalidate(); e.aplSnapshot=nil
 else return false,"未知人工操作。" end
 self:Reconcile(); return true,"操作完成；未记作技能成功。"
end
function C:ObserveTakeover(e,event,id)
 if self.e~=e or not self.intent or event~="UNIT_SPELLCAST_SENT" or not e.steps or not e.steps[e.index] or e.steps[e.index].matches[id] then return end
 e:Log("observed","MANUAL_OTHER_SPELL_OBSERVED",id)
 if e.db.dispatch.takeover=="pause" then self:Stop("MANUAL_TAKEOVER_PAUSED") end
end
function C:Start(reset)
    if reset then self:Stop("RUNTIME_RESTART"); if not self:EngineCall("Reset") then return false end end
    return self:SetIntent(true)
end
function C:Reset()
    self:Stop("RUNTIME_RESET")
    if self.state=="error" or not self:EngineCall("Reset") then return end
    self:Changed("paused","RUNTIME_RESET")
end
function C:SetCastQueue(value)
    self:Stop("CAST_QUEUE_SETTING_CHANGED")
    self.e.db.dispatch.castQueue=value==true
    return true
end
function C:SetCastQueueLead(value)
    local lead=S.Public(value,"number")
    if not lead or lead<0 or lead>.5 then return false end
    self:Stop("CAST_QUEUE_SETTING_CHANGED")
    self.e.db.dispatch.castQueueLead=lead
    return true
end
function C:SetMode(mode)
    if not modes[mode] then return false end
    self.e.db.dispatch.mode=mode; self:Reconcile(); return true
end
function C:SetPermission(value)
    self.e.db.dispatch.permission=value==true
    if value~=true then self:Stop("RUNTIME_PERMISSION_OFF") end
    TEF.Dispatch:SetEnabled(value); self:Reconcile(); return true
end
function C:SetSignal(value)
    self.e.db.dispatch.signal=value==true
    if value~=true then self:Stop("RUNTIME_SIGNAL_OFF") end
    local ok=TEF.Transport:SetEnabled(value)
    if not ok then self:Fault("RUNTIME_SIGNAL_FAILED") end
    self:Reconcile(); return ok
end
function C:World()
    TEF.Dispatch.channelInputLock=nil
    local first=not self.worldSeen; self.worldSeen=true
    self.e:ClearUsage()
    self:Stop("RUNTIME_WORLD_INVALIDATED")
    if first and self.e.db.dispatch.autoStart then self:SetIntent(true,"RUNTIME_AUTO_WORLD") end
end
function C:TryConfirmAttackEnabled()
    local policy=TEF.Dispatch:ManualPolicy(self.e,self.e.steps and self.e.steps[self.e.index])
    if policy~=true then return false end
    local e=self.e; local step=e.steps and e.steps[e.index]
    if not self.intent or not step or step.spellID~=6603 or TEF.Recommendation:Source(e)~="manual"
        or (e.attackActivationStreak or 0)>=#e.steps then return false end
    local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
    if not TEF.Dispatch:AttackEnabled() then return false end
    if not self.intent or self.e~=e or TEF.engine~=e or e.generation~=generation or e.index~=index or (e.receiptSerial or 0)~=serial then return false end
    if not e.running then
        if not self:EngineCall("Resume") or not self.intent or not TEF.Dispatch:AttackEnabled() then return false end
        generation=e.generation
    end
    if not self.intent or self.e~=e or TEF.engine~=e or e.index~=index or (e.receiptSerial or 0)~=serial or e.generation~=generation then return false end
    self.internal=true
    local ok,confirmed=pcall(e.ConfirmAttackEnabled,e,generation,index,serial)
    self.internal=false
    if not ok then self:Fault("ATTACK_CONFIRM_FAILED"); return true end
    if confirmed then
        if e.completed and e.groupRun then TEF.SkillGroups:Refresh(e); self:Changed("blocked","GROUP_STEP_FINISHED")
        elseif e.completed then self:Stop("RUNTIME_COMPLETED","completed")
        else self:Changed("running","ATTACK_ENABLE_CONFIRMED") end
    end
    return confirmed
end
function C:Reconcile()
    if not self.e or self.e~=TEF.engine then return end
    self.cycle=self.cycle+1
    TEF.APL.State.SampleResources(self.e)
    self.e:ObserveUsageCombat()
    TEF.APL.Custom:LifecycleContext(self.e)
    if not self.intent then return end
    local e=self.e
    TEF.APL.Custom:ReconcilePolicyProgress(e)
    TEF.SkillGroups:Refresh(e)
    TEF.Maintenance:Refresh(e)
    if e.identitySaturated then self:Fault("RUNTIME_IDENTITY_CAPACITY_RELOAD_REQUIRED"); return end
    if TEF.APL:IsActive(e) and not TEF.UI.settingsOpen then TEF.APL:Refresh(e) end
    TEF.SkillGroups:Refresh(e)
    local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
    local function current() return self.intent and self.e==e and TEF.engine==e and generation==e.generation and index==e.index and serial==(e.receiptSerial or 0) end
    if e.completed and e.groupRun then
        -- 引导成功可发生在起始；等公开读条/引导消失再由组推进轮数。
        TEF.Dispatch:YieldCast("GROUP_WAIT_STEP_FINISH"); self:Changed("blocked","GROUP_WAIT_STEP_FINISH"); return
    end
    if e.completed then
        if TEF.Maintenance:Enabled(e) and (self.maintenanceManual or TEF.APL.State.Boolean("InCombatLockdown")==true) then self:Suspend("MAINTENANCE_IDLE","standby")
        else self:Stop("RUNTIME_COMPLETED","completed") end
        return
    end
    if not e.db.dispatch.permission or not e.db.dispatch.signal then self:Stop("RUNTIME_GATE_OFF"); return end
    if not TEF.Recommendation:Configured(e) then
        if TEF.Maintenance:Enabled(e) and self.maintenanceManual then self:Suspend("MAINTENANCE_IDLE","standby")
        else self:Suspend("RUNTIME_PROFILE_UNCONFIGURED") end
        return
    end
    local ok,raw=S.Call("InCombatLockdown"); local combat
    if ok then combat=S.Public(raw,"boolean") end
    if not current() then return end
    local maintenanceOutside=combat==false and self.maintenanceManual and TEF.Maintenance:Enabled(e)
    if e.db.dispatch.mode=="stop" and combat==false and not maintenanceOutside
        and not (e.groupRun and TEF.Dispatch:HasCurrentInitiation()) then self:Stop("RUNTIME_OUT_OF_COMBAT_STOP"); return end
    if TEF.UI.settingsOpen then self:Suspend("RUNTIME_SETTINGS_STANDBY","standby"); return end
    if combat==nil then self:Suspend("RUNTIME_COMBAT_UNKNOWN"); return end
    if e.groupRun and not e.maintenanceActive and combat~=true then
        if TEF.Dispatch:HasCurrentInitiation() then
            TEF.Dispatch:YieldCast("GROUP_COMBAT_REQUIRED"); self:Changed("standby","GROUP_COMBAT_REQUIRED")
        else self:Suspend("GROUP_COMBAT_REQUIRED","standby") end
        return
    end
    if e:HasUsagePolicy() then
        self.internal=true
        local prepared,allowed,reason=pcall(e.PrepareUsage,e)
        self.internal=false
        if not prepared then self:Fault("SEQUENCE_USAGE_FAILED"); return end
        if not current() then return end
        if not allowed then self:Suspend(reason); return end
    end
    if maintenanceOutside and not e.maintenanceActive and not self:OutsideCombatAllowed(e) then self:Suspend("MAINTENANCE_IDLE","standby"); return end
    if e.db.dispatch.mode=="auto" and combat==false and not TEF.Maintenance:OutsideAllowed(e) then
        if TEF.Recommendation:Source(e)=="manual" then
            -- 待命保留固定序列的精确回执监听，输入仍由派发门禁控制。
            -- 不反复恢复或暂停，避免清除手动起手跨进战斗的身份。
            if not e.running and not self:EngineCall("Resume") then return end
            TEF.Dispatch:StopContinuous("RUNTIME_AUTO_STANDBY")
            TEF.Dispatch:Cancel("RUNTIME_AUTO_STANDBY")
            if self:TryConfirmAttackEnabled() and e.completed then return end
            if not self.intent or self.e~=e or TEF.engine~=e then return end
            self:Changed("standby","RUNTIME_AUTO_STANDBY")
        else self:Suspend("RUNTIME_AUTO_STANDBY","standby") end
        return
    end
    if TEF.Recommendation:Source(e)=="manual" then
        local step=e.steps and e.steps[e.index]
        if step and (step.enabled==false or (step.strategies and #step.strategies>0) or (step.targetMode and step.targetMode~="auto")) and not TEF.Dispatch:InputIdle() then
            if e:RecommendationLocked() then TEF.Dispatch:YieldCast("CONTINUOUS_TEXT_FOCUS_OR_UNKNOWN"); self:Changed("blocked","CONTINUOUS_TEXT_FOCUS_OR_UNKNOWN")
            else self:Suspend("CONTINUOUS_TEXT_FOCUS_OR_UNKNOWN") end
            return
        end
        local allowed,reason=TEF.Dispatch:ManualPolicy(e,step)
        if not current() then return end
        if allowed~=true and e:RecommendationLocked() then
            TEF.Dispatch:YieldCast("SEQUENCE_POLICY_WAIT_RECEIPT"); self:Changed("blocked","SEQUENCE_POLICY_WAIT_RECEIPT"); return
        end
        if allowed~=true then
            if allowed==nil then self:Suspend(reason or "SEQUENCE_POLICY_UNKNOWN"); return end
            TEF.Dispatch:Cancel(reason or "SEQUENCE_POLICY_UNMATCHED")
            self.internal=true; local ok,skipped=pcall(e.SkipUnavailable,e,"STRATEGY_STEP_SKIPPED"); self.internal=false
            if not ok then self:Fault("SEQUENCE_POLICY_SKIP_FAILED")
            elseif not skipped then
                local now=TEF.APL.State.Time()
                local sample=self.policyRecovery
                local recover=now and (not sample or sample.engine~=e or now<sample.at or now-sample.at>=.20)
                if recover then
                    self.policyRecovery={engine=e,at=now}
                    for candidate,other in ipairs(e.steps) do
                        local eligible=TEF.Dispatch:ManualPolicy(e,other,true)
                        if not current() then return end
                        if eligible==true then
                            self.internal=true; local ok=pcall(e.Invalidate,e,"SEQUENCE_POLICY_RECOVERED"); self.internal=false
                            if not ok then self:Fault("SEQUENCE_POLICY_RECOVERY_FAILED"); return end
                            e.index=candidate; e.stepCasts=0; e.policySkipStreak=0
                            self:Changed("blocked","SEQUENCE_POLICY_RECOVERED"); return
                        end
                    end
                end
                self:Suspend("SEQUENCE_POLICY_ALL_BLOCKED")
            elseif e.completed then
                if e.groupRun then TEF.SkillGroups:Refresh(e); self:Changed("blocked","GROUP_STEP_SKIPPED")
                elseif TEF.Maintenance:Enabled(e) and (self.maintenanceManual or combat==true) then self:Suspend("MAINTENANCE_IDLE","standby") else self:Stop("RUNTIME_COMPLETED","completed") end
            else self:Changed("blocked","STRATEGY_STEP_SKIPPED") end
            return
        end
        if allowed==true then e.policySkipStreak=0 end
    end
    if self:TryConfirmAttackEnabled() then return end
    if not current() then return end
    -- Keep the already initiated receipt while showing a cast block. Pausing
    -- the Engine here would erase its initiation and lose SUCCEEDED (S61).
    local ordinary=TEF.Dispatch:OrdinaryContinuous()
    local idle=TEF.Dispatch:TransportCastAllowed(true)
    if not current() then return end
    if not idle then
        if combat==true and TEF.Dispatch:CastQueueWindow() then
            self:Changed("running","CAST_QUEUE_WINDOW"); return
        end
        TEF.Dispatch:YieldCast("CONTINUOUS_CAST_PRESENT_OR_UNKNOWN")
        self:Changed("blocked","CONTINUOUS_CAST_PRESENT_OR_UNKNOWN"); return
    end
    if not ordinary and TEF.Recommendation:Source(e)=="manual" and not TEF.Dispatch:HasCurrentInitiation()
        and e:RecommendationLocked() then
        -- 手动起手的回执可能早于客户端公开读条；先等该次结果。
        TEF.Dispatch:YieldCast("MANUAL_WAIT_CURRENT_RECEIPT")
        self:Changed("blocked","MANUAL_WAIT_CURRENT_RECEIPT"); return
    end
    if not ordinary and TEF.APL:IsActive(e) and TEF.Dispatch:HasCurrentInitiation() then
        -- SENT may precede visible cast presence, and SUCCEEDED can precede
        -- cast disappearance. A dirty APL snapshot must not erase its receipt.
        TEF.Dispatch:YieldCast("APL_WAIT_CURRENT_RECEIPT")
        self:Changed("blocked","APL_WAIT_CURRENT_RECEIPT"); return
    end
    if not TEF.Recommendation:Current(e) then self:Suspend("APL_NO_CANDIDATE"); return end
    local allowed,reason=TEF.Dispatch:ContinuousEvidence(e.steps[e.index].spellID)
    if not current() then return end
    local step=e.steps[e.index]
    if step.skipUnavailable and step.spellID~=5019 and step.spellID~=6603 and step.spellID~=75 and TEF.Recommendation:Source(e)=="manual"
        and (allowed or reason=="CONTINUOUS_USABLE_UNKNOWN_OR_BLOCKED") then
        -- Focus/target/range and cast gates precede omission; an in-flight
        -- initiation always owns its receipt, even if resources changed.
        if e:RecommendationLocked() and not ordinary then
            TEF.Dispatch:YieldCast("SKIP_WAIT_CURRENT_RECEIPT")
            self:Changed("blocked","SKIP_WAIT_CURRENT_RECEIPT"); return
        end
        if not e:RecommendationLocked() and not TEF.Dispatch.pending and TEF.Dispatch.waitReceipt~=(e.receiptSerial or 0) then
            local unavailable=TEF.Dispatch:Unavailable(step.spellID)
            if not current() then return end
            if unavailable==nil then self:Suspend("SKIP_AVAILABILITY_UNKNOWN"); return end
            if unavailable then
                self.internal=true
                local skippedOK,skipped=pcall(e.SkipUnavailable,e)
                self.internal=false
                if not skippedOK then self:Fault("SKIP_ENGINE_FAILED")
                elseif not skipped then self:Suspend("SKIP_ALL_UNAVAILABLE")
                elseif e.completed and e.groupRun then TEF.SkillGroups:Refresh(e); self:Changed("blocked","GROUP_STEP_SKIPPED")
                elseif e.completed then self:Stop("RUNTIME_COMPLETED","completed")
                else self:Changed("blocked","UNAVAILABLE_STEP_SKIPPED") end
                return
            end
            e.skipStreak=0
        end
    end
    if not allowed then self:Suspend(reason); return end
    if TEF.Dispatch.bindingCache[e.steps[e.index].spellID]==false then self:Suspend("TEK_EXACT_DIRECT_BINDING_UNAVAILABLE"); return end
    if not e.running and not self:EngineCall("Resume") then return end
    if not TEF.Dispatch.enabled then TEF.Dispatch:SetEnabled(true) end
    if not TEF.Dispatch.continuous then
        if not TEF.Dispatch:SetContinuous(true) then self:Fault("RUNTIME_DISPATCH_START_FAILED"); return end
    end
    self:Changed("running","RUNTIME_RUNNING")
end
function C:DisplayBlockDetail(reason)
    local d,e=self.displayBlock,self.e
    if d and e and d.engine==e and d.generation==e.generation and d.index==e.index and d.serial==(e.receiptSerial or 0) and d.reason==reason then return d end
end
function C:GetViewState()
    local e=self.e
    local source=e and TEF.Recommendation:Source(e) or "manual"
    return {intent=self.intent,state=self.state,label=names[self.state] or "未知",reason=self.reason,
        detail=self:DisplayBlockDetail(self.reason),profileKey=e and e.profileKey or "职业未解析",source=source,index=e and e.index or 1,
        count=e and e.steps and #e.steps or 0}
end
function C:IsDispatchIntentEnabled() return self.intent end
function C:View()
    local v=self:GetViewState()
    return v.label .. " | " .. (v.source=="apl" and "优先级推荐" or v.profileKey) .. " | " .. (v.source=="apl" and "优先级推荐" or "列表循环")
end
-- Internal compatibility, no additional public toggle or execution loop.
C.Tick=C.Reconcile
C.Toggle=C.ToggleIntent
