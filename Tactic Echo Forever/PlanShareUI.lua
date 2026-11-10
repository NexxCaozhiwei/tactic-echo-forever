local _,T=...
local U,S,X=T.UI,T.Safety,T.PlanShare
local slots={single=true,multi=true,third=true}
function U:ShareNames()
 if self.shareNameEngine~=self.engine or self.shareNameClass~=self.engine.classToken then self.shareNameEngine=self.engine; self.shareNameClass=self.engine.classToken; self.shareNames={} end
 return self.shareNames
end
function U:SharePlanName(source,slot)
 return self:ShareNames()[source..":"..slot] or T.Profiles:PlanName(slot,self.engine,source)
end
function U:CommitShareName(source,slot)
 local names=self:ShareNames(); local key=source..":"..slot
 if names[key] and T.Profiles:SetPlanName(self.engine,source,slot,names[key]) then names[key]=nil end
end
function U:ClosePlanShare()
 if self.shareBox then self:Paint(self.shareBox,"ClearFocus") end
 self.shareParsed=nil; self.shareContext=nil
 self:Paint(self.shareShield,"Hide")
end
function U:PlanShareRows(source,slot)
 return self:StudioPlanDraft(source,slot) or (source=="manual" and self.engine.db.profiles[slot] or T.APL.Custom:Rows(self.engine,slot))
end
function U:ShareContextValid()
 local c=self.shareContext
 if c and c.kind=="policy" then
  return self.settingsOpen and c.engine==self.engine and c.class==self.engine.classToken and c.page==self.page
   and c.source==self.strategySource and c.row==self:CustomRow() and c.index==(self.strategySource=="manual" and self.sequencePolicyIndex or self.strategySource=="groupStep" and self.groupSelected or self.customSelected) and self:Combat()==false
 end
 local _,source,slot=self:StudioRows()
 return c and self.settingsOpen and c.engine==self.engine and c.class==self.engine.classToken
  and source==c.source and (slot~="maintenance" or c.kind=="bundle") and not self.groupEditing and self:Combat()==false
end
function U:PreparePlanImport(slot)
 if not self:ShareContextValid() or not slots[slot] or not self.shareParsed then return nil,"请重新打开导入并解析分享码。" end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return nil,"请先修正当前草稿的输入。" end
 local ok,text=self:Invoke(self.shareBox,"GetText")
 if not ok or S.Public(text,"string")~=self.shareParsedText then return nil,"分享码已改变，请重新解析。" end
 local c=self.shareContext
 return {engine=self.engine,class=c.class,source=c.source,slot=slot,plan=self.shareParsed,
  fingerprint=self:StudioFingerprint(self:PlanShareRows(c.source,slot),c.source),name=self:SharePlanName(c.source,slot)}
end
function U:ApplyPlanImport(tx)
 if not self:ShareContextValid() or tx.engine~=self.engine or tx.class~=self.engine.classToken or tx.source~=self.shareContext.source
  or not slots[tx.slot] or tx.plan~=self.shareParsed then return false,"编辑对象已改变，请重新导入。" end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false,"请先修正当前草稿输入。" end
 if tx.fingerprint~=self:StudioFingerprint(self:PlanShareRows(tx.source,tx.slot),tx.source) or tx.name~=self:SharePlanName(tx.source,tx.slot) then
  return false,"目标方案已改变，请重新预览后确认。"
 end
 local ok,plan=pcall(X.Clean,X,tx.plan); if not ok then return false,tostring(plan) end
 -- 所有校验完成后才切换编辑槽并替换草稿；不调用运行方案或派发接口。
 if tx.source=="manual" then
  self.editScene=tx.slot; self:ShowPage("profiles"); self:WriteDraft(plan.rows)
  self.sequenceDrafts=self.sequenceDrafts or {}; self.sequenceDrafts[(self.engine.profileKey or "unknown")..":"..tx.slot]=plan.rows
 else
  self.customScene=tx.slot; self:ShowPage("customapl"); self.customDraft=plan.rows
  self.customDraftCache=self.customDraftCache or {}; self.customDraftCache[self.engine.classToken..":"..tx.slot]=plan.rows
  self.customSelected=1; self.customFormIndex=nil; self:RefreshCustomAPL()
 end
 self:ShareNames()[tx.source..":"..tx.slot]=plan.name
 self.undoDelete=nil; self.studioProbe=nil; self.studioPlanLoaded=nil; self.studioSelected=nil; self.sequencePolicyRow=nil; self.strategyInputs={}; self:Paint(self.strategyPanel,"Hide")
 self:ClosePlanShare(); self:RefreshStudio()
 self:StudioMessage("已导入草稿，待保存名称："..plan.name.."。点击保存方案后生效；未切换运行方案或开启派发。")
 return true
end
function U:ParsePlanShare()
 if not self:ShareContextValid() then return false end
 local ok,text=self:Invoke(self.shareBox,"GetText"); text=ok and S.Public(text,"string")
 local policy=self.shareContext.kind=="policy"
 local plan,reason
 if policy then plan,reason=X:ImportPolicy(text,self.engine.classToken)
 elseif self.shareContext.kind=="bundle" then plan,reason=X:ImportBundle(text,self.engine.classToken)
 else plan,reason=X:Import(text,self.engine.classToken,self.shareContext.source) end
 self.shareParsed=plan; self.shareParsedText=text
 self:Paint(self.sharePreview,"SetText",plan and (policy and X:PolicyPreview(plan) or self.shareContext.kind=="bundle" and X:BundlePreview(plan) or X:Preview(plan)) or reason)
 self:SetControlEnabled(self.shareApply,plan~=nil,"请先解析有效分享码。")
 return plan~=nil
end
function U:OpenPlanShare(mode)
 local rows,source,slot=self:StudioRows()
 if (mode~="import" and mode~="export") or not slots[slot] or self.groupEditing or self:Combat()~=false then
  self:StudioMessage("请在脱战时选择列表循环或优先级推荐的父方案。"); return false
 end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false end
 rows=self:StudioRows()
 local code,reason
 if mode=="export" then
  code,reason=X:Export(self.engine.classToken,source,self:SharePlanName(source,slot),rows)
  if not code then self:StudioMessage("无法导出："..reason); return false end
 end
 self:CreatePlanShare()
 self.shareContext={engine=self.engine,class=self.engine.classToken,source=source,mode=mode}
 self.shareTarget=slot; self.shareParsed=nil; self.shareParsedText=nil
 self:Paint(self.shareTitle,"SetText",mode=="export" and "导出方案 · 当前编辑草稿" or "导入方案 · 解析后替换目标草稿")
 self:Paint(self.shareBox,"SetText",code or "")
 self:Paint(self.sharePreview,"SetText",mode=="export" and ("包含未保存修改及全部技能组／策略。\n当前名称："..self:SharePlanName(source,slot).."\n点击文本后按Ctrl+A、Ctrl+C复制；导出不会保存或启用方案。") or "粘贴分享码后点击解析预览。导入仅支持当前职业及同类型方案。\n不会导入按键、HUD、运行进度、启用状态或派发参数。")
 for _,control in ipairs({self.shareParse,self.shareTargets,self.shareApply}) do self:Paint(control,mode=="import" and "Show" or "Hide") end
 self:SetControlEnabled(self.shareApply,false,"请先解析有效分享码。")
 self:Paint(self.shareShield,"SetScale",1); self:Paint(self.shareShield,"Show"); self:Paint(self.shareShield,"Raise")
 self:Paint(self.shareBox,"SetFocus"); self:Paint(self.shareBox,"HighlightText")
 self:RefreshControls()
 return true
end
function U:PolicyShareSnapshot()
 local row=self:CustomRow()
 local actual=self.strategySource=="manual" and (self:DraftRows() or {})[self.sequencePolicyIndex] or row
 return X:Serialize({editor=row,actual=actual})
end
function U:OpenPolicyShare(mode)
 if (mode~="import" and mode~="export") or not self.settingsOpen or self:Combat()~=false then return false end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false end
 local row=self:CustomRow(); if not row or not self.strategySource then return false end
 local code,reason
 if mode=="export" then
  code,reason=X:ExportPolicy(self.engine.classToken,row.strategies)
  if not code then self:CustomMessage("无法导出策略："..reason); return false end
 end
 self:CreatePlanShare()
 self.shareContext={kind="policy",mode=mode,engine=self.engine,class=self.engine.classToken,page=self.page,source=self.strategySource,row=row,
  index=self.strategySource=="manual" and self.sequencePolicyIndex or self.strategySource=="groupStep" and self.groupSelected or self.customSelected}
 self.shareParsed=nil; self.shareParsedText=nil
 self:Paint(self.shareTitle,"SetText",mode=="export" and "导出当前条目的使用／跳过策略" or "导入策略 · 替换当前条目的条件草稿")
 self:Paint(self.shareBox,"SetText",code or "")
 self:Paint(self.sharePreview,"SetText",mode=="export" and "复制分享码以复用当前使用／跳过策略。技能ID、次数、顺序和触发行为不在策略包中。\n条件中的显式观察ID保留；无ID的条件跟随导入目标技能。" or "粘贴TEFPOLICY分享码并解析预览。仅替换当前条目的使用／跳过策略，不改变技能ID和列表顺序；保存方案后生效。")
 self:Paint(self.shareTargets,"Hide")
 for _,control in ipairs({self.shareParse,self.shareApply}) do self:Paint(control,mode=="import" and "Show" or "Hide") end
 self:SetControlEnabled(self.shareApply,false,"请先解析有效策略分享码。")
 self:Paint(self.shareShield,"Show"); self:Paint(self.shareShield,"Raise"); self:Paint(self.shareBox,"SetFocus"); self:Paint(self.shareBox,"HighlightText")
 return true
end
function U:PreparePolicyImport()
 if not self:ShareContextValid() or self.shareContext.kind~="policy" or not self.shareParsed then return nil,"请重新选择技能并解析策略码。" end
 if not self:CommitCustomNumbers() then return nil,"请先修正当前策略输入。" end
 local ok,text=self:Invoke(self.shareBox,"GetText")
 if not ok or S.Public(text,"string")~=self.shareParsedText then return nil,"策略码已改变，请重新解析。" end
 return {context=self.shareContext,policy=self.shareParsed,fingerprint=self:PolicyShareSnapshot()}
end
function U:ApplyPolicyImport(tx)
 if not self:ShareContextValid() or tx.context~=self.shareContext or tx.policy~=self.shareParsed then return false,"当前编辑对象已改变，请重新导入。" end
 if not self:CommitCustomNumbers() then return false,"请先修正当前策略输入。" end
 if tx.fingerprint~=self:PolicyShareSnapshot() then return false,"当前条目已改变，请重新预览后确认。" end
 local ok,policy=pcall(X.CleanPolicy,X,tx.policy); if not ok then return false,tostring(policy) end
 self.strategyInputs={}
 self:ChangeCustomStrategy(function(row)
  row.strategies=policy.strategies
  if self.strategySource=="apl" or self.strategySource=="maintenance" then
   row.moving="any"; row.activity="any"; row.distanceOp="any"; row.distanceValue=nil
   row.cdmKind="none"; row.cdmSpellID=nil; row.enemyMin=nil; row.enemyMax=nil
  end
 end)
 self:ClosePlanShare(); self:CustomMessage("使用／跳过策略已替换到当前条目草稿；保存方案后生效。")
 return true
end
function U:BundleDraft()
 local bundle={schema=2,class=self.engine.classToken,plans={manual={},apl={}},maintenance={rows=self:StudioPlanDraft("apl","maintenance") or T.Maintenance:Rows(self.engine)}}
 for _,source in ipairs({"manual","apl"}) do for _,slot in ipairs({"single","multi","third"}) do
  bundle.plans[source][slot]={schema=1,class=bundle.class,source=source,name=self:SharePlanName(source,slot),rows=self:PlanShareRows(source,slot) or {}}
 end end
 return bundle
end
function U:OpenBundleShare(mode)
 local _,source,slot=self:StudioRows()
 if (mode~="import" and mode~="export") or (not slots[slot] and slot~="maintenance") or self.groupEditing or not self.settingsOpen or self:Combat()~=false then return false end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false end
 local code,reason
 if mode=="export" then
  code,reason=X:ExportBundle(self:BundleDraft())
  if not code then self:StudioMessage("无法导出整包："..reason); return false end
 end
 self:CreatePlanShare()
 self.shareContext={kind="bundle",mode=mode,engine=self.engine,class=self.engine.classToken,source=source}
 self.shareParsed=nil; self.shareParsedText=nil
 self:Paint(self.shareTitle,"SetText",mode=="export" and "导出全部方案 · 当前职业六套方案及增益与紧急草稿" or "导入全部方案 · 当前职业六套方案及增益与紧急草稿")
 self:Paint(self.shareBox,"SetText",code or "")
 self:Paint(self.sharePreview,"SetText",mode=="export" and "整包包含列表循环三套、优先级推荐三套，以及名称、技能组、策略和未保存修改。同时包含增益与紧急技能列表及策略；本机维护启用状态保留，其他职业、本机按键及派发设置不在整包中。" or "粘贴TEFBUNDLE整包码并解析预览。确认后替换六套草稿；随后点击方案设置中的保存全部导入，一次保存六套。")
 self:Paint(self.shareTargets,"Hide")
 for _,control in ipairs({self.shareParse,self.shareApply}) do self:Paint(control,mode=="import" and "Show" or "Hide") end
 self:SetControlEnabled(self.shareApply,false,"请先解析有效整包码。")
 self:Paint(self.shareShield,"Show"); self:Paint(self.shareShield,"Raise"); self:Paint(self.shareBox,"SetFocus"); self:Paint(self.shareBox,"HighlightText")
 return true
end
function U:PrepareBundleImport()
 if not self:ShareContextValid() or self.shareContext.kind~="bundle" or not self.shareParsed then return nil,"请重新解析整包。" end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return nil,"请先修正当前输入。" end
 local ok,text=self:Invoke(self.shareBox,"GetText")
 if not ok or S.Public(text,"string")~=self.shareParsedText then return nil,"整包码已改变，请重新解析。" end
 return {context=self.shareContext,bundle=self.shareParsed,fingerprint=X:Serialize(self:BundleDraft())}
end
function U:ApplyBundleImport(tx)
 if not self:ShareContextValid() or tx.context~=self.shareContext or tx.bundle~=self.shareParsed then return false,"编辑对象已改变，请重新导入整包。" end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false,"请先修正当前输入。" end
 if tx.fingerprint~=X:Serialize(self:BundleDraft()) then return false,"六套草稿已有变化，请重新预览后确认。" end
 local ok,bundle=pcall(X.CleanBundle,X,tx.bundle); if not ok then return false,tostring(bundle) end
 local page=self.page; local e=self.engine
 self:ShowPage(page)
 self.sequenceDrafts=self.sequenceDrafts or {}; self.customDraftCache=self.customDraftCache or {}
 for _,slot in ipairs({"single","multi","third"}) do
  self.sequenceDrafts[(e.profileKey or "unknown")..":"..slot]=bundle.plans.manual[slot].rows
  self.customDraftCache[e.classToken..":"..slot]=bundle.plans.apl[slot].rows
 end
 if self.sequenceEngine==e and slots[self.loadedScene] then self:WriteDraft(bundle.plans.manual[self.loadedScene].rows) end
 if self.customEngine==e and slots[self.customLoadedScene] then self.customDraft=bundle.plans.apl[self.customLoadedScene].rows end
 if bundle.maintenance then
  self.customDraftCache[e.classToken..":maintenance"]=bundle.maintenance.rows
  if self.customEngine==e and self.customLoadedScene=="maintenance" then self.customDraft=bundle.maintenance.rows end
 end
 self.shareBundleMaintenance=bundle.maintenance~=nil
 for _,source in ipairs({"manual","apl"}) do for _,slot in ipairs({"single","multi","third"}) do
  self:ShareNames()[source..":"..slot]=bundle.plans[source][slot].name
 end end
 self.shareBundleEngine=e; self.shareBundleClass=e.classToken
 self.undoDelete=nil; self.studioProbe=nil; self.studioPlanLoaded=nil; self.sequencePolicyRow=nil; self.strategyInputs={}; self.customFormIndex=nil
 self:Paint(self.strategyPanel,"Hide"); self:ClosePlanShare()
 self:RefreshPage(); self:StudioMessage(bundle.maintenance and "六套方案及增益与紧急已导入草稿；保存全部导入后落盘，本机启用状态保留。" or "旧版六套方案已导入草稿；本机增益与紧急保留。")
 return true
end
function U:SaveBundleDraft()
 if self.shareBundleEngine~=self.engine or self.shareBundleClass~=self.engine.classToken or not self.settingsOpen or self.groupEditing or self:Combat()~=false then return false end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false end
 local bundle=self:BundleDraft()
 if not self.shareBundleMaintenance then bundle.schema=1; bundle.maintenance=nil end
 local ok,reason=T.Profiles:SaveBundle(self.engine,bundle)
 if ok then
  self.shareBundleEngine=nil; self.shareBundleClass=nil; self.shareBundleMaintenance=nil
  for _,source in ipairs({"manual","apl"}) do for _,slot in ipairs({"single","multi","third"}) do self:ShareNames()[source..":"..slot]=nil end end
  self.studioPlanLoaded=nil; self:RefreshStudio()
 end
 self:StudioMessage(ok and "整包所含方案及增益与紧急已保存，旧派发已停止；本机启用状态保留。" or ("整包未保存："..tostring(reason)))
 return ok,reason
end
function U:CreatePlanShare()
 if self.shareShield then return end
 local shield=self:Frame("Frame",self.settings,"BackdropTemplate"); self.shareShield=shield
 self:Paint(shield,"SetAllPoints",UIParent); self:Paint(shield,"SetFrameStrata","DIALOG"); self:Paint(shield,"EnableMouse",true)
 self:Paint(shield,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8"}); self:Paint(shield,"SetBackdropColor",0,0,0,.65)
 local panel=self:CreateStudioPanel(shield); self.sharePanel=panel
 self:Paint(panel,"SetSize",620,620); self:Paint(panel,"SetPoint","CENTER",self.settings,"CENTER",0,0)
 self:Paint(panel,"EnableMouse",true)
 self.shareTitle=self:Text(panel,20,-20,580,"GameFontNormal")
 self:CreateHintText(panel,"分享码（点击文本后使用Ctrl+A／Ctrl+C／Ctrl+V）",20,-56,580)
 local input=self:CreateStudioPanel(panel); self.shareInputArea=input; self:StudioAnchor(input,panel,20,-84,580,164)
 local scroll=self:Frame("ScrollFrame",input,"UIPanelScrollFrameTemplate"); self.shareInputScroll=scroll
 self:StudioAnchor(scroll,input,8,-8,540,148)
 local box=self:SequenceInput(scroll,0,0,532); self.shareBox=box
 self:Paint(box,"SetBackdrop",nil)
 local function focus() self:Paint(box,"SetFocus") end
 self:Paint(input,"EnableMouse",true); self:Paint(input,"SetScript","OnMouseDown",focus)
 self:Paint(scroll,"EnableMouse",true); self:Paint(scroll,"SetScript","OnMouseDown",focus)
 self:Paint(box,"SetMultiLine",true); self:Paint(box,"SetHeight",148); self:Paint(box,"SetMaxLetters",X.MaxCode)
 self:Paint(box,"SetScript","OnEnterPressed",nil); self:Paint(box,"SetScript","OnEscapePressed",function() self:ClosePlanShare() end)
 self:Paint(box,"SetScript","OnTextChanged",function()
  self.shareParsed=nil; self:SetControlEnabled(self.shareApply,false,"文本已改变，请重新解析。")
 end)
 self:Paint(box,"SetScript","OnHide",function() self:Paint(box,"ClearFocus") end)
 self:Paint(scroll,"SetScrollChild",box)
 self.shareParse=self:CreateActionButton(panel,"解析预览",20,-264,120,function() self:Paint(box,"ClearFocus"); self:ParsePlanShare() end)
 local previewScroll=self:Frame("ScrollFrame",panel,"UIPanelScrollFrameTemplate"); self:StudioAnchor(previewScroll,panel,20,-304,552,168)
 local child=self:Frame("Frame",previewScroll); self:Paint(child,"SetSize",544,1000); self:Paint(previewScroll,"SetScrollChild",child)
 self.sharePreview=self:Text(child,0,0,536); self:Paint(self.sharePreview,"SetWordWrap",true)
 self.shareTargets=self:Frame("Frame",panel); self:StudioAnchor(self.shareTargets,panel,20,-492,580,32)
 self:CreateSegmentedControl(self.shareTargets,{{"single","方案一"},{"multi","方案二"},{"third","方案三"}},0,0,580,
  function() return self.shareTarget end,function(v) self.shareTarget=v end)
 self.shareApply=self:CreateActionButton(panel,"导入到草稿",320,-568,144,function()
  self:Paint(box,"ClearFocus")
  local policy=self.shareContext and self.shareContext.kind=="policy"
  local bundle=self.shareContext and self.shareContext.kind=="bundle"
  local tx,reason
  if policy then tx,reason=self:PreparePolicyImport() elseif bundle then tx,reason=self:PrepareBundleImport() else tx,reason=self:PreparePlanImport(self.shareTarget) end
  if not tx then self:Paint(self.sharePreview,"SetText",reason); return end
  local prompt=policy and "确认替换当前条目的全部使用／跳过策略？技能及其他设置保留，保存方案后生效。" or bundle and "确认替换整包所含六套方案及增益与紧急草稿？旧版整包不改维护列表。本机启用状态保留，保存全部导入后才落盘。" or ("确认替换“"..tx.name.."”的草稿及待保存名称？已有内容和未保存修改将被替换；保存前不写入配置。")
  self:ConfirmAction(prompt,function()
   local ok,message
   if policy then ok,message=self:ApplyPolicyImport(tx) elseif bundle then ok,message=self:ApplyBundleImport(tx) else ok,message=self:ApplyPlanImport(tx) end; if not ok then self:Paint(self.sharePreview,"SetText",message) end
  end,"替换目标草稿")
 end)
 self:CreateActionButton(panel,"关闭",476,-568,124,function() self:ClosePlanShare() end)
 self:Paint(shield,"SetScript","OnHide",function() self.shareParsed=nil; self.shareContext=nil; self:Paint(box,"ClearFocus") end)
 self:Paint(shield,"Hide")
end
