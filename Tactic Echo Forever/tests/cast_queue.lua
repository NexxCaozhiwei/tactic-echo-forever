local T,F=...
local test,eq,receipt=F.test,F.eq,F.receipt
local now=12.29
local function fixture(repeats)
    F.runtimeFixture("manual")
    T.engine.steps=T.Engine.Validate({
        {name="A",spellID=116,matchIDs={116},repeatCount=repeats or 1},
        {name="B",spellID=205,matchIDs={205}}})
    T.engine.db.dispatch.castQueue=true
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
test("cast_queue_failure_before_SENT_and_out_of_order_success_retire_identity",function()
    for _,event in ipairs({"UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_SUCCEEDED"}) do
        fixture(); now=12.31; tick()
        receipt(event,205,"early-B"); eq(T.engine.index,1)
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
test("cast_queue_excludes_APL_Shoot_channel_destination_and_completion",function()
    fixture(); T.engine.steps[2].spellID=5019; now=12.31; tick(); eq(T.Dispatch.pending,nil)
    fixture(); T.engine.steps[2].spellID=5143; now=12.31; tick(); eq(T.Dispatch.pending,nil)
    fixture(); T.engine.steps[2]=nil; now=12.31; tick(); eq(T.Dispatch.pending,nil)
    fixture(); local original=T.APL.IsActive; T.APL.IsActive=function() return true end
    eq(T.Dispatch:CastQueueWindow(),nil); T.APL.IsActive=original
    T.Runtime:Stop(); UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
end)
