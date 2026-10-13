local _,TEF=...
local P,S={},TEF.Safety
TEF.Presentation=P
-- Display-only. No state is read by Engine, Research or Dispatch.
P.cooldowns={}
P.bindings={}
-- 独立固定物品探针，仅估测距离区间；不参与APL或派发资格。
local probes={{5,8149,136605,63427},{8,34368,33278},{10,32321,17626,10699},
    {15,33069,31129},{20,10645,21519},{25,13289,24268,41509,31463},
    {30,17202,835,7734,34191},{35,18904,24269},{40,4945,8348,28767,18640,18662}}
local function boolean(path,...)
    local ok,raw=S.Call(path,...)
    if ok then return S.Public(raw,"boolean") end
end
function P:PrepareRangeProbes()
    if self.rangePrepared then return end
    self.rangePrepared=true
    for _,rung in ipairs(probes) do
        for i=2,#rung do S.Call("C_Item.RequestLoadItemDataByID",rung[i]) end
    end
end
function P:MeasureDistance()
    if boolean("UnitExists","target")~=true then return nil,nil,"TARGET_MISSING_OR_UNKNOWN" end
    if boolean("UnitIsUnit","target","player")~=false or boolean("UnitIsDeadOrGhost","target")~=false then
        return nil,nil,"TARGET_INVALID_OR_UNKNOWN"
    end
    local attack=boolean("UnitCanAttack","player","target")
    if attack==nil then return nil,nil,"TARGET_REACTION_UNKNOWN" end
    if not attack then
        if boolean("InCombatLockdown")~=false then return nil,nil,"FRIENDLY_COMBAT_OR_UNKNOWN" end
        if S.Resolve("C_ChallengeMode.IsChallengeModeActive") and boolean("C_ChallengeMode.IsChallengeModeActive")~=false then
            return nil,nil,"FRIENDLY_CHALLENGE_OR_UNKNOWN"
        end
    end
    local path=S.Resolve("C_Item.IsItemInRange") and "C_Item.IsItemInRange" or "IsItemInRange"
    if not S.Resolve(path) then return nil,nil,"ITEM_RANGE_UNAVAILABLE" end
    local low,known=0,false
    for _,rung in ipairs(probes) do
        local inside,sawFalse=false,false
        for i=2,#rung do
            local ok,raw=S.Call(path,rung[i],"target")
            if ok then
                local v=S.Public(raw,"boolean")
                if v==nil then
                    local n=S.Public(raw,"number")
                    if n==1 then v=true elseif n==0 then v=false end
                end
                if v==true then inside=true; break end
                if v==false then sawFalse=true end
            end
        end
        if inside then return low,rung[1],"ITEM_BRACKET_ESTIMATE" end
        if sawFalse then low,known=rung[1],true end
    end
    if known then return low,nil,"ITEM_LOWER_BOUND_ESTIMATE" end
    return nil,nil,"ITEM_RANGE_UNKNOWN"
end
function P:PaintRange(card,step)
    local out=false
    if step and step.spellID~=6603 and not step.unverified and boolean("UnitExists","target")==true
        and boolean("UnitIsDeadOrGhost","target")==false then
        local ok,raw=S.Call("C_Spell.IsSpellInRange",step.spellID,"target")
        if ok then out=S.Public(raw,"boolean")==false end
    end
    TEF.UI:Paint(card.icon,"SetVertexColor",1,out and .25 or 1,out and .25 or 1,1)
    local hud=TEF.HUD
    local styles=hud and hud.engine and hud.engine.db.hud.styles
    local color=styles and styles[card==hud.cards[1] and "main" or "preview"].key.color
    TEF.UI:Paint(card.key,"SetTextColor",out and 1 or color and color.r or 1,
        out and .2 or color and color.g or 1,out and .2 or color and color.b or 1,color and color.a or 1)
end
function P:UpdateRange(hud)
    self:PrepareRangeProbes()
    for _,card in ipairs(hud.cards or {}) do self:PaintRange(card,card.displayStep) end
    local low,high,reason=self:MeasureDistance()
    local text=low and (high and string.format("估测距离：%d–%d码",low,high) or string.format("估测距离：%d码以上",low)) or "估测距离：未知"
    TEF.UI:Paint(hud.rangeText,"SetText",text)
    local ok,raw=S.Call("UnitGUID","target"); local guid=ok and S.Public(raw,"string")
    if guid and #guid>128 then guid=nil end
    local signature=(guid or "UNKNOWN")..":"..reason..":"..tostring(low)..":"..tostring(high)
    if signature==self.rangeSignature then return end
    self.rangeSignature=signature
    local rows=hud.engine.db.rangeDiagnostics or {}; hud.engine.db.rangeDiagnostics=rows
    if #rows>=32 then table.remove(rows,1); hud.engine.db.rangeEvicted=(hud.engine.db.rangeEvicted or 0)+1 end
    local clockOK,clock=S.Call("GetTime")
    rows[#rows+1]={session=hud.engine.session,reason=reason,low=low,high=high,targetGUID=guid,
        time=clockOK and S.Public(clock,"number"),version=TEF.Version}
end
local function number(record,key) return S.Field(record,key,"number") end
function P:Read(id,cooldownEvent)
    local result={cd="CD 未知",charges="充能 未知"}
    local ok,info=S.Call("C_Spell.GetSpellCooldown",id)
    if ok then
        local start,duration=number(info,"startTime"),number(info,"duration")
        local enabled=S.Field(info,"isEnabled","boolean")
        local rate=number(info,"modRate")
        if start and duration and start>=0 and duration>=0 and enabled==true and rate and rate>0 then
            if duration==0 then self.cooldowns[id]=nil; result.cd="CD 0"
            elseif cooldownEvent then
                local gcd=S.Field(info,"isOnGCD","boolean")
                if gcd==false then self.cooldowns[id]={start=start,duration=duration,rate=rate}
                elseif gcd==true then self.cooldowns[id]=nil; result.cd="GCD"
                else self.cooldowns[id]=nil end
            end
        elseif cooldownEvent then self.cooldowns[id]=nil end
    elseif cooldownEvent then self.cooldowns[id]=nil end
    local cached=self.cooldowns[id]
    if cached then
        local start,duration=number(info,"startTime"),number(info,"duration")
        local rate=number(info,"modRate")
        if start~=cached.start or duration~=cached.duration or rate~=cached.rate then cached=nil end
    end
    if cached then
        local got,raw=S.Call("GetTime"); local now=got and S.Public(raw,"number")
        if now then result.cd="CD " .. math.ceil(math.max(0,cached.start+cached.duration/cached.rate-now)) .. "s" end
    end
    local got,charge=S.Call("C_Spell.GetSpellCharges",id)
    if got then
        local _,reason=S.Public(charge,"table")
        if reason=="NO_DATA" then result.charges="充能 —"
        else
            local current,max=number(charge,"currentCharges"),number(charge,"maxCharges")
            if current and max and current>=0 and max>0 and current<=max and current%1==0 and max%1==0 then
                result.charges="充能 " .. current .. "/" .. max; result.recharging=current<max
            end
        end
    end
    return result
end
function P:Paint(card,step,cooldownEvent)
    local U=TEF.UI
    self:PaintRange(card,step)
    card.visualID=step and not step.unverified and step.spellID or nil
    U:Call(card.cooldown,"Clear")
    if not step or step.unverified then
        U:Paint(card.key,"SetText","—"); U:Paint(card.meta,"SetText","")
        U:Paint(card.cooldownText,"SetText",""); U:Paint(card.chargeText,"SetText",""); return
    end
    local binding=self.bindings[step.spellID]
    if binding==nil then binding=TEF.Dispatch:Resolve(step.spellID); self.bindings[step.spellID]=binding or false end
    U:Paint(card.key,"SetText",binding and binding.key or "未解析")
    local view=self:Read(step.spellID,cooldownEvent)
    U:Paint(card.meta,"SetText","")
    U:Paint(card.cooldownText,"SetText",view.cd:match("^CD (%d+)s$") or "")
    U:Paint(card.chargeText,"SetText",view.charges:match("(%d+/%d+)") or "")
    -- A client duration object is passed directly to ONE renderer, never
    -- inspected, compared, persisted or used for input eligibility.
    local path=view.recharging and "C_Spell.GetSpellChargeDuration" or "C_Spell.GetSpellCooldownDuration"
    local ok,duration
    if view.recharging then ok,duration=S.Call(path,step.spellID)
    else ok,duration=S.Call(path,step.spellID,true) end
    if ok then U:Call(card.cooldown,"SetCooldownFromDurationObject",duration) end
end
function P:Tick(card)
    local cached=card.visualID and self.cooldowns[card.visualID]
    if not cached then return end
    local ok,raw=S.Call("GetTime"); local now=ok and S.Public(raw,"number")
    if not now then TEF.UI:Paint(card.cooldownText,"SetText",""); return end
    local remain=math.ceil(math.max(0,cached.start+cached.duration/cached.rate-now))
    TEF.UI:Paint(card.cooldownText,"SetText",remain>0 and tostring(remain) or "")
end
