local _,T=...
local S,M=T.Safety,{}
T.ActionSources=M
local function count(raw)
    local n=S.Public(raw,"number")
    return n and n>=0 and n<=256 and n%1==0 and n or nil
end
function M:Layout()
    local fn=S.Resolve("GetNumMacros")
    if not fn then return nil end
    local ok,a,c=pcall(fn); a=ok and count(a); c=ok and count(c)
    local limit,reason=S.Public(MAX_ACCOUNT_MACROS,"number")
    if reason=="NO_DATA" then limit=120 end
    limit=count(limit)
    if not a or not c or not limit or limit<a or a+c>256 or limit+c>256 then return nil end
    return {account=a,character=c,limit=limit}
end
function M:Index(id,layout)
    return id and layout and (id<=layout.account or (id>layout.limit and id<=layout.limit+layout.character))
end
local function trim(text) return text:match("^%s*(.-)%s*$") end
function M:References(body,id)
    local view=S.Spell(id,"")
    local name=view.reason=="PUBLIC" and view.name
    for line in body:gmatch("[^\r\n]+") do
        local command,args=line:match("^%s*/(%a+)%s*(.*)$")
        command=command and command:lower()
        if command=="startattack" and id==6603 then return true end
        if command=="cast" or command=="use" or command=="castsequence" or command=="castrandom" then
            args=args:gsub("%b[]",""):gsub("reset=[^%s]+%s*","")
            for raw in args:gmatch("[^;,]+") do
                local token=trim(raw)
                local useItem=command=="use" and (token:match("^%d+$") or token:match("^item:"))
                if not useItem and (token==tostring(id) or token=="spell:"..id or (name and token==name)) then return true end
                -- 等级后缀只作正文引用核对；精确等级由 GetMacroSpell 的公开ID确认。
                local base=token:match("^(.-)%s*%([^()]+%)$")
                if name and base and trim(base)==name then return true end
            end
        end
    end
    return false
end
function M:ReadMacro(index,layout)
    index=S.ID(index); layout=layout or self:Layout()
    if not self:Index(index,layout) then return nil,"MACRO_INDEX_UNVERIFIED" end
    local info,spell=S.Resolve("GetMacroInfo"),S.Resolve("GetMacroSpell")
    if not info or not spell then return nil,"MACRO_API_MISSING" end
    local ok,rawName,_,rawBody=pcall(info,index)
    local name=ok and S.Public(rawName,"string"); local body=ok and S.Public(rawBody,"string")
    if not name or #name==0 or #name>128 or not body or #body==0 or #body>4096 then return nil,"MACRO_BODY_UNVERIFIED" end
    local got,first,__,third=pcall(spell,index)
    local firstID=got and S.ID(first); local thirdID=got and S.ID(third)
    if firstID and thirdID and firstID~=thirdID then return nil,"MACRO_SPELL_CONFLICT" end
    local id=firstID or thirdID
    if not id or not self:References(body,id) then return nil,"MACRO_SPELL_UNVERIFIED" end
    return {kind="macro",macroID=index,macroName=name,body=body,spellID=id},"MACRO_VERIFIED"
end
function M:Clear() self.catalog=nil end
function M:Catalog(layout)
    local cached=self.catalog
    if cached and cached.account==layout.account and cached.character==layout.character and cached.limit==layout.limit then return cached.rows end
    local rows={}
    for i=1,layout.account do local row=self:ReadMacro(i,layout); if row then rows[#rows+1]={macroID=i,macroName=row.macroName,spellID=row.spellID} end end
    for i=layout.limit+1,layout.limit+layout.character do local row=self:ReadMacro(i,layout); if row then rows[#rows+1]={macroID=i,macroName=row.macroName,spellID=row.spellID} end end
    self.catalog={account=layout.account,character=layout.character,limit=layout.limit,rows=rows}
    return rows
end
function M:ActionMacro(slot,actionID)
    local layout=self:Layout()
    if not layout then return nil,"MACRO_LAYOUT_UNVERIFIED" end
    local labelOK,labelRaw=S.Call("GetActionText",slot)
    local label=labelOK and S.Public(labelRaw,"string")
    if self:Index(actionID,layout) then
        local row=self:ReadMacro(actionID,layout)
        if row and (not S.Resolve("GetActionText") or (label and label==row.macroName)) then return row,"MACRO_VERIFIED" end
    end
    -- 某些客户端返回宏代表的技能ID；用当前可见标签恢复唯一宏身份。
    if not label or #label==0 or #label>128 then return nil,"MACRO_LABEL_UNVERIFIED" end
    local view=S.Spell(actionID,""); local displayName=view.reason=="PUBLIC" and view.name
    local rows=self:Catalog(layout); local named=false
    for _,row in ipairs(rows) do if row.macroName==label then named=true; break end end
    local selected
    for _,candidate in ipairs(rows) do
        if candidate.spellID==actionID and ((named and candidate.macroName==label) or (not named and label==displayName)) then
            local row=self:ReadMacro(candidate.macroID,layout)
            if row and row.spellID==actionID and row.macroName==candidate.macroName then
                if selected then return nil,"MACRO_IDENTITY_AMBIGUOUS" end
                selected=row
            end
        end
    end
    return selected,selected and "MACRO_VERIFIED" or "MACRO_IDENTITY_UNVERIFIED"
end
function M:Action(slot)
    slot=S.ID(slot)
    local fn=S.Resolve("C_ActionBar.GetActionInfo") or S.Resolve("GetActionInfo")
    if not slot or slot>180 or not fn then return nil,"ACTION_UNVERIFIED" end
    local ok,rawKind,rawID=pcall(fn,slot)
    local kind=ok and S.Public(rawKind,"string"); local id=ok and S.ID(rawID)
    if not id then return nil,"ACTION_ID_UNVERIFIED" end
    if kind=="spell" then return {kind="spell",spellID=id},"SPELL_VERIFIED" end
    if kind=="macro" then return self:ActionMacro(slot,id) end
    return nil,"ACTION_KIND_UNVERIFIED"
end
function M:Cursor()
    local fn=S.Resolve("GetCursorInfo")
    if not fn then return nil,"CURSOR_API_MISSING" end
    local ok,rawKind,rawSlot,_,rawID=pcall(fn)
    local kind,reason=S.Public(rawKind,"string")
    if ok and reason=="NO_DATA" then return nil,"NO_DATA" end
    if not ok then return nil,"CURSOR_CALL_FAILED" end
    if kind=="spell" then return S.ID(rawID) end
    if kind=="macro" then
        local row,why=self:ReadMacro(rawSlot)
        return row and row.spellID,why
    end
    if kind=="action" then
        local row,why=self:Action(rawSlot)
        return row and row.spellID,why
    end
    return nil,"CURSOR_KIND_UNVERIFIED"
end
