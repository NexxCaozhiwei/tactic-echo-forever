local _, TEF = ...
local S, P = TEF.Safety, {}
TEF.Profiles = P
local classes={WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,DEATHKNIGHT=true,
    SHAMAN=true,MAGE=true,WARLOCK=true,MONK=true,DRUID=true,DEMONHUNTER=true,EVOKER=true}
function P:Identity()
    local fn=S.Resolve("UnitClass")
    if not fn then return nil,nil end
    local ok,_,raw=pcall(fn,"player")
    local class=ok and S.Public(raw,"string")
    if not class or not classes[class] then return nil,nil end
    return class .. ":base",class
end
local function validKey(key)
    if #key>40 then return false end
    local class,spec=key:match("^(%u+):(%w+)$")
    return classes[class] and (spec=="base" or (spec:match("^%d+$") and S.ID(tonumber(spec))~=nil))
end

-- Detached, bounded configuration. Never import another AddOn's database.
function P:Clean(raw, limit)
    local parent = S.Public(raw, "table")
    if not parent then return nil end
    local ok, length = pcall(function() return #parent end)
    if not ok or length > (limit or 16) then return nil end
    local rows = {}
    for i=1,length do
        local got, rawRow = pcall(function() return parent[i] end)
        local row = got and S.Public(rawRow, "table")
        if not row then return nil end
        local rawID = S.Field(row,"spellID","number")
        local id = S.ID(rawID)
        local name = S.Field(row,"name","string")
        local ids = S.Field(row,"matchIDs","table")
        local pending = S.Field(row,"unverified","boolean") == true and rawID == 0
        local repeats, repeatReason = S.Field(row,"repeatCount","number")
        if repeatReason=="NO_DATA" then repeats=1 end
        if not repeats or repeats<1 or repeats>99 or repeats%1~=0 then return nil end
        if id==6603 then repeats=1 end
        local policy,policyReason=S.Field(row,"usagePolicy","string")
        if policyReason=="NO_DATA" then policy="always" end
        if policy~="always" and policy~="target" and policy~="combat" then return nil end
        if (not id and not pending) or id==7268 or not name or #name < 1 or #name > 128 or not ids then return nil end
        local measured, size = pcall(function() return #ids end)
        if not measured or size > 16 or (size<1 and not pending) or (pending and size~=0) then return nil end
        local matches = {}
        for j=1,size do
            local read, value = pcall(function() return ids[j] end)
            local match = read and S.ID(value)
            if not match or match == 7268 then return nil end
            matches[j] = match
        end
        rows[i] = {name=name,spellID=id or 0,matchIDs=matches,unverified=pending or nil,repeatCount=repeats,usagePolicy=policy,skipUnavailable=id~=6603 and S.Field(row,"skipUnavailable","boolean")==true}
    end
    return rows
end

function P:Initialize(e, old)
    local scene = S.Field(old,"scene","string")
    if scene ~= "multi" then scene = "single" end
    e.db.classProfiles={}; e.db.sourceByProfile={}
    e.db.profileMigrationConflicts={}
    local conflicts=S.Field(old,"profileMigrationConflicts","table")
    for class in pairs(classes) do
        if conflicts and S.Field(conflicts,class,"boolean")==true then e.db.profileMigrationConflicts[class]=true end
    end
    e.db.apl=TEF.APL and TEF.APL.Clean(S.Field(old,"apl","table")) or nil
    local retiredClassAPL=e.db.apl and e.db.apl.template~="custom"
    if e.db.apl then e.db.apl.template="custom" end
    e.db.aplByClass={}
    local aplModes=S.Field(old,"aplByClass","table")
    for class in pairs(classes) do
        local mode=aplModes and S.Field(aplModes,class,"table")
        if mode then e.db.aplByClass[class]={single=not retiredClassAPL and S.Field(mode,"single","boolean")==true,multi=not retiredClassAPL and S.Field(mode,"multi","boolean")==true} end
    end
    local savedClasses=S.Field(old,"classProfiles","table")
    local sources=S.Field(old,"sourceByProfile","table")
    if savedClasses then
        local scanned=0
        local copied=pcall(function()
            for rawKey,rawProfile in pairs(savedClasses) do
                scanned=scanned+1; if scanned>65 then break end
                local key=S.Public(rawKey,"string")
                if key and validKey(key) then
                    e.db.classProfiles[key]={}
                    local savedSource=sources and S.Field(sources,key,"table")
                    e.db.sourceByProfile[key]={}
                    for _,sceneKey in ipairs({"single","multi"}) do
                        -- Preserve old 17..32-row configuration for explicit editing;
                        -- Engine.Validate refuses to run it until reduced to 16.
                        e.db.classProfiles[key][sceneKey]=self:Clean(S.Field(rawProfile,sceneKey,"table"),32) or {}
                        local source=savedSource and S.Field(savedSource,sceneKey,"string")
                        e.db.sourceByProfile[key][sceneKey]="manual"
                    end
                end
            end
        end)
        if not copied then e.db.classProfiles={}; e.db.sourceByProfile={} end
    end
    -- Unique populated legacy spec profile migrates once; conflicting profiles
    -- remain preserved, with an empty base and a visible diagnostic.
    for class in pairs(classes) do
        local base=class .. ":base"
        if not e.db.classProfiles[base] then
            local candidates={}
            for key,profile in pairs(e.db.classProfiles) do
                if key:match("^" .. class .. ":%d+$") and (#profile.single>0 or #profile.multi>0) then candidates[#candidates+1]=key end
            end
            if #candidates==1 then
                local key=candidates[1]
                e.db.classProfiles[base]={single=self:Clean(e.db.classProfiles[key].single,32),multi=self:Clean(e.db.classProfiles[key].multi,32)}
                local source=e.db.sourceByProfile[key] or {}
                e.db.sourceByProfile[base]={single=source.single,multi=source.multi}
                e:Log("lifecycle","CLASS_BASE_PROFILE_MIGRATED")
            elseif #candidates>1 then
                e.db.classProfiles[base]={single={},multi={}}
                e.db.profileMigrationConflicts[class]=true
                e:Log("error","CLASS_BASE_PROFILE_MIGRATION_CONFLICT")
            end
        end
    end
    -- Legacy unscoped profiles were exclusively mage practice. Never migrate
    -- them to the currently logged-in non-mage character.
    if not e.db.classProfiles["MAGE:base"] then
        local saved=S.Field(old,"profiles","table")
        local mage={}
        for _,key in ipairs({"single","multi"}) do
            mage[key]=self:Clean(saved and S.Field(saved,key,"table"),32) or self:Clean(TEF.ProfileDefaults[key])
        end
        e.db.classProfiles["MAGE:base"]=mage
    end
    e.profileKey,e.classToken=self:Identity()
    if e.profileKey then
        if not e.db.classProfiles[e.profileKey] then
            e.db.classProfiles[e.profileKey]={single={},multi={}}
            if e.classToken=="MAGE" then
                for _,key in ipairs({"single","multi"}) do
                    e.db.classProfiles[e.profileKey][key]=self:Clean(e.db.classProfiles["MAGE:base"][key]) or {}
                end
            end
        end
        e.db.profiles=e.db.classProfiles[e.profileKey]
    else e.db.profiles={single={},multi={}} end
    local multi=e.db.profiles.multi
    if multi and #multi==2 and multi[1].unverified and multi[1].name=="变形术"
        and multi[2].spellID==5143 and #multi[2].matchIDs==1 and multi[2].matchIDs[1]==5143 then
        e.db.profiles.multi=self:Clean(TEF.ProfileDefaults.multi)
        e:Log("lifecycle","POLYMORPH_DEFAULT_MIGRATED",118)
    end
    e.scene, e.db.scene = scene, scene
    -- Explicit Engine.New(config) callers retain their own config. Bootstrap
    -- selects the saved profile separately; research never changes selection.
    e.db.schema = 4
    e.db.dispatch=TEF.Runtime and TEF.Runtime.Clean(S.Field(old,"dispatch","table")) or nil
    if not e.profileKey or e.classToken~="MAGE" then e.steps=TEF.Engine.Validate(e.db.profiles[scene]) end
    local hud = S.Field(old,"hud","table")
    local scale = hud and S.Field(hud,"scale","number")
    local locked = hud and S.Field(hud,"locked","boolean")
    local preview = hud and S.Field(hud,"preview","boolean")
    e.db.hud = {scale=scale and scale>=0.6 and scale<=1.8 and scale or 1,
        locked=locked==true, preview=preview~=false}
    e.db.hud.geometry=TEF.HudStyles.CleanGeometry(hud and S.Field(hud,"geometry","table"))
    e.db.hud.styles=TEF.HudStyles.Clean(hud and S.Field(hud,"styles","table"))
    local x=hud and S.Field(hud,"x","number"); local y=hud and S.Field(hud,"y","number")
    if x and y and math.abs(x)<=10000 and math.abs(y)<=10000 then e.db.hud.x=x; e.db.hud.y=y end
end

function P:Select(e, key)
    if key ~= "single" and key ~= "multi" then return false,"SCENE_INVALID" end
    local rows
    if TEF.Recommendation then rows=TEF.Recommendation:Rows(e,key) else rows=self:Clean(e.db.profiles[key]) end
    e:Reset() -- keeps success tombstones; old initiation can never take over.
    e.aplCandidate=nil; e.aplSnapshot=nil
    if TEF.APL then TEF.APL:Invalidate(true) end
    e.steps = TEF.Engine.Validate(rows)
    e.scene, e.db.scene = key, key
    if not rows then e:Log("lifecycle","PROFILE_UNCONFIGURED"); return false,"PROFILE_UNCONFIGURED" end
    e:Log("lifecycle","SCENE_CHANGED")
    return true
end

function P:Save(e, key, rows)
    if key ~= "single" and key ~= "multi" then return false,"SCENE_INVALID" end
    if not e.profileKey then return false,"PROFILE_IDENTITY_UNKNOWN" end
    local clean = self:Clean(rows)
    if not clean then return false,"CONFIG_INVALID" end
    e:Reset()
    e.db.profiles[key] = clean
    e.db.profileMigrationConflicts[e.classToken]=nil
    if e.scene == key then
        local selected=clean
        if TEF.Recommendation then selected=TEF.Recommendation:Rows(e,key) end
        e.steps = TEF.Engine.Validate(selected)
    end
    e:Log("lifecycle","CONFIG_SAVED")
    return true
end
function P:RefreshIdentity(e)
    local key,class=self:Identity()
    if key==e.profileKey then return false end
    e:Reset(); e.profileKey,e.classToken=key,class
    if key then
        e.db.classProfiles[key]=e.db.classProfiles[key] or {single={},multi={}}
        e.db.profiles=e.db.classProfiles[key]
    else e.db.profiles={single={},multi={}} end
    self:Select(e,e.scene); e:Log("lifecycle","PROFILE_IDENTITY_CHANGED")
    return true
end

function P:RowsText(rows)
    local lines = {}
    for _, row in ipairs(rows or {}) do
        local ids = {}
        for _, id in ipairs(row.matchIDs) do ids[#ids+1] = tostring(id) end
        lines[#lines+1] = row.unverified and ("?" .. row.name) or (row.spellID .. ":" .. table.concat(ids,"/"))
        if (row.repeatCount or 1)>1 then lines[#lines]=lines[#lines] .. "*" .. row.repeatCount end
        if row.skipUnavailable then lines[#lines]=lines[#lines] .. "!skip" end
        if row.usagePolicy=="target" or row.usagePolicy=="combat" then lines[#lines]=lines[#lines] .. "!" .. row.usagePolicy end
    end
    return table.concat(lines,"\n")
end
function P:Text(e, key) return self:RowsText(e.db.profiles[key]) end

function P:Parse(raw, limit)
    local text = S.Public(raw,"string")
    if not text or #text>4096 then return nil,"CONFIG_INVALID" end
    local rows = {}
    for line in text:gmatch("[^\r\n]+") do
        local policy=line:match("!(target)%s*$") or line:match("!(combat)%s*$") or "always"
        if policy~="always" then line=line:gsub("!" .. policy .. "%s*$","") end
        local skipUnavailable=line:match("!skip%s*$")~=nil
        if skipUnavailable then line=line:gsub("!skip%s*$","") end
        local repeats=1
        local body,count=line:match("^(.-)%s*%*%s*(%d+)%s*$")
        if body then line=body; repeats=tonumber(count) end
        local unresolved=line:match("^%?(.+)$")
        if unresolved then
            rows[#rows+1]={name=unresolved,spellID=0,matchIDs={},unverified=true,repeatCount=repeats,usagePolicy=policy,skipUnavailable=skipUnavailable}
        else
        local primary, rest = line:match("^%s*(%d+)%s*:%s*([%d/%s]+)%s*$")
        if not primary then primary=line:match("^%s*(%d+)%s*$"); rest=primary end
        if not primary then return nil,"CONFIG_INVALID" end
        local id = S.ID(tonumber(primary))
        if not id then return nil,"CONFIG_INVALID" end
        local ids = {}
        -- Explicit separators only: reject malformed/trailing empty matches.
        if rest:match("%d%s+%d") then return nil,"CONFIG_INVALID" end
        rest=rest:gsub("%s","")
        if rest:sub(1,1)=="/" or rest:sub(-1)=="/" or rest:find("//",1,true) then return nil,"CONFIG_INVALID" end
        for value in rest:gmatch("%d+") do ids[#ids+1]=tonumber(value) end
        rows[#rows+1]={name="技能 " .. id,spellID=id,matchIDs=ids,repeatCount=repeats,usagePolicy=policy,skipUnavailable=skipUnavailable}
        end
    end
    local clean=self:Clean(rows,limit)
    if #rows==0 then clean=nil end
    return clean,clean and "CONFIG_VALID" or "CONFIG_INVALID"
end

function P:ConfirmObserved(e)
    local step=e.steps and e.steps[e.index]
    if not step or not step.unverified then return false,"NO_PENDING_STEP" end
    local generation,scene,index=e.generation,e.scene,e.index
    for i=#e.db.diagnostics,1,-1 do
        local row=e.db.diagnostics[i]
        if row.session==e.session and row.generation==e.generation and row.current==e.index
            and row.event=="UNIT_SPELLCAST_SUCCEEDED" and row.reason=="OUT_OF_SEQUENCE" and row.spellID then
            local view=S.Spell(row.spellID,step.name)
            if generation~=e.generation or scene~=e.scene or index~=e.index then return false,"STALE_GENERATION" end
            if view.reason=="PUBLIC" and view.name==step.name then
                local rows=self:Clean(e.db.profiles[e.scene])
                if not rows then return false,"CONFIG_INVALID" end
                rows[e.index]={name=step.name,spellID=row.spellID,matchIDs={row.spellID},repeatCount=step.repeatCount,usagePolicy=step.usagePolicy,skipUnavailable=step.skipUnavailable}
                return self:Save(e,e.scene,rows)
            end
        end
    end
    return false,"NO_VERIFIED_NAME_SUCCESS"
end
