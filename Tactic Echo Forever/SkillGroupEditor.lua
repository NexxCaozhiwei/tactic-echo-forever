local _,T=...
local U,S,G=T.UI,T.Safety,T.SkillGroups
function U:AddSkillGroup(source)
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
 self.groupDraft=clean; self.groupSelected=1; self.strategySource=nil; self.sequencePolicyRow=nil; self.strategyInputs={}
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
 for i,row in ipairs(self.groupDraft.steps) do
  local widget=self.groupWidgets[i]; local read,value=self:Invoke(widget.count,"GetText"); value=read and S.Public(value,"string")
  local count=value and value:match("^%d+$") and tonumber(value)
  if not count or count<1 or count>99 then self:Paint(self.groupMessage,"SetText","使用次数须为1～99整数。"); return false end
  row.repeatCount=count
 end
 self.groupDraft.name=name; self.groupDraft.rounds=rounds; return true
end
function U:RefreshSkillGroup()
 if not self.groupDraft then return end
 self:Paint(self.groupName,"SetText",self.groupDraft.name); self:Paint(self.groupRounds,"SetText",tostring(self.groupDraft.rounds))
 for i,w in ipairs(self.groupWidgets) do
  local row=self.groupDraft.steps[i]; self:Paint(w.frame,row and "Show" or "Hide")
  if row then
   self:Paint(w.name,"SetText",i .. ". " .. S.Spell(row.spellID,row.name).name)
   self:Paint(w.count,"SetText",tostring(row.repeatCount)); self:Paint(w.skip,"SetText",row.skipUnavailable and "不可用跳过：开" or "不可用跳过：关")
  end
 end
 self:Paint(self.groupChild,"SetHeight",math.max(120,#self.groupDraft.steps*76))
end
function U:GroupAdd(id,index)
 if not self:CommitGroupFields() then return false end
 id=S.ID(id); if not id or id==7268 or #self.groupDraft.steps>=8 then self:Paint(self.groupMessage,"SetText","精确ID无效或组内已达到8步。"); return false end
 local view=S.Spell(id,"技能 " .. id)
 table.insert(self.groupDraft.steps,index and math.min(index,#self.groupDraft.steps+1) or #self.groupDraft.steps+1,{spellID=id,name=view.name,matchIDs={id},repeatCount=1,enabled=true,usagePolicy="always",strategies={}})
 self:RefreshSkillGroup()
 self:Paint(self.groupMessage,"SetText","已加入技能组草稿；保存后生效。")
 return true
end
function U:GroupMove(index,destination)
 if not self:CommitGroupFields() or not self.groupDraft.steps[destination] then return end
 local row=table.remove(self.groupDraft.steps,index); table.insert(self.groupDraft.steps,destination,row); self:RefreshSkillGroup()
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
 if not self:SaveSkillGroup() then return false end
 if keepGroup then self:Paint(self.groupPanel,"Hide"); self:Paint(self.strategyPanel,"Hide")
 else self:CloseSkillGroup() end
 return true
end
function U:SaveSkillGroup()
 if not self.groupEditing or not self:CommitCustomNumbers() or not self:CommitGroupFields() then return false end
 local group,why=G:Clean(self.groupDraft)
 if not group or #group.steps==0 then self:Paint(self.groupMessage,"SetText",why or "至少加入一个技能再保存。"); return false end
 local edit=self.groupEditing; local rows=edit.source=="manual" and self:DraftRows() or self.customDraft
 local parent=rows and rows[edit.index]; if not parent or not parent.group then return false end
 local row=G:Row(group,parent.strategies,parent.enabled)
 if edit.source=="manual" then rows[edit.index]=row; self:WriteDraft(rows)
 else rows[edit.index]={group=group,spellID=row.spellID,enabled=row.enabled,strategies=row.strategies}; self.customFormIndex=nil; self:RefreshCustomAPL() end
 local ok,reason
 if edit.source=="manual" then ok,reason=T.Profiles:Save(self.engine,edit.scene,rows)
 else ok,reason=T.APL.Custom:Save(self.engine,rows,edit.scene,self.customClass) end
 self:Paint(self.groupMessage,"SetText",ok and "技能组和父列表已保存，派发已停止。" or (reason or "保存失败"))
 return ok
end
function U:CloseSkillGroup()
 self:Paint(self.groupPanel,"Hide"); self:Paint(self.strategyPanel,"Hide")
 self.groupEditing=nil; self.groupDraft=nil; self.strategySource=nil; self.strategyInputs={}; self.customFormIndex=nil
end
function U:CreateSkillGroupEditor()
 local panel=self:Frame("Frame",self.settings,"BackdropTemplate","TEF_SkillGroupEditor"); self.groupPanel=panel
 self:Paint(panel,"SetPoint","TOPLEFT",self.settings,"TOPRIGHT",8,0); self:Paint(panel,"SetSize",430,720)
 self:Paint(panel,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
 self:Paint(panel,"SetBackdropColor",.025,.035,.055,.98); self:Paint(panel,"SetBackdropBorderColor",.25,.45,.60,1)
 self:Paint(self:Text(panel,15,-18,390,"GameFontNormal"),"SetText","技能组编辑 · 顺序执行")
 self:CreateHintText(panel,"组策略决定进入；组内精确成功推进。最多8步，不嵌套。",15,-51,395)
 self.groupName=self:SequenceInput(panel,15,-84,245); self.groupRounds=self:SequenceInput(panel,335,-84,65)
 self:Paint(self:Text(panel,268,-91,65),"SetText","循环轮数")
 self.groupDrop=self:CreateActionButton(panel,"拖入技能",15,-126,120,function() self:GroupReceive() end)
 self:BindGroupDrop(self.groupDrop); self:Paint(self.groupDrop,"RegisterForDrag","LeftButton"); self:Paint(self.groupDrop,"RegisterForClicks","LeftButtonUp")
 self.groupID=self:SequenceInput(panel,145,-126,90)
 self:CreateActionButton(panel,"ID新增",245,-126,85,function() local ok,v=self:Invoke(self.groupID,"GetText"); local raw=ok and S.Public(v,"string"); self:GroupAdd(raw and raw:match("^%d+$") and tonumber(raw)) end)
 self:BindGroupDrop(panel)
 self.groupListBox=self:Frame("Frame",panel,"BackdropTemplate")
 self:Paint(self.groupListBox,"SetPoint","TOPLEFT",panel,"TOPLEFT",15,-166); self:Paint(self.groupListBox,"SetSize",400,435)
 self:CreateSectionCard(self.groupListBox,"技能列表 · 拖入追加，拖到条目前插入",0,0,400,435)
 self:Paint(self.groupListBox,"SetBackdrop",{edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
 self:Paint(self.groupListBox,"SetBackdropBorderColor",.25,.45,.60,1)
 self:BindGroupDrop(self.groupListBox,nil,true)
 local scroll=self:Frame("ScrollFrame",panel,"UIPanelScrollFrameTemplate")
 self.groupScroll=scroll
 self:Paint(scroll,"SetPoint","TOPLEFT",panel,"TOPLEFT",21,-202); self:Paint(scroll,"SetSize",378,391)
 self.groupChild=self:Frame("Frame",scroll); self:Paint(self.groupChild,"SetSize",385,120); self:Paint(scroll,"SetScrollChild",self.groupChild)
 self:BindGroupDrop(scroll,nil,true); self:BindGroupDrop(self.groupChild,nil,true)
 self.groupWidgets={}
 for i=1,8 do
  local index=i; local frame=self:Frame("Frame",self.groupChild,"BackdropTemplate")
  self:Paint(frame,"SetPoint","TOPLEFT",self.groupChild,"TOPLEFT",0,-(i-1)*76); self:Paint(frame,"SetSize",380,72)
  self:Paint(frame,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  self:Paint(frame,"SetBackdropColor",.05,.08,.12,1); self:Paint(frame,"SetBackdropBorderColor",.25,.42,.58,1)
  self:BindGroupDrop(frame,index,true)
  local w={frame=frame,name=self:Text(frame,6,-8,126),count=self:SequenceInput(frame,70,-38,46)}
  w.policy=self:CreateActionButton(frame,"编辑策略",138,-2,80,function()
   if not self:PrepareGroupPanelSwitch(true) then return end
   self.strategySource="groupStep"; self.groupSelected=index; self.customSelected=index; self.customFormIndex=nil
   self:Paint(panel,"Hide"); self:RefreshStrategyForm(); self:Paint(self.strategyPanel,"Show")
  end)
  self:CreateActionButton(frame,"↑",224,-2,42,function() self:GroupMove(index,index-1) end)
  self:CreateActionButton(frame,"↓",272,-2,42,function() self:GroupMove(index,index+1) end)
  self:CreateActionButton(frame,"删",320,-2,52,function() table.remove(self.groupDraft.steps,index); self:RefreshSkillGroup() end)
  self:Paint(self:Text(frame,6,-45,60),"SetText","使用次数")
  local function count(box) local ok,raw=self:Invoke(box,"GetText"); local text=ok and S.Public(raw,"string"); local n=text and text:match("^%d+$") and tonumber(text)
   if n and n>=1 and n<=99 and self.groupDraft.steps[index] then self.groupDraft.steps[index].repeatCount=n else self:Paint(self.groupMessage,"SetText","使用次数须为1～99整数。") end
   self:Paint(box,"ClearFocus")
  end
  self:Paint(w.count,"SetScript","OnEnterPressed",function(box) self:Guard(function() count(box) end) end)
  self:Paint(w.count,"SetScript","OnEditFocusLost",function(box) self:Guard(function() count(box) end) end)
  w.skip=self:CreateActionButton(frame,"不可用跳过：关",132,-38,175,function() local row=self.groupDraft.steps[index]; row.skipUnavailable=not row.skipUnavailable; self:RefreshSkillGroup() end)
  self:Paint(frame,"RegisterForDrag","LeftButton")
  self:Paint(frame,"SetScript","OnDragStart",function() self.groupDragging=index end)
  self:Paint(frame,"SetScript","OnDragStop",function() self:Guard(function()
   local source=self.groupDragging; self.groupDragging=nil; if not source then return end
   for dest,widget in ipairs(self.groupWidgets) do local ok,over=S.Call("MouseIsOver",widget.frame); if ok and S.Public(over,"boolean")==true then self:GroupMove(source,dest); break end end
  end) end)
  self.groupWidgets[i]=w
 end
 self.groupMessage=self:Text(panel,15,-611,395)
 self:CreateActionButton(panel,"保存",15,-675,120,function() self:SaveSkillGroup() end)
 self:CreateActionButton(panel,"清空",145,-675,120,function() self.groupDraft.steps={}; self:RefreshSkillGroup(); self:Paint(self.groupMessage,"SetText","已清空草稿；未改变保存配置。") end)
 self:CreateActionButton(panel,"退出",275,-675,120,function() self:CloseSkillGroup() end)
 self:Paint(panel,"Hide")
end
