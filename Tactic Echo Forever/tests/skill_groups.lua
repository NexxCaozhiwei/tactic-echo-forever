local _,T,F=...
local n=0
local function eq(a,b) assert(a==b,"group expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function test(name,fn) fn(); n=n+1 end
local function spell(id,count,skip) return {spellID=id,name="技能 " .. id,matchIDs={id},repeatCount=count or 1,skipUnavailable=skip,enabled=true,strategies={}} end
local function group() return {name="技能组A",rounds=1,steps={spell(143),spell(205,2)}} end
local function receipt(id,guid) F.receipt("UNIT_SPELLCAST_SENT",id,guid); F.receipt("UNIT_SPELLCAST_SUCCEEDED",id,guid) end
test("manual_group_success_counts_and_returns_to_parent",function()
 local e=F.runtime(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row(group()),spell(143)})); e:SetLoop(false)
 T.Runtime:SetIntent(true); assert(e.groupRun); eq(e.steps[1].spellID,143)
 T.Dispatch:TickContinuous(); assert(T.Dispatch:Packet())
 receipt(143,"group-x"); T.Runtime:Reconcile(); eq(e.index,2)
 receipt(205,"group-y1"); T.Runtime:Reconcile(); eq(e.index,2); eq(e.stepCasts,1)
 T.Runtime:Stop(); assert(e.groupRun); eq(e.stepCasts,1)
 T.Runtime:SetIntent(true); assert(e.groupRun); eq(e.stepCasts,1)
 receipt(205,"group-y2"); T.Runtime:Reconcile(); eq(e.groupRun,nil); eq(e.index,2); eq(e.steps[2].spellID,143)
 T.Runtime:Stop()
end)
test("manual_group_finite_rounds_and_failed_receipt",function()
 local e=F.runtime(); assert(T.Recommendation:SetSource(e,"manual","single"))
 local g=group(); g.steps={spell(143)}; g.rounds=2
 assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row(g),spell(205)})); e:SetLoop(false)
 T.Runtime:SetIntent(true); assert(e.groupRun)
 F.receipt("UNIT_SPELLCAST_SENT",143,"group-failed"); F.receipt("UNIT_SPELLCAST_FAILED",143,"group-failed")
 T.Runtime:Reconcile(); eq(e.index,1); eq(e.receiptSerial or 0,0)
 receipt(143,"group-round1"); T.Runtime:Reconcile(); eq(e.groupRun.round,2); eq(e.receiptSerial,1)
 receipt(143,"group-round2"); T.Runtime:Reconcile(); eq(e.groupRun,nil); eq(e.index,2)
 T.Runtime:Stop()
end)
test("priority_group_locks_order_then_consumes_trigger",function()
 local e=F.runtime(); local g=group()
 assert(T.APL.Custom:Save(e,{{group=g,spellID=143,enabled=true,strategies={}}, {spellID=205,enabled=true}},"single","MAGE"))
 T.Runtime:SetIntent(true); assert(e.groupRun); eq(T.Recommendation:Source(e),"manual")
 receipt(143,"apl-group-x"); T.Runtime:Reconcile(); eq(e.steps[e.index].spellID,205)
 receipt(205,"apl-group-y1"); T.Runtime:Reconcile(); eq(e.stepCasts,1)
 receipt(205,"apl-group-y2"); T.Runtime:Reconcile(); eq(e.groupRun,nil); eq(T.Recommendation:Source(e),"apl")
 T.APL:Invalidate(); T.Runtime:Reconcile(); eq(e.aplCandidate.spellID,205)
 T.Runtime:Stop()
end)
test("group_editor_save_roundtrip_and_reject_nested_secret",function()
 local e=F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddSkillGroup("apl")
 assert(T.UI.groupEditing); T.UI:GroupAdd(143); T.UI:GroupAdd(205)
 T.UI.groupName.text="连招A"; T.UI.groupRounds.text="2"; assert(T.UI:SaveSkillGroup())
 local row=T.APL.Custom:Rows(e)[1]; eq(row.group.name,"连招A"); eq(row.group.rounds,2); eq(#row.group.steps,2)
 local reload=T.Engine.New(T.Config,e.db); eq(T.APL.Custom:Rows(reload,"single")[1].group.steps[2].spellID,205)
 T.UI:CloseSkillGroup(true)
 local g=group(); g.steps[1].group=group(); eq(T.SkillGroups:Clean(g),nil)
 g=group(); g.rounds=F.secret; eq(T.SkillGroups:Clean(g),nil)
end)
test("group_maintenance_restores_child_progress_and_edit_clears_both",function()
 local e=F.runtime(); local info,known=C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown
 C_Spell.GetSpellInfo=function(id) return {name=id==168 and "霜甲术" or id==205 and "寒冰箭" or "火球术"} end
 C_SpellBook.IsSpellKnown=function() return true end
 assert(T.Recommendation:SetSource(e,"manual","single")); assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row(group()),spell(143)})); e:SetLoop(false)
 assert(T.Maintenance:Save(e,{{spellID=168,strategies={{mode="use",conditions={{kind="moving",value=true}}}}}})); T.Maintenance:SetEnabled(e,true)
 IsPlayerMoving=function() return false end; T.Runtime:SetIntent(true); assert(e.groupRun)
 receipt(143,"maint-group-x"); T.Runtime:Reconcile(); eq(e.index,2)
 IsPlayerMoving=function() return true end; T.APL:Invalidate(); T.Runtime:Reconcile(); assert(e.maintenanceActive); assert(e.groupRun)
 receipt(168,"maint-group-buff"); IsPlayerMoving=function() return false end; T.APL:Invalidate(); T.Runtime:Reconcile()
 eq(e.maintenanceActive,nil); assert(e.groupRun); eq(e.index,2); eq(e.stepCasts,0)
 e:Reset(); eq(e.groupRun,nil); eq(e.maintenanceActive,nil); eq(e.steps[1].group.name,"技能组A")
 C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown=info,known
end)
test("group_target_selection_change_aborts_and_unknown_policy_waits",function()
 local e=F.runtime(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row(group()),spell(205)})); e:SetLoop(false)
 T.Runtime:SetIntent(true); assert(e.groupRun); e:UsageTargetChanged(); T.Runtime:Reconcile(); eq(e.groupRun,nil); eq(e.index,2)
 T.Runtime:Stop()
end)
test("manual_group_entry_false_skips_unknown_waits_and_raw_success_cannot_expand",function()
 local e=F.runtime(); assert(T.Recommendation:SetSource(e,"manual","single"))
 local r=T.SkillGroups:Row(group(),{{mode="use",conditions={{kind="moving",value=true}}}})
 assert(T.Profiles:Save(e,"single",{r,spell(205)})); e:SetLoop(false)
 IsPlayerMoving=function() return false end; T.Runtime:SetIntent(true); eq(e.groupRun,nil); eq(e.index,2); eq(e.receiptSerial or 0,0)
 T.Runtime:Stop(); assert(T.Profiles:Save(e,"single",{r,spell(205)}))
 IsPlayerMoving=function() return F.secret end; T.Runtime:SetIntent(true); eq(e.groupRun,nil); eq(e.index,1); eq(T.Dispatch:Packet(),nil)
 receipt(143,"raw-group-first"); eq(e.index,1); eq(e.receiptSerial or 0,0)
 T.Runtime:Stop(); IsPlayerMoving=function() return false end
end)
test("manual_group_editor_child_policy_and_roundtrip",function()
 local e=F.runtime(); assert(T.Recommendation:SetSource(e,"manual","single")); assert(T.Profiles:Save(e,"single",{}))
 T.UI:ShowPage("profiles"); T.UI:AddSkillGroup("manual"); T.UI:GroupAdd(143); T.UI:GroupAdd(205)
 T.UI:GroupMove(2,1); eq(T.UI.groupDraft.steps[1].spellID,205)
 T.UI.groupWidgets[1].count.text="3"; T.UI.groupDraft.steps[1].skipUnavailable=true
 T.UI.groupDraft.steps[1].strategies={{mode="use",conditions={{kind="moving",value=false}}}}
 assert(T.UI:SaveSkillGroup()); eq(e.db.profiles.single[1].group.steps[1].repeatCount,3)
 local reload=T.Engine.New(T.Config,e.db); eq(reload.db.profiles.single[1].group.steps[1].strategies[1].conditions[1].kind,"moving")
 T.UI:CloseSkillGroup(true)
 local bad=T.SkillGroups:Row(group()); bad.enabled=F.secret; eq(T.Profiles:Clean({bad}),nil)
end)
test("group_drop_on_list_and_row_preserves_cursor_when_rejected",function()
 local e=F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddSkillGroup("apl")
 local cursor,clear=GetCursorInfo,ClearCursor; local cleared=0
 ClearCursor=function() cleared=cleared+1 end
 GetCursorInfo=function() return "spell",1,nil,143 end
 T.UI.groupScroll.scripts.OnReceiveDrag(); eq(#T.UI.groupDraft.steps,1); eq(cleared,1)
 GetCursorInfo=function() return "spell",1,nil,205 end
 T.UI.groupWidgets[1].frame.scripts.OnReceiveDrag(); eq(T.UI.groupDraft.steps[1].spellID,205); eq(T.UI.groupDraft.steps[2].spellID,143)
 eq(cleared,2)
 for i=3,8 do T.UI:GroupAdd(143) end
 T.UI.groupDrop.scripts.OnReceiveDrag(); eq(#T.UI.groupDraft.steps,8); eq(cleared,2)
 assert(T.UI.groupListBox); T.UI:CloseSkillGroup(true); GetCursorInfo,ClearCursor=cursor,clear
end)
test("right_panel_switch_stages_group_and_never_overlaps",function()
 local e=F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddSkillGroup("apl"); T.UI:GroupAdd(143)
 T.UI.groupName.text="切换前保存"; T.UI.groupWidgets[1].count.text="3"
 T.UI.customWidgets[1].policy.scripts.OnClick()
 eq(T.UI.groupPanel.shown,false); eq(T.UI.strategyPanel.shown,true); eq(T.UI.groupEditing,nil)
 eq(#T.APL.Custom:Rows(e),0); eq(T.UI.customDraft[1].group.name,"切换前保存"); eq(T.UI.customDraft[1].group.steps[1].repeatCount,3)
 T.UI:OpenSkillGroup("apl",1); eq(T.UI.strategyPanel.shown,false); eq(T.UI.groupPanel.shown,true)
 T.UI.groupWidgets[1].policy.scripts.OnClick(); eq(T.UI.groupPanel.shown,false); eq(T.UI.strategyPanel.shown,true)
 eq(T.UI.strategySource,"groupStep"); T.UI:CloseSkillGroup(true)
end)
test("parent_loop_does_not_bypass_three_group_rounds",function()
 local e=F.runtime(); assert(T.Recommendation:SetSource(e,"manual","single"))
 local g=group(); g.steps[2].repeatCount=1; g.rounds=3
 assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row(g),spell(205)})); e:SetLoop(true)
 T.Runtime:SetIntent(true)
 for round=1,3 do
  eq(e.groupRun.round,round); receipt(143,"loop-x" .. round); T.Runtime:Reconcile(); eq(e.index,2)
  receipt(205,"loop-y" .. round); T.Runtime:Reconcile()
 end
 eq(e.groupRun,nil); eq(e.index,2); eq(e.steps[2].spellID,205); eq(e.receiptSerial,6)
 T.Runtime:Stop()
end)
test("manual_start_before_combat_is_adopted_once_and_never_grants_outside_input",function()
 local e=F.runtime(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row(group()),spell(205)})); e:SetLoop(true)
 InCombatLockdown=function() return false end; T.Runtime:SetIntent(true); eq(e.groupRun,nil)
 UnitCastingInfo=function() return "火球术" end
 F.receipt("UNIT_SPELLCAST_SENT",143,"hand-first"); assert(e.groupRun); assert(e.associations["hand-first"])
 T.Runtime:Reconcile(); eq(T.Dispatch:Packet(),nil); assert(e.associations["hand-first"])
 InCombatLockdown=function() return true end; T.Runtime:Reconcile(); assert(e.associations["hand-first"])
 UnitCastingInfo=function() return nil end
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"hand-first"); T.Runtime:Reconcile()
 eq(e.index,2); eq(e.receiptSerial,1); eq(e.steps[e.index].spellID,205)
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"hand-first"); eq(e.receiptSerial,1)
 T.Runtime:Stop()
end)
test("priority_manual_start_matches_selected_group_and_rejects_higher_priority_conflict",function()
 local e=F.runtime(); assert(T.APL.Custom:Save(e,{{group=group(),spellID=143,enabled=true,strategies={}}},"single","MAGE"))
 InCombatLockdown=function() return false end; T.Runtime:SetIntent(true); UnitCastingInfo=function() return "火球术" end
 F.receipt("UNIT_SPELLCAST_SENT",143,"apl-hand-first"); assert(e.groupRun); eq(e.groupRun.source,"apl")
 InCombatLockdown=function() return true end; UnitCastingInfo=function() return nil end
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"apl-hand-first"); T.Runtime:Reconcile(); eq(e.index,2); eq(e.receiptSerial,1)
 T.Runtime:Stop()
 e=F.runtime(); assert(T.APL.Custom:Save(e,{{spellID=205,enabled=true},{group=group(),spellID=143,enabled=true,strategies={}}},"single","MAGE"))
 InCombatLockdown=function() return false end; T.Runtime:SetIntent(true); F.receipt("UNIT_SPELLCAST_SENT",143,"wrong-group"); eq(e.groupRun,nil)
 T.Runtime:Stop()
end)
test("manual_group_start_failure_or_secret_identity_never_advances",function()
 local e=F.runtime(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row(group())})); InCombatLockdown=function() return false end; T.Runtime:SetIntent(true)
 F.receipt("UNIT_SPELLCAST_SENT",143,F.secret); eq(e.groupRun,nil)
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"success-without-start"); eq(e.groupRun,nil)
 F.receipt("UNIT_SPELLCAST_SENT",143,"failed-hand"); assert(e.groupRun)
 F.receipt("UNIT_SPELLCAST_FAILED",143,"failed-hand"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"failed-hand")
 eq(e.receiptSerial or 0,0); eq(e.index,1); T.Runtime:Stop()
end)
test("last_channel_success_waits_for_finish_before_next_round",function()
 local e=F.runtime(); assert(T.Recommendation:SetSource(e,"manual","single"))
 local g=group(); g.steps={spell(143),spell(5144)}; g.rounds=2
 assert(T.Profiles:Save(e,"single",{T.SkillGroups:Row(g),spell(205)})); e:SetLoop(true)
 T.Runtime:SetIntent(true); receipt(143,"channel-round1-x"); T.Runtime:Reconcile()
 F.receipt("UNIT_SPELLCAST_SENT",5144,"channel-round1-y")
 UnitChannelInfo=function() return "奥术飞弹" end
 F.receipt("UNIT_SPELLCAST_CHANNEL_START",5144,nil); F.receipt("UNIT_SPELLCAST_SUCCEEDED",5144,"channel-round1-y")
 T.Runtime:Reconcile(); assert(T.Runtime.intent); assert(e.groupRun); eq(e.groupRun.round,1); eq(T.Dispatch:Packet(),nil)
 UnitChannelInfo=function() return nil end; F.receipt("UNIT_SPELLCAST_CHANNEL_STOP",5144,nil); T.Runtime:Reconcile()
 assert(e.groupRun); eq(e.groupRun.round,2); eq(e.index,1)
 receipt(143,"channel-round2-x"); T.Runtime:Reconcile(); receipt(5144,"channel-round2-y"); T.Runtime:Reconcile()
 eq(e.groupRun,nil); eq(e.index,2); eq(e.receiptSerial,4); T.Runtime:Stop()
end)


test("group_header_survives_skip_and_dirty_exit_confirmation",function()
 F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddSkillGroup("apl"); T.UI:GroupAdd(143)
 T.UI.groupName.text="未保存名称"; T.UI.groupRounds.text="4"
 T.UI.groupWidgets[1].skip.scripts.OnClick()
 eq(T.UI.groupDraft.name,"未保存名称"); eq(T.UI.groupDraft.rounds,4); eq(T.UI.groupName.text,"未保存名称")
 eq(T.UI:CloseSkillGroup(),false); assert(T.UI.pendingConfirmation)
 T.UI.confirmCancel.scripts.OnClick(); assert(T.UI.groupEditing)
 T.UI:CloseSkillGroup(); T.UI.confirmAccept.scripts.OnClick(); eq(T.UI.groupEditing,nil)
end)
test("strategy_pool_is_bounded_after_warmup",function()
 F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddCustomSpell(143)
 local create=CreateFrame; local made=0
 CreateFrame=function(...) made=made+1; return create(...) end
 T.UI.customFormIndex=nil; T.UI:RefreshStrategyForm(); local first=made; local syncs=#T.UI.controls
 for i=1,25 do T.UI.customFormIndex=nil; T.UI:RefreshStrategyForm() end
 eq(made,first); eq(#T.UI.controls,syncs); eq(T.UI.strategyPoolActive,false)
 CreateFrame=create
end)
test("settings_fit_small_viewport_and_use_side_editor_when_room_exists",function()
 local combat=InCombatLockdown; InCombatLockdown=function() return false end
 local parent=UIParent; UIParent={GetWidth=function() return 1000 end,GetHeight=function() return 600 end}
 T.UI.strategyPanel.IsShown=function() return true end; T.UI.groupPanel.IsShown=function() return false end
 T.UI:LayoutSettings(); eq(T.UI.settingsFitScale,1); eq(T.UI.settingsHeight,568); eq(T.UI.editorOverlay,true)
 UIParent.GetWidth=function() return 1920 end; UIParent.GetHeight=function() return 1080 end
 T.UI:LayoutSettings(); eq(T.UI.settingsFitScale,1); eq(T.UI.editorOverlay,false)
 UIParent=parent; T.UI.strategyPanel.IsShown=nil; T.UI.groupPanel.IsShown=nil
 InCombatLockdown=combat
end)
test("attack_skip_hidden_and_slider_submit_once",function()
 F.runtime(); T.UI:ShowPage("profiles"); T.UI:WriteDraft({spell(6603)}); T.UI:RefreshSequenceEditor(true)
 eq(T.UI.sequenceRows[1].skip.shown,false)
 local value,calls=5,0
 local slider,input=T.UI:CreateSliderRow(T.UI.settings,"测试数值",0,0,300,1,99,1,function() return value end,function(v) value=v; calls=calls+1 end,true)
 input.text="7"; input.scripts.OnEnterPressed(); input.scripts.OnEditFocusLost(); eq(calls,1); eq(value,7)
 input.text="100"; input.scripts.OnEnterPressed(); eq(calls,1); eq(value,7)
 assert(slider.scripts.OnEnter); assert(slider.scripts.OnLeave)
end)

test("theme_typography_footer_and_owned_tooltip",function()
 F.runtime(); T.UI:ShowPage("profiles")
 eq(T.UI.controlHeight,32); eq(T.UI.controlFontSize,14); assert(T.UI.manualSave.parent~=T.UI.pages.profiles)
 local old=GameTooltip; local owner,hidden=nil,0
 GameTooltip={SetOwner=function(_,v) owner=v end,GetOwner=function() return owner end,Hide=function() hidden=hidden+1 end}
 local control=T.UI.manualSave; T.UI:ShowControlTooltip(control); owner={}; T.UI:HideControlTooltip(control); eq(hidden,0)
 T.UI:ShowControlTooltip(control); T.UI:HideControlTooltip(control); eq(hidden,1); GameTooltip=old
end)
test("delete_undo_and_group_delete_confirmation",function()
 F.runtime(); T.UI:ShowPage("profiles"); T.UI:WriteDraft({spell(143),spell(205)})
 assert(T.UI:DeleteDraft("manual",1)); eq(#T.UI:DraftRows(),1); assert(T.UI:UndoDelete("manual")); eq(T.UI:DraftRows()[1].spellID,143)
 T.UI:WriteDraft({T.SkillGroups:Row(group()),spell(205)})
 eq(T.UI:DeleteDraft("manual",1),false); eq(#T.UI:DraftRows(),2); assert(T.UI.pendingConfirmation)
 T.UI.confirmationShield.scripts.OnKeyDown(nil,"ESCAPE"); eq(T.UI.pendingConfirmation,nil); eq(#T.UI:DraftRows(),2)
 T.UI:DeleteDraft("manual",1); T.UI.confirmAccept.scripts.OnClick(); eq(#T.UI:DraftRows(),1)
end)
test("custom_plan_and_maintenance_switch_preserve_unsaved_rows",function()
 F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddCustomSpell(143)
 T.UI.customScene="multi"; T.UI:RefreshCustomAPL(); T.UI:AddCustomSpell(205)
 T.UI:ShowPage("maintenance"); T.UI:ShowPage("customapl")
 eq(T.UI.customDraft[1].spellID,205); T.UI.customScene="single"; T.UI:RefreshCustomAPL(); eq(T.UI.customDraft[1].spellID,143)
end)
test("atomic_range_validation_labels_and_unknown_input",function()
 F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddCustomSpell(143)
 T.UI:ChangeCustomStrategy(function(row) row.strategies={{mode="use",conditions={{kind="distance",min=10,max=30}}}} end)
 local low,high; for _,entry in ipairs(T.UI.strategyInputs) do assert(entry.label); if entry.field=="min" then low=entry else high=entry end end
 low.box.text="40"; eq(T.UI:CommitCustomNumbers(),false); eq(low.condition.min,10); eq(high.condition.max,30)
 low.box.text="20"; high.box.text=""; eq(T.UI:CommitCustomNumbers(),true); eq(low.condition.min,20); eq(high.condition.max,nil)
 local detector=issecretvalue; issecretvalue=function(v) if v=="20" then return true end; return detector(v) end
 eq(T.UI:CommitCustomNumbers(),false); issecretvalue=detector
end)
test("input_focus_cancel_and_single_commit",function()
 local value,calls=5,0; local _,box=T.UI:CreateSliderRow(T.UI.settings,"测试",0,0,300,1,99,1,function() return value end,function(v) value=v; calls=calls+1 end,true)
 box.text="5"; box.scripts.OnEditFocusGained(); box.text="99"; box.scripts.OnEscapePressed(); box.scripts.OnEditFocusLost(); eq(value,5); eq(calls,0)
 box.text="7"; box.scripts.OnEnterPressed(); box.scripts.OnEditFocusLost(); eq(value,7); eq(calls,1)
 box.text="100"; box.scripts.OnEnterPressed(); T.UI:RefreshControls(); eq(box.text,"100"); eq(value,7)
end)
test("largest_strategy_form_pool_stable_and_callback_identity",function()
 F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddCustomSpell(143)
 T.UI:ChangeCustomStrategy(function(row) row.strategies={}; for i=1,8 do local conditions={}; for j=1,8 do conditions[j]={kind="nearbyEnemies",radius=10,min=2} end; row.strategies[i]={mode="use",conditions=conditions} end end)
 local create=CreateFrame; local made=0; CreateFrame=function(...) made=made+1; return create(...) end
 T.UI.customFormIndex=nil; T.UI:RefreshStrategyForm(); local warm=made; local syncs=#T.UI.controls
 for i=1,25 do T.UI.customFormIndex=nil; T.UI:RefreshStrategyForm() end
 eq(made,warm); eq(#T.UI.controls,syncs); CreateFrame=create
 T.UI:AddCustomSpell(205); local former=T.UI.customDraft[1]; T.UI.strategySpellID.text="143"; T.UI.strategyReplaceID.scripts.OnClick(); eq(former.spellID,143); eq(T.UI.customDraft[2].spellID,143)
end)

test("overview_sections_order_and_class_label",function()
 F.runtime(); T.UI:ShowPage("overview")
 local titles={}; for _,child in ipairs(T.UI.pages.overview.children or {}) do if type(child.text)=="string" and type(child.point)=="table" then titles[child.text]=child.point[5] end end
 assert(titles["运行模式"]>titles["当前配置"]); assert(titles["当前配置"]>titles["派发启停快捷键"])
 for title in pairs(titles) do assert(not title:find("临时覆盖已有绑定",1,true)) end
 T.UI:ShowPage("profiles"); assert(T.UI.readouts.profiles.text:find("法师",1,true)); assert(not T.UI.readouts.profiles.text:find(":base",1,true))
end)
test("matching_plan_toolbar_and_visible_list_bottom",function()
 local combat=InCombatLockdown; InCombatLockdown=function() return false end
 F.runtime(); InCombatLockdown=function() return false end; T.UI:ShowPage("profiles"); T.UI:WriteDraft({spell(143)})
 local parent=UIParent; UIParent={GetWidth=function() return 1920 end,GetHeight=function() return 1080 end}; T.UI.settingsLayoutSignature=nil; T.UI:LayoutSettings()
 eq(T.UI.manualSave.text,"保存配置"); eq(T.UI.customSave.text,"保存配置")
 eq(T.UI.manualSave.point[4],T.UI.customSave.point[4]); eq(T.UI.manualSave.point[5],T.UI.customSave.point[5]); eq(T.UI.manualSave.width,T.UI.customSave.width)
 local a,b=T.UI.sequenceRows[1].policy,T.UI.customWidgets[1].policy; eq(a.point[4],b.point[4]); eq(a.point[5],b.point[5]); eq(a.width,b.width)
 eq(T.UI.customScroll.parent,T.UI.studioEditor); eq(T.UI.sequenceScroll.parent,T.UI.studioEditor)
 assert(T.UI.studioListHeight>=200)
 assert(-T.UI.sequenceScroll.point[5]+T.UI.sequenceScroll.height<T.UI.studioEditor.height)
 UIParent=parent
 InCombatLockdown=combat
end)
test("hud_slider_columns_do_not_overlap_and_accept_signed_decimal",function()
 F.runtime(); T.UI:ShowPage("hud"); eq(T.UI.labelStylePanel.point[5],-48)
 for _,row in pairs(T.UI.hudGeometryControls) do assert(row.slider.point[4]+row.slider.width<row.input.point[4]); eq(row.input.height,32) end
 local value=0; local _,box=T.UI:CreateSliderRow(T.UI.settings,"偏移",0,0,548,-100,100,1,function() return value end,function(v) value=v end,true)
 box.text="-35"; box.scripts.OnEnterPressed(); eq(value,-35)
 local scale=1; local _,decimal=T.UI:CreateSliderRow(T.UI.settings,"缩放",0,0,548,.6,2,.1,function() return scale end,function(v) scale=v end,true)
 decimal.text="1.2"; decimal.scripts.OnEnterPressed(); eq(scale,1.2)
end)
test("distance_style_controls_apply_and_survive_reload",function()
 local e=F.runtime(); local combat,hudEngine=InCombatLockdown,T.HUD.engine; T.HUD.engine=e; InCombatLockdown=function() return false end; T.UI:ShowPage("hud"); assert(e.db.hud.styles.global.rangeText)
 T.UI.labelModuleButtons.global.scripts.OnClick(); T.UI:RefreshControls(); assert(T.UI.labelStyleButtons.rangeText.tefControlEnabled)
 T.UI.labelStyleButtons.rangeText.scripts.OnClick(); T.UI.labelEnabledButton.scripts.OnClick(); eq(e.db.hud.styles.global.rangeText.enabled,false)
 e.db.hud.styles.global.rangeText.fontSize=18; e.db.hud.styles.global.rangeText.offsetX=25
 T.HudStyles:Apply(T.HUD); eq(T.HUD.rangeText.shown,false); eq(T.HUD.rangeText.point[4],25)
 T.Presentation:UpdateRange(T.HUD); eq(T.HUD.rangeText.shown,false)
 local copy=T.Engine.New(T.Config,e.db); eq(copy.db.hud.styles.global.rangeText.fontSize,18); eq(copy.db.hud.styles.global.rangeText.enabled,false); InCombatLockdown=combat; T.HUD.engine=hudEngine
end)

test("reused_strategy_scroll_child_keeps_anchor_and_skill_controls",function()
 F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddCustomSpell(143)
 T.UI:ChangeCustomStrategy(function(row) row.strategies={{mode="use",conditions={{kind="distance",min=10,max=30}}}} end)
 local form=T.UI.strategyForm
 for i=1,10 do
  T.UI.customFormIndex=nil; T.UI:RefreshStrategyForm(); eq(T.UI.strategyForm,form)
  eq(form.point[1],"TOPLEFT"); eq(form.point[2],T.UI.strategyScroll)
  assert(T.UI.strategySpellID.shown); assert(T.UI.strategyReplaceID.shown); assert(T.UI.strategyUpgrade.shown); eq(#T.UI.strategyInputs,2)
  assert(T.UI.strategySpellID.parent==form); assert(T.UI.strategyUpgrade.parent==form)
 end
end)
test("strategy_build_failure_not_cached_and_retry_preserves_conditions",function()
 F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddCustomSpell(143)
 T.UI:ChangeCustomStrategy(function(row) row.strategies={{mode="use",conditions={{kind="moving",value=true}}}} end)
 local create=T.UI.CreateHintText; T.UI.CreateHintText=function() error("SIMULATED_FORM_BUILD_ERROR") end
 T.UI.customFormIndex=nil; eq(pcall(function() T.UI:RefreshStrategyForm() end),false)
 eq(T.UI.customFormIndex,nil); eq(T.UI.strategyPoolActive,false); eq(#T.UI.customDraft[1].strategies,1)
 T.UI.CreateHintText=create; T.UI:RefreshStrategyForm(); eq(T.UI.customFormIndex,1)
 assert(T.UI.strategyForm.point); assert(T.UI.strategyUpgrade.shown); eq(T.UI.strategyBuildError,nil)
end)

test("negative_control_reproduces_anchor_loss_and_explicit_anchor_repairs_it",function()
 F.runtime(); T.UI:ShowPage("customapl"); T.UI:AddCustomSpell(143)
 local paint=T.UI.Paint
 T.UI.Paint=function(self,object,method,...) if object==self.strategyForm and method=="SetPoint" then return true end; return paint(self,object,method,...) end
 T.UI.customFormIndex=nil; T.UI:RefreshStrategyForm(); eq(rawget(T.UI.strategyForm,"point"),nil)
 T.UI.Paint=paint; T.UI.customFormIndex=nil; T.UI:RefreshStrategyForm(); eq(T.UI.strategyForm.point[1],"TOPLEFT")
 local scroll=T.UI.strategyScroll; scroll.GetVerticalScroll=function() return 5000 end; scroll.GetHeight=function() return 530 end
 scroll.SetVerticalScroll=function(self,value) self.testScroll=value end
 T.UI.customFormIndex=nil; T.UI:RefreshStrategyForm(); eq(scroll.testScroll,0)
 scroll.GetVerticalScroll=nil; scroll.GetHeight=nil; scroll.SetVerticalScroll=nil
end)

test("compact_list_controls_stay_inside_row_bounds",function()
 F.runtime(); T.UI:ShowPage("profiles"); T.UI:WriteDraft({spell(143),T.SkillGroups:Row(group())})
 local function inside(frame,controls)
  for _,control in ipairs(controls) do local point=control.point; assert(point and point[1]=="TOPLEFT")
   local x,y=point[4],-point[5]; assert(x>=0 and y>=0); assert(x+control.width<=frame.width); assert(y+control.height<=frame.height)
  end
 end
 for _,w in ipairs(T.UI.sequenceRows) do inside(w.frame,{w.count,w.groupEdit,w.policy,w.up,w.down,w.delete,w.skip,w.usage}); eq(w.frame.height,80) end
 T.UI:ShowPage("customapl"); T.UI:AddCustomSpell(143)
 for _,w in ipairs(T.UI.customWidgets) do if w.frame.shown then inside(w.frame,{w.policy,w.up,w.down,w.delete}); eq(w.frame.height,80) end end
 T.UI:AddSkillGroup("apl"); T.UI:GroupAdd(143)
 for _,w in ipairs(T.UI.groupWidgets) do inside(w.frame,{w.count,w.policy,w.up,w.down,w.delete,w.skip}); eq(w.frame.height,80) end
 T.UI:CloseSkillGroup(true)
end)

test("strategy_viewport_preserves_border_and_scrollbar_gutter",function()
 local combat=InCombatLockdown; InCombatLockdown=function() return false end
 F.runtime(); InCombatLockdown=function() return false end; T.UI:ShowPage("customapl"); T.UI:AddCustomSpell(143)
 local viewport,form,panel=T.UI.strategyScroll,T.UI.strategyForm,T.UI.strategyPanel
 assert(viewport.width>=form.width+4)
 local left=viewport.point[4]; assert(left>=16)
 assert(panel.width-left-viewport.width>=32)
 local oldWidth,oldHeight=UIParent.GetWidth,UIParent.GetHeight
 local oldStrategyWidth,oldGroupWidth=panel.GetWidth,T.UI.groupPanel.GetWidth
 panel.GetWidth=function() return panel.width end; T.UI.groupPanel.GetWidth=function() return 432 end
 UIParent.GetHeight=function() return 1000 end
 for _,case in ipairs({{960,true},{1296,false},{1920,false}}) do
  UIParent.GetWidth=function() return case[1] end
  T.UI.settingsLayoutSignature=nil; T.UI:LayoutSettings(); eq(T.UI.editorOverlay,case[2])
 end
 UIParent.GetWidth,UIParent.GetHeight=oldWidth,oldHeight
 panel.GetWidth,T.UI.groupPanel.GetWidth=oldStrategyWidth,oldGroupWidth
 T.UI.settingsLayoutSignature=nil
 InCombatLockdown=combat
end)
test("studio_shell_preserves_intent_and_workspace_keeps_drafts",function()
 local e=F.runtime(); T.Runtime:SetIntent(true); local intent=T.Runtime.intent
 InCombatLockdown=function() return false end
 T.UI:OpenSettings(); eq(T.UI.studio,true); eq(T.Runtime.intent,intent); eq(T.Dispatch.pending,nil)
 T.UI:ShowPage("profiles"); T.UI:WriteDraft({spell(143,3,true)})
 T.UI:RefreshStudio(); assert(T.UI.studioSequenceTab.text:find("*",1,true))
 T.UI.studioNodes.customapl.scripts.OnClick(); T.UI.studioNodes.profiles.scripts.OnClick()
 local rows=T.UI:DraftRows(); eq(rows[1].spellID,143); eq(rows[1].repeatCount,3); eq(rows[1].skipUnavailable,true)
 T.UI:CloseSettings(); eq(T.UI.settingsOpen,false); eq(T.Runtime.intent,intent)
end)
test("studio_selection_uses_original_strategy_and_unknown_is_display_only",function()
 local e=F.runtime(); T.UI:ShowPage("profiles"); T.UI:WriteDraft({spell(143,3,true)})
 assert(T.UI:SelectStudioRule("manual",1)); eq(T.UI:CustomRow().spellID,143); eq(T.UI.strategyPanel.parent,T.UI.studioInspector)
 T.UI:OpenSequencePolicy(1); eq(T.UI:CustomRow().spellID,143)
 T.UI:ChangeCustomStrategy(function(r) r.strategies={{mode="skip",conditions={{kind="moving",value=true}}}} end)
 eq(T.UI:DraftRows()[1].strategies[1].mode,"skip")
 T.UI:ShowPage("customapl"); assert(T.UI:AddCustomSpell(205)); T.UI:RefreshStudio()
 local before=e.generation; eq(T.UI.customWidgets[1].frame.studioBadge.text,"UNKNOWN")
 T.UI:RefreshStudio(); eq(e.generation,before); eq(T.Dispatch.pending,nil)
 assert(T.UI.studioStatus.text:find("TEK连接：未确认",1,true))
end)
test("studio_apl_cursor_inserts_before_target_and_failure_preserves_cursor",function()
 local e=F.runtime(); T.UI:ShowPage("customapl"); T.UI.customDraft={}; T.UI:AddCustomSpell(143); T.UI:AddCustomSpell(205)
 local cursor,clear=GetCursorInfo,ClearCursor; local cleared=0
 GetCursorInfo=function() return "spell",0,"spell",2136 end; ClearCursor=function() cleared=cleared+1 end
 assert(T.UI:ReceiveCustomSpell(2)); eq(T.UI.customDraft[2].spellID,2136); eq(T.UI.customDraft[3].spellID,205); eq(cleared,1)
 GetCursorInfo=function() return "spell",0,"spell",nil end
 eq(T.UI:ReceiveCustomSpell(1),false); eq(cleared,1); eq(T.UI.customDraft[1].spellID,143)
 GetCursorInfo,ClearCursor=cursor,clear
end)
test("studio_drag_cancel_and_drop_before_keep_strategy_identity",function()
 F.runtime(); T.UI:ShowPage("customapl"); T.UI.customDraft={}; T.UI:AddCustomSpell(143); T.UI:AddCustomSpell(205); T.UI:AddCustomSpell(2136)
 T.UI.customDraft[1].strategies={{mode="skip",conditions={{kind="moving",value=true}}}}
 local over=MouseIsOver; MouseIsOver=function() return false end
 local row=T.UI.customDraft[1]; T.UI.customWidgets[1].frame.scripts.OnDragStart(); T.UI.customWidgets[1].frame.scripts.OnDragStop()
 eq(T.UI.customDraft[1],row)
 MouseIsOver=function(frame) return frame==T.UI.customWidgets[3].frame end
 T.UI.customWidgets[1].frame.scripts.OnDragStart(); T.UI:RefreshStudio(); eq(T.UI.studioInsertion.shown,true)
 T.UI.customWidgets[1].frame.scripts.OnDragStop(); eq(T.UI.customDraft[2],row); eq(row.strategies[1].mode,"skip"); eq(T.UI.studioInsertion.shown,false)
 MouseIsOver=over
end)
test("studio_layout_collapses_panels_without_mutating_draft_and_reuses_frames",function()
 F.runtime(); InCombatLockdown=function() return false end
 T.UI:ShowPage("profiles"); T.UI:WriteDraft({spell(143,3,true)})
 local parent=UIParent; UIParent={GetWidth=function() return 1920 end,GetHeight=function() return 1080 end}
 T.UI:LayoutSettings(); eq(T.UI.studioInspector.shown,true); eq(T.UI.studioWorkspace.shown,true)
 UIParent.GetWidth=function() return 1000 end; UIParent.GetHeight=function() return 720 end
 T.UI:LayoutSettings(); eq(T.UI.studioInspector.shown,false); eq(T.UI.studioWorkspace.shown,false)
 UIParent.GetWidth=function() return 900 end; T.UI:LayoutSettings(); eq(T.UI.studioWorkspace.shown,false)
 eq(T.UI:DraftRows()[1].repeatCount,3)
 local create=CreateFrame; local made=0; CreateFrame=function(...) made=made+1; return create(...) end
 for i=1,25 do T.UI:RefreshStudio(); T.UI:LayoutSettings() end
 eq(made,0); CreateFrame=create
 local h=T.UI.settingsHeight; InCombatLockdown=function() return true end; UIParent.GetHeight=function() return 500 end
 T.UI:LayoutSettings(); eq(T.UI.settingsHeight,h)
 UIParent=parent
end)
test("studio_saved_draft_marker_clears_and_inactive_tab_keeps_marker",function()
 local e=F.runtime(); T.UI:ShowPage("customapl"); T.UI.customDraft={}; T.UI:AddCustomSpell(143)
 assert(T.UI:StudioDirty("apl","single",T.UI.customDraft))
 T.UI.studioSave.scripts.OnClick(); eq(T.UI:StudioDirty("apl","single",T.UI.customDraft),false)
 T.UI:ShowPage("profiles"); T.UI:WriteDraft({spell(205,3,true)}); T.UI:ShowPage("customapl")
 assert(T.UI.studioSequenceTab.text:find("*",1,true))
end)
test("studio_viewport_matrix_keeps_editor_and_footer_reachable",function()
 F.runtime(); InCombatLockdown=function() return false end; T.UI:ShowPage("profiles")
 local parent=UIParent
 for _,size in ipairs({{1920,1080},{2560,1440},{3440,1440},{1280,720}}) do
  for _,scale in ipairs({.75,1,1.25}) do
   UIParent={GetWidth=function() return size[1]/scale end,GetHeight=function() return size[2]/scale end}
   T.UI:LayoutSettings()
   assert(T.UI.studioWidth*T.UI.settingsFitScale<=size[1]/scale-31)
   assert(T.UI.settingsHeight*T.UI.settingsFitScale<=size[2]/scale-31)
   local x=T.UI.studioEditor.point[4]; assert(x+T.UI.studioEditorWidth<=T.UI.studioWidth)
   local footer=T.UI.pageFooters[T.UI.pages.profiles]; eq(footer.point[4],x); assert(-footer.point[5]+88<=T.UI.settingsHeight-28)
  end
 end
 UIParent=parent
end)
test("studio_global_save_commits_open_group_through_existing_save",function()
 local e=F.runtime(); T.UI.editScene="single"; T.UI:ShowPage("profiles")
 T.UI:WriteDraft({T.SkillGroups:Row(group())}); T.UI:OpenSkillGroup("manual",1)
 T.UI.groupRounds.text="3"; T.UI.studioSave.scripts.OnClick()
 eq(e.db.profiles.single[1].group.rounds,3); eq(T.Runtime.intent,false)
 T.UI:CloseSkillGroup(true)
end)
return n
