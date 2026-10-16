local T,F=...
local H,U=T.HUD,T.UI
local eq,test=F.eq,F.test
local function setup()
 F.deliveryFixture("manual")
 InCombatLockdown=function() return false end
 local e=T.engine
 e.db.hud.styles=T.HudStyles.Clean(nil); e.db.hud.geometry=T.HudStyles.CleanGeometry(nil)
 UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
 GetTime=function() return 10 end
 H:Layout(); H:Refresh()
 return e
end
test("hud_compact_matches_260_88_and_uses_shared_rounded_surfaces",function()
 setup(); eq(H.layoutWidth,260); eq(H.layoutHeight,88)
 assert(H.chrome.frameLevel<H.content.frameLevel); assert(H.content.frameLevel<H.cards[1].frame.frameLevel)
 eq(H.cards[1].frame.point[4],6); eq(H.cards[1].size,44); eq(H.cards[2].size,28)
 eq(H.textSlots.name.frame.point[4],56); eq(H.cards[2].frame.point[4],194)
 eq(H.castBar.height,3); eq(-H.castBar.point[5],54); eq(-H.countText.point[5],68)
 assert(H.textSlots.status.frame.point[4]+H.textSlots.status.frame.width<H.countText.point[4])
 eq(H.cards[1].key.scale,1); eq(H.name.scale,1)
 eq(#H.roundSurfaces[H.chrome].fill,9); eq(#H.roundSurfaces[H.chrome].border,9)
 eq(#H.roundSurfaces[H.cards[1].border].border,9)
 assert(H.cards[1].icon.mask); eq(H.spellID.shown,false); eq(H.rangeText.shown,false)
 eq(H.castText.shown,false); eq(H.castTime.shown,false); eq(H.cards[2].key.shown,false)
end)
test("hud_studio_public_cast_progress_is_visual_only",function()
 local e=setup(); local generation,index,serial=e.generation,e.index,e.receiptSerial
 UnitCastingInfo=function() return "寒冰箭",nil,nil,9500,12000 end
 H:RefreshState(); eq(H.castBar.value,.2); eq(H.castTime.text,"0.5 / 2.5秒")
 GetTime=function() return 11 end; H:VisualTick(); eq(H.castBar.value,.6)
 eq(e.generation,generation); eq(e.index,index); eq(e.receiptSerial,serial); eq(T.Dispatch.pending,nil)
end)
test("hud_studio_channel_counts_down_without_advancing",function()
 local e=setup(); UnitChannelInfo=function() return "奥术飞弹",nil,nil,9500,11500 end
 H:RefreshState(); eq(H.castBar.value,.75); eq(H.castTime.text,"1.5 / 2.0秒")
 eq(H.cards[1].state.text,"引导"); eq(e.index,1); eq(T.Dispatch.pending,nil)
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
test("hud_studio_apl_uses_candidate_label_without_sequence_segments",function()
 local e=setup(); assert(T.Recommendation:SetSource(e,"apl")); H:Refresh()
 eq(H.previewTitle.text,"候选预览"); eq(H.previewHint.text,"非施放顺序")
 for _,segment in ipairs(H.stepSegments) do eq(segment.shown,false) end
 assert(not H.status.text:find("步骤",1,true)); eq(T.Dispatch.pending,nil)
end)
test("hud_studio_preview_toggle_and_unknown_status_are_explicit",function()
 local e=setup(); e.db.hud.preview=false; H:Refresh()
 eq(H.cards[2].frame.shown,false); eq(H.cards[3].frame.shown,false); eq(H.previewHint.text,"预览已关闭")
 T.Runtime:Changed("blocked","CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED")
 eq(H.badgeText.text,"阻断·距离"); eq(H.cards[1].state.text,"阻断·距离")
 T.Runtime:Changed("blocked","RUNTIME_COMBAT_UNKNOWN"); eq(H.badgeText.text,"状态未知"); eq(T.Dispatch.pending,nil)
end)
test("hud_compact_preserves_saved_styles_without_showing_extra_labels",function()
 local e=setup(); local style=e.db.hud.styles.global.rangeText
 style.offsetX=25; style.offsetY=-120; style.enabled=true
 H:Layout(); eq(H.rangeText.parent,H.textSlots.rangeText.frame)
 eq(H.rangeText.point[4],0); eq(H.rangeText.shown,false)
 eq(style.offsetX,25); eq(style.offsetY,-120); eq(style.enabled,true); eq(e.db.hud.geometry.mainSize,64)
end)
test("hud_compact_large_legacy_preferences_never_expand_footprint",function()
 local e=setup(); e.db.hud.geometry={mainSize=112,preview1Size=96,preview2Size=96,gap1=40,gap2=40}
 for _,key in ipairs({"name","status","rangeText"}) do
  local v=e.db.hud.styles.global[key]; v.fontSize=30; v.scale=2; v.offsetX=100; v.offsetY=150
 end
 e.db.hud.scale=1.8; H:Layout()
 eq(H.layoutWidth,260); eq(H.layoutHeight,88); eq(H.frame.scale,1)
 assert(H.frame.width*H.frame.scale<=260); assert(H.frame.height*H.frame.scale<=100)
 eq(H.cards[1].size,44); eq(H.cards[2].size,28); eq(H.cards[3].size,28)
 eq(e.db.hud.geometry.mainSize,112); eq(e.db.hud.styles.global.name.fontSize,30); eq(e.db.hud.scale,1.8)
 eq(H.name.point[4],0); eq(H.name.point[5],0); eq(H.rangeText.shown,false)
 e.db.hud.styles.global.status.enabled=false; H:Layout(); eq(H.status.shown,false); eq(H.countText.shown,false)
end)
test("hud_compact_metadata_and_controls_stay_in_tooltip",function()
 local e=setup(); local lines={}; local tooltip=GameTooltip
 GameTooltip={AddLine=function(_,text) lines[#lines+1]=text end}
 H:TooltipDetails(H.cards[1]); GameTooltip=tooltip
 local joined=table.concat(lines,"\n")
 assert(joined:find("SpellID",1,true)); assert(joined:find("固定序列",1,true))
 eq(H.hint.shown,false); eq(H.sourceText.shown,false); eq(H.previewTitle.shown,false)
 eq(H.status.text,"步骤 1/4"); eq(H.countText.text,"本步 0/1"); eq(T.Dispatch.pending,nil)
end)
test("hud_compact_round_surfaces_reuse_their_texture_pieces",function()
 setup(); local surface=H.roundSurfaces[H.chrome]; local fill,border=surface.fill[1],surface.border[9]
 for i=1,5 do H:Layout(); H:RefreshState() end
 eq(H.roundSurfaces[H.chrome].fill[1],fill); eq(H.roundSurfaces[H.chrome].border[9],border)
 eq(#surface.fill,9); eq(#surface.border,9)
end)
