local _,TEF=...
local R={}
TEF.Recommendation=R
function R:BaseSource(e,scene)
    scene=scene or e.scene
    local apl=e.db.aplByClass and e.db.aplByClass[e.classToken or ""]
    if apl and apl[scene]==true then return "apl" end
    return "manual"
end
function R:Source(e,scene)
    if e.maintenanceActive and (not scene or scene==e.scene) then return "apl" end
    if e.groupRun and not scene then return "manual" end
    return self:BaseSource(e,scene)
end
function R:Configured(e)
    if e.maintenanceActive then return TEF.Maintenance:Enabled(e) end
    local source=self:Source(e)
    if e.db.selectedPlans and e.db.selectedPlans[source]==e.scene and e.db.enabledPlans[source][e.scene]~=true then return false end
    if self:Source(e)=="apl" then return TEF.APL.Custom:ClassSupported(e.classToken) end
    return self:Current(e)~=nil
end
function R:Rows(e,scene)
    local source=self:Source(e,scene)
    if source=="apl" then return {},"apl" end
    return TEF.Profiles:Clean(e.db.profiles[scene]),"manual"
end
function R:Current(e)
    local step=e.steps and e.steps[e.index]
    if self:Source(e)=="apl" then
        local c=e.aplCandidate
        if not c or not step or step.spellID~=c.spellID then return nil,"APL_NO_CANDIDATE" end
        return {spellID=c.spellID,index=1,generation=e.generation,source="apl",rule=c.rule,
            profileKey=e.classToken,receiptSerial=e.receiptSerial or 0},"APL_CANDIDATE"
    end
    if not e.profileKey or not step or step.unverified then return nil,"RECOMMENDATION_UNCONFIGURED" end
    return {spellID=step.spellID,index=e.index,generation=e.generation,
        source="manual",profileKey=e.profileKey,receiptSerial=e.receiptSerial or 0},"RECOMMENDATION_FIXED"
end
function R:SetSource(e,source,scene)
    if TEF.Maintenance and e.maintenanceActive then TEF.Maintenance:Restore(e,"MAINTENANCE_SOURCE_CHANGED") end
    if not e.classToken then return false,"PROFILE_IDENTITY_UNKNOWN" end
    if source~="manual" and source~="apl" then return false,"RECOMMENDATION_SOURCE_INVALID" end
    scene=scene or e.scene
    if scene~="single" and scene~="multi" and scene~="third" then return false,"SCENE_INVALID" end
    if source=="apl" and not TEF.APL.Custom:ClassSupported(e.classToken) then return false,"APL_CLASS_UNSUPPORTED" end
    if source=="apl" then e.db.apl.template="custom" end
    if source~="apl" and not e.profileKey then return false,"PROFILE_IDENTITY_UNKNOWN" end
    e.db.aplByClass[e.classToken]=e.db.aplByClass[e.classToken] or {}
    e.db.aplByClass[e.classToken][scene]=source=="apl"
    if source~="apl" then
        e.db.sourceByProfile[e.profileKey]=e.db.sourceByProfile[e.profileKey] or {}
        e.db.sourceByProfile[e.profileKey][scene]=source
    end
    e.aplCandidate=nil; e.aplSnapshot=nil; e.aplPreviewSnapshot=nil; e.aplTrace=nil; TEF.APL:Invalidate(true)
    return TEF.Profiles:Select(e,scene)
end
-- 只读显示列表，不能成为运行意图、派发请求或回执身份。
function R:HUDSteps(e)
    local manual=self:Source(e)=="manual"
    if not manual and e.db.apl.template~="custom" then return nil end
    local ok,raw=TEF.Safety.Call("UnitExists","target")
    local target=ok and TEF.Safety.Public(raw,"boolean")
    if target==true then
        local hostile=TEF.APL.State.Boolean("UnitCanAttack","player","target")
        local dead=TEF.APL.State.Boolean("UnitIsDeadOrGhost","target")
        -- 死亡敌方目标仅切换只读图标预览，不授予派发资格。
        if hostile==true and dead==true then target=false end
    end
    local result,seen={},{}
    local function add(id,name)
        if id and not seen[id] then result[#result+1]={spellID=id,name=name or ("技能 " .. id)}; seen[id]=true end
    end
    local rows=manual and (e.steps or {}) or TEF.APL.Custom:Rows(e)
    local snapshot=e.aplPreviewSnapshot or e.aplSnapshot
    local now=TEF.APL.State.Time()
    local fresh=snapshot and snapshot.generation==e.generation and snapshot.receiptSerial==(e.receiptSerial or 0)
        and snapshot.revision==(TEF.APL.State.revision or 0) and now and snapshot.sampledAt and now>=snapshot.sampledAt and now-snapshot.sampledAt<=1
    local first=1
    if manual then
        local current=rows[e.index]
        if current then add(current.spellID,current.name) end
        local position=e.index or 1
        for offset=1,#rows-1 do
            local index=position+offset
            if index>#rows then if e.db.loop then index=(index-1)%#rows+1 else break end end
            local row=rows[index]
            if target==false then add(row.spellID,row.name)
            elseif target==true then
                local action=TEF.APL.Custom:Read(row.spellID,false,row.targetMode)
                local allowed=TEF.Dispatch:ManualPolicy(e,row)
                if allowed==true and action.known==true and action.usable==true and action.power_ok==true and action.in_range==true then add(row.spellID,row.name) end
            end
            if #result>=3 then break end
        end
        while #result>0 and #result<3 do result[#result+1]=result[#result] end
        return result
    end
    if not e.aplCandidate then target=false end
    if target==true then
        local current=e.aplCandidate
        if current then add(current.spellID,current.name); first=(current.customIndex or 0)+1 end
        if fresh then
            for i=first,#rows do
                local row=rows[i]; local action=snapshot.actions["custom_" .. i]
                if TEF.APL.Custom:Check(snapshot,row,i)==true and action then add(action.spellID,action.name) end
                if #result>=3 then break end
            end
        end
    elseif target==false then
        for _,row in ipairs(rows) do
            if row.enabled and not row.invalid then add(row.spellID) end
            if #result>=3 then break end
        end
    end
    -- 待命或没有可显示候选时，三格统一回退到配置顺序；只读预览不授权输入。
    if #result==0 then
        for _,row in ipairs(rows) do
            if row.enabled and not row.invalid then add(row.spellID) end
            if #result>=3 then break end
        end
    end
    while #result>0 and #result<3 do result[#result+1]=result[#result] end
    return result
end
