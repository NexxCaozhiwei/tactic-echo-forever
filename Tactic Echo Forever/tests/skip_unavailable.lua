local T,F=...
local test,eq=F.test,F.eq
local function fixture(loop)
    F.runtimeFixture("manual")
    T.engine.steps=T.Engine.Validate({
        {name="A",spellID=116,matchIDs={116},repeatCount=3,skipUnavailable=true},
        {name="B",spellID=205,matchIDs={205},skipUnavailable=true}})
    T.engine.db.loop=loop==true
    InCombatLockdown=function() return true end
    C_Spell.GetSpellCharges=function() return nil end
    C_Spell.GetSpellCooldown=function() return {startTime=0,duration=0,isEnabled=true} end
    UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
end
test("skip_option_text_clean_save_and_secret_default",function()
    local rows=assert(T.Profiles:Parse("116:116*3!skip\n205:205"))
    eq(rows[1].skipUnavailable,true); eq(rows[2].skipUnavailable,false)
    eq(T.Profiles:RowsText(rows),"116:116*3!skip\n205:205")
    local clean=T.Profiles:Clean({{name="A",spellID=116,matchIDs={116},skipUnavailable=F.secret}})
    eq(clean[1].skipUnavailable,false)
    eq(T.Engine.Validate(clean)[1].skipUnavailable,false)
    fixture(); assert(T.Profiles:Save(T.engine,"single",rows))
    local reloaded=T.Engine.New(T.Config,T.engine.db)
    eq(reloaded.db.profiles.single[1].skipUnavailable,true)
end)
test("skip_unusable_omits_remaining_repeats_without_success",function()
    fixture(); C_Spell.IsSpellUsable=function(id) return id~=116,false end
    T.Runtime:Start(false)
    eq(T.engine.index,2); eq(T.engine.stepCasts,0); eq(T.engine.receiptSerial,nil)
    eq(T.Runtime.intent,true); eq(T.Dispatch.pending,nil)
    eq(T.engine.lastReason,"UNAVAILABLE_STEP_SKIPPED")
end)
test("skip_power_and_own_cooldown_but_never_GCD",function()
    for _,reason in ipairs({"power","cooldown"}) do
        fixture()
        if reason=="power" then C_Spell.IsSpellUsable=function() return true,true end
        else C_Spell.GetSpellCooldown=function(id)
            assert(id~=61304); return {startTime=1,duration=60,isEnabled=true,isOnGCD=false,isActive=true}
        end end
        T.Runtime:Start(false); eq(T.engine.index,2)
    end
    fixture(); C_Spell.GetSpellCooldown=function() return {startTime=1,duration=1.5,isEnabled=true,isOnGCD=true} end
    T.Runtime:Start(false); eq(T.engine.index,1); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
end)
test("skip_secret_unknown_and_context_preserve_position",function()
    local changes={
        function() C_Spell.IsSpellUsable=function() return F.secret,F.secret end end,
        function() C_Spell.GetSpellCooldown=function() return {startTime=F.secret,duration=F.secret,isEnabled=true} end end,
        function() UnitExists=function() return false end; C_Spell.IsSpellUsable=function() return false,false end end,
        function() GetCurrentKeyBoardFocus=function() return {} end; C_Spell.IsSpellUsable=function() return false,false end end,
        function() C_Spell.IsSpellInRange=function() return false end; C_Spell.IsSpellUsable=function() return false,false end end,
        function() UnitCastingInfo=function() return "cast" end; C_Spell.IsSpellUsable=function() return false,false end end,
    }
    for _,change in ipairs(changes) do
        fixture(); change(); T.Runtime:Start(false)
        eq(T.engine.index,1); eq(T.Dispatch.pending,nil); eq(T.Runtime.intent,true)
    end
end)
test("skip_pending_or_initiated_cast_waits_for_exact_success",function()
    fixture(); T.Runtime:Start(false); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    C_Spell.IsSpellUsable=function() return false,false end
    T.Runtime:Reconcile(); eq(T.engine.index,1); eq(T.engine.stepCasts,0)
    -- Restart with an actual public initiation, then change usability.
    fixture(); T.Runtime:Start(false); T.Dispatch:TickContinuous()
    F.receipt("UNIT_SPELLCAST_SENT",116,"skip-A")
    C_Spell.IsSpellUsable=function() return false,false end
    T.Runtime:Reconcile(); eq(T.engine.index,1)
    F.receipt("UNIT_SPELLCAST_SUCCEEDED",116,"skip-A"); eq(T.engine.stepCasts,1)
    T.Runtime:Reconcile(); eq(T.engine.index,2); eq(T.engine.stepCasts,0)
end)
test("skip_all_loop_bounded_and_availability_restores_dispatch",function()
    fixture(true); C_Spell.IsSpellUsable=function() return false,false end
    T.Runtime:Start(false); eq(T.engine.index,2)
    T.Runtime:Reconcile(); eq(T.engine.index,1)
    for i=1,20 do T.Runtime:Reconcile() end
    eq(T.engine.skipStreak,2); eq(T.Runtime.reason,"SKIP_ALL_UNAVAILABLE"); eq(T.Runtime.intent,true)
    C_Spell.IsSpellUsable=function() return true,false end
    T.Runtime:Reconcile(); eq(T.engine.skipStreak,0); eq(T.Runtime.state,"running")
end)
test("skip_charge_available_not_recharge_and_depleted_skips",function()
    fixture(); C_Spell.GetSpellCharges=function() return {currentCharges=1,maxCharges=2} end
    C_Spell.GetSpellCooldown=function() error("Do not treat recharge as unavailable") end
    eq(T.Dispatch:Unavailable(116),false)
    C_Spell.GetSpellCharges=function() return {currentCharges=0,maxCharges=2} end
    eq(T.Dispatch:Unavailable(116),true)
    C_Spell.GetSpellCharges=function() return {currentCharges=F.secret,maxCharges=2} end
    eq(T.Dispatch:Unavailable(116),nil)
end)
test("skip_default_off_code_and_Shoot_remain_attempts",function()
    fixture(); T.engine.steps[1].skipUnavailable=false
    C_Spell.IsSpellUsable=function() return false,false end
    T.Runtime:Start(false); eq(T.engine.index,1)
    fixture(); T.engine.steps[1].spellID=5019
    C_Spell.IsSpellUsable=function() return false,false end
    T.Runtime:Start(false); eq(T.engine.index,1)
    fixture(); T.engine.db.sourceByProfile[T.engine.profileKey]={single="code"}
    C_Spell.IsSpellUsable=function() return false,false end
    T.Runtime:Start(false); eq(T.engine.index,2)
    T.Runtime:Stop()
end)

test("skip_editor_row_count_reorder_roundtrip",function()
    F.deliveryFixture("manual")
    T.UI:WriteDraft({{name="A",spellID=116,matchIDs={116}},{name="B",spellID=205,matchIDs={205}}})
    assert(T.UI:EditSequenceRow(1,"skip",true))
    assert(T.UI:EditSequenceRow(1,"count","3"))
    assert(T.UI:EditSequenceRow(1,"move",1))
    local rows=T.UI:DraftRows(); eq(rows[2].skipUnavailable,true); eq(rows[2].repeatCount,3)
    eq(rows[1].skipUnavailable,false)
    assert(T.UI.sequenceRows[2].skip)
end)
