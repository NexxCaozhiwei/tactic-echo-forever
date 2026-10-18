local _,T=...
local U,S,C=T.UI,T.Safety,T.APL.Custom
local function bounded(raw,limit)
 local n=S.Public(raw,"number"); return n and n>=0 and n<=limit and n%1==0 and n or nil
end
local function encode(value)
 if type(value)~="table" then return type(value) .. ":" .. tostring(value) end
 local keys={}; for k in pairs(value) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local parts={}; for _,key in ipairs(keys) do parts[#parts+1]=encode(key) .. "=" .. encode(value[key]) end
 return "{" .. table.concat(parts,";") .. "}"
end
function U:ConditionCategory(kind)
 if kind=="cdmBuff" or kind=="cdmCooldown" then return "CDM" end
 if kind=="range" or kind=="distance" or kind=="targetType" then return "目标" end
 if kind=="moving" or kind=="comboPoints" or kind=="lossOfControl" then return "玩家" end
 if kind=="combat" or kind=="enemies" or kind=="nearbyEnemies" then return "战斗" end
 return "技能"
end
function U:OpenStudioConditionPicker()
 if not self.strategyKindTarget then return end
 self.studioConditionFilter=""; self:Paint(self.studioConditionSearch,"SetText","")
 self:StudioAnchor(self.strategyKindMenu,self.studioInspector,16,-100,390,324)
 self:RefreshStrategyKinds(); self:Paint(self.strategyKindMenu,"Show"); self:Paint(self.strategyKindMenu,"Raise")
 self:Paint(self.studioConditionSearch,"SetFocus")
end
function U:StudioFingerprint(rows,source)
 local clean
 if source=="manual" or source=="group" then clean=T.Profiles:Clean(rows,source=="group" and 8 or 32) else clean=C.CleanRows(rows) end
 return encode(clean)
end
function U:StudioInsert(id,index)
 id=S.ID(id); if not id then return false end
 if T.APL.State.Boolean("C_SpellBook.IsSpellKnown",id)~=true then self:StudioMessage("技能库新增失败：该精确ID未确认仍已学，请刷新技能库。"); return false end
 local passive=T.APL.State.Boolean("C_Spell.IsSpellPassive",id)
 if passive~=false then self:StudioMessage("技能库新增失败：被动状态未知或为被动技能。"); return false end
 if self.groupEditing then return self:GroupAdd(id,index)
 elseif self.page=="profiles" then return self:AddSequenceSpell(id,index)
 elseif self.page=="customapl" or self.page=="maintenance" then return self:AddCustomSpell(id,index) end
 self:StudioMessage("请先选择列表循环、优先级或增益维护列表。"); return false
end
function U:RefreshStudioLibrary(force)
 if force or self.studioLibraryEngine~=self.engine or not self.studioLibraryCatalog then
  local rows,seen={},{}; local partial=false; local scanned=0
  local bank=S.Field(S.Field(Enum,"SpellBookSpellBank","table"),"Player","number")
  local spellType=S.Field(S.Field(Enum,"SpellBookItemType","table"),"Spell","number")
  local ok,raw=S.Call("C_SpellBook.GetNumSpellBookSkillLines"); local count=ok and bounded(raw,16)
  if not count or bank==nil or spellType==nil then partial=true else
   for line=1,count do
    local got,info=S.Call("C_SpellBook.GetSpellBookSkillLineInfo",line)
    local offset=got and bounded(S.Field(info,"itemIndexOffset","number"),2048)
    local size=got and bounded(S.Field(info,"numSpellBookItems","number"),256)
    if not offset or not size or scanned+size>2048 then partial=true; break end
    for slot=offset+1,offset+size do
     scanned=scanned+1
     local read,item=S.Call("C_SpellBook.GetSpellBookItemInfo",slot,bank)
     local kind=read and S.Field(item,"itemType","number")
     if kind==spellType then
      local id=S.ID(S.Field(item,"spellID","number"))
      local passive=S.Field(item,"isPassive","boolean")
      local known=id and T.APL.State.Boolean("C_SpellBook.IsSpellKnown",id)
      if not id or passive==nil or known==nil then partial=true end
      if id and not seen[id] and passive==false and known==true then
       local view=S.Spell(id,"技能 " .. id)
       if view.reason=="PUBLIC" then
        local rank=bounded(S.Field(item,"rank","number"),100)
        local nameFn=S.Resolve("C_SpellBook.GetSpellBookItemName")
        local nameOK,bookName,rankText
        if nameFn then nameOK,bookName,rankText=pcall(nameFn,slot,bank) end
        bookName=nameOK and S.Public(bookName,"string"); rankText=nameOK and S.Public(rankText,"string")
        local textRank=bookName==view.name and rankText and tonumber(rankText:match("^Rank (%d+)$") or rankText:match("^等级 (%d+)$"))
        if rank and textRank and rank~=textRank then rank=nil elseif not rank then rank=bounded(textRank,100) end
        rows[#rows+1]={spellID=id,name=view.name,icon=view.icon,rank=rank and rank>=1 and rank or nil}; seen[id]=true
       else partial=true end
      elseif not id then partial=true end
     elseif kind==nil then partial=true end
    end
   end
  end
  table.sort(rows,function(a,b) if a.name==b.name then return a.spellID<b.spellID end; return a.name<b.name end)
  self.studioLibraryCatalog=rows; self.studioLibraryEngine=self.engine; self.studioLibraryPartial=partial
 end
 local got,raw=self:Invoke(self.studioLibrarySearch,"GetText"); local query=(got and S.Public(raw,"string") or ""):lower()
 if self.studioLibraryOnlyBar and (force or not self.studioLibraryBarIDs or self.studioLibraryBarEngine~=self.engine) then
  local ids={}
  -- 仅在开启筛选、重新打开或手动刷新时扫描；只接受现有解析器确认的精确ID。
  for slot=1,180 do
   local action=T.ActionSources:Action(slot)
   if action then ids[action.spellID]=true end
  end
  self.studioLibraryBarIDs=ids; self.studioLibraryBarEngine=self.engine
 end
 local matches={}
 for _,row in ipairs(self.studioLibraryCatalog) do
  if (not self.studioLibraryOnlyBar or self.studioLibraryBarIDs[row.spellID])
   and (query=="" or row.name:lower():find(query,1,true) or tostring(row.spellID):find(query,1,true)) then matches[#matches+1]=row end
 end
 self.studioLibraryMatches=matches
 self.studioLibraryOffset=math.max(0,math.min(self.studioLibraryOffset or 0,math.max(0,#matches-(self.studioLibraryVisible or 8))))
 self:PaintStudioLibraryRows()
end
function U:PaintStudioLibraryRows()
 local matches=self.studioLibraryMatches or {}
 local offset=self.studioLibraryOffset or 0
 for i,w in ipairs(self.studioLibraryWidgets) do
  local entry=i<=(self.studioLibraryVisible or 8) and matches[offset+i]; w.entry=entry
  self:Paint(w.frame,entry and "Show" or "Hide")
  if entry then
   self:Paint(w.icon,"SetTexture",entry.icon); self:Paint(w.name,"SetText",self:ShortLabel(entry.name,14))
   self:Paint(w.id,"SetText","ID " .. entry.spellID .. " · " .. (entry.rank and ("等级 " .. entry.rank) or "等级未知"))
   w.frame.tefTooltipTitle=entry.name; w.frame.tefTooltipBody="精确ID " .. entry.spellID .. "；点击＋追加，或拖入技能行之前。"
  end
 end
 self:Paint(self.studioLibraryInfo,"SetText",#matches .. "项" .. (self.studioLibraryOnlyBar and " · 仅动作条" or "") .. " · 滚轮或右侧滚动条" .. (self.studioLibraryPartial and " · 部分身份未知" or ""))
 self.studioLibraryScrolling=true
 self:Paint(self.studioLibraryBar,"SetMinMaxValues",0,math.max(0,#matches-(self.studioLibraryVisible or 8)))
 self:Paint(self.studioLibraryBar,"SetValue",offset)
 self.studioLibraryScrolling=false
end
function U:CloseStudioLibrary()
 self.studioLibraryOpen=false; self.studioLibraryDragging=nil
 self.studioLibraryBarIDs=nil
 self:Paint(self.studioLibrarySearch,"ClearFocus"); self:Paint(self.studioLibrary,"Hide")
 for _,w in ipairs(self.studioLibraryWidgets or {}) do self:Paint(w.frame,"SetAlpha",1) end
 self:HideStudioInsertion(); self:HideControlTooltip()

end
function U:StudioProbeRows()
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false end
 if self.groupEditing and not self:CommitGroupFields() then return false end
 local rows,source,scene=self:StudioActiveRows(); if not rows then return false end
 if #rows>(source=="group" and 8 or 16) then self:StudioMessage("草稿超过当前列表容量，请先删减后采样。"); return false end
 local clean=source=="apl" and C.CleanRows(rows) or T.Profiles:Clean(rows,source=="group" and 8 or 32)
 if not clean then self:StudioMessage("草稿无效，不能采样。"); return false end
 -- 此快照只归界面所有。readOnly禁止重新武装额度和组触发。
 local e=self.engine; local state={readOnly=true,engine=e,actions={},scene=scene,classToken=e.classToken,
  generation=e.generation,receiptSerial=e.receiptSerial or 0,revision=T.APL.State.revision or 0,
  sampledAt=T.APL.State.Time(),moving=T.APL.State.Boolean("IsPlayerMoving")}
 local fingerprint=self:StudioFingerprint(rows,source)
 local probes={}
 for i,row in ipairs(clean) do
  row.enabled=row.enabled~=false; row.moving=row.moving or "any"; row.activity=row.activity or "any"; row.distanceOp=row.distanceOp or "any"; row.cdmKind=row.cdmKind or "none"
  C.PolicyIdentities[row]=rows[i]
 end
 C:Sample(e,state,clean)
 if e~=self.engine or state.generation~=e.generation or state.receiptSerial~=(e.receiptSerial or 0) or state.revision~=(T.APL.State.revision or 0) then self.studioProbe=nil; self:StudioMessage("采样时状态发生变化，请重新采样。"); return false end
 local first
 for i,row in ipairs(clean) do
  local result,reason,status=C:Check(state,row,i)
  local label=status or (result==nil and "UNKNOWN" or result and "TRUE" or "FALSE")
  if result==true and not first then first=i end
  probes[i]={index=i,spellID=row.spellID,result=label,reason=reason or "UNKNOWN"}
 end
 local current,currentSource,currentScene=self:StudioActiveRows()
 if state.generation~=e.generation or state.receiptSerial~=(e.receiptSerial or 0) or state.revision~=(T.APL.State.revision or 0)
  or currentSource~=source or currentScene~=scene or not current or fingerprint~=self:StudioFingerprint(current,source) then
  self.studioProbe=nil; self:StudioMessage("求值期间身份或草稿发生变化，请重新采样。"); return false
 end
 self.studioProbe={engine=e,source=source,scene=scene,generation=e.generation,serial=e.receiptSerial or 0,revision=T.APL.State.revision or 0,
  fingerprint=fingerprint,rows=probes,state=state,first=first,time=state.sampledAt}
 self.studioBottomMode="trace"; self:RefreshStudio(); return true
end
function U:MaybeStudioLiveProbe()
 if not self.studioTraceLive or not self.settingsOpen then return end
 local rows=self:StudioActiveRows(); if not rows then return end
 local path=S.Resolve("GetCurrentKeyBoardFocus") and "GetCurrentKeyBoardFocus" or "GetCurrentKeyboardFocus"
 local ok,focus=S.Call(path)
 local _,why=S.Public(focus,"table")
 if not ok or why~="NO_DATA" then return end
 local now=T.APL.State.Time(); if not now then return end
 if self.studioLastProbeTime and now>=self.studioLastProbeTime and now-self.studioLastProbeTime<.20 then return end
 self.studioLastProbeTime=now
 local mode=self.studioBottomMode; self:StudioProbeRows(); self.studioBottomMode=mode
end
function U:StudioProbeCurrent()
 local p=self.studioProbe; local rows,source,scene=self:StudioActiveRows(); local e=self.engine
 if not p or not rows or p.engine~=e or p.source~=source or p.scene~=scene or p.generation~=e.generation or p.serial~=(e.receiptSerial or 0)
  or p.revision~=(T.APL.State.revision or 0) or p.fingerprint~=self:StudioFingerprint(rows,source) then return nil end
 return p
end
function U:RefreshStudioBottom()
 if not self.studioTraceWidgets then return end
 local rows,source=self:StudioActiveRows(); local p=self:StudioProbeCurrent()
 local mode=self.studioBottomMode or "trace"
 self:Paint(self.studioBottomText,mode=="trace" and "Hide" or "Show")
 self:Paint(self.studioTraceScroll,mode=="trace" and "Show" or "Hide")
 self:Paint(self.studioTraceHeader,"SetText",p and ("只读草稿采样 · " .. (p.time and (string.format("%.2f",p.time) .. "秒") or "时间未知") .. " · 仅供诊断，不授予派发资格") or "尚无对应采样／草稿已变化；点击只读采样。")
 for i,w in ipairs(self.studioTraceWidgets) do
  local row=rows and rows[i]; local probe=p and p.rows[i]
  self:Paint(w,mode=="trace" and row and "Show" or "Hide")
  if row then
   local result=probe and probe.result or "UNKNOWN"
   self:Paint(w,"SetText",string.format("%02d",i) .. " · ID " .. (row.spellID or 0) .. " · " .. result .. " · " .. (probe and probe.reason or "未采样或采样已失效"))
   w.tefTraceIdentity=p; w.tefTraceIndex=i; w.tefTooltipTitle=result; w.tefTooltipBody=probe and probe.reason or "未知不等于不满足；不会授予输入资格。"
  end
 end
 self:Paint(self.studioTraceChild,"SetHeight",math.max(32,(rows and #rows or 0)*36))
 if mode=="problems" then
  local fingerprint=rows and self:StudioFingerprint(rows,source) or ""
  if self.studioAuditFingerprint~=fingerprint or self.studioAuditEngine~=self.engine or self.studioAuditRevision~=T.APL.State.revision then
   local valid,errors,warnings=C:Audit(rows or {},self.engine)
   self.studioAuditText=(errors~="" and ("错误\n" .. errors) or "未发现可证明的条件矛盾。") .. (warnings~="" and ("\n提示\n" .. warnings) or "")
   self.studioAuditFingerprint=fingerprint; self.studioAuditEngine=self.engine; self.studioAuditRevision=T.APL.State.revision
  end
  self:Paint(self.studioBottomText,"SetText",self.studioAuditText)
 elseif mode=="output" then self:Paint(self.studioBottomText,"SetText",C:Timeline(self.engine)) end
 local ok,text=self:Invoke(self.studioBottomText,"GetText"); text=ok and S.Public(text,"string") or ""
 local _,lines=text:gsub("\n","\n"); self:Paint(self.studioTextChild,"SetHeight",math.max(40,(lines+2)*20))
 for key,button in pairs(self.studioBottomTabs) do button.tefControlSelected=key==mode; self:SetControlEnabled(button,true) end
 self.studioLiveButton.tefControlSelected=self.studioTraceLive==true; self:SetControlEnabled(self.studioLiveButton,true)
 if self.studioBottomHeight then self:LayoutStudioBottom(self.studioEditorWidth or 600,self.studioBottomHeight) end
end
function U:LayoutStudioBottom(width,height)
 self.studioBottomHeight=height
 self:Paint(self.studioTextChild,"SetWidth",width-48)
 self:Paint(self.studioBottomText,"SetWidth",width-48)
 self:Paint(self.studioTextScroll,"SetSize",width-44,math.max(24,height-48))
 self:Paint(self.studioTraceScroll,"SetSize",width-44,math.max(24,height-72))
 self:Paint(self.studioTraceChild,"SetWidth",width-48)
 for _,w in ipairs(self.studioTraceWidgets) do self:Paint(w,"SetWidth",width-48) end
 self:StudioAnchor(self.studioSampleButton,self.studioBottom,width-136,-4,120,28)
 self:Paint(self.studioTextScroll,(self.studioBottomMode or "trace")~="trace" and "Show" or "Hide")
 self:Paint(self.studioTraceScroll,(self.studioBottomMode or "trace")=="trace" and height>=100 and "Show" or "Hide")
 self:Paint(self.studioTraceHeader,(self.studioBottomMode or "trace")=="trace" and "Show" or "Hide")
end
function U:LayoutStudioLibrary(left,height)
 local h=math.min(680,height-80)
 self.studioLibraryVisible=math.max(1,math.min(8,math.floor((h-192)/56)))
 self.studioLibraryOffset=math.max(0,math.min(self.studioLibraryOffset or 0,math.max(0,#(self.studioLibraryMatches or {})-self.studioLibraryVisible)))
 self:Paint(self.studioLibraryBar,"SetHeight",math.max(32,self.studioLibraryVisible*56-32))
 self:PaintStudioLibraryRows()
 -- 浮窗位于右侧，可拖动；单一滚动偏移同时驱动滚轮与滑块。
 if not self.studioLibraryMoved then
  self:Paint(self.studioLibrary,"ClearAllPoints")
  self:Paint(self.studioLibrary,"SetPoint","TOPRIGHT",self.settings,"TOPRIGHT",-12,-72)
 end
 self:Paint(self.studioLibrary,"SetSize",360,h)
 self:Paint(self.studioLibrary,"SetFrameStrata","DIALOG")
 self:Paint(self.studioLibrary,"SetFrameLevel",60)
 self:Paint(self.studioLibrary,self.studioLibraryOpen and "Show" or "Hide")
end
function U:CreateStudioTools()
 self:Paint(self.strategyKindMenu,"SetSize",390,324)
 self.studioConditionSearch=self:SequenceInput(self.strategyKindMenu,8,-12,370); self:Paint(self.studioConditionSearch,"SetMaxLetters",80)
 self:BindControlTooltip(self.studioConditionSearch,"搜索条件","可按条件名称、字段名或技能／目标／玩家／战斗／CDM分类搜索。")
 self:Paint(self.studioConditionSearch,"SetScript","OnTextChanged",function()
  local ok,raw=self:Invoke(self.studioConditionSearch,"GetText"); self.studioConditionFilter=(ok and S.Public(raw,"string") or ""):lower(); self:RefreshStrategyKinds()
 end)
 self:Paint(self.strategyKindMenu,"SetScript","OnHide",function() self:Paint(self.studioConditionSearch,"ClearFocus"); self:HideControlTooltip() end)
 local ok,scroll=self:Invoke(self.strategyKindChild,"GetParent")
 if ok and scroll then self:StudioAnchor(scroll,self.strategyKindMenu,8,-52,344,264) end
 for _,button in pairs(self.strategyKindButtons) do self:Paint(button,"SetWidth",340) end
 self:Paint(self.strategyKindChild,"SetWidth",340)
 self.studioLibrary=self:CreateStudioPanel(self.settings); self:Paint(self.studioLibrary,"EnableMouse",true)
 self:Paint(self.studioLibrary,"SetBackdropColor",.025,.055,.095,1)
 self:Paint(self.studioLibrary,"SetBackdropBorderColor",.34,.58,.78,1)
 self:BindControlTooltip(self.studioLibrary,"已学技能库","只收录公开确认的精确已学主动技能；新学技能后点击刷新。")
 self:Paint(self:Text(self.studioLibrary,12,-12,224,"GameFontNormal"),"SetText","已学主动技能 · 精确ID")
 self:CreateActionButton(self.studioLibrary,"关闭",276,-8,72,function() self:CloseStudioLibrary(); self:LayoutSettings() end)
 self:CreateHintText(self.studioLibrary,"搜索技能名或SpellID",12,-52,280)
 self.studioLibrarySearch=self:SequenceInput(self.studioLibrary,12,-76,248); self:Paint(self.studioLibrarySearch,"SetMaxLetters",80)
 self:Paint(self.studioLibrarySearch,"SetScript","OnTextChanged",function() self.studioLibraryOffset=0; if self.studioLibraryCatalog then self:RefreshStudioLibrary(false) end end)
 self:CreateActionButton(self.studioLibrary,"刷新",272,-76,76,function() self:RefreshStudioLibrary(true) end)
 self:Paint(self:Text(self.studioLibrary,12,-118,240),"SetText","仅显示动作条上的技能")
 -- 纯视图开关，不使用会标记技能组草稿变更的策略开关。
 self.studioLibraryBarToggle=self:CreateActionButton(self.studioLibrary,"关闭",263,-112,85,function()
  self.studioLibraryOnlyBar=not self.studioLibraryOnlyBar; self.studioLibraryBarIDs=nil; self.studioLibraryOffset=0
  self:RefreshStudioLibrary(false)
 end)
 local function syncBarFilter()
  local enabled=self.studioLibraryOnlyBar==true
  self.studioLibraryBarToggle.tefControlSelected=enabled
  self:Paint(self.studioLibraryBarToggle,"SetText",enabled and "开启" or "关闭")
  self:SetControlEnabled(self.studioLibraryBarToggle,true)
 end
 self:AddControlSync(syncBarFilter,self.studioLibraryBarToggle); syncBarFilter()
 self:BindControlTooltip(self.studioLibraryBarToggle,"仅显示动作条上的技能","按精确技能ID筛选，包含现有解析器能核对的宏技能；未知身份不收录。移动技能后点击刷新。")
 self.studioLibraryInfo=self:Text(self.studioLibrary,12,-152,336,"GameFontHighlightSmall")
 self:Paint(self.studioLibrary,"SetMovable",true); self:Paint(self.studioLibrary,"SetClampedToScreen",true)
 local drag=self:Frame("Frame",self.studioLibrary); self:StudioAnchor(drag,self.studioLibrary,0,0,264,40)
 self:Paint(drag,"EnableMouse",true); self:Paint(drag,"RegisterForDrag","LeftButton")
 self:Paint(drag,"SetScript","OnDragStart",function() self:Paint(self.studioLibrary,"StartMoving") end)
 self:Paint(drag,"SetScript","OnDragStop",function() self:Paint(self.studioLibrary,"StopMovingOrSizing"); self.studioLibraryMoved=true end)
 self.studioLibraryChild=self:Frame("Frame",self.studioLibrary); self:StudioAnchor(self.studioLibraryChild,self.studioLibrary,12,-180,312,448)
 self.studioLibraryBar=self:Frame("Slider",self.studioLibrary,"UIPanelScrollBarTemplate")
 self:StudioAnchor(self.studioLibraryBar,self.studioLibrary,336,-196,16,416)
 self:Paint(self.studioLibraryBar,"SetValueStep",1); self:Paint(self.studioLibraryBar,"SetObeyStepOnDrag",true)
 self:Paint(self.studioLibraryBar,"SetScript","OnValueChanged",function(_,value)
  value=S.Public(value,"number"); if self.studioLibraryScrolling or not value then return end
  self.studioLibraryOffset=math.floor(value+.5); self:PaintStudioLibraryRows()
 end)
 self:Paint(self.studioLibrary,"EnableMouseWheel",true)
 self:Paint(self.studioLibrary,"SetScript","OnMouseWheel",function(_,delta)
  delta=S.Public(delta,"number"); if not delta then return end
  self.studioLibraryOffset=math.max(0,math.min((self.studioLibraryOffset or 0)-delta,math.max(0,#(self.studioLibraryMatches or {})-(self.studioLibraryVisible or 8))))
  self:PaintStudioLibraryRows()
 end)
 self.studioLibraryWidgets={}
 for i=1,8 do
  local frame=self:CreateStudioPanel(self.studioLibraryChild); self:StudioAnchor(frame,self.studioLibraryChild,0,-(i-1)*56,312,52)
  self:Paint(frame,"SetBackdropColor",.07,.11,.17,1)
  self:Paint(frame,"SetBackdropBorderColor",.22,.35,.48,1)
  local ok,icon=self:Invoke(frame,"CreateTexture",nil,"ARTWORK"); if ok then self:StudioAnchor(icon,frame,8,-8,32,32) end
  local w={frame=frame,icon=icon,name=self:Text(frame,48,-6,216),id=self:Text(frame,48,-28,216,"GameFontHighlightSmall")}
  self:Paint(w.name,"SetWordWrap",false)
  self:CreateActionButton(frame,"＋",272,-10,32,function() if w.entry then self:StudioInsert(w.entry.spellID) end end)
  self:Paint(frame,"EnableMouse",true); self:Paint(frame,"RegisterForDrag","LeftButton")
  self:BindControlTooltip(frame,"已学技能","点击＋追加，拖入主编辑器插入；不会改变技能绑定。")
  self:Paint(frame,"SetScript","OnDragStart",function() if w.entry then self.studioLibraryDragging=w.entry.spellID; self:Paint(frame,"SetAlpha",.5) end end)
  self:Paint(frame,"SetScript","OnDragStop",function() self:Guard(function()
   local id=self.studioLibraryDragging; self.studioLibraryDragging=nil; self:Paint(frame,"SetAlpha",1); self:HideStudioInsertion()
   local _,source=self:StudioActiveRows(); local index=self:StudioDropTarget(source)
   local overOK,over=S.Call("MouseIsOver",self.studioLibrary); if overOK and S.Public(over,"boolean")==true then index=nil end
   if id and index then self:StudioInsert(id,index) else self:StudioMessage("已取消技能库拖动，草稿保持。"); end
  end) end)
  self.studioLibraryWidgets[i]=w
 end
 self.studioBottomTabs={}
 for i,entry in ipairs({{"trace","APL TRACE"},{"problems","问题"},{"output","输出"}}) do
  local key=entry[1]; self.studioBottomTabs[key]=self:CreateActionButton(self.studioBottom,entry[2],8+(i-1)*116,-4,108,function() self.studioBottomMode=key; self.studioBottomExpanded=true; self:RefreshStudioBottom(); self.settingsLayoutSignature=nil; self:LayoutSettings() end)
  self:CompactControl(self.studioBottomTabs[key],108)
 end
 self.studioSampleButton=self:CreateActionButton(self.studioBottom,"只读采样",420,-4,120,function() self:StudioProbeRows() end); self:CompactControl(self.studioSampleButton,120)
 self.studioLiveButton=self:CreateActionButton(self.studioBottom,"实时：关",360,-4,80,function()
  self.studioTraceLive=not self.studioTraceLive; self:Paint(self.studioLiveButton,"SetText",self.studioTraceLive and "实时：开" or "实时：关")
  if self.studioTraceLive then self:StudioProbeRows() end
 end); self:CompactControl(self.studioLiveButton,80)
 self:BindControlTooltip(self.studioLiveButton,"只读实时追踪","复用现有心跳，最多每0.20秒采样一次；输入框有焦点或焦点未知时暂停，不改变运行候选和额度。")
 self.studioTraceHeader=self:Text(self.studioBottom,12,-40,800,"GameFontHighlightSmall")
 self.studioTraceScroll=self:Frame("ScrollFrame",self.studioBottom,"UIPanelScrollFrameTemplate"); self:StudioAnchor(self.studioTraceScroll,self.studioBottom,12,-64,540,80)
 self.studioTraceChild=self:Frame("Frame",self.studioTraceScroll); self:Paint(self.studioTraceScroll,"SetScrollChild",self.studioTraceChild)
 self.studioTraceWidgets={}
 for i=1,16 do
  local index=i; local row=self:CreateActionButton(self.studioTraceChild,"",0,-(i-1)*36,540,function()
   local current=self:StudioProbeCurrent(); local widget=self.studioTraceWidgets[index]
   if not current or widget.tefTraceIdentity~=current then self:StudioMessage("采样对应的草稿已变化，请重新采样后定位。"); return end
   self:SelectStudioRule(current.source,index)
  end)
  self:ApplyControlFont(row,true,12); self.studioTraceWidgets[i]=row
  local ok,font=self:Invoke(row,"GetFontString"); if ok and font then self:Paint(font,"SetWordWrap",false); self:Paint(font,"SetJustifyH","LEFT") end
 end
 self.studioTextScroll=self:Frame("ScrollFrame",self.studioBottom,"UIPanelScrollFrameTemplate"); self:StudioAnchor(self.studioTextScroll,self.studioBottom,12,-44,540,100)
 local child=self:Frame("Frame",self.studioTextScroll); self.studioTextChild=child; self:Paint(self.studioTextScroll,"SetScrollChild",child)
 self.studioBottomText=self:Text(child,0,0,530,"GameFontHighlightSmall")
 self:Paint(child,"SetSize",540,1200)
end
