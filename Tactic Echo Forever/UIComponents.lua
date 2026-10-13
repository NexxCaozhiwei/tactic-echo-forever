local _,TEF=...
local U,S=TEF.UI,TEF.Safety
-- Independent TEUI-style components. Presentation holds no input authority.
U.controls={}
U.controlHeight=28
U.controlFontSize=12
function U:ApplyControlFont(control,isButton)
    local target=control
    if isButton then local ok,font=self:Invoke(control,"GetFontString"); if not ok or not font then return end; target=font end
    local ok,path,_,flags=self:Invoke(GameFontHighlightSmall,"GetFont")
    path=ok and S.Public(path,"string") or S.Public(STANDARD_TEXT_FONT,"string")
    flags=S.Public(flags,"string") or ""
    if path then self:Paint(target,"SetFont",path,self.controlFontSize,flags) end
end
function U:CreatePlanRename(parent,source,x,y,getter)
    self.planRenameBoxes=self.planRenameBoxes or {}
    local group=self:Frame("Frame",parent); self:Paint(group,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y); self:Paint(group,"SetSize",550,28)
    parent=group; x=0; y=0
    self:CreateHintText(parent,"方案名称",x,y-7,75)
    local box=self:SequenceInput(parent,x+80,y,270); self:Paint(box,"SetMaxLetters",64)
    self.planRenameBoxes[source]={box=box,getter=getter,frame=group}
    local function save()
        local ok,raw=self:Invoke(box,"GetText")
        local valid=ok and TEF.Profiles:SetPlanName(self.engine,source,getter(),raw)
        local text=valid and "方案名称已保存；空白恢复默认名称。" or "名称无效：最多64字节，不允许控制符或竖线。"
        if source=="manual" then self:SequenceMessage(text) else self:CustomMessage(text) end
        self:Paint(box,"ClearFocus"); self:RefreshPlanFeedback()
    end
    self:CreateActionButton(parent,"保存名称",x+365,y,120,save)
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
            local letters={}; for letter in text:gmatch("[\1-\127\194-\244][\128-\191]*") do letters[#letters+1]=letter end
            if #letters>9 then local short={}; for i=1,9 do short[i]=letters[i] end; text=table.concat(short) .. "…" end
            self:Paint(button,"SetText",(using and "|cff80ffcc" or "") .. text .. (using and " · 当前|r" or ""))
        end
        local using=active==source and e.scene==key and e.db.enabledPlans[source][key]==true
        local button=source=="manual" and self.manualUseButton or self.customUseButton
        if button then button.tefControlSelected=using; self:Paint(button,"SetText",using and "正在使用" or "使用本方案"); self:SetControlEnabled(button,key and e.db.enabledPlans[source][key]==true) end
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
    b.tefControlEnabled=true
    self:Paint(b,"SetSize",width or 120,self.controlHeight); self:Paint(b,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
    self:Paint(b,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    self:Paint(b,"SetBackdropColor",.07,.10,.15,1); self:Paint(b,"SetBackdropBorderColor",.21,.29,.39,1)
    self:Paint(b,"SetNormalFontObject",GameFontHighlightSmall)
    self:Paint(b,"SetText",label)
    self:ApplyControlFont(b,true)
    self:Paint(b,"SetScript","OnEnter",function() if b.tefControlEnabled then self:Call(b,"SetBackdropColor",.12,.20,.28,1) end end)
    self:Paint(b,"SetScript","OnLeave",function() self:SetControlEnabled(b,b.tefControlEnabled) end)
    self:Paint(b,"SetScript","OnClick",function() if b.tefControlEnabled then self:Guard(callback); self:Refresh() end end)
    return b
end
function U:SetControlEnabled(button,enabled)
    button.tefControlEnabled=enabled==true
    self:Paint(button,enabled==true and "Enable" or "Disable")
    if enabled==true and button.tefControlSelected==true then
        self:Paint(button,"SetBackdropColor",.08,.23,.20,1)
        self:Paint(button,"SetBackdropBorderColor",.25,.85,.65,1)
    else
        self:Paint(button,"SetBackdropColor",enabled==true and .07 or .035,enabled==true and .10 or .045,enabled==true and .15 or .06,1)
        self:Paint(button,"SetBackdropBorderColor",enabled==true and .21 or .10,enabled==true and .29 or .13,enabled==true and .39 or .17,1)
    end
end
function U:CreateSectionCard(parent,title,x,y,width,height)
    -- Page text must be above its decoration. A child backdrop Frame has a
    -- higher frame level than the parent's FontStrings and obscures them.
    local ok,bg=self:Invoke(parent,"CreateTexture",nil,"BACKGROUND")
    if not ok then self:Error(); return end
    self:Paint(bg,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y); self:Paint(bg,"SetSize",width,height)
    self:Paint(bg,"SetColorTexture",.04,.06,.095,.92)
    for _,edge in ipairs({{x,y,width,1},{x,y-height+1,width,1},{x,y,1,height},{x+width-1,y,1,height}}) do
        local made,line=self:Invoke(parent,"CreateTexture",nil,"BORDER")
        if made then
            self:Paint(line,"SetPoint","TOPLEFT",parent,"TOPLEFT",edge[1],edge[2])
            self:Paint(line,"SetSize",edge[3],edge[4]); self:Paint(line,"SetColorTexture",.13,.19,.27,1)
        else self:Error() end
    end
    self:Paint(self:Text(parent,x+12,y-10,width-24,"GameFontNormal"),"SetText",title)
    return bg
end
function U:CreateHintText(parent,text,x,y,width)
    local t=self:Text(parent,x,y,width,"GameFontHighlightSmall")
    self:Paint(t,"SetText",text); self:Paint(t,"SetTextColor",.60,.68,.78,1); return t
end
function U:CreateDivider(parent,x,y,width)
    local ok,t=self:Invoke(parent,"CreateTexture",nil,"BACKGROUND")
    if not ok then return end
    self:Paint(t,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y); self:Paint(t,"SetSize",width,1)
    self:Paint(t,"SetColorTexture",.16,.22,.30,1); return t
end
function U:CreateToggleRow(parent,label,x,y,width,getter,setter)
    local text=self:Text(parent,x,y-6,width-95); self:Paint(text,"SetText",label)
    local b=self:CreateActionButton(parent,"",x+width-85,y,85,function() setter(not getter()) end)
    local function sync()
        local enabled=getter()==true
        b.tefControlSelected=enabled
        self:Paint(b,"SetText",enabled and "开启" or "关闭")
        self:SetControlEnabled(b,b.tefControlEnabled)
    end
    self.controls[#self.controls+1]=sync; sync(); return b,text
end
function U:CreateSegmentedControl(parent,choices,x,y,width,getter,setter)
    local out={}; local cell=(width-(#choices-1)*6)/#choices
    for i,choice in ipairs(choices) do
        local value,label=choice[1],choice[2]
        local b=self:CreateActionButton(parent,label,x+(i-1)*(cell+6),y,cell,function() setter(value) end)
        out[value]=b
        self.controls[#self.controls+1]=function()
            local active=getter()==value
            b.tefControlSelected=active
            self:Paint(b,"SetText",active and ("|cff80ffcc● " .. label .. "|r") or label)
            self:SetControlEnabled(b,b.tefControlEnabled)
        end
    end
    return out
end
function U:CreateSelectRow(parent,label,choices,x,y,width,getter,setter)
    self:Paint(self:Text(parent,x,y,width),"SetText",label)
    return self:CreateSegmentedControl(parent,choices,x,y-25,width,getter,setter)
end
function U:CreateSliderRow(parent,label,x,y,width,min,max,step,getter,setter,editable)
    local text=self:Text(parent,x,y,width)
    local slider=self:Frame("Slider",parent,"OptionsSliderTemplate")
    self:Paint(slider,"SetPoint","TOPLEFT",parent,"TOPLEFT",x+8,y-25); self:Paint(slider,"SetSize",width-16,18)
    self:Paint(slider,"SetMinMaxValues",min,max); self:Paint(slider,"SetValueStep",step); self:Paint(slider,"SetObeyStepOnDrag",true)
    local syncing=false
    local input
    if editable then
        input=self:SequenceInput(parent,x+width-82,y+5,76)
        self:Paint(text,"SetWidth",width-90)
        local function submit()
            local ok,raw=self:Invoke(input,"GetText")
            local value=ok and S.Public(raw,"string")
            local n=value and value:match("^%s*%d+%s*$") and tonumber(value)
            if not n or n<min or n>max then
                self:Paint(text,"SetText",label .. "：须为" .. min .. "–" .. max .. "的整数")
                self:Paint(input,"SetText",tostring(getter()))
                return
            end
            self:Guard(setter,n); self:Refresh()
        end
        self:Paint(input,"SetScript","OnEnterPressed",function() submit(); self:Paint(input,"ClearFocus") end)
        self:Paint(input,"SetScript","OnEditFocusLost",submit)
    end
    self:Paint(slider,"SetScript","OnValueChanged",function(_,raw)
        local v=S.Public(raw,"number")
        if syncing or not v or v<min or v>max then return end
        self:Guard(setter,math.floor(v/step+.5)*step); self:Refresh()
    end)
    self.controls[#self.controls+1]=function()
        local value=getter(); self:Paint(text,"SetText",editable and (label .. "（" .. min .. "–" .. max .. "）") or (label .. "  " .. string.format(step<.1 and "%.2f" or "%.1f",value)))
        if input then
            local focused,raw=self:Invoke(input,"HasFocus")
            if not focused or S.Public(raw,"boolean")~=true then self:Paint(input,"SetText",tostring(value)) end
        end
        syncing=true; self:Paint(slider,"SetValue",value); syncing=false
    end
    return slider,input
end
function U:CreateStatusBadge(parent,x,y,width)
    local text=self:Text(parent,x,y,width,"GameFontNormalLarge")
    return text
end
function U:CreateHotkeyRow(parent,x,y,width)
    local box=self:Frame("EditBox",parent,"InputBoxTemplate","TEF_HotkeyEditor")
    self:Paint(box,"SetSize",165,self.controlHeight); self:Paint(box,"SetPoint","TOPLEFT",parent,"TOPLEFT",x+5,y)
    self:ApplyControlFont(box)
    self:Paint(box,"SetAutoFocus",false); self:Paint(box,"SetMaxLetters",40)
    self:Paint(box,"EnableKeyboard",true)
    self:Paint(box,"SetText",self.engine.db.dispatch.hotkey)
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
    self.captureHotkeyButton=self:CreateActionButton(parent,"录入",x+185,y,70,function()
        self.captureHotkey=true; self:Call(box,"SetPropagateKeyboardInput",false); self:Paint(box,"SetFocus")
        self:Paint(self.hotkeyMessage,"SetText","按下组合键即保存并应用；Esc取消。")
    end)
    self.applyHotkeyButton=self:CreateActionButton(parent,"保存",x+265,y,70,function()
        local ok,raw=self:Invoke(box,"GetText"); if ok then submit(raw) end
    end)
    self.clearHotkeyButton=self:CreateActionButton(parent,"清除",x+345,y,70,function() submit("") end)
    self:Paint(self.hotkeyMessage,"SetText",TEF.Hotkeys:Status())
    return box
end
function U:RefreshControls()
    for _,sync in ipairs(self.controls) do self:Guard(sync) end
end
-- Old test panel uses the same visual/action primitive without owning runtime.
U.Button=U.CreateActionButton
