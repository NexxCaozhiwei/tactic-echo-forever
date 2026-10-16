local _,TEF=...
local U,S=TEF.UI,TEF.Safety
-- Independent TEUI-style components. Presentation holds no input authority.
U.controls={}
U.theme={fontBody=14,fontHint=12,fontSection=16,fontPage=18,fontTitle=20,controlHeight=32,spaceInline=8,spaceSection=24,
 panel={.086,.102,.133,1},border={.204,.251,.322,1},
 colorText={.94,.96,1,1},colorHint={.70,.76,.84,1},colorBorder={.34,.44,.58,1},colorFocus={.35,.85,1,1}}
U.controlHeight=U.theme.controlHeight
U.theme.statusColors={READY={.35,.82,.55,1},UNKNOWN={.96,.76,.36,1},BLOCKED={.94,.40,.42,1},DISABLED={.70,.76,.84,1}}
U.controlFontSize=U.theme.fontBody
function U:ApplyControlFont(control,isButton,size)
    local target=control
    if isButton then local ok,font=self:Invoke(control,"GetFontString"); if not ok or not font then return end; target=font end
    local ok,path,_,flags=self:Invoke(GameFontHighlightSmall,"GetFont")
    path=ok and S.Public(path,"string") or S.Public(STANDARD_TEXT_FONT,"string")
    flags=S.Public(flags,"string") or ""
    if path then self:Paint(target,"SetFont",path,size or self.controlFontSize,flags) end
end
function U:StyleText(text,template)
 local sizes={GameFontNormalLarge=self.theme.fontPage,GameFontNormal=self.theme.fontSection,GameFontHighlightSmall=self.theme.fontHint}
 self:ApplyControlFont(text,false,sizes[template] or self.theme.fontBody)
 self:Call(text,"SetTextColor",unpack(self.theme.colorText)); self:Call(text,"SetSpacing",math.ceil((sizes[template] or self.theme.fontBody)*.4))
end
function U:HideControlTooltip(owner)
 if not self.tooltipOwner or (owner and self.tooltipOwner~=owner) then return end
 local current=self.tooltipOwner; self.tooltipOwner=nil
 local ok,raw=self:Invoke(GameTooltip,"GetOwner")
 local owner=ok and (S.Public(raw,"table") or S.Public(raw,"userdata"))
 if owner and owner==current then self:Call(GameTooltip,"Hide") end
end
function U:BindControlTooltip(control,title,body)
 control.tefTooltipTitle=title; control.tefTooltipBody=body
 self:Paint(control,"SetScript","OnEnter",function() self:ShowControlTooltip(control) end)
 self:Paint(control,"SetScript","OnLeave",function() self:HideControlTooltip(control) end)
 self:Paint(control,"SetScript","OnHide",function() self:HideControlTooltip(control) end)
end
function U:SetInputValue(box,value)
 local ok,raw=self:Invoke(box,"HasFocus")
 if not ok or S.Public(raw,"boolean")~=true then self:Paint(box,"SetText",value); box.tefCommitted=value end
end
function U:StyleInput(box,label)
 box.tefTooltipTitle=label or "输入数值"; box.tefTooltipBody="按Enter提交；Esc恢复进入编辑前的值。无效输入保留，修正后再保存。"
 self:Paint(box,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
 self:Paint(box,"SetBackdropColor",.035,.05,.08,1); self:Paint(box,"SetBackdropBorderColor",unpack(self.theme.colorBorder))
 self:Paint(box,"SetTextInsets",8,8,0,0)
 self:BindControlTooltip(box,box.tefTooltipTitle,box.tefTooltipBody)
 self:Paint(box,"SetScript","OnEditFocusGained",function()
  local ok,text=self:Invoke(box,"GetText"); box.tefBeforeEdit=ok and S.Public(text,"string")
  self:Call(box,"SetBackdropBorderColor",unpack(self.theme.colorFocus))
 end)
 self:Paint(box,"SetScript","OnEditFocusLost",function() self:Call(box,"SetBackdropBorderColor",unpack(self.theme.colorBorder)) end)
 self:Paint(box,"SetScript","OnEscapePressed",function()
  box.tefCancelling=true; if box.tefBeforeEdit then self:Paint(box,"SetText",box.tefBeforeEdit) end
  self:Paint(box,"ClearFocus"); box.tefCancelling=false
  self:Call(box,"SetBackdropBorderColor",unpack(self.theme.colorBorder))
 end)
end
function U:BindInputCommit(box,submit)
 self:Paint(box,"SetScript","OnEnterPressed",function()
  local result; local ok=self:Guard(function() result=submit(box) end)
  if ok and result~=false then box.tefSubmitting=true; self:Paint(box,"ClearFocus"); box.tefSubmitting=false end
  self:Call(box,"SetBackdropBorderColor",unpack(self.theme.colorBorder))
 end)
 self:Paint(box,"SetScript","OnEditFocusLost",function()
  self:Call(box,"SetBackdropBorderColor",unpack(self.theme.colorBorder))
  if not box.tefSubmitting and not box.tefCancelling then self:Guard(submit,box) end
 end)
end
function U:DeleteDraft(source,index,confirmed)
 if source=="manual" and not self:CommitSequenceCounts() then return false end
 if not self:CommitCustomNumbers() then return false end
 local rows=source=="manual" and self:DraftRows() or source=="group" and self.groupDraft and self.groupDraft.steps or self.customDraft
 local row=rows and rows[index]; if not row then return false end
 if row.group and not confirmed then
  self:ConfirmAction("确认删除技能组“" .. row.group.name .. "”及其全部步骤？保存后生效，可撤销最近一次删除。",function() self:DeleteDraft(source,index,true) end,"删除技能组")
  return false
 end
 if source=="group" and not self:CommitGroupFields() then return false end
 table.remove(rows,index)
 self.studioSelected=nil; self:Paint(self.strategyPanel,"Hide")
 self.strategyInputs={}; self.sequencePolicyRow=nil; self.customFormIndex=nil
 if source=="group" then self.strategySource=nil; self:Paint(self.groupPanel,"Show") end
 self.undoDelete={source=source,index=index,row=row,engine=self.engine,scene=source=="manual" and self.editScene or self.customLoadedScene,group=self.groupDraft}
 if source=="manual" then self.sequencePolicyRow=nil; self:Paint(self.strategyPanel,"Hide"); self:WriteDraft(rows); self:SequenceMessage("已删除草稿条目，可撤销；保存后生效。")
 elseif source=="group" then self.groupDirty=true; self:RefreshSkillGroup()
 else self.customSelected=math.min(index,math.max(1,#rows)); self.customFormIndex=nil; self:RefreshCustomAPL(); self:CustomMessage("已删除草稿条目，可撤销；保存后生效。") end
 return true
end
function U:RefreshUndoControls()
 for source,button in pairs({manual=self.manualUndoButton,apl=self.customUndoButton,group=self.groupUndoButton}) do
  local undo=self.undoDelete
  local valid=undo and undo.engine==self.engine and undo.source==source
  local scene=source=="manual" and self.editScene or self.customLoadedScene
  if valid then valid=source=="group" and undo.group==self.groupDraft or source~="group" and undo.scene==scene end
  self:SetControlEnabled(button,valid==true,"当前编辑对象没有可撤销的删除；仅支持撤销最近一次删除。")
 end
end
function U:UndoDelete(source)
 if source=="group" and not self:CommitGroupFields() then return false end
 if source=="manual" and not self:CommitSequenceCounts() then return false end
 local undo=self.undoDelete
 if not undo or undo.engine~=self.engine or undo.source~=source then return false end
 local scene=source=="manual" and self.editScene or self.customLoadedScene
 if source=="group" then if undo.group~=self.groupDraft then return false end elseif undo.scene~=scene then return false end
 local rows=source=="manual" and self:DraftRows() or source=="group" and self.groupDraft.steps or self.customDraft
 if not rows or #rows>=(source=="group" and 8 or 16) or not self:CommitCustomNumbers() then return false end
 table.insert(rows,math.min(undo.index,#rows+1),undo.row); self.undoDelete=nil
 self.studioSelected=nil; self:Paint(self.strategyPanel,"Hide"); self.sequencePolicyRow=nil; self.strategyInputs={}; self.customFormIndex=nil
 if source=="group" then self.strategySource=nil; self:Paint(self.groupPanel,"Show") end
 if source=="manual" then self:WriteDraft(rows); self:SequenceMessage("已撤销最近一次删除；保存后生效。")
 elseif source=="group" then self.groupDirty=true; self:RefreshSkillGroup()
 else self.customFormIndex=nil; self:RefreshCustomAPL(); self:CustomMessage("已撤销最近一次删除；保存后生效。") end
 return true
end
function U:ShortLabel(text,limit)
 local chars={}; for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars+1]=ch end
 if #chars<=limit then return text end
 local out={}; for i=1,limit do out[i]=chars[i] end; return table.concat(out) .. "…"
end
function U:Footer(parent)
 local f=self:Frame("Frame",self.settings); self:Paint(f,"SetSize",580,88)
 self:Paint(f,"SetPoint","BOTTOMRIGHT",self.settings,"BOTTOMRIGHT",-24,16)
 self.pageFooters=self.pageFooters or {}; self.pageFooters[parent]=f
 return f
end
-- 策略表单复用无名框架及文字对象；重建前解除旧回调与焦点。
function U:BeginStrategyPool()
 self.strategyPool=self.strategyPool or {}; self.strategyPoolCursor={}
 for _,list in pairs(self.strategyPool) do for _,object in ipairs(list) do
  self:HideControlTooltip(object)
  if object.tefPooledFrame then
   for _,event in ipairs({"OnClick","OnEnter","OnLeave","OnReceiveDrag","OnDragStart","OnDragStop","OnEnterPressed","OnEscapePressed","OnEditFocusLost","OnValueChanged","OnHide","OnMouseDown","OnMouseUp","OnEditFocusGained"}) do self:Call(object,"SetScript",event,nil) end
   if object.tefPooledKind=="EditBox" then self:Call(object,"ClearFocus") end
  end
  self:Call(object,"Hide")
 end end
 self.strategyPoolActive=true
end
function U:EndStrategyPool() self.strategyPoolActive=false end
function U:AcquireStrategyFrame(kind,parent,template)
 local key="frame:" .. kind .. ":" .. (template or "")
 local index=(self.strategyPoolCursor[key] or 0)+1; self.strategyPoolCursor[key]=index
 local list=self.strategyPool[key] or {}; self.strategyPool[key]=list
 local object=list[index]
 if not object then local ok,value=pcall(CreateFrame,kind,nil,parent,template); if not ok then self:Error(); return nil end; object=value; list[index]=object; object.tefPooledFrame=true; object.tefPooledKind=kind end
 local ok,raw=self:Invoke(parent,"GetFrameStrata"); local strata=ok and S.Public(raw,"string"); if strata then self:Call(object,"SetFrameStrata",strata) end
 local levelOK,rawLevel=self:Invoke(parent,"GetFrameLevel"); local level=levelOK and S.Public(rawLevel,"number"); if level then self:Call(object,"SetFrameLevel",level+1) end
 object.tefSubmitting=nil; object.tefCancelling=nil; object.tefBeforeEdit=nil; object.tefControlSelected=nil; object.tefTooltipTitle=nil; object.tefTooltipBody=nil; object.tefDisabledReason=nil; self:Call(object,"SetParent",parent); self:Call(object,"ClearAllPoints"); self:Call(object,"SetAlpha",1); self:Call(object,"Show")
 return object
end
function U:AcquireStrategyText(parent,template)
 local key="text:" .. template; local index=(self.strategyPoolCursor[key] or 0)+1; self.strategyPoolCursor[key]=index
 local list=self.strategyPool[key] or {}; self.strategyPool[key]=list
 local object=list[index]
 if not object then local ok,value=self:Invoke(parent,"CreateFontString",nil,"OVERLAY",template); if not ok then self:Error(); return nil end; object=value; list[index]=object end
 self:Call(object,"SetParent",parent); self:Call(object,"ClearAllPoints"); self:Call(object,"SetTextColor",1,1,1,1); self:Call(object,"SetWordWrap",true); self:Call(object,"Show")
 return object
end
function U:LayoutSettings()
 if not self.settings or self.fittingSettings then return end
 local widthOK,rawWidth=self:Invoke(UIParent,"GetWidth"); local heightOK,rawHeight=self:Invoke(UIParent,"GetHeight")
 local width=widthOK and S.Public(rawWidth,"number"); local height=heightOK and S.Public(rawHeight,"number")
 if not width or not height or width<=32 or height<=32 then return end
 if self.studio then if self:Combat()==false then self:LayoutStudioSettings(width,height) end; return end
 self.fittingSettings=true
 local scale=math.max(.85,math.min(1,(width-32)/820)); self.settingsFitScale=scale
 local panelHeight=math.min(880,(height-32)/scale); self.settingsHeight=panelHeight
 local editing=false
 for _,panel in pairs({strategy=self.strategyPanel,group=self.groupPanel}) do if panel then local ok,raw=self:Invoke(panel,"IsShown"); if ok and S.Public(raw,"boolean")==true then editing=true end end end
 local editorWidth=448
 for _,panel in pairs({strategy=self.strategyPanel,group=self.groupPanel}) do if panel then
  local ok,raw=self:Invoke(panel,"GetWidth"); local w=ok and S.Public(raw,"number")
  if w and w>0 then editorWidth=math.max(editorWidth,w) end
 end end
 local side=width>=(820+8+editorWidth)*scale+32; self.editorOverlay=not side
 local signature=width .. ":" .. height .. ":" .. tostring(editing) .. ":" .. tostring(side)
 if self.settingsLayoutSignature==signature then self.fittingSettings=false; return end
 self.settingsLayoutSignature=signature
 self:Call(self.settings,"SetScale",scale); self:Call(self.settings,"SetHeight",panelHeight)
 self:Call(self.settings,"ClearAllPoints"); self:Call(self.settings,"SetPoint","CENTER",UIParent,"CENTER",editing and side and -(editorWidth+8)*scale/2 or 0,0)
 self:Call(self.confirmationBody,"SetScale",scale)
 for _,panel in pairs({strategy=self.strategyPanel,group=self.groupPanel}) do if panel then
  self:Call(panel,"SetHeight",panelHeight); self:Call(panel,"ClearAllPoints"); self:Call(panel,"SetPoint",side and "TOPLEFT" or "CENTER",self.settings,side and "TOPRIGHT" or "CENTER",side and 8 or 0,0)
  self:Call(panel,"SetClampedToScreen",true)
 end end
 for key,scroll in pairs(self.pageScrolls or {}) do self:Call(scroll,"SetHeight",math.max(80,panelHeight-((key=="profiles" or key=="customapl") and 232 or 144))) end
 self:Call(self.strategyScroll,"SetHeight",math.max(80,panelHeight-232))
 self:Call(self.groupScroll,"SetHeight",math.max(80,panelHeight-440))
 self:Call(self.groupListBox,"SetHeight",math.max(124,panelHeight-392))
 local available=math.max(352,panelHeight-232)
 self:ResizeSectionCard(self.customListCard,available-228-8)
 self:Call(self.customScroll,"SetHeight",math.max(64,available-272-16))
 self:Call(self.pages and self.pages.customapl,"SetHeight",available)
 self:Call(self.manualLoopPanel,"ClearAllPoints"); self:Call(self.manualLoopPanel,"SetPoint","TOPLEFT",self.pages and self.pages.profiles,"TOPLEFT",0,-available-16)
 self:Call(self.pages and self.pages.profiles,"SetHeight",available+312)
 self:ResizeSectionCard(self.sequenceListCard,available-252-8)
 self:Call(self.sequenceScroll,"SetHeight",math.max(64,available-296-16))
 self.fittingSettings=false
end
function U:CancelConfirmation()
 self.pendingConfirmation=nil
 if self.confirmationShield then self:Call(self.confirmationShield,"Hide") end
end
function U:ConfirmAction(message,callback,accept,cancel)
 if not self.confirmationShield then
  local shield=self:Frame("Frame",UIParent,"BackdropTemplate","TEF_Confirmation"); self.confirmationShield=shield
  self:Paint(shield,"SetAllPoints",UIParent); self:Paint(shield,"SetFrameStrata","FULLSCREEN_DIALOG"); self:Paint(shield,"EnableMouse",true)
  self:Paint(shield,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8"}); self:Paint(shield,"SetBackdropColor",0,0,0,.55)
  local panel=self:Frame("Frame",shield,"BackdropTemplate"); self.confirmationBody=panel
  self:Paint(panel,"SetSize",480,208); self:Paint(panel,"SetPoint","CENTER",UIParent,"CENTER",0,0); self:Backdrop(panel)
  self:Paint(self:Text(panel,24,-20,432,"GameFontNormal"),"SetText","确认操作")
  self.confirmationText=self:Text(panel,24,-56,432)
  self.confirmAccept=self:CreateActionButton(panel,"确认操作",256,-152,200,function() local action=self.pendingConfirmation; self:CancelConfirmation(); if action then action() end end)
  self.confirmCancel=self:CreateActionButton(panel,"取消",24,-152,200,function() self:CancelConfirmation() end)
  self:Paint(shield,"EnableKeyboard",true)
  self:Paint(shield,"SetScript","OnKeyDown",function(_,key)
   self:Call(shield,"SetPropagateKeyboardInput",false)
   local public=S.Public(key,"string"); if public=="ESCAPE" or public=="ENTER" then self:CancelConfirmation() end
  end)
 end
 self:HideControlTooltip(); self:Paint(self.strategyKindMenu,"Hide")
 self:Paint(self.confirmAccept,"SetText",accept or "确认操作"); self:Paint(self.confirmCancel,"SetText",cancel or "取消")
 self.confirmCancel.tefControlSelected=true; self:SetControlEnabled(self.confirmCancel,true)
 self.pendingConfirmation=callback; self:Paint(self.confirmationText,"SetText",message)
 self:Paint(self.confirmationBody,"SetScale",self.settingsFitScale or 1); self:Paint(self.confirmationShield,"Show")
end
local tooltipText={
 ["保存"]="保存当前草稿；配置保存后停止旧派发，关闭设置后重新开启。",
 ["清空"]="清空当前编辑草稿；需要确认，保存后才改变已保存配置。",
 ["删"]="删除当前草稿条目；保存后生效。",
 ["↑"]="将当前条目向前移动一位。",["↓"]="将当前条目向后移动一位。",
 ["退出"]="退出技能组编辑；未暂存的修改会提示放弃或取消。",
 ["ID替换"]="更换当前技能的精确ID，保留策略；保存后生效。",
 ["拖入替换"]="拖入新技能更换当前技能，保留策略；保存后生效。",
 ["使用本方案"]="切换运行方案并停止旧派发；请先启用该方案。",
 ["替换为已学最高等级"]="按公开法术书等级确认新技能；信息未知时不替换，不修改技能绑定。"
}
function U:ShowControlTooltip(control)
 if not GameTooltip then return end
 self.tooltipOwner=control; self:Call(GameTooltip,"SetOwner",control,"ANCHOR_RIGHT"); self:Call(GameTooltip,"ClearLines")
 self:Call(GameTooltip,"AddLine",control.tefTooltipTitle or control.tefCaption or "设置")
 local aliases={["保存方案"]="保存",["清空条件"]="清空",["清空步骤"]="清空",["退出编辑"]="退出",["删除"]="删"}
 local text=control.tefTooltipBody or tooltipText[control.tefCaption] or tooltipText[aliases[control.tefCaption]]
 if text then self:Call(GameTooltip,"AddLine",text,1,1,1,true) end
 if control.tefControlEnabled==false then self:Call(GameTooltip,"AddLine",control.tefDisabledReason or "当前不可操作，请检查方案启用状态或条目位置。",1,.78,.3,true) end
 self:Call(GameTooltip,"Show")
end
function U:AddControlSync(sync,owner)
 self.controls[#self.controls+1]=sync
 self.controlOwners=self.controlOwners or setmetatable({},{__mode="k"}); self.controlOwners[sync]=owner
end
function U:CreatePlanRename(parent,source,x,y,getter)
    self.planRenameBoxes=self.planRenameBoxes or {}
    local group=self:Frame("Frame",parent); self:Paint(group,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y); self:Paint(group,"SetSize",580,32)
    parent=group; x=0; y=0
    self:CreateHintText(parent,"方案名称",x,y-8,88)
    local box=self:SequenceInput(parent,x+96,y,280); self:Paint(box,"SetMaxLetters",64)
    self.planRenameBoxes[source]={box=box,getter=getter,frame=group}
    local function save()
        local ok,raw=self:Invoke(box,"GetText")
        local valid=ok and TEF.Profiles:SetPlanName(self.engine,source,getter(),raw)
        local text=valid and "方案名称已保存；空白恢复默认名称。" or "名称无效：最多64字节，不允许控制符或竖线。"
        if source=="manual" then self:SequenceMessage(text) else self:CustomMessage(text) end
        self:Paint(box,"ClearFocus"); self:RefreshPlanFeedback()
    end
    self:CreateActionButton(parent,"保存名称",x+392,y,188,save)
    self:Paint(box,"SetScript","OnEnterPressed",function() self:Guard(save) end)
end
function U:RefreshPlanFeedback()
    local e=self.engine; if not e then return end
    local active=TEF.Recommendation:BaseSource(e)
    for _,source in ipairs({"manual","apl"}) do
        local key=source=="manual" and self.editScene or self.customScene
        local controls=source=="manual" and self.manualPlanControls or self.customPlanControls
        for slot,button in pairs(controls or {}) do
            local using=active==source and e.scene==slot and e.db.enabledPlans[source][slot]
            local text=TEF.Profiles:PlanName(slot,e,source)
            button.tefTooltipTitle=text; button.tefTooltipBody="切换当前编辑方案；点击使用本方案才切换运行方案。"
            local letters={}; for letter in text:gmatch("[\1-\127\194-\244][\128-\191]*") do letters[#letters+1]=letter end
            if #letters>9 then local short={}; for i=1,9 do short[i]=letters[i] end; text=table.concat(short) .. "…" end
            self:Paint(button,"SetText",(using and "|cff80ffcc" or "") .. text .. (using and " · 当前|r" or ""))
        end
        local using=active==source and e.scene==key and e.db.enabledPlans[source][key]==true
        local button=source=="manual" and self.manualUseButton or self.customUseButton
        if button then button.tefControlSelected=using; self:Paint(button,"SetText",using and "正在使用" or "使用本方案"); self:SetControlEnabled(button,key and e.db.enabledPlans[source][key]==true,"方案尚未启用，请先开启启用本方案。") end
        local entry=self.planRenameBoxes and self.planRenameBoxes[source]
        if entry and (entry.loaded~=key or entry.engine~=e) then entry.loaded=key; entry.engine=e; self:Paint(entry.box,"SetText",TEF.Profiles:PlanName(key,e,source)) end
    end
end
function U:Guard(callback,...)
    local ok=pcall(callback,...)
    if not ok then
        if TEF.Runtime and TEF.Runtime.e==self.engine then TEF.Runtime:Fault("UI_CALLBACK_FAILED") end
        self:Error()
    end
    return ok
end
function U:CreateActionButton(parent,label,x,y,width,callback)
    local b=self:Frame("Button",parent,"BackdropTemplate")
    b.tefControlEnabled=true; b.tefCaption=label
    self:Paint(b,"SetSize",width or 120,self.controlHeight); self:Paint(b,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
    self:Paint(b,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    self:Paint(b,"SetBackdropColor",.07,.10,.15,1); self:Paint(b,"SetBackdropBorderColor",.21,.29,.39,1)
    self:Paint(b,"SetNormalFontObject",GameFontHighlightSmall)
    self:Paint(b,"SetText",label)
    self:ApplyControlFont(b,true)
    self:Paint(b,"SetScript","OnEnter",function() if b.tefControlEnabled then self:Call(b,"SetBackdropColor",.12,.20,.28,1) end; self:ShowControlTooltip(b) end)
    self:Paint(b,"SetScript","OnLeave",function() self:SetControlEnabled(b,b.tefControlEnabled,b.tefDisabledReason); self:HideControlTooltip(b) end)
    self:Paint(b,"SetScript","OnClick",function() if b.tefControlEnabled then self:Guard(callback); self:Refresh() end end)
    self:Paint(b,"SetScript","OnHide",function() self:HideControlTooltip(b) end)
    self:Paint(b,"SetScript","OnMouseDown",function() if b.tefControlEnabled then self:Call(b,"SetBackdropColor",.18,.28,.38,1) end end)
    self:Paint(b,"SetScript","OnMouseUp",function() self:SetControlEnabled(b,b.tefControlEnabled,b.tefDisabledReason) end)
    self:SetControlEnabled(b,true)
    return b
end
function U:SetControlEnabled(button,enabled,reason)
    button.tefControlEnabled=enabled==true; button.tefDisabledReason=reason
    self:Paint(button,enabled==true and "Enable" or "Disable")
    if enabled==true and button.tefControlSelected==true then
        self:Paint(button,"SetBackdropColor",.08,.23,.20,1)
        self:Paint(button,"SetBackdropBorderColor",.25,.85,.65,1)
    else
        self:Paint(button,"SetBackdropColor",enabled==true and .07 or .035,enabled==true and .10 or .045,enabled==true and .15 or .06,1)
        self:Paint(button,"SetBackdropBorderColor",enabled==true and .34 or .24,enabled==true and .44 or .30,enabled==true and .58 or .40,1)
    end
end
-- 紧凑列表使用两行布局，点击区域保持至少28单位高。
function U:CompactControl(control,width)
 self:Paint(control,"SetSize",width,28)
 self:ApplyControlFont(control,control.tefCaption~=nil,12)
end
function U:PaintListRow(frame,hover)
 if hover~=nil then frame.tefRowHovered=hover end
 local alternate=(frame.tefRowIndex or 1)%2==0
 local selected=frame.tefRowSelected==true
 local active=selected or frame.tefRowHovered
 self:Call(frame,"SetBackdropColor",active and .07 or alternate and .04 or .03,active and .12 or alternate and .065 or .05,active and .18 or alternate and .10 or .08,1)
 if selected then self:Call(frame,"SetBackdropBorderColor",unpack(self.theme.colorFocus))
 else self:Call(frame,"SetBackdropBorderColor",.13,.20,.28,1) end
end
function U:StyleListRow(frame,index)
 frame.tefRowIndex=index
 self:Paint(frame,"SetScript","OnEnter",function() self:PaintListRow(frame,true); self:ShowControlTooltip(frame) end)
 self:Paint(frame,"SetScript","OnLeave",function() self:PaintListRow(frame,false); self:HideControlTooltip(frame) end)
 self:PaintListRow(frame,false)
end
function U:CreateSectionCard(parent,title,x,y,width,height)
    -- Page text must be above its decoration. A child backdrop Frame has a
    -- higher frame level than the parent's FontStrings and obscures them.
    local ok,bg=self:Invoke(parent,"CreateTexture",nil,"BACKGROUND")
    if not ok then self:Error(); return end
    self:Paint(bg,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y); self:Paint(bg,"SetSize",width,height)
    self:Paint(bg,"SetColorTexture",.04,.06,.095,.92)
    bg.tefCard={parent=parent,x=x,y=y,width=width,edges={}}
    for _,edge in ipairs({{x,y,width,1},{x,y-height+1,width,1},{x,y,1,height},{x+width-1,y,1,height}}) do
        local made,line=self:Invoke(parent,"CreateTexture",nil,"BORDER")
        if made then
            self:Paint(line,"SetPoint","TOPLEFT",parent,"TOPLEFT",edge[1],edge[2])
            self:Paint(line,"SetSize",edge[3],edge[4]); self:Paint(line,"SetColorTexture",.13,.19,.27,1)
            bg.tefCard.edges[#bg.tefCard.edges+1]=line
        else self:Error() end
    end
    self:Paint(self:Text(parent,x+12,y-10,width-24,"GameFontNormal"),"SetText",title)
    return bg
end
function U:ResizeSectionCard(bg,height)
 if not bg or not bg.tefCard then return end
 local card=bg.tefCard; self:Call(bg,"SetHeight",height)
 for i,line in ipairs(card.edges) do
  if i==2 then self:Call(line,"ClearAllPoints"); self:Call(line,"SetPoint","TOPLEFT",card.parent,"TOPLEFT",card.x,card.y-height+1)
  elseif i>2 then self:Call(line,"SetHeight",height) end
 end
end
function U:ClassLabel()
 local names={MAGE="法师",WARRIOR="战士",ROGUE="盗贼",PRIEST="牧师",WARLOCK="术士",PALADIN="圣骑士",HUNTER="猎人",SHAMAN="萨满祭司",DRUID="德鲁伊"}
 return names[self.engine.classToken] or "职业未知"
end
function U:CreateHintText(parent,text,x,y,width)
    local t=self:Text(parent,x,y,width,"GameFontHighlightSmall")
    self:Paint(t,"SetText",text); self:Paint(t,"SetTextColor",unpack(self.theme.colorHint)); return t
end
function U:CreateDivider(parent,x,y,width)
    local ok,t=self:Invoke(parent,"CreateTexture",nil,"BACKGROUND")
    if not ok then return end
    self:Paint(t,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y); self:Paint(t,"SetSize",width,1)
    self:Paint(t,"SetColorTexture",.16,.22,.30,1); return t
end
function U:CreateToggleRow(parent,label,x,y,width,getter,setter)
    local text=self:Text(parent,x,y-6,width-95); self:Paint(text,"SetText",label)
    local b=self:CreateActionButton(parent,"",x+width-85,y,85,function() if self.strategySource=="groupStep" then self.groupDirty=true end; setter(not getter()) end)
    b.tefTooltipTitle=label; b.tefTooltipBody="点击切换；开启和关闭同时使用文字与高亮标记。"
    local function sync()
        local enabled=getter()==true
        b.tefControlSelected=enabled
        self:Paint(b,"SetText",enabled and "开启" or "关闭")
        self:SetControlEnabled(b,b.tefControlEnabled)
    end
    self:AddControlSync(sync,b); sync(); return b,text
end
function U:CreateSegmentedControl(parent,choices,x,y,width,getter,setter)
    local out={}; local cell=math.floor((width-(#choices-1)*8)/#choices/4)*4; local needed=64
    for _,choice in ipairs(choices) do local n=0; for ch in choice[2]:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n=n+(#ch>1 and 14 or 7) end; needed=math.max(needed,n+32) end
    if cell<needed then
        local menu; local toggle=self:CreateActionButton(parent,"选择",x,y,width,function() local ok,shown=self:Invoke(menu,"IsShown"); self:Paint(menu,ok and S.Public(shown,"boolean")==true and "Hide" or "Show") end)
        menu=self:Frame("Frame",toggle,"BackdropTemplate"); self:Paint(menu,"SetPoint","TOPLEFT",toggle,"BOTTOMLEFT",0,-8)
        self:Paint(menu,"SetSize",width,math.min(248,#choices*40+8)); self:Backdrop(menu); self:Paint(menu,"SetFrameStrata","DIALOG"); self:Paint(menu,"SetClampedToScreen",true); self:Paint(menu,"EnableMouse",true)
        local scroll=self:Frame("ScrollFrame",menu,"UIPanelScrollFrameTemplate"); self:Paint(scroll,"SetSize",width-32,math.min(240,#choices*40)); self:Paint(scroll,"SetPoint","TOPLEFT",menu,"TOPLEFT",8,-8)
        local child=self:Frame("Frame",scroll); self:Paint(child,"SetSize",width-32,#choices*40); self:Paint(scroll,"SetScrollChild",child); self:Paint(child,"SetPoint","TOPLEFT",scroll,"TOPLEFT",0,0)
        self:Paint(toggle,"SetScript","OnHide",function() self:Paint(menu,"Hide"); self:HideControlTooltip(toggle) end)
        for i,choice in ipairs(choices) do local value,label=choice[1],choice[2]
            out[value]=self:CreateActionButton(child,label,0,-(i-1)*40,width-32,function() if self.strategySource=="groupStep" then self.groupDirty=true end; setter(value); self:Paint(menu,"Hide") end)
        end
        local function sync() local value=getter(); for _,choice in ipairs(choices) do if value==choice[1] then self:Paint(toggle,"SetText",choice[2] .. " v") end; out[choice[1]].tefControlSelected=value==choice[1]; self:SetControlEnabled(out[choice[1]],out[choice[1]].tefControlEnabled) end end
        self:AddControlSync(sync,toggle); sync(); self:Paint(menu,"Hide"); return out
    end
    for i,choice in ipairs(choices) do
        local value,label=choice[1],choice[2]
        local b=self:CreateActionButton(parent,label,x+(i-1)*(cell+8),y,cell,function() if self.strategySource=="groupStep" then self.groupDirty=true end; setter(value) end)
        out[value]=b
        local function sync()
            local active=getter()==value
            b.tefControlSelected=active
            self:Paint(b,"SetText",active and ("|cff80ffcc" .. label .. "|r") or label)
            self:SetControlEnabled(b,b.tefControlEnabled)
        end
        self:AddControlSync(sync,b)
    end
    return out
end
function U:CreateSelectRow(parent,label,choices,x,y,width,getter,setter)
    self:Paint(self:Text(parent,x,y,width),"SetText",label)
    return self:CreateSegmentedControl(parent,choices,x,y-25,width,getter,setter)
end
function U:CreateSliderRow(parent,label,x,y,width,min,max,step,getter,setter,editable)
    local labelWidth=math.max(88,math.min(184,math.floor(width*.34)))
    local text=self:Text(parent,x,y-4,labelWidth)
    local errorText=editable and self:CreateHintText(parent,"",x,y-40,width)
    local slider=self:Frame("Slider",parent,"OptionsSliderTemplate")
    self:Paint(slider,"SetPoint","TOPLEFT",parent,"TOPLEFT",x+labelWidth+12,y-8); self:Paint(slider,"SetSize",width-labelWidth-12-(editable and 100 or 0),20)
    self:Paint(slider,"SetMinMaxValues",min,max); self:Paint(slider,"SetValueStep",step); self:Paint(slider,"SetObeyStepOnDrag",true)
    for _,key in ipairs({"Low","High","Text"}) do
        local ok,raw=pcall(function() return slider[key] end)
        local region=ok and (S.Public(raw,"table") or S.Public(raw,"userdata")); if region then self:Call(region,"Hide") end
    end
    local syncing=false
    local input; local inputError
    if editable then
        input=self:SequenceInput(parent,x+width-88,y,88)
        local function submit()
            local ok,raw=self:Invoke(input,"GetText")
            local value=ok and S.Public(raw,"string")
            local n=value and value:match("^%s*[+-]?%d+%.?%d*%s*$") and tonumber(value)
            if not n or n<min or n>max or (step>=1 and n%1~=0) then
                inputError="须为" .. min .. "–" .. max .. (step>=1 and "的整数" or "的数值"); self:Paint(errorText,"SetText","输入" .. inputError)
                return false
            end
            inputError=nil
            if n~=getter() then self:Guard(setter,n) end; self:Refresh()
        end
        self:BindInputCommit(input,submit)
    end
    self:Paint(slider,"SetScript","OnValueChanged",function(_,raw)
        local v=S.Public(raw,"number")
        if syncing or not v or v<min or v>max then return end
        inputError=nil; local value=math.floor(v/step+.5)*step; if value~=getter() then self:Guard(setter,value) end; self:Refresh()
    end)
    local function sync()
        local value=getter(); self:Paint(text,"SetText",editable and (label .. "\n" .. min .. "～" .. max) or (label .. "  " .. string.format(step<.1 and "%.2f" or "%.1f",value)))
        if errorText then self:Paint(errorText,"SetText",inputError and ("输入" .. inputError) or "") end
        if input then
            local focused,raw=self:Invoke(input,"HasFocus")
            if not inputError and (not focused or S.Public(raw,"boolean")~=true) then self:SetInputValue(input,tostring(value)) end
        end
        syncing=true; self:Paint(slider,"SetValue",value); syncing=false
    end
    self:AddControlSync(sync,slider)
    slider.tefCaption=label; slider.tefTooltipBody="拖动调整数值；范围" .. min .. "～" .. max .. "，步进" .. step .. "。"
    self:Paint(slider,"SetScript","OnEnter",function() self:ShowControlTooltip(slider) end)
    self:Paint(slider,"SetScript","OnLeave",function() self:HideControlTooltip(slider) end)
    self:Paint(slider,"SetScript","OnHide",function() self:HideControlTooltip(slider) end)
    return slider,input
end
function U:CreateStatusBadge(parent,x,y,width)
    local text=self:Text(parent,x,y,width,"GameFontNormalLarge")
    return text
end
function U:CreateHotkeyRow(parent,x,y,width)
    local box=self:Frame("EditBox",parent,"BackdropTemplate","TEF_HotkeyEditor")
    self:Paint(box,"SetSize",168,self.controlHeight); self:Paint(box,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
    self:ApplyControlFont(box)
    self:Paint(box,"SetAutoFocus",false); self:Paint(box,"SetMaxLetters",40)
    self:Paint(box,"EnableKeyboard",true)
    self:Paint(box,"SetText",self.engine.db.dispatch.hotkey)
    self:StyleInput(box,"派发启停快捷键")
    self.hotkey,self.hotkeyMessage=box,self:Text(parent,x,y-38,width)
    local function submit(raw)
        TEF.Hotkeys:Set(raw)
        self:Paint(box,"SetText",self.engine.db.dispatch.hotkey)
        self:Paint(self.hotkeyMessage,"SetText",TEF.Hotkeys:Status())
        self:Paint(box,"ClearFocus")
    end
    self:Paint(box,"SetScript","OnKeyDown",function(editor,key)
        self:Call(editor,"SetPropagateKeyboardInput",not self.captureHotkey)
        self:Guard(function()
            if not self.captureHotkey then return end
            local done,captured=TEF.Hotkeys:Capture(editor,key)
            if done then
                self.captureHotkey=false
                if captured then submit(captured)
                else self:Paint(box,"SetText",self.engine.db.dispatch.hotkey); self:Paint(self.hotkeyMessage,"SetText","录入已取消，原快捷键保留。") end
            end
        end)
    end)
    self:Paint(box,"SetScript","OnEnterPressed",function()
        self:Guard(function() local ok,raw=self:Invoke(box,"GetText"); if ok then submit(raw) end end)
    end)
    self:Paint(box,"SetScript","OnEscapePressed",function()
        self.captureHotkey=false; self:Paint(box,"SetText",self.engine.db.dispatch.hotkey); self:Paint(box,"ClearFocus")
    end)
    self.captureHotkeyButton=self:CreateActionButton(parent,"录入",x+180,y,112,function()
        self.captureHotkey=true; self:Call(box,"SetPropagateKeyboardInput",false); self:Paint(box,"SetFocus")
        self:Paint(self.hotkeyMessage,"SetText","按下组合键即保存并应用；Esc取消。")
    end)
    self.applyHotkeyButton=self:CreateActionButton(parent,"保存",x+304,y,112,function()
        local ok,raw=self:Invoke(box,"GetText"); if ok then submit(raw) end
    end)
    self.clearHotkeyButton=self:CreateActionButton(parent,"清除",x+428,y,112,function() submit("") end)
    self:Paint(self.hotkeyMessage,"SetText",TEF.Hotkeys:Status())
    return box
end
function U:RefreshControls()
    for _,sync in ipairs(self.controls) do
        local owner=self.controlOwners and self.controlOwners[sync]; local visible=true
        if owner then local ok,raw=self:Invoke(owner,"IsVisible"); if ok and S.Public(raw,"boolean")==false then visible=false end end
        if visible then self:Guard(sync) end
    end
end
-- Old test panel uses the same visual/action primitive without owning runtime.
U.Button=U.CreateActionButton
