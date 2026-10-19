local T,F=...
local U,H,C=T.UI,T.HUD,T.APL.Custom
local eq,test=F.eq,F.test
local function setup(page)
 F.deliveryFixture("manual"); InCombatLockdown=function() return false end
 UIParent.GetWidth=function() return 1920 end; UIParent.GetHeight=function() return 1080 end
 U:OpenSettings(); U:ShowPage(page or "profiles")
 return T.engine
end

test("audit_refresh_failures_release_flags_and_recover",function()
 for _,case in ipairs({{"RefreshControls","RefreshPage","refreshingPage"},{"StudioActiveRows","RefreshStudio","studioRefreshing"},{"StudioAnchor","LayoutSettings","studioLayoutBusy"}}) do
  setup(); U.settingsLayoutSignature=nil
  local original=U[case[1]]; U[case[1]]=function() error("INJECTED_REFRESH_FAILURE") end
  eq(pcall(U[case[2]],U),false); eq(U[case[3]],false); eq(U.settingsLayoutSignature,nil)
  U[case[1]]=original
  eq(pcall(U[case[2]],U),true); eq(U[case[3]],false); assert(U.settingsLayoutSignature)
 end
end)

test("audit_small_viewport_cache_updates_window_and_confirmation_scale",function()
 setup(); U:ConfirmAction("缩放测试",function() end); U:CancelConfirmation(); U.settingsLayoutSignature=nil
 U:LayoutStudioSettings(640,1080); local first=U.settingsLayoutSignature
 U:LayoutStudioSettings(600,1080)
 assert(U.settingsLayoutSignature~=first)
 eq(U.settings.scale,568/680); eq(U.confirmationBody.scale,568/680)
end)
test("audit_live_trace_uses_real_heartbeat_even_when_hud_and_signal_hidden",function()
 local e=setup(); T.Transport:SetEnabled(false); U:Paint(H.frame,"Hide")
 local clock=100; GetTime=function() return clock end; GetCurrentKeyBoardFocus=function() return nil end
 local sample=U.StudioProbeRows; local calls=0
 U.StudioProbeRows=function() calls=calls+1; return true end
 U.studioTraceLive=true; U.studioLastProbeTime=nil; H.traceElapsed=0
 local generation,index,serial,intent=e.generation,e.index,e.receiptSerial,T.Runtime.intent
 local tick=H.heartbeat:GetScript("OnUpdate")
 for i=1,30 do clock=100+i*.05; tick(H.heartbeat,.05) end
 assert(calls>=4 and calls<=8); local before=calls
 GetCurrentKeyBoardFocus=function() return F.secret end
 for i=1,10 do clock=102+i*.05; tick(H.heartbeat,.05) end
 eq(calls,before); eq(e.generation,generation); eq(e.index,index); eq(e.receiptSerial,serial); eq(T.Runtime.intent,intent); eq(T.Dispatch.pending,nil)
 U.StudioProbeRows=sample; U.studioTraceLive=false; U:Paint(H.frame,"Show"); GetCurrentKeyBoardFocus=function() return nil end
end)
test("audit_unknown_strategy_keeps_exact_condition_and_chinese_explanation",function()
 setup(); local row={spellID=143,strategies={{mode="use",conditions={{kind="range",value=true},{kind="cdmBuff",spellID=133,value=true}}}}}
 local state={actions={custom_1={in_range=true,strategyCDM={["buff:133"]={reason="CDM_FRAME_MISSING"}}}}}
 local allowed,reason=C:CheckStrategies(state,row,1); eq(allowed,nil); eq(reason,"UNKNOWN:custom:strategy")
 local detail=state.strategyBlockDetails[1]; eq(detail.strategy,1); eq(detail.condition,2); eq(detail.kind,"cdmBuff"); eq(detail.spellID,133); eq(detail.unknown,true)
 assert(detail.description:find("CDM",1,true)); assert(detail.description:find("请确认",1,true))
 local title,body,unknown=H:StatusText({state="blocked",reason=reason,detail={title="条件未知",description=detail.description,unknown=true}})
 eq(title,"条件未知"); eq(body,detail.description); eq(unknown,true)
end)
test("audit_runtime_preserves_display_reason_across_suspend_but_not_reset",function()
 local e=setup(); U:CloseSettings(); T.Runtime:SetIntent(true)
 T.Dispatch:EvidenceBlock("CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED","超出范围","目标超出技能范围，请调整距离",false)
 T.Runtime:Suspend("CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED")
 local view=T.Runtime:GetViewState(); assert(view.detail); eq(view.detail.unknown,false); eq(H:StatusText(view),"超出范围")
 e:Reset(); eq(T.Runtime:GetViewState().detail,nil)
end)
test("audit_known_range_block_and_unknown_range_have_distinct_display",function()
 local e=setup(); GetCurrentKeyBoardFocus=function() return nil end
 UnitExists=function() return true end; UnitCanAttack=function() return true end; UnitIsDeadOrGhost=function() return false end
 C_Spell.IsSpellInRange=function() return false end
 local allowed,reason=T.Dispatch:ContinuousEvidence(e.steps[1].spellID); eq(allowed,false)
 local d=T.Dispatch:BlockDetail(reason); assert(d); eq(d.unknown,false); eq(d.title,"超出范围")
 C_Spell.IsSpellInRange=function() return F.secret end
 allowed,reason=T.Dispatch:ContinuousEvidence(e.steps[1].spellID); eq(allowed,false)
 d=T.Dispatch:BlockDetail(reason); assert(d); eq(d.unknown,true); eq(d.title,"距离未知"); eq(T.Dispatch.pending,nil)
end)
test("audit_studio_has_one_name_writer_and_keeps_target_repair_hint",function()
 local e=setup("customapl"); U.customDraft=C.CleanRows({{spellID=143,enabled=true}})
 e.aplSnapshot={actions={custom_1={spellID=143,reason="CUSTOM_TARGET_UNKNOWN"}}}
 local read=T.Safety.Spell; local reads=0
 T.Safety.Spell=function(...) reads=reads+1; return read(...) end
 U:RefreshPage(); T.Safety.Spell=read
 assert(reads<=2); assert(U.customWidgets[1].frame.studioSummary.text:find("请选择施放类型",1,true)); eq(U.customWidgets[1].frame.studioSummary.shown,true)
 U.customDraft[1].targetMode="enemy"; U:RefreshPage()
 assert(not U.customWidgets[1].frame.tefTooltipBody:find("施放类型未知",1,true))
end)
test("audit_diagnostics_show_identity_summary_and_selected_report",function()
 setup("diagnostics"); local text=U.readouts.diagnostics.text
 assert(text:find("会话",1,true)); assert(text:find("代次",1,true)); assert(text:find("Binding",1,true)); assert(#text>40)
end)
test("audit_mini_geometry_controls_do_not_change_standard_preferences",function()
 local e=setup("hud"); H:SetMode("mini"); U:RefreshPage()
 local before=e.db.hud.geometry.mainSize; local control=U.hudGeometryControls.mainSize
 assert(control.slider.tefDisabledReason:find("固定",1,true))
 control.slider:GetScript("OnValueChanged")(control.slider,32); eq(e.db.hud.geometry.mainSize,before); eq(H.cards[1].size,44)
 H:SetMode("standard"); U:RefreshPage(); eq(rawget(control.slider,"tefDisabledReason"),nil)
end)
test("audit_effective_font_is_readable_and_legacy_preferences_remain",function()
 local e=setup("hud"); H:SetMode("standard")
 local style=e.db.hud.styles.global.name; style.fontSize=8; style.scale=.6
 local font=H.name.SetFont; local actual
 H.name.SetFont=function(_,_,size) actual=size end; H:Layout(); eq(actual,8); eq(style.fontSize,8); eq(style.scale,.6)
 style.fontSize=30; style.scale=2; H:Layout(); eq(actual,14); eq(style.fontSize,30); H.name.SetFont=font
end)
test("audit_unchanged_studio_geometry_is_not_rebuilt",function()
 setup("customapl"); U:RefreshPage()
 local anchor=U.StudioAnchor; local anchors=0
 U.StudioAnchor=function(self,...) anchors=anchors+1; return anchor(self,...) end
 U:RefreshPage(); U.StudioAnchor=anchor
 eq(anchors,0)
 UIParent.GetWidth=function() return 1100 end; U:RefreshPage(); assert(U.studioWidth<1400)
end)
test("audit_hidden_developer_panel_performs_no_spell_reads",function()
 setup(); U.settingsOpen=false; U:Paint(U.frame,"Hide")
 local spell=T.Safety.Spell; local refresh=H.Refresh; local reads=0
 T.Safety.Spell=function(...) reads=reads+1; return spell(...) end; H.Refresh=function() end
 U:Refresh(); eq(reads,0); U:Paint(U.frame,"Show"); U:Refresh(); assert(reads>0)
 U:Paint(U.frame,"Hide"); T.Safety.Spell=spell; H.Refresh=refresh
end)
test("audit_same_snapshot_reuses_cooldown_and_keeps_row_actions_independent",function()
 local e=setup(); local oldRead=C.Read; local reads,probes=0,0; local probe=T.APL.State.ProbeCooldown
 C.Read=function(_,id) reads=reads+1; return {spellID=id,known=true,usable=true,power_ok=true,in_range=true} end
 T.APL.State.ProbeCooldown=function() probes=probes+1; return {active=false} end
 local row={spellID=143,enabled=true,activity="any",moving="any",cdmKind="none",distanceOp="any",strategies={{mode="use",conditions={{kind="cooldown",value=false},{kind="cooldown",value=false}}}}}
 local state={actions={}}; C:Sample(e,state,{row,row})
 eq(reads,1); eq(probes,1); eq(state.actions.custom_1.active,false); eq(state.actions.custom_2.active,false)
 assert(state.actions.custom_1~=state.actions.custom_2); assert(state.actions.custom_1.conditionObservations~=state.actions.custom_2.conditionObservations)
 C.Read=oldRead; T.APL.State.ProbeCooldown=probe
end)
test("audit_research_prototype_is_not_loaded_in_runtime",function()
 setup(); eq(T.Research.Priority,nil)
 local clean=T.Research.CleanSummary({ready="UNKNOWN",gcdClear="UNKNOWN"}); eq(clean.ready,"UNKNOWN"); eq(clean.gcdClear,"UNKNOWN")
end)

test("audit_label_switch_shows_current_effective_value_immediately",function()
 local e=setup("hud"); H:SetMode("standard")
 e.db.hud.styles.global.name.fontSize=30; e.db.hud.styles.global.name.scale=2
 U.labelStyleButtons.name:GetScript("OnClick")(U.labelStyleButtons.name)
 local active
 for _,item in ipairs(U.labelFontPanels) do if item.frame.shown then active=item end end
 assert(active); eq(active.key,"name"); eq(active.input.text,"14")
 U.labelStyleButtons.status:GetScript("OnClick")(U.labelStyleButtons.status)
 H:SetMode("mini")
 for _,item in ipairs(U.labelFontPanels) do if item.frame.shown then active=item end end
 eq(active.key,"status"); eq(active.mini,true); eq(active.input.text,"10")
 H:SetMode("standard")
end)
