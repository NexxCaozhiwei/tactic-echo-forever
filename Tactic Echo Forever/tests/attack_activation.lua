local T,F=...
local eq,test=F.eq,F.test
local function fixture(id,mode)
    F.deliveryFixture(mode or "manual")
    id=id or 6603
    T.engine.steps=T.Engine.Validate({{name="A",spellID=id,matchIDs={id}},{name="B",spellID=20271,matchIDs={20271}}})
    ActionButton1={action=7,GetAttribute=function() return 7 end}
    ActionButton2={action=8,GetAttribute=function() return 8 end}
    GetActionInfo=function(slot) return "spell",slot==7 and id or 20271 end
    GetBindingKey=function(command) return command=="ACTIONBUTTON1" and "1" or "2" end
    C_Spell.GetSpellInfo=function(spell) return {name="技能"..spell,minRange=0,maxRange=5} end
    C_Spell.IsSpellHelpful=function() return false end; C_Spell.IsSpellHarmful=function() return true end
    C_Spell.IsSpellInRange=function(spell) if spell~=id then return true end end
    IsActionInRange=function(slot,unit) eq(unit,"target"); return slot==7 end
    IsCurrentAction=function() return false end; IsAutoRepeatAction=function() return false end
    T.Dispatch:ClearBindingCache(); T.Presentation.bindings={}
end
test("attack_6603_requests_once_confirms_enabled_then_next_step",function()
    fixture(); assert(T.Runtime:SetIntent(true)); T.Dispatch:TickContinuous()
    assert(T.Dispatch.pending); eq(T.Dispatch.pending.binding.spellID,6603); assert(T.Dispatch:Packet())
    local generation=T.engine.generation
    IsCurrentAction=function() return true end
    eq(T.Dispatch:Packet(),nil); T.Runtime:Reconcile()
    eq(T.engine.index,2); eq(T.engine.generation,generation+1); eq(T.Dispatch.pending,nil)
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    assert(T.Dispatch.pending); eq(T.Dispatch.pending.binding.spellID,20271)
end)
test("attack_already_enabled_advances_without_toggling",function()
    fixture(); IsCurrentAction=function() return true end
    assert(T.Runtime:SetIntent(true)); eq(T.engine.index,2); eq(T.Runtime.requestSerial,0)
    eq(T.engine.receiptSerial,1)
end)
test("attack_unknown_status_no_toggle_no_advance",function()
    for _,fn in ipairs({function() return F.secret end,function() return nil end,function() error("UNKNOWN") end}) do
        fixture(); IsCurrentAction=fn
        assert(T.Runtime:SetIntent(true)); T.Dispatch:TickContinuous()
        eq(T.engine.index,1); eq(T.Dispatch.pending,nil); eq(T.engine.receiptSerial,nil)
    end
    fixture(); IsCurrentAction=function() return true end; UnitExists=function() return false end
    assert(T.Runtime:SetIntent(true)); eq(T.engine.index,1); eq(T.Dispatch.pending,nil)
end)
test("attack_activation_observed_in_standby_but_not_settings_or_pause",function()
    fixture(6603,"auto"); assert(T.Runtime:SetIntent(true)); eq(T.engine.index,1)
    IsCurrentAction=function() return true end; T.Runtime:Reconcile()
    eq(T.engine.index,2); eq(T.Runtime.state,"standby"); T.Transport:Paint(); eq(T.Transport.fields[15],0)
    fixture(); T.Runtime:Stop(); IsCurrentAction=function() return true end; T.Runtime:Reconcile(); eq(T.engine.index,1)
    fixture(); T.UI.settingsOpen=true; IsCurrentAction=function() return true end
    T.Runtime:SetIntent(true); eq(T.engine.index,1); eq(T.Dispatch.pending,nil)
end)
test("exact_action_range_fallback_never_overrides_false_secret_or_call_failure",function()
    fixture(2764); assert(T.Dispatch:ContinuousEvidence(2764))
    for _,fn in ipairs({function() return false end,function() return F.secret end,function() error("UNKNOWN") end}) do
        C_Spell.IsSpellInRange=fn; eq(T.Dispatch:ContinuousEvidence(2764),false)
    end
    C_Spell.IsSpellInRange=function() return nil end
    GetActionInfo=function() return "spell",143 end
    eq(T.Dispatch:ContinuousEvidence(2764),false)
    fixture(2764); IsActionInRange=function() return F.secret end; eq(T.Dispatch:ContinuousEvidence(2764),false)
end)
test("attack_activation_never_claims_melee_range_and_keeps_enemy_gate",function()
    fixture(); local reads=0
    C_Spell.IsSpellInRange=function() reads=reads+1; return F.secret end
    IsActionInRange=function() reads=reads+1; return false end
    assert(T.Dispatch:ContinuousEvidence(6603)); eq(reads,0)
    UnitCanAttack=function() return false end; eq(T.Dispatch:ContinuousEvidence(6603),false)
    UnitCanAttack=function() return F.secret end; eq(T.Dispatch:ContinuousEvidence(6603),false)
end)
test("ordinary_throw_range_fallback_preserves_real_cast_receipts",function()
    fixture(2764); IsActionInRange=function() return 1 end
    assert(T.Runtime:SetIntent(true)); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    eq(T.engine.index,1)
    F.receipt("UNIT_SPELLCAST_SENT",2764,"throw"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",2764,"throw")
    eq(T.engine.index,2)
    fixture(2764); C_Spell.IsSpellInRange=nil; assert(T.Dispatch:ContinuousEvidence(2764))
    IsActionInRange=function() return 0 end; eq(T.Dispatch:ContinuousEvidence(2764),false)
end)
test("auto_shot_75_active_does_not_toggle_or_use_attack_activation",function()
    fixture(75); assert(T.Runtime:SetIntent(true)); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    IsAutoRepeatAction=function() return true end; eq(T.Dispatch:Packet(),nil)
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
    eq(T.engine.index,1); eq(T.Dispatch.pending,nil)
end)
test("attack_public_api_reentry_cannot_advance_stopped_intent",function()
    fixture(); IsCurrentAction=function() T.Runtime:Stop(); return true end
    T.Runtime:SetIntent(true); eq(T.Runtime.intent,false); eq(T.engine.index,1); eq(T.Dispatch.pending,nil)
end)
test("attack_only_loop_confirms_once_without_busy_loop",function()
    fixture(); T.engine.steps=T.Engine.Validate({{name="攻击",spellID=6603,matchIDs={6603}}}); T.engine.db.loop=true
    IsCurrentAction=function() return true end; assert(T.Runtime:SetIntent(true)); eq(T.engine.receiptSerial,1)
    for i=1,10 do T.Runtime:Reconcile(); T.Dispatch:TickContinuous() end
    eq(T.engine.receiptSerial,1); eq(T.Dispatch.pending,nil)
end)
test("attack_count_is_one_and_swing_success_never_confirms_activation",function()
    fixture(); local rows=T.Profiles:Parse("6603*3!skip\n20271"); eq(rows[1].repeatCount,1); eq(rows[1].skipUnavailable,false)
    T.engine.steps=T.Engine.Validate(rows); assert(T.Runtime:SetIntent(true))
    F.receipt("UNIT_SPELLCAST_SENT",6603,"swing"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",6603,"swing")
    eq(T.engine.index,1); eq(T.engine.receiptSerial,nil)
    IsCurrentAction=function() return true end; T.Runtime:Reconcile(); eq(T.engine.index,2)
end)
test("attack_already_active_unbound_source_is_readonly",function()
    fixture(); GetBindingKey=function() return nil end; IsCurrentAction=function() return true end
    assert(T.Runtime:SetIntent(true)); eq(T.engine.index,2); eq(T.Runtime.requestSerial,0)
    eq(T.Dispatch.pending,nil)
    fixture(); GetBindingKey=function() return nil end
    assert(T.Runtime:SetIntent(true)); T.Dispatch:TickContinuous(); eq(T.engine.index,1); eq(T.Dispatch.pending,nil)
end)
test("startattack_macro_body_needs_public_exact_attack_identity",function()
    fixture(); MAX_ACCOUNT_MACROS=120; GetNumMacros=function() return 1,0 end
    GetMacroInfo=function() return "开始攻击",123,"#showtooltip\n/startattack [harm]" end
    GetMacroSpell=function() return 6603 end
    GetActionText=function() return "开始攻击" end
    GetActionInfo=function(slot) return slot==7 and "macro" or "spell",slot==7 and 1 or 20271 end
    local binding=T.Dispatch:Resolve(6603); assert(binding); eq(binding.source,"macro")
    GetMacroInfo=function() return "停止攻击",123,"#showtooltip\n/stopattack" end
    eq(T.Dispatch:VerifyCurrent(binding),false)
end)
