local _, TEF = ...
local D,S={},TEF.Safety
TEF.Dispatch=D
-- 独立有界证据保留逐段信号身份；运行门禁从不读取此表。
function D:ObservePublishedFrame(sequence,freshness,token)
 local p,e=self.pending,TEF.engine
 local now=TEF.APL.State.Time()
 if not p or not now or p.generation~=e.generation or token~=p.binding.token then return end
 local row=p.deliveryRow
 if not row or sequence~=(row.lastSequence+1)%65536 or freshness~=(row.lastFreshness+1)%65536
  or (sequence-row.firstSequence)%65536>=4096 then
  local rows=e.db.deliveryDiagnostics
  if #rows>=128 then table.remove(rows,1); e.db.deliveryEvicted=(e.db.deliveryEvicted or 0)+1 end
  row={session=e.session,generation=e.generation,request=p.request,spellID=p.binding.spellID,token=token,
   requestedAt=p.requestedAt,firstPublishedAt=now,firstSequence=sequence,firstFreshness=freshness}
  rows[#rows+1]=row; p.deliveryRow=row
 end
 row.lastSequence=sequence; row.lastFreshness=freshness; row.lastPublishedAt=now
end
function D:ObserveDeliveryInitiation(id,guid)
 local e=TEF.engine; local rows=e.db.deliveryDiagnostics; local now=TEF.APL.State.Time()
 if not now or not S.Identity(guid) then return end
 for i=#rows,1,-1 do
  local row=rows[i]
  if row.session==e.session and row.generation==e.generation and row.request==TEF.Runtime.requestSerial and row.spellID==id then
   if not row.initiatedAt then row.initiatedAt=now; row.guid=guid end
   return
  end
 end
end
D.enabled=false
-- Runtime-only opt-in; no timer estimates, persisted arm state or second transport.
D.continuous=false
-- Independent bounded evidence only; never read by queue/dispatch admission.
function D:TraceQueue(reason,event,id,guid,queue)
    local e=TEF.engine
    if not e or not e.db.dispatch or (not e.db.dispatch.castQueue and not e.db.dispatch.groupQueue and not e.db.dispatch.ordinaryContinuous) then return end
    local q=queue or self.castQueue or (self.pending and self.pending.castQueue)
    local ok,clock=S.Call("GetTime")
    local row={reason=S.Public(reason,"string"),event=S.Public(event,"string"),spellID=S.ID(id),guid=S.Identity(guid),
        session=e.session,generation=e.generation,version=TEF.Version,index=e.index,count=e.stepCasts or 0,
        receiptSerial=e.receiptSerial or 0,cycle=TEF.Runtime.cycle,request=TEF.Runtime.requestSerial,
        time=ok and S.Public(clock,"number"),lead=S.Field(e.db.dispatch,"castQueueLead","number"),
        retryDelay=S.Field(e.db.dispatch,"retryDelay","number"),
        source=q and (q.source=="apl" and "apl_queue" or (e.groupRun and "group_queue" or "queue")) or "ordinary",windowReason=self.queueWindowReason,
        currentGUID=self.initiation and S.Identity(self.initiation.guid),loopMode=e.db.loopMode}
    if q then
        row.originGUID=S.Identity(q.originGUID); row.queuedGUID=S.Identity(q.guid)
        row.queueRequest=q.request; row.queueIndex=q.index; row.nextIndex=q.nextIndex
        row.queueSpellID=q.spellID; row.queueSerial=q.receiptSerial
        row.clientWindow=q.clientWindow; row.remaining=q.remaining; row.effectiveLead=q.effectiveLead
    end
    local timing=q and q.windowSnapshot or self.timingWindow
    if timing and timing.engine==e and timing.generation==e.generation then
        row.worldLatency=timing.worldLatency; row.homeLatency=timing.homeLatency; row.latencyAllowance=timing.latencyAllowance
        if not q then row.remaining=timing.remaining; row.clientWindow=timing.clientWindow; row.effectiveLead=timing.effectiveLead end
        row.windowSampledAt=timing.sampledAt; row.windowAge=row.time and math.max(0,row.time-timing.sampledAt) or nil
        row.windowKind=timing.kind
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
function D:ManualPolicy(e,step,live,groupEntry,readOnly)
    if TEF.Recommendation:Source(e)~="manual" then return true end
    if step and not step.group and TEF.Maintenance:Owns(e,step.spellID) then return false,"MAINTENANCE_OWNS_SPELL" end
    if not step then return nil,"SEQUENCE_POLICY_STEP_UNKNOWN" end
    if step.group and not groupEntry then return nil,"GROUP_WAIT_ENTRY" end
    if step.group and #step.group.steps==0 then return false,"GROUP_EMPTY" end
    if step.enabled==false then return false,"SEQUENCE_POLICY_DISABLED" end
    if e.groupPolicyBlocked then return nil,e.groupPolicyBlocked end
    if not step.behavior and (not step.strategies or #step.strategies==0) then
        if not step.targetMode or step.targetMode=="auto" then return true end
    end
    local now=TEF.APL.State.Time(); local revision=TEF.APL.State.revision or 0
    local cached=self.manualPolicySnapshot
    if not readOnly and not live and cached and cached.engine==e and cached.step==step and cached.state.generation==e.generation and cached.state.receiptSerial==(e.receiptSerial or 0)
        and cached.state.revision==revision and now and cached.state.sampledAt and now>=cached.state.sampledAt and now-cached.state.sampledAt<.05 then
        return cached.allowed,cached.reason
    end
    local row={spellID=step.spellID,enabled=true,moving="any",activity="any",distanceOp="any",cdmKind="none",strategies=step.strategies,targetMode=step.targetMode,behavior=step.behavior}
    local state={readOnly=readOnly==true,policyOwner=step,generation=e.generation,receiptSerial=e.receiptSerial or 0,revision=revision,sampledAt=now,scene=e.scene,actions={},moving=TEF.APL.State.Boolean("IsPlayerMoving")}
    local index=e.index
    TEF.APL.Custom:Sample(e,state,{row})
    if state.generation~=e.generation or state.receiptSerial~=(e.receiptSerial or 0) or index~=e.index or revision~=(TEF.APL.State.revision or 0) then return nil,"SEQUENCE_POLICY_STALE" end
    local allowed,reason=TEF.APL.Custom:Check(state,row,1)
    if not readOnly then self.manualPolicySnapshot={engine=e,step=step,state=state,allowed=allowed,reason=reason} end
    return allowed,reason
end
function D:PolicyEvidence(reason)
    local e=TEF.engine; local p=self.manualPolicySnapshot
    if not p or p.engine~=e or p.step~=(e.steps and e.steps[e.index]) or p.reason~=reason
        or p.state.generation~=e.generation or p.state.receiptSerial~=(e.receiptSerial or 0)
        or p.state.revision~=(TEF.APL.State.revision or 0) then return nil end
    local detail=p.state.strategyBlockDetails and p.state.strategyBlockDetails[1]
    local block
    if detail then
        block={strategyIndex=detail.strategy,conditionIndex=detail.condition,kind=detail.kind,spellID=detail.spellID}
        if detail.kind=="cdmBuff" or detail.kind=="cdmCooldown" then
            local action=p.state.actions.custom_1
            local probe=action and action.strategyCDM and action.strategyCDM[(detail.kind=="cdmBuff" and "buff:" or "cooldown:") .. detail.spellID]
            block.cdmReason=probe and probe.reason
        end
    end
    return TEF.APL.Trace.Clean({reason="MANUAL_POLICY_BLOCKED",sampledAt=p.state.sampledAt,actions=p.state.actions,policyBlock=block})
end
function D:EvidenceBlock(reason,title,description,unknown)
 local e=TEF.engine
 self.evidenceDetail={engine=e,generation=e.generation,index=e.index,serial=e.receiptSerial or 0,
  reason=reason,title=title,description=description,unknown=unknown==true}
 return false,reason
end
function D:BlockDetail(reason)
 local e=TEF.engine; local d=self.evidenceDetail
 if d and d.engine==e and d.generation==e.generation and d.index==e.index and d.serial==(e.receiptSerial or 0) and d.reason==reason then return d end
 local p=self.manualPolicySnapshot
 if p and p.engine==e and p.step==(e.steps and e.steps[e.index]) and p.state.generation==e.generation and p.state.receiptSerial==(e.receiptSerial or 0) and p.reason==reason then
  local condition=p.state.strategyBlockDetails and p.state.strategyBlockDetails[1]
  if condition and (reason=="UNKNOWN:custom:strategy" or reason=="CUSTOM_USE_STRATEGY_UNMATCHED") then return {title=condition.unknown and "条件未知" or "条件未满足",description=condition.description,unknown=condition.unknown} end
 end
end
function D:ContinuousEvidence(id,policyStep,queue)
    self.evidenceDetail=nil
    local e=TEF.engine
    if TEF.Recommendation:Source(e)=="manual" then
        local step=policyStep or (self.castQueue and e.steps[self.castQueue.nextIndex]) or (e.steps and e.steps[e.index])
        if step and step.spellID==id then local allowed,reason=self:ManualPolicy(e,step); if allowed~=true then return false,reason end end
    end
    if TEF.APL and TEF.APL:IsActive(TEF.engine) then
        local allowed,reason=TEF.APL:Allowed(TEF.engine,id,queue)
        if not allowed then return false,reason end
    end
    if not self:InputIdle() then return false,"CONTINUOUS_TEXT_FOCUS_OR_UNKNOWN" end
    local selfAction=self:IsSelfAction(id)
    local candidate=queue and queue.candidate or TEF.engine.aplCandidate
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
    if not selfAction and not friendly then
        for _,test in ipairs({{"UnitExists",true,"目标不存在","请先选择目标"},{"UnitCanAttack",true,"目标不可攻击","请选择可攻击的敌方目标"},{"UnitIsDeadOrGhost",false,"目标已死亡","请选择存活目标"}}) do
            local value=test[1]=="UnitCanAttack" and publicBoolean(test[1],"player","target")
            if test[1]~="UnitCanAttack" then value=publicBoolean(test[1],"target") end
            if value~=test[2] then
                return self:EvidenceBlock("CONTINUOUS_TARGET_UNKNOWN_OR_BLOCKED",value==nil and "目标状态未知" or test[3],value==nil and "无法公开确认目标状态，等待重新探测" or test[4],value==nil)
            end
        end
    end
    -- 6603是用户选择的启动开关步骤；开启不等同于近战命中，不要求命中范围。
    if not selfAction and friendlyUnit~="player" and id~=6603 then
        local range,rangeReason
        local rangeOK,rangeRaw,callReason=S.Call("C_Spell.IsSpellInRange",id,"target")
        if rangeOK then range,rangeReason=rangeBoolean(rangeRaw) end
        -- 普通技能缺少数据时才回退；公开超距或Secret不绕过。
        if (rangeOK and rangeReason=="NO_DATA") or (not rangeOK and callReason=="UNAVAILABLE") then
            range=self:ActionRange(id)
        end
        if range~=true then return self:EvidenceBlock("CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED",range==false and "超出范围" or "距离未知",range==false and "目标超出技能范围，请调整距离" or "无法公开确认技能范围，等待重新探测",range==nil) end
    end
    local fn=S.Resolve("C_Spell.IsSpellUsable")
    if not fn then return self:EvidenceBlock("CONTINUOUS_USABLE_UNKNOWN_OR_BLOCKED","可用性未知","客户端未提供技能可用性接口",true) end
    local ok,usable,power=pcall(fn,id)
    local canUse=ok and S.Public(usable,"boolean"); local insufficient=ok and S.Public(power,"boolean")
    if not ok or canUse~=true or insufficient~=false then
        local unknown=not ok or (canUse~=false and insufficient~=true)
        return self:EvidenceBlock("CONTINUOUS_USABLE_UNKNOWN_OR_BLOCKED",unknown and "可用性未知" or insufficient==true and "资源不足" or "技能不可用",
            unknown and "无法公开确认可用性或资源状态，等待重新探测" or insufficient==true and "当前资源不足，等待恢复" or "客户端确认该技能当前不可用",unknown)
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
    if binding.spellID==5019 then
        local current=publicBoolean(S.Resolve("C_ActionBar.IsCurrentAction") and "C_ActionBar.IsCurrentAction" or "IsCurrentAction",binding.slot)
        local repeating=publicBoolean(S.Resolve("C_ActionBar.IsAutoRepeatAction") and "C_ActionBar.IsAutoRepeatAction" or "IsAutoRepeatAction",binding.slot)
        -- 魔杖在两发之间仍可能处于自动重复状态，不能只凭当前动作结束重新按键。
        if current==true or repeating==true then return true end
        if current==false and repeating==false then return false end
        return nil
    end
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
function D:QueueStepAllowed(step)
    local id=step and step.spellID
    if not id then return false,"NEXT_STEP_MISSING" end
    if TEF.APL.State.Boolean("C_SpellBook.IsSpellKnown",id)~=true then return false,"NEXT_EXACT_LEARNED_UNKNOWN_OR_FALSE" end
    local ok,info=S.Call("C_Spell.GetSpellInfo",id)
    local name=ok and S.Field(info,"name","string")
    if not name then return false,"NEXT_METADATA_UNKNOWN" end
    local catalog=TEF.APL.CatalogByID[id]
    local key=catalog and catalog.key or TEF.APL.AbilityNames[name]
    local ability=key and TEF.APL.Abilities[key]
    -- 下一技能可以是引导；这不授予截断当前引导的资格。
    if not ability then return false,"NEXT_TYPE_UNKNOWN" end
    if not ({filler=true,cast=true,instant=true,channel=true})[ability.type] then return false,"NEXT_TYPE_UNSUPPORTED" end
    return true
end
-- 网络延迟仅作为有界估计，不改变客户端公开的最大预载窗口。
function D:ClientQueueWindow()
 local path=S.Resolve("C_CVar.GetCVar") and "C_CVar.GetCVar" or "GetCVar"
 local ok,value=S.Call(path,"SpellQueueWindow"); local text=ok and S.Public(value,"string")
 local ms=text and S.Public(tonumber(text),"number")
 if ms and ms>=0 and ms<=1000 then return ms/1000 end
end
function D:TimingWindow(channel)
 local e=TEF.engine; local now=TEF.APL.State.Time()
 if not e or not now then return end
 local client=self:ClientQueueWindow()
 if not client or client<=0 then return end
 local net=self.networkTiming
 if not net or net.engine~=e or now<net.at or now-net.at>=1 then
  net={engine=e,at=now}; self.networkTiming=net
  local fn=S.Resolve("GetNetStats")
  if fn then
   local got,_,__,home,world=pcall(fn)
   if got then
    home=S.Public(home,"number"); world=S.Public(world,"number")
    if home and home>=0 and home<=10000 then net.homeMS=home end
    if world and world>=0 and world<=10000 then net.worldMS=world end
   end
  end
 end
 local group=not channel and e.groupRun~=nil
 local kind=channel and "channel" or group and "group" or "ordinary"
 local options=e.db.dispatch
 local lead=S.Field(options,channel and "channelTailLead" or group and "groupQueueLead" or "castQueueLead","number")
 local mode=not channel and S.Field(options,group and "groupQueueWindowMode" or "queueWindowMode","string")
 if mode=="client" then lead=math.min(client,.5) end
 if not lead or lead<=0 or lead>.5 then return end
 local compensate=S.Field(options,group and "groupLatencyCompensation" or "latencyCompensation","boolean")
 local cap=S.Field(options,group and "groupLatencyAllowanceMax" or "latencyAllowanceMax","number") or .15
 local extra=not channel and mode~="client" and compensate==true and net.worldMS and math.min(.15,math.max(0,cap),net.worldMS/2000) or 0
 local effective=math.min(client,.5,lead+extra)
 self.timingWindow={engine=e,generation=e.generation,sampledAt=now,kind=kind,clientWindow=client,effectiveLead=effective,remaining=nil,worldLatency=net.worldMS,homeLatency=net.homeMS,latencyAllowance=extra}
 return effective,self.timingWindow
end
-- 心跳内只读预热；不发布Token、不改变推荐、不提前推进任何计数。
function D:PrepareHandoff()
 local e,r=TEF.engine,TEF.Runtime
 if not e or r.e~=e or not r.intent or TEF.UI.settingsOpen or e.maintenanceActive then self.handoff=nil; return end
 local channel=self.channelReceipt
 local isChannel=not self:HasCurrentInitiation() and channel and channel.engine==e and channel.generation==e.generation
  and channel.serial==(e.receiptSerial or 0) and channel.group==e.groupRun and channel.startMS~=nil
 if not isChannel and not self:HasCurrentInitiation() then self.handoff=nil; return end
 local enabled=e.groupRun and e.db.dispatch.groupQueue or not e.groupRun and e.db.dispatch.castQueue
 if not enabled or (isChannel and not e.db.dispatch.channelTail) then self.handoff=nil; return end
 local now=TEF.APL.State.Time(); if not now then self.handoff=nil; return end
 local old=self.handoff
 if old and old.engine==e and old.generation==e.generation and old.index==e.index
  and old.serial==(e.receiptSerial or 0) and old.targetSerial==(e.usageTargetSerial or 0)
  and now>=old.preparedAt and now-old.preparedAt<.2 then return end
 local fn=S.Resolve(isChannel and "UnitChannelInfo" or "UnitCastingInfo"); if not fn then self.handoff=nil; return end
 local got,name,_,__,startRaw,endRaw,___,____,channelID,castID=pcall(fn,"player")
 local startMS,endMS=S.Public(startRaw,"number"),S.Public(endRaw,"number")
 local id
 if isChannel then id=S.ID(channelID) else id=S.ID(castID) end
 local origin=isChannel and channel.guid or self.initiation.guid
 if not got or not S.Public(name,"string") or not startMS or not endMS or endMS<=startMS
  or now<startMS/1000 or now>=endMS/1000 or id~=(isChannel and channel.spellID or self.initiation.spellID)
  or (isChannel and startMS~=channel.startMS) then self.handoff=nil; return end
 local lead=self:TimingWindow(isChannel); if not lead then self.handoff=nil; return end
 local index=e.index; local step=e.steps and e.steps[index]
 if not step then self.handoff=nil; return end
 local prepared
 if not e.groupRun and TEF.APL:IsActive(e) then
  local target=TEF.APL:QueueTargetIdentity(e)
  local preview=e.aplPreviewSnapshot
  if not preview or preview.generation~=e.generation or preview.receiptSerial~=(e.receiptSerial or 0)
   or preview.revision~=(TEF.APL.State.revision or 0) or not preview.sampledAt
   or now<preview.sampledAt or now-preview.sampledAt>.2 then preview=nil end
  local candidate,snapshot,row=TEF.APL:PrepareQueueCandidate(e,preview)
  if candidate and target and target==TEF.APL:QueueTargetIdentity(e) then
   e.aplPreviewSnapshot=snapshot
   prepared={engine=e,generation=e.generation,receiptSerial=e.receiptSerial or 0,originGUID=origin,targetIdentity=target,
    candidate=candidate,snapshot=snapshot,policyRow=row,
    step={spellID=candidate.spellID,name=candidate.name,matchIDs={candidate.spellID},repeatCount=1}}
   if not isChannel then self.aplQueuePreparation=prepared end
   step=prepared.step
  else step=nil end
 elseif not isChannel then
  if (e.stepCasts or 0)+1>=step.repeatCount then index=index+1 end
  if e.groupRun and index>#e.steps and e.groupRun.round<e.groupRun.group.rounds then index=1 end
  step=e.steps[index]
 elseif e.completed then
  step=e.groupRun and e.groupRun.round<e.groupRun.group.rounds and e.groupRun.group.steps[1] or nil
 end
 if step and not step.group and not step.unverified and self:QueueStepAllowed(step) then self:ResolveCached(step.spellID) end
 local same=old and old.engine==e and old.generation==e.generation and old.serial==(e.receiptSerial or 0)
  and old.originGUID==origin and old.finish==endMS/1000 and old.wakeAt==endMS/1000-lead and old.targetSerial==(e.usageTargetSerial or 0)
 self.handoff={engine=e,generation=e.generation,index=e.index,serial=e.receiptSerial or 0,targetSerial=e.usageTargetSerial or 0,
  originGUID=origin,finish=endMS/1000,wakeAt=endMS/1000-lead,preparedAt=now,woken=same and old.woken or false,
  spellID=step and step.spellID,apl=prepared,channel=isChannel==true}
 if not same or old.spellID~=self.handoff.spellID then self:TraceQueue("HANDOFF_PREPARED",nil,self.handoff.spellID) end
end
-- 复用已有逐帧回调，仅比较公开时钟和截止点；不逐帧扫描候选或法术书。
function D:HandoffWakeDue()
 local h,e=self.handoff,TEF.engine
 if not h or h.woken or h.engine~=e or not TEF.Runtime.intent or TEF.Runtime.e~=e or TEF.UI.settingsOpen
  or h.generation~=e.generation or h.index~=e.index or h.serial~=(e.receiptSerial or 0)
  or h.targetSerial~=(e.usageTargetSerial or 0) then return false end
 local now=TEF.APL.State.Time()
 if not now or now<h.preparedAt or now>h.finish then return false end
 if now<h.wakeAt then return false end
 h.woken=true; self:TraceQueue("HANDOFF_TAIL_WAKE",nil,h.spellID)
 return true
end
function D:PreparedAPLState(e)
 local h=self.handoff; local p=h and h.apl; local now=TEF.APL.State.Time()
 if not h or not h.channel or not p or h.engine~=e or h.generation~=e.generation or h.index~=e.index
  or h.serial~=(e.receiptSerial or 0) or h.targetSerial~=(e.usageTargetSerial or 0)
  or not now or now<h.preparedAt or now-h.preparedAt>.2 or p.snapshot.revision~=(TEF.APL.State.revision or 0)
  or not p.snapshot.sampledAt or now<p.snapshot.sampledAt or now-p.snapshot.sampledAt>.2
  or p.targetIdentity~=TEF.APL:QueueTargetIdentity(e) then return end
 h.apl=nil; p.snapshot.readOnly=nil
 return p.snapshot
end
function D:ObserveChannelSuccess(e,id,guid)
 local start=self.channelStart
 self.channelReceipt={engine=e,generation=e.generation,serial=e.receiptSerial or 0,spellID=id,guid=guid,at=TEF.APL.State.Time(),group=e.groupRun,
  startMS=start and start.engine==e and start.guid==guid and start.spellID==id and start.startMS or nil}
end
function D:ChannelTailAllowed()
 local e=TEF.engine; local r=self.channelReceipt
 local run=e and e.groupRun
 local roundTail=e and e.completed and run and run.round<run.group.rounds
 if not e or not e.db.dispatch.channelTail or not (e.groupRun and e.db.dispatch.groupQueue or not e.groupRun and e.db.dispatch.castQueue) or not TEF.Runtime.intent
  or TEF.Runtime.e~=e or TEF.UI.settingsOpen or e.maintenanceActive or (e.completed and not roundTail)
  or publicBoolean("InCombatLockdown")~=true or self:HasCurrentInitiation() then return false end
 if not r or not r.startMS or r.engine~=e or r.generation~=e.generation or r.serial~=(e.receiptSerial or 0) or r.group~=e.groupRun or not r.at then return false end
 local fn=S.Resolve("UnitChannelInfo"); if not fn then return false end
 local ok,name,_,__,startRaw,endRaw,___,____,idRaw=pcall(fn,"player")
 local shown=S.Public(name,"string"); local startMS=S.Public(startRaw,"number"); local endMS=S.Public(endRaw,"number"); local id=S.ID(idRaw)
 local now=TEF.APL.State.Time()
 if not ok or not shown or id~=r.spellID or not startMS or not endMS or not now or endMS<=startMS
  or startMS~=r.startMS or r.at<startMS/1000 or r.at>endMS/1000 then return false end
 local castOK,castRaw=S.Call("UnitCastingInfo","player"); local _,why=S.Public(castRaw,"string")
 if not castOK or why~="NO_DATA" then return false end
 local lead,window=self:TimingWindow(true); local remaining=endMS/1000-now
 if window then window.remaining=remaining end
 if not lead or remaining<=0 or remaining>lead then return false end
 if e.groupRun and (not e.db.dispatch.groupQueue or e.groupRun.targetSerial~=(e.usageTargetSerial or 0)
  or (e.groupRun.group.maintain and TEF.SkillGroups:KeepAllowed(e,e.groupRun)~=true)) then return false end
 local nextStep
 if roundTail then nextStep=run.group.steps and run.group.steps[1]
 else nextStep=e.steps and e.steps[e.index] end
 if not self:QueueStepAllowed(nextStep) then return false end
 window.remaining=remaining; self.queueWindowSnapshot=window; self.queueWindowReason="CHANNEL_TAIL_OPEN"
 return true
end
function D:CastQueueWindow()
    self.queueWindowSnapshot=nil; self.queueAPLPreparation=nil
    self.queueWindowReason="LIFECYCLE_OR_CURRENT_INITIATION"
    local e=TEF.engine
    if not e or not (e.groupRun and e.db.dispatch.groupQueue or not e.groupRun and e.db.dispatch.castQueue) or not self.continuous or not self:HasCurrentInitiation()
        or e.maintenanceActive or not e.running or e.completed or TEF.UI.settingsOpen
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
    self.queueWindowReason="CLOCK_OR_CLIENT_WINDOW_UNKNOWN"
    local lead,window=self:TimingWindow(false)
    if not now or not lead then return nil end
    local remaining=endMS/1000-now
    window.remaining=remaining
    self.queueWindowReason=remaining<=0 and "CAST_ENDED" or "OUTSIDE_TAIL"
    if now<startMS/1000 or remaining<=0 or remaining>lead then return nil end
    if e.groupRun and (e.groupRun.targetSerial~=(e.usageTargetSerial or 0)
      or (e.groupRun.group.maintain and TEF.SkillGroups:KeepAllowed(e,e.groupRun)~=true)) then return nil end
    local apl=TEF.APL:IsActive(e)
    local preparation
    if apl then
        if self.castQueue and self.castQueue.source=="apl" then preparation=self.castQueue
        elseif self.aplQueuePreparation and self.aplQueuePreparation.engine==e
            and self.aplQueuePreparation.generation==generation and self.aplQueuePreparation.receiptSerial==serial
            and self.aplQueuePreparation.originGUID==initiation.guid
            and self.aplQueuePreparation.snapshot.sampledAt and now>=self.aplQueuePreparation.snapshot.sampledAt
            and now-self.aplQueuePreparation.snapshot.sampledAt<=.2
            and self.aplQueuePreparation.snapshot.revision==(TEF.APL.State.revision or 0) then preparation=self.aplQueuePreparation
        else
            self.queueWindowReason="APL_QUEUE_TARGET_OR_CANDIDATE_UNKNOWN"
            local targetIdentity=TEF.APL:QueueTargetIdentity(e)
            local candidate,snapshot,row=TEF.APL:PrepareQueueCandidate(e)
            if not candidate or not targetIdentity or targetIdentity~=TEF.APL:QueueTargetIdentity(e) then return nil end
            preparation={engine=e,generation=generation,receiptSerial=serial,originGUID=initiation.guid,targetIdentity=targetIdentity,candidate=candidate,snapshot=snapshot,policyRow=row,
                step={spellID=candidate.spellID,name=candidate.name,matchIDs={candidate.spellID},repeatCount=1}}
        end
        self.aplQueuePreparation=preparation
    end
    local nextIndex=index
    if not apl and (e.stepCasts or 0)+1>=step.repeatCount then nextIndex=index+1 end
    -- 技能组可在同一组内接续下一轮，不能跨到父列表。
    local run=e.groupRun
    if run and nextIndex>#e.steps and run.round<run.group.rounds then nextIndex=1 end
    local nextStep=preparation and preparation.step or e.steps[nextIndex]
    self.queueWindowReason="NEXT_STEP_OR_GROUP_BOUNDARY"
    if not nextStep or nextStep.group or nextStep.unverified then return nil end
    if nextStep.spellID==initiation.spellID and TEF.APL.Custom:HasInternalCooldown(preparation and preparation.policyRow or nextStep) then
        self.queueWindowReason="NEXT_INTERNAL_COOLDOWN"
        return nil
    end
    local eligible,typeReason=self:QueueStepAllowed(nextStep)
    if not eligible then self.queueWindowReason=typeReason; return nil end
    self.queueWindowReason="NEXT_BEHAVIOR_NOT_CONTINUOUS"
    if (step.behavior and step.behavior.trigger~="continuous") or (nextStep.behavior and nextStep.behavior.trigger~="continuous") then return nil end
    self.queueWindowReason="NEXT_USAGE_BLOCKED_OR_UNKNOWN"
    if e:UsageEligibility(nextIndex)~=true then return nil end
    if generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0)
        or self.initiation~=initiation or not self.continuous or not self.enabled
        or TEF.UI.settingsOpen or not self:HasCurrentInitiation() then return nil end
    self.queueAPLPreparation=preparation
    self.queueWindowReason="WINDOW_OPEN"
    window.remaining=remaining; self.queueWindowSnapshot=window
    return nextIndex,nextStep
end
function D:TryCastQueue()
    local nextIndex,step=self:CastQueueWindow()
    if not nextIndex then return false end
    local e=TEF.engine
    if self.castQueue then return true end
    if self.castQueueAttempt==self.initiation.guid then return false end
    local generation,index,serial,initiation=e.generation,e.index,e.receiptSerial or 0,self.initiation
    if step.skipUnavailable and TEF.Recommendation:Source(e)=="manual" and self:Unavailable(step.spellID)~=false then self.queueWindowReason="NEXT_UNAVAILABLE_OR_UNKNOWN"; return false end
    local policyAllowed=self:ManualPolicy(e,step,true)
    if policyAllowed~=true then self.queueWindowReason="NEXT_POLICY_BLOCKED_OR_UNKNOWN"; return false end
    local allowed,reason=self:ContinuousEvidence(step.spellID,step,self.queueAPLPreparation)
    if not allowed then self.queueWindowReason=reason or "NEXT_EVIDENCE_BLOCKED_OR_UNKNOWN"; return false end
    if not allowed or generation~=e.generation or index~=e.index or serial~=(e.receiptSerial or 0)
        or self.initiation~=initiation or not self.continuous then return false end
    local q={generation=generation,index=index,receiptSerial=serial,
        nextIndex=nextIndex,spellID=step.spellID,originGUID=initiation.guid}
    if e.groupRun and nextIndex==1 and index==#e.steps and (e.stepCasts or 0)+1>=e.steps[index].repeatCount then
        q.groupRun=e.groupRun; q.nextRound=e.groupRun.round+1
    end
    local prepared=self.queueAPLPreparation
    if prepared then q.source="apl"; q.targetIdentity=prepared.targetIdentity; q.candidate=prepared.candidate; q.snapshot=prepared.snapshot; q.step=prepared.step; q.policyRow=prepared.policyRow end
    local snapshot=self.queueWindowSnapshot
    q.windowSnapshot=snapshot
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
        self:Cancel("CONTINUOUS_SUCCESS_RECOMMENDATION_CHANGED")
        self.waitReceipt=nil; self.initiation=nil
        return
    end
    if q.nextRound then e:PromoteQueuedRound(q,guid) end
    if guid~=q.originGUID or e.generation~=q.generation or e.index~=q.nextIndex
        or (e.receiptSerial or 0)~=q.receiptSerial+1 or e.completed then
        self:DropCastQueue(); self:Cancel("CAST_QUEUE_INVALIDATED"); return
    end
    self:TraceQueue(q.guid and "QUEUE_CURRENT_SUCCESS_WITH_IDENTITY" or "QUEUE_CURRENT_SUCCESS_NO_NEXT_IDENTITY",nil,q.spellID,guid,q)
    if q.source=="apl" then
        e.steps=TEF.Engine.Validate({q.step}); e.index=1
        e.aplCandidate=q.candidate; e.aplSnapshot=q.snapshot; e.aplPreviewSnapshot=q.snapshot
        q.snapshot.generation=e.generation; q.snapshot.receiptSerial=e.receiptSerial or 0; q.snapshot.revision=TEF.APL.State.revision or 0
    end
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
    local pending=self.pending
    if pending and pending.diagnosticPublished and pending.requestedAt and not self:HasCurrentInitiation()
        and current and current.spellID~=5019 and current.spellID~=6603 and current.spellID~=75
        and TEF.Runtime.e==e and TEF.Runtime.intent and self:CastIdle() then
        local now=TEF.APL.State.Time()
        -- 只释放一直没有起手的普通请求，成功等待及预载身份继续受原门禁保护。
        if now and now-pending.requestedAt>=.75 and self.pending==pending then
            e:Log("transport","CONTINUOUS_INITIATION_TIMEOUT",current.spellID)
            TEF.Runtime:Suspend("CONTINUOUS_INITIATION_TIMEOUT")
            TEF.Runtime:DeferRetry()
            return
        end
    end
    if TEF.Runtime and TEF.Runtime.e==e and TEF.Runtime.intent
        and not self.pending and self.waitReceipt==(e.receiptSerial or 0) and not self:HasCurrentInitiation() then
        self.waitReceipt=nil; self.initiation=nil
        e:Log("transport","CONTINUOUS_UNINITIATED_WAIT_RELEASED")
    end
    if self:HasCurrentInitiation() or self.waitReceipt==(e.receiptSerial or 0) then
        self:ContinuousStatus("CONTINUOUS_WAIT_CURRENT_RECEIPT"); return
    end
    if self.pending then return end
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
-- 保留旧配置字段用于识别普通派发路径；起手后统一等待回执。
function D:OrdinaryContinuous()
    local e=TEF.engine; local r=TEF.Runtime
    local step=e and e.steps and e.steps[e.index]
    return r and r.e==e and r.intent and not e.groupRun and e.db.dispatch.ordinaryContinuous==true
        and step and step.spellID~=5019 and step.spellID~=6603 and step.spellID~=75 or false
end
function D:TransportCastAllowed(continuous)
    if self:ChannelTailAllowed() then return true end
    if TEF.engine.db.dispatch.ordinaryContinuous and self.channelInputLock then return false end
    return self:CastIdle()
end
function D:Request(fromContinuous,queue)
    -- The test button cannot revoke or replace an automatic request (S37).
    if fromContinuous~=true and self.continuous then
        if self.pending then return true,"TEK_REQUEST_ALREADY_PENDING" end
        return false,"TEK_AUTOMATIC_OWNS_REQUEST"
    end
    self:Cancel()
    local e=TEF.engine; local step=queue and queue.step or (e.steps and e.steps[queue and queue.nextIndex or e.index])
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
    elseif not queue and not self:TransportCastAllowed(fromContinuous==true) then blocked="TEK_CAST_PRESENT_OR_UNKNOWN"
    elseif not queue and self:HasCurrentInitiation() then blocked="CONTINUOUS_WAIT_CURRENT_RECEIPT" end
    if blocked then e:Log("transport",blocked); return false,blocked end
    -- 普通连续请求复用本轮决策；最终Packet仍强制实时复核。
    -- 手工请求与预载保留独立实时检查。
    local policyAllowed,policyReason=self:ManualPolicy(e,step,fromContinuous~=true or queue~=nil)
    if policyAllowed~=true then return false,policyReason end
    local eligible,usageReason,usageContext=e:UsageEligibility(queue and queue.nextIndex or e.index)
    if eligible~=true then return false,usageReason end
    if TEF.APL and TEF.APL:IsActive(e) then
        local allowed,reason=TEF.APL:Allowed(e,step.spellID,queue)
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
    self.pending={generation=e.generation,index=e.index,binding=binding,receiptSerial=serial,castQueue=queue,usageContext=usageContext,requestedAt=TEF.APL.State.Time()}
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
    if not p.castQueue and self:HasCurrentInitiation() then self:Cancel("CONTINUOUS_WAIT_CURRENT_RECEIPT"); return nil end
    local policyStep=p.castQueue and p.castQueue.step or (e.steps and e.steps[p.castQueue and p.castQueue.nextIndex or e.index])
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
    if self:ShootActive(p.binding)~=false then self:Cancel("SHOOT_ACTIVE_OR_UNKNOWN"); return nil end
    if self.continuous then
        local allowed,reason=self:ContinuousEvidence(p.binding.spellID,policyStep,p.castQueue)
        if not allowed then self:Block(reason); return nil end
        if self.pending~=p or not self.continuous or e.generation~=p.generation or e.index~=p.index then return nil end
    elseif TEF.APL and TEF.APL:IsActive(e) then
        -- 连续路径已在ContinuousEvidence实时复查；单次请求仍独立复查。
        local allowed,reason=TEF.APL:Allowed(e,p.binding.spellID)
        if not allowed then self:Cancel(reason); return nil end
    end
    local ok,rawCombat=S.Call("InCombatLockdown")
    local combat
    if ok then combat=S.Public(rawCombat,"boolean") end
    if combat==nil then self:Cancel("TEK_COMBAT_UNKNOWN"); return nil end
    if TEF.Runtime and TEF.Runtime.e==e and TEF.Runtime.intent and combat==false and e.db.dispatch.mode=="manual"
        and not TEF.Runtime:CombatAllowed(e,combat) then self:Cancel("RUNTIME_MANUAL_START_REQUIRED"); return nil end
    if e.groupRun and not e.maintenanceActive and not TEF.Runtime:GroupCombatAllowed(e,combat) then self:Cancel("GROUP_COMBAT_REQUIRED"); return nil end
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
    if owned and TEF.SkillGroups:ObserveStart(e,event,unitValue,spellValue,guid) then
        eventGeneration,eventIndex=e.generation,e.index
    end
    if unitValue=="player" and event=="UNIT_SPELLCAST_CHANNEL_START" then
        self.channelInputLock=true
        local channelGUID=guid
        if not channelGUID and self:HasCurrentInitiation() and self.initiation.spellID==spellValue then channelGUID=self.initiation.guid end
        local fn=S.Resolve("UnitChannelInfo")
        if fn and channelGUID then
            local ok,_,__,___,startRaw,____,_____,______,channelID=pcall(fn,"player")
            local startMS=S.Public(startRaw,"number")
            if ok and startMS and S.ID(channelID)==spellValue then
                self.channelStart={engine=e,generation=e.generation,guid=channelGUID,spellID=spellValue,startMS=startMS}
                local receipt=self.channelReceipt
                if receipt and receipt.engine==e and receipt.guid==channelGUID and receipt.serial==(e.receiptSerial or 0) then receipt.startMS=startMS end
            end
        end
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
        if nextStep and not nextStep.group and not step.behavior and not nextStep.behavior and not TEF.APL.Custom:HasInternalCooldown(nextStep) and nextStep.spellID==spellValue and spellValue==self.initiation.spellID then
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
                e.attemptSerial=(e.attemptSerial or 0)+1
                e.associations[guid]={generation=e.generation,index=q.nextIndex,spellID=q.spellID,receiptSerial=q.receiptSerial+1,usageContext=q.usageContext,attempt=e.attemptSerial,request=q.request,policyRow=q.policyRow or e.steps[q.nextIndex],policyStamp=TEF.APL.Custom:PolicyStamp(e,q.policyRow or e.steps[q.nextIndex])}
            end
            self:ObserveDeliveryInitiation(spellValue,guid)
            self:Cancel("CAST_QUEUE_INITIATED"); return true
        elseif failure or event=="UNIT_SPELLCAST_SUCCEEDED" then
            if not q.guid or guid~=q.guid then
                -- 终态只封存它自己的身份，不借同ID终态撤销另一项预载。
                if not e.seen[guid] then
                    if e.seenCount>=4096 then e.identitySaturated=true; runtime:Fault("CAST_QUEUE_IDENTITY_CAPACITY"); return true end
                    e.seen[guid]="retired"; e.seenCount=e.seenCount+1
                end
                self:TraceQueue("QUEUE_UNASSOCIATED_EVENT_IGNORED",event,spellValue,guid,q)
            elseif guid==q.guid then
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
    local adoptedFailure=owned and runtime.intent and e.groupRun and failure and unitValue=="player"
        and self:HasCurrentInitiation() and self.initiation.guid==guid and self.initiation.spellID==spellValue
    if self.continuous or adoptedFailure or (owned and runtime.intent and runtime.reason=="CONTINUOUS_MOVING_OR_UNKNOWN" and failure) then
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
                elseif a and a.generation==generation and a.index==index and a.spellID==spell
                    and a.receiptSerial==(e.receiptSerial or 0) and not a.failed then
                    -- Failed and invalidated initiations share Engine's existing
                    -- lifetime tombstones. Never evict: delayed events must stay
                    -- retired, but there is no redundant 128-attempt budget.
                    if not e.seen[guid] then
                        if e.seenCount>=4096 then e.identitySaturated=true; runtime:Fault("CONTINUOUS_FAILED_IDENTITY_CAPACITY"); return true end
                        e.seen[guid]="retired"; e.seenCount=e.seenCount+1
                    end
                    local reason=moving==true and "CONTINUOUS_MOVEMENT_FAILURE_RETRY" or (moving==false and "CONTINUOUS_FAILURE_RETRY" or "CONTINUOUS_FAILURE_MOVEMENT_UNKNOWN")
                    e:Log("observed",reason,spell,nil,nil,event)
                    runtime:Suspend(reason); runtime:DeferRetry(true); return true
                else
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
        self:ObserveDeliveryInitiation(spell,guid)
        self:TraceQueue("DISPATCH_INITIATION_CONFIRMED",event,spell,guid)
        self:Cancel("TEK_GAME_EVENT_RECEIVED")
    end
end
