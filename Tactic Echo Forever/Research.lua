local _, TEF = ...
local S, R = TEF.Safety, {revision=0,fields={},versions={}}
TEF.Research = R
local keys={"targetExists","targetAttackable","targetAlive","inRange","usable","insufficientPower",
    "moving","castPresent","channelPresent","visibleEnemies"}
local states={PUBLIC_TRUE=true,PUBLIC_FALSE=true,PUBLIC_VALUE=true,NO_DATA=true,SECRET=true,
    UNKNOWN=true,UNAVAILABLE=true,CALL_FAILED=true,FIELD_FAILED=true,UNKNOWN_UNIT=true,
    UNKNOWN_CAPACITY=true,UNKNOWN_IDENTITY=true,UNKNOWN_DETECTOR_MISSING=true,
    UNKNOWN_DETECTOR_FAILED=true,UNKNOWN_DETECTOR_RESULT=true,UNKNOWN_OPERATION_FAILED=true,
    UNKNOWN_TYPE=true,UNKNOWN_NUMBER=true}
function R.CleanSummary(raw)
    if not S.Public(raw,"table") then return nil end
    local clean={}
    for _,key in ipairs(keys) do
        local value=S.Field(raw,key,"string")
        if value and states[value] then clean[key]=value end
    end
    -- 只保留旧记录的字段，不再把未实现的探测显示为当前状态。
    for _,key in ipairs({"ready","gcdClear"}) do
        local value=S.Field(raw,key,"string"); if value and states[value] then clean[key]=value end
    end
    local count=S.Field(raw,"visibleCount","number")
    if count and count>=0 and count<=40 and count%1==0 then clean.visibleCount=count end
    local proposal=S.Field(raw,"proposal","string")
    if proposal=="single" or proposal=="multi" then clean.proposal=proposal end
    return clean
end

function R:Invalidate()
    self.revision=self.revision+1
    self.fields={}; self.auto={}; self.proposal=nil; self.dynamic=nil; self.sampledAt=nil
    for _,key in ipairs(keys) do self.versions[key]=(self.versions[key] or 0)+1 end
end
function R:Ticket(e)
    local versions={}
    for _,key in ipairs(keys) do versions[key]=self.versions[key] end
    return {generation=e.generation,revision=self.revision,versions=versions}
end
function R:Put(e,ticket,key,field)
    if ticket.generation~=e.generation or ticket.revision~=self.revision
        or ticket.versions[key]~=self.versions[key] then return false end
    self.fields[key]=field
    return true
end
function R:Current(e,ticket)
    if ticket.generation~=e.generation or ticket.revision~=self.revision then return false end
    for _,key in ipairs(keys) do if ticket.versions[key]~=self.versions[key] then return false end end
    return true
end
function R:Immediate(e,key,field)
    self.versions[key]=(self.versions[key] or 0)+1
    self.fields[key]=field
end
function R.Boolean(raw, reason)
    local value, classification=S.Public(raw,"boolean")
    if value==nil then return {state=classification or reason or "UNKNOWN"} end
    return {state=value and "PUBLIC_TRUE" or "PUBLIC_FALSE",value=value}
end
local function boolean(path,...)
    local ok,raw,reason=S.Call(path,...)
    if not ok then return {state=reason} end
    return R.Boolean(raw)
end
local function presence(path)
    local ok,raw,reason=S.Call(path,"player")
    if not ok then return {state=reason} end
    -- The first return is a name; only derive existence after official
    -- detection. Never save or inspect restricted name content.
    local value, classification=S.Public(raw,"string")
    if classification=="NO_DATA" then return {state="PUBLIC_FALSE",value=false} end
    if value then return {state="PUBLIC_TRUE",value=true} end
    return {state=classification}
end
-- 兼容原生unitToken/GetUnit及旧结构；身份冲突不选任意来源。
function R:NamePlateToken(raw)
    local plate,why=S.Public(raw,"table"); if not plate then return nil,why end
    local token,source; local fields={}; local failed
    local function accept(value,reason,name)
        fields[name]=reason
        if reason=="NO_DATA" then return end
        if reason~="PUBLIC" then failed=failed or reason; return end
        if #value>32 or (value~="player" and not value:match("^nameplate%d+$")) then failed="TOKEN_FORMAT_INVALID"; return end
        if token and token~=value then failed="TOKEN_SOURCE_CONFLICT"; return end
        token,source=value,source or name
    end
    local value,reason=S.Field(plate,"namePlateUnitToken","string"); accept(value,reason,"legacy")
    value,reason=S.Field(plate,"unitToken","string"); accept(value,reason,"native")
    local frame,status=S.Field(plate,"UnitFrame","table")
    if frame then value,reason=S.Field(frame,"unit","string"); accept(value,reason,"unitFrame")
    elseif status~="NO_DATA" then failed=failed or status end
    local getter,getReason=S.Field(plate,"GetUnit","function")
    if getter then
        local ok,rawValue=pcall(getter,plate)
        if ok then value,reason=S.Public(rawValue,"string"); accept(value,reason,"method")
        else failed="TOKEN_GETTER_FAILED" end
    elseif getReason~="NO_DATA" then failed=failed or getReason end
    if failed then return nil,failed,source,fields end
    if not token then return nil,"TOKEN_MISSING",nil,fields end
    if token~="player" and S.Resolve("C_NamePlate.GetNamePlateForUnit") then
        local ok,mapped=S.Call("C_NamePlate.GetNamePlateForUnit",token)
        local matched=ok and S.Public(mapped,"table")
        if not matched then return nil,"TOKEN_MAPPING_UNKNOWN",source,fields end
        if matched~=plate then return nil,"TOKEN_MAPPING_CONFLICT",source,fields end
    end
    return token,"PUBLIC",source,fields
end
function R:ProbeVisibleYards(radius)
    radius=S.Public(radius,"number")
    if not radius or radius<=0 or radius>40 then return {state="RADIUS_INVALID"} end
    local out={state="PUBLIC_BOUNDS",radius=radius,lower=0,upper=0,unknown=0,details={}}
    local ok,raw,reason=S.Call("C_NamePlate.GetNamePlates")
    local list,classification
    if ok then list,classification=S.Public(raw,"table") end
    if not list then out.state=classification or reason or "NAMEPLATES_UNKNOWN"; return out end
    local measured,size=pcall(function() return #list end)
    if not measured or size>40 then out.state="UNKNOWN_CAPACITY"; return out end
    local seen={}; TEF.APL.PublicConditions:PrepareRangeProbes()
    for i=1,size do
        local plate,plateReason=S.Field(list,i,"table")
        local token,identity,source,fields=self:NamePlateToken(plate)
        if not plate then identity=plateReason end
        local detail={index=i,unit=token,identityReason=identity,source=source,fields=fields}
        local uncertain=false
        if not token then uncertain=true
        elseif seen[token] then uncertain=true; detail.identityReason="TOKEN_DUPLICATE"
        else
            seen[token]=true
            if token~="player" then
                local method=S.Field(plate,"IsVisible","function")
                local visible
                if method then local got,value=pcall(method,plate); if got then visible,detail.visibleReason=S.Public(value,"boolean") else detail.visibleReason="CALL_FAILED" end
                else detail.visibleReason="VISIBILITY_UNAVAILABLE" end
                if visible==nil then uncertain=true
                elseif visible then
                    local exists=boolean("UnitExists",token)
                    if exists.value==nil then uncertain=true; detail.rangeReason="UNIT_EXISTS_UNKNOWN"
                    elseif exists.value then
                        local enemy,dead=boolean("UnitCanAttack","player",token),boolean("UnitIsDeadOrGhost",token)
                        if enemy.value==nil or dead.value==nil then uncertain=true; detail.rangeReason="UNIT_REACTION_OR_ALIVE_UNKNOWN"
                        elseif enemy.value and not dead.value then
                            local low,high,why=TEF.APL.PublicConditions:DistanceBracket(token,radius)
                            detail.low,detail.high,detail.rangeReason=low,high,why
                            if high and high<=radius then detail.inside=true; out.lower=out.lower+1; out.upper=out.upper+1
                            elseif low and low>=radius and low>0 then detail.inside=false
                            else uncertain=true end
                        end
                    end
                end
            end
        end
        if uncertain then out.unknown=out.unknown+1; out.upper=out.upper+1 end
        out.details[#out.details+1]=detail
    end
    return out
end
function R.CountBoundsMatch(lower,upper,min,max)
    local low=S.Public(lower,"number"); local high=S.Public(upper,"number")
    local minimum,minReason=S.Public(min,"number"); local maximum,maxReason=S.Public(max,"number")
    if not low or not high or low<0 or high>40 or low>high then return nil end
    if (minReason~="NO_DATA" and not minimum) or (maxReason~="NO_DATA" and not maximum) then return nil end
    lower,upper,min,max=low,high,minimum,maximum
    if (min and upper<min) or (max and lower>max) then return false end
    if (not min or lower>=min) and (not max or upper<=max) then return true end
    return nil
end
function R:CountVisible(spellID)
    if spellID then
        if spellID==61304 or boolean("C_SpellBook.IsSpellKnown",spellID).value~=true then return {state="UNKNOWN_RANGE_SPELL"} end
        local got,info=S.Call("C_Spell.GetSpellInfo",spellID)
        local max=got and S.Field(info,"maxRange","number")
        if max==0 then return {state="UNKNOWN_RANGE_SPELL",detailReason="SPELL_UNIT_RANGE_UNSUPPORTED"} end
    end
    local ok,raw,reason=S.Call("C_NamePlate.GetNamePlates")
    if not ok then return {state=reason} end
    local list,classification=S.Public(raw,"table")
    if not list then return {state=classification} end
    local measured,size=pcall(function() return #list end)
    if not measured or size>40 then return {state="UNKNOWN_CAPACITY"} end
    local count,seen=0,{}
    for i=1,size do
        local read,plate=pcall(function() return list[i] end)
        if not read then return {state="FIELD_FAILED"} end
        local token,why,source,fields=self:NamePlateToken(plate)
        if not token or seen[token] then return {state="UNKNOWN_IDENTITY",detailReason=seen[token] and "TOKEN_DUPLICATE" or why,source=source,fields=fields,index=i} end
        seen[token]=true
        local exists=boolean("UnitExists",token)
        if exists.value==nil then return {state="UNKNOWN_UNIT"} end
        if exists.value and token~="player" then
            local enemy,dead=boolean("UnitCanAttack","player",token),boolean("UnitIsDeadOrGhost",token)
            if enemy.value==nil or dead.value==nil then return {state="UNKNOWN_UNIT"} end
            if enemy.value and not dead.value then
                if spellID then
                    local range=boolean("C_Spell.IsSpellInRange",spellID,token)
                    if range.value==nil then return {state="UNKNOWN_RANGE"} end
                    if range.value then count=count+1 end
                else count=count+1 end
            end
        end
    end
    return {state="PUBLIC_VALUE",value=count}
end

-- Pure future scene policy: two distinct samples, hysteresis. It only
-- produces a proposal; runtime never consumes it as a scene change.
function R.Auto(policy,field,sample,current)
    if field.state~="PUBLIC_VALUE" then policy.last=nil; policy.pending=nil; policy.hits=0; return nil,"AUTO_UNKNOWN" end
    if policy.last==sample then return nil,"AUTO_SAME_SAMPLE" end
    policy.last=sample
    local desired=field.value>=3 and "multi" or (field.value<=1 and "single" or current)
    if desired==current then policy.pending=nil; policy.hits=0; return nil,"AUTO_HOLD" end
    if policy.pending~=desired then policy.pending=desired; policy.hits=1
    else policy.hits=policy.hits+1 end
    if policy.hits>=2 then return desired,"AUTO_PROPOSAL" end
    return nil,"AUTO_CONFIRMING"
end
function R:Sample(e)
    if not e.steps or not e.steps[e.index] then return false,"RESEARCH_UNCONFIGURED" end
    if not e.running then self:Invalidate(); return false,"RESEARCH_PAUSED" end
    self.sampleSerial=(self.sampleSerial or 0)+1
    local ticket=self:Ticket(e)
    local step=e.steps[e.index]
    local id=step.spellID
    local alive=boolean("UnitIsDeadOrGhost","target")
    if alive.value~=nil then alive=R.Boolean(not alive.value) end
    local evidence={targetExists=boolean("UnitExists","target"),targetAttackable=boolean("UnitCanAttack","player","target"),
        targetAlive=alive,inRange=id>0 and boolean("C_Spell.IsSpellInRange",id,"target") or {state="UNAVAILABLE"},
        moving=boolean("IsPlayerMoving"),
        castPresent=presence("UnitCastingInfo"),channelPresent=presence("UnitChannelInfo"),
        visibleEnemies=self:CountVisible()}
    local fn=S.Resolve("C_Spell.IsSpellUsable")
    if fn and id>0 then
        local ok,usable,power=pcall(fn,id)
        if ok then evidence.usable=R.Boolean(usable); evidence.insufficientPower=R.Boolean(power)
        else evidence.usable={state="CALL_FAILED"}; evidence.insufficientPower={state="CALL_FAILED"} end
    else evidence.usable={state="UNAVAILABLE"}; evidence.insufficientPower={state="UNAVAILABLE"} end
    local ok,raw=S.Call("GetTime")
    local sampledAt=ok and S.Public(raw,"number") or nil
    if not self:Current(e,ticket) then return false,"RESEARCH_STALE" end
    for _,key in ipairs(keys) do
        if not self:Put(e,ticket,key,evidence[key]) then return false,"RESEARCH_STALE" end
    end
    if not sampledAt or not self.sampledAt or sampledAt-self.sampledAt>1 or sampledAt<self.sampledAt then self.auto={} end
    self.sampledAt=sampledAt
    self.auto=self.auto or {}
    self.proposal,self.autoReason=nil,"AUTO_UNKNOWN"
    if sampledAt then self.proposal,self.autoReason=R.Auto(self.auto,self.fields.visibleEnemies,self.sampleSerial,e.scene) end
    e:Log("observed","RESEARCH_SAMPLED")
    local summary={proposal=self.proposal}
    for _,key in ipairs(keys) do summary[key]=self.fields[key].state end
    summary.visibleCount=self.fields.visibleEnemies.value
    e.db.diagnostics[#e.db.diagnostics].research=R.CleanSummary(summary)
    return true
end
function R:View()
    local ok,raw=S.Call("GetTime")
    local now=ok and S.Public(raw,"number") or nil
    if not now or not self.sampledAt or now-self.sampledAt>1 or now<self.sampledAt then return "状态未采样或已过期；请重新执行只读采样" end
    local lines={"最近手动采样时刻 " .. self.sampledAt .. "（非实时状态）"}
    for _,key in ipairs(keys) do
        local field=self.fields[key]
        lines[#lines+1]=key .. "=" .. (field and field.state or "UNKNOWN")
            .. (field and field.state=="PUBLIC_VALUE" and (":" .. field.value) or "")
    end
    lines[#lines+1]="场景建议：" .. (self.proposal or "无") .. "（只观察，不自动切换）"
    lines[#lines+1]="场景采样仅供诊断；推荐由当前列表或APL负责。"
    return table.concat(lines,"\n")
end
R:Invalidate()
