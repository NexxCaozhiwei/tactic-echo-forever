local _,T=...
local U,S=T.UI,T.Safety
function U:StudioAnchor(object,parent,x,y,width,height)
 self:Paint(object,"ClearAllPoints"); self:Paint(object,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
 if width then self:Paint(object,"SetWidth",width) end
 if height then self:Paint(object,"SetHeight",height) end
end
function U:StudioAction(button)
 local ok,callback=self:Invoke(button,"GetScript","OnClick")
 if ok and callback then callback(button) end
end
function U:StudioMessage(text)
 if self.groupEditing then self:Paint(self.groupMessage,"SetText",text)
 elseif self.page=="profiles" then self:SequenceMessage(text) else self:CustomMessage(text) end
 self:Paint(self.studioPlanMessage,"SetText",text)
 if self.studioLibraryOpen then
  self:Paint(self.studioLibraryInfo,"SetText",self:ShortLabel(text,24)); self.studioLibrary.tefTooltipTitle="技能库提示"; self.studioLibrary.tefTooltipBody=text
 end
end
function U:SaveStudio()
 if self.groupEditing then return self:SaveSkillGroup() end
 if self.page=="profiles" then self:StudioAction(self.manualSave)
 elseif self.page=="customapl" or self.page=="maintenance" then self:StudioAction(self.customSave) end
end
function U:DuplicateStudioRow()
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false end
 if self.groupEditing and not self:CommitGroupFields() then return false end
 local rows,source=self:StudioActiveRows(); local selected=self.studioSelected
 if not selected or selected.source~=source or not rows or not rows[selected.index] then return false end
 if #rows>=(source=="group" and 8 or 16) then self:StudioMessage("已达到列表容量，未复制。"); return false end
 local copy=source=="apl" and T.APL.Custom.CleanRows({rows[selected.index]}) or T.Profiles:Clean({rows[selected.index]},1)
 if not copy or not copy[1] then return false end
 table.insert(rows,selected.index+1,copy[1])
 if source=="manual" then self:WriteDraft(rows) elseif source=="group" then self.groupDirty=true; self:RefreshSkillGroup() else self.customFormIndex=nil; self:RefreshCustomAPL() end
 self:SelectStudioRule(source,selected.index+1); self:StudioMessage("已复制到下一行草稿；保存后生效。"); return true
end
function U:SelectStudioRule(source,index)
 if self.studioSelecting then return false end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false end
 if source=="group" and not self:CommitGroupFields() then return false end
 local rows=source=="manual" and self:DraftRows() or source=="group" and self.groupDraft and self.groupDraft.steps or self.customDraft
 if not rows or not rows[index] then return false end
 self.studioSelecting=true
 if source=="manual" then
  self:OpenSequencePolicy(index)
 elseif source=="group" then
  self.groupSelected=index; self.customSelected=index; self.strategySource="groupStep"; self.customFormIndex=nil
  self:RefreshStrategyForm(); self:Paint(self.groupPanel,"Hide"); self:Paint(self.strategyPanel,"Show")
 else
  if not self:PrepareGroupPanelSwitch(false) then self.studioSelecting=false; return false end
  self.strategySource=self.page=="maintenance" and "maintenance" or "apl"
  self.customSelected=index; self.customFormIndex=nil; self:RefreshStrategyForm(); self:Paint(self.strategyPanel,"Show")
 end
 self.studioSelected={source=source,index=index}; self.studioInspectorRequested=true; self.studioPlanOpen=false
 self.studioSelecting=false; self:RefreshStudio(); self:LayoutSettings(); return true
end
function U:StudioActiveRows()
 if self.groupEditing and self.groupDraft then return self.groupDraft.steps,"group",self.groupEditing.scene end
 return self:StudioRows()
end
function U:ShowStudioPlan()
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return end
 self.settingsLayoutSignature=nil
 if self.groupEditing then self:Paint(self.strategyPanel,"Hide"); self:Paint(self.groupPanel,"Show")
 else self.studioPlanOpen=true; self:Paint(self.strategyPanel,"Hide") end
 self.studioInspectorRequested=true; self:RefreshStudio(); self:LayoutSettings()
end
function U:CreateStudioPlan()
 self.studioPlanScroll=self:Frame("ScrollFrame",self.studioInspector,"UIPanelScrollFrameTemplate")
 local panel=self:Frame("Frame",self.studioPlanScroll); self.studioPlanPanel=panel
 self:Paint(panel,"SetSize",410,744); self:Paint(self.studioPlanScroll,"SetScrollChild",panel)
 self.studioPlanTitle=self:Text(panel,16,-20,390,"GameFontNormal"); self:Paint(self.studioPlanTitle,"SetText","方案设置 · 改名／启用／使用")
 self.studioPlanNameLabel=self:CreateHintText(panel,"方案名称（最多64字节）",16,-64,390)
 self.studioPlanName=self:SequenceInput(panel,16,-92,390); self:Paint(self.studioPlanName,"SetMaxLetters",64)
 self.studioPlanRename=self:CreateActionButton(panel,"保存名称",16,-132,120,function()
  local _,source,scene=self:StudioRows(); if not source or scene=="maintenance" then return end
  local ok,raw=self:Invoke(self.studioPlanName,"GetText")
  local saved=ok and T.Profiles:SetPlanName(self.engine,source,scene,raw)
  self:StudioMessage(saved and "方案名称已保存。" or "名称无效：最多64字节，不允许控制符或竖线。")
 end)
 self.studioPlanToggle,self.studioPlanToggleLabel=self:CreateToggleRow(panel,"启用本方案",16,-184,390,function()
  local _,source,scene=self:StudioRows()
  if scene=="maintenance" then return T.Maintenance:Enabled(self.engine) end
  return source and self.engine.db.enabledPlans[source][scene]==true
 end,function(v)
  local _,source,scene=self:StudioRows()
  if scene=="maintenance" then T.Maintenance:SetEnabled(self.engine,v)
  elseif source then T.Profiles:SetPlanEnabled(self.engine,source,scene,v) end
 end)
 self.studioUsePlan=self:CreateActionButton(panel,"使用本方案",16,-232,390,function()
  local _,source,scene=self:StudioRows(); if not source or scene=="maintenance" then return end
  local ok,reason=T.Profiles:UsePlan(self.engine,source,scene)
  self:StudioMessage(ok and "已切换运行方案并停止派发；关闭设置后开启。" or ("未切换：" .. (reason or "UNKNOWN")))
 end)
 self.studioLoopPanel=self:Frame("Frame",panel); self:StudioAnchor(self.studioLoopPanel,panel,16,-296,390,250)
 self:CreateSelectRow(self.studioLoopPanel,"循环方式",{{"none","不循环"},{"normal","普通循环"},{"target","切目标重置"},{"combat","脱战重置"}},0,0,390,
  function() return self.engine.db.loopMode end,function(v) T.Runtime:SetLoopMode(v) end)
 self:CreateHintText(self.studioLoopPanel,"切换循环方式会停止并重置；手动停止保留原进度。",0,-88,390)
 self:CreateActionButton(self.studioLoopPanel,"重置并停止",0,-144,188,function() T.Runtime:Reset() end)
 self.studioPlanMessage=self:Text(panel,16,-576,390)
 self:Paint(self:Text(panel,16,-640,390,"GameFontHighlightSmall"),"SetText","编辑方案与正在使用的方案分别显示。保存内容会停止旧派发；切换编辑标签不会自行运行。")
end
function U:CreateStudioToolbar(parent,source)
 local toolbar=self:Frame("Frame",parent); self:StudioAnchor(toolbar,parent,12,-44,580,76)
 local function receive(index)
  if source=="manual" then return self:ReceiveSequenceSpell(index) elseif source=="group" then return self:GroupReceive(index) else return self:ReceiveCustomSpell(index) end
 end
 self:CreateHintText(toolbar,"精确技能ID",132,0,120)
 local box=self:SequenceInput(toolbar,132,-24,120)
 local drop=self:CreateActionButton(toolbar,"拖入技能",0,-24,120,function() receive() end)
 self:Paint(drop,"SetScript","OnReceiveDrag",function() self:Guard(receive) end)
 self:CreateActionButton(toolbar,"ID新增",264,-24,104,function()
  local ok,raw=self:Invoke(box,"GetText"); local value=ok and S.Public(raw,"string"); local id=value and value:match("^%s*(%d+)%s*$") and tonumber(value)
  local added
  if source=="manual" then added=self:AddSequenceSpell(id) elseif source=="group" then added=self:GroupAdd(id) else added=self:AddCustomSpell(id) end
  if added then self:Paint(box,"SetText",""); self:Paint(box,"ClearFocus") end
 end)
 if source~="group" then
  toolbar.group=self:CreateActionButton(toolbar,"新建技能组",380,-24,132,function() self:AddSkillGroup(source) end)
 else
  self:CreateActionButton(toolbar,"组属性",380,-24,132,function() self:ShowStudioPlan() end)
 end
 return toolbar
end
function U:CreateStudio()
 self.studio=true; self.studioIntegrated=true; self.studioRefreshing=false; self.studioLayoutBusy=false; self.studioSelected=nil; self.studioPlanOpen=false
 self.studioInspectorRequested=false; self.studioLibraryOpen=false; self.studioWorkspaceOpen=false
 self.studioTraceLive=false; self.studioProbe=nil; self.studioLastProbeTime=nil
 self.studioEditor=self:Frame("Frame",self.settings)
 self:Paint(self.pageHeading,"Hide")
 self.studioActivity=self:CreateStudioPanel(self.settings); self.studioWorkspace=self:CreateStudioPanel(self.settings)
 self.studioInspector=self:CreateStudioPanel(self.settings); self:Paint(self.studioInspector,"EnableMouse",true)
 self.studioBottom=self:CreateStudioPanel(self.settings)
 self.studioStatus=self:Text(self.settings,12,-800,1200,"GameFontHighlightSmall"); self:Paint(self.studioStatus,"SetWordWrap",false)
 self.studioContext=self:Text(self.settings,348,-20,400); self:Paint(self.studioContext,"SetWordWrap",false)
 self.studioRun=self:CreateActionButton(self.settings,"开启意图",900,-16,112,function() T.Runtime:ToggleIntent("USER_TOGGLE_DISPATCH") end)
 self:BindControlTooltip(self.studioRun,"派发意图","设置期间继续阻断输入；开启意图不表示正在派发。")
 self.studioSave=self:CreateActionButton(self.settings,"保存方案",1020,-16,112,function() self:SaveStudio() end)
 self.studioTab=self:CreateActionButton(self.settings,"优先级.apl",280,-68,180,function() if self.page~="maintenance" then self:ShowPage("customapl") end end)
 self.studioSequenceTab=self:CreateActionButton(self.settings,"列表循环.sequence",468,-68,180,function() self:ShowPage("profiles") end)
 self.studioGroupTab=self:CreateActionButton(self.settings,"技能组.group",656,-68,180,function() if self.groupEditing then self:ShowStudioPlan() end end)
 self.studioPlanButton=self:CreateActionButton(self.studioEditor,"方案设置",460,0,120,function() self:ShowStudioPlan() end)
 self.studioDuplicateButton=self:CreateActionButton(self.studioEditor,"复制条目",336,0,112,function() self:DuplicateStudioRow() end)
 self.studioListHeading=self:Text(self.studioEditor,12,-8,440)
 self.studioEmpty=self:Text(self.studioEditor,24,-144,480)
 self:Paint(self.studioEmpty,"SetText","尚未添加技能。\n从技能库拖入，或输入精确技能ID新增。")
 self.studioToolbars={manual=self:CreateStudioToolbar(self.studioEditor,"manual"),apl=self:CreateStudioToolbar(self.studioEditor,"apl"),group=self:CreateStudioToolbar(self.studioEditor,"group")}
 for _,button in pairs(self.navigation) do self:Paint(button,"Hide") end
 self.studioActivities={}
 for i,entry in ipairs({{"工作区","workspace"},{"技能库","library"},{"设置","overview"},{"HUD","hud"},{"TEK","tek"},{"诊断","diagnostics"}}) do
  local key=entry[2]
  self.studioActivities[key]=self:CreateActionButton(self.studioActivity,entry[1],4,-12-(i-1)*56,56,function()
   if key=="workspace" then
    if not self:StudioRows() then self:ShowPage(self.studioLastEditorPage or "customapl") end
    self.studioWorkspaceOpen=(self.studioWidth or 0)<1400 and not self.studioWorkspaceOpen; self:LayoutSettings()
   elseif key=="library" then
    local opening=not self.studioLibraryOpen
    if opening and not self:StudioRows() then self:ShowPage(self.studioLastEditorPage or "customapl") end
    self.studioLibraryOpen=opening; if opening then self:RefreshStudioLibrary(false) else self:CloseStudioLibrary() end; self:LayoutSettings()
   else self:ShowPage(key) end
  end)
  self:Paint(self.studioActivities[key],"SetHeight",44); self:ApplyControlFont(self.studioActivities[key],true,12)
 end
 -- 保留原导航字段供现有命令和回归定位，但不创建第二套页面。
 self.studioActivities.customapl=self.studioActivities.workspace
 self.studioNodes={}; self.studioPlans={}
 self:Paint(self:Text(self.studioWorkspace,12,-16,176,"GameFontNormal"),"SetText","工作区")
 for i,entry in ipairs({{"优先级推荐","customapl"},{"列表循环","profiles"},{"增益与紧急","maintenance"}}) do
  local key=entry[2]; self.studioNodes[key]=self:CreateActionButton(self.studioWorkspace,entry[1],8,-52-(i-1)*40,184,function() self:ShowPage(key) end)
 end
 self.studioPlansHeading=self:Text(self.studioWorkspace,12,-232,176,"GameFontNormal"); self:Paint(self.studioPlansHeading,"SetText","方案 · 编辑对象")
 for i,key in ipairs({"single","multi","third"}) do
  self.studioPlans[key]=self:CreateActionButton(self.studioWorkspace,"方案",8,-268-(i-1)*44,184,function()
   if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return end
   if self.groupEditing and not self:CloseSkillGroup(false,function() self:StudioAction(self.studioPlans[key]) end) then return end
   if self.page=="profiles" then self.editScene=key; self:ShowPage("profiles")
   else self.customScene=key; self:ShowPage("customapl") end
  end)
  self:Paint(self.studioPlans[key],"SetHeight",40); self:ApplyControlFont(self.studioPlans[key],true,12)
 end
 self.studioPlansHint=self:CreateHintText(self.studioWorkspace,"切换仅编辑草稿；使用本方案才切换运行来源。",12,-416,176)
 self.studioWorkspacePlanButton=self:CreateActionButton(self.studioWorkspace,"方案设置",8,-476,184,function() self:ShowStudioPlan() end)
 self.studioInspectTitle=self:Text(self.studioInspector,16,-16,390,"GameFontNormal")
 self.studioInspectBody=self:Text(self.studioInspector,16,-60,390)
 self:Paint(self.studioInspectTitle,"SetText","INSPECTOR · 规则详情")
 self:Paint(self.studioInspectBody,"SetText","点击技能行，在此编辑同一条草稿。\n条件未知不会被视为可用。")
 self.studioInspectOpen=self:CreateActionButton(self.studioInspector,"方案设置",16,-160,200,function() self:ShowStudioPlan() end)
 self:CreateStudioPlan()
 self.studioInspectorShield=self:Frame("Frame",self.settings); self:Paint(self.studioInspectorShield,"EnableMouse",true); self:Paint(self.studioInspectorShield,"Hide")
 self.studioInspectorClose=self:CreateActionButton(self.studioInspector,"收起详情",16,-700,120,function()
  if not self:CommitCustomNumbers() then return end
  self.studioSelected=nil; self.studioInspectorRequested=false; self.studioPlanOpen=false; self:Paint(self.strategyPanel,"Hide"); self:Paint(self.groupPanel,"Hide"); self:LayoutSettings()
 end)
 self:Paint(self.strategyPanel,"SetParent",self.studioInspector); self:Paint(self.strategyPanel,"SetFrameStrata","MEDIUM")
 self:Paint(self.groupPanel,"SetParent",self.studioInspector); self:Paint(self.groupPanel,"SetFrameStrata","MEDIUM")
 self:Paint(self.groupListBox,"Hide"); self:Paint(self.groupIDLabel,"Hide")
 self:CreateHintText(self.groupPanel,"在左侧编辑组内步骤；选择技能行后在此编辑策略。\n返回父列表会先暂存，保存方案才持久化。",16,-176,390)
 self:Paint(self.groupScroll,"SetParent",self.studioEditor)
 for _,control in ipairs({self.groupDrop,self.groupID,self.groupAddButton}) do self:Paint(control,"Hide") end
 self.studioGroupFooter=self:Frame("Frame",self.settings); self:Paint(self.studioGroupFooter,"SetSize",580,88)
 local controls={self.groupUndoButton,self.groupClearButton,self.groupExitButton,self.groupSaveButton}
 for i,control in ipairs(controls) do self:Paint(control,"SetParent",self.studioGroupFooter); self:StudioAnchor(control,self.studioGroupFooter,(i-1)*144,-52,132,32) end
 self:Paint(self.groupMessage,"SetParent",self.studioGroupFooter); self:StudioAnchor(self.groupMessage,self.studioGroupFooter,0,-4,580)
 self:Paint(self.groupExitButton,"SetText","返回父列表")
 self:Paint(self.groupExitButton,"SetScript","OnClick",function() self:Guard(function()
  if not self:SaveSkillGroup(true) then return end
  self:CloseSkillGroup(true); self:RefreshStudio()
 end) end)
 for _,scroll in ipairs({self.sequenceScroll,self.customScroll}) do self:Paint(scroll,"SetParent",self.studioEditor) end
 for i,w in ipairs(self.sequenceRows) do self:BindStudioDrag(w,i,"manual") end
 for i,w in ipairs(self.customWidgets) do self:BindStudioDrag(w,i,"apl") end
 for i,w in ipairs(self.groupWidgets) do self:BindStudioDrag(w,i,"group") end
 self:CreateStudioTools(); self.settingsLayoutSignature=nil
end
function U:RefreshStudio()
 if not self.studio or self.studioRefreshing then return end
 self.studioRefreshing=true
 local e=self.engine; local rows,source,scene=self:StudioActiveRows(); local view=T.Runtime:GetViewState()
 self:MaybeStudioLiveProbe()
 local parentSource=self.page=="profiles" and "manual" or "apl"
 if source then self.studioLastEditorPage=self.page end
 local maintenance=self.page=="maintenance"
 local name=maintenance and "增益与紧急" or (scene and T.Profiles:PlanName(scene,e,parentSource) or (self.pageTitles[self.page] or "设置"))
 self:Paint(self.studioPlansHeading,maintenance and "Hide" or "Show"); self:Paint(self.studioPlansHint,maintenance and "Hide" or "Show")
 for _,button in ipairs({self.studioPlanButton,self.studioWorkspacePlanButton,self.studioInspectOpen}) do self:Paint(button,"SetText",maintenance and "维护设置" or "方案设置") end
 local aplScene=self.customScene or e.db.selectedPlans.apl; local manualScene=self.editScene or e.db.selectedPlans.manual
 for _,entry in ipairs({{self.studioTab,"apl",aplScene,".apl"},{self.studioSequenceTab,"manual",manualScene,".sequence"}}) do
  local dirty=self:StudioDirty(entry[2],entry[3],self:StudioPlanDraft(entry[2],entry[3]))
  self:Paint(entry[1],"SetText",self:ShortLabel(T.Profiles:PlanName(entry[3],e,entry[2]),8) .. entry[4] .. (dirty and " *" or ""))
  entry[1].tefControlSelected=entry[2]==parentSource and source~=nil; self:SetControlEnabled(entry[1],true)
 end
 self:Paint(self.studioTab,source and "Show" or "Hide")
 self:Paint(self.studioSequenceTab,source and not maintenance and "Show" or "Hide")
 if maintenance then self:Paint(self.studioTab,"SetText","增益与紧急.apl" .. (self:StudioDirty("apl","maintenance",rows) and " *" or "")) end
 self:Paint(self.studioGroupTab,self.groupEditing and "Show" or "Hide")
 if self.groupDraft then self:Paint(self.studioGroupTab,"SetText",self:ShortLabel(self.groupDraft.name,6) .. ".group" .. (self.groupDirty and " *" or "")) end
 self:Paint(self.studioContext,"SetText",self:ClassLabel() .. " / " .. name)
 self:Paint(self.studioRun,"SetText",view.intent and "停止意图" or "开启意图")
 self:SetControlEnabled(self.studioSave,source~=nil,"当前页面没有可保存的列表。")
 self:SetControlEnabled(self.studioDuplicateButton,self.studioSelected~=nil and self.studioSelected.source==source and rows and rows[self.studioSelected.index]~=nil or false,"先选择当前列表中的条目；复制仍受列表容量限制。")
 self:Paint(self.studioStatus,"SetText","TEF " .. T.Version .. " · TEAP输出：" .. (T.Transport.enabled and "开启" or "关闭") .. " · TEK连接：未确认 · 派发：" .. view.label .. " · 意图：" .. (view.intent and "开启" or "关闭") .. " · 设置期间输入阻断")
 if self.studioWidth and self.studioWidth<1000 then self:Paint(self.studioStatus,"SetText","TEF " .. T.Version .. " · 派发：" .. view.label .. " · 意图：" .. (view.intent and "开启" or "关闭") .. " · 设置期间输入阻断") end
 for key,button in pairs(self.studioNodes) do button.tefControlSelected=key==self.page; self:SetControlEnabled(button,true) end
 for key,button in pairs(self.studioActivities) do if key~="customapl" then
  button.tefControlSelected=(key=="workspace" and source~=nil) or (key=="library" and self.studioLibraryOpen) or key==self.page
  self:SetControlEnabled(button,true)
 end end
 for key,button in pairs(self.studioPlans) do
  self:Paint(button,self.page=="maintenance" and "Hide" or "Show")
  local planSource=self.page=="profiles" and "manual" or "apl"
  local dirty=self:StudioDirty(planSource,key,self:StudioPlanDraft(planSource,key)); local using=T.Recommendation:BaseSource(e)==planSource and e.scene==key
  self:Paint(button,"SetText",self:ShortLabel(T.Profiles:PlanName(key,e,planSource),9) .. "\n" .. (key==scene and "编辑 · " or "") .. (using and "使用 · " or "") .. (e.db.enabledPlans[planSource][key] and "已启用" or "未启用") .. (dirty and " *" or ""))
  button.tefControlSelected=key==scene; self:SetControlEnabled(button,true)
  button.tefTooltipTitle=T.Profiles:PlanName(key,e,planSource); button.tefTooltipBody=e.db.enabledPlans[planSource][key] and "已启用；切换编辑保留会话草稿。" or "未启用；切换编辑保留会话草稿。"
 end
 self:Paint(self.studioListHeading,"SetText",self.groupDraft and (self.groupDraft.name .. " · " .. #self.groupDraft.steps .. "/8步") or (name .. " · " .. (rows and #rows or 0) .. "/16项"))
 self.studioCurrentProbe=self:StudioProbeCurrent()
 local widgets=source=="group" and self.groupWidgets or source=="manual" and self.sequenceRows or self.customWidgets
 for i,w in ipairs(widgets or {}) do self:RefreshStudioRow(w,rows and rows[i],i,source) end
 self:Paint(self.studioEmpty,rows and #rows==0 and "Show" or "Hide")
 self:Paint(self.studioToolbars.apl.group,self.page=="maintenance" and "Hide" or "Show")
 local _,planSource,planScene=self:StudioRows()
 if planSource and not self.groupEditing then
  self:Paint(self.studioPlanToggleLabel,"SetText",planScene=="maintenance" and "启用增益维护" or "启用本方案")
  self:Paint(self.studioPlanTitle,"SetText",planScene=="maintenance" and "增益维护设置 · 启用维护" or "方案设置 · 改名／启用／使用")
  local loaded=planSource .. ":" .. planScene
  if self.studioPlanLoaded~=loaded or self.studioPlanEngine~=e then self.studioPlanEngine=e; self.studioPlanLoaded=loaded; self:SetInputValue(self.studioPlanName,T.Profiles:PlanName(planScene,e,planSource)) end
  self:SetControlEnabled(self.studioUsePlan,planScene~="maintenance" and e.db.enabledPlans[planSource][planScene]==true,"请先启用方案；维护列表不切换战斗来源。")
  self:Paint(self.studioLoopPanel,planSource=="manual" and "Show" or "Hide")
  for _,control in ipairs({self.studioPlanNameLabel,self.studioPlanName,self.studioPlanRename,self.studioUsePlan}) do self:Paint(control,planScene=="maintenance" and "Hide" or "Show") end
 end
 local dragging=self.studioDragging
 if dragging or self.studioLibraryDragging then local _,frame=self:StudioDropTarget(dragging and dragging.source or source); if frame then self:ShowStudioInsertion(frame) else self:HideStudioInsertion() end end
 self:RefreshStudioBottom()
 self.studioRefreshing=false
 self:LayoutSettings()
end
function U:LayoutStudioSettings(width,height)
 if self.studioLayoutBusy then return end
 self.studioLayoutBusy=true
 local scale=math.min(1,(width-32)/680); local w=math.min(1560,(width-32)/scale); local h=math.min(920,(height-32)/scale)
 local workspace=w>=1400 and 200 or 0
 local dock=w>=64+workspace+620+448+48
 local left=80+workspace; local editorWidth=w-left-16-(dock and 460 or 0)
 local bottom=(h>=760 or self.studioBottomExpanded) and math.max(64,math.min(164,h-504)) or 64
 local bodyHeight=h-64-28; local editorHeight=bodyHeight-44
 local listPage=self.page=="profiles" or self.page=="customapl" or self.page=="maintenance"
 local rows,source=self:StudioActiveRows()
 local selected=self.studioSelected and rows and self.studioSelected.source==source and rows[self.studioSelected.index]
 local inspect=listPage and (dock or self.studioInspectorRequested)
 local signature=table.concat({w,h,tostring(self.page),tostring(source),tostring(dock),tostring(inspect),tostring(self.studioPlanOpen),tostring(self.studioLibraryOpen),tostring(self.studioWorkspaceOpen),tostring(selected~=nil),tostring(bottom)},":")
 self.studioWidth=w; self.settingsHeight=h; self.settingsFitScale=scale; self.editorOverlay=not dock
 self.studioEditorWidth=editorWidth; self.studioListHeight=math.max(32,editorHeight-120-bottom-96)
 -- 刷新可能重新显示旧控件，必须每次同步可见性，不能按几何签名跳过。
 self.settingsLayoutSignature=signature
 self:Paint(self.settings,"SetScale",scale); self:Paint(self.settings,"SetSize",w,h)
 self:StudioAnchor(self.studioActivity,self.settings,0,-64,64,bodyHeight)
 self:StudioAnchor(self.studioWorkspace,self.settings,64,-64,200,bodyHeight)
 self:Paint(self.studioWorkspace,(workspace>0 or self.studioWorkspaceOpen) and "Show" or "Hide")
 self:Paint(self.studioWorkspacePlanButton,listPage and bodyHeight>=520 and "Show" or "Hide")
 self:Paint(self.studioWorkspace,"SetFrameLevel",self.studioWorkspaceOpen and 30 or 2); self:Paint(self.studioWorkspace,"EnableMouse",true)
 self:StudioAnchor(self.studioEditor,self.settings,left,-108,editorWidth,editorHeight)
 self:Paint(self.studioEditor,listPage and "Show" or "Hide")
 self:StudioAnchor(self.studioTab,self.settings,left,-68,180,32); self:StudioAnchor(self.studioSequenceTab,self.settings,left+188,-68,204,32)
 self:StudioAnchor(self.studioGroupTab,self.settings,left+400,-68,math.max(160,editorWidth-400),32)
 self:StudioAnchor(self.studioPlanButton,self.studioEditor,editorWidth-136,0,120,32)
 self:StudioAnchor(self.studioDuplicateButton,self.studioEditor,editorWidth-260,0,112,32)
 self:Paint(self.studioListHeading,"SetWidth",editorWidth-292)
 for key,panel in pairs(self.pageFrames) do
  self:StudioAnchor(panel,self.settings,left,-116,editorWidth,h-160)
  self:Paint(panel,(not listPage and self.pageFrames[self.page]==panel) and "Show" or "Hide")
 end
 for _,scroll in pairs(self.pageScrolls) do self:Paint(scroll,"SetHeight",h-160) end
 local scrolls={manual=self.sequenceScroll,apl=self.customScroll,group=self.groupScroll}
 for key,scroll in pairs(scrolls) do
  self:StudioAnchor(scroll,self.studioEditor,12,-120,editorWidth-44,self.studioListHeight)
  self:Paint(scroll,listPage and key==source and "Show" or "Hide")
 end
 for key,toolbar in pairs(self.studioToolbars) do self:Paint(toolbar,listPage and key==source and "Show" or "Hide") end
 for _,entry in ipairs({{self.sequenceRows,self.sequenceChild},{self.customWidgets,self.customChild},{self.groupWidgets,self.groupChild}}) do
  self:Paint(entry[2],"SetWidth",editorWidth-48)
  for _,row in ipairs(entry[1]) do self:LayoutStudioRow(row,editorWidth-48) end
 end
 for _,footer in pairs(self.pageFooters) do self:StudioAnchor(footer,self.settings,left,-h+bottom+116,editorWidth-16,88); self:Paint(footer,"Hide") end
 self:StudioAnchor(self.manualSave,self.pageFooters[self.pages.profiles],editorWidth-160,-52,144,32)
 self:StudioAnchor(self.customSave,self.pageFooters[self.pages.customapl],editorWidth-160,-52,144,32)
 self:Paint(self.editorMessage,"SetWidth",editorWidth-16); self:Paint(self.customMessage,"SetWidth",editorWidth-16)
 local footer=source=="manual" and self.pageFooters[self.pages.profiles] or source=="apl" and self.pageFooters[self.pages.customapl] or self.studioGroupFooter
 self:StudioAnchor(self.studioGroupFooter,self.settings,left,-h+bottom+116,580,88)
 self:Paint(self.studioGroupFooter,listPage and source=="group" and "Show" or "Hide")
 if listPage and footer then self:Paint(footer,"Show") end
 self:StudioAnchor(self.studioBottom,self.settings,left,-h+bottom+28,editorWidth,bottom)
 self:Paint(self.studioBottom,listPage and "Show" or "Hide"); self:LayoutStudioBottom(editorWidth,bottom)
 self:StudioAnchor(self.studioInspector,self.settings,w-464,-64,448,bodyHeight)
 self:Paint(self.studioInspector,inspect and "Show" or "Hide"); self:Paint(self.studioInspector,"SetFrameLevel",dock and 4 or 40)
 self:StudioAnchor(self.studioInspectorShield,self.settings,left,-64,w-left-16,bodyHeight)
 self:Paint(self.studioInspectorShield,"SetFrameLevel",39); self:Paint(self.studioInspectorShield,inspect and not dock and "Show" or "Hide")
 self:Paint(self.studioInspectorClose,"ClearAllPoints"); self:Paint(self.studioInspectorClose,"SetPoint","BOTTOMLEFT",self.studioInspector,"BOTTOMLEFT",16,12)
 self:Paint(self.studioInspectorClose,dock and "Hide" or "Show")
 for _,panel in ipairs({self.strategyPanel,self.groupPanel}) do self:StudioAnchor(panel,self.studioInspector,0,0,448,bodyHeight-(dock and 0 or 48)) end
 self:StudioAnchor(self.studioPlanScroll,self.studioInspector,0,0,410,bodyHeight-(dock and 0 or 48))
 self:StudioAnchor(self.studioPlanPanel,self.studioPlanScroll,0,0,410,744)
 self:Paint(self.studioPlanScroll,listPage and self.studioPlanOpen and not self.groupEditing and "Show" or "Hide")
 self:Paint(self.strategyScroll,"SetHeight",math.max(80,bodyHeight-(dock and 232 or 280)))
 self:Paint(self.studioPlanPanel,listPage and self.studioPlanOpen and not self.groupEditing and "Show" or "Hide")
 if not listPage or self.studioPlanOpen then self:Paint(self.strategyPanel,"Hide") end
 if not self.groupEditing then self:Paint(self.groupPanel,"Hide") end
 self:Paint(self.studioInspectTitle,(selected or self.studioPlanOpen or self.groupEditing) and "Hide" or "Show")
 self:Paint(self.studioInspectBody,(selected or self.studioPlanOpen or self.groupEditing) and "Hide" or "Show")
 self:Paint(self.studioInspectOpen,(selected or self.studioPlanOpen or self.groupEditing) and "Hide" or "Show")
 self:StudioAnchor(self.studioStatus,self.settings,12,-h+20,w-24)
 self:StudioAnchor(self.studioRun,self.settings,w-340,-16,112,32); self:StudioAnchor(self.studioSave,self.settings,w-220,-16,112,32)
 self:Paint(self.studioClose,"ClearAllPoints"); self:Paint(self.studioClose,"SetPoint","TOPRIGHT",self.settings,"TOPRIGHT",-16,-16)
 self:Paint(self.studioContext,w>=1200 and "Show" or "Hide"); self:Paint(self.studioContext,"SetWidth",w-720)
 self:LayoutStudioLibrary(left,h)
 self:Call(self.confirmationBody,"SetScale",scale)
 self.studioLayoutBusy=false
end
function U:LayoutStudioRow(w,width)
 self:Paint(w.frame,"SetWidth",width)
 self:StudioAnchor(w.policy,w.frame,width-272,-8,88,28)
 self:StudioAnchor(w.up,w.frame,width-176,-8,32,28); self:StudioAnchor(w.down,w.frame,width-136,-8,32,28)
 self:StudioAnchor(w.delete,w.frame,width-96,-8,88,28)
 if w.usage then self:StudioAnchor(w.usage,w.frame,width-212,-44,204,28) end
 self:Paint(w.name,"SetWidth",math.max(120,width-348))
end
