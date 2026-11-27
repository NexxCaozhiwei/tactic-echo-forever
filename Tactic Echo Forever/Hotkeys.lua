local _,TEF=...
local S,H=TEF.Safety,{}
TEF.Hotkeys=H
local bindings={
    {"hotkey","TEF_TOGGLE_DISPATCH"},
    {"gateKey1","TEF_OPEN_DISPATCH_GATE_1"},
    {"gateKey2","TEF_OPEN_DISPATCH_GATE_2"},
}
function H.Normalize(raw,gate)
    local key=S.Public(raw,"string")
    if not key or #key>40 then return nil end
    key=key:upper():gsub("%s","")
    if key=="" then return "" end
    local rest=key
    for _,prefix in ipairs({"CTRL-","ALT-","SHIFT-"}) do
        if rest:sub(1,#prefix)==prefix then rest=rest:sub(#prefix+1) end
    end
    -- 中文输入法的中点对应客户端绑定名中的反引号。
    if gate and rest=="·" then return key:sub(1,#key-#rest) .. "`" end
    local punctuation=gate and #rest==1 and ([=[`~!@#$%^&*()_+[]{}\;:'",.<>/?]=]):find(rest,1,true)
    if rest:match("^[A-Z0-9]+$") or rest=="-" or rest=="=" or punctuation then
        if rest=="CTRL" or rest=="ALT" or rest=="SHIFT" or rest=="ESCAPE" or rest=="UNKNOWN" or rest:match("^[LR]CTRL$") or rest:match("^[LR]ALT$") or rest:match("^[LR]SHIFT$") or rest:match("CONTROL$") then return nil end
        return key
    end
end
function H:Result(ok,reason)
    self.pending=not ok
    if self.lastReason~=reason then
        self.lastReason=reason
        if TEF.engine then TEF.engine:Log("lifecycle",reason) end
    end
    return ok,reason
end
function H:Status(field,reason)
    local labels={HOTKEY_APPLIED="已生效",HOTKEY_DEFERRED="已保存，等待脱战应用",
        HOTKEY_CONFLICT_UNKNOWN="未生效：无法验证快捷键绑定",
        HOTKEY_VERIFY_FAILED="已保存，绑定未验证",HOTKEY_APPLY_FAILED="已保存，绑定应用失败",
        HOTKEY_CLEAR_FAILED="已保存，旧绑定清理失败",HOTKEY_OWNER_FAILED="未生效：绑定所有者创建失败",
        HOTKEY_INVALID="未保存：快捷键无效",
        HOTKEY_DUPLICATE="未保存：此键已用于另一项派发控制",
        HOTKEY_SEMI_AUTO_KEY="半自动支持字母、数字或 F1–F12 单键"}
    local key=TEF.engine and TEF.engine.db.dispatch[field or "hotkey"] or ""
    local last=self.lastReason
    if field and field~="hotkey" then
        local index=field=="gateKey1" and 1 or 2
        if key=="" and not (self.appliedGateKeys and (self.appliedGateKeys[index] or "")~="") then last=nil
        elseif key~="" and self.appliedGateKeys and self.appliedGateKeys[index]==key then last="HOTKEY_APPLIED" end
        if key=="" and not last and not reason then return "未设置" end
    end
    return "已保存：" .. (key=="" and "未设置" or key) .. " · " .. (labels[reason or last] or "等待应用")
end
function H.IsSemiAutoKey(key)
    return key and (key:match("^[A-Z0-9]$") or key:match("^F[1-9]$") or key:match("^F1[0-2]$"))~=nil
end
function H.SemiAutoVK(key)
    if not H.IsSemiAutoKey(key) then return nil end
    return #key==1 and key:byte() or 111+tonumber(key:sub(2))
end
function H:SetSemiAuto(enabled,key)
    local dispatch=TEF.engine.db.dispatch
    key=key or dispatch.hotkey
    if enabled then
        if not H.IsSemiAutoKey(key) then return self:Result(false,"HOTKEY_SEMI_AUTO_KEY") end
        if key==dispatch.gateKey1 or key==dispatch.gateKey2 then return self:Result(false,"HOTKEY_DUPLICATE") end
        local eligible,reason=self:Check(key)
        if not eligible then return self:Result(false,reason) end
    end
    if enabled then
        TEF.Runtime:SetMode("semi")
        return self:Set(key)
    end
    if dispatch.mode=="semi" then TEF.Runtime:SetMode("manual") end
    return self:Apply()
end
function H:Apply()
    if self.applying then return false,"HOTKEY_REENTRANT" end
    self.applying=true
    local called,ok,reason=pcall(self.ApplyCurrent,self)
    self.applying=false
    if not called then return self:Result(false,"HOTKEY_APPLY_FAILED") end
    return self:Result(ok,reason)
end
function H:Check(key)
    if key=="" then return true,nil,"" end
    -- 已有绑定保留在底层，TEF 临时覆盖只在插件生效期间优先。
    for _,includeOverrides in ipairs({false,true}) do
        local known,raw=S.Call("GetBindingAction",key,includeOverrides)
        local command=known and S.Public(raw,"string")
        if not command then return false,"HOTKEY_CONFLICT_UNKNOWN" end
        if includeOverrides then return true,nil,command end
    end
end
function H:ApplyCurrent()
    local dispatch=TEF.engine.db.dispatch
    local desired,used,conflict={},{},nil
    local applied=self.appliedGateKeys or {}
    local unchanged=self.owner~=nil
    for i,binding in ipairs(bindings) do
        local key=H.Normalize(dispatch[binding[1]] or "",i~=1)
        if not key then return false,"HOTKEY_INVALID" end
        if key~="" and used[key] then return false,"HOTKEY_DUPLICATE" end
        desired[i]=key; used[key]=true
        local eligible,actual
        if i==1 then
            local reason
            eligible,reason,actual=self:Check(key)
            if not eligible then conflict=reason end
        elseif key~="" then
            -- 开门键只核对临时覆盖，原动作条命令不参与校验。
            local found,raw=S.Call("GetBindingAction",key,true)
            actual=found and S.Public(raw,"string")
            eligible=actual~=nil and actual~=false
        else
            eligible=true
        end
        local installed=i==1 and self.appliedKey or applied[i-1]
        if not eligible or (installed or "")~=key or (key~="" and actual~=binding[2]) then unchanged=false end
    end
    if unchanged then return true,"HOTKEY_APPLIED" end
    local ok,raw=S.Call("InCombatLockdown")
    local combat
    if ok then combat=S.Public(raw,"boolean") end
    if combat~=false then self.pending=true; return false,"HOTKEY_DEFERRED" end
    if not self.owner then
        if conflict then return false,conflict end
        self.owner=TEF.UI:Frame("Frame",UIParent,nil,"TEF_HotkeyOwner")
        if not self.owner then return false,"HOTKEY_OWNER_FAILED" end
    end
    local cleared=S.Call("ClearOverrideBindings",self.owner)
    if not cleared then return false,"HOTKEY_CLEAR_FAILED" end
    self.appliedKey=nil; self.appliedGateKeys={}; self.gateHeld={}
    if conflict then return false,conflict end
    for i,binding in ipairs(bindings) do
        local key=desired[i]
        if key~="" then
            local installed,result=S.Call("SetOverrideBinding",self.owner,true,key,binding[2])
            local value,classification=S.Public(result,"boolean")
            local verified,actual=S.Call("GetBindingAction",key,true)
            local reason
            if not installed or (classification~="NO_DATA" and value~=true) then reason="HOTKEY_APPLY_FAILED"
            elseif not verified or S.Public(actual,"string")~=binding[2] then reason="HOTKEY_VERIFY_FAILED" end
            if reason then
                if not S.Call("ClearOverrideBindings",self.owner) then return false,"HOTKEY_CLEAR_FAILED" end
                return false,reason
            end
        end
    end
    self.appliedKey=desired[1]; self.appliedGateKeys={desired[2],desired[3]}
    self.pending=false; return true,"HOTKEY_APPLIED"
end
function H:Set(raw,field)
    if self.applying then return false,"HOTKEY_REENTRANT" end
    field=field or "hotkey"
    if field~="hotkey" and field~="gateKey1" and field~="gateKey2" then return self:Result(false,"HOTKEY_INVALID") end
    local key=H.Normalize(raw,field~="hotkey")
    if not key then return self:Result(false,"HOTKEY_INVALID") end
    local dispatch=TEF.engine.db.dispatch
    for _,binding in ipairs(bindings) do
        if key~="" and binding[1]~=field and dispatch[binding[1]]==key then return self:Result(false,"HOTKEY_DUPLICATE") end
    end
    if field=="hotkey" and dispatch.mode=="semi" and key~="" and not H.IsSemiAutoKey(key) then
        return self:Result(false,"HOTKEY_SEMI_AUTO_KEY")
    end
    if field=="hotkey" then
        local eligible,conflict=self:Check(key)
        if not eligible then return self:Result(false,conflict) end
    end
    if dispatch[field]~=key then
        if field~="hotkey" then TEF.Runtime:Stop("GATE_HOTKEY_CHANGED")
        elseif dispatch.mode=="semi" then
            TEF.Runtime:Stop("SEMI_AUTO_HOTKEY_CHANGED")
            TEF.Runtime.semiAutoHeld=false
        end
    end
    dispatch[field]=key
    local ok,reason=self:Apply()
    TEF.Dispatch:BindingsChanged()
    return ok,reason
end
function H:GateKey(index,rawState)
    if index~=1 and index~=2 then return end
    local state=S.Public(rawState,"string")
    self.gateHeld=self.gateHeld or {}
    if state=="up" then self.gateHeld[index]=nil; return end
    if state~="down" or self.gateHeld[index] then return end
    local key=self.appliedGateKeys and self.appliedGateKeys[index]
    if not key or key=="" or not TEF.engine or TEF.engine.db.dispatch["gateKey"..index]~=key then return end
    self.gateHeld[index]=true
    TEF.Runtime:OpenGateRound()
end
function H:Capture(editor,rawKey,gate)
    local key=S.Public(rawKey,"string")
    if not key then return end
    if key=="ESCAPE" then TEF.UI:Call(editor,"ClearFocus"); return true,nil end
    if key=="CTRL" or key=="ALT" or key=="SHIFT" or key:match("CONTROL$") or key:match("^[LR]CTRL$") or key:match("^[LR]ALT$") or key:match("^[LR]SHIFT$") then return false end
    local parts={}
    for _,entry in ipairs({{"IsControlKeyDown","CTRL"},{"IsAltKeyDown","ALT"},{"IsShiftKeyDown","SHIFT"}}) do
        local ok,raw=S.Call(entry[1]); local down
        if ok then down=S.Public(raw,"boolean") end
        if down==nil then return end
        if down then parts[#parts+1]=entry[2] end
    end
    parts[#parts+1]=key
    local normalized=H.Normalize(table.concat(parts,"-"),gate)
    if normalized then TEF.UI:Call(editor,"SetText",normalized); TEF.UI:Call(editor,"ClearFocus"); return true,normalized end
end
