local T,F=...
local eq,test=F.eq,F.test
local function fixture()
    F.deliveryFixture("manual")
    T.engine.steps=T.Engine.Validate({{name="十字军圣印",spellID=20162,matchIDs={20162}},{name="审判",spellID=20271,matchIDs={20271}}})
    GetActionInfo=function() return "spell",T.engine.steps[T.engine.index].spellID end
    C_Spell.GetSpellInfo=function(id) return {name="技能"..id,minRange=0,maxRange=id==20162 and 0 or 10} end
    C_Spell.IsSpellHelpful=function(id) return id==20162 end
    C_Spell.IsSpellHarmful=function(id) return id~=20162 end
    C_Spell.IsSpellInRange=function(id) if id~=20162 then return true end end
    T.Dispatch:ClearBindingCache(); T.Presentation.bindings={}
end
test("paladin_seal_no_enemy_range_counts_then_judgement_keeps_range",function()
    fixture(); assert(T.Runtime:SetIntent(true)); T.Dispatch:TickContinuous()
    assert(T.Dispatch.pending); eq(T.Dispatch.pending.binding.spellID,20162); assert(T.Dispatch:Packet())
    F.receipt("UNIT_SPELLCAST_SENT",20162,"seal"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",20162,"seal")
    eq(T.engine.index,2)
    C_Spell.IsSpellInRange=function() return false end
    T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil)
    eq(T.Runtime.reason,"CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED")
end)
test("public_self_buff_without_target_still_checks_usability_and_resources",function()
    fixture(); UnitExists=function() return false end
    assert(T.Dispatch:ContinuousEvidence(20162))
    C_Spell.IsSpellUsable=function() return false,false end; eq(T.Dispatch:ContinuousEvidence(20162),false)
    C_Spell.IsSpellUsable=function() return true,true end; eq(T.Dispatch:ContinuousEvidence(20162),false)
    C_Spell.IsSpellUsable=function() return F.secret,false end; eq(T.Dispatch:ContinuousEvidence(20162),false)
end)
test("self_classification_unknown_helpfulness_range_and_harmfulness_never_bypass",function()
    fixture(); UnitExists=function() return false end
    for _,value in ipairs({F.secret,true}) do
        C_Spell.IsSpellHarmful=function() return value end
        eq(T.Dispatch:ContinuousEvidence(20162),false)
    end
    C_Spell.IsSpellHarmful=function() return false end
    C_Spell.IsSpellHelpful=function() return F.secret end; eq(T.Dispatch:ContinuousEvidence(20162),false)
    C_Spell.IsSpellHelpful=function() return true end
    C_Spell.GetSpellInfo=function() return {minRange=0,maxRange=F.secret} end
    eq(T.Dispatch:ContinuousEvidence(20162),false)
    C_Spell.GetSpellInfo=function() return {minRange=0,maxRange=40} end
    eq(T.Dispatch:ContinuousEvidence(20162),false)
end)
test("legacy_public_self_classification_and_standby_emit_zero",function()
    fixture(); C_Spell.IsSpellHelpful=nil; C_Spell.IsSpellHarmful=nil
    IsHelpfulSpell=function() return true end; IsHarmfulSpell=function() return false end
    assert(T.Dispatch:ContinuousEvidence(20162))
    T.engine.db.dispatch.mode="auto"; assert(T.Runtime:SetIntent(true)); T.Dispatch:TickContinuous()
    eq(T.Runtime.state,"standby"); eq(T.Dispatch.pending,nil)
    T.Transport:Paint(); eq(T.Transport.fields[15],0)
end)
test("self_metadata_change_revokes_existing_request",function()
    fixture(); assert(T.Runtime:SetIntent(true)); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
    UnitExists=function() return false end
    C_Spell.GetSpellInfo=function() return {minRange=0,maxRange=F.secret} end
    eq(T.Dispatch:Packet(),nil); eq(T.Dispatch.pending,nil); eq(T.engine.index,1)
end)
test("legacy_spell_metadata_requires_returned_exact_id",function()
    fixture(); C_Spell.GetSpellInfo=nil; UnitExists=function() return false end
    GetSpellInfo=function(id) return "十字军圣印","等级6",123,0,0,0,id end
    assert(T.Dispatch:ContinuousEvidence(20162))
    GetSpellInfo=function() return "十字军圣印","等级1",123,0,0,0,21082 end
    eq(T.Dispatch:ContinuousEvidence(20162),false)
end)
test("secret_modern_range_never_uses_legacy_self_fallback",function()
    fixture(); UnitExists=function() return false end
    C_Spell.GetSpellInfo=function() return {minRange=0,maxRange=F.secret} end
    local reads=0; GetSpellInfo=function(id) reads=reads+1; return "圣印",nil,nil,nil,0,0,id end
    eq(T.Dispatch:ContinuousEvidence(20162),false); eq(reads,0)
end)
