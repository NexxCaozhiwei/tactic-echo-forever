local _,TEF=...
local U,S,P=TEF.UI,TEF.Safety,TEF.Profiles

function U:SequenceMessage(text)
    self:Paint(self.editorMessage,"SetText",text)
end
function U:DraftRows()
    local ok,raw=self:Invoke(self.editor,"GetText")
    local text=ok and S.Public(raw,"string")
    if self.sequenceDraft and text==self.sequenceDraftText then return P:Clean(self.sequenceDraft,32) end
    if text=="" then return {} end
    return text and P:Parse(text,32)
end
function U:WriteDraft(rows)
    self.sequenceDraft=rows; self.sequenceDraftText=P:RowsText(rows)
    self:Paint(self.editor,"SetText",P:RowsText(rows))
    self:RefreshSequenceEditor(true)
end
function U:OpenSequencePolicy(index)
    if not self:PrepareGroupPanelSwitch(false) then return end
    if not self:CommitCustomNumbers() then return end
    local rows=self:DraftRows(); if not rows or not rows[index] then return end
    self.strategySource="manual"; self.sequencePolicyIndex=index; self.sequencePolicyRow=rows[index]
    self.sequencePolicyRow.strategies=self.sequencePolicyRow.strategies or {}
    self.customFormIndex=nil; self:RefreshStrategyForm(); self:Paint(self.strategyPanel,"Show")
end
function U:StoreSequencePolicy()
    if self.strategySource~="manual" or not self.sequencePolicyRow then return end
    local rows=self:DraftRows() or self.sequenceDraft; local row=rows and rows[self.sequencePolicyIndex]
    if not row or row.spellID~=self.sequencePolicyRow.spellID then return end
    row.strategies=self.sequencePolicyRow.strategies; row.enabled=self.sequencePolicyRow.enabled; row.targetMode=self.sequencePolicyRow.targetMode
    self:WriteDraft(rows)
    return self:DraftRows()~=nil
end
function U:ReorderSequenceRow(index,destination)
    local rows=self:DraftRows(); if not rows or not rows[index] or not rows[destination] then return end
    if not self:CommitCustomNumbers() then return end
    rows=self:DraftRows(); local row=table.remove(rows,index); table.insert(rows,destination,row)
    self:Paint(self.strategyPanel,"Hide"); self.sequencePolicyRow=nil; self:WriteDraft(rows)
end
function U:AddSequenceSpell(rawID,index)
    local id=S.ID(rawID)
    if not id or id==7268 then self:SequenceMessage("未新增：精确技能ID无效或为引导子事件。"); return false end
    local rows=self:DraftRows()
    if not rows then self:SequenceMessage("草稿无效，请重新编辑技能配置。"); return false end
    if #rows>=16 then self:SequenceMessage("未新增：每套最多16个技能步骤。"); return false end
    local view=S.Spell(id,"技能 " .. id)
    local row={spellID=id,name=view.reason=="PUBLIC" and view.name or ("技能 " .. id),matchIDs={id},repeatCount=1}
    table.insert(rows,index and math.min(index,#rows+1) or #rows+1,row)
    self:WriteDraft(rows)
    self:SequenceMessage(view.reason=="PUBLIC" and "已加入草稿；仅匹配该精确ID，点击保存生效。" or "已加入精确ID，但技能信息未解析；请核对后保存。")
    return true
end
function U:EditSequenceRow(index,operation,value)
    if not self:CommitCustomNumbers() then return false end
    local rows=self:DraftRows()
    if not rows or not rows[index] then return false end
    if operation=="delete" then table.remove(rows,index)
    elseif operation=="move" then
        local dest=index+value
        if dest<1 or dest>#rows then return false end
        rows[index],rows[dest]=rows[dest],rows[index]
    elseif operation=="skip" then
        rows[index].skipUnavailable=S.Public(value,"boolean")==true
    elseif operation=="usage" then
        local policy=S.Public(value,"string")
        if policy~="always" and policy~="target" and policy~="combat" then return false end
        rows[index].usagePolicy=policy
    elseif operation=="count" then
        if rows[index].spellID==6603 then
            self:RefreshSequenceEditor(true)
            self:SequenceMessage("攻击6603是开启步骤：确认自动攻击已开启一次后推进，不按平砍次数计数。"); return false
        end
        local text=S.Public(value,"string")
        local n=text and text:match("^%s*(%d+)%s*$") and tonumber(text)
        if not n or n<1 or n>99 then self:SequenceMessage("释放次数须为1–99的整数；草稿未改变。"); return false end
        if rows[index].repeatCount==n then return true end
        rows[index].repeatCount=n
    else return false end
    self.sequencePolicyRow=nil; self:Paint(self.strategyPanel,"Hide")
    self:WriteDraft(rows); self:SequenceMessage(operation=="usage" and value=="target"
        and "草稿已调整；目标GUID受限时按本次目标选择计一次，重新选中算新选择。点击保存生效。"
        or "草稿已调整，点击保存生效。")
    return true
end
function U:ReceiveSequenceSpell(index)
    local id,reason=TEF.ActionSources:Cursor()
    if reason=="NO_DATA" then return false end
    if not id then
        self.engine:Log("display",reason or "CURSOR_ID_UNVERIFIED")
        self:SequenceMessage("拖入未接纳：技能或宏的当前精确技能ID未确认（" .. (reason or "UNKNOWN") .. "）。")
        return false
    end
    if not self:AddSequenceSpell(id,index) then return false end
    local cleared=S.Call("ClearCursor")
    if not cleared then self.engine:Log("display","CURSOR_CLEAR_FAILED") end
    return true
end
function U:BindSequenceDrop(frame,index,click)
    self:Paint(frame,"EnableMouse",true)
    self:Paint(frame,"SetScript","OnReceiveDrag",function()
        self:Guard(function() self:ReceiveSequenceSpell(index) end)
    end)
    if click then
        self:Paint(frame,"SetScript","OnMouseUp",function(_,button)
            if S.Public(button,"string")=="LeftButton" then self:Guard(function() self:ReceiveSequenceSpell(index) end) end
        end)
    end
end
function U:SequenceInput(parent,x,y,width)
    local box=self:Frame("EditBox",parent,"InputBoxTemplate")
    self:Paint(box,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y); self:Paint(box,"SetSize",width,self.controlHeight or 28)
    self:ApplyControlFont(box)
    self:Paint(box,"SetAutoFocus",false); self:Paint(box,"SetMaxLetters",12)
    self:Paint(box,"SetScript","OnEscapePressed",function() self:Paint(box,"ClearFocus") end)
    return box
end
function U:RefreshSequenceEditor(force)
    if not self.sequenceRows then return end
    local ok,raw=self:Invoke(self.editor,"GetText")
    local text=ok and S.Public(raw,"string")
    if not force and text==self.sequenceRendered then return end
    self.sequenceRendered=text
    local rows=self:DraftRows()
    if rows and #rows>16 then self:SequenceMessage("旧配置超过16步，已保留；请逐行删除至16步以内再保存。") end
    self:Paint(self.editorScroll,"Hide")
    self:Paint(self.sequenceScroll,"Show")
    self:Paint(self.sequenceCount,"SetText",rows and (#rows .. "/16步 · 次数按独立成功事件计数") or "草稿无效，请重新编辑")
    for i,widgets in ipairs(self.sequenceRows) do
        local row=rows and rows[i]
        self:Paint(widgets.frame,row and "Show" or "Hide")
        if row then
            local view=row.unverified and S.Spell(row.name,row.name) or S.Spell(row.spellID,row.name)
            self:Paint(widgets.icon,"SetTexture",view.icon)
            self:Paint(widgets.groupEdit,row.group and "Show" or "Hide")
            self:Paint(widgets.name,"SetWidth",row.group and 170 or 278)
            self:Paint(widgets.name,"SetText",i .. ". " .. (row.group and ("【" .. row.group.name .. "】") or (view.name .. " · ID " .. row.spellID)) .. (row.enabled==false and " · 已停用" or ""))
            self:Paint(widgets.count,"SetText",tostring(row.repeatCount or 1))
            self:Paint(widgets.skip,"SetText",row.skipUnavailable and "不可用跳过：开" or "不可用跳过：关")
            self:Paint(widgets.skip,row.spellID==6603 and "Hide" or "Show")
            self:Paint(widgets.usage,"SetText",({always="每轮使用",target="同一目标只用一次",combat="同一战斗只用一次"})[row.usagePolicy or "always"])
            for _,control in ipairs({widgets.count,widgets.countLabel,widgets.skip,widgets.usage}) do self:Paint(control,row.group and "Hide" or "Show") end
            self:Paint(widgets.groupInfo,row.group and "Show" or "Hide")
            if row.group then self:Paint(widgets.groupInfo,"SetText",#row.group.steps .. "个组内技能 · 循环" .. row.group.rounds .. "轮 · 次数与跳过在组内设置") end
            self:SetControlEnabled(widgets.up,i>1); self:SetControlEnabled(widgets.down,i<#rows)
        end
    end
    self:Paint(self.sequenceChild,"SetHeight",math.max(355,rows and math.min(#rows,16)*72 or 355))
end
function U:CreateSequenceEditor(parent)
    self.sequenceAdvanced=false
    self:BindSequenceDrop(parent,nil,true)
    self.dropZone=self:CreateActionButton(parent,"拖入技能（追加）",4,-164,195,function() self:ReceiveSequenceSpell() end)
    self:Paint(self.dropZone,"RegisterForDrag","LeftButton")
    self:Paint(self.dropZone,"RegisterForClicks","LeftButtonUp")
    self:BindSequenceDrop(self.dropZone)
    self.spellIDInput=self:SequenceInput(parent,216,-164,90)
    self:Paint(self.spellIDInput,"SetText","")
    self:CreateActionButton(parent,"ID新增",317,-164,94,function()
        local ok,raw=self:Invoke(self.spellIDInput,"GetText")
        local text=ok and S.Public(raw,"string")
        local id=text and text:match("^%s*(%d+)%s*$") and tonumber(text)
        if self:AddSequenceSpell(id) then self:Paint(self.spellIDInput,"SetText",""); self:Paint(self.spellIDInput,"ClearFocus") end
    end)
    self:CreateActionButton(parent,"新建技能组",418,-164,140,function() self:AddSkillGroup("manual") end)
    self.sequenceCount=self:Text(parent,4,-199,560,"GameFontHighlightSmall")
    self:CreateSectionCard(parent,"技能列表 · 拖动条目排序，或使用上下箭头",0,-217,580,312)
    local scroll=self:Frame("ScrollFrame",parent,"UIPanelScrollFrameTemplate")
    self.sequenceScroll=scroll
    self:Paint(scroll,"SetPoint","TOPLEFT",parent,"TOPLEFT",4,-252); self:Paint(scroll,"SetSize",550,270)
    local child=self:Frame("Frame",scroll); self.sequenceChild=child
    self:Paint(child,"SetSize",540,355); self:Paint(scroll,"SetScrollChild",child)
    self:BindSequenceDrop(scroll,nil,true); self:BindSequenceDrop(child,nil,true)
    self.sequenceRows={}
    for i=1,16 do
        local index=i
        local row=self:Frame("Frame",child,"BackdropTemplate")
        self:Paint(row,"SetPoint","TOPLEFT",child,"TOPLEFT",0,-(i-1)*72); self:Paint(row,"SetSize",530,68)
        self:BindSequenceDrop(row,index,true)
        self:Paint(row,"SetBackdrop",{bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
        self:Paint(row,"SetBackdropColor",.05,.08,.12,1); self:Paint(row,"SetBackdropBorderColor",.25,.42,.58,1)
        self:Paint(row,"RegisterForDrag","LeftButton")
        self:Paint(row,"SetScript","OnDragStart",function() self:Guard(function() if self:CommitCustomNumbers() then self.sequenceDragging=index; self:Paint(row,"SetAlpha",.5) end end) end)
        self:Paint(row,"SetScript","OnDragStop",function() self:Guard(function()
            local source=self.sequenceDragging; self.sequenceDragging=nil; self:Paint(row,"SetAlpha",1)
            if not source then return end
            for target,w in ipairs(self.sequenceRows) do local ok,value=S.Call("MouseIsOver",w.frame)
                if ok and S.Public(value,"boolean")==true then self:ReorderSequenceRow(source,target); break end
            end
        end) end)
        local made,icon=self:Invoke(row,"CreateTexture",nil,"ARTWORK")
        if made then self:Paint(icon,"Hide") end
        local widgets={frame=row,icon=icon,name=self:Text(row,6,-7,278,"GameFontHighlightSmall"),count=self:SequenceInput(row,70,-38,46)}
        self:Paint(widgets.name,"SetWordWrap",false)
        self:BindSequenceDrop(widgets.count,index)
        widgets.countLabel=self:Text(row,6,-44,60,"GameFontHighlightSmall"); self:Paint(widgets.countLabel,"SetText","使用次数")
        widgets.groupInfo=self:Text(row,6,-44,505,"GameFontHighlightSmall")
        self:Paint(widgets.count,"SetScript","OnEnterPressed",function(box)
            self:Guard(function() local ok,raw=self:Invoke(box,"GetText"); if ok then self:EditSequenceRow(index,"count",raw) end end)
            self:Paint(box,"ClearFocus")
        end)
        self:Paint(widgets.count,"SetScript","OnEditFocusLost",function(box)
            self:Guard(function() local ok,raw=self:Invoke(box,"GetText"); if ok then self:EditSequenceRow(index,"count",raw) end end)
        end)
        widgets.groupEdit=self:CreateActionButton(row,"技能组编辑",180,-2,104,function() self:OpenSkillGroup("manual",index) end)
        widgets.policy=self:CreateActionButton(row,"编辑策略",290,-2,80,function() self:OpenSequencePolicy(index) end)
        widgets.up=self:CreateActionButton(row,"↑",376,-2,38,function() self:EditSequenceRow(index,"move",-1) end)
        widgets.down=self:CreateActionButton(row,"↓",420,-2,38,function() self:EditSequenceRow(index,"move",1) end)
        widgets.delete=self:CreateActionButton(row,"删",464,-2,52,function() self:EditSequenceRow(index,"delete") end)
        widgets.skip=self:CreateActionButton(row,"不可用跳过：关",132,-38,156,function()
            local rows=self:DraftRows()
            if rows and rows[index] then self:EditSequenceRow(index,"skip",not rows[index].skipUnavailable) end
        end)
        widgets.usage=self:CreateActionButton(row,"每轮使用",300,-38,215,function()
            local rows=self:DraftRows()
            if rows and rows[index] then self:EditSequenceRow(index,"usage",({always="target",target="combat",combat="always"})[rows[index].usagePolicy or "always"]) end
        end)
        for _,control in ipairs({widgets.up,widgets.down,widgets.delete,widgets.skip,widgets.usage}) do self:BindSequenceDrop(control,index) end
        self.sequenceRows[i]=widgets
    end
end
