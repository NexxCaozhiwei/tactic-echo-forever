local _, TEF = ...
local D,S={},TEF.Safety
TEF.Dispatch=D
D.enabled=false
-- Runtime-only opt-in; no timer estimates, persisted arm state or second transport.
D.continuous=false
-- Independent bounded evidence only; never read by queue/dispatch admission.
function D:TraceQueue(reason,event,id,guid,queue)
    local e=TEF.engine
    if not e or not e.db.dispatch or (not e.db.dispatch.castQueue and not e.db.dispatch.ordinaryContinuous) then return end
    local q=queue or self.castQueue or (self.pending and self.pending.castQueue)
    local ok,clock=S.Call("GetTime")
    local row={reason=S.Public(reason,"string"),event=S.Public(event,"string"),spellID=S.ID(id),guid=S.Identity(guid),
        session=e.session,generation=e.generation,version=TEF.Version,index=e.index,count=e.stepCasts or 0,
        receiptSerial=e.receiptSerial or 0,cycle=TEF.Runtime.cycle,request=TEF.Runtime.requestSerial,
        time=ok and S.Public(clock,"number"),lead=S.Field(e.db.dispatch,"castQueueLead","number"),
        source=q and "queue" or "ordinary",windowReason=self.queueWindowReason,
        currentGUID=self.initiation and S.Identity(self.initiation.guid),loopMode=e.db.loopMode}
    if q then
        row.originGUID=S.Identity(q.originGUID); row.queuedGUID=S.Identity(q.guid)
        row.queueRequest=q.request; row.queueIndex=q.index; row.nextIndex=q.nextIndex
        row.queueSpellID=q.spellID; row.queueSerial=q.receiptSerial
        row.clientWindow=q.clientWindow; row.remaining=q.remaining; row.effectiveLead=q.effectiveLead
    end
    local rows=e.db.queueDiagnostics
    if not rows then rows={}; e.db.queueDiagnostics=rows end
    if #rows>=512 then table.remove(rows,1); e.db.queueEvicted=(e.db.queueEvicted or 0)+1 end
    rows[#rows+1]=row
end
function D:StopContinuous(reason)
    self:DropCastQueue(); self.castQueueAttempt=nil
    local active=self.continuous
    self.continuous=false; self.continuousGeneration=nil; self.waitReceipt=nil; self.continuousBinding=nil; self.initiation=nil
    self.continuousReason=reason or "CONTINUOUS_OFF"
    if active then
        TEF.engine:Log("transport",self.continuousReason)
    end
end
function D:ContinuousStatus(reason)
    if self.continuousReason~=reason then
        self.continuousReason=reason; TEF.engine:Log("transport",reason)
    end
end
function D:Block(reason)
    self:StopContinuous(reason); self:Cancel(reason)
    if TEF.Runtime and TEF.Runtime.e==TEF.engine and TEF.Runtime.intent then TEF.Runtime:Suspend(reason) end
end
function D:SetContinuous(value)
    self:Cancel("TEK_CONTINUOUS_CHANGED")
    if value~=true then self:StopContinuous(); return true end
    local e=TEF.engine
    if not self.enabled or not e.running or e.completed or TEF.UI.settingsOpen then
        self:StopContinuous("CONTINUOUS_START_BLOCKED"); return false
    end
    self.continuous=true; self.continuousGeneration=e.generation
    self.waitReceipt=nil; self.continuousReason=nil; self.continuousBinding=nil
    self:ContinuousStatus("CONTINUOUS_ON")
    return true
end
local function publicBoolean(path,...)
    local ok,value=S.Call(path,...)
    if not ok then return nil end
    return S.Public(value,"boolean")
end
local function rangeBoolean(raw)
    local value,reason=S.Public(raw,"boolean")
    if reason=="UNKNOWN_TYPE" then
        local number=S.Public(raw,"number")
        if number==0 then return false,"PUBLIC" end
        if number==1 then return true,"PUBLIC" end
    end
    return value,reason
end
function D:ActionRange(id)
    local binding=self:ResolveCached(id)
    if not binding or not self:VerifyCurrent(binding) then return nil end
    local path=S.Resolve("C_ActionBar.IsActionInRange") and "C_ActionBar.IsActionInRange" or "IsActionInRange"
    local ok,raw=S.Call(path,binding.slot,"target")
    if ok then return rangeBoolean(raw) end
end
function D:InputIdle()
    local path=S.Resolve("GetCurrentKeyBoardFocus") and "GetCurrentKeyBoardFocus" or "GetCurrentKeyboardFocus"
    local ok,raw=S.Call(path)
    if not ok then return false end
    local _,classification=S.Public(raw,"table")
    -- Any focused object, restricted result or unknown detector blocks input.
    return classification=="NO_DATA"
end
function D:IsSelfAction(id)
    local e=TEF.engine; local c=e.aplCandidate
    if TEF.APL and TEF.APL:IsActive(e) and c and c.spellID==id then
        return c.target=="self" or c.target=="ground" or (TEF.APL.Abilities[c.action] and TEF.APL.Abilities[c.action].target=="self") or false
    end
    local policy=self.manualPolicySnapshot
    if TEF.Recommendation:Source(e)=="manual" and policy and policy.engine==e and policy.step.spellID==id and policy.state.generation==e.generation then
        local action=policy.state.actions.custom_1
        return action and (action.target=="self" or action.target=="ground") or false
    end
    -- 自身目标分类必须由公开元数据确认；不从缺少敌方范围推断。
    local ok,info=S.Call("C_Spell.GetSpellInfo",id)
    local min,minReason,max,maxReason
    if ok then
        min,minReason=S.Field(info,"minRange","number")
        max,maxReason=S.Field(info,"maxRange","number")
    end
    if (min==nil or max==nil) and minReason~="SECRET" and maxReason~="SECRET" then
        local fn=S.Resolve("GetSpellInfo")
        if fn then
            local read,_,__,___,____,rawMin,rawMax,rawID=pcall(fn,id)
            if read and S.ID(rawID)==id then
                min=S.Public(rawMin,"number"); max=S.Public(rawMax,"number")
            end
        end
    end
    if min~=0 or max~=0 then return false end
    local helpful=S.Resolve("C_Spell.IsSpellHelpful") and "C_Spell.IsSpellHelpful" or "IsHelpfulSpell"
    local harmful=S.Resolve("C_Spell.IsSpellHarmful") and "C_Spell.IsSpellHarmful" or "IsHarmfulSpell"
    return publicBoolean(helpful,id)==true and publicBoolean(harmful,id)==false
end
function D:ManualPolicy(e,step,live)
    if TEF.Recommendation:Source(e)~="manual" then return true end
    if TEF.Maintenance:Owns(e,step and step.spellID) then return false,"MAINTENANCE_OWNS_SPELL" end
    if not step then return nil,"SEQUENCE_POLICY_STEP_UNKNOWN" end
    if step.enabled==false then return false,"SEQUENCE_POLICY_DISABLED" end
    if not step.strategies or #step.strategies==0 then
        if not step.targetMode or step.targetMode=="auto" then return true end
    end
    local now=TEF.APL.State.Time(); local revision=TEF.APL.State.revision or 0
    local cached=self.manualPolicySnapshot
    if not live and cached and cached.engine==e and cached.step==step and cached.state.generation==e.generation and cached.state.receiptSerial==(e.receiptSerial or 0)
        and cached.state.revision==revision and now and cached.state.sampledAt and now>=cached.state.sampledAt and now-cached.state.sampledAt<.05 then
        return cached.allowed,cached.reason
    end
    local row={spellID=step.spellID,enabled=true,moving="any",activity="any",distanceOp="any",cdmKind="none",strategies=step.strategies,targetMode=step.targetMode}
    local state={generation=e.generation,receiptSerial=e.receiptSerial or 0,revision=revision,sampledAt=now,scene=e.scene,actions={},moving=TEF.APL.State.Boolean("IsPlayerMoving")}
    local index=e.index
    TEF.APL.Custom:Sample(e,state,{row})
    if state.generation~=e.generation or state.receiptSerial~=(e.receiptSerial or 0) or index~=e.index or revision~=(TEF.APL.State.revision or 0) then return nil,"SEQUENCE_POLICY_STALE" end
    local allowed,reason=TEF.APL.Custom:Check(state,row,1)
    self.manualPolicySnapshot={engine=e,step=step,state=state,allowed=allowed,reason=reason}
    return allowed,reason
end
function D:ContinuousEvidence(id,policyStep)
    local e=TEF.engine
    if TEF.Recommendation:Source(e)=="manual" then
        local step=policyStep or (self.castQueue and e.steps[self.castQueue.nextIndex]) or (e.steps and e.steps[e.index])
        if step and step.spellID==id then local allowed,reason=self:ManualPolicy(e,step); if allowed~=true then return false,reason end end
    end
    if TEF.APL and TEF.APL:IsActive(TEF.engine) then
        local allowed,reason=TEF.APL:Allowed(TEF.engine,id)
        if not allowed then return false,reason end
    end
    if not self:InputIdle() then return false,"CONTINUOUS_TEXT_FOCUS_OR_UNKNOWN" end
    local selfAction=self:IsSelfAction(id)
    local candidate=TEF.engine.aplCandidate
    if TEF.Recommendation:Source(e)=="manual" and self.manualPolicySnapshot and self.manualPolicySnapshot.engine==e and self.manualPolicySnapshot.state.generation==e.generation and self.manualPolicySnapshot.step.spellID==id then candidate=self.manualPolicySnapshot.state.actions.custom_1 end
    if candidate and candidate.spellID==id and candidate.target=="ground" then
        if publicBoolean("SpellIsTargeting")~=false then return false,"GROUND_TARGETING_OR_UNKNOWN" end
    end
    local friendly=candidate and candidate.spellID==id and candidate.target=="friendly"
    local friendlyUnit
    if friendly then
        local reason; friendlyUnit,reason=TEF.APL.State.FriendlyUnit()
        if not friendlyUnit then return false,reason end
    end
    if not selfAction and not friendly and (publicBoolean("UnitExists","target")~=true
        or publicBoolean("UnitCanAttack","player","target")~=true
        or publicBoolean("UnitIsDeadOrGhost","target")~=false) then return false,"CONTINUOUS_TARGET_UNKNOWN_OR_BLOCKED" end
    -- 6603是用户选择的启动开关步骤；开启不等同于近战命中，不要求命中范围。
    if not selfAction and friendlyUnit~="player" and id~=6603 then
        local range,rangeReason
        local rangeOK,rangeRaw,callReason=S.Call("C_Spell.IsSpellInRange",id,"target")
        if rangeOK then range,rangeReason=rangeBoolean(rangeRaw) end
        -- 普通技能缺少数据时才回退；公开超距或Secret不绕过。
        if (rangeOK and rangeReason=="NO_DATA") or (not rangeOK and callReason=="UNAVAILABLE") then
            range=self:ActionRange(id)
        end
        if range~=true then return false,"CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED" end
    end
    local fn=S.Resolve("C_Spell.IsSpellUsable")
    if not fn then return false,"CONTINUOUS_USABLE_UNKNOWN_OR_BLOCKED" end
    local ok,usable,power=pcall(fn,id)
    if not ok or S.Public(usable,"boolean")~=true or S.Public(power,"boolean")~=false then
        return false,"CONTINUOUS_USABLE_UNKNOWN_OR_BLOCKED"
    end
    -- Ordinary fixed practice is an explicitly authorized input attempt, like
    -- TE's ordinary recommendation transport, not AutoBurst admission or a
    -- dynamic ready selector. Never interpret UNKNOWN cooldown/GCD as ready.
    return true
end
-- Public FALSE/own cooldown only; missing/Secret never means unavailable.
function D:Unavailable(id)
    local fn=S.Resolve("C_Spell.IsSpellUsable")
    if not fn then return nil end
    local ok,rawUsable,rawPower=pcall(fn,id)
    if not ok then return nil end
    local usable,power=S.Public(rawUsable,"boolean"),S.Public(rawPower,"boolean")
    if usable==false or power==true then return true end
    if usable~=true or power~=false then return nil end
    local chargeFn=S.Resolve("C_Spell.GetSpellCharges")
    if chargeFn then
        local chargeOK,chargeRaw=pcall(chargeFn,id)
        local _,chargeReason=S.Public(chargeRaw,"table")
        if not chargeOK then return nil end
        if chargeReason~="NO_DATA" then
            local count=S.Field(chargeRaw,"currentCharges","number")
            local maximum=S.Field(chargeRaw,"maxCharges","number")
            if not count or not maximum or count<0 or maximum<1 or count>maximum
                or count%1~=0 or maximum%1~=0 then return nil end
            return count==0
        end
    end
    local got,info=S.Call("C_Spell.GetSpellCooldown",id)
    if not got then return nil end
    local start,duration=S.Field(info,"startTime","number"),S.Field(info,"duration","number")
    local enabled=S.Field(info,"isEnabled","boolean")
    if enabled~=true then return nil end
    -- Public inactive cooldown establishes only that this omission check has
    -- no cooldown reason to skip. Ordinary target/range/usability/cast gates
    -- still authorize the attempt; restricted timing is never called ready.
    -- Read this before timing/GCD: inactive spells may expose Secret times
    -- and no isOnGCD on the Forever client.
    local active=S.Field(info,"isActive","boolean")
    if active==false then return false end
    if start==0 and duration==0 then return false end
    -- Never skip because the spell reports only the global cooldown.
    local gcd=S.Field(info,"isOnGCD","boolean")
    if gcd==true then return false end
    if gcd~=false then return nil end
    if active==true then return true end
    if start and duration and start>0 and duration>0 then return true end
    return nil
end
function D:ShootActive(binding)
    if binding.spellID~=5019 and binding.spellID~=6603 and binding.spellID~=75 then return false end
    if not self:VerifyCurrent(binding) then return nil end
    local path
    if binding.spellID==75 then
        path=S.Resolve("C_ActionBar.IsAutoRepeatAction") and "C_ActionBar.IsAutoRepeatAction" or "IsAutoRepeatAction"
    else path=S.Resolve("C_ActionBar.IsCurrentAction") and "C_ActionBar.IsCurrentAction" or "IsCurrentAction" end
    return publicBoolean(path,binding.slot)
end
function D:AttackEnabled()
    local e=TEF.engine; local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
    if publicBoolean("UnitExists","target")~=true or publicBoolean("UnitCanAttack","player","target")~=true
        or publicBoolean("UnitIsDeadOrGhost","target")~=false then return false end
    local binding=self:ResolveCached(6603) or (self.actionSources and self.actionSources[6603])
    local active=binding and self:ShootActive(binding)
    return active==true and e==TEF.engine and generation==e.generation and index==e.index and serial==(e.receiptSerial or 0)
end
function D:HasCurrentInitiation()
    local e=TEF.engine; local i=self.initiation
    if not i or i.generation~=e.generation or i.index~=e.index then return false end
    local a=e.associations[i.guid]
    return a~=nil and not a.failed and a.generation==e.generation and a.index==e.index and a.spellID==i.spellID
        and a.receiptSerial==(e.receiptSerial or 0)
end
-- One bounded look-ahead reservation, never a second intent or input path.
function D:DropCastQueue()
    local q,e=self.castQueue,TEF.engine
    self.castQueue=nil
    if q and q.guid and e and not e.seen[q.guid] then
        if e.seenCount>=4096 then e.identitySaturated=true
        else e.seen[q.guid]="retired"; e.seenCount=e.seenCount+1 end
        if e.associations[q.guid] then e.associations[q.guid]=nil; e.associationCount=e.associationCount-1 end
    end
end
function D:CastQueueWindow()
    self.queueWindowReason="LIFECYCLE_OR_CURRENT_INITIATION"
    local e=TEF.engine
    if not e or not e.db.dispatch.castQueue or not self.continuous or not self:HasCurrentInitiation()
        or TEF.APL:IsActive(e) or not e.running or e.completed or TEF.UI.settingsOpen
        or publicBoolean("InCombatLockdown")~=true then return nil end
    local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
    local initiation=self.initiation
    local step=e.steps[index]
    if step.spellID==5019 or step.spellID==6603 or step.spellID==75 then return nil end
    local cast=S.Resolve("UnitCastingInfo"); local channel=S.Resolve("UnitChannelInfo")
    if not cast or not channel then return nil end
    local ok,name,_,__,startRaw,endRaw,___,____,_____,idRaw=pcall(cast,"player")
    local nameValue=S.Public(name,"string"); local startMS=S.Public(startRaw,"number")
    local endMS=S.Public(endRaw,"number"); local id=S.ID(idRaw)
    self.queueWindowReason="CAST_FIELDS_OR_IDENTITY"
    if not ok or not nameValue or not startMS or not endMS or id~=initiation.spellID
        or startMS<0 or endMS<=startMS then return nil end
    local channelOK,channelRaw=pcall(channel,"player")
    local _,channelReason=S.Public(channelRaw,"string")
    self.queueWindowReason="CHANNEL_PRESENT_OR_UNKNOWN"
    if not channelOK or channelReason~="NO_DATA" then return nil end
    local timeOK,timeRaw=S.Call("GetTime"); local now=timeOK and S.Public(timeRaw,"number")
    local path=S.Resolve("C_CVar.GetCVar") and "C_CVar.GetCVar" or "GetCVar"
    local queueOK,queueRaw=S.Call(path,"SpellQueueWindow")
    local queueText=queueOK and S.Public(queueRaw,"string")
    local queueMS=queueText and S.Public(tonumber(queueText),"number")
    self.queueWindowReason="CLOCK_OR_CLIENT_WINDOW_UNKNOWN"
    if not now or not queueMS or queueMS<=0 or queueMS>1000 then return nil end
    local remaining=endMS/1000-now
    local lead=S.Field(e.db.dispatch,"castQueueLead","number")
    self.queueWindowReason="LEAD_DISABLED_OR_INVALID"
    if not lead or lead<=0 or lead>.5 then return nil end
    self.queueWindowReason=remaining<=0 and "CAST_ENDED" or "OUTSIDE_TAIL"
    if now<startMS/1000 or remaining<=0 or remaining>math.min(lead,queueMS/1000) then return nil end
    local nextIndex=index
    if (e.stepCasts or 0)+1>=step.repeatCount then nextIndex=index+1 end
    -- Do not speculate across loop/completion, channel or Shoot boundaries.
    local nextStep=e.steps[nextIndex]
    if not nextStep or nextStep.unverified or nextStep.spellID==5019 or nextStep.spellID==6603 or nextStep.spellID==75 or nextStep.spellID==5143 then return nil end
    if e:UsageEligibility(nextIndex)~=true then return nil end
    if generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0)
        or self.initiation~=initiation or not self.continuous or not self.enabled
        or TEF.UI.settingsOpen or not self:HasCurrentInitiation() then return nil end
    self.queueWindowReason="WINDOW_OPEN"
    self.queueWindowSnapshot={remaining=remaining,clientWindow=queueMS/1000,effectiveLead=math.min(lead,queueMS/1000)}
    return nextIndex,nextStep
end
function D:TryCastQueue()
    local nextIndex,step=self:CastQueueWindow()
    if not nextIndex then return false end
    local e=TEF.engine
    if self.castQueue then return true end
    if self.castQueueAttempt==self.initiation.guid then return false end
    local generation,index,serial,initiation=e.generation,e.index,e.receiptSerial or 0,self.initiation
    if step.skipUnavailable and TEF.Recommendation:Source(e)=="manual" and self:Unavailable(step.spellID)~=false then return false end
    local policyAllowed=self:ManualPolicy(e,step,true)
    if policyAllowed~=true then return false end
    local allowed=self:ContinuousEvidence(step.spellID,step)
    if not allowed or generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0)
        or self.initiation~=initiation or not self.continuous then return false end
    local q={generation=generation,index=index,receiptSerial=serial,
        nextIndex=nextIndex,spellID=step.spellID,originGUID=initiation.guid}
    local snapshot=self.queueWindowSnapshot
    q.remaining=snapshot and snapshot.remaining; q.clientWindow=snapshot and snapshot.clientWindow
    q.effectiveLead=snapshot and snapshot.effectiveLead
    self.castQueue=q
    local requested=self:Request(true,q)
    if not requested then self:DropCastQueue(); return false end
    q.binding=self.pending.binding; q.usageContext=self.pending.usageContext; self.castQueueAttempt=q.originGUID
    q.request=TEF.Runtime.requestSerial
    e:Log("transport","CAST_QUEUE_REQUEST",q.spellID)
    return true
end
function D:SequenceSucceeded(guid)
    self.castQueueAttempt=nil
    local q,e=self.castQueue,TEF.engine
    if not q then
        if self:OrdinaryContinuous() then
            self:Cancel("CONTINUOUS_SUCCESS_RECOMMENDATION_CHANGED")
            self.waitReceipt=nil; self.initiation=nil
        end
        return
    end
    if guid~=q.originGUID or e.generation~=q.generation or e.index~=q.nextIndex
        or (e.receiptSerial or 0)~=q.receiptSerial+1 or e.completed then
        self:DropCastQueue(); self:Cancel("CAST_QUEUE_INVALIDATED"); return
    end
    self:TraceQueue(q.guid and "QUEUE_CURRENT_SUCCESS_WITH_IDENTITY" or "QUEUE_CURRENT_SUCCESS_NO_NEXT_IDENTITY",nil,q.spellID,guid,q)
    self.castQueue=nil
    self:Cancel("CAST_QUEUE_CURRENT_SUCCESS")
    local a=q.guid and e.associations[q.guid]
    if a and not a.failed and not e.seen[q.guid] then
        self.initiation={generation=e.generation,index=e.index,spellID=q.spellID,guid=q.guid}
        self.waitReceipt=e.receiptSerial; self.continuousBinding=q.binding
        e:Log("transport","CAST_QUEUE_PROMOTED",q.spellID)
    else self.waitReceipt=nil; self.initiation=nil end
end
function D:YieldCast(reason)
    self:Cancel(reason)
    -- Only an actual current initiation owns a success wait. An uninitiated
    -- candidate withdrawn for somebody else's cast must become publishable
    -- again when the authoritative presence query becomes idle.
    if not self:HasCurrentInitiation() then
        if self.waitReceipt~=nil then TEF.engine:Log("transport","CONTINUOUS_UNINITIATED_WAIT_RELEASED") end
        self.waitReceipt=nil; self.initiation=nil
    end
end
function D:TickContinuous()
    if not self.continuous then return end
    local e=TEF.engine
    if TEF.Runtime and TEF.Runtime.e==e and TEF.Runtime.intent and TEF.Runtime.state~="running" then return end
    if e.generation~=self.continuousGeneration or not e.running or e.completed
        or not self.enabled or TEF.UI.settingsOpen then
        self:StopContinuous("CONTINUOUS_LIFECYCLE_STOP"); self:Cancel(); return
    end
    local current=e.steps and e.steps[e.index]
    if current and (current.spellID==5019 or current.spellID==6603 or current.spellID==75) then
        local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
        local binding=self:ResolveCached(current.spellID)
        local active
        if binding then active=self:ShootActive(binding) end
        if generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0) or not self.continuous then return end
        if active~=false then
            self:Cancel("SHOOT_ACTIVE_OR_UNKNOWN")
            self:ContinuousStatus(current.spellID==6603 and (active==true and "ATTACK_ACTIVE_CONFIRMED_WAIT" or "ATTACK_ACTIVE_UNKNOWN")
                or (active==true and "SHOOT_ACTIVE_WAIT_SUCCESS" or "SHOOT_ACTIVE_UNKNOWN"))
            return
        end
        -- A withdrawn toggle without actual initiation owns no success wait.
        if not self.pending and not self:HasCurrentInitiation() then self.waitReceipt=nil end
    end
    if not self:CastIdle() then
        if self:TryCastQueue() then self:ContinuousStatus("CAST_QUEUE_WAIT_SUCCESS"); return end
        if not self:TransportCastAllowed(true) then return end
    end
    if self.castQueue then return end
    if TEF.Runtime and TEF.Runtime.e==e and TEF.Runtime.intent
        and not self.pending and self.waitReceipt==(e.receiptSerial or 0) and not self:HasCurrentInitiation() then
        self.waitReceipt=nil; self.initiation=nil
        e:Log("transport","CONTINUOUS_UNINITIATED_WAIT_RELEASED")
    end
    if self.pending or (not self:OrdinaryContinuous() and self.waitReceipt==(e.receiptSerial or 0)) then return end
    if not self:TransportCastAllowed(true) then self:ContinuousStatus("CONTINUOUS_CAST_PRESENT_OR_UNKNOWN"); return end
    local recommendation=TEF.Recommendation:Current(e)
    local step=recommendation and e.steps[e.index]
    if not step or step.unverified then self:StopContinuous("CONTINUOUS_STEP_UNRESOLVED"); return end
    local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
    local allowed,reason=self:ContinuousEvidence(step.spellID)
    if not self.continuous or generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0) then return end
    if not allowed then self:ContinuousStatus(reason); return end
    local requested,blocked=self:Request(true)
    if requested then self.waitReceipt=serial; self.continuousBinding=self.pending.binding; self:ContinuousStatus("CONTINUOUS_WAIT_RECEIPT")
    else self:Block(blocked) end
end
function D:SetEnabled(value)
    self:StopContinuous("CONTINUOUS_PERMISSION_CHANGED")
    self:Cancel("TEK_PERMISSION_CHANGED")
    self.enabled=value==true
    TEF.engine:Log("transport",self.enabled and "TEK_PERMISSION_ON" or "TEK_PERMISSION_OFF")
end
-- 直接技能或经正文与公开精确ID核对的当前宏；不猜等级别名。
local keys={Q=1,E=2,R=3,F=4,["1"]=5,["2"]=6,["3"]=7,["4"]=8,["5"]=9,Z=10,X=11,C=12,V=13,T=14,G=15,F1=16,F2=17,F3=18,F4=19,["`"]=20,["6"]=24,["7"]=25,["8"]=26,["9"]=27,["0"]=28,["-"]=29,["="]=30}
function D.Token(key)
    local k=S.Public(key,"string"); if not k then return nil end
    local prefix,base=k:match("^(%u+)%-(.+)$")
    local modifier=0
    if prefix then modifier=({ALT=1,CTRL=2,SHIFT=3})[prefix]; if not modifier then return nil end; k=base end
    local code=keys[k]; return code and code+modifier*64 or nil
end
function D.SkillToken(raw)
    local key=S.Public(raw,"string"); if not key then return nil end
    -- A control override must never be sent as a spell key. During a deferred
    -- combat edit both the saved key and the still-installed old key are reserved.
    local dispatch=TEF.engine and TEF.engine.db.dispatch
    if dispatch and key==dispatch.hotkey then return nil end
    if TEF.Hotkeys and key==TEF.Hotkeys.appliedKey then return nil end
    return D.Token(key)
end
function D:Cancel(reason)
    local hadPending=self.pending~=nil
    if hadPending then TEF.engine:Log("transport",reason or "TEK_REQUEST_CANCELLED") end
    self.pending=nil
    -- Publish the zero-token barrier immediately, rather than leaving an old
    -- armed strip until the next heartbeat after a pause/settings/game event.
    if hadPending and TEF.Transport and TEF.Transport.enabled then
        local ok=pcall(TEF.Transport.Paint,TEF.Transport)
        if not ok then TEF.Transport:Fail("TRANSPORT_REVOKE_FAILED") end
    end
end
function D:Resolve(id)
    local info=S.Resolve("C_ActionBar.GetActionInfo") or S.Resolve("GetActionInfo")
    if not info then return nil,"TEK_ACTION_API_MISSING" end
    local names={"ActionButton","MultiBarBottomLeftButton","MultiBarBottomRightButton","MultiBarRightButton","MultiBarLeftButton","MultiBar5Button","MultiBar6Button","MultiBar7Button"}
    local commands={"ACTIONBUTTON","MULTIACTIONBAR1BUTTON","MULTIACTIONBAR2BUTTON","MULTIACTIONBAR3BUTTON","MULTIACTIONBAR4BUTTON","MULTIACTIONBAR5BUTTON","MULTIACTIONBAR6BUTTON","MULTIACTIONBAR7BUTTON"}
    for bar,name in ipairs(names) do for n=1,12 do
        local got,b=pcall(function() return _G[name .. n] end)
        if got and b then
            local ok,raw=TEF.UI:Invoke(b,"GetAttribute","action")
            local slot=ok and S.ID(raw)
            if not slot then local read,v=pcall(function() return b.action end); slot=read and S.ID(v) end
            if slot and slot<=180 then
                local source=TEF.ActionSources:Action(slot)
                if source and source.spellID==id then
                    self.actionSources=self.actionSources or {}
                    if not self.actionSources[id] then
                        self.actionSources[id]={slot=slot,spellID=id,command=commands[bar] .. n,button=b,buttonName=name .. n,
                            source=source.kind,macroID=source.macroID,macroName=source.macroName,macroBody=source.body,actionOnly=true}
                    end
                    local fn=S.Resolve("GetBindingKey")
                    if fn then
                        local bound,k1,k2=pcall(fn,commands[bar] .. n)
                        local token=bound and (D.SkillToken(k1) or D.SkillToken(k2))
                        if token then
                            local key=D.SkillToken(k1) and S.Public(k1,"string") or S.Public(k2,"string")
                            return {slot=slot,token=token,key=key,spellID=id,command=commands[bar] .. n,button=b,buttonName=name .. n,
                                source=source.kind,macroID=source.macroID,macroName=source.macroName,macroBody=source.body},"TEK_BINDING_VERIFIED"
                        end
                    end
                end
            end
        end
    end end
    return nil,"TEK_EXACT_DIRECT_BINDING_UNAVAILABLE"
end
-- Input sources are cached only between binding/spell lifecycle events.
-- A positive source is still verified live at Request and every Packet.
D.bindingCache={}
function D:ClearBindingCache() self.bindingCache={}; self.actionSources={} end
function D:ResolveCached(id)
    local cached=self.bindingCache[id]
    if cached==nil then cached=self:Resolve(id); self.bindingCache[id]=cached or false end
    if cached==false then return nil,"TEK_EXACT_DIRECT_BINDING_UNAVAILABLE" end
    return cached,"TEK_BINDING_VERIFIED"
end
function D:CastIdle()
    local e=TEF.engine; local h=e and e.shootHandoff
    local generation,index,serial=e and e.generation,e and e.index,e and e.receiptSerial
    local handoff=h and h.generation==generation and h.index==index and h.receiptSerial==serial
        and e.running and not e.completed and e.steps[index].spellID~=5019
    for _,path in ipairs({"UnitCastingInfo","UnitChannelInfo"}) do
        local fn=S.Resolve(path)
        if not fn then return false end
        local ok,value,_,__,___,____,_____,______,_______,spell=pcall(fn,"player")
        local _,reason=S.Public(value,"string")
        if not ok then return false end
        if reason~="NO_DATA" then
            if not handoff or path~="UnitCastingInfo" or reason~="PUBLIC" or S.ID(spell)~=5019 then return false end
        end
    end
    if e and (generation~=e.generation or index~=e.index or serial~=e.receiptSerial) then return false end
    return true
end
-- 普通读条采用TE式持续推荐输出；引导仍是输入锁。
function D:OrdinaryContinuous()
    local e=TEF.engine; local r=TEF.Runtime
    local step=e and e.steps and e.steps[e.index]
    return r and r.e==e and r.intent and e.db.dispatch.ordinaryContinuous==true
        and step and step.spellID~=5019 and step.spellID~=6603 and step.spellID~=75 or false
end
function D:TransportCastAllowed(continuous)
    if TEF.engine.db.dispatch.ordinaryContinuous and self.channelInputLock then return false end
    if continuous and self:OrdinaryContinuous() then
        local ok,raw=S.Call("UnitChannelInfo","player")
        local _,reason=S.Public(raw,"string")
        return ok and reason=="NO_DATA"
    end
    return self:CastIdle()
end
function D:Request(fromContinuous,queue)
    -- The test button cannot revoke or replace an automatic request (S37).
    if fromContinuous~=true and self.continuous then
        if self.pending then return true,"TEK_REQUEST_ALREADY_PENDING" end
        return false,"TEK_AUTOMATIC_OWNS_REQUEST"
    end
    self:Cancel()
    local e=TEF.engine; local step=e.steps and e.steps[queue and queue.nextIndex or e.index]
    local generation,index,serial=e.generation,e.index,e.receiptSerial or 0
    local blocked
    if not self.enabled then blocked="TEK_PERMISSION_DISABLED"
    elseif TEF.UI.settingsOpen then blocked="TEK_SETTINGS_OPEN"
    elseif not e.running then blocked="TEK_PRACTICE_PAUSED"
    elseif e.completed then blocked="TEK_PRACTICE_COMPLETED"
    elseif TEF.Runtime and TEF.Runtime.e==e and TEF.Runtime.intent
        and TEF.Runtime.state=="standby" and TEF.Runtime.reason=="RUNTIME_AUTO_STANDBY" then blocked="RUNTIME_AUTO_STANDBY"
    elseif not step or step.unverified then blocked="TEK_STEP_UNRESOLVED"
    elseif queue and (queue~=self.castQueue or self:CastQueueWindow()~=queue.nextIndex) then blocked="CAST_QUEUE_WINDOW_CLOSED"
    elseif not queue and not self:TransportCastAllowed(fromContinuous==true) then blocked="TEK_CAST_PRESENT_OR_UNKNOWN" end
    if blocked then e:Log("transport",blocked); return false,blocked end
    local policyAllowed,policyReason=self:ManualPolicy(e,queue and e.steps[queue.nextIndex] or step,true)
    if policyAllowed~=true then return false,policyReason end
    local eligible,usageReason,usageContext=e:UsageEligibility(queue and queue.nextIndex or e.index)
    if eligible~=true then return false,usageReason end
    if TEF.APL and TEF.APL:IsActive(e) then
        local allowed,reason=TEF.APL:Allowed(e,step.spellID)
        if not allowed then return false,reason end
    end
    local binding,reason
    if fromContinuous then binding,reason=self:ResolveCached(step.spellID) else binding,reason=self:Resolve(step.spellID) end
    if not binding then e:Log("transport",reason); return false,reason end
    if not self:VerifyCurrent(binding) then self.bindingCache[step.spellID]=nil; return false,"TEK_BINDING_CHANGED" end
    if self:ShootActive(binding)~=false then return false,"SHOOT_ACTIVE_OR_UNKNOWN" end
    if not TEF.Transport.enabled and not TEF.Transport:SetEnabled(true) then return false,"TEK_SIGNAL_UNAVAILABLE" end
    if generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0) or not e.running or not self.enabled
        or TEF.UI.settingsOpen or (fromContinuous==true and not self.continuous) then
        return false,"TEK_REQUEST_STALE"
    end
    local stillEligible,_,freshContext=e:UsageEligibility(queue and queue.nextIndex or e.index)
    if stillEligible~=true or not e:SameUsageContext(usageContext,freshContext)
        or generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0) or not e.running or not self.enabled or TEF.UI.settingsOpen then
        return false,"SEQUENCE_USAGE_SCOPE_CHANGED"
    end
    self.pending={generation=e.generation,index=e.index,binding=binding,receiptSerial=serial,castQueue=queue,usageContext=usageContext}
    if TEF.Runtime and TEF.Runtime.e==e then TEF.Runtime.requestSerial=TEF.Runtime.requestSerial+1 end
    self.pending.request=TEF.Runtime.requestSerial
    if queue then queue.request=self.pending.request end
    e:Log("transport",fromContinuous==true and "TEK_CONTINUOUS_REQUEST" or "TEK_MANUAL_REQUEST",step.spellID)
    return true,"TEK_MANUAL_REQUEST"
end
function D:VerifyCurrent(b)
    local currentOK,current=pcall(function() return _G[b.buttonName] end)
    if not currentOK or current~=b.button then return false end
    local ok,raw=TEF.UI:Invoke(b.button,"GetAttribute","action")
    local slot=ok and S.ID(raw)
    if not slot then local read,value=pcall(function() return b.button.action end); slot=read and S.ID(value) end
    local source=slot and TEF.ActionSources:Action(slot)
    if slot~=b.slot or not source or source.spellID~=b.spellID then return false end
    if b.source=="macro" then
        if source.kind~="macro" or source.macroID~=b.macroID or source.macroName~=b.macroName or source.body~=b.macroBody then return false end
    elseif source.kind~="spell" then return false end
    -- 无键位的来源仅供确认已开启状态，绝不能发布输入。
    if b.actionOnly then return true end
    local bindingFn=S.Resolve("GetBindingKey")
    local bound,k1,k2=false,nil,nil
    if bindingFn then bound,k1,k2=pcall(bindingFn,b.command) end
    local token=bound and (D.SkillToken(k1) or D.SkillToken(k2))
    return token==b.token
end
function D:BindingsChanged()
    self:ClearBindingCache()
    if self.continuous then
        local binding=self.pending and self.pending.binding or (self.castQueue and self.castQueue.binding) or self.continuousBinding
        if binding and not self:VerifyCurrent(binding) then
            self:Block("CONTINUOUS_BINDING_CHANGED")
        end
        return
    end
    if not self.pending then return end
    if not self:VerifyCurrent(self.pending.binding) then self:Cancel("TEK_BINDING_CHANGED") end
end
function D:Packet()
    local p,e=self.pending,TEF.engine
    if not p then return nil end
    local policyStep=e.steps and e.steps[p.castQueue and p.castQueue.nextIndex or e.index]
    local policyAllowed,policyReason=self:ManualPolicy(e,policyStep,true)
    if policyAllowed~=true then self:Cancel(policyReason or "SEQUENCE_POLICY_UNKNOWN"); return nil end
    if not self.enabled or not e.running or e.completed or e.generation~=p.generation or e.index~=p.index
        or p.receiptSerial~=(e.receiptSerial or 0) or TEF.UI.settingsOpen then self:Cancel("TEK_REQUEST_STALE"); return nil end
    local eligible,usageReason,usageContext=e:UsageEligibility(p.castQueue and p.castQueue.nextIndex or e.index)
    if eligible~=true or not e:SameUsageContext(p.usageContext,usageContext) then self:Cancel(usageReason or "SEQUENCE_USAGE_SCOPE_CHANGED"); return nil end
    -- Revalidate the locked source; never silently switch to another slot/key.
    if not self:VerifyCurrent(p.binding) then
        self.bindingCache[p.binding.spellID]=nil
        self:Block("CONTINUOUS_BINDING_CHANGED"); return nil
    end
    if p.castQueue then
        if p.castQueue~=self.castQueue or self:CastQueueWindow()~=p.castQueue.nextIndex then
            self:Cancel("CAST_QUEUE_WINDOW_CLOSED"); return nil
        end
    elseif not self:TransportCastAllowed(self.continuous) then self:Cancel("TEK_CAST_PRESENT_OR_UNKNOWN"); return nil end
    if TEF.APL and TEF.APL:IsActive(e) then
        local allowed,reason=TEF.APL:Allowed(e,p.binding.spellID)
        if not allowed then self:Cancel(reason); return nil end
    end
    if self:ShootActive(p.binding)~=false then self:Cancel("SHOOT_ACTIVE_OR_UNKNOWN"); return nil end
    if self.continuous then
        local allowed,reason=self:ContinuousEvidence(p.binding.spellID)
        if not allowed then self:Block(reason); return nil end
        if self.pending~=p or not self.continuous or e.generation~=p.generation or e.index~=p.index then return nil end
    end
    local ok,rawCombat=S.Call("InCombatLockdown")
    local combat
    if ok then combat=S.Public(rawCombat,"boolean") end
    if combat==nil then self:Cancel("TEK_COMBAT_UNKNOWN"); return nil end
    if TEF.Runtime and TEF.Runtime.e==e and TEF.Runtime.intent
        and e.db.dispatch.mode=="auto" and combat~=true and not TEF.Maintenance:OutsideAllowed(e) then self:Cancel("RUNTIME_AUTO_STANDBY"); return nil end
    if p.castQueue and combat~=true then self:Cancel("CAST_QUEUE_COMBAT_REQUIRED"); return nil end
    if TEF.APL and TEF.APL:IsActive(e) and not TEF.Runtime:CombatAllowed(e,combat) then self:Cancel("APL_DISPATCH_COMBAT_REQUIRED"); return nil end
    if self.pending~=p or not self.enabled or not e.running or e.completed
        or e.generation~=p.generation or e.index~=p.index or p.receiptSerial~=(e.receiptSerial or 0) or TEF.UI.settingsOpen then return nil end
    local stillEligible,_,freshContext=e:UsageEligibility(p.castQueue and p.castQueue.nextIndex or e.index)
    if stillEligible~=true or not e:SameUsageContext(p.usageContext,freshContext) then self:Cancel("SEQUENCE_USAGE_SCOPE_CHANGED"); return nil end
    if self.pending~=p or not self.enabled or not e.running or e.completed or TEF.UI.settingsOpen
        or e.generation~=p.generation or e.index~=p.index or p.receiptSerial~=(e.receiptSerial or 0) then return nil end
    if not p.diagnosticPublished then
        p.diagnosticPublished=true
        self:TraceQueue("TOKEN_PUBLISHED",nil,p.binding.spellID,nil,p.castQueue)
    end
    return p.binding.token,combat
end
function D:Event(event,unit,id,guidRaw)
    local failure=event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_FAILED_QUIET" or event=="UNIT_SPELLCAST_INTERRUPTED"
    local runtime=TEF.Runtime
    local e=TEF.engine
    local owned=runtime and runtime.e==e
    local eventGeneration,eventIndex=e.generation,e.index
    -- Public identities only; retain bounded failed-attempt tombstones across temporary
    -- generations so a delayed FAILED/START/SUCCEEDED cannot stop or advance retry.
    local unitValue=S.Public(unit,"string")
    local spellValue=S.ID(id)
    local guid=S.Identity(guidRaw)
    if unitValue=="player" and event=="UNIT_SPELLCAST_CHANNEL_START" then
        self.channelInputLock=true
        self:Cancel("CHANNEL_ACTIVE_INPUT_LOCK")
    elseif unitValue=="player" and event=="UNIT_SPELLCAST_CHANNEL_STOP" then
        self.channelInputLock=nil -- 只撤销事件锁，派发仍复核实时引导接口。
    end
    if unitValue=="player" then self:TraceQueue("GAME_EVENT",event,spellValue,guid) end
    if owned and (runtime.e~=e or TEF.engine~=e or e.generation~=eventGeneration or e.index~=eventIndex) then return true end
    if owned and unitValue=="player" and guid and e.seen[guid]=="retired" then
        e:Log("ignored","CONTINUOUS_FAILED_RECEIPT_IGNORED",spellValue,nil,nil,event)
        return true
    end
    -- 连发可能让客户端提前接受同技能的下一次起始。仅人工固定
    -- 序列确实还有同ID次数时保留未来回执；失败不影响原起始。
    local q=self.castQueue
    if not q and self.continuous and self:OrdinaryContinuous() and TEF.Recommendation:Source(e)=="manual"
        and unitValue=="player" and guid and self:HasCurrentInitiation()
        and guid~=self.initiation.guid and not e.seen[guid]
        and (event=="UNIT_SPELLCAST_SENT" or event=="UNIT_SPELLCAST_START") then
        local step=e.steps[e.index]
        local nextIndex=(e.stepCasts or 0)+1<step.repeatCount and e.index or e.index+1
        local nextStep=e.steps[nextIndex]
        if nextStep and nextStep.spellID==spellValue and spellValue==self.initiation.spellID then
            q={generation=e.generation,index=e.index,receiptSerial=e.receiptSerial or 0,
                nextIndex=nextIndex,spellID=spellValue,originGUID=self.initiation.guid,
                request=TEF.Runtime.requestSerial,implicitContinuous=true}
            self.castQueue=q
            self:TraceQueue("ORDINARY_SAME_SPELL_NEXT_RESERVED",event,spellValue,guid,q)
        end
    end
    if q and unitValue=="player" and spellValue==q.spellID and guid and guid~=q.originGUID then
        if q.generation~=e.generation or q.index~=e.index or q.receiptSerial~=(e.receiptSerial or 0) then
            self:DropCastQueue(); self:Cancel("CAST_QUEUE_INVALIDATED"); return true
        end
        if (event=="UNIT_SPELLCAST_SENT" or event=="UNIT_SPELLCAST_START") and not e.seen[guid] then
            if q.guid and q.guid~=guid then return true end
            if not q.guid then
                if e.associationCount>=256 then runtime:Fault("CAST_QUEUE_IDENTITY_CAPACITY"); return true end
                q.guid=guid; e.associationCount=e.associationCount+1
                e.associations[guid]={generation=e.generation,index=q.nextIndex,spellID=q.spellID,receiptSerial=q.receiptSerial+1,usageContext=q.usageContext}
            end
            self:Cancel("CAST_QUEUE_INITIATED"); return true
        elseif failure or event=="UNIT_SPELLCAST_SUCCEEDED" then
            if not q.guid then q.guid=guid end
            if guid==q.guid then
                self:TraceQueue(failure and "QUEUE_FAILURE_EVENT" or "QUEUE_SUCCESS_BEFORE_CURRENT_SUCCESS",event,spellValue,guid,q)
                self:DropCastQueue(); self:Cancel("CAST_QUEUE_REJECTED"); e:Log("ignored","CAST_QUEUE_REJECTED",spellValue)
            end
            return true
        end
    end
    -- A current exact initiation owns its receipt. An extra same-spell
    -- attempt cannot replace it or suspend it on failure. Explicit queue
    -- identities were handled above and retain their separate reservation.
    if owned and runtime.intent and self.continuous and unitValue=="player"
        and guid and self:HasCurrentInitiation() and guid~=self.initiation.guid
        and spellValue==self.initiation.spellID then
        if not e.seen[guid] then
            if e.seenCount>=4096 then runtime:Fault("CONTINUOUS_FAILED_IDENTITY_CAPACITY"); return true end
            e.seen[guid]="retired"; e.seenCount=e.seenCount+1
        end
        self:TraceQueue("EXTRA_SAME_SPELL_ATTEMPT_RETIRED",event,spellValue,guid)
        e:Log("ignored","CONTINUOUS_EXTRA_ATTEMPT_IGNORED",spellValue,nil,nil,event)
        return true
    end
    if owned and runtime.intent and self.continuous and unitValue=="player" and spellValue then
        local step=e.steps[e.index]
        if event=="UNIT_SPELLCAST_SENT" or event=="UNIT_SPELLCAST_START" then
            if step.matches[spellValue] and guid and not e.seen[guid] then
                self.initiation={generation=e.generation,index=e.index,spellID=spellValue,guid=guid}
            elseif not step.matches[spellValue] then
                self:YieldCast("CONTINUOUS_FOREIGN_CAST_YIELD")
            end
        end
    end
    if self.continuous or (owned and runtime.intent and runtime.reason=="CONTINUOUS_MOVING_OR_UNKNOWN" and failure) then
        local u=S.Public(unit,"string"); local spell=S.ID(id)
        local step=TEF.engine.steps and TEF.engine.steps[TEF.engine.index]
        if not u or (u=="player" and not spell) then self:Block("CONTINUOUS_EVENT_UNKNOWN")
        elseif u=="player" and step and step.matches[spell] and failure then
            if owned then
                local generation,index=e.generation,e.index
                local moving=publicBoolean("IsPlayerMoving")
                if runtime.e~=e or TEF.engine~=e or generation~=e.generation or index~=e.index or not runtime.intent then return true end
                local a=guid and e.associations[guid]
                if not guid then
                    self:Block("CONTINUOUS_FAILURE_IDENTITY_UNKNOWN"); return true
                elseif moving==true or (a and a.generation==generation and a.index==index and a.spellID==spell) then
                    -- Failed and invalidated initiations share Engine's existing
                    -- lifetime tombstones. Never evict: delayed events must stay
                    -- retired, but there is no redundant 128-attempt budget.
                    if not e.seen[guid] then
                        if e.seenCount>=4096 then e.identitySaturated=true; runtime:Fault("CONTINUOUS_FAILED_IDENTITY_CAPACITY"); return true end
                        e.seen[guid]="retired"; e.seenCount=e.seenCount+1
                    end
                    local reason=moving==true and "CONTINUOUS_MOVEMENT_FAILURE_RETRY" or (moving==false and "CONTINUOUS_FAILURE_RETRY" or "CONTINUOUS_FAILURE_MOVEMENT_UNKNOWN")
                    e:Log("observed",reason,spell,nil,nil,event)
                    runtime:Suspend(reason); return true
                elseif not a or a.generation~=generation or a.index~=index or a.spellID~=spell then
                    -- A same-ID failure without this attempt's initiation is not
                    -- proof of current failure, especially adjacent rank repeats.
                    e:Log("ignored","CONTINUOUS_FAILURE_NO_CURRENT_INITIATION",spell,nil,nil,event)
                    return true
                end
            end
            self:StopContinuous("CONTINUOUS_FAILURE_STOP")
            if TEF.Runtime and TEF.Runtime.e==TEF.engine then TEF.Runtime:OnDispatchFault("CONTINUOUS_FAILURE_STOP") end
        end
        if not self.continuous then self:Cancel() end
    end
    if not self.pending then return end
    local u=S.Public(unit,"string"); local spell=S.ID(id)
    if not u or (u=="player" and not spell) then self:Cancel("TEK_EVENT_UNKNOWN"); return end
    if failure and not self.continuous and u=="player" and spell==self.pending.binding.spellID then
        self:Cancel("TEK_GAME_EVENT_RECEIVED"); return
    end
    if u=="player" and spell==self.pending.binding.spellID
        and (event=="UNIT_SPELLCAST_SENT" or event=="UNIT_SPELLCAST_START") and not guid then
        self:Cancel("TEK_EVENT_UNKNOWN"); return
    end
    -- 仅精确公开起始事件确认新请求；旧引导结束/伤害/成功不能
    -- 仅凭相同技能ID撤销尚未起始的新请求。
    if u=="player" and guid and (event=="UNIT_SPELLCAST_SENT" or event=="UNIT_SPELLCAST_START")
        and spell==self.pending.binding.spellID
        and (not self.pending.castQueue or guid==self.pending.castQueue.guid) then
        if self.continuous and self:OrdinaryContinuous() and not self.pending.castQueue then
            self:TraceQueue("ORDINARY_CONTINUOUS_INITIATED",event,spell,guid)
        else self:Cancel("TEK_GAME_EVENT_RECEIVED") end
    end
end
