local _,T=...
local U,S,C=T.UI,T.Safety,T.APL.Custom
function U:CustomMessage(text) if self.strategySource=="manual" then self:SequenceMessage(text) else self:Paint(self.customMessage,"SetText",text) end end
function U:CustomRow() if self.strategySource=="manual" then return self.sequencePolicyRow end; return self.customDraft and self.customDraft[self.customSelected or 1] end
function U:CommitCustomNumbers()
 local pending={}
 for _,entry in ipairs(self.strategyInputs or {}) do
  local ok,raw=self:Invoke(entry.box,"GetText"); local text=ok and S.Public(raw,"string")
  if not text then return false end
  text=text:match("^%s*(.-)%s*$")
  local n=text~="" and text:match("^%d+%.?%d*$") and tonumber(text) or nil
  local limit=entry.field=="spellID" and 2147483647 or entry.field=="radius" and 40 or entry.condition.kind=="distance" and 2000 or entry.condition.kind=="cdmStacks" and 255 or entry.condition.kind=="comboPoints" and 10 or 40
  if text~="" and (not n or n>limit or (entry.condition.kind~="distance" and entry.field~="radius" and n%1~=0) or ((entry.field=="spellID" or entry.field=="radius") and n<=0)) then
   self:CustomMessage("数值无效：距离0～2000码、敌人数0～40整数、层数0～255整数、连击点0～10整数，观察技能填写精确ID。"); return false
  end
  pending[#pending+1]={condition=entry.condition,field=entry.field,value=n}
 end
 for _,entry in ipairs(pending) do entry.condition[entry.field]=entry.value end
 if self:StoreSequencePolicy()==false then self:CustomMessage("策略条件无效：请检查范围上下限或清空条件后重建。"); return false end
 return true
end
function U:RefreshCustomAPL()
 if self.strategySource=="manual" then self:RefreshStrategyForm(); return end
 local e=self.engine
 local maintenance=self.page=="maintenance"
 if self.customEngine~=e then self.customScene=e.db.selectedPlans.apl end
 local scene=maintenance and "maintenance" or self.customScene or "single"
 if not self.customDraft or self.customEngine~=e or self.customClass~=e.classToken or self.customLoadedScene~=scene then
  self.customEngine=e
  self.customClass,self.customLoadedScene=e.classToken,scene
  self.customMaintenanceMode=maintenance
  self.customDraft=C.CleanRows(maintenance and T.Maintenance:Rows(e) or C:Rows(e,scene)); self.customSelected=1; self.customFormIndex=nil; self.strategyInputs={}; self:Paint(self.strategyPanel,"Hide")
  for _,row in ipairs(self.customDraft) do C:UpgradeStrategies(row) end
 end
 self:Paint(self.readouts.customapl,"SetText",(e.classToken or "职业未知") .. " · 编辑" .. T.Profiles:PlanName(scene,e,"apl") .. " · 当前使用：" .. T.Profiles:PlanName(e.scene,e,T.Recommendation:Source(e)) .. " · " .. #self.customDraft .. "/16条")
 for i,w in ipairs(self.customWidgets) do
  local row=self.customDraft[i]; self:Paint(w.frame,row and "Show" or "Hide")
  if row then
   local view=S.Spell(row.spellID,tostring(row.spellID or "未解析"))
   self:Paint(w.name,"SetText",(i==self.customSelected and "|cffffcf45" or "") .. i .. ". " .. view.name .. " · ID " .. (row.spellID or "?") .. (row.enabled and "" or " · 已停用") .. "|r")
   local sampled=self.engine.aplSnapshot and self.engine.aplSnapshot.actions["custom_" .. i]
   if sampled and sampled.spellID==row.spellID and sampled.reason=="CUSTOM_TARGET_UNKNOWN" then self:Paint(w.name,"SetText",i .. ". " .. view.name .. " |cffffcf45· 请选择施放类型|r") end
  end
 end
 self:Paint(self.customChild,"SetHeight",math.max(108,#self.customDraft*36))
 self:RefreshStrategyForm()
 if maintenance then self:Paint(self.readouts.customapl,"SetText",(e.classToken or "职业未知") .. " · 增益维护 · " .. #self.customDraft .. "/16个增益／解控技能") end
 for _,button in pairs(self.customPlanControls or {}) do self:Paint(button,maintenance and "Hide" or "Show") end
 self:Paint(self.planRenameBoxes.apl.frame,maintenance and "Hide" or "Show"); self:Paint(self.customUseButton,maintenance and "Hide" or "Show")
 self:Paint(self.maintenanceHint,maintenance and "Show" or "Hide")
 self:Paint(self.customEnableLabel,"SetText",maintenance and "启用增益维护" or "启用本方案")
end
function U:AddCustomSpell(id)
 if not self.customDraft then self:RefreshCustomAPL() end
 id=S.ID(id); if not id then self:CustomMessage("请输入公开合法技能ID。"); return false end
 if self.page=="maintenance" and not T.Maintenance:BuffSpell(id) then self:CustomMessage("仅支持可确认的增益或已支持的解控法术；治疗、伤害、造物和位移不能加入。"); return false end
 if not self:CommitCustomNumbers() then return false end
 if #self.customDraft>=16 then self:CustomMessage("最多16条规则。"); return false end
 self.customDraft[#self.customDraft+1]={spellID=id,enabled=true,moving="any",activity="any",distanceOp="any",cdmKind="none",experimentalEnemies=false,strategies={}}
 if self.page=="maintenance" then
  local condition=T.Maintenance.ControlBreakers[id] and {kind="lossOfControl",control="stun",value=true} or {kind="cdmBuff",value=false,spellID=id}
  self.customDraft[#self.customDraft].strategies={{mode="use",conditions={condition}}}
 end
 self.customSelected=#self.customDraft; self.customFormIndex=nil; self:RefreshCustomAPL(); self:CustomMessage("已加入草稿；保存后生效。自动无法识别目标类型时，请编辑施放类型。"); return true
end
function U:ReceiveCustomSpell()
 local id,why=T.ActionSources:Cursor()
 if why=="NO_DATA" then return false end
 if not id then self.engine:Log("display",why or "CUSTOM_CURSOR_ID_UNVERIFIED"); self:CustomMessage("技能或宏ID未确认：" .. (why or "UNKNOWN") .. "；可手输精确ID。"); return false end
 if not self:AddCustomSpell(id) then return false end
 S.Call("ClearCursor"); self:Refresh(); return true
end
function U:CreateCustomAPLEditor(parent)
 self:Paint(parent,"EnableMouse",true)
 self:Paint(parent,"SetScript","OnReceiveDrag",function() self:Guard(function() self:ReceiveCustomSpell() end) end)
 local function action(text,x,y,w,fn) return self:CreateActionButton(parent,text,x,y,w,fn) end
 self.customScene=self.customScene or "single"
 self.customPlanControls=self:CreateSegmentedControl(parent,{{"single","方案一"},{"multi","方案二"},{"third","方案三"}},0,-30,550,
  function() return self.customScene end,function(key) if self:CommitCustomNumbers() then self.customScene=key; self:RefreshCustomAPL() end end)
 self:CreatePlanRename(parent,"apl",0,-76,function() return self.customScene end)
 self.customEnableButton,self.customEnableLabel=self:CreateToggleRow(parent,"启用本方案",0,-116,250,
  function() return self.page=="maintenance" and T.Maintenance:Enabled(self.engine) or (self.page~="maintenance" and self.engine.db.enabledPlans.apl[self.customScene]) end,
  function(value) if self.page=="maintenance" then T.Maintenance:SetEnabled(self.engine,value) else T.Profiles:SetPlanEnabled(self.engine,"apl",self.customScene,value) end end)
 self.maintenanceHint=self:CreateHintText(parent,"优先于战斗来源；脱战需要手动开启派发。增益默认检查CDM未活动；生存意志1259718默认昏迷存在。按行优先，未知不派发。",0,-32,550)
 self:Paint(self.maintenanceHint,"Hide")
 self.customUseButton=action("使用本方案",280,-116,120,function()
  local ok,reason=T.Profiles:UsePlan(self.engine,"apl",self.customScene)
  self:CustomMessage(ok and "已选择并停止派发；关闭设置后开启。" or "请先启用本方案。")
 end)
 self.customID=self:SequenceInput(parent,160,-150,90)
 action("ID新增",265,-150,80,function()
  local ok,raw=self:Invoke(self.customID,"GetText"); local text=ok and S.Public(raw,"string")
  self:AddCustomSpell(text and text:match("^%d+$") and tonumber(text))
 end)
 local drop=action("拖入技能",0,-150,140,function() self:ReceiveCustomSpell() end)
 self.customDrop=drop
 self:Paint(drop,"RegisterForDrag","LeftButton")
 self:Paint(drop,"RegisterForClicks","LeftButtonUp")
 self:Paint(drop,"EnableMouse",true)
 self:Paint(drop,"SetScript","OnReceiveDrag",function()
  self:Guard(function()
   self:ReceiveCustomSpell()
  end)
 end)
 self.customSave=action("保存配置",435,-116,140,function()
  if not self:CommitCustomNumbers() then return end
  if self.page=="maintenance" then local ok,reason=T.Maintenance:Save(self.engine,self.customDraft); self:CustomMessage(ok and "增益维护已保存并停止派发；关闭设置后手动开启。" or reason); return end
  local ok,reason=C:Save(self.engine,self.customDraft,self.customLoadedScene,self.customClass)
  if ok and self.engine.db.enabledPlans.apl[self.customLoadedScene] then ok,reason=T.Profiles:UsePlan(self.engine,"apl",self.customLoadedScene) end
  self:CustomMessage(ok and "已保存并停止派发；关闭设置后主动开启。" or (reason or "保存失败"))
 end)
 self:CreateSectionCard(parent,"技能列表 · 拖动条目或用上下箭头排序",0,-190,575,450)
 for _,edge in ipairs({{0,-190,575,2},{0,-638,575,2},{0,-190,2,450},{573,-190,2,450}}) do
  local ok,line=self:Invoke(parent,"CreateTexture",nil,"BORDER")
  if ok then self:Paint(line,"SetPoint","TOPLEFT",parent,"TOPLEFT",edge[1],edge[2]); self:Paint(line,"SetSize",edge[3],edge[4]); self:Paint(line,"SetColorTexture",.25,.45,.60,1) end
 end
 local scroll=self:Frame("ScrollFrame",parent,"UIPanelScrollFrameTemplate")
 self:Paint(scroll,"SetPoint","TOPLEFT",parent,"TOPLEFT",10,-227); self:Paint(scroll,"SetSize",540,390)
 local child=self:Frame("Frame",scroll); self.customChild=child; self:Paint(child,"SetSize",530,108); self:Paint(scroll,"SetScrollChild",child)
 self.customWidgets={}
 for i=1,16 do
  local index=i; local frame=self:Frame("Frame",child,"BackdropTemplate")
  self:Paint(frame,"SetPoint","TOPLEFT",child,"TOPLEFT",0,-(i-1)*36); self:Paint(frame,"SetSize",530,32)
  self:Paint(frame,"EnableMouse",true)
  self:Paint(frame,"SetScript","OnReceiveDrag",function() self:Guard(function() self:ReceiveCustomSpell() end) end)
  self:Paint(frame,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
  self:Paint(frame,"SetBackdropColor",.05,.08,.12,1); self:Paint(frame,"SetBackdropBorderColor",.25,.42,.58,1)
  self:Paint(frame,"RegisterForDrag","LeftButton")
  self:Paint(frame,"SetScript","OnDragStart",function() self:Guard(function()
   if self:CommitCustomNumbers() then self.customDragging=index; self:Paint(frame,"SetAlpha",.5); self:CustomMessage("松开鼠标，将技能移到指向条目的位置。") end
  end) end)
  self:Paint(frame,"SetScript","OnDragStop",function() self:Guard(function()
   local source=self.customDragging; self.customDragging=nil; self:Paint(frame,"SetAlpha",1)
   if not source then return end
   for target,w in ipairs(self.customWidgets) do
    local ok,raw=S.Call("MouseIsOver",w.frame)
    if ok and S.Public(raw,"boolean")==true and self.customDraft[target] then self:ReorderCustomRule(source,target); break end
   end
  end) end)
  local name=self:Text(frame,6,-7,278,"GameFontHighlightSmall")
  self:Paint(name,"SetWordWrap",false)
  self:CreateActionButton(frame,"编辑策略",290,-2,80,function() if self:CommitCustomNumbers() then self.strategySource=self.page=="maintenance" and "maintenance" or "apl"; self.customSelected=index; self.customFormIndex=nil; self:RefreshCustomAPL(); self:Paint(self.strategyPanel,"Show") end end)
  self:CreateActionButton(frame,"↑",376,-2,38,function() self:MoveCustomRule(index,-1) end)
  self:CreateActionButton(frame,"↓",420,-2,38,function() self:MoveCustomRule(index,1) end)
  self:CreateActionButton(frame,"删",464,-2,52,function()
   if self:CommitCustomNumbers() then table.remove(self.customDraft,index); self.customSelected=math.min(index,math.max(1,#self.customDraft)); self.customFormIndex=nil; self:RefreshCustomAPL() end
  end)
  self.customWidgets[i]={frame=frame,name=name}
 end
 self.customMessage=self:Text(parent,0,-652,570,"GameFontHighlightSmall")
 self:CreateStrategyPanel()
 self:CustomMessage("从上往下检查；使用条件全部满足，否则检查下一技能。")
end
function U:MoveCustomRule(index,direction)
 if not self:CommitCustomNumbers() then return end
 local other=index+direction
 if other<1 or other>#self.customDraft then return end
 self.customDraft[index],self.customDraft[other]=self.customDraft[other],self.customDraft[index]
 self.customSelected=other; self.customFormIndex=nil; self:RefreshCustomAPL()
end

function U:ReorderCustomRule(index,other)
 if not self:CommitCustomNumbers() or not self.customDraft[index] or not self.customDraft[other] then return end
 local row=table.remove(self.customDraft,index); table.insert(self.customDraft,other,row)
 self.customSelected=other; self.customFormIndex=nil; self:RefreshCustomAPL()
end
local strategyKinds={"comboPoints","lossOfControl","usable","range","distance","moving","enemies","cdmCooldown","cdmBuff","cooldown","combat","targetType","learned","succeeded","cdmStacks","nearbyEnemies"}
local strategyNames={comboPoints="连击点数",lossOfControl="自身失控类型",usable="技能可用性",range="技能范围",distance="目标距离",moving="移动状态",enemies="可见敌人数",cdmCooldown="CDM冷却状态",cdmBuff="CDM增益状态",cooldown="技能是否CD",combat="战斗状态",targetType="当前目标类型",learned="指定技能已学",succeeded="精确成功使用记录",cdmStacks="CDM增益层数",rangedEnemies="自身范围内可见敌人数",nearbyEnemies="自身范围内可见敌人数"}
function U:RefreshStrategyKinds()
 local count=0
 for _,kind in ipairs(strategyKinds) do
  local button=self.strategyKindButtons and self.strategyKindButtons[kind]
  if button then
   if kind=="comboPoints" and self.engine.classToken~="ROGUE" then self:Paint(button,"Hide")
   else self:Paint(button,"Show"); self:Paint(button,"ClearAllPoints"); self:Paint(button,"SetPoint","TOPLEFT",self.strategyKindChild,"TOPLEFT",0,-count*30); count=count+1 end
  end
 end
 self:Paint(self.strategyKindChild,"SetHeight",math.max(30,count*30))
end
function U:ChangeCustomStrategy(callback)
 if not self:CommitCustomNumbers() then return end
 local row=self:CustomRow(); if not row then return end
 row.strategies=row.strategies or {}; callback(row)
 self:StoreSequencePolicy()
 self.customFormIndex=nil; self:RefreshCustomAPL()
end
function U:ReplaceStrategySpell(rawID)
 local id=S.ID(rawID)
 if not id or id==7268 or id==61304 then self:CustomMessage("替换失败：请提供有效的精确技能ID。"); return false end
 if not self:CommitCustomNumbers() then return false end
 local row=self:CustomRow(); if not row then return false end
 if T.APL.State.Boolean("C_SpellBook.IsSpellKnown",id)~=true then self:CustomMessage("替换失败：新技能的精确ID尚未公开确认已学。"); return false end
 local view=S.Spell(id,tostring(id))
 if view.reason~="PUBLIC" then self:CustomMessage("替换失败：新技能信息未公开确认。"); return false end
 local action=C:Read(id,false,row.targetMode)
 if action.reason=="CUSTOM_PASSIVE_SPELL" or action.reason=="CUSTOM_PASSIVE_UNKNOWN" then self:CustomMessage("替换失败：新技能为被动或被动状态未知。"); return false end
 local maintenance=self.strategySource=="maintenance" or (self.strategySource~="manual" and self.page=="maintenance")
 if maintenance then
  if not T.Maintenance:BuffSpell(id) then self:CustomMessage("替换失败：增益维护仅接受支持的增益或解控技能。"); return false end
  for _,other in ipairs(self.customDraft or {}) do if other~=row and other.spellID==id then self:CustomMessage("替换失败：增益维护中已有该精确ID。"); return false end end
 end
 if self.strategySource=="manual" then
  local rows=self:DraftRows(); local current=rows and rows[self.sequencePolicyIndex]
  if not current or current.spellID~=row.spellID then self:CustomMessage("替换失败：当前草稿已变化，请重新打开策略。"); return false end
  current.spellID=id; current.name=view.name; current.matchIDs={id}
  self.sequencePolicyRow=current; self:WriteDraft(rows)
 else row.spellID=id; row.invalid=nil end
 self.customFormIndex=nil; self:RefreshCustomAPL()
 self:CustomMessage("已更换草稿技能，保留策略及显式观察ID；点击保存后生效。"); return true
end
function U:UpgradeStrategySpell()
 if not self:CommitCustomNumbers() then return false end
 local row=self:CustomRow(); if not row then return false end
 local id,reason,rank=T.APL.State.HighestLearnedRank(row.spellID)
 if not id then self:CustomMessage("未更换：无法唯一确认已学最高等级（" .. (reason or "UNKNOWN") .. "）。"); return false end
 if id==row.spellID then self:CustomMessage("当前已是法术书确认的最高已学等级。" ); return true end
 if not self:ReplaceStrategySpell(id) then return false end
 self:CustomMessage("已替换为法术书确认的等级" .. rank .. "，策略保留；点击保存生效。"); return true
end
function U:ReceiveStrategySpell()
 local id,why=T.ActionSources:Cursor()
 if not id then self:CustomMessage("替换失败：拖入技能的精确ID未确认（" .. (why or "UNKNOWN") .. "）。"); return false end
 if not self:ReplaceStrategySpell(id) then return false end
 S.Call("ClearCursor"); return true
end
function U:RefreshStrategyForm()
 if not self.strategyPanel then return end
 local row=self:CustomRow()
 self:Paint(self.strategyTitle,"SetText",row and ("策略条件设置 · " .. S.Spell(row.spellID,tostring(row.spellID)).name) or "策略条件设置 · 未选择技能")
 if self.customFormIndex==self.customSelected then return end
 self.customFormIndex=self.customSelected
 self:Paint(self.strategyKindMenu,"Hide")
 if self.strategyForm then self:Paint(self.strategyForm,"Hide") end
 if self.strategyFormControls then
  local keep={}; for _,sync in ipairs(self.controls) do if not self.strategyFormControls[sync] then keep[#keep+1]=sync end end
  self.controls=keep
 end
 local first=#self.controls
 local form=self:Frame("Frame",self.strategyScroll); self.strategyForm=form
 self:Paint(form,"SetSize",390,100); self:Paint(self.strategyScroll,"SetScrollChild",form)
 self.strategyInputs={}; self.customNumbers={}
 local y=0
 if row then
  self:CreateHintText(form,"更换当前技能（保留策略条件）",0,y,390); y=y-28
  self.strategySpellID=self:SequenceInput(form,0,y,110); self:Paint(self.strategySpellID,"SetText",tostring(row.spellID))
  self.strategyReplaceID=self:CreateActionButton(form,"ID替换",122,y,100,function()
   local ok,raw=self:Invoke(self.strategySpellID,"GetText"); local text=ok and S.Public(raw,"string")
   self:ReplaceStrategySpell(text and text:match("^%s*(%d+)%s*$") and tonumber(text))
  end)
  self.strategyReplaceDrop=self:CreateActionButton(form,"拖入替换",234,y,150,function() self:ReceiveStrategySpell() end)
  self:Paint(self.strategyReplaceDrop,"SetScript","OnReceiveDrag",function() self:Guard(function() self:ReceiveStrategySpell() end) end)
  y=y-40
  self.strategyUpgrade=self:CreateActionButton(form,"替换为已学最高等级",0,y,390,function() self:UpgradeStrategySpell() end); y=y-40
  self:CreateToggleRow(form,"启用当前技能",0,y,390,function() return row.enabled end,function(v) row.enabled=v end); y=y-40
  self:CreateSelectRow(form,"施放类型（自动无法确认时手动选择）",{{"auto","自动"},{"self","自身"},{"friendly","友方"},{"enemy","敌方"},{"ground","地面"}},0,y,390,
   function() return row.targetMode or "auto" end,function(v) row.targetMode=v end); y=y-68
  self:CreateHintText(form,"地面技能只发送现有按键，落点由玩家操作。",0,y,390); y=y-32
  if (row.moving and row.moving~="any") or (row.activity and row.activity~="any") or (row.distanceOp and row.distanceOp~="any") or (row.cdmKind and row.cdmKind~="none") or row.enemyMin or row.enemyMax then
   self:CreateHintText(form,"保留旧配置条件，与新策略共同判断；清空可移除旧条件。",0,y,390); y=y-40
  end
  for si,strategy in ipairs(row.strategies or {}) do
   local index=si; local card=self:Frame("Frame",form,"BackdropTemplate")
   local height=50+#strategy.conditions*120
   self:Paint(card,"SetPoint","TOPLEFT",form,"TOPLEFT",0,y); self:Paint(card,"SetSize",390,height)
   self:Paint(card,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
   self:Paint(card,"SetBackdropColor",.045,.075,.11,1); self:Paint(card,"SetBackdropBorderColor",.25,.45,.60,1)
   self:CreateSegmentedControl(card,{{"use","使用"},{"skip","跳过"}},8,-8,160,function() return strategy.mode end,function(v) strategy.mode=v end)
   self:CreateActionButton(card,"+ 条件",176,-8,95,function() self:ChangeCustomStrategy(function()
    if #strategy.conditions>=8 then self:CustomMessage("每条策略最多8个条件。"); return end
    strategy.conditions[#strategy.conditions+1]={kind="usable",value=true}
   end) end)
   self:CreateActionButton(card,"删除策略",279,-8,102,function() self:ChangeCustomStrategy(function(r) table.remove(r.strategies,index) end) end)
   for ci,condition in ipairs(strategy.conditions) do
    local conditionIndex=ci; local cy=-46-(ci-1)*120
    local typeButton=self:CreateActionButton(card,condition.kind=="comboPoints" and self.engine.classToken~="ROGUE" and "当前职业不支持此条件" or strategyNames[condition.kind] or "未知条件",8,cy,190,function() end)
    self:Paint(typeButton,"SetScript","OnClick",function() self:Guard(function()
     self:Paint(self.strategyKindMenu,"ClearAllPoints"); self:Paint(self.strategyKindMenu,"SetPoint","TOPLEFT",typeButton,"BOTTOMLEFT",0,-2)
     self.strategyKindTarget=condition; self:RefreshStrategyKinds(); self:Paint(self.strategyKindMenu,"Show")
    end) end)
    self:CreateActionButton(card,"删除条件",282,cy,99,function() self:ChangeCustomStrategy(function()
     table.remove(strategy.conditions,conditionIndex); if #strategy.conditions==0 then table.remove(row.strategies,index) end
    end) end)
    local function input(field,x,width)
     local box=self:SequenceInput(card,x,cy-36,width)
     self:Paint(box,"SetText",condition[field] and tostring(condition[field]) or "")
     self.strategyInputs[#self.strategyInputs+1]={box=box,condition=condition,field=field}
    end
    if condition.kind=="comboPoints" and self.engine.classToken~="ROGUE" then
     self:CreateHintText(card,"当前职业不支持，保持未知阻断；可以删除或更换条件。",8,cy-40,370)
    elseif condition.kind=="comboPoints" or condition.kind=="distance" or condition.kind=="enemies" or condition.kind=="cdmStacks" or condition.kind=="rangedEnemies" or condition.kind=="nearbyEnemies" then
     if condition.op then
      local ops={{"lt","<"},{"le","≤"},{"eq","="},{"ne","≠"},{"ge","≥"},{"gt",">"}}
      self:CreateSegmentedControl(card,ops,8,cy-36,250,function() return condition.op end,function(v) condition.op=v end)
      input("threshold",280,92)
      self:CreateHintText(card,"保留旧条件的比较方式；重新选择目标距离可改为区间。",8,cy-70,370)
     else
     self:CreateHintText(card,condition.kind=="comboPoints" and "连击点：下限～上限（0～10整数）" or condition.kind=="distance" and "码数：下限～上限（含边界）" or condition.kind=="cdmStacks" and "公开层数：下限～上限" or "数量：下限～上限（可见姓名板）",8,cy-40,205)
     input("min",220,65); input("max",307,65)
     if condition.kind=="rangedEnemies" or condition.kind=="nearbyEnemies" then
      local choices={{5,"5码"},{10,"10码"},{20,"20码"},{25,"25码"},{30,"30码"},{35,"35码"},{40,"40码"}}
      self:CreateSegmentedControl(card,choices,8,cy-66,370,function() return condition.radius end,
       function(value) if self:CommitCustomNumbers() then condition.radius=value; self.customFormIndex=nil; self:RefreshStrategyForm() end end)
      local supported=false; for _,choice in ipairs(choices) do if condition.radius==choice[1] then supported=true end end
      self:CreateHintText(card,supported and "自身所选码数内；探针未知不视为满足。" or ("旧半径 " .. tostring(condition.radius) .. "码；请选择新档位，原条件暂保留。"),8,cy-100,370)
     elseif condition.kind=="cdmStacks" then
      local box=self:SequenceInput(card,8,cy-66,105); local field=(condition.kind=="nearbyEnemies" or condition.kind=="rangedEnemies") and "radius" or "spellID"
      self:Paint(box,"SetText",condition[field] and tostring(condition[field]) or "")
      self.strategyInputs[#self.strategyInputs+1]={box=box,condition=condition,field=field}
      self:CreateHintText(card,"目录ID；Secret/隐藏/缺失均未知",120,cy-70,250)
     else self:CreateHintText(card,"单边可留空；距离区间跨越阈值时视为未知。",8,cy-70,370) end
     end
    elseif condition.kind=="lossOfControl" then
     self:CreateSegmentedControl(card,{{"stun","昏迷"},{"confuse","迷惑"},{"fear","恐惧"},{"any","任意失控"}},8,cy-36,370,
      function() return condition.control end,function(v) condition.control=v end)
     self:CreateSegmentedControl(card,{{true,"存在"},{false,"不存在"}},8,cy-70,190,function() return condition.value end,function(v) condition.value=v end)
    elseif condition.kind=="targetType" then
     self:CreateSegmentedControl(card,{{"enemy","敌对"},{"friendly","友方"},{"self","自己"},{"none","无目标"}},8,cy-36,370,
      function() return condition.target end,function(v) condition.target=v end)
     self:CreateHintText(card,"只检查当前目标，不选择或切换目标。",8,cy-70,370)
    else
     local labels=condition.kind=="combat" and {"战斗中","脱战"} or condition.kind=="learned" and {"已学","未学"}
      or condition.kind=="succeeded" and {"本轮已成功","本轮未成功"} or condition.kind=="moving" and {"移动中","站定"} or condition.kind=="cdmBuff" and {"存在","不存在"}
      or (condition.kind=="cdmCooldown" or condition.kind=="cooldown") and {"冷却中","可用"} or condition.kind=="range" and {"范围内","范围外"} or {"可用","不可用"}
     self:CreateSegmentedControl(card,{{true,labels[1]},{false,labels[2]}},8,cy-36,190,function() return condition.value end,function(v) condition.value=v end)
     if condition.kind=="cdmCooldown" or condition.kind=="cdmBuff" or condition.kind=="learned" or condition.kind=="succeeded" then
      input("spellID",270,102); self:CreateHintText(card,"ID",230,cy-42,35)
      self:CreateHintText(card,condition.kind=="succeeded" and "ID空白=本技能；开始/重置/编辑清除，暂停保留。" or condition.kind=="learned" and "精确已学ID；空白=本技能，不按名称或最高等级推断。" or "ID空白=当前技能；帧缺失为未知；增益存在指帧活动。",8,cy-70,370)
     end
    end
   end
   y=y-height-12
  end
  if #(row.strategies or {})==0 then self:CreateHintText(form,"点击 [+] 添加策略；没有策略时按基础可用性判断。",0,y,390); y=y-55 end
 end
 self:Paint(form,"SetHeight",math.max(120,-y))
 self.strategyFormControls={}; for i=first+1,#self.controls do self.strategyFormControls[self.controls[i]]=true end
end
function U:CreateStrategyPanel()
 local panel=self:Frame("Frame",self.settings,"BackdropTemplate","TEF_StrategySettings"); self.strategyPanel=panel
 self:Paint(panel,"SetPoint","TOPLEFT",self.settings,"TOPRIGHT",8,0); self:Paint(panel,"SetSize",430,720)
 self:Paint(panel,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
 self:Paint(panel,"SetBackdropColor",.025,.035,.055,.98); self:Paint(panel,"SetBackdropBorderColor",.25,.45,.60,1)
 self.strategyTitle=self:Text(panel,15,-18,335,"GameFontNormal")
 self:CreateActionButton(panel,"关闭",365,-12,52,function() self:Paint(panel,"Hide") end)
 self:CreateHintText(panel,"使用条件全部满足；任一跳过策略满足则跳过。未知不授权使用。",15,-51,395)
 self:CreateActionButton(panel,"+",365,-84,50,function() self:ChangeCustomStrategy(function(r)
  if #r.strategies>=8 then self:CustomMessage("每个技能最多8条策略。"); return end
  r.strategies[#r.strategies+1]={mode="use",conditions={{kind="usable",value=true}}}
 end) end)
 self:CreateHintText(panel,"每条策略内的条件共同满足（AND）",15,-91,335)
 self.strategyScroll=self:Frame("ScrollFrame",panel,"UIPanelScrollFrameTemplate")
 self:Paint(self.strategyScroll,"SetPoint","TOPLEFT",panel,"TOPLEFT",15,-126); self:Paint(self.strategyScroll,"SetSize",385,530)
 self.strategySaveButton=self:CreateActionButton(panel,"保存",15,-675,190,function()
  if not self:CommitCustomNumbers() then return end
  if self.strategySource=="manual" then
   local rows=self:DraftRows(); local ok,reason=T.Profiles:Save(self.engine,self.editScene,rows)
   self:SequenceMessage(ok and "已保存列表循环策略并停止派发。" or (reason or "保存失败")); return
  end
  if self.page=="maintenance" then local ok,reason=T.Maintenance:Save(self.engine,self.customDraft); self:CustomMessage(ok and "增益维护策略已保存并停止派发。" or reason); return end
  local ok,reason=C:Save(self.engine,self.customDraft,self.customLoadedScene,self.customClass)
  if ok and self.engine.db.enabledPlans.apl[self.customLoadedScene] then ok,reason=T.Profiles:UsePlan(self.engine,"apl",self.customLoadedScene) end
  self:CustomMessage(ok and "已保存并停止派发；关闭设置后主动开启。" or (reason or "保存失败"))
 end)
 self:CreateActionButton(panel,"清空",220,-675,190,function() self.strategyInputs={}; local row=self:CustomRow(); if row then row.strategies={} end; self:ChangeCustomStrategy(function(r)
  r.strategies={}; r.moving="any"; r.activity="any"; r.distanceOp="any"; r.distanceValue=nil
  r.cdmKind="none"; r.cdmSpellID=nil; r.enemyMin=nil; r.enemyMax=nil
 end); self:CustomMessage("已清空当前技能条件草稿；保存后生效。") end)
 local menu=self:Frame("Frame",panel,"BackdropTemplate"); self.strategyKindMenu=menu
 self:Paint(menu,"SetSize",220,248); self:Paint(menu,"SetFrameStrata","DIALOG"); self:Paint(menu,"SetClampedToScreen",true)
 local scroll=self:Frame("ScrollFrame",menu,"UIPanelScrollFrameTemplate")
 self:Paint(scroll,"SetPoint","TOPLEFT",menu,"TOPLEFT",4,-4); self:Paint(scroll,"SetSize",190,240)
 local child=self:Frame("Frame",scroll); self.strategyKindChild=child; self.strategyKindButtons={}; self:Paint(child,"SetSize",187,#strategyKinds*30); self:Paint(scroll,"SetScrollChild",child)
 self:Paint(menu,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
 self:Paint(menu,"SetBackdropColor",.03,.05,.08,1)
 for i,kind in ipairs(strategyKinds) do local selectedKind=kind
  self.strategyKindButtons[kind]=self:CreateActionButton(child,strategyNames[kind],0,-(i-1)*30,187,function()
   if selectedKind=="comboPoints" and self.engine.classToken~="ROGUE" then return end
   self:ChangeCustomStrategy(function()
   local c=self.strategyKindTarget; if not c then return end
   for k in pairs(c) do c[k]=nil end
   c.kind=selectedKind
   if selectedKind=="comboPoints" then c.min=5 elseif selectedKind=="lossOfControl" then c.control="stun"; c.value=true elseif selectedKind=="distance" then c.max=20 elseif selectedKind=="nearbyEnemies" then c.min=1; c.radius=10 elseif selectedKind=="enemies" or selectedKind=="rangedEnemies" or selectedKind=="cdmStacks" then c.min=1 elseif selectedKind=="targetType" then c.target="enemy" else c.value=selectedKind~="cdmCooldown" and selectedKind~="cooldown" end
  end); self:Paint(menu,"Hide") end)
 end
 self:RefreshStrategyKinds(); self:Paint(menu,"Hide"); self:Paint(panel,"Hide")
end
