local _,T=...
local U,S=T.UI,T.Safety
local function anchor(self,object,parent,x,y)
 self:Paint(object,"ClearAllPoints"); self:Paint(object,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
end
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
function U:StudioRows()
 if self.page=="profiles" then return self:DraftRows(),"manual",self.editScene end
 if self.page=="customapl" or self.page=="maintenance" then return self.customDraft,"apl",self.customLoadedScene end
end
function U:StudioDirty(source,scene,rows)
 if not rows then return false end
 local saved=source=="manual" and T.Profiles:Clean(self.engine.db.profiles[scene],32)
  or T.APL.Custom.CleanRows(scene=="maintenance" and T.Maintenance:Rows(self.engine) or T.APL.Custom:Rows(self.engine,scene))
 local draft=source=="manual" and T.Profiles:Clean(rows,32) or T.APL.Custom.CleanRows(rows)
 if not draft then return true end
 if source=="apl" then
  for _,row in ipairs(saved) do T.APL.Custom:UpgradeStrategies(row) end
  for _,row in ipairs(draft) do T.APL.Custom:UpgradeStrategies(row) end
 end
 return not equal(draft,saved)
end
function U:StudioPlanDraft(source,scene)
 if source=="manual" then
  if self.sequenceEngine~=self.engine then return nil end
  if self.loadedScene==scene then return self:DraftRows() end
  return self.sequenceDrafts and self.sequenceDrafts[(self.engine.profileKey or "unknown") .. ":" .. scene]
 end
 if self.customEngine~=self.engine then return nil end
 if self.customLoadedScene==scene then return self.customDraft end
 return self.customDraftCache and self.customDraftCache[(self.engine.classToken or "UNKNOWN") .. ":" .. scene]
end
function U:CreateStudioPanel(parent)
 local panel=self:Frame("Frame",parent,"BackdropTemplate")
 self:Paint(panel,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=4,right=4,top=4,bottom=4}})
 self:Paint(panel,"SetBackdropColor",unpack(self.theme.panel)); self:Paint(panel,"SetBackdropBorderColor",unpack(self.theme.border))
 return panel
end
function U:CreateRuleRow(parent,index)
 local frame=self:CreateStudioPanel(parent)
 self:Paint(frame,"SetSize",530,80)
 local handle=self:Text(frame,8,-12,24,"GameFontHighlightSmall"); self:Paint(handle,"SetText","≡")
 local ok,icon=self:Invoke(frame,"CreateTexture",nil,"ARTWORK")
 if ok then anchor(self,icon,frame,32,-8); self:Paint(icon,"SetSize",28,28) end
 local badge=self:Text(frame,8,-58,104,"GameFontHighlightSmall")
 frame.studioID=self:Text(frame,68,-30,172,"GameFontHighlightSmall")
 frame.studioSummary=self:Text(frame,136,-56,384,"GameFontHighlightSmall")
 frame.studioIcon=icon; frame.studioBadge=badge
 frame.studioChips={}
 for n=1,3 do
  local chip=self:CreateStudioPanel(frame); self:Paint(chip,"SetPoint","TOPLEFT",frame,"TOPLEFT",136+(n-1)*104,-48); self:Paint(chip,"SetSize",96,24)
  chip.label=self:Text(chip,6,-5,84,"GameFontHighlightSmall"); self:Paint(chip.label,"SetWordWrap",false)
  self:BindControlTooltip(chip,"条件摘要","仅展示条件要求，不表示已满足。"); self:Paint(chip,"EnableMouse",true)
  frame.studioChips[n]=chip
 end
 self:StyleListRow(frame,index)
 return frame
end
function U:RefreshStudioRow(w,row,index,source)
 if not row then return end
 local view=S.Spell(row.spellID,row.name or ("技能 " .. (row.spellID or "未知")))
 self:Paint(w.frame.studioIcon,"SetTexture",view.icon)
 self:Paint(w.frame.studioID,"SetText","ID " .. (row.spellID or "未知"))
 self:Paint(w.frame.studioBadge,(source=="manual" or source=="group") and "Hide" or "Show")
 self:Paint(w.frame.studioSummary,(source=="manual" or source=="group") and "Hide" or "Show")
 if source=="apl" then self:Paint(w.frame.studioSummary,"SetText",row.group and (#row.group.steps .. "步 · " .. row.group.rounds .. "轮") or ("策略 " .. #(row.strategies or {}) .. " 组 · 点击编辑策略")) end
 anchor(self,w.name,w.frame,68,-10); self:Paint(w.name,"SetWidth",math.max(120,(self.studioEditorWidth or 580)-396))
 self:Paint(w.name,"SetText",string.format("%02d",index) .. " " .. self:ShortLabel(row.group and row.group.name or view.name,7))
 local badge=row.enabled==false and "DISABLED" or "UNKNOWN"
 local p=self.studioCurrentProbe; local now=T.APL.State.Time()
 if p and now and p.time and now>=p.time and now-p.time<=.25 and p.rows[index] and row.enabled~=false then
  local result=p.rows[index].result
  badge=result=="TRUE" and "READY" or result=="UNKNOWN" and "UNKNOWN" or result=="DISABLED" and "DISABLED" or "BLOCKED"
 end
 self:Paint(w.frame.studioBadge,"SetText",badge)
 self:Paint(w.frame.studioBadge,"SetTextColor",unpack(self.theme.statusColors[badge] or self.theme.colorHint))
 -- 草稿没有对应的实时求值身份，不复用已保存列表的就绪快照。
 local selected=self.studioSelected and self.studioSelected.source==source and self.studioSelected.index==index
 w.frame.tefRowSelected=selected==true; self:PaintListRow(w.frame)
 local conditions={}
 for _,strategy in ipairs(row.strategies or {}) do for _,c in ipairs(strategy.conditions or {}) do
  local label=(strategy.mode=="skip" and "除非·" or "满足·") .. ((self.conditionNames and self.conditionNames[c.kind]) or c.kind)
  conditions[#conditions+1]=label
 end end
 for n,chip in ipairs(w.frame.studioChips or {}) do
  local shown=source=="apl" and not row.group and conditions[n]~=nil
  self:Paint(chip,shown and "Show" or "Hide")
  if shown then self:Paint(chip.label,"SetText",n==3 and #conditions>3 and ("＋" .. (#conditions-2) .. "项") or self:ShortLabel(conditions[n],6)); chip.tefTooltipBody=table.concat(conditions,"\n") .. "\n使用条件全部满足；任一跳过策略全部满足则跳过。" end
 end
 if source=="apl" and #conditions>0 and not row.group then self:Paint(w.frame.studioSummary,"Hide") end
end
function U:StudioDropTarget(source)
 if source~="manual" and source~="apl" and source~="group" then return nil end
 local widgets=source=="group" and self.groupWidgets or source=="manual" and self.sequenceRows or self.customWidgets
 local rows=source=="group" and self.groupDraft and self.groupDraft.steps or source=="manual" and self:DraftRows() or self.customDraft
 for i,w in ipairs(widgets or {}) do
  local ok,over=S.Call("MouseIsOver",w.frame)
  if rows and rows[i] and ok and S.Public(over,"boolean")==true then return i,w.frame end
 end
 local scroll=source=="group" and self.groupScroll or source=="manual" and self.sequenceScroll or self.customScroll
 local ok,over=S.Call("MouseIsOver",scroll)
 if rows and ok and S.Public(over,"boolean")==true then return #rows+1,scroll end
end
function U:HideStudioInsertion()
 if self.studioInsertion then self:Paint(self.studioInsertion,"Hide") end
end
function U:ShowStudioInsertion(frame)
 if not self.studioInsertion then
  local line=self:CreateStudioPanel(self.settings); self.studioInsertion=line
  self:Paint(line,"SetHeight",4); self:Paint(line,"SetBackdropColor",unpack(self.theme.colorFocus))
  line.label=self:Text(line,144,16,260,"GameFontHighlightSmall"); self:Paint(line.label,"SetText","↓ 拖放插入到此处")
 end
 local line=self.studioInsertion
 self:Paint(line,"SetParent",frame); self:Paint(line,"ClearAllPoints")
 self:Paint(line,"SetPoint","TOPLEFT",frame,"TOPLEFT",0,4); self:Paint(line,"SetPoint","TOPRIGHT",frame,"TOPRIGHT",0,4)
 self:Paint(line,"Show")
end
function U:BindStudioDrag(w,index,source)
 local frame=w.frame
 for _,chip in ipairs(frame.studioChips or {}) do
  self:Paint(chip,"RegisterForDrag","LeftButton")
  for _,event in ipairs({"OnReceiveDrag","OnMouseUp","OnDragStart","OnDragStop"}) do
   local script=event
   self:Paint(chip,"SetScript",script,function(_,...) local args={...}; self:Guard(function()
    local ok,callback=self:Invoke(frame,"GetScript",script); if ok and type(callback)=="function" then callback(frame,unpack(args)) end
   end) end)
  end
 end
 local policyOK,policyClick=self:Invoke(w.policy,"GetScript","OnClick")
 if policyOK and policyClick then self:Paint(w.policy,"SetScript","OnClick",function(button) self:Guard(function()
  if self:SelectStudioRule(source,index) then policyClick(button) end
 end) end) end
 for _,key in ipairs({"policy","groupEdit","up","down","delete"}) do
  self:Paint(w[key],"SetScript","OnReceiveDrag",function() self:Guard(function()
   if source=="manual" then self:ReceiveSequenceSpell(index) elseif source=="group" then self:GroupReceive(index) else self:ReceiveCustomSpell(index) end
  end) end)
 end
 local enterOK,enter=self:Invoke(frame,"GetScript","OnEnter")
 local leaveOK,leave=self:Invoke(frame,"GetScript","OnLeave")
 self:Paint(frame,"SetScript","OnEnter",function(f)
  if enterOK and enter then enter(f) end
  local id=T.ActionSources:Cursor()
  if self.studioDragging or id then self:ShowStudioInsertion(frame) end
 end)
 self:Paint(frame,"SetScript","OnLeave",function(f)
  if leaveOK and leave then leave(f) end
  self:HideStudioInsertion()
 end)
 self:Paint(frame,"SetScript","OnDragStart",function() self:Guard(function()
  if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return end
  if source=="group" and not self:CommitGroupFields() then return end
  self.studioDragging={source=source,index=index,frame=frame}; self:Paint(frame,"SetAlpha",.5)
 end) end)
 self:Paint(frame,"SetScript","OnDragStop",function() self:Guard(function()
  local drag=self.studioDragging; self.studioDragging=nil; self:Paint(frame,"SetAlpha",1); self:HideStudioInsertion()
  if not drag then return end
  local target=self:StudioDropTarget(source)
  local rows=source=="group" and self.groupDraft and self.groupDraft.steps or source=="manual" and self:DraftRows() or self.customDraft
  if target and rows then
   if target>index then target=target-1 end
   target=math.min(target,#rows)
   if source=="manual" then self:ReorderSequenceRow(index,target) elseif source=="group" then self:GroupMove(index,target) else self:ReorderCustomRule(index,target) end
   self.studioSelected={source=source,index=target}
  else
   if source=="manual" then self:SequenceMessage("已取消拖动，草稿顺序保持。") else self:CustomMessage("已取消拖动，草稿顺序保持。") end
  end
  self:RefreshStudio()
 end) end)
 self:Paint(frame,"SetScript","OnMouseUp",function(f,button)
  if S.Public(button,"string")=="LeftButton" and not self.studioDragging then self:Guard(function()
   if source=="manual" then self:ReceiveSequenceSpell(index) elseif source=="group" then self:GroupReceive(index) else self:ReceiveCustomSpell(index) end
   self:SelectStudioRule(source,index)
  end) end
 end)
 self:Paint(frame,"SetScript","OnHide",function()
  self:HideControlTooltip(frame); self:HideStudioInsertion()
  self:Paint(frame,"SetAlpha",1)
  if self.studioDragging and self.studioDragging.frame==frame then self.studioDragging=nil end
 end)
end
