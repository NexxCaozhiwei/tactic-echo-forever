local T,F=...
local H,U=T.HUD,T.UI
local eq,test=F.eq,F.test
local function setup()
 F.deliveryFixture("manual")
 InCombatLockdown=function() return false end
 local e=T.engine
 e.db.hud.mode="standard"
 e.db.hud.styles=T.HudStyles.Clean(nil); e.db.hud.geometry=T.HudStyles.CleanGeometry(nil)
 UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
 GetTime=function() return 10 end
 H:Layout(); H:Refresh()
 return e
end

test("hud_opacity_is_saved_and_rejects_secret_or_invalid_values",function()
 local e=setup(); eq(e.db.hud.opacity.background,.94); eq(e.db.hud.opacity.border,1)
 e.db.hud.opacity={background=.35,border=0}
 local copy=T.Engine.New(T.Config,e.db)
 eq(copy.db.hud.opacity.background,.35); eq(copy.db.hud.opacity.border,0)
 local clean=T.HudStyles.CleanOpacity({background=F.secret,border=math.huge})
 eq(clean.background,.94); eq(clean.border,1)
 clean=T.HudStyles.CleanOpacity({background=-1,border=2})
 eq(clean.background,0); eq(clean.border,1)
end)

test("hud_opacity_controls_only_change_shell_in_both_modes",function()
 local e=setup(); U:OpenSettings(); U:ShowPage("hud")
 local generation,index,serial=e.generation,e.index,e.receiptSerial
 local setAlpha=H.frame.SetAlpha; local parentAlphaCalls=0
 H.frame.SetAlpha=function() parentAlphaCalls=parentAlphaCalls+1 end
 local background,border=U.hudOpacityControls.background.slider,U.hudOpacityControls.border.slider
 background:GetScript("OnValueChanged")(background,100)
 border:GetScript("OnValueChanged")(border,75)
 for _,mode in ipairs({"mini","standard"}) do
  H:SetMode(mode); H:Refresh()
  for _,part in ipairs(H.roundSurfaces[H.chrome].fill) do eq(part.color[4],0) end
  for _,part in ipairs(H.roundSurfaces[H.chrome].border) do eq(part.color[4],.25) end
  for _,part in ipairs(H.roundSurfaces[H.chromeInner].border) do eq(part.color[4],.65*.25) end
  for _,card in ipairs(H.cards) do
   for _,part in ipairs(H.roundSurfaces[card.border].border) do eq(part.color[4],1) end
   eq(card.icon.color[4],1)
  end
 end
 background:GetScript("OnValueChanged")(background,0)
 border:GetScript("OnValueChanged")(border,100)
 eq(H.roundSurfaces[H.chrome].fill[1].color[4],1); eq(H.roundSurfaces[H.chrome].border[1].color[4],0)
 eq(parentAlphaCalls,0); eq(e.generation,generation); eq(e.index,index); eq(e.receiptSerial,serial)
 H.frame.SetAlpha=setAlpha
end)
test("hud_compact_matches_260_108_and_uses_shared_rounded_surfaces",function()
 setup(); eq(H.layoutWidth,260); eq(H.layoutHeight,108)
 assert(H.chrome.frameLevel<H.content.frameLevel); assert(H.content.frameLevel<H.cards[1].frame.frameLevel)
 eq(H.cards[1].frame.point[4],6); eq(H.cards[1].size,44); eq(H.cards[2].size,36)
 eq(H.textSlots.name.frame.point[4],56); eq(H.cards[2].frame.point[4],178)
 eq(H.castBar.height,3); eq(-H.castBar.point[5],54); eq(-H.countText.point[5],74)
 assert(H.textSlots.status.frame.point[4]+H.textSlots.status.frame.width<H.countText.point[4])
 eq(H.cards[1].key.scale,1); eq(H.name.scale,1)
 eq(#H.roundSurfaces[H.chrome].fill,9); eq(#H.roundSurfaces[H.chrome].border,9)
 eq(#H.roundSurfaces[H.cards[1].border].border,9)
 assert(H.cards[1].icon.mask); eq(H.spellID,nil); eq(H.rangeText,nil)
 eq(H.castText.shown,true); eq(H.castTime.shown,true); eq(H.role.shown,true); eq(H.cards[2].key,nil)
end)
test("hud_studio_public_cast_progress_is_visual_only",function()
 local e=setup(); local generation,index,serial=e.generation,e.index,e.receiptSerial
 UnitCastingInfo=function() return "寒冰箭",nil,nil,9500,12000 end
 H:RefreshState(); eq(H.castBar.value,.2); eq(H.castTime.text,"0.5 / 2.5秒")
 GetTime=function() return 11 end; H:VisualTick(); eq(H.castBar.value,.6)
 eq(e.generation,generation); eq(e.index,index); eq(e.receiptSerial,serial); eq(T.Dispatch.pending,nil)
end)

test("hud_status_separates_public_cast_channel_unknown_and_other_blockers",function()
 local e=setup(); local index,generation=e.index,e.generation
 local view={state="blocked",reason="CONTINUOUS_CAST_PRESENT_OR_UNKNOWN"}
 UnitCastingInfo=function() return "寒冰箭",nil,nil,9500,12000 end
 H:ReadCastVisual(); eq(H:StatusText(view),"正在施法")
 UnitCastingInfo=function() return nil end
 UnitChannelInfo=function() return "奥术飞弹",nil,nil,9500,12000 end
 H:ReadCastVisual(); eq(H:StatusText(view),"正在引导")
 view.reason="CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED"
 eq(H:StatusText(view),"距离受阻")
 view.reason="CONTINUOUS_CAST_PRESENT_OR_UNKNOWN"
 UnitChannelInfo=function() return F.secret end
 H:ReadCastVisual(); local badge,detail,unknown=H:StatusText(view)
 eq(badge,"施法状态未知"); eq(unknown,true)
 UnitChannelInfo=function() return nil end
 H:ReadCastVisual(); eq(H:StatusText(view),"等待施法结束")
 view.reason="APL_WAIT_CURRENT_RECEIPT"; eq(H:StatusText(view),"等待回执")
 view.reason="RUNTIME_SETTINGS_STANDBY"; eq(H:StatusText(view),"设置中")
 view.state="paused"; eq(H:StatusText(view),"已暂停")
 view.state="completed"; eq(H:StatusText(view),"已完成")
 view.state="error"; eq(H:StatusText(view),"运行异常")
 eq(e.index,index); eq(e.generation,generation); eq(T.Dispatch.pending,nil)
end)
test("hud_studio_channel_counts_down_without_advancing",function()
 local e=setup(); UnitChannelInfo=function() return "奥术飞弹",nil,nil,9500,11500 end
 H:RefreshState(); eq(H.castBar.value,.75); eq(H.castTime.text,"1.5 / 2.0秒")
 eq(H.castText.text,"引导中 · 奥术飞弹"); eq(e.index,1); eq(T.Dispatch.pending,nil)
end)
test("hud_studio_secret_missing_or_invalid_cast_time_stays_unknown",function()
 local e=setup(); local index=e.index
 for _,value in ipairs({F.secret,-1,0/0,math.huge,"时间"}) do
  UnitCastingInfo=function() return "寒冰箭",nil,nil,value,12000 end
  H:RefreshState(); eq(H.castBar.value,0); eq(H.castTime.text,"")
  assert(H.castText.text:find("未知",1,true))
 end
 UnitCastingInfo=function() return F.secret,nil,nil,9500,12000 end
 H:RefreshState(); eq(H.castBar.value,0); eq(H.castTime.text,""); eq(e.index,index)
 UnitCastingInfo=function() return "寒冰箭",nil,nil,9500,12000 end
 GetTime=function() return F.secret end; H:RefreshState()
 eq(H.castBar.value,0); eq(H.castText.text,"施法时间未知"); eq(T.Dispatch.pending,nil)
end)
test("hud_studio_expired_or_replaced_cast_never_predicts_success",function()
 local e=setup(); UnitCastingInfo=function() return "寒冰箭",nil,nil,9500,12000 end
 H:RefreshState(); GetTime=function() return 12 end; H:VisualTick()
 eq(H.castBar.value,0); eq(H.castText.text,"等待状态更新"); eq(e.index,1); eq(e.stepCasts,0)
 GetTime=function() return 10 end; e.generation=e.generation+1; H:VisualTick()
 eq(H.castBar.value,0); eq(H.castText.text,"等待状态更新"); eq(T.Dispatch.pending,nil)
end)
test("hud_studio_visual_tick_does_not_poll_cast_or_resolve_bindings",function()
 setup(); UnitCastingInfo=function() return "寒冰箭",nil,nil,9500,12000 end; H:RefreshState()
 local reads=0; local resolver=T.Dispatch.Resolve
 UnitCastingInfo=function() reads=reads+1 end; UnitChannelInfo=function() reads=reads+1 end
 T.Dispatch.Resolve=function() reads=reads+1 end
 for i=1,20 do H:VisualTick() end
 eq(reads,0); T.Dispatch.Resolve=resolver
end)

test("hud_frame_interpolation_and_centered_keycap_preserve_dispatch",function()
 local e=setup(); UnitCastingInfo=function() return "寒冰箭",nil,nil,9500,12000 end
 H:RefreshState(); H.elapsed=0
 local reads,rangeReads,updates=0,0,0
 local range=T.Presentation.UpdateRange; local setValue=H.castBar.SetValue
 UnitCastingInfo=function() reads=reads+1 end; UnitChannelInfo=function() reads=reads+1 end
 T.Presentation.UpdateRange=function() rangeReads=rangeReads+1 end
 H.castBar.SetValue=function(self,value) updates=updates+1; setValue(self,value) end
 local tick=H.heartbeat:GetScript("OnUpdate")
 for i=1,10 do GetTime=function() return 10+i*.01 end; tick(H.frame,.01) end
 assert(updates>=10); assert(math.abs(H.castBar.value-.24)<.00001)
 eq(reads,0); eq(rangeReads,0); eq(T.Dispatch.pending,nil)
 H.castBar.SetValue=setValue; T.Presentation.UpdateRange=range
 H.cards[1].key:SetText("CTRL-1"); H:RefreshState()
 eq(H.cards[1].key.point[1],"CENTER"); eq(H.cards[1].key.point[2],H.cards[1].keycap)
 eq(H.cards[1].key.point[3],"CENTER"); eq(H.cards[1].key.height,18)
 e.db.hud.styles.global.status.enabled=false; H:Layout()
 eq(H.status.shown,true); eq(H.countText.shown,true)
 eq(H.status.text,"步骤 1/4"); eq(H.countText.text,"本步 0/1")
 eq(e.db.hud.styles.global.status.enabled,false)
end)
test("hud_studio_apl_uses_candidate_label_without_sequence_segments",function()
 local e=setup(); assert(T.Recommendation:SetSource(e,"apl")); H:Refresh()
 eq(H.status.text,"优先级推荐"); eq(H.countText.text,"候选预览"); eq(H.stepSegments,nil)
 assert(not H.status.text:find("步骤",1,true)); eq(T.Dispatch.pending,nil)
end)
test("hud_studio_preview_toggle_and_unknown_status_are_explicit",function()
 local e=setup(); e.db.hud.preview=false; H:Refresh()
 eq(H.cards[2].frame.shown,false); eq(H.cards[3].frame.shown,false); eq(H.previewHint,nil)
 T.Runtime:Changed("blocked","CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED")
 eq(H.badgeText.text,"距离受阻"); eq(H.cards[1].state,nil)
 T.Runtime:Changed("blocked","RUNTIME_COMBAT_UNKNOWN"); eq(H.badgeText.text,"战斗未知"); eq(T.Dispatch.pending,nil)
end)

test("hud_last_group_channel_receipt_keeps_previews_until_group_restored",function()
 local e=setup()
 e.steps={{spellID=5144,name="奥术飞弹",repeatCount=1}}; e.index=1; e.stepCasts=1
 e.completed=true; e.groupRun={group={name="飞弹组",rounds=1},round=1}
 UnitChannelInfo=function() return "奥术飞弹",nil,nil,9500,12500 end
 local generation,serial,intent=e.generation,e.receiptSerial,T.Runtime.intent
 for _,mode in ipairs({"standard","mini"}) do
  assert(H:SetMode(mode)); H:Refresh()
  eq(H.cards[2].frame.shown,true); eq(H.cards[3].frame.shown,true)
  eq(H.cards[2].displayStep.spellID,5144); eq(H.cards[3].displayStep.spellID,5144)
  eq(H.primaryFullName,"spell5144")
  e.db.hud.preview=false; H:Refresh(); eq(H.cards[2].frame.shown,false)
  e.db.hud.preview=true
 end
 e.groupRun=nil; H:Refresh(); eq(H.cards[2].frame.shown,false); eq(H.cards[3].frame.shown,false)
 eq(e.generation,generation); eq(e.receiptSerial,serial); eq(e.index,1); eq(e.stepCasts,1)
 eq(T.Runtime.intent,intent); eq(T.Dispatch.pending,nil)
end)
test("hud_removed_labels_and_ignored_anchors_are_not_recreated",function()
 local e=setup()
 local clean=T.HudStyles.Clean({main={key={fontSize=10,offsetX=20},state={enabled=true}},global={rangeText={enabled=true}}})
 eq(clean.main.key.fontSize,10); eq(clean.main.key.offsetX,nil); eq(clean.main.state,nil)
 eq(clean.global.rangeText,nil); eq(clean.preview,nil)
 eq(H.rangeText,nil); eq(H.previewTitle,nil); eq(H.stepSegments,nil)
 for _,card in ipairs(H.cards) do
  eq(card.state,nil); eq(card.meta,nil); eq(card.label,nil); eq(card.cooldownText,nil); eq(card.chargeText,nil)
 end
 eq(e.db.hud.geometry.mainSize,64)
end)

test("hud_compact_large_legacy_preferences_never_expand_footprint",function()
 local e=setup(); e.db.hud.geometry={mainSize=112,preview1Size=96,preview2Size=96,gap1=40,gap2=40}
 for _,key in ipairs({"name","status"}) do
  local v=e.db.hud.styles.global[key]; v.fontSize=30; v.scale=2; v.offsetX=100; v.offsetY=150
 end
 e.db.hud.scale=1.8; H:Layout()
 eq(H.layoutWidth,260); eq(H.layoutHeight,108); eq(H.frame.scale,1)
 assert(H.frame.width*H.frame.scale<=260); assert(H.frame.height*H.frame.scale<=108)
 eq(H.cards[1].size,44); eq(H.cards[2].size,36); eq(H.cards[3].size,36)
 eq(e.db.hud.geometry.mainSize,112); eq(e.db.hud.styles.global.name.fontSize,30); eq(e.db.hud.scale,1.8)
 eq(H.name.point[4],0); eq(H.name.point[5],0); eq(H.rangeText,nil)
 e.db.hud.styles.global.status.enabled=false; H:Layout(); eq(H.status.shown,true); eq(H.countText.shown,true)
end)
test("hud_compact_metadata_and_controls_stay_in_tooltip",function()
 local e=setup(); local lines={}; local tooltip=GameTooltip
 GameTooltip={AddLine=function(_,text) lines[#lines+1]=text end}
 H:TooltipDetails(H.cards[1]); GameTooltip=tooltip
 local joined=table.concat(lines,"\n")
 assert(joined:find("SpellID",1,true)); assert(joined:find("固定序列",1,true))
 eq(H.hint,nil); eq(H.sourceText,nil); eq(H.previewTitle,nil)
 eq(H.status.text,"步骤 1/4"); eq(H.countText.text,"本步 0/1"); eq(T.Dispatch.pending,nil)
end)
test("hud_compact_round_surfaces_reuse_their_texture_pieces",function()
 setup(); local surface=H.roundSurfaces[H.chrome]; local fill,border=surface.fill[1],surface.border[9]
 for i=1,5 do H:Layout(); H:RefreshState() end
 eq(H.roundSurfaces[H.chrome].fill[1],fill); eq(H.roundSurfaces[H.chrome].border[9],border)
 eq(#surface.fill,9); eq(#surface.border,9)
end)

test("hud_quick_plan_buttons_are_small_unlabelled_and_preserve_existing_layout",function()
 local e=setup(); eq(#H.quickPlanRows,2); eq(H.quickPlans.shown,true)
 eq(H.quickPlans.point[4],120)
 eq(-H.quickPlans.point[5]+23/2,-H.cards[2].frame.point[5]+H.cards[2].size/2)
 assert(H.textSlots.name.frame.point[4]+H.textSlots.name.width<H.quickPlans.point[4])
 for _,row in ipairs(H.quickPlanRows) do
  eq(#row.buttons,3)
  for _,button in ipairs(row.buttons) do eq(button.width,10); eq(button.height,10); eq(rawget(button,"text"),nil) end
 end
 eq(H.quickPlanRows[1].label.text,"[A]"); eq(H.quickPlanRows[2].label.text,"[S]")
 eq(H.quickPlanRows[2].buttons[1].quickSelected,true)
 eq(H.quickPlanRows[1].buttons[1].quickSelected,false)
 local generation,index=e.generation,e.index
 eq(H:SelectQuickPlan("manual","single"),true); eq(e.generation,generation); eq(e.index,index)
 eq(H:SelectQuickPlan("apl","third"),false); eq(e.generation,generation)
 eq(H:SelectQuickPlan("invalid","single"),false)
 eq(H:SelectQuickPlan("manual",F.secret),false)
 H:SetMode("mini"); eq(H.quickPlans.shown,false)
 H:SetMode("standard"); eq(H.quickPlans.shown,true)
 eq(H.layoutWidth,260); eq(H.layoutHeight,108)
 eq(H.castBar.point[5],-54); eq(H.cards[2].frame.point[4],178)
end)

test("hud_quick_plan_switch_reuses_profile_reset_and_has_one_selected_button",function()
 local e=setup()
 assert(T.Profiles:SetPlanEnabled(e,"apl","multi",true))
 assert(T.Runtime:Start("HUD_TEST")); eq(T.Runtime.intent,true)
 local generation=e.generation
 local button=H.quickPlanRows[1].buttons[2]; local click=button:GetScript("OnClick")
 click(button,"RightButton"); eq(T.Recommendation:BaseSource(e),"manual")
 click(button,"LeftButton"); eq(T.Recommendation:BaseSource(e),"apl"); eq(e.scene,"multi")
 eq(e.db.selectedPlans.apl,"multi"); eq(e.db.selectedPlans.manual,"single")
 eq(T.Runtime.intent,false); assert(e.generation>generation); eq(T.Dispatch.pending,nil)
 local count=0
 for _,row in ipairs(H.quickPlanRows) do for _,item in ipairs(row.buttons) do if item.quickSelected then count=count+1 end end end
 eq(count,1); eq(button.quickSelected,true)
 e.maintenanceActive=true; H:RefreshQuickPlans(); eq(button.quickSelected,true); e.maintenanceActive=nil
 generation=e.generation
 H.quickPlanRows[2].buttons[3]:GetScript("OnClick")(nil,"LeftButton")
 eq(e.generation,generation); eq(e.scene,"multi")
 assert(H:SelectQuickPlan("manual","single")); eq(T.Recommendation:BaseSource(e),"manual")
 eq(H.quickPlanRows[2].buttons[1].quickSelected,true)
end)


test("hud_mini_switch_preserves_runtime_and_restores_standard",function()
 local e=setup(); local generation,index,serial=e.generation,e.index,e.receiptSerial
 local intent=T.Runtime.intent; local pending=T.Dispatch.pending
 local fill=H.roundSurfaces[H.chrome].fill[1]
 for i=1,5 do
  assert(H:SetMode("mini")); eq(e.db.hud.mode,"mini")
  eq(H.layoutWidth,156); eq(H.layoutHeight,60); eq(H.cards[2].size,36)
  eq(H.cards[1].frame.point[5],-6); eq(H.cards[2].frame.point[4],62)
  eq(H.name.shown,false); eq(H.status.shown,false); eq(H.badge.shown,false)
  eq(H.castText.shown,false); eq(H.castTime.shown,false); eq(H.role.shown,false)
  eq(H.countText.text,"0/1"); eq(H.countText.parent,H.cards[1].textParent)
  eq(H.statusDot.parent,H.cards[1].textParent); eq(H.castBar.height,2)
  eq(H.modeButton.width,8); eq(H.modeButton.height,8); eq(H.modeButton.point[4],146)
  assert(H:SetMode("standard")); eq(H.layoutWidth,260); eq(H.layoutHeight,108)
  eq(H.countText.text,"本步 0/1"); eq(H.countText.parent,H.content)
  eq(H.badge.shown,true); eq(H.name.shown,true); eq(H.status.shown,true)
  eq(H.castText.shown,true); eq(H.castTime.shown,true); eq(H.role.shown,true)
  eq(H.modeButton.point[4],250); eq(H.chromeInner.width,258)
 end
 eq(H.roundSurfaces[H.chrome].fill[1],fill)
 eq(e.generation,generation); eq(e.index,index); eq(e.receiptSerial,serial)
 eq(T.Runtime.intent,intent); eq(T.Dispatch.pending,pending)
end)

test("hud_mode_button_requires_public_peace_and_left_click",function()
 local e=setup(); local click=H.modeButton:GetScript("OnClick")
 click(nil,"RightButton"); eq(e.db.hud.mode,"standard")
 InCombatLockdown=function() return true end
 click(nil,"LeftButton"); eq(e.db.hud.mode,"standard"); eq(H.layoutWidth,260)
 InCombatLockdown=function() return F.secret end
 assert(not H:SetMode("mini")); eq(e.db.hud.mode,"standard")
 InCombatLockdown=function() return false end
 click(nil,"LeftButton"); eq(e.db.hud.mode,"mini"); eq(H.layoutWidth,156)
 assert(not H:SetMode(F.secret)); assert(not H:SetMode("bad"))
 e.db.hud.styles.global.status.enabled=false; H:Layout()
 eq(H.countText.shown,false); eq(H.miniCountChip.shown,false)
 e.db.hud.preview=false; H:Refresh(); eq(H.cards[2].frame.shown,false)
 H:SetMode("standard")
end)


test("hud_mini_saved_mode_is_whitelisted_and_apl_has_no_repeat_chip",function()
 local e=setup(); H:SetMode("mini")
 local copy=T.Engine.New(T.Config,e.db); eq(copy.db.hud.mode,"mini")
 for _,bad in ipairs({F.secret,"other",42}) do
  e.db.hud.mode=bad; copy=T.Engine.New(T.Config,e.db); eq(copy.db.hud.mode,"standard")
 end
 e.db.hud.mode="mini"; H:Layout()
 assert(T.Recommendation:SetSource(e,"apl")); H:Refresh()
 eq(H.countText.shown,false); eq(H.miniCountChip.shown,false)
 H:SetMode("standard"); eq(H.countText.text,"候选预览"); eq(H.countText.shown,true)
end)
