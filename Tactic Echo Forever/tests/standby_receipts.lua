local T,F=...
local test,eq,receipt=F.test,F.eq,F.receipt
local function fixture(repeats)
    F.runtimeFixture("auto")
    T.engine.steps=T.Engine.Validate({
        {name="A",spellID=116,matchIDs={116},repeatCount=repeats or 1},
        {name="B",spellID=143,matchIDs={143},repeatCount=1},
        {name="C",spellID=2136,matchIDs={2136},repeatCount=1},
        {name="D",spellID=5143,matchIDs={5143},repeatCount=1}})
    T.engine.db.loop=false
    assert(T.Runtime:SetIntent(true))
end
local function cast(id,guid)
    receipt("UNIT_SPELLCAST_SENT",id,guid)
    receipt("UNIT_SPELLCAST_SUCCEEDED",id,guid)
end
local function quiet()
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); T.Transport:Paint()
    eq(T.Dispatch.continuous,false); eq(T.Dispatch.pending,nil); eq(T.Transport.fields[15],0)
end
test("standby_manual_abcd_counts_without_input",function()
    fixture()
    for i,id in ipairs({116,143,2136,5143}) do
        cast(id,"manual-"..i)
        eq(T.engine.index,math.min(i+1,4)); quiet()
    end
    eq(T.engine.completed,true); eq(T.Runtime.intent,false)
end)
test("standby_manual_repeat_and_duplicate_share_success_count",function()
    fixture(3)
    for i=1,3 do
        cast(116,"repeat-"..i)
        receipt("UNIT_SPELLCAST_SUCCEEDED",116,"repeat-"..i)
        eq(T.engine.index,i<3 and 1 or 2)
        eq(T.engine.stepCasts,i<3 and i or 0); quiet()
    end
end)
test("standby_failed_foreign_unknown_and_uninitiated_never_count",function()
    fixture()
    cast(143,"foreign")
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"no-start")
    receipt("UNIT_SPELLCAST_SENT",116,"failed")
    receipt("UNIT_SPELLCAST_INTERRUPTED",116,"failed")
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"failed")
    receipt("UNIT_SPELLCAST_SENT",116,F.secret)
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,F.secret)
    eq(T.engine.index,1); eq(T.engine.stepCasts,0); quiet()
    cast(116,"fresh"); eq(T.engine.index,2)
end)
test("standby_opener_crosses_combat_keeps_receipt_and_next_step",function()
    fixture()
    receipt("UNIT_SPELLCAST_SENT",116,"opener")
    local generation=T.engine.generation
    T.Runtime:Reconcile(); eq(T.engine.generation,generation)
    InCombatLockdown=function() return true end
    UnitCastingInfo=function() return "A" end
    T.Runtime:Reconcile(); eq(T.engine.generation,generation)
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"opener"); eq(T.engine.index,2)
    UnitCastingInfo=function() return nil end
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    eq(T.engine.index,2); eq(T.Runtime.state,"running"); assert(T.Dispatch.pending)
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"opener"); eq(T.engine.index,2)
end)
test("standby_stop_settings_and_reset_invalidate_manual_receipts",function()
    for _,action in ipairs({"stop","settings","reset"}) do
        fixture(); receipt("UNIT_SPELLCAST_SENT",116,"old-"..action)
        if action=="settings" then T.UI.settingsOpen=true; T.Runtime:Reconcile()
        elseif action=="reset" then T.Runtime:Reset()
        else T.Runtime:Stop() end
        receipt("UNIT_SPELLCAST_SUCCEEDED",116,"old-"..action)
        cast(116,"paused-"..action); eq(T.engine.index,1)
        T.UI.settingsOpen=false; T.Runtime:Reconcile()
        if action=="settings" then
            cast(116,"fresh-settings"); eq(T.engine.index,2)
        else cast(116,"still-paused-"..action); eq(T.engine.index,1); eq(T.Runtime.intent,false) end
    end
end)
test("standby_opener_combat_before_cast_visible_waits_exact_receipt",function()
    fixture(); receipt("UNIT_SPELLCAST_SENT",116,"early-opener")
    InCombatLockdown=function() return true end
    UnitCastingInfo=function() return nil end
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    eq(T.Runtime.reason,"MANUAL_WAIT_CURRENT_RECEIPT"); eq(T.Dispatch.pending,nil)
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"early-opener"); eq(T.engine.index,2)
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
end)
test("standby_unknown_combat_retires_receipt",function()
    fixture(); receipt("UNIT_SPELLCAST_SENT",116,"old-unknown")
    InCombatLockdown=function() return F.secret end; T.Runtime:Reconcile()
    receipt("UNIT_SPELLCAST_SUCCEEDED",116,"old-unknown"); eq(T.engine.index,1)
    InCombatLockdown=function() return false end; T.Runtime:Reconcile()
    cast(116,"fresh-known"); eq(T.engine.index,2); quiet()
end)
test("standby_request_and_combat_exit_packet_emit_zero",function()
    fixture(); local ok,reason=T.Dispatch:Request()
    eq(ok,false); eq(reason,"RUNTIME_AUTO_STANDBY"); quiet()
    InCombatLockdown=function() return true end; T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    assert(T.Dispatch.pending)
    InCombatLockdown=function() return false end
    eq(T.Dispatch:Packet(),nil); eq(T.Dispatch.pending,nil)
    quiet(); cast(116,"after-exit"); eq(T.engine.index,2)
end)
