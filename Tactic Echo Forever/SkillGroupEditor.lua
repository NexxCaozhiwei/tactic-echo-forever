local _,T=...
local U,S,G=T.UI,T.Safety,T.SkillGroups
function U:AddSkillGroup(source)
 if source=="manual" and not self:CommitSequenceCounts() then return end
 if not self:PrepareGroupPanelSwitch(false) then return end
 if not self:CommitCustomNumbers() then return end
 local rows=source=="manual" and self:DraftRows() or self.customDraft
 if not rows or #rows>=16 then self:CustomMessage("父列表最多16项。"); return end
 local group={name="技能组" .. (#rows+1),rounds=1,steps={}}
 local row=source=="manual" and G:Row(group) or {group=group,spellID=0,enabled=true,strategies={}}
 rows[#rows+1]=row
 if source=="manual" then self:WriteDraft(rows) else self.customFormIndex=nil; self:RefreshCustomAPL() end
 self:OpenSkillGroup(source,#rows)
end
function U:OpenSkillGroup(source,index)
 if not self:PrepareGroupPanelSwitch(false) then return end
 if not self:CommitCustomNumbers() then return end
 local rows=source=="manual" and self:DraftRows() or self.customDraft
 local row=rows and rows[index]; if not row or not row.group then return end
 local clean=G:Clean(row.group); if not clean then return end
 self.groupEditing={source=source,index=index,scene=source=="manual" and self.editScene or self.customLoadedScene}
 self.groupDirty=false; self.groupDraft=clean; self.groupSelected=1; self.strategySource=nil; self.sequencePolicyRow=nil; self.strategyInputs={}
 self:Paint(self.strategyPanel,"Hide"); self:Paint(self.groupPanel,"Show"); self:RefreshSkillGroup()
end
function U:CommitGroupFields()
 if not self.groupDraft then return false end
 local got,name=self:Invoke(self.groupName,"GetText"); name=got and S.Public(name,"string")
 local ok,raw=self:Invoke(self.groupRounds,"GetText"); raw=ok and S.Public(raw,"string")
 local rounds=raw and raw:match("^%d+$") and tonumber(raw)
 if not name or #name<1 or #name>64 or name:find("[|%c]") or not rounds or rounds<1 or rounds>99 then
  self:Paint(self.groupMessage,"SetText","名称1～64字节；循环轮数1～99整数。"); return false
 end
 local counts={}
 for i,row in ipairs(self.groupDraft.steps) do
  local widget=self.groupWidgets[i]; local read,value=self:Invoke(widget.count,"GetText"); value=read and S.Public(value,"string")
  local count=value and value:match("^%d+$") and tonumber(value)
  if not count or count<1 or count>99 then self:Paint(self.groupMessage,"SetText","使用次数须为1～99整数。"); return false end
  counts[i]=count
 end
 for i,row in ipairs(self.groupDraft.steps) do if row.repeatCount~=counts[i] then self.groupDirty=true end; row.repeatCount=counts[i] end
 if self.groupDraft.name~=name or self.groupDraft.rounds~=rounds then self.groupDirty=true end; self.groupDraft.name=name; self.groupDraft.rounds=rounds; return true
end
function U:RefreshSkillGroup()
 if not self.groupDraft then return end
 self:SetInputValue(self.groupName,self.groupDraft.name); self:SetInputValue(self.groupRounds,tostring(self.groupDraft.rounds))
 for i,w in ipairs(self.groupWidgets) do
  local row=self.groupDraft.steps[i]; self:Paint(w.frame,row and "Show" or "Hide")
  if row then
   w.frame.tefTooltipTitle=S.Spell(row.spellID,row.name).name; w.frame.tefTooltipBody="精确ID " .. row.spellID .. "；次数1～99。"
   self:Paint(w.name,"SetText",i .. ". " .. self:ShortLabel(w.frame.tefTooltipTitle,6) .. " · ID " .. row.spellID)
   self:SetInputValue(w.count,tostring(row.repeatCount)); self:Paint(w.skip,"SetText",row.skipUnavailable and "不可用跳过：开" or "不可用跳过：关")
  end
 end
 self:Paint(self.groupChild,"SetHeight",math.max(120,#self.groupDraft.steps*88)); self:LayoutSettings()
end
function U:GroupAdd(id,index)
 if not self:CommitGroupFields() then return false end
 id=S.ID(id); if not id or id==7268 or #self.groupDraft.steps>=8 then self:Paint(self.groupMessage,"SetText","精确ID无效或组内已达到8步。"); return false end
 local view=S.Spell(id,"技能 " .. id)
 table.insert(self.groupDraft.steps,index and math.min(index,#self.groupDraft.steps+1) or #self.groupDraft.steps+1,{spellID=id,name=view.name,matchIDs={id},repeatCount=1,enabled=true,usagePolicy="always",strategies={}})
 self.groupDirty=true; self:RefreshSkillGroup()
 self:Paint(self.groupMessage,"SetText","已加入技能组草稿；保存后生效。")
 return true
end
function U:GroupMove(index,destination)
 if not self:CommitGroupFields() or not self.groupDraft.steps[destination] then return end
 local row=table.remove(self.groupDraft.steps,index); table.insert(self.groupDraft.steps,destination,row); self.groupDirty=true; self:RefreshSkillGroup()
end
function U:GroupReceive(index)
 local id,reason=T.ActionSources:Cursor()
 if not id then
  if reason~="NO_DATA" then self:Paint(self.groupMessage,"SetText","拖入未接纳：无法确认精确技能ID。") end
  return false
 end
 if not self:GroupAdd(id,index) then return false end
 S.Call("ClearCursor"); return true
end
function U:BindGroupDrop(frame,index,click)
 self:Paint(frame,"EnableMouse",true)
 self:Paint(frame,"SetScript","OnReceiveDrag",function() self:Guard(function() self:GroupReceive(index) end) end)
 if click then self:Paint(frame,"SetScript","OnMouseUp",function(_,button) if S.Public(button,"string")=="LeftButton" then self:Guard(function() self:GroupReceive(index) end) end end) end
end
function U:PrepareGroupPanelSwitch(keepGroup)
 if not self.groupEditing then self:Paint(self.groupPanel,"Hide"); return true end
 if not self:SaveSkillGroup(true) then return false end
 if keepGroup then self:Paint(self.groupPanel,"Hide"); self:Paint(self.strategyPanel,"Hide")
 else self:CloseSkillGroup(true) end
 return true
end
function U:SaveSkillGroup(draftOnly)
 if not self.groupEditing or not self:CommitCustomNumbers() or not self:CommitGroupFields() then return false end
 local group,why=G:Clean(self.groupDraft)
 if not group or #group.steps==0 then self:Paint(self.groupMessage,"SetText",why or "至少加入一个技能再保存。"); return false end
 local edit=self.groupEditing; local rows=edit.source=="manual" and self:DraftRows() or self.customDraft
 local parent=rows and rows[edit.index]; if not parent or not parent.group then return false end
 local row=G:Row(group,parent.strategies,parent.enabled); row.behavior=parent.behavior
 if edit.source=="manual" then rows[edit.index]=row; self:WriteDraft(rows)
 else rows[edit.index]={group=group,spellID=row.spellID,enabled=row.enabled,strategies=row.strategies,behavior=row.behavior}; self.customFormIndex=nil; self:RefreshCustomAPL() end
 if draftOnly then self.groupDirty=false; self:Paint(self.groupMessage,"SetText","已暂存到父列表草稿；点击保存后生效。"); return true end
 local ok,reason
 if edit.source=="manual" then ok,reason=T.Profiles:Save(self.engine,edit.scene,rows)
 else ok,reason=T.APL.Custom:Save(self.engine,rows,edit.scene,self.customClass) end
 if ok then self.groupDirty=false end
 self:Paint(self.groupMessage,"SetText",ok and "技能组和父列表已保存，派发已停止。" or (reason or "保存失败"))
 return ok
end
function U:CloseSkillGroup(force,nextAction)
 if self.groupEditing and not force then
  if not self:CommitCustomNumbers() or not self:CommitGroupFields() then self.groupDirty=true end
  if self.groupDirty then
   self:ConfirmAction("技能组仍有未暂存修改。确认放弃这些修改并退出？",function() self:CloseSkillGroup(true); if nextAction then nextAction() end end,"放弃修改","继续编辑")
   return false
  end
 end
 self:Paint(self.groupPanel,"Hide"); self:Paint(self.strategyPanel,"Hide")
 self.groupEditing=nil; self.groupDraft=nil; self.groupDirty=false; self.strategySource=nil; self.strategyInputs={}; self.customFormIndex=nil; self:LayoutSettings(); return true
end
function U:CreateSkillGroupEditor()
 local panel=self:Frame("Frame",self.settings,"BackdropTemplate","TEF_SkillGroupEditor"); self.groupPanel=panel
 self:Paint(panel,"SetFrameStrata","DIALOG"); self:Paint(panel,"EnableMouse",true)
 self:Paint(panel,"SetPoint","TOPLEFT",self.settings,"TOPRIGHT",8,0); self:Paint(panel,"SetSize",430,720)
 self:Paint(panel,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
 self:Paint(panel,"SetBackdropColor",.025,.035,.055,.98); self:Paint(panel,"SetBackdropBorderColor",.25,.45,.60,1)
 self:Paint(self:Text(panel,15,-18,390,"GameFontNormal"),"SetText","技能组编辑 · 顺序执行")
 self:CreateHintText(panel,"组策略决定进入；组内精确成功推进。最多8步，不嵌套。",15,-51,395)
 self:CreateHintText(panel,"组名（1～64字节）",16,-88,240); self:CreateHintText(panel,"循环轮数（1～99）",280,-88,136)
 self.groupName=self:SequenceInput(panel,16,-112,248); self.groupRounds=self:SequenceInput(panel,280,-112,120); self:Paint(self.groupName,"SetMaxLetters",64)

 self.groupDrop=self:CreateActionButton(panel,"拖入技能",16,-184,120,function() self:GroupReceive() end)
 self:BindGroupDrop(self.groupDrop); self:Paint(self.groupDrop,"RegisterForDrag","LeftButton"); self:Paint(self.groupDrop,"RegisterForClicks","LeftButtonUp")
 self:CreateHintText(panel,"精确技能ID",152,-160,112)
 self.groupID=self:SequenceInput(panel,152,-184,112)
 self:CreateActionButton(panel,"ID新增",280,-184,120,function() local ok,v=self:Invoke(self.groupID,"GetText"); local raw=ok and S.Public(v,"string"); self:GroupAdd(raw and raw:match("^%d+$") and tonumber(raw)) end)
 self:BindGroupDrop(panel)
 self.groupListBox=self:Frame("Frame",panel,"BackdropTemplate")
 self:Paint(self.groupListBox,"SetPoint","TOPLEFT",panel,"TOPLEFT",16,-232); self:Paint(self.groupListBox,"SetSize",400,435)
 self:Paint(self:Text(self.groupListBox,8,-8,384,"GameFontNormal"),"SetText","技能列表 · 拖入追加／插入")
 self:Paint(self.groupListBox,"SetBackdrop",{edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
 self:Paint(self.groupListBox,"SetBackdropBorderColor",.25,.45,.60,1)
 self:BindGroupDrop(self.groupListBox,nil,true)
 local scroll=self:Frame("ScrollFrame",panel,"UIPanelScrollFrameTemplate")
 self.groupScroll=scroll
 self:Paint(scroll,"SetPoint","TOPLEFT",panel,"TOPLEFT",24,-272); self:Paint(scroll,"SetSize",378,391)
 self.groupChild=self:Frame("Frame",scroll); self:Paint(self.groupChild,"SetSize",385,120); self:Paint(scroll,"SetScrollChild",self.groupChild)
 self:BindGroupDrop(scroll,nil,true); self:BindGroupDrop(self.groupChild,nil,true)
 self.groupWidgets={}
 for i=1,8 do
  local index=i; local frame=self:Frame("Frame",self.groupChild,"BackdropTemplate")
  self:Paint(frame,"SetPoint","TOPLEFT",self.groupChild,"TOPLEFT",0,-(i-1)*88); self:Paint(frame,"SetSize",380,80)
  self:Paint(frame,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  self:Paint(frame,"SetBackdropColor",.05,.08,.12,1); self:Paint(frame,"SetBackdropBorderColor",.25,.42,.58,1)
  self:BindGroupDrop(frame,index,true)
  self:BindControlTooltip(frame,"组内技能","精确成功回执推进组内步骤。")
  local w={frame=frame,name=self:Text(frame,8,-10,148),count=self:SequenceInput(frame,48,-44,64)}
  self:Paint(w.name,"SetWordWrap",false)
  w.policy=self:CreateActionButton(frame,"编辑策略",164,-8,84,function()
   if not self:PrepareGroupPanelSwitch(true) then return end
   self.strategySource="groupStep"; self.groupSelected=index; self.customSelected=index; self.customFormIndex=nil
   self:Paint(panel,"Hide"); self:RefreshStrategyForm(); self:Paint(self.strategyPanel,"Show")
  end)
  local up=self:CreateActionButton(frame,"↑",256,-8,28,function() self:GroupMove(index,index-1) end)
  local down=self:CreateActionButton(frame,"↓",292,-8,28,function() self:GroupMove(index,index+1) end)
  local delete=self:CreateActionButton(frame,"删除",328,-8,44,function() self:DeleteDraft("group",index) end)
  self:Paint(self:Text(frame,8,-52,32,"GameFontHighlightSmall"),"SetText","次数")
  local function count(box) local ok,raw=self:Invoke(box,"GetText"); local text=ok and S.Public(raw,"string"); local n=text and text:match("^%d+$") and tonumber(text)
   if n and n>=1 and n<=99 and self.groupDraft.steps[index] then if self.groupDraft.steps[index].repeatCount~=n then self.groupDirty=true end; self.groupDraft.steps[index].repeatCount=n else self:Paint(self.groupMessage,"SetText","使用次数须为1～99整数。"); return false end
  end
  self:BindInputCommit(w.count,count)
  w.skip=self:CreateActionButton(frame,"不可用跳过：关",124,-44,248,function() if not self:CommitGroupFields() then return end; local row=self.groupDraft.steps[index]; row.skipUnavailable=not row.skipUnavailable; self.groupDirty=true; self:RefreshSkillGroup() end)
  self:Paint(frame,"RegisterForDrag","LeftButton")
  self:Paint(frame,"SetScript","OnDragStart",function() self.groupDragging=index end)
  self:Paint(frame,"SetScript","OnDragStop",function() self:Guard(function()
   local source=self.groupDragging; self.groupDragging=nil; if not source then return end
   for dest,widget in ipairs(self.groupWidgets) do local ok,over=S.Call("MouseIsOver",widget.frame); if ok and S.Public(over,"boolean")==true then self:GroupMove(source,dest); break end end
  end) end)
  self:CompactControl(w.count,64); self:CompactControl(w.policy,84); self:CompactControl(up,28); self:CompactControl(down,28); self:CompactControl(delete,44); self:CompactControl(w.skip,248)
  self:ApplyControlFont(w.name,false,12); self:StyleListRow(frame,i)
  w.up,w.down,w.delete=up,down,delete; self.groupWidgets[i]=w
 end
 self.groupMessage=self:Text(panel,16,-611,398); self:Paint(self.groupMessage,"ClearAllPoints"); self:Paint(self.groupMessage,"SetPoint","BOTTOMLEFT",panel,"BOTTOMLEFT",16,96)
 self.groupSaveButton=self:CreateActionButton(panel,"保存方案",280,-675,120,function() self:SaveSkillGroup() end)
 self.groupClearButton=self:CreateActionButton(panel,"清空步骤",16,-675,120,function() if not self:CommitGroupFields() then return end; self:ConfirmAction("确认清空技能组的全部步骤？保存后生效。",function() self.groupDraft.steps={}; self.groupDirty=true; self:RefreshSkillGroup(); self:Paint(self.groupMessage,"SetText","已清空草稿；未改变保存配置。") end,"清空步骤") end)
 self.groupExitButton=self:CreateActionButton(panel,"退出编辑",152,-675,112,function() self:CloseSkillGroup() end)
 for i,button in ipairs({self.groupClearButton,self.groupExitButton,self.groupSaveButton}) do self:Paint(button,"ClearAllPoints"); self:Paint(button,"SetPoint","BOTTOMLEFT",panel,"BOTTOMLEFT",i==1 and 16 or i==2 and 152 or 280,16) end
 self.groupUndoButton=self:CreateActionButton(panel,"撤销删除",16,-635,120,function() self:UndoDelete("group") end)
 self:Paint(self.groupUndoButton,"ClearAllPoints"); self:Paint(self.groupUndoButton,"SetPoint","BOTTOMLEFT",panel,"BOTTOMLEFT",16,56)
 self:Paint(panel,"Hide")
end
