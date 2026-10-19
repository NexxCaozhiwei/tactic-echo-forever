local _,TEF=...
local P,S={},TEF.Safety
TEF.Presentation=P
-- Display-only. No state is read by Engine, Research or Dispatch.
P.bindings={}
local function boolean(path,...)
    local ok,raw=S.Call(path,...)
    if ok then return S.Public(raw,"boolean") end
end
-- 显示与APL共用公开距离探针；显示不改变运行意图。
function P:PrepareRangeProbes() TEF.APL.PublicConditions:PrepareRangeProbes() end
function P:MeasureDistance() return TEF.APL.PublicConditions:DistanceBracket() end
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
    local color=styles and card==hud.cards[1] and styles.main.key.color
    if card.key then TEF.UI:Paint(card.key,"SetTextColor",out and 1 or color and color.r or 1,
        out and .2 or color and color.g or 1,out and .2 or color and color.b or 1,color and color.a or 1) end
end
function P:UpdateRange(hud)
    self:PrepareRangeProbes()
    for _,card in ipairs(hud.cards or {}) do self:PaintRange(card,card.displayStep) end
    local low,high,reason=self:MeasureDistance()
    local text=low and (high and string.format("估测距离：%d–%d码",low,high) or string.format("估测距离：%d码以上",low)) or "估测距离：未知"
    hud.rangeDescription=text
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
function P:Read(id)
    local ok,charge=S.Call("C_Spell.GetSpellCharges",id)
    if not ok then return {} end
    local current,max=number(charge,"currentCharges"),number(charge,"maxCharges")
    if current and max and current>=0 and max>0 and current<=max and current%1==0 and max%1==0 then
        return {recharging=current<max}
    end
    return {}
end
function P:Paint(card,step)
    local U=TEF.UI
    self:PaintRange(card,step)
    U:Call(card.cooldown,"Clear")
    if not step or step.unverified then
        if card.key then U:Paint(card.key,"SetText","—") end
        return
    end
    if card.key then
        local binding=self.bindings[step.spellID]
        if binding==nil then binding=TEF.Dispatch:Resolve(step.spellID); self.bindings[step.spellID]=binding or false end
        U:Paint(card.key,"SetText",binding and binding.key or "未解析")
    end
    local view=self:Read(step.spellID)
    -- A client duration object is passed directly to ONE renderer, never
    -- inspected, compared, persisted or used for input eligibility.
    local path=view.recharging and "C_Spell.GetSpellChargeDuration" or "C_Spell.GetSpellCooldownDuration"
    local ok,duration
    if view.recharging then ok,duration=S.Call(path,step.spellID)
    else ok,duration=S.Call(path,step.spellID,true) end
    if ok then U:Call(card.cooldown,"SetCooldownFromDurationObject",duration) end
end
