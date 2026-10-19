local _,T=...
local S,P=T.Safety,{}
T.APL.PublicConditions=P
P.ops={any=true,lt=true,le=true,eq=true,ne=true,ge=true,gt=true}
function P.Compare(value,op,threshold)
 if op=="any" then return true end
 if value==nil then return nil end
 if op=="lt" then return value<threshold elseif op=="le" then return value<=threshold
 elseif op=="eq" then return value==threshold elseif op=="ne" then return value~=threshold
 elseif op=="ge" then return value>=threshold elseif op=="gt" then return value>threshold end
 return nil
end
function P.Mana()
 local ok,raw,reason=S.Call("UnitPower","player",0)
 if not ok then return nil,reason end
 local current,why=S.Public(raw,"number"); if current==nil then return nil,why end
 local got,maximum,status=S.Call("UnitPowerMax","player",0)
 if not got then return nil,status end
 local max,classification=S.Public(maximum,"number"); if max==nil then return nil,classification end
 if current<0 or max<=0 or current>max then return nil,"UNKNOWN_NUMBER" end
 local calculated,value=pcall(function() return current/max*100 end)
 if calculated then return S.Public(value,"number") end
 return nil,"UNKNOWN_OPERATION_FAILED"
end
-- 固定数量物品探针提供距离区间，不伪造精确码数。
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
function P:DistanceBracket(unit,radius)
    local valid,why=S.Public(unit,"string")
    if why=="NO_DATA" then valid="target" end
    if not valid or (valid~="target" and not valid:match("^nameplate%d+$")) then return nil,nil,"UNIT_INVALID_OR_UNKNOWN" end
    unit=valid
    local checked,status=S.Public(radius,"number")
    if status~="NO_DATA" then
        if not checked or checked<=0 or checked>40 then return nil,nil,"RADIUS_INVALID" end
    end
    radius=checked
    if boolean("UnitExists",unit)~=true then return nil,nil,"TARGET_MISSING_OR_UNKNOWN" end
    if boolean("UnitIsUnit",unit,"player")~=false or boolean("UnitIsDeadOrGhost",unit)~=false then
        return nil,nil,"TARGET_INVALID_OR_UNKNOWN"
    end
    local attack=boolean("UnitCanAttack","player",unit)
    if attack==nil then return nil,nil,"TARGET_REACTION_UNKNOWN" end
    if not attack then
        if boolean("InCombatLockdown")~=false then return nil,nil,"FRIENDLY_COMBAT_OR_UNKNOWN" end
        if S.Resolve("C_ChallengeMode.IsChallengeModeActive") and boolean("C_ChallengeMode.IsChallengeModeActive")~=false then
            return nil,nil,"FRIENDLY_CHALLENGE_OR_UNKNOWN"
        end
    end
    local path=S.Resolve("C_Item.IsItemInRange") and "C_Item.IsItemInRange" or "IsItemInRange"
    if not S.Resolve(path) then return nil,nil,"ITEM_RANGE_UNAVAILABLE" end
    local low,high,known=0,nil,false
    local below,above
    if radius then
        for _,rung in ipairs(probes) do
            if rung[1]<=radius then below=rung[1] end
            if not above and rung[1]>=radius then above=rung[1] end
        end
    end
    for _,rung in ipairs(probes) do if not radius or rung[1]==below or rung[1]==above then
        for i=2,#rung do
            local ok,raw=S.Call(path,rung[i],unit)
            if ok then
                local v=S.Public(raw,"boolean")
                if v==nil then
                    local n=S.Public(raw,"number")
                    if n==1 then v=true elseif n==0 then v=false end
                end
                if v==true then high=math.min(high or rung[1],rung[1]); known=true end
                if v==false then low=math.max(low,rung[1]); known=true end
            end
        end
    end end
    if high and low>=high then return nil,nil,"ITEM_RANGE_CONFLICT" end
    if high then return low,high,"ITEM_BRACKET_ESTIMATE" end
    if known then return low,nil,"ITEM_LOWER_BOUND_ESTIMATE" end
    return nil,nil,"ITEM_RANGE_UNKNOWN"
end

function P.Distance()
 local fn=S.Resolve("UnitDistanceSquared"); if not fn then return nil,"UNAVAILABLE" end
 local ok,raw,checked=pcall(fn,"target"); if not ok then return nil,"CALL_FAILED" end
 local valid,why=S.Public(checked,"boolean"); if valid~=true then return nil,valid==false and "DISTANCE_NOT_CHECKED" or why end
 local squared,status=S.Public(raw,"number"); if squared==nil then return nil,status end
 if squared<0 then return nil,"UNKNOWN_NUMBER" end
 local calculated,value=pcall(math.sqrt,squared)
 if calculated then return S.Public(value,"number") end
 return nil,"UNKNOWN_OPERATION_FAILED"
end
-- 精确公开距离优先；不可得时实时读取区间，不使用HUD缓存。
function P:SampleDistance(state)
 state.distance,state.distanceReason=self.Distance()
 state.distanceLow,state.distanceHigh=nil,nil
 if state.distance==nil then
  self:PrepareRangeProbes()
  state.distanceLow,state.distanceHigh,state.distanceReason=self:DistanceBracket()
 end
end
function P.DistanceCompare(state,op,threshold)
 if op=="any" then return true end
 if state.distance~=nil then return P.Compare(state.distance,op,threshold) end
 local low,high=state.distanceLow,state.distanceHigh
 if low==nil then return nil end
 -- 下界是开区间：公开超出low；上界是闭区间。
 if op=="lt" then
  if high and high<threshold then return true end
  if low>=threshold then return false end
 elseif op=="le" then
  if high and high<=threshold then return true end
  if low>=threshold then return false end
 elseif op=="gt" then
  if low>=threshold then return true end
  if high and high<=threshold then return false end
 elseif op=="ge" then
  if low>=threshold then return true end
  if high and high<threshold then return false end
 elseif op=="eq" or op=="ne" then
  if threshold<=low or (high and threshold>high) then return op=="ne" end
 end
 return nil
end
function P.DistanceText(state)
 if not state then return "未采样" end
 if state.distance~=nil then return tostring(state.distance) end
 if state.distanceLow~=nil then
  return "(" .. tostring(state.distanceLow) .. "," .. (state.distanceHigh and tostring(state.distanceHigh) or "∞") .. "]（估测）"
 end
 return "未知"
end
local categories={
 {kind="cooldown",value=0,viewer="EssentialCooldownViewer"},
 {kind="cooldown",value=1,viewer="UtilityCooldownViewer"},
 {kind="buff",value=2,viewer="BuffIconCooldownViewer"},
 {kind="buff",value=3,viewer="BuffBarCooldownViewer"}}
local function key(kind,id) return kind .. ":" .. id end
local function visible(frame)
 local method=frame and S.Field(frame,"IsVisible","function")
 if method then
  local ok,value=pcall(method,frame)
  if ok then return S.Public(value,"boolean") end
 end
end
function P.CDM(rows)
 local requests,needed,out,skipped={},{},{},{}
 for _,row in ipairs(rows) do
  if row.enabled and not row.invalid and row.cdmKind and row.cdmKind~="none" then
   local id=row.cdmSpellID or row.spellID; local k=key(row.cdmKind,id)
   requests[k]=id; needed[row.cdmKind]=true; out[k]={reason="CDM_FRAME_MISSING"}
  end
 end
 for _,cat in ipairs(categories) do if needed[cat.kind] then
  local ok,list=S.Call("C_CooldownViewer.GetCooldownViewerCategorySet",cat.value,true)
  list=ok and S.Public(list,"table")
  local mappings,bad={},nil
  local measured,size=pcall(function() return list and #list end)
  if not measured or not size then bad="CDM_CATALOG_UNKNOWN"
  elseif size>128 then bad="CDM_CAPACITY"
  else
   for i=1,size do
    local id=S.ID(S.Field(list,i,"number"))
    if not id then bad="CDM_CATALOG_UNKNOWN"; break end
    local got,info=S.Call("C_CooldownViewer.GetCooldownViewerCooldownInfo",id)
    local record=got and S.Public(info,"table")
    if not record then bad="CDM_MAPPING_UNKNOWN"; break end
    local raw,why=S.Field(record,"spellID","number")
    local spell=raw and S.ID(raw)
    -- Official spellID is nilable (for example an equipment entry). A
    -- public missing spellID cannot be a direct spell identity. Secret or
    -- malformed identity remains unknown, never a proxy match.
    if not spell and why~="NO_DATA" then bad="CDM_MAPPING_UNKNOWN"; break end
    -- Exact directory spellID only; overrides/linked spells are not identity.
    if spell and requests[key(cat.kind,spell)] then mappings[id]=key(cat.kind,spell) end
   end
  end
  local viewer=S.Field(_G,cat.viewer,"table")
  local pool=viewer and S.Field(viewer,"itemFramePool","table")
  local enumerate=pool and S.Field(pool,"EnumerateActive","function")
  if not bad and enumerate then
   local got,iterator,state,var=pcall(enumerate,pool)
   iterator=got and S.Public(iterator,"function")
   if not iterator then bad="CDM_ENUMERATION_UNKNOWN"
   else
    for i=1,81 do
     local nextOK,raw=pcall(iterator,state,var)
     if not nextOK then bad="CDM_ENUMERATION_FAILED"; break end
     local frame,why=S.Public(raw,"table")
     if why=="NO_DATA" then break end
     if not frame then bad="CDM_FRAME_UNKNOWN"; break end
     if i>80 then bad="CDM_CAPACITY"; break end
     var=frame
     local id=S.ID(S.Field(frame,"cooldownID","number"))
     if not id then
      local get=S.Field(frame,"GetCooldownID","function")
      if get then local read,value=pcall(get,frame); if read then id=S.ID(value) end end
     end
     -- An unidentified frame has no proven relation to any requested spell.
     -- Keep scanning; it must neither supply INACTIVE nor erase exact matches.
     if not id then skipped[cat.kind]=(skipped[cat.kind] or 0)+1 end
     local k=id and mappings[id]
     if k then
      local shown=visible(frame)
      local active,classification
      if shown==true then active,classification=S.Field(frame,"isActive","boolean")
      elseif shown==false and cat.kind=="buff" and visible(viewer)==true
       and S.Field(frame,"hideWhenInactive","boolean")==true
       and S.Field(frame,"allowHideWhenInactive","boolean")==true then
       -- 增益条目可以因公开的不活动状态自行隐藏；面板整体隐藏不能授权。
       local value,why=S.Field(frame,"isActive","boolean")
       if value==false then active=false; classification="PUBLIC_INACTIVE_HIDDEN"
       else classification=value==nil and why or "CDM_HIDDEN_OR_UNKNOWN" end
      else classification="CDM_HIDDEN_OR_UNKNOWN" end
      local old=out[k]
      if active==nil then out[k]={reason=classification or "CDM_ACTIVE_UNKNOWN",uncertain=true}
      elseif old.uncertain or (old.value~=nil and old.value~=active) then out[k]={reason="CDM_CONFLICT",uncertain=true}
      else out[k]={value=active,reason=classification=="PUBLIC_INACTIVE_HIDDEN" and classification or "PUBLIC"} end

     end
    end
   end
  elseif not bad then bad="CDM_VIEWER_UNAVAILABLE" end
  if bad then for k in pairs(requests) do if k:match("^" .. cat.kind .. ":") then out[k]={reason=bad,uncertain=true} end end end
 end end
 for k in pairs(requests) do
  local kind=k:match("^([a-z]+):")
  local count=skipped[kind]
  if count then
   out[k].scanReason="CDM_FRAME_ID_UNKNOWN"; out[k].skippedFrames=count
   if out[k].reason=="CDM_FRAME_MISSING" then out[k].reason="CDM_FRAME_ID_UNKNOWN" end
  end
 end
 return out
end
function P:Sample(state,rows)
 local distance=false
 for _,r in ipairs(rows) do if r.enabled and not r.invalid then
  distance=distance or (r.distanceOp and r.distanceOp~="any")
 end end
 if distance then self:SampleDistance(state) end
 local cdm=self.CDM(rows)
 for i,row in ipairs(rows) do
  if row.cdmKind and row.cdmKind~="none" then
   local v=cdm[key(row.cdmKind,row.cdmSpellID or row.spellID)]
   local a=state.actions["custom_" .. i]
   if a and v then
    a.cdmActive,a.cdmReason=v.value,v.reason
    a.cdmScanReason,a.cdmSkippedFrames=v.scanReason,v.skippedFrames
   end
  end
 end
end
