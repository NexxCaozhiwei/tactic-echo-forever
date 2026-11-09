local T,F=...
local test,eq,receipt=F.test,F.eq,F.receipt
local now=12.29
local function fixture(repeats)
    F.runtimeFixture("manual")
    T.engine.steps=T.Engine.Validate({
        {name="A",spellID=116,matchIDs={116},repeatCount=repeats or 1},
        {name="B",spellID=205,matchIDs={205}}})
    T.engine.db.dispatch.castQueue=true
    C_SpellBook={IsSpellKnown=function() return true end}
    InCombatLockdown=function() return true end
    C_CVar=nil; GetCVar=function() return "400" end
    GetTime=function() return now end
    UnitCastingInfo=function() return nil end
    UnitChannelInfo=function() return nil end
    GetActionInfo=function(slot) return "spell",slot==1 and 116 or 205 end
    ActionButton1={action=1,GetAttribute=function(self) return self.action end}
    ActionButton2={action=2,GetAttribute=function(self) return self.action end}
    GetBindingKey=function(command) return command=="ACTIONBUTTON1" and "1" or "2" end
    T.Dispatch:ClearBindingCache()
    T.Runtime:Start(false); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",116,"queue-A")
    assert(T.Dispatch:HasCurrentInitiation(),"fixture running="..tostring(T.engine.running).." continuous="..tostring(T.Dispatch.continuous).." reason="..tostring(T.engine.lastReason).." step="..tostring(T.engine.steps[1].spellID))
    UnitCastingInfo=function() return "A",nil,nil,10000,12500,nil,nil,false,116 end
    now=12.29
end
local function tick() T.Runtime:Reconcile(); T.Dispatch:TickContinuous() end

test("handoff_prepares_binding_without_request_or_progress_and_wakes_once",function()
 fixture(); now=12
 local e=T.engine; local request=T.Runtime.requestSerial
 local resolver=T.Dispatch.Resolve; local calls=0
 T.Dispatch.Resolve=function(self,id) calls=calls+1; return resolver(self,id) end
 T.Dispatch:PrepareHandoff(); assert(T.Dispatch.handoff); eq(T.Dispatch.handoff.spellID,205)
 eq(T.Dispatch.pending,nil); eq(T.Dispatch.castQueue,nil); eq(e.index,1)
 eq(T.Runtime.requestSerial,request); eq(e.receiptSerial or 0,0)
 T.Dispatch:PrepareHandoff(); eq(calls,1)
 now=12.29; eq(T.Dispatch:HandoffWakeDue(),false)
 now=12.31; assert(T.Dispatch:HandoffWakeDue()); eq(T.Dispatch:HandoffWakeDue(),false)
 e:UsageTargetChanged(); eq(T.Dispatch:HandoffWakeDue(),false)
 T.Dispatch.Resolve=resolver
end)

test("shared_frame_callback_can_detect_tail_between_full_heartbeats",function()
 fixture(); local e=T.engine; e.db.dispatch.castQueueLead=.05
 now=12.4; T.Dispatch:PrepareHandoff()
 T.Transport.elapsed=0
 local update=T.Transport.frame:GetScript("OnUpdate")
 assert(update); now=12.46; update(T.Transport.frame,.001)
 assert(T.Dispatch.castQueue); assert(T.Dispatch.pending)
 eq(T.Dispatch.pending.binding.spellID,205); eq(e.index,1); eq(e.receiptSerial or 0,0)
 T.Runtime:Stop(); eq(T.Dispatch.handoff,nil)
end)

test("delivery_frame_segments_keep_identity_wrap_bounds_and_exact_initiation",function()
 fixture(); now=12.31; tick()
 local e=T.engine
 T.Transport.sequence=65534; T.Transport.freshness=65534
 assert(T.Transport:Paint()); assert(T.Transport:Paint())
 local rows=e.db.deliveryDiagnostics; local row=rows[#rows]
 eq(row.firstSequence,65535); eq(row.lastSequence,0); eq(row.token,T.Dispatch.pending.binding.token)
 now=12.35; receipt("UNIT_SPELLCAST_SENT",205,"delivery-next")
 eq(row.initiatedAt,12.35); eq(row.guid,"delivery-next"); eq(e.receiptSerial or 0,0)
 local reloaded=T.Engine.New(T.Config,e.db)
 eq(reloaded.db.deliveryDiagnostics[#reloaded.db.deliveryDiagnostics].guid,"delivery-next")
 receipt("UNIT_SPELLCAST_SUCCEEDED",116,"queue-A")
 receipt("UNIT_SPELLCAST_SUCCEEDED",205,"delivery-next"); eq(e.receiptSerial,2)
 fixture(); now=12.31; tick()
 for i=1,140 do T.Dispatch:ObservePublishedFrame(i*2,i*2,T.Dispatch.pending.binding.token) end
 eq(#T.engine.db.deliveryDiagnostics,128); assert(T.engine.db.deliveryEvicted>0)
end)

test("timing_settings_migrate_independently_and_reject_secret",function()
 local c=T.Runtime.Clean({castQueueLead=.3,latencyCompensation=false,channelTailLead=.2})
 eq(c.groupQueueLead,.3); eq(c.groupLatencyCompensation,false); eq(c.channelTailLead,.2)
 c=T.Runtime.Clean({groupQueueLead=F.secret,groupLatencyCompensation=F.secret})
 eq(c.groupQueueLead,.2); eq(c.groupLatencyCompensation,false)
 eq(T.Runtime.Clean({groupQueueLead=9,latencyAllowanceMax=9,groupLatencyAllowanceMax=-1}).groupQueueLead,.5)
 fixture(); local e=T.engine
 eq(T.Runtime:SetTimingOption("groupQueueLead",F.secret),false); eq(T.Runtime.intent,true)
 eq(T.Runtime:SetTimingOption(F.secret,.1),false)
 assert(T.Runtime:SetTimingOption("groupQueueLead",.3)); eq(T.Runtime.intent,false)
 eq(e.db.dispatch.groupQueueLead,.3); eq(e.db.dispatch.castQueueLead,.2)
 eq(T.Runtime:SetTimingOption("groupLatencyAllowanceMax",.2),false)
 eq(T.Runtime:SetTimingOption("queueWindowMode","unexpected"),false)
end)

test("group_and_ordinary_windows_are_independent_and_client_mode_caps",function()
 fixture(); local e=T.engine; local previous=GetNetStats
 GetNetStats=function() return 0,0,20,400 end
 e.db.dispatch.castQueueLead=.2; e.db.dispatch.latencyAllowanceMax=.03
 eq(T.Dispatch:TimingWindow(false),.23)
 e.groupRun={targetSerial=e.usageTargetSerial or 0,round=1,group={maintain=false,rounds=1}}
 e.db.dispatch.castQueue=false; e.db.dispatch.groupQueue=true
 e.db.dispatch.groupQueueLead=.3; e.db.dispatch.groupLatencyCompensation=false
 eq(T.Dispatch:TimingWindow(false),.3)
 e.db.dispatch.groupLatencyCompensation=true; e.db.dispatch.groupLatencyAllowanceMax=.01
 eq(T.Dispatch:TimingWindow(false),.31)
 e.db.dispatch.groupLatencyCompensation=false
 now=12.25; assert(T.Dispatch:CastQueueWindow())
 e.db.dispatch.groupQueueLead=0; eq(T.Dispatch:CastQueueWindow(),nil)
 e.db.dispatch.groupQueueWindowMode="client"; eq(T.Dispatch:TimingWindow(false),.4)
 eq(T.Dispatch.timingWindow.latencyAllowance,0)
 assert(T.Dispatch:CastQueueWindow())
 GetCVar=function() return "50" end; eq(T.Dispatch:TimingWindow(false),.05)
 e.groupRun=nil; e.db.dispatch.castQueueLead=0
 eq(T.Dispatch:TimingWindow(false),nil)
 e.db.dispatch.queueWindowMode="client"; eq(T.Dispatch:TimingWindow(false),.05)
 GetCVar=function() return F.secret end; eq(T.Dispatch:TimingWindow(false),nil)
 GetNetStats=previous
end)

test("arcane_wrath_semantic_type_never_authorizes_unknown_learned_id",function()
 fixture(); now=12.31
 local info,known=C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown
 local e=T.engine; e.steps[2]=T.Engine.Validate({{spellID=1326079,name="奥术愤怒",matchIDs={1326079}}})[1]
 C_Spell.GetSpellInfo=function(id) if id==1326079 then return {name="奥术愤怒"} end; return info(id) end
 GetActionInfo=function(slot) return "spell",slot==1 and 116 or 1326079 end
 C_SpellBook.IsSpellKnown=function(id) return id==1326079 or known(id) end
 T.Dispatch:ClearBindingCache(); assert(T.Dispatch:TryCastQueue()); eq(T.Dispatch.castQueue.spellID,1326079)
 C_SpellBook.IsSpellKnown=function(id) if id==1326079 then return F.secret end; return known(id) end
 T.APL.State:Invalidate("SPELLS_CHANGED"); T.Dispatch.manualPolicySnapshot=nil
 eq(T.Dispatch:Packet(),nil)
 C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown=info,known
end)

test("unrelated_queue_terminal_keeps_accepted_identity_and_success_order",function()
 fixture(); now=12.31; tick()
 receipt("UNIT_SPELLCAST_SENT",205,"accepted-next")
 local queue=T.Dispatch.castQueue
 receipt("UNIT_SPELLCAST_FAILED_QUIET",205,"unrelated-failed")
 eq(T.Dispatch.castQueue,queue); eq(queue.guid,"accepted-next"); eq(T.engine.receiptSerial or 0,0)
 eq(T.engine.seen["unrelated-failed"],"retired")
 receipt("UNIT_SPELLCAST_SUCCEEDED",116,"queue-A")
 receipt("UNIT_SPELLCAST_SUCCEEDED",205,"accepted-next")
 eq(T.engine.receiptSerial,2); eq(T.engine.completed,true)
end)

test("window_log_keeps_sample_age_and_never_reuses_other_generation",function()
 fixture(); now=12.31; tick(); local q=T.Dispatch.castQueue
 now=12.4; T.Dispatch:TraceQueue("AGE_TEST")
 local row=T.engine.db.queueDiagnostics[#T.engine.db.queueDiagnostics]
 eq(row.windowSampledAt,12.31); assert(row.windowAge>.08); eq(row.windowKind,"ordinary")
 T.engine.generation=T.engine.generation+1; T.Dispatch.castQueue=nil; T.Dispatch.pending=nil
 T.Dispatch:TraceQueue("STALE_TEST")
 row=T.engine.db.queueDiagnostics[#T.engine.db.queueDiagnostics]; eq(row.remaining,nil)
 eq(row.windowSampledAt,nil)
end)

test("group_queue_opt_in_preserves_order_and_keep_gate",function()
 fixture(); now=12.31
 local e=T.engine
 e.groupRun={targetSerial=e.usageTargetSerial or 0,round=1,group={maintain=false,rounds=1}}
 eq(T.Dispatch:CastQueueWindow(),nil)
 e.db.dispatch.groupQueue=true
 assert(T.Dispatch:TryCastQueue()); eq(T.Dispatch.castQueue.spellID,205); assert(T.Dispatch:Packet())
 local keep=T.SkillGroups.KeepAllowed; e.groupRun.group.maintain=true
 T.SkillGroups.KeepAllowed=function() return false end
 eq(T.Dispatch:Packet(),nil)
 T.SkillGroups.KeepAllowed=keep
end)

test("group_queue_cross_round_promotes_only_on_exact_success",function()
 fixture(); local e=T.engine
 e.groupRun={targetSerial=e.usageTargetSerial or 0,round=1,group={maintain=false,rounds=2}}
 e.db.dispatch.groupQueue=true
 UnitCastingInfo=function() return nil end
 receipt("UNIT_SPELLCAST_SUCCEEDED",116,"queue-A")
 T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
 receipt("UNIT_SPELLCAST_SENT",205,"group-round-end")
 UnitCastingInfo=function() return "寒冰箭",nil,nil,10000,12500,nil,nil,false,205 end
 now=12.31
 assert(T.Dispatch:TryCastQueue()); eq(T.Dispatch.castQueue.nextIndex,1); eq(e.groupRun.round,1)
 receipt("UNIT_SPELLCAST_SENT",116,"group-round-next")
 eq(e.groupRun.round,1); eq(e.receiptSerial,1)
 receipt("UNIT_SPELLCAST_SUCCEEDED",205,"group-round-end")
 eq(e.groupRun.round,2); eq(e.index,1); eq(e.completed,false); eq(e.receiptSerial,2)
 receipt("UNIT_SPELLCAST_SUCCEEDED",116,"group-round-next"); eq(e.receiptSerial,3)
end)

test("client_window_caps_network_allowance_and_channel_budget",function()
 fixture(); local previous=GetNetStats
 GetNetStats=function() return 0,0,50,200 end
 local e=T.engine; e.db.dispatch.latencyCompensation=true
 local lead=T.Dispatch:TimingWindow(false); eq(math.floor(lead*1000+.5),300)
 e.db.dispatch.channelTailLead=.05
 eq(T.Dispatch:TimingWindow(true),.05)
 GetCVar=function() return "50" end
 eq(T.Dispatch:TimingWindow(false),.05)
 GetCVar=function() return "0" end; eq(T.Dispatch:TimingWindow(false),nil)
 GetNetStats=previous
end)

test("channel_tail_requires_success_identity_and_public_time",function()
 F.runtimeFixture("manual")
 local e=T.engine; local clock=10
 InCombatLockdown=function() return true end
 e.steps=T.Engine.Validate({{name="奥术飞弹",spellID=5143,matchIDs={5143}},{name="寒冰箭",spellID=205,matchIDs={205}}})
 e.db.dispatch.castQueue=true; e.db.dispatch.channelTail=true; e.db.dispatch.channelTailLead=.05
 GetTime=function() return clock end; GetCVar=function() return "400" end; C_CVar=nil
 GetActionInfo=function(slot) return "spell",slot==1 and 5143 or 205 end
 ActionButton1={action=1,GetAttribute=function(self) return self.action end}
 ActionButton2={action=2,GetAttribute=function(self) return self.action end}
 GetBindingKey=function(command) return command=="ACTIONBUTTON1" and "1" or "2" end
 UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
 T.Dispatch:ClearBindingCache(); T.Runtime:Start(false); T.Dispatch:TickContinuous()
 receipt("UNIT_SPELLCAST_SENT",5143,"channel-timing-origin")
 UnitChannelInfo=function() return "奥术飞弹",nil,nil,10000,13000,false,false,5143 end
 T.Dispatch:Event("UNIT_SPELLCAST_CHANNEL_START","player",5143,"channel-timing-origin")
 eq(T.Dispatch:ChannelTailAllowed(),false)
 receipt("UNIT_SPELLCAST_SUCCEEDED",5143,"channel-timing-origin")
 eq(e.index,2); eq(e.receiptSerial,1)
 T.Dispatch.channelInputLock=true
 clock=12.7; eq(T.Dispatch:ChannelTailAllowed(),false)
 clock=12.96; assert(T.Dispatch:ChannelTailAllowed())
 T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending); assert(T.Dispatch:Packet())
 UnitChannelInfo=function() return "奥术飞弹",nil,nil,10000,F.secret,false,false,5143 end
 eq(T.Dispatch:Packet(),nil)
 -- 停止事件不能把未知实时状态伪装为空闲；公开消失后复用同一调度立即接续。
 clock=13.1
 T.Dispatch:Event("UNIT_SPELLCAST_CHANNEL_STOP","player",5143,nil)
 T.Transport:Pulse("CHANNEL_STOP_RECONCILE"); eq(T.Dispatch.pending,nil)
 UnitChannelInfo=function() return nil end
 T.Dispatch:Event("UNIT_SPELLCAST_CHANNEL_STOP","player",5143,nil)
 assert(T.Transport:Pulse("CHANNEL_STOP_RECONCILE")); assert(T.Dispatch.pending)
 eq(T.Dispatch.pending.binding.spellID,205); eq(e.receiptSerial,1)
end)

test("group_final_channel_can_enter_next_round_only_in_confirmed_tail",function()
 F.runtimeFixture("manual"); local e=T.engine; local clock=10
 C_SpellBook={IsSpellKnown=function() return true end}
 InCombatLockdown=function() return true end
 local rows={{name="奥术飞弹",spellID=5143,matchIDs={5143}}}
 e.steps=T.Engine.Validate(rows)
 e.groupRun={targetSerial=e.usageTargetSerial or 0,round=1,group={steps=rows,maintain=false,rounds=2}}
 e.db.dispatch.castQueue=false; e.db.dispatch.groupQueue=true
 e.db.dispatch.channelTail=true; e.db.dispatch.channelTailLead=.05
 GetTime=function() return clock end; GetCVar=function() return "400" end; C_CVar=nil
 GetActionInfo=function() return "spell",5143 end
 ActionButton1={action=1,GetAttribute=function(self) return self.action end}
 GetBindingKey=function() return "1" end
 UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
 T.Dispatch:ClearBindingCache(); T.Runtime:Start(false); T.Dispatch:TickContinuous()
 receipt("UNIT_SPELLCAST_SENT",5143,"group-channel-round1")
 UnitChannelInfo=function() return "奥术飞弹",nil,nil,10000,13000,false,false,5143 end
 T.Dispatch:Event("UNIT_SPELLCAST_CHANNEL_START","player",5143,"group-channel-round1")
 clock=12.96; eq(T.Dispatch:ChannelTailAllowed(),false)
 receipt("UNIT_SPELLCAST_SUCCEEDED",5143,"group-channel-round1")
 eq(e.completed,true); eq(e.receiptSerial,1)
 clock=12.8; T.SkillGroups:Refresh(e); eq(e.groupRun.round,1)
 clock=12.96; T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
 eq(e.groupRun.round,2); eq(e.completed,false); eq(e.receiptSerial,1)
 assert(T.Dispatch.pending,"reason="..tostring(T.Runtime.reason).." running="..tostring(e.running).." tail="..tostring(T.Dispatch:ChannelTailAllowed()).." gen="..e.generation.." receiptGen="..tostring(T.Dispatch.channelReceipt and T.Dispatch.channelReceipt.generation)); eq(T.Dispatch.pending.binding.spellID,5143)
 receipt("UNIT_SPELLCAST_SENT",5143,"group-channel-round2")
 receipt("UNIT_SPELLCAST_SUCCEEDED",5143,"group-channel-round2")
 eq(e.receiptSerial,2); eq(e.completed,true)
 eq(T.Dispatch:ChannelTailAllowed(),false)
end)
test("queue_rejects_ground_channel_and_unknown_types",function()
 fixture(); now=12.31
 local info=C_Spell.GetSpellInfo
 for _,case in ipairs({{400001,"暴风雪"},{400002,"未知技能"}}) do
  T.engine.steps[2].spellID=case[1]
  C_Spell.GetSpellInfo=function() return {name=case[2]} end
  eq(T.Dispatch:CastQueueWindow(),nil)
 end
 T.engine.steps[2].spellID=205; C_Spell.GetSpellInfo=info
 assert(T.Dispatch:CastQueueWindow())
end)

test("queue_next_disabled_policy_never_publishes_and_current_receipt_survives",function()
    fixture(); now=12.31; T.engine.steps[2].enabled=false
    tick(); eq(T.Dispatch.castQueue,nil); eq(T.Dispatch:Packet(),nil); eq(T.engine.receiptSerial or 0,0)
    assert(T.Dispatch:HasCurrentInitiation())
    T.engine.steps[2].enabled=true; tick(); assert(T.Dispatch.castQueue); assert(T.Dispatch:Packet())
end)
test("old_channel_stop_cannot_consume_next_channel_request",function()
    fixture()
    UnitCastingInfo=function() return nil end
    UnitChannelInfo=function() return nil end
    T.Runtime:Stop(); T.engine.steps=T.Engine.Validate({
        {name="飞弹",spellID=5143,matchIDs={5143},repeatCount=2}})
    GetActionInfo=function() return "spell",5143 end
    T.Dispatch:ClearBindingCache(); T.Runtime:Start(false); T.Dispatch:TickContinuous()
    receipt("UNIT_SPELLCAST_SENT",5143,"channel-old")
    receipt("UNIT_SPELLCAST_SUCCEEDED",5143,"channel-old")
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    local pending=T.Dispatch.pending; assert(pending)
    receipt("UNIT_SPELLCAST_CHANNEL_STOP",5143,nil)
    eq(T.Dispatch.pending,pending)
    receipt("UNIT_SPELLCAST_CHANNEL_STOP",5143,"channel-old")
    eq(T.Dispatch.pending,pending)
    receipt("UNIT_SPELLCAST_SENT",5143,"channel-new")
    eq(T.Dispatch.pending,nil)
    receipt("UNIT_SPELLCAST_SUCCEEDED",5143,"channel-new")
    eq(T.engine.completed,true); eq(T.engine.receiptSerial,2)
end)
test("uninitiated_cancelled_request_releases_wait_and_reoffers",function()
    fixture(); UnitCastingInfo=function() return nil end
    -- 先消费既有起始，使当前步骤不再拥有旧回执。
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"queue-A")
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    T.Dispatch:Cancel("TEST_UNINITIATED_CANCEL")
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    assert(T.Dispatch.pending); eq(T.Dispatch.pending.binding.spellID,205)
end)
test("queued_late_start_extra_same_spell_failure_preserves_real_success",function()
    fixture(); now=12.31; tick()
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"queue-A")
    receipt("UNIT_SPELLCAST_SENT",205,"late-real-B")
    receipt("UNIT_SPELLCAST_START",205,"late-real-B")
    local generation=T.engine.generation
    receipt("UNIT_SPELLCAST_SENT",205,"extra-B")
    receipt("UNIT_SPELLCAST_FAILED_QUIET",205,"extra-B")
    eq(T.Dispatch.initiation.guid,"late-real-B")
    eq(T.engine.generation,generation); eq(T.Runtime.intent,true)
    eq(T.engine.seen["extra-B"],"retired")
    receipt("UNIT_SPELLCAST_SUCCEEDED",205,"late-real-B")
    eq(T.engine.completed,true); eq(T.engine.receiptSerial,2)
    receipt("UNIT_SPELLCAST_SUCCEEDED",205,"extra-B")
    eq(T.engine.receiptSerial,2)
end)
test("cast_queue_evidence_has_exact_event_identity_and_bounded_reload_history",function()
    fixture(); now=12.31; tick()
    assert(T.Dispatch:Packet())
    receipt("UNIT_SPELLCAST_SENT",205,"diagnostic-B")
    receipt("UNIT_SPELLCAST_FAILED",205,"diagnostic-B")
    local failure,published
    for _,row in ipairs(T.engine.db.queueDiagnostics) do
        if row.reason=="QUEUE_FAILURE_EVENT" then failure=row end
        if row.reason=="TOKEN_PUBLISHED" and row.source=="queue" then published=row end
    end
    assert(failure); eq(failure.event,"UNIT_SPELLCAST_FAILED")
    eq(failure.guid,"diagnostic-B"); eq(failure.originGUID,"queue-A")
    eq(failure.queueSpellID,205); assert(failure.queueRequest)
    assert(published); eq(published.clientWindow,.4); eq(published.effectiveLead,.2)
    T.Dispatch:TraceQueue("SECRET_GUID",nil,205,F.secret)
    eq(T.engine.db.queueDiagnostics[#T.engine.db.queueDiagnostics].guid,nil)
    for i=1,520 do T.Dispatch:TraceQueue("BOUNDED_RECORD") end
    eq(#T.engine.db.queueDiagnostics,512); assert(T.engine.db.queueEvicted>0)
    local reload=T.Engine.New(T.Config,T.engine.db)
    eq(#reload.db.queueDiagnostics,512)
    eq(reload.db.queueDiagnostics[512].reason,"BOUNDED_RECORD")
end)
test("cast_queue_adjustable_lead_zero_half_second_and_client_cap",function()
    fixture(); T.engine.db.dispatch.castQueueLead=0; now=12.49
    eq(T.Dispatch:CastQueueWindow(),nil)
    fixture(); T.engine.db.dispatch.castQueueLead=.5; GetCVar=function() return "500" end
    now=12.01; eq(T.Dispatch:CastQueueWindow(),2)
    GetCVar=function() return "200" end
    eq(T.Dispatch:CastQueueWindow(),nil)
    now=12.31; eq(T.Dispatch:CastQueueWindow(),2)
    eq(T.Runtime.Clean({}).castQueueLead,.2)
    eq(T.Runtime.Clean({castQueueLead=F.secret}).castQueueLead,.2)
    eq(T.Runtime.Clean({castQueueLead=9}).castQueueLead,.5)
    eq(T.Runtime.Clean({castQueueLead=-1}).castQueueLead,0)
    assert(T.Runtime:SetCastQueueLead(.35)); eq(T.Runtime.intent,false)
    eq(T.engine.db.dispatch.castQueueLead,.35)
    eq(T.Runtime:SetCastQueueLead(F.secret),false)
end)
test("cast_queue_public_tail_next_identity_promotes_only_after_success",function()
    fixture(); tick(); eq(T.Dispatch.pending,nil); eq(T.engine.index,1)
    now=12.31; tick(); assert(T.Dispatch.pending, "queue="..tostring(T.Dispatch:CastQueueWindow()).." state="..tostring(T.Runtime.state).." reason="..tostring(T.engine.lastReason).." initiation="..tostring(T.Dispatch:HasCurrentInitiation()))
    eq(T.Dispatch.pending.binding.spellID,205); eq(T.Dispatch:Packet(),T.Dispatch.Token("2"))
    receipt("UNIT_SPELLCAST_SENT",205,"queue-B")
    eq(T.engine.index,1); eq(T.engine.receiptSerial,nil); eq(T.Dispatch.pending,nil)
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"queue-A")
    eq(T.engine.index,2); assert(T.Dispatch:HasCurrentInitiation())
    receipt("UNIT_SPELLCAST_SUCCEEDED",205,"queue-B")
    eq(T.engine.completed,true); eq(T.engine.receiptSerial,2)
end)
test("cast_queue_same_id_repeat_does_not_replace_A_receipt",function()
    fixture(2); now=12.31; tick(); eq(T.Dispatch.pending.binding.spellID,116)
    receipt("UNIT_SPELLCAST_SENT",116,"repeat-B")
    eq(T.Dispatch.initiation.guid,"queue-A"); eq(T.engine.stepCasts,0)
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"queue-A")
    eq(T.engine.index,1); eq(T.engine.stepCasts,1); eq(T.Dispatch.initiation.guid,"repeat-B")
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"repeat-B")
    eq(T.engine.index,2); eq(T.engine.stepCasts,0)
end)
test("cast_queue_rejected_B_never_advances_or_reoffers_A_window",function()
    fixture(); now=12.31; tick(); receipt("UNIT_SPELLCAST_SENT",205,"reject-B")
    receipt("UNIT_SPELLCAST_FAILED",205,"reject-B")
    eq(T.engine.index,1); eq(T.engine.seen["reject-B"],"retired"); assert(T.Dispatch:HasCurrentInitiation())
    tick(); eq(T.Dispatch.pending,nil)
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"queue-A"); eq(T.engine.index,2)
    receipt("UNIT_SPELLCAST_SUCCEEDED",205,"reject-B"); eq(T.engine.completed,false)
end)
test("cast_queue_unassociated_terminal_retires_only_its_identity",function()
    for _,event in ipairs({"UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_SUCCEEDED"}) do
        fixture(); now=12.31; tick()
        local queue,pending=T.Dispatch.castQueue,T.Dispatch.pending
        receipt(event,205,"early-B"); eq(T.engine.index,1)
        eq(T.Dispatch.castQueue,queue); eq(T.Dispatch.pending,pending)
        eq(T.engine.seen["early-B"],"retired")
        receipt("UNIT_SPELLCAST_SENT",205,"early-B")
        receipt("UNIT_SPELLCAST_SUCCEEDED",116,"queue-A")
        receipt("UNIT_SPELLCAST_SUCCEEDED",205,"early-B"); eq(T.engine.completed,false)
    end
end)
test("cast_queue_A_failure_or_stop_retires_B_and_late_success",function()
    for _,action in ipairs({"failure","stop","reset"}) do
        fixture(); now=12.31; tick(); receipt("UNIT_SPELLCAST_SENT",205,"invalid-B")
        if action=="failure" then receipt("UNIT_SPELLCAST_INTERRUPTED",116,"queue-A")
        elseif action=="reset" then T.Runtime:Reset() else T.Runtime:Stop() end
        eq(T.Dispatch.castQueue,nil); eq(T.Dispatch.pending,nil)
        eq(T.engine.seen["invalid-B"],"retired")
        receipt("UNIT_SPELLCAST_SUCCEEDED",205,"invalid-B"); eq(T.engine.index,1)
    end
end)
test("cast_queue_secret_timing_channel_and_public_combat_fail_closed",function()
    local modifications={
        function() UnitCastingInfo=function() return "A",nil,nil,10000,F.secret,nil,nil,false,116 end end,
        function() GetTime=function() return F.secret end end,
        function() GetCVar=function() return F.secret end end,
        function() GetCVar=function() return "0" end end,
        function() UnitChannelInfo=function() return "channel" end end,
        function() UnitChannelInfo=function() return F.secret end end,
        function() InCombatLockdown=function() return false end end,
        function() UnitCastingInfo=function() return "other",nil,nil,10000,12500,nil,nil,false,143 end end,
    }
    for _,modify in ipairs(modifications) do
        fixture(); now=12.31; modify(); tick(); eq(T.Dispatch.pending,nil); eq(T.engine.index,1)
    end
end)
test("cast_queue_packet_rechecks_binding_time_focus_and_setting",function()
    for _,modify in ipairs({
        function() GetTime=function() return F.secret end end,
        function() GetBindingKey=function() return "3" end end,
        function() GetCurrentKeyBoardFocus=function() return {} end end,
        function() T.engine.db.dispatch.castQueue=false end,
    }) do
        fixture(); now=12.31; tick(); assert(T.Dispatch.pending)
        modify(); eq(T.Dispatch:Packet(),nil)
    end
end)
test("cast_queue_window_honors_smaller_client_window_and_default_off",function()
    fixture(); now=12.31; GetCVar=function() return "100" end; tick(); eq(T.Dispatch.pending,nil)
    now=12.41; tick(); assert(T.Dispatch.pending)
    fixture(); T.engine.db.dispatch.castQueue=false; now=12.31; tick(); eq(T.Dispatch.pending,nil)
    eq(T.Runtime.Clean({}).castQueue,false); eq(T.Runtime.Clean({castQueue=F.secret}).castQueue,false)
end)
test("cast_queue_reentrant_stop_during_timing_or_evidence_cannot_offer",function()
    fixture(); now=12.31
    UnitCastingInfo=function()
        T.Runtime:Stop(); return "A",nil,nil,10000,12500,nil,nil,false,116
    end
    eq(T.Dispatch:CastQueueWindow(),nil); eq(T.Dispatch.pending,nil)
    fixture(); now=12.31
    C_Spell.IsSpellUsable=function() T.Runtime:Stop(); return true,false end
    eq(T.Dispatch:TryCastQueue(),false); eq(T.Dispatch.pending,nil); eq(T.Runtime.intent,false)
end)
test("cast_queue_excludes_APL_Shoot_and_completion_allows_channel_destination",function()
    fixture(); T.engine.steps[2].spellID=5019; now=12.31; tick(); eq(T.Dispatch.pending,nil)
    fixture(); now=12.31; eq(T.Dispatch:QueueStepAllowed({spellID=5143}),true)
    fixture(); T.engine.steps[2]=nil; now=12.31; tick(); eq(T.Dispatch.pending,nil)
    fixture(); local original=T.APL.IsActive; T.APL.IsActive=function() return true end
    eq(T.Dispatch:CastQueueWindow(),nil); T.APL.IsActive=original
    T.Runtime:Stop(); UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
end)
