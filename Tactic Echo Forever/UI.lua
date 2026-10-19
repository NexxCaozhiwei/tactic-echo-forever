local _, TEF = ...
local S, UI = TEF.Safety, {}
TEF.UI = UI

function UI:Invoke(object, method, ...)
    local ok, fn = pcall(function() return object[method] end)
    if not ok or type(fn) ~= "function" then return false end
    return pcall(fn, object, ...)
end
function UI:Call(object, method, ...)
    local ok=self:Invoke(object,method,...); return ok
end
-- 刷新异常必须释放重入标记，并丢弃可能只完成一部分的布局缓存。
function UI:WithUpdateFlag(flag,callback,...)
    if self[flag] then return end
    self[flag]=true
    local ok,err=pcall(callback,self,...)
    self[flag]=false
    if not ok then
        self.settingsLayoutSignature=nil; self.studioBottomGeometry=nil
        error(err,0)
    end
end
function UI:Error()
    if not self.errorLogged then self.errorLogged=true; self.engine:Log("display","UI_CALL_FAILED") end
end
function UI:Paint(object,method,...)
    if not self:Call(object,method,...) then self:Error(); return false end
    if (object==self.strategyPanel or object==self.groupPanel) and (method=="Show" or method=="Hide") and self.LayoutSettings and not self.refreshingPage and not self.studioRefreshing and not self.studioLayoutBusy then self:LayoutSettings() end
    return true
end
function UI:Frame(kind,parent,template,name)
    if self.strategyPoolActive and not name then return self:AcquireStrategyFrame(kind,parent,template) end
    local ok,f=pcall(CreateFrame,kind,name,parent,template)
    if not ok then self:Error(); return nil end
    return f
end
function UI:Text(parent,x,y,width,template)
    local ok,t
    if self.strategyPoolActive then t=self:AcquireStrategyText(parent,template or "GameFontHighlight"); ok=t~=nil
    else ok,t=self:Invoke(parent,"CreateFontString",nil,"OVERLAY",template or "GameFontHighlight") end
    if not ok then self:Error(); return nil end
    self:Paint(t,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
    if self.StyleText then self:StyleText(t,template) end
    self:Paint(t,"SetWidth",width); self:Paint(t,"SetJustifyH","LEFT")
    return t
end
function UI:Button(parent,label,x,y,width,callback)
    local b=self:Frame("Button",parent,"UIPanelButtonTemplate")
    self:Paint(b,"SetSize",width or 85,self.controlHeight or 28); self:Paint(b,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
    self:Paint(b,"SetText",label)
    if self.ApplyControlFont then self:ApplyControlFont(b,true) end
    self:Paint(b,"SetScript","OnClick",function()
        local ok=pcall(callback)
        if not ok then TEF.Runtime:Fault("UI_CALLBACK_FAILED"); self:Error() end
        self:Refresh()
    end)
    return b
end
function UI:Backdrop(frame)
    self:Paint(frame,"SetBackdrop",{bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,
        insets={left=4,right=4,top=4,bottom=4}})
    self:Paint(frame,"SetBackdropColor",0.04,0.06,0.09,0.94)
    self:Paint(frame,"SetClampedToScreen",true)
end
function UI:Combat()
    local ok,raw=S.Call("InCombatLockdown")
    if not ok then return nil end
    return S.Public(raw,"boolean")
end
function UI:Layout()
    if TEF.HUD then TEF.HUD:Layout() end
    if self:Combat()~=false then self.layoutPending=true; return end
    self.layoutPending=false
    self:Paint(self.frame,"SetScale",self.engine.db.hud.scale)
    self:LayoutSettings()
end
function UI:Refresh()
    if TEF.HUD then TEF.HUD:Refresh() end
    local ok,raw=self:Invoke(self.frame,"IsVisible")
    if ok and S.Public(raw,"boolean")==true then self:RefreshPractice() end
    if self.settingsOpen then self:RefreshPage() end
end
-- 仅供 /tef test 使用的兼容工具，不参与普通Studio刷新。
function UI:RefreshPractice()
    local e=self.engine
    local step=e.steps and e.steps[e.index]
    local view
    if step and step.unverified then
        view=S.Spell(step.name,step.name); view.name=step.name .. "（成功ID待核验）"
    elseif step then view=S.Spell(step.spellID,step.name)
    else view={name=TEF.APL:IsActive(e) and TEF.APL.Trace:Waiting(e) or "配置无效（未解析）",icon=TEF.Placeholder,reason="CONFIG_INVALID",iconReason="CONFIG_INVALID"} end
    if not self:Paint(self.icon,"SetTexture",view.icon) then self:Paint(self.icon,"SetTexture",TEF.Placeholder) end
    self:Paint(self.name,"SetText",view.name)
    local scene=TEF.Profiles:PlanName(e.scene)
    local status=e.completed and "完成" or (e.running and "运行" or "暂停")
    self:Paint(self.progress,"SetText",e.index .. "/" .. (e.steps and #e.steps or 0) .. "  ·  " .. TEF.Profiles:PlanName(e.scene) .. "序列 · 次数 " .. (e.stepCasts or 0) .. "/" .. (step and step.repeatCount or 1))
    self:Paint(self.status,"SetText","手动  |  " .. scene .. "  |  " .. status)
    self:Paint(self.pause,"SetText",e.running and "暂停" or "继续")
    self:Paint(self.loop,"SetChecked",e.db.loop)
    self:Paint(self.detail,"SetText","ID " .. (step and step.spellID or 0) .. "  ·  " .. (e.lastReason or "LOGIN_PAUSED"))
    for i,card in ipairs(self.previews) do
        local n=e.index+i
        if e.db.loop and e.steps and n>#e.steps then n=(n-1)%#e.steps+1 end
        local nextStep=e.steps and not e.completed and e.db.hud.preview and not TEF.APL:IsActive(e) and e.steps[n]
        local preview=nextStep and (nextStep.unverified and S.Spell(nextStep.name,nextStep.name) or S.Spell(nextStep.spellID,nextStep.name))
        self:Paint(card.icon,"SetTexture",preview and preview.icon or TEF.Placeholder)
        self:Paint(card.label,"SetText",nextStep and ("随后 " .. n .. " · ID " .. nextStep.spellID) or "—")
    end
    local key=view.reason .. ":" .. (view.iconReason or "UNKNOWN") .. ":" .. e.index .. ":" .. e.scene
    if key~=self.lastResolution then
        self.lastResolution=key
        e:Log("display","SPELL_" .. view.reason,step and step.spellID>0 and step.spellID or nil)
    end
end
function UI:OpenSettings()
    if self:Combat()~=false then self.engine:Log("ignored","SETTINGS_COMBAT_BLOCKED"); return end
    -- Opening settings revokes the execution epoch, never user intent.
    self.settingsOpen=true
    TEF.Runtime:Suspend("RUNTIME_SETTINGS_STANDBY","standby")
    if not self.settings then self:CreateSettings() end
    self:Paint(self.settings,"Show"); self:Paint(self.settings,"Raise"); self:ShowPage(self.page or "overview"); self:LayoutSettings()
end
function UI:CloseSettings()
    if not self:CommitSequenceCounts() then return end
    if self.groupEditing and not self:CloseSkillGroup(false,function() self:CloseSettings() end) then return end
    if not self:CommitCustomNumbers() then return end
    self:CancelConfirmation()
    self:HideStudioInsertion(); self.studioDragging=nil
    self.captureHotkey=false; self.settingsOpen=false
    self:Paint(self.settings,"Hide")
    TEF.Runtime:Reconcile("SETTINGS_CLOSED")
    self:Refresh()
end
function UI:ShowPage(key)
    if self.sequenceEngine==self.engine and not self:CommitSequenceCounts() then return end
    if self.groupEditing and not self:CloseSkillGroup(false,function() self:ShowPage(key) end) then return end
    if self.sequenceEngine~=self.engine then
        self.sequenceEngine=self.engine; self.sequenceDrafts={}; self.sequenceDraft=nil; self.drafts={}; self.loadedScene=nil; self.loadedProfile=nil
        if self.strategySource=="manual" then self.sequencePolicyRow=nil; self.strategyInputs={} end
    end
    if self.customEngine~=self.engine then self.strategyInputs={} end
    if not self:CommitCustomNumbers() then return end
    key=({looping="overview",labels="hud",apl="customapl"})[key] or key
    self.drafts=self.drafts or {}
    if self.page=="profiles" and self.loadedScene and self.editor then
        self.sequenceDrafts=self.sequenceDrafts or {}
        self.sequenceDrafts[(self.loadedProfile or "unknown") .. ":" .. self.loadedScene]=self:DraftRows()
        local ok,raw=self:Invoke(self.editor,"GetText")
        local draft=ok and S.Public(raw,"string")
        if draft and #draft<=4096 then self.drafts[(self.loadedProfile or "unknown") .. ":" .. self.loadedScene]=draft end
    end
    self.studioSelected=nil; self.studioPlanOpen=false; self.studioInspectorRequested=false; self.studioWorkspaceOpen=false
    if self.CloseStudioLibrary then self:CloseStudioLibrary() end
    self.settingsLayoutSignature=nil
    self.page=key
    for parent,footer in pairs(self.pageFooters or {}) do self:Paint(footer,self.pages[key]==parent and "Show" or "Hide") end
    self.strategySource=key=="maintenance" and "maintenance" or key=="customapl" and "apl" or nil; self.sequencePolicyRow=nil; self.strategyInputs={}; self.customFormIndex=nil
    if key~="customapl" then self:Paint(self.strategyPanel,"Hide") end
    if self.pageTitles then self:Paint(self.pageHeading,"SetText",self.pageTitles[key] or "设置") end
    for name,nav in pairs(self.navigation or {}) do
        nav.tefControlSelected=name==key; self:SetControlEnabled(nav,true)
        self:Paint(nav,"SetText",(name==key and "|cffffcf45● " or "|cffb8c6dc") .. (self.pageTitles[name] or name) .. "|r")
    end
    local shown=(self.pageFrames or self.pages)[key]
    for _,panel in pairs(self.pageFrames or self.pages) do self:Paint(panel,panel==shown and "Show" or "Hide") end
    if key=="profiles" then
        self.editScene=self.editScene or self.engine.scene
        self.loadedScene=self.editScene
        self.loadedProfile=self.engine.profileKey
        self:Paint(self.editor,"SetText",self.drafts[(self.loadedProfile or "unknown") .. ":" .. self.editScene] or TEF.Profiles:Text(self.engine,self.editScene))
        local draftKey=(self.loadedProfile or "unknown") .. ":" .. self.editScene
        self.sequenceDraft=(self.sequenceDrafts and self.sequenceDrafts[draftKey]) or TEF.Profiles:Clean(self.engine.db.profiles[self.editScene],32)
        local got,value=self:Invoke(self.editor,"GetText"); self.sequenceDraftText=got and S.Public(value,"string")
    end
    self:LayoutSettings()
    self:RefreshPage()
    if key=="profiles" then self:RefreshSequenceEditor(true) end
end
function UI:RefreshPage()
    return self:WithUpdateFlag("refreshingPage",self.RefreshPageContent)
end
function UI:RefreshPageContent()
    local e=self.engine
    if self.RefreshControls then self:RefreshControls() end
    self:RefreshPlanFeedback(); self:RefreshUndoControls()
    if self.page=="overview" then
        if self.hotkeyMessage and not self.captureHotkey then self:Paint(self.hotkeyMessage,"SetText",TEF.Hotkeys:Status()) end
        local v=TEF.Runtime:GetViewState()
        self:Paint(self.overviewBadge,"SetText",v.label .. " · " .. (v.intent and "派发意图开启" or "派发意图关闭"))
        self:Paint(self.readouts.overview,"SetText",(self:ClassLabel() .. (v.source=="apl" and " · 优先级推荐" or " · 列表循环")) .. " · " .. TEF.Profiles:PlanName(e.scene)
            .. "\n" .. (v.source=="apl" and (e.aplTrace and e.aplTrace.reason or "等待启动采样") or ("步骤 " .. e.index .. "/" .. (e.steps and #e.steps or 0) .. " · 固定练习不保证ready")))
    elseif self.page=="profiles" then
        if self.loadedProfile~=e.profileKey then self.refreshingPage=false; self:ShowPage("profiles"); return end
        self:Paint(self.readouts.profiles,"SetText",self:ClassLabel() .. " · 编辑：" .. TEF.Profiles:PlanName(self.editScene,e,"manual") .. " · 当前使用：" .. TEF.Profiles:PlanName(e.scene,e,TEF.Recommendation:Source(e))
)
        if e.db.profileMigrationConflicts[e.classToken] and self.migrationHintEngine~=e then self.migrationHintEngine=e; self:SequenceMessage("旧职业配置存在冲突，原配置已保留，请核对并保存。") end
        self:RefreshSequenceEditor()

    elseif self.page=="customapl" or self.page=="maintenance" then
        self:RefreshCustomAPL()
    elseif self.page=="scene" then
        self:Paint(self.readouts.scene,"SetText","切换重置并暂停；自动判定仅旁路观察。\n可见敌方≥3建议多目标，≤1单体，2保持。\n1秒内两次不同采样；未知撤回。计数不等于命中。\n以下是采样时结果，不代表当前状态。\n\n" .. TEF.Research:View())
    elseif self.page=="hud" then
        -- 这些信息已有对应控件，旧摘要会覆盖标签设置卡片。
        self:Paint(self.readouts.hud,"SetText",""); self:Paint(self.readouts.hud,"Hide")
    elseif self.page=="tek" then
        self:Paint(self.readouts.tek,"SetText","TEAP v3 · 输出：" .. (TEF.Transport.enabled and "开启" or "关闭")
            .. "\nTEK许可：" .. (TEF.Dispatch.enabled and "开启" or "关闭")
            .. "\n连续执行（只读）：" .. (TEF.Dispatch.continuous and "ACTIVE" or "OFF")
            .. "\n" .. (TEF.Dispatch.continuousReason or "CONTINUOUS_OFF"))
    elseif self.page=="diagnostics" then
        local pending=TEF.Dispatch.pending
        local lines={"会话 " .. e.session .. " / 代次 " .. e.generation .. " / 淘汰 " .. e.db.evicted,
            "Pending " .. (pending and "有" or "无") .. " · Continuous " .. (TEF.Dispatch.continuous and "ACTIVE" or "OFF"),
            "Binding " .. (pending and pending.binding.key or "—") .. " · " .. (TEF.Runtime.reason or "—")}
        for i=math.max(1,#e.db.diagnostics-4),#e.db.diagnostics do
            local r=e.db.diagnostics[i]
            lines[#lines+1]=(r.event or "-") .. "\n" .. r.reason .. " · ID " .. (r.spellID or 0) .. " · " .. r.current .. "→" .. r.next .. " · 请求 " .. (r.request or 0) .. " / 轮 " .. (r.cycle or 0)
        end
        local report=self.diagnosticMode=="explain" and (self.diagnosticReport or "点击策略解释进行只读现场采样。") or TEF.APL.Custom:Timeline(e)
        if self.diagnosticMode=="audit" then
            local rows=TEF.Recommendation:BaseSource(e)=="manual" and e.db.profiles[e.scene] or TEF.APL.Custom:Rows(e,e.scene)
            local valid,errors,warnings=TEF.APL.Custom:Audit(rows,e)
            report="当前已保存方案体检\n" .. (valid and "未发现可证明的矛盾。" or errors) .. "\n" .. warnings
        end
        self:Paint(self.readouts.diagnostics,"SetText",table.concat(lines,"\n") .. "\n\n" .. report)
        local _,lineCount=(table.concat(lines,"\n") .. "\n\n" .. report):gsub("\n","\n")
        self:Paint(self.pages.diagnostics,"SetHeight",math.max(600,100+(lineCount+1)*52))
    end
    self.refreshingPage=false
    self:RefreshStudio()
end
function UI:CreateSettings()
    self.studio=false
    local e=self.engine
    local f=self:Frame("Frame",UIParent,"BackdropTemplate","TEF_Settings")
    self.settings=f; self.pages={}; self.readouts={}
    self:Paint(f,"SetSize",820,720); self:Paint(f,"SetPoint","CENTER",UIParent,"CENTER",0,0)
    self:Paint(f,"SetFrameStrata","MEDIUM"); self:Paint(f,"SetToplevel",true); self:Backdrop(f)
    self:Paint(f,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    self:Paint(f,"SetBackdropColor",.025,.035,.055,.98); self:Paint(f,"SetBackdropBorderColor",.18,.24,.34,1)
    self:Paint(f,"SetMovable",true); self:Paint(f,"EnableMouse",true); self:Paint(f,"RegisterForDrag","LeftButton")
    self:Paint(f,"SetScript","OnDragStart",function() if self:Combat()==false then self:Call(f,"StartMoving") end end)
    self:Paint(f,"SetScript","OnDragStop",function() self:Call(f,"StopMovingOrSizing") end)
    local title=self:Text(f,24,-20,280,"GameFontNormalLarge"); self:ApplyControlFont(title,false,self.theme.fontTitle); self:Paint(title,"SetText","TEF Studio · 战术回响")
    self:Paint(self:Text(f,24,-48,640,"GameFontHighlightSmall"),"SetText","TEF " .. TEF.Version .. " · 设置期间派发阻断，运行意图由启停控制")
    self.studioClose=self:CreateActionButton(f,"关闭",722,-16,75,function() self:CloseSettings() end)
    self:Paint(f,"SetScript","OnHide",function()
        self:CancelConfirmation()
        if self.settingsOpen then self.settingsOpen=false; self.captureHotkey=false; TEF.Runtime:Reconcile("SETTINGS_CLOSED") end
    end)
    self.navigation={}; self.pageTitles={}; self.pageFrames={}; self.pageScrolls={}
    self.pageHeading=self:Text(f,192,-80,592,"GameFontNormalLarge")
    local tabs={{"overview","派发总览"},{"profiles","列表循环"},{"customapl","优先级推荐"},{"maintenance","增益与紧急"},{"scene","场景与验证"},{"hud","HUD外观"},{"tek","高级TEK"},{"diagnostics","诊断/测试"}}
    local visibleIndex=0
    for i,tab in ipairs(tabs) do
        local key=tab[1]
        self.pageTitles[key]=tab[2]
        local hidden=key=="scene"
        if not hidden then visibleIndex=visibleIndex+1 end
        self.navigation[key]=self:Button(f,tab[2],24,-80-(visibleIndex-1)*44,144,function() self:ShowPage(key) end)
        if hidden then self:Paint(self.navigation[key],"Hide") end
        local panel=self:Frame("Frame",f)
        self.pages[key]=panel
        self:Paint(panel,"SetSize",610,590); self:Paint(panel,"SetPoint","TOPLEFT",f,"TOPLEFT",192,-116)
        self.pageFrames[key]=panel
        if key=="overview" or key=="hud" or key=="profiles" or key=="customapl" or key=="tek" or key=="scene" or key=="diagnostics" then
            local scroll=self:Frame("ScrollFrame",panel,"UIPanelScrollFrameTemplate")
            self.pageScrolls[key]=scroll
            self:Paint(scroll,"SetSize",580,575); self:Paint(scroll,"SetPoint","TOPLEFT",panel,"TOPLEFT",0,0)
            local content=self:Frame("Frame",scroll)
            self:Paint(content,"SetSize",580,key=="hud" and 1370 or key=="profiles" and 920 or key=="customapl" and 670 or 570)
            self:Paint(scroll,"SetScrollChild",content)
            self:Paint(content,"SetPoint","TOPLEFT",scroll,"TOPLEFT",0,0)
            self:Paint(content,"Show"); self:Paint(scroll,"Show")
            self.pages[key]=content; panel=content
        end
        self.readouts[key]=self:Text(panel,4,-4,580)
    end
    self:Paint(self.pageFrames.maintenance,"Hide")
    self.pageFrames.maintenance=self.pageFrames.customapl; self.pages.maintenance=self.pages.customapl; self.readouts.maintenance=self.readouts.customapl
    self:CreateCustomAPLEditor(self.pages.customapl)
    self:CreateSkillGroupEditor()
    local function button(page,label,x,y,w,fn) return self:Button(self.pages[page],label,x,y,w,fn) end
    local function selectEditor(key) self.editScene=key; self:ShowPage("profiles") end
    self.editScene=e.db.selectedPlans.manual
    self.manualPlanControls=self:CreateSegmentedControl(self.pages.profiles,{{"single","方案一"},{"multi","方案二"},{"third","方案三"}},0,-40,580,
        function() return self.editScene end,function(key) selectEditor(key) end)
    self:CreatePlanRename(self.pages.profiles,"manual",0,-80,function() return self.editScene end)
    self:CreateToggleRow(self.pages.profiles,"启用本方案",0,-120,284,
        function() return e.db.enabledPlans.manual[self.editScene] end,
        function(value) TEF.Profiles:SetPlanEnabled(e,"manual",self.editScene,value) end)
    self.manualUseButton=button("profiles","使用本方案",392,-120,188,function()
        local ok,reason=TEF.Profiles:UsePlan(e,"manual",self.editScene)
        self:SequenceMessage(ok and "已选择并停止派发；关闭设置后开启。" or "请先启用本方案。")
    end)
    local scroll=self:Frame("ScrollFrame",self.pages.profiles,"UIPanelScrollFrameTemplate")
    self:Paint(scroll,"SetPoint","TOPLEFT",self.pages.profiles,"TOPLEFT",8,-138); self:Paint(scroll,"SetSize",550,346)
    self.editorScroll=scroll
    local editor=self:Frame("EditBox",scroll)
    self.editor=editor
    self:Paint(editor,"SetSize",530,346); self:Paint(editor,"SetMultiLine",true)
    self:Paint(editor,"SetAutoFocus",false); self:Paint(editor,"SetMaxLetters",4096)
    self:Paint(editor,"SetFontObject",ChatFontNormal or GameFontHighlight)
    self:Paint(editor,"SetScript","OnTextChanged",function()
        local ok,raw=self:Invoke(editor,"GetText")
        local value=ok and S.Public(raw,"string")
        if value and #value<=4096 then
            local _,lines=value:gsub("\n","")
            self:Paint(editor,"SetHeight",math.max(346,math.min(600,(lines+2)*18)))
        end
    end)
    self:Paint(editor,"SetScript","OnEscapePressed",function() self:Paint(editor,"ClearFocus") end)
    self:Paint(scroll,"SetScrollChild",editor)
    self:Paint(scroll,"Hide") -- 内部草稿序列化载体，不再提供高级文本界面。
    local manualFooter=self:Footer(self.pages.profiles)
    self.editorMessage=self:Text(manualFooter,0,-4,580)
    self.manualUndoButton=self:CreateActionButton(manualFooter,"撤销删除",0,-52,120,function() self:UndoDelete("manual") end)
    self.manualSave=self:CreateActionButton(manualFooter,"保存配置",436,-52,144,function()
        if not self:CommitSequenceCounts() then return end
        if not self:CommitCustomNumbers() then return end
        local ok,raw=self:Invoke(editor,"GetText")
        local rows=ok and self:DraftRows()
        local saved,reason=false,"CONFIG_INVALID"
        if rows then saved,reason=TEF.Profiles:Save(e,self.editScene,rows) end
        if saved then self.drafts[(e.profileKey or "unknown") .. ":" .. self.editScene]=nil end
        self:Paint(self.editorMessage,"SetText",saved and "方案已保存；旧派发已停止并重置。" or ("未保存：" .. reason))
        self:Paint(editor,"ClearFocus")
    end)
    button("scene","切换单体",4,-345,115,function() TEF.Profiles:Select(e,"single") end)
    button("scene","切换多目标",129,-345,115,function() TEF.Profiles:Select(e,"multi") end)
    self:CreateSectionCard(self.pages.overview,"派发状态",0,0,580,100)
    self.overviewBadge=self:CreateStatusBadge(self.pages.overview,16,-38,368)
    self.intentToggle=self:CreateToggleRow(self.pages.overview,"派发启/停",16,-64,548,
        function() return TEF.Runtime:IsDispatchIntentEnabled() end,function() TEF_ToggleDispatchIntent() end)
    self:CreateSectionCard(self.pages.overview,"运行模式",0,-112,580,80)
    self.modeControls=self:CreateSegmentedControl(self.pages.overview,{{"auto","自动启停"},{"manual","手动启停"},{"stop","脱战后停止"}},16,-152,548,
        function() return e.db.dispatch.mode end,function(value) TEF.Runtime:SetMode(value) end)
    self:CreateToggleRow(self.pages.overview,"登录/reload自动启动（创建新意图）",16,-208,548,
        function() return e.db.dispatch.autoStart end,function(value) e.db.dispatch.autoStart=value end)
    self:CreateSectionCard(self.pages.overview,"当前配置",0,-260,580,168)
    self:Paint(self.readouts.overview,"ClearAllPoints")
    self:Paint(self.readouts.overview,"SetPoint","TOPLEFT",self.pages.overview,"TOPLEFT",16,-344)
    self:CreateSectionCard(self.pages.overview,"派发启停快捷键",0,-444,580,152)
    self:CreateHotkeyRow(self.pages.overview,16,-484,548)
    self:CreateHintText(self.pages.overview,"仅接纳未绑定的快捷键；不会覆盖其他技能或系统绑定。",16,-564,548)
    self:Paint(self.pages.overview,"SetHeight",612)
    local loopPanel=self:Frame("Frame",self.pages.profiles); self.manualLoopPanel=loopPanel
    self:Paint(loopPanel,"SetSize",580,280); self:Paint(loopPanel,"SetPoint","TOPLEFT",self.pages.profiles,"TOPLEFT",0,-624)
    self:CreateSectionCard(loopPanel,"循环 / 重置",0,0,580,280)
    self.loopModeControls=self:CreateSegmentedControl(loopPanel,{{"none","不循环"},{"normal","普通循环"},{"target","切目标重置"},{"combat","脱战重置"}},16,-48,548,
        function() return e.db.loopMode end,function(v) TEF.Runtime:SetLoopMode(v) end)
    self:CreateHintText(loopPanel,"普通循环：末步完成后回首步。\n切目标重置：目标变化时回首步，次数清零。\n脱战重置：退出战斗时回首步，次数清零。\n切换循环模式会停止并重置；手动停止不会自动恢复。",16,-96,548)
    self.testReset=self:CreateActionButton(loopPanel,"重置并停止",16,-224,188,function() TEF.Runtime:Reset() end)
    self:CreateSequenceEditor(self.pages.profiles)
    self.sourceMessage=self:Text(self.pages.overview,16,-400,550,"GameFontHighlightSmall")
    self.sourceSelect=self:CreateSegmentedControl(self.pages.overview,{{"manual","列表循环"},{"apl","优先级推荐"}},16,-300,548,
        function() return TEF.Recommendation:BaseSource(e,e.scene) end,
        function(value)
            if value=="apl" and e.db.apl.template~="custom" then TEF.APL:Configure(e,"template","custom") end
            local ok,reason=TEF.Profiles:UsePlan(e,value,e.db.selectedPlans[value])
            self:Paint(self.sourceMessage,"SetText",ok and "来源已切换并停止；关闭设置后主动开启。" or ("来源未切换：" .. reason))
        end)
    self:Paint(self.readouts.hud,"SetText","")
    self:Paint(self.readouts.hud,"Hide")
    self:CreateSectionCard(self.pages.hud,"标签样式",0,0,580,512)
    local labelPanel=self:Frame("Frame",self.pages.hud); self.labelStylePanel=labelPanel
    self:Paint(labelPanel,"SetSize",548,440); self:Paint(labelPanel,"SetPoint","TOPLEFT",self.pages.hud,"TOPLEFT",16,-48)
    TEF.HudStyles:BuildUI(self,labelPanel)
    self:CreateSectionCard(self.pages.hud,"HUD位置与缩放",0,-528,580,248)
    self.hudSlider=self:CreateSliderRow(self.pages.hud,"整体缩放",16,-576,548,.6,1,.1,
        function() return math.min(1,e.db.hud.scale) end,function(value) e.db.hud.scale=value; self:Layout() end)
    self:CreateToggleRow(self.pages.hud,"锁定位置",16,-632,548,function() return e.db.hud.locked end,function(value) e.db.hud.locked=value end)
    self:CreateToggleRow(self.pages.hud,"显示后续预览",16,-680,548,function() return e.db.hud.preview end,function(value) e.db.hud.preview=value end)
    button("hud","恢复位置",16,-728,188,function()
        self:ConfirmAction("确认将HUD恢复到默认位置？其他设置保留。",function()
            if self:Combat()~=false then return end
            e.db.position=nil; e.db.hud.x=nil; e.db.hud.y=nil
            self:Paint(self.frame,"ClearAllPoints"); self:Paint(self.frame,"SetPoint","CENTER",UIParent,"CENTER",0,0)
            self:Paint(TEF.HUD.frame,"ClearAllPoints"); self:Paint(TEF.HUD.frame,"SetPoint","CENTER",UIParent,"CENTER",0,-155)
        end,"恢复位置")
    end)
    self:CreateSectionCard(self.pages.hud,"技能图标大小与间距",0,-792,580,392)
    local geometryRows={{"mainSize","当前技能大小",32,44},{"preview1Size","后续技能1大小",24,36},{"preview2Size","后续技能2大小",24,36},{"gap1","主图标与文字间距",2,6},{"gap2","后续1与2间距",2,4}}
    self.hudGeometryControls={}
    for i,row in ipairs(geometryRows) do local field=row[1]
        local slider,input=self:CreateSliderRow(self.pages.hud,row[2],16,-840-(i-1)*64,548,row[3],row[4],1,
            function() return math.min(row[4],e.db.hud.geometry[field]) end,function(value) if e.db.hud.mode=="mini" then return end; e.db.hud.geometry[field]=value; TEF.HUD:Layout() end,true)
        self.hudGeometryControls[field]={slider=slider,input=input}
        self:AddControlSync(function()
            local enabled=e.db.hud.mode~="mini"
            self:Paint(slider,enabled and "Enable" or "Disable"); self:Paint(input,"EnableMouse",enabled); self:Paint(input,"EnableKeyboard",enabled)
            if not enabled then self:Paint(input,"ClearFocus") end
            slider.tefDisabledReason=not enabled and "迷你HUD采用固定图标大小与间距；切回标准HUD后可调整。" or nil
            input.tefDisabledReason=slider.tefDisabledReason
        end,slider)
    end
    self:CreateHintText(self.pages.hud,"迷你HUD固定图标大小与间距，以上几何设置仅用于标准HUD。左键主卡启停，右键设置；空白可拖动。",16,-1208,548)
    self:Paint(self.pages.hud,"SetHeight",1268)
    self:CreateSectionCard(self.pages.tek,"高级能力门禁",0,-138,580,238)
    self.signalToggle=self:CreateToggleRow(self.pages.tek,"TEAP输出",12,-176,556,function() return e.db.dispatch.signal end,function(v) TEF.Runtime:SetSignal(v) end)
    self.permissionToggle=self:CreateToggleRow(self.pages.tek,"TEK请求许可",12,-220,556,function() return e.db.dispatch.permission end,function(v) TEF.Runtime:SetPermission(v) end)
    self.castQueueToggle=self:CreateToggleRow(self.pages.tek,"读条末尾提前排队（实验）",12,-264,556,function() return e.db.dispatch.castQueue end,function(v) TEF.Runtime:SetCastQueue(v) end)
    self.castQueueLeadSlider=self:CreateSliderRow(self.pages.tek,"提前时间（秒，0关闭提前）",14,-306,550,0,.5,.05,
        function() return e.db.dispatch.castQueueLead end,function(v) TEF.Runtime:SetCastQueueLead(v) end)
    self:CreateHintText(self.pages.tek,"正常使用只需主卡或派发启停。以上是高级门禁。\n设置期间零Token，关闭后按模式恢复新请求。\n固定练习不保证ready。只保留一个信号源。\n提前时间0–0.5秒，0不提前；实际受客户端排队窗口上限约束。\n排队仅固定序列普通读条，不含APL或引导。\nTEK等待事件时可能重复输入；插件不证明已连接。",12,-400,550)
    self:Paint(self.readouts.diagnostics,"ClearAllPoints"); self:Paint(self.readouts.diagnostics,"SetPoint","TOPLEFT",self.pages.diagnostics,"TOPLEFT",4,-104)
    for i,option in ipairs({{"explain","策略解释"},{"audit","配置体检"},{"timeline","事件时间线"}}) do
        local mode=option[1]
        button("diagnostics",option[2],4+(i-1)*192,0,184,function() self.diagnosticMode=mode; if mode=="explain" then self.diagnosticReport=TEF.APL.Custom:Explain(e) end; self:RefreshPage() end)
    end
    self.testSingle=button("diagnostics","单步派发测试",4,-44,184,function() TEF_RequestCurrent() end)
    self:SetControlEnabled(self.testSingle,false,"设置期间禁止派发；关闭设置后使用 /tef dispatch。")
    self:CreateSelectRow(self.pages.tek,"施放非当前步骤技能后",{{"continue","保留原进度"},{"pause","暂停等待手动继续"}},12,-584,550,
        function() return e.db.dispatch.takeover end,function(v) TEF.Runtime:Stop("TAKEOVER_SETTING_CHANGED"); e.db.dispatch.takeover=v end)
    self:Paint(self.pages.tek,"SetHeight",680)
    for _,panel in pairs(self.pageFrames or self.pages) do self:Paint(panel,"Hide") end
    self:CreateStudio()
    self.settingsLayoutSignature=nil
end
function UI:Create(engine)
    self.engine=engine; self.previews={}
    local f=self:Frame("Frame",UIParent,"BackdropTemplate","TEF_PracticePanel")
    self.frame=f; self:Paint(f,"SetSize",390,285); self:Backdrop(f)
    local pos=engine.db.position or {x=0,y=0}
    self:Paint(f,"SetPoint","CENTER",UIParent,"CENTER",pos.x,pos.y)
    self:Paint(f,"SetMovable",true); self:Paint(f,"EnableMouse",true); self:Paint(f,"RegisterForDrag","LeftButton")
    self:Paint(f,"SetScript","OnDragStart",function()
        if not engine.db.hud.locked and self:Combat()==false then self:Paint(f,"StartMoving") end
    end)
    self:Paint(f,"SetScript","OnDragStop",function()
        self:Paint(f,"StopMovingOrSizing")
        local ok,_,_,_,rx,ry=self:Invoke(f,"GetPoint",1)
        if ok then
            local x,y=S.Public(rx,"number"),S.Public(ry,"number")
            if x and y and math.abs(x)<=10000 and math.abs(y)<=10000 then engine.db.position={x=x,y=y} end
        end
    end)
    self:Paint(self:Text(f,16,-12,355,"GameFontNormal"),"SetText","TEF " .. TEF.Version .. " · 方案配置")
    local made,icon=self:Invoke(f,"CreateTexture",nil,"ARTWORK")
    if made then self.icon=icon; self:Paint(icon,"SetSize",62,62); self:Paint(icon,"SetPoint","TOPLEFT",f,"TOPLEFT",18,-43)
    else self:Error() end
    self.name=self:Text(f,92,-45,278,"GameFontNormalLarge")
    self.progress=self:Text(f,92,-75,278)
    self.detail=self:Text(f,18,-117,355,"GameFontHighlightSmall")
    for i=1,2 do
        local got,texture=self:Invoke(f,"CreateTexture",nil,"ARTWORK")
        if not got then self:Error() end
        self:Paint(texture,"SetSize",30,30); self:Paint(texture,"SetPoint","TOPLEFT",f,"TOPLEFT",18+(i-1)*177,-142)
        self.previews[i]={icon=texture,label=self:Text(f,55+(i-1)*177,-150,135,"GameFontHighlightSmall")}
    end
    self:Button(f,"开始",18,-188,78,function() TEF.Runtime:Start(true) end)
    self.pause=self:Button(f,"继续",106,-188,78,function() TEF_ToggleDispatchIntent() end)
    self:Button(f,"重置",194,-188,78,function() TEF.Runtime:Reset() end)
    self:Button(f,"设置",282,-188,85,function() self:OpenSettings() end)
    self.loop=self:Frame("CheckButton",f,"UICheckButtonTemplate")
    self:Paint(self.loop,"SetPoint","TOPLEFT",f,"TOPLEFT",16,-222)
    self:Paint(self.loop,"SetScript","OnClick",function()
        local ok,raw=self:Invoke(self.loop,"GetChecked")
        local value=ok and S.Public(raw,"boolean")
        if value~=nil then engine:SetLoop(value) end
        self:Refresh()
    end)
    self:Paint(self:Text(f,48,-229,160,"GameFontHighlightSmall"),"SetText","完成后循环")
    self:Button(f,"方案配置",220,-225,145,function()
        self:OpenSettings(); self:ShowPage(TEF.Recommendation:Source(engine)=="apl" and "customapl" or "profiles")
    end)
    self.status=self:Text(f,18,-261,355,"GameFontNormal")
    self:Layout(); self:Refresh()
end
