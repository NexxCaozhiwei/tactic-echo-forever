local T,F=...
local test,eq=F.test,F.eq
local ids={116,205,143,2136}
local target,combat,serial
local function fixture(policy,repeats,mode)
    F.deliveryFixture(mode or "manual")
    target,combat,serial="target-A",true,0
    UnitGUID=function() return target end
    InCombatLockdown=function() return combat end
    local rows={}
    for i,id in ipairs(ids) do
        rows[i]={name="技能"..id,spellID=id,matchIDs={id},repeatCount=i==2 and (repeats or 1) or 1,usagePolicy=i==2 and policy or "always"}
        _G["ActionButton"..i]={action=i,GetAttribute=function() return i end}
    end
    GetActionInfo=function(slot) return "spell",ids[slot] end
    GetBindingKey=function(command) return command:match("^ACTIONBUTTON([1-4])$") end
    C_Spell.GetSpellInfo=function(id) return {name="技能"..id,minRange=0,maxRange=30} end
    C_Spell.IsSpellHelpful=function() return false end; C_Spell.IsSpellHarmful=function() return true end
    T.engine.steps=T.Engine.Validate(rows); T.engine.db.loop=true
    T.Dispatch:ClearBindingCache()
    assert(T.Runtime:SetIntent(true))
    return T.engine
end
local function reconcile()
    T.Runtime:Reconcile(); T.Runtime:Reconcile()
end
local function cast(id)
    serial=serial+1; local guid="usage-cast"..serial
    F.receipt("UNIT_SPELLCAST_SENT",id,guid); F.receipt("UNIT_SPELLCAST_SUCCEEDED",id,guid)
    reconcile()
end
local function firstLoop(repeats)
    cast(116); for _=1,repeats or 1 do cast(205) end; cast(143); cast(2136)
end
test("usage_target_ABCD_then_ACD_and_new_target_rearms",function()
    local e=fixture("target"); firstLoop(); eq(e.index,1)
    cast(116); eq(e.index,3); cast(143); cast(2136)
    target="target-B"; T.Runtime:Suspend("RUNTIME_TARGET_CHANGED"); reconcile()
    cast(116); eq(e.index,2); cast(205); cast(143); cast(2136)
    target="target-A"; T.Runtime:Suspend("RUNTIME_TARGET_CHANGED"); reconcile()
    cast(116); eq(e.index,3)
end)
test("usage_combat_survives_target_change_and_rearms_after_exit",function()
    local e=fixture("combat"); firstLoop()
    target="target-B"; T.Runtime:Suspend("RUNTIME_TARGET_CHANGED"); reconcile()
    cast(116); eq(e.index,3); cast(143); cast(2136)
    combat=false; reconcile(); combat=true; reconcile()
    cast(116); eq(e.index,2)
end)
test("usage_repeat_count_marks_only_after_final_success",function()
    local e=fixture("target",2); cast(116); cast(205)
    eq(e.index,2); eq(e.stepCasts,1); assert(e:UsageEligibility())
    serial=serial+1; F.receipt("UNIT_SPELLCAST_SENT",205,"failed"..serial)
    F.receipt("UNIT_SPELLCAST_FAILED",205,"failed"..serial); reconcile()
    eq(e.stepCasts,1); assert(e:UsageEligibility())
    cast(205); eq(e.index,3); eq(e:UsageEligibility(2),false)
end)
test("usage_partial_count_cannot_cross_target_or_battle_scope",function()
    for _,policy in ipairs({"target","combat"}) do
        local e=fixture(policy,2); cast(116); cast(205); eq(e.stepCasts,1)
        if policy=="target" then target="target-B" else combat=false; reconcile(); combat=true end
        reconcile(); eq(e.stepCasts,0); cast(205); eq(e.index,2); eq(e.stepCasts,1)
    end
end)
test("usage_pause_preserves_reset_and_reload_clear_records",function()
    local e=fixture("target"); firstLoop(); T.Runtime:Stop(); eq(e:UsageEligibility(2),false)
    assert(T.Runtime:SetIntent(true)); cast(116); eq(e.index,3)
    T.Runtime:Reset(); eq(e.usage,nil); assert(e:UsageEligibility(2))
    local copy=T.Engine.New({{name="B",spellID=205,matchIDs={205},usagePolicy="target"}},e.db)
    eq(copy.usage,nil); assert(copy:UsageEligibility())
end)
test("usage_automatic_target_reset_preserves_combat_marks",function()
    local e=fixture("combat"); firstLoop()
    target="target-B"; T.Runtime:ResetCycle("LOOP_TARGET_RESET"); reconcile()
    cast(116); eq(e.index,3)
end)
test("usage_unknown_and_secret_target_existence_never_send_or_count",function()
    for _,unknown in ipairs({F.secret,false}) do
        local e=fixture("target"); cast(116)
        UnitExists=function() if unknown~=false then return unknown end end
        reconcile(); eq(e.index,2); eq(T.Runtime.intent,true); eq(T.Runtime.state,"blocked")
        T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil)
        F.receipt("UNIT_SPELLCAST_SENT",205,"unknown"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",205,"unknown")
        eq(e.index,2); eq(e.stepCasts,0)
    end
    local e=fixture("combat"); cast(116); InCombatLockdown=function() return F.secret end
    reconcile(); eq(e.index,2); eq(T.Dispatch.pending,nil)
end)
test("usage_packet_revokes_on_target_change_before_event",function()
    local e=fixture("target"); cast(116); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    target="target-B"; eq(T.Dispatch:Packet(),nil); eq(T.Dispatch.pending,nil); eq(e.index,2)
end)
test("usage_receipt_target_change_does_not_consume_new_target",function()
    local e=fixture("target"); cast(116)
    F.receipt("UNIT_SPELLCAST_SENT",205,"old-target"); target="target-B"
    F.receipt("UNIT_SPELLCAST_SUCCEEDED",205,"old-target"); eq(e.index,2); eq(e.stepCasts,0)
    assert(e:UsageEligibility())
end)
test("usage_all_limited_loop_waits_without_empty_spinning",function()
    local e=fixture("target")
    e.steps=T.Engine.Validate({{name="B",spellID=205,matchIDs={205},usagePolicy="target"}})
    reconcile(); cast(205); eq(e.index,1); eq(T.Runtime.reason,"SEQUENCE_USAGE_EXHAUSTED")
    local generation=e.generation
    for _=1,20 do T.Runtime:Reconcile() end
    eq(e.generation,generation); eq(T.Dispatch.pending,nil)
    target="target-B"; reconcile(); eq(e.running,true); assert(e:UsageEligibility())
end)
test("usage_attack_confirmation_marks_6603_without_fake_receipt",function()
    local e=fixture("target"); ids[2]=6603
    e.steps=T.Engine.Validate({{name="攻击",spellID=6603,matchIDs={6603},usagePolicy="target"},{name="A",spellID=116,matchIDs={116}}})
    IsCurrentAction=function() return true end; T.Dispatch:ClearBindingCache()
    reconcile(); eq(e.index,2); eq(e:UsageEligibility(1),false)
    cast(116); eq(e.index,2); ids[2]=205
end)
test("usage_configuration_roundtrip_ui_and_invalid_policy",function()
    fixture("target")
    local rows=assert(T.Profiles:Parse("205:205*3!skip!target\n143:143!combat"))
    eq(rows[1].usagePolicy,"target"); eq(rows[1].repeatCount,3); eq(rows[1].skipUnavailable,true)
    eq(rows[2].usagePolicy,"combat")
    local copy=assert(T.Profiles:Parse(T.Profiles:RowsText(rows))); eq(copy[1].usagePolicy,"target")
    eq(T.Profiles:Parse("205:205!bad"),nil)
    eq(T.Engine.Validate({{name="B",spellID=205,matchIDs={205},usagePolicy=F.secret}}),nil)
    T.UI:WriteDraft(rows); assert(T.UI:EditSequenceRow(1,"usage","combat"))
    eq(T.UI:DraftRows()[1].usagePolicy,"combat")
    assert(T.Profiles:Save(T.engine,T.engine.scene,T.UI:DraftRows()))
    eq(T.engine.db.profiles[T.engine.scene][1].usagePolicy,"combat")
end)
test("usage_target_capacity_fails_closed_without_eviction",function()
    local e=fixture("target"); cast(116)
    e.usage.targetCount=256
    local allowed,reason=e:UsageEligibility(); eq(allowed,nil); eq(reason,"SEQUENCE_USAGE_CAPACITY")
    reconcile(); eq(T.Dispatch.pending,nil)
end)
test("usage_public_api_reentry_cannot_skip_or_advance_stopped_sequence",function()
    local e=fixture("target"); firstLoop(); cast(116)
    -- 当前B已使用；公开查询期间停止必须撤销推进。
    e.index=2; UnitGUID=function() T.Runtime:Stop(); return target end
    T.Runtime:Reconcile(); eq(T.Runtime.intent,false); eq(e.index,2); eq(T.Dispatch.pending,nil)
end)
test("usage_out_of_combat_manual_start_carries_into_combat",function()
    local e=fixture("combat",1,"auto"); combat=false; reconcile()
    cast(116); cast(205); eq(e:UsageEligibility(2),false)
    combat=true; reconcile(); cast(143); cast(2136); cast(116); eq(e.index,3)
end)
test("usage_queue_refuses_used_step_and_preserves_new_step_context",function()
    for _,used in ipairs({true,false}) do
        local e=fixture("target")
        if used then firstLoop() end
        e.db.dispatch.castQueue=true; GetCVar=function() return "400" end
        C_CVar=nil; GetTime=function() return 12.31 end
        T.Dispatch:TickContinuous()
        F.receipt("UNIT_SPELLCAST_SENT",116,"queue-usage-A")
        UnitCastingInfo=function() return "A",nil,nil,10000,12500,nil,nil,false,116 end
        T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
        if used then
            eq(T.Dispatch.castQueue,nil); eq(T.Dispatch:CastQueueWindow(),nil)
        else
            assert(T.Dispatch.castQueue); assert(T.Dispatch:Packet())
            F.receipt("UNIT_SPELLCAST_SENT",205,"queue-usage-B")
            F.receipt("UNIT_SPELLCAST_SUCCEEDED",116,"queue-usage-A")
            F.receipt("UNIT_SPELLCAST_SUCCEEDED",205,"queue-usage-B")
            eq(e.index,3); eq(e:UsageEligibility(2),false)
        end
        UnitCastingInfo=function() return nil end
    end
end)
test("usage_final_packet_guard_catches_scope_change_in_binding_api",function()
    fixture("target"); cast(116); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    GetBindingKey=function(command) target="target-B"; return command:match("^ACTIONBUTTON([1-4])$") end
    eq(T.Dispatch:Packet(),nil); eq(T.Dispatch.pending,nil)
end)
test("usage_old_battle_receipt_retires_and_new_scope_can_retry",function()
    local e=fixture("combat"); cast(116)
    F.receipt("UNIT_SPELLCAST_SENT",205,"old-battle")
    combat=false; reconcile(); eq(e.seen["old-battle"],"retired")
    F.receipt("UNIT_SPELLCAST_SUCCEEDED",205,"old-battle")
    eq(e.index,2); eq(e.stepCasts,0)
    combat=true; reconcile(); cast(205); eq(e.index,3)
end)
test("usage_secret_guid_uses_public_selection_and_rearms_on_target_event",function()
    local e=fixture("target")
    e:UsageTargetChanged(); UnitGUID=function() return F.secret end
    firstLoop(); cast(116); eq(e.index,3); eq(e.usageTarget.kind,"selection")
    cast(143); cast(2136)
    e:UsageTargetChanged(); T.Runtime:Suspend("RUNTIME_TARGET_CHANGED"); reconcile()
    cast(116); eq(e.index,2); cast(205); eq(e.index,3)
    eq(e.usage.targetCount,2)
end)
test("usage_guid_missing_failed_or_nil_uses_selection_only_with_existing_target",function()
    for _,fn in ipairs({function() return nil end,function() error("NO_GUID") end}) do
        local e=fixture("target"); e:UsageTargetChanged(); UnitGUID=fn
        firstLoop(); eq(e.usageTarget.kind,"selection"); cast(116); eq(e.index,3)
    end
    local e=fixture("target"); e:UsageTargetChanged(); UnitGUID=nil
    firstLoop(); cast(116); eq(e.index,3)
    UnitExists=function() return false end; reconcile(); eq(T.Dispatch.pending,nil)
end)
test("usage_selection_identity_stays_stable_when_guid_becomes_public",function()
    local e=fixture("target"); e:UsageTargetChanged(); UnitGUID=function() return F.secret end
    firstLoop(); UnitGUID=function() return "public-after-combat" end
    cast(116); eq(e.index,3); eq(e.usageTarget.kind,"selection")
    e:UsageTargetChanged(); reconcile(); eq(e.usageTarget,nil)
end)
test("usage_target_event_during_api_read_never_authorizes_old_selection",function()
    local e=fixture("target"); cast(116)
    UnitGUID=function() e:UsageTargetChanged(); return F.secret end
    reconcile(); eq(e.index,2); eq(T.Dispatch.pending,nil); eq(T.Runtime.state,"blocked")
end)
