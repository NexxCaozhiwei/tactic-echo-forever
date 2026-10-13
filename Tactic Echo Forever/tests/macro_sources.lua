local T,F=...
local test,eq=F.test,F.eq
local function environment()
    MAX_ACCOUNT_MACROS=120; GetNumMacros=function() return 1,0 end
    GetMacroInfo=function(index) eq(index,1); return "焦点寒冰箭",123,"#showtooltip\n/stopcasting\n/cast [@focus,exists] spell:116" end
    GetMacroSpell=function(index) eq(index,1); return "spell116",123,116 end
    GetActionInfo=function() return "macro",1 end
    GetActionText=function() return "焦点寒冰箭" end
    T.ActionSources:Clear(); T.Dispatch:ClearBindingCache(); T.Presentation.bindings={}
end
local function fixture()
    F.deliveryFixture("manual"); environment()
    assert(T.Runtime:SetIntent(true)); T.Dispatch:TickContinuous()
end
test("macro_legacy_and_numeric_spell_api_resolve_exact_binding",function()
    fixture(); assert(T.Dispatch.pending)
    local b=T.Dispatch.pending.binding; eq(b.source,"macro"); eq(b.macroID,1); eq(b.spellID,116)
    assert(T.Dispatch:VerifyCurrent(b)); assert(T.Dispatch:Packet())
    GetMacroSpell=function() return 116 end; assert(T.Dispatch:VerifyCurrent(b))
    eq(T.engine.db.macroBody,nil)
end)
test("macro_tooltip_only_wrong_spell_secret_body_and_identity_rejected",function()
    F.deliveryFixture(); environment()
    for _,body in ipairs({"#showtooltip spell:116","/cast spell:143","/use 13","/click AnotherButton"}) do
        GetMacroInfo=function() return "焦点寒冰箭",123,body end
        eq(T.Dispatch:Resolve(116),nil)
    end
    GetMacroInfo=function() return "焦点寒冰箭",123,F.secret end; eq(T.Dispatch:Resolve(116),nil)
    GetMacroInfo=function() return F.secret,123,"/cast spell:116" end; eq(T.Dispatch:Resolve(116),nil)
    GetMacroInfo=function() return "焦点寒冰箭",123,"/cast spell:116" end
    GetMacroSpell=function() return F.secret end; eq(T.Dispatch:Resolve(116),nil)
    GetNumMacros=function() return F.secret,0 end; eq(T.Dispatch:Resolve(116),nil)
end)
test("macro_represented_spell_recovers_unique_name_rejects_duplicates",function()
    F.deliveryFixture(); environment()
    GetActionInfo=function() return "macro",116 end
    local b=T.Dispatch:Resolve(116); assert(b); eq(b.macroID,1)
    GetNumMacros=function() return 2,0 end
    GetMacroInfo=function() return "焦点寒冰箭",123,"/cast spell:116" end
    GetMacroSpell=function() return 116 end
    T.ActionSources:Clear(); eq(T.Dispatch:Resolve(116),nil)
end)
test("macro_representation_spell_label_and_character_index",function()
    F.deliveryFixture(); environment()
    GetActionInfo=function() return "macro",116 end; GetActionText=function() return "spell116" end
    assert(T.Dispatch:Resolve(116))
    GetNumMacros=function() return 0,1 end
    GetActionInfo=function() return "macro",121 end
    GetActionText=function() return "人物宏" end
    GetMacroInfo=function(index) eq(index,121); return "人物宏",123,"/cast spell:116" end
    GetMacroSpell=function(index) eq(index,121); return 116 end
    T.ActionSources:Clear(); local b=T.Dispatch:Resolve(116); assert(b); eq(b.macroID,121)
end)
test("macro_body_binding_and_dynamic_spell_changes_revoke_packet",function()
    fixture(); assert(T.Dispatch.pending)
    GetMacroInfo=function() return "焦点寒冰箭",123,"/cast [@mouseover] spell:116" end
    eq(T.Dispatch:Packet(),nil); eq(T.Dispatch.pending,nil)
    fixture(); GetBindingKey=function() return "2" end
    eq(T.Dispatch:Packet(),nil)
    fixture(); GetMacroSpell=function() return 143 end
    eq(T.Dispatch:Packet(),nil); eq(T.engine.index,1)
end)
test("macro_cursor_and_action_cursor_work_in_both_editors",function()
    F.editorFixture("205*3"); environment()
    local held=true; GetCursorInfo=function() if held then return "macro",1 end end
    ClearCursor=function() held=false end
    assert(T.UI:ReceiveSequenceSpell()); eq(T.UI:DraftRows()[2].spellID,116); eq(T.UI:DraftRows()[1].repeatCount,3)
    T.UI:ShowPage("customapl"); held=true
    GetCursorInfo=function() if held then return "action",7 end end
    assert(T.UI:ReceiveCustomSpell()); eq(T.UI.customDraft[#T.UI.customDraft].spellID,116); eq(held,false)
end)
test("macro_update_event_revalidates_and_cancels_changed_request",function()
    fixture(); assert(F.frames.TEF_EventFrame.events.UPDATE_MACROS); assert(T.Dispatch.pending)
    GetMacroInfo=function() return "焦点寒冰箭",123,"/cast spell:143" end
    GetMacroSpell=function() return 143 end
    local frame=F.frames.TEF_EventFrame; frame.scripts.OnEvent(frame,"UPDATE_MACROS")
    eq(T.Dispatch.pending,nil); eq(T.Dispatch.continuous,false)
    eq(T.engine.index,1); eq(T.Presentation.bindings[116],false)
end)
test("macro_same_spell_repeats_use_exact_receipts_only",function()
    fixture(); T.Runtime:Stop()
    T.engine.steps=T.Engine.Validate({{name="A",spellID=116,matchIDs={116},repeatCount=2},{name="B",spellID=143,matchIDs={143}}})
    assert(T.Runtime:SetIntent(true))
    F.receipt("UNIT_SPELLCAST_SENT",116,"macro-A1"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",116,"macro-A1")
    eq(T.engine.index,1); eq(T.engine.stepCasts,1)
    F.receipt("UNIT_SPELLCAST_SUCCEEDED",116,"macro-A1"); eq(T.engine.stepCasts,1)
    F.receipt("UNIT_SPELLCAST_SENT",116,"macro-A2"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",116,"macro-A2")
    eq(T.engine.index,2)
end)
test("settings_raise_only_on_open_refresh_does_not_reclaim_front",function()
    F.deliveryFixture(); T.UI:OpenSettings()
    local f=T.UI.settings; eq(f.toplevel,true); eq(f.strata,"MEDIUM"); eq(f.raises,1)
    for i=1,5 do T.UI:Refresh(); T.Runtime:Reconcile() end
    eq(f.raises,1)
    T.UI:CloseSettings(); T.UI:OpenSettings(); eq(f.raises,2)
end)
