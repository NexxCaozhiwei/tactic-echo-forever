local _,TEF=...
local E,S=TEF.Engine,TEF.Safety

function E:ClearUsage()
    self.usage=nil; self.usageProgress=nil; self.usageTarget=nil
end
function E:UsageTargetChanged()
    self.usageTargetSerial=(self.usageTargetSerial or 0)+1
    self.usageTarget=nil
end
function E:UsageTargetIdentity()
    local generation,selection=self.generation,self.usageTargetSerial or 0
    local existsOK,rawExists=S.Call("UnitExists","target")
    local exists=existsOK and S.Public(rawExists,"boolean")
    if exists~=true then return nil end
    local ok,raw=S.Call("UnitGUID","target")
    local guid=ok and S.Identity(raw)
    if generation~=self.generation or selection~=(self.usageTargetSerial or 0) then return nil end
    local cached=self.usageTarget
    -- 公开目标切换事件界定选择周期；不比较或保存受限GUID。
    if cached and cached.selection==selection and (cached.kind=="selection" or not guid) then return cached.key end
    local key=guid and ("GUID:" .. guid) or ("SELECTION:" .. selection)
    self.usageTarget={selection=selection,key=key,kind=guid and "guid" or "selection"}
    return key
end
function E:HasUsagePolicy()
    if TEF.Recommendation and TEF.Recommendation:Source(self)~="manual" then return false end
    for _,step in ipairs(self.steps or {}) do
        if step.usagePolicy and step.usagePolicy~="always" then return true end
    end
    return false
end
function E:ObserveUsageCombat()
    if not self:HasUsagePolicy() then return true end
    local generation=self.generation
    local ok,raw=S.Call("InCombatLockdown")
    local combat=ok and S.Public(raw,"boolean")
    if self.generation~=generation or combat==nil then return nil end
    self.usage=self.usage or {targets={},targetCount=0,combatUsed={},epoch=1}
    local u=self.usage
    if u.lastCombat==true and combat==false then
        u.epoch=u.epoch+1; u.combatUsed={}
    end
    u.lastCombat=combat
    return true
end
function E:UsageEligibility(index)
    local step=self.steps and self.steps[index or self.index]
    if not step or not step.usagePolicy or step.usagePolicy=="always"
        or (TEF.Recommendation and TEF.Recommendation:Source(self)~="manual") then return true,nil end
    local generation,current,serial=self.generation,self.index,self.receiptSerial or 0
    if not self:ObserveUsageCombat() then return nil,"SEQUENCE_USAGE_CONTEXT_UNKNOWN" end
    local u=self.usage
    local context={policy=step.usagePolicy,epoch=u.epoch,index=index or self.index}
    if step.usagePolicy=="target" then
        context.target=self:UsageTargetIdentity()
        if not context.target then return nil,"SEQUENCE_USAGE_CONTEXT_UNKNOWN" end
    end
    if generation~=self.generation or current~=self.index or serial~=(self.receiptSerial or 0) or self.usage~=u then
        return nil,"SEQUENCE_USAGE_CONTEXT_UNKNOWN"
    end
    local used=step.usagePolicy=="combat" and u.combatUsed or u.targets[context.target]
    if used and used[context.index] then return false,"SEQUENCE_USAGE_ALREADY_DONE",context end
    if step.usagePolicy=="target" and not used and u.targetCount>=256 then return nil,"SEQUENCE_USAGE_CAPACITY" end
    return true,nil,context
end
function E:SameUsageContext(a,b)
    if not a and not b then return true end
    return a and b and a.policy==b.policy and a.index==b.index
        and (a.policy=="target" and a.target==b.target or a.policy=="combat" and a.epoch==b.epoch) or false
end
function E:MarkUsage(context)
    if not context then return end
    local u=self.usage
    if not u then return end
    local used
    if context.policy=="combat" then
        if context.epoch~=u.epoch then return end
        used=u.combatUsed
    else
        used=u.targets[context.target]
        if not used then
            if u.targetCount>=256 then return end
            used={}; u.targets[context.target]=used; u.targetCount=u.targetCount+1
        end
    end
    used[context.index]=true; self.usageProgress=nil
end
function E:PrepareUsage()
    if not self:HasUsagePolicy() then return true end
    local generation,index,serial=self.generation,self.index,self.receiptSerial or 0
    local allowed,reason,context=self:UsageEligibility()
    if generation~=self.generation or index~=self.index or serial~=(self.receiptSerial or 0) then return nil,"SEQUENCE_USAGE_CONTEXT_UNKNOWN" end
    if allowed==nil then return nil,reason end
    local scopeChanged=self.usageProgress and not self:SameUsageContext(self.usageProgress,context)
    for _,a in pairs(self.associations) do
        if a.generation==generation and a.index==index and a.receiptSerial==serial
            and self.steps[index].matches[a.spellID] and a.usageContext and not self:SameUsageContext(a.usageContext,context) then
            scopeChanged=true
        end
    end
    if scopeChanged then
        self:Invalidate("SEQUENCE_USAGE_SCOPE_CHANGED")
        if self.generation~=generation+1 or self.index~=index or serial~=(self.receiptSerial or 0) then return nil,"SEQUENCE_USAGE_CONTEXT_UNKNOWN" end
        self.stepCasts=0; self.usageProgress=nil
        return nil,"SEQUENCE_USAGE_SCOPE_CHANGED"
    end
    if allowed then return true end
    if self:RecommendationLocked() then return nil,"SEQUENCE_USAGE_WAIT_RECEIPT" end
    local following=index
    for _=1,#self.steps do
        following=following+1
        if following>#self.steps then
            if not self.db.loop then following=nil; break end
            following=1
        end
        local eligible,blocked=self:UsageEligibility(following)
        if generation~=self.generation or index~=self.index or serial~=(self.receiptSerial or 0) then return nil,"SEQUENCE_USAGE_CONTEXT_UNKNOWN" end
        if eligible==nil then return nil,blocked end
        if eligible then break end
        if following==index then return nil,"SEQUENCE_USAGE_EXHAUSTED" end
    end
    self:Invalidate("SEQUENCE_USAGE_SKIPPED")
    if self.generation~=generation+1 or self.index~=index or serial~=(self.receiptSerial or 0) or self.identitySaturated then return nil,"SEQUENCE_USAGE_CONTEXT_UNKNOWN" end
    self.stepCasts=0; self.usageProgress=nil
    if following then self.index=following
    else self.completed=true; self.running=false end
    return nil,"SEQUENCE_USAGE_SKIPPED"
end
