local _,T,F=...
local U,C=T.UI,T.APL.Custom
local n=0
local function eq(a,b) assert(a==b,"Studio期望 " .. tostring(b) .. "，实际 " .. tostring(a)) end
local function test(name,fn) fn(); n=n+1 end
local function setup()
 local e=F.runtime(); InCombatLockdown=function() return false end
 UIParent.GetWidth=function() return 1920 end; UIParent.GetHeight=function() return 1080 end
 U:ShowPage("customapl"); U.customDraft={}; U:AddCustomSpell(143); U:AddCustomSpell(205)
 return e
end
local function spell(id) return {spellID=id,name="技能 " .. id,matchIDs={id},repeatCount=1,enabled=true,strategies={}} end
test("规则选择直接绑定嵌入Inspector且保留原保存接口",function()
 local e=setup(); assert(U:SelectStudioRule("apl",2)); eq(U:CustomRow(),U.customDraft[2]); eq(U.strategyPanel.parent,U.studioInspector)
 U:ChangeCustomStrategy(function(r) r.strategies={{mode="use",conditions={{kind="range",value=true}}}} end)
 eq(#U.customDraft[2].strategies,1); eq(#C:Rows(e),0)
 U:StudioAction(U.studioSave); eq(C:Rows(e)[2].strategies[1].conditions[1].kind,"range")
end)
test("Inspector无效数值阻止切换并保留输入",function()
 setup(); U:SelectStudioRule("apl",1)
 U:ChangeCustomStrategy(function(r) r.strategies={{mode="use",conditions={{kind="distance",min=10,max=20}}}} end)
 local box=U.strategyInputs[1].box; box.text="错误"
 eq(U:SelectStudioRule("apl",2),false); eq(U.customSelected,1); eq(box.text,"错误")
 box.text="10"; assert(U:CommitCustomNumbers())
end)
test("技能组主列表不随Inspector切换隐藏且统一行组件",function()
 setup(); U:AddSkillGroup("apl"); U:GroupAdd(143); U:GroupAdd(205)
 eq(U.groupScroll.parent,U.studioEditor); assert(U.groupWidgets[1].frame.studioIcon)
 U:SelectStudioRule("group",2); eq(U.strategySource,"groupStep"); eq(U:CustomRow(),U.groupDraft.steps[2])
 eq(U.groupScroll.shown,true); eq(U.groupPanel.shown,false)
 U:ShowStudioPlan(); eq(U.groupScroll.shown,true); eq(U.groupPanel.shown,true)
 U:StudioAction(U.groupExitButton); eq(U.groupEditing,nil); eq(#U.customDraft[3].group.steps,2)
end)
test("技能组返回先校验并暂存不自动持久化",function()
 local e=setup(); U:AddSkillGroup("apl"); U:GroupAdd(143); U.groupRounds.text="3"
 U:StudioAction(U.groupExitButton); eq(U.customDraft[3].group.rounds,3); eq(#C:Rows(e),0)
 U:AddSkillGroup("apl"); U:StudioAction(U.groupExitButton); assert(U.groupEditing)
 U:CloseSkillGroup(true)
end)
test("技能组排序共用插入线且取消不改变草稿",function()
 setup(); U:AddSkillGroup("apl"); U:GroupAdd(143); U:GroupAdd(205)
 local over=MouseIsOver; MouseIsOver=function() return false end
 U.groupWidgets[1].frame.scripts.OnDragStart(); U.groupWidgets[1].frame.scripts.OnDragStop(); eq(U.groupDraft.steps[1].spellID,143)
 MouseIsOver=function(frame) return frame==U.groupScroll end
 U.groupWidgets[1].frame.scripts.OnDragStart(); U.groupWidgets[1].frame.scripts.OnDragStop(); eq(U.groupDraft.steps[2].spellID,143)
 MouseIsOver=over; U:CloseSkillGroup(true)
end)
test("只读Trace采样不改变运行候选额度与身份",function()
 local e=setup(); local generation,index,serial,intent=e.generation,e.index,e.receiptSerial,T.Runtime.intent
 local candidate,snapshot,records,groups=e.aplCandidate,e.aplSnapshot,e.policyRecords,e.groupConsumed
 assert(U:StudioProbeRows()); eq(e.generation,generation); eq(e.index,index); eq(e.receiptSerial,serial); eq(T.Runtime.intent,intent)
 eq(e.aplCandidate,candidate); eq(e.aplSnapshot,snapshot); eq(e.policyRecords,records); eq(e.groupConsumed,groups); eq(T.Dispatch.pending,nil)
 assert(U.studioProbe.state.readOnly); assert(U.studioProbe.rows[1].result)
end)
test("Trace定位严格检查草稿内容及场景身份",function()
 setup(); assert(U:StudioProbeRows()); U:StudioAction(U.studioTraceWidgets[2]); eq(U.customSelected,2)
 U:ReorderCustomRule(1,2); eq(U:StudioProbeCurrent(),nil)
 U:StudioAction(U.studioTraceWidgets[1]); eq(U.customSelected,2)
 U:StudioProbeRows(); U.customScene="multi"; U:RefreshCustomAPL(); eq(U:StudioProbeCurrent(),nil)
end)
test("Secret可用性保持UNKNOWN且不转为FALSE",function()
 local e=setup(); local usable=C_Spell.IsSpellUsable; C_Spell.IsSpellUsable=function() return F.secret,F.secret end
 assert(U:StudioProbeRows()); eq(U.studioProbe.rows[1].result,"UNKNOWN"); eq(T.Dispatch.pending,nil)
 C_Spell.IsSpellUsable=usable
end)
test("问题面板复用Audit不虚构不可达结论",function()
 setup(); U.customDraft[1].strategies={{mode="use",conditions={{kind="moving",value=true},{kind="moving",value=false}}}}
 U.studioBottomMode="problems"; U:RefreshStudioBottom(); assert(U.studioAuditText:find("矛盾",1,true)); eq(T.Dispatch.pending,nil)
end)
test("技能库严格收录已学非被动精确ID且不按名称合并",function()
 setup(); local book=C_SpellBook; local enum=Enum
 Enum={SpellBookSpellBank={Player=0},SpellBookItemType={Spell=1}}
 C_SpellBook={GetNumSpellBookSkillLines=function() return 1 end,GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0,numSpellBookItems=4} end,
  GetSpellBookItemInfo=function(i) return {itemType=1,spellID=({143,205,2136,999})[i],isPassive=i==3} end,
  IsSpellKnown=function(id) if id==999 then return F.secret end; return true end}
 U:RefreshStudioLibrary(true); eq(#U.studioLibraryCatalog,2)
 U.studioLibrarySearch.text="205"; U:RefreshStudioLibrary(false); eq(#U.studioLibraryMatches,1); eq(U.studioLibraryMatches[1].spellID,205)
 C_SpellBook=book; Enum=enum; U.studioLibrarySearch.text=""
end)
test("技能库缓存不在普通刷新中反复扫描",function()
 setup(); U:RefreshStudioLibrary(true)
 local fn=C_SpellBook.GetNumSpellBookSkillLines; local calls=0
 C_SpellBook.GetNumSpellBookSkillLines=function() calls=calls+1; return 0 end
 for i=1,25 do U:RefreshStudioLibrary(false); U:RefreshStudio() end
 eq(calls,0); C_SpellBook.GetNumSpellBookSkillLines=fn
end)
test("技能库添加和拖入复用父列表及组内插入接口",function()
 setup(); local passive=C_Spell.IsSpellPassive; C_Spell.IsSpellPassive=function() return false end
 assert(U:StudioInsert(143,2)); eq(U.customDraft[2].spellID,143); eq(U.customDraft[3].spellID,205)
 U:AddSkillGroup("apl"); assert(U:StudioInsert(143)); assert(U:StudioInsert(205,1)); eq(U.groupDraft.steps[1].spellID,205)
 U:CloseSkillGroup(true); C_Spell.IsSpellPassive=passive
end)
test("技能库已学或被动身份变未知时保留原列表",function()
 setup(); local passive=C_Spell.IsSpellPassive; C_Spell.IsSpellPassive=function() return F.secret end
 local count=#U.customDraft; eq(U:StudioInsert(143),false); eq(#U.customDraft,count)
 C_Spell.IsSpellPassive=passive
end)
test("条件搜索复用原定义并保留职业限制",function()
 setup(); U.studioConditionFilter="CDM"; U:RefreshStrategyKinds()
 eq(U.strategyKindButtons.cdmBuff.shown,true); eq(U.strategyKindButtons.distance.shown,false)
 U.studioConditionFilter="连击"; U:RefreshStrategyKinds(); eq(U.strategyKindButtons.comboPoints.shown,false)
 U.studioConditionFilter=""; U:RefreshStrategyKinds()
end)
test("条件芯片只显示要求与数量不伪造就绪",function()
 setup(); U.customDraft[1].strategies={{mode="use",conditions={{kind="moving",value=false},{kind="range",value=true},{kind="learned",value=true},{kind="combat",value=true}}}}
 U.studioProbe=nil; U:RefreshStudio()
 eq(U.customWidgets[1].frame.studioChips[3].label.text,"＋2项"); eq(U.customWidgets[1].frame.studioBadge.text,"UNKNOWN")
end)
test("不同窗口下列表底部与固定保存区不重叠",function()
 setup(); local parent=UIParent
 for _,size in ipairs({{1920,1080},{2560,1440},{3440,1440},{1280,720},{1000,600},{720,540}}) do
  UIParent={GetWidth=function() return size[1] end,GetHeight=function() return size[2] end}
  U.studioInspectorRequested=false; U:LayoutSettings()
  local footer=U.pageFooters[U.pages.customapl]
  local listBottom=-U.studioEditor.point[5]-U.customScroll.point[5]+U.customScroll.height
  assert(listBottom<=-footer.point[5],"列表遮挡固定保存区")
  assert(-footer.point[5]+88<=-U.studioBottom.point[5])
  assert(U.studioEditorWidth>=580)
 end
 UIParent=parent
end)
test("窄屏Inspector覆盖拦截编辑区且关闭不丢草稿",function()
 setup(); local parent=UIParent; UIParent={GetWidth=function() return 1000 end,GetHeight=function() return 720 end}
 U:SelectStudioRule("apl",1); U:LayoutSettings(); eq(U.editorOverlay,true); eq(U.studioInspectorShield.shown,true)
 U:StudioAction(U.studioInspectorClose); eq(U.studioInspectorShield.shown,false); eq(#U.customDraft,2)
 UIParent=parent
end)
test("预热后连续切换Inspector与诊断不增加Frame或同步注册",function()
 setup(); U:SelectStudioRule("apl",1); U:SelectStudioRule("apl",2); U:StudioProbeRows(); U:ShowStudioInsertion(U.customWidgets[1].frame); U:HideStudioInsertion()
 local create=CreateFrame; local made=0; local syncs=#U.controls
 CreateFrame=function(...) made=made+1; return create(...) end
 for i=1,25 do U:SelectStudioRule("apl",1); U:SelectStudioRule("apl",2); U:RefreshStudioBottom(); U:LayoutSettings() end
 CreateFrame=create; eq(made,0); eq(#U.controls,syncs)
end)
test("复制条目深拷贝条件并保留容量限制",function()
 setup(); U:SelectStudioRule("apl",1); U:ChangeCustomStrategy(function(r) r.strategies={{mode="skip",conditions={{kind="moving",value=true}}}} end)
 assert(U:DuplicateStudioRow()); eq(U.customDraft[2].strategies[1].mode,"skip")
 assert(U.customDraft[1].strategies~=U.customDraft[2].strategies)
 U.customDraft[2].strategies[1].conditions[1].value=false; eq(U.customDraft[1].strategies[1].conditions[1].value,true)
 while #U.customDraft<16 do U:AddCustomSpell(143) end
 U:SelectStudioRule("apl",1); eq(U:DuplicateStudioRow(),false); eq(#U.customDraft,16)
end)
test("修改序列次数后Inspector重绑同一索引不留空白详情",function()
 setup(); U.editScene="single"; U:ShowPage("profiles"); U:WriteDraft({spell(143),spell(205)})
 U:SelectStudioRule("manual",1); assert(U:EditSequenceRow(1,"count","3"))
 eq(U.studioSelected.index,1); eq(U:CustomRow().repeatCount,3); eq(U.strategyPanel.shown,true)
 U:EditSequenceRow(1,"move",1); eq(U.studioSelected.index,2); eq(U:CustomRow().spellID,143)
end)
test("APL箭头排序同步高亮和Inspector身份",function()
 setup(); U:SelectStudioRule("apl",1); U:MoveCustomRule(1,1)
 eq(U.studioSelected.index,2); eq(U.customSelected,2); eq(U:CustomRow().spellID,143)
end)
test("删除撤销清理详情旧回调且保持条件",function()
 setup(); U:SelectStudioRule("apl",1); U:ChangeCustomStrategy(function(r) r.strategies={{mode="skip",conditions={{kind="moving",value=true}}}} end)
 U:DeleteDraft("apl",1); eq(U.studioSelected,nil); eq(U.strategyPanel.shown,false)
 U:UndoDelete("apl"); eq(U.customDraft[1].strategies[1].mode,"skip")
end)
test("实时采样复用心跳并在输入焦点占用时暂停",function()
 setup(); local clock,focus=GetTime,GetCurrentKeyBoardFocus; local sample=U.StudioProbeRows; local calls=0
 U.StudioProbeRows=function() calls=calls+1; return true end
 U.settingsOpen=true; U.studioTraceLive=true; U.studioLastProbeTime=nil
 GetTime=function() return 100 end; GetCurrentKeyBoardFocus=function() return nil end
 U:MaybeStudioLiveProbe(); U:MaybeStudioLiveProbe(); eq(calls,1)
 GetTime=function() return 100.21 end; U:MaybeStudioLiveProbe(); eq(calls,2)
 GetCurrentKeyBoardFocus=function() return {} end; GetTime=function() return 101 end; U:MaybeStudioLiveProbe(); eq(calls,2)
 GetCurrentKeyBoardFocus=function() return F.secret end; U:MaybeStudioLiveProbe(); eq(calls,2)
 U.StudioProbeRows=sample; U.studioTraceLive=false; U.settingsOpen=false; GetTime=clock; GetCurrentKeyBoardFocus=focus
end)
test("采样期间代次变化拒绝发布旧Trace",function()
 local e=setup(); local fn=C_Spell.IsSpellUsable; local changed=false
 C_Spell.IsSpellUsable=function(id) if not changed then changed=true; e.generation=e.generation+1 end; return true,false end
 eq(U:StudioProbeRows(),false); eq(U.studioProbe,nil)
 C_Spell.IsSpellUsable=fn
end)
test("组内排序保留选中技能的Inspector身份与条件",function()
 setup(); U:AddSkillGroup("apl"); U:GroupAdd(143); U:GroupAdd(205); U:SelectStudioRule("group",2)
 U:ChangeCustomStrategy(function(r) r.strategies={{mode="use",conditions={{kind="moving",value=false}}}} end)
 U:GroupMove(1,2); eq(U.groupSelected,1); eq(U.studioSelected.index,1); eq(U:CustomRow().spellID,205)
 eq(U:CustomRow().strategies[1].conditions[1].value,false); U:CloseSkillGroup(true)
end)
test("只读求值期间身份变化再次拒绝发布Trace",function()
 local e=setup(); local check=C.Check; local changed=false
 C.Check=function(self,...) if not changed then changed=true; e.generation=e.generation+1 end; return check(self,...) end
 eq(U:StudioProbeRows(),false); eq(U.studioProbe,nil); C.Check=check
end)
test("低窗口方案属性可滚动且收起后不留下覆盖遮罩",function()
 setup(); local parent=UIParent; UIParent={GetWidth=function() return 1000 end,GetHeight=function() return 600 end}
 U:ShowStudioPlan(); U:LayoutSettings(); eq(U.studioPlanScroll.shown,true)
 assert(U.studioPlanScroll.height<U.studioPlanPanel.height); eq(U.studioInspectorShield.shown,true)
 U:StudioAction(U.studioInspectorClose); eq(U.studioInspectorShield.shown,false)
 UIParent=parent
end)
test("条件摘要命中区域转交选择与精确拖入事件",function()
 setup(); U:SelectStudioRule("apl",1); U:ChangeCustomStrategy(function(r) r.strategies={{mode="use",conditions={{kind="range",value=true}}}} end)
 local chip=U.customWidgets[1].frame.studioChips[1]
 chip.scripts.OnMouseUp(chip,"LeftButton"); eq(U.customSelected,1)
 local cursor,clear=GetCursorInfo,ClearCursor
 GetCursorInfo=function() return "spell",0,"spell",205 end; ClearCursor=function() end
 chip.scripts.OnReceiveDrag(chip); eq(U.customDraft[1].spellID,205); eq(U.customDraft[2].spellID,143)
 GetCursorInfo,ClearCursor=cursor,clear
end)
test("刷新后重复布局仍清理旧页面与其他来源遮挡",function()
 setup(); U:LayoutSettings()
 U.pageFrames.profiles:Show(); U.pageFrames.customapl:Show(); U.sequenceScroll:Show()
 U:LayoutSettings()
 eq(U.pageFrames.profiles.shown,false); eq(U.pageFrames.customapl.shown,false)
 eq(U.sequenceScroll.shown,false); eq(U.customScroll.shown,true)
 U:ShowPage("profiles"); U.customScroll:Show(); U:LayoutSettings()
 eq(U.customScroll.shown,false); eq(U.sequenceScroll.shown,true)
 U:ShowPage("maintenance"); U.sequenceScroll:Show(); U:LayoutSettings()
 eq(U.sequenceScroll.shown,false); eq(U.customScroll.shown,true)
end)
test("技能库滚轮与滑块使用同一偏移且搜索归零",function()
 setup(); U.studioLibraryCatalog={}; U.studioLibraryEngine=U.engine
 for i=1,20 do U.studioLibraryCatalog[i]={spellID=i,name="技能" .. i,rank=i,icon=123} end
 U.studioLibrarySearch.text=""; U.studioLibraryOffset=0; U:RefreshStudioLibrary(false)
 U.studioLibrary.scripts.OnMouseWheel(U.studioLibrary,-1)
 eq(U.studioLibraryOffset,1); eq(U.studioLibraryWidgets[1].entry.spellID,2)
 U.studioLibraryBar.scripts.OnValueChanged(U.studioLibraryBar,12)
 eq(U.studioLibraryWidgets[1].entry.spellID,13)
 U.studioLibrarySearch.text="20"; U.studioLibrarySearch.scripts.OnTextChanged()
 eq(U.studioLibraryOffset,0); eq(U.studioLibraryWidgets[1].entry.spellID,20)
 assert(U.studioLibraryWidgets[1].id.text:find("等级 20",1,true))
 eq(U.studioLibraryNext,nil); eq(U.studioLibraryPrevious,nil)
end)
test("切换成功关闭技能库并清理拖动且无重复派发导航",function()
 setup(); U.studioLibraryOpen=true; U.studioLibraryDragging=143; U.studioLibrary:Show()
 U:ShowPage("profiles"); eq(U.studioLibraryOpen,false); eq(U.studioLibrary.shown,false)
 eq(U.studioLibraryDragging,nil); eq(U.studioNodes.overview,nil)
 U:ShowStudioPlan(); eq(U.studioPlanScroll.shown,true); eq(U.strategyPanel.shown,false)
 U:ShowPage("maintenance"); U:ShowStudioPlan()
 eq(U.studioPlanName.shown,false); eq(U.studioPlanRename.shown,false); eq(U.studioUsePlan.shown,false)
 eq(U.studioSequenceTab.shown,false); eq(U.studioPlansHeading.shown,false)
 assert(U.studioListHeading.text:find("增益与紧急",1,true))
 U:StudioAction(U.studioTab); eq(U.page,"maintenance")
end)
test("技能等级仅采用同槽位公开值且冲突未知",function()
 setup(); local book,enum,info=C_SpellBook,Enum,C_Spell.GetSpellInfo
 C_Spell.GetSpellInfo=function(id) return {name="技能 " .. id,iconID=123} end
 Enum={SpellBookSpellBank={Player=0},SpellBookItemType={Spell=1}}
 C_SpellBook={GetNumSpellBookSkillLines=function() return 1 end,
  GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0,numSpellBookItems=3} end,
  GetSpellBookItemInfo=function(i) return {itemType=1,spellID=100+i,isPassive=false,rank=i==1 and 2 or i==2 and F.secret or 4} end,
  GetSpellBookItemName=function(i) return "技能 " .. (100+i),i==3 and "等级 5" or nil end,
  IsSpellKnown=function() return true end}
 U.studioLibrarySearch.text=""; U:RefreshStudioLibrary(true)
 local ranks={}; for _,r in ipairs(U.studioLibraryCatalog) do ranks[r.spellID]=r.rank or false end
 eq(ranks[101],2); eq(ranks[102],false); eq(ranks[103],false)
 C_SpellBook=book; Enum=enum; C_Spell.GetSpellInfo=info
end)
test("选中边框在鼠标移出和普通刷新后持续高亮",function()
 setup(); U:SelectStudioRule("apl",1)
 local a,b=U.customWidgets[1].frame,U.customWidgets[2].frame
 a.scripts.OnEnter(a); a.scripts.OnLeave(a)
 eq(a.tefRowSelected,true); eq(a.backdropBorderColor[1],U.theme.colorFocus[1])
 U:RefreshStudio(); eq(a.backdropBorderColor[2],U.theme.colorFocus[2])
 U:SelectStudioRule("apl",2); eq(a.tefRowSelected,false); eq(b.tefRowSelected,true)
 b.scripts.OnLeave(b); eq(b.backdropBorderColor[1],U.theme.colorFocus[1])
 U:ShowPage("profiles"); U:WriteDraft({spell(143)}); U:SelectStudioRule("manual",1)
 a=U.sequenceRows[1].frame; a.scripts.OnLeave(a)
 eq(a.tefRowSelected,true); eq(a.backdropBorderColor[1],U.theme.colorFocus[1])
 U:AddSkillGroup("manual"); U:GroupAdd(143); U:SelectStudioRule("group",1)
 a=U.groupWidgets[1].frame; a.scripts.OnLeave(a)
 eq(a.tefRowSelected,true); eq(a.backdropBorderColor[1],U.theme.colorFocus[1]); U:CloseSkillGroup(true)
end)
test("紧凑下拉不依赖缺失箭头字形",function()
 setup(); local choices=U:CreateSegmentedControl(U.studioEditor,{{"a","持续参与推荐"},{"b","成功后消耗"}},0,0,200,function() return "a" end,function() end)
 local menu=choices.a.parent.parent.parent; local toggle=menu.parent
 U:RefreshControls(); eq(toggle.text,"持续参与推荐 v")
end)
return n
