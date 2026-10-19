local _,T=...
local A,S=T.APL,T.Safety
local C={PolicyIdentities=setmetatable({}, {__mode="k"})}; A.Custom=C
-- 自定义增益技能独立授权，不改变内置伤害规则或技能等级选择。
C.AdditionalActions={arcane_intellect=true}
function C:SupportsName(name,id)
 if id==5019 then return true end
 local key=name and A.AbilityNames[name]
 if key and self.AdditionalActions[key] then return true end
 for _,k in ipairs(A.RuleActions) do if k==key then return true end end
 local ability=key and A.Abilities[key]
 if ability and ability.target then return true end
 return nil
end
local fields={group=true,targetMode=true,strategies=true,spellID=true,enabled=true,moving=true,enemyMin=true,enemyMax=true,activity=true,experimentalEnemies=true,invalid=true,requireReady=true,
 behavior=true,
 manaOp=true,manaValue=true,distanceOp=true,distanceValue=true,cdmKind=true,cdmState=true,cdmSpellID=true}
local classes={"MAGE","WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","SHAMAN","WARLOCK","DRUID","DEATHKNIGHT","MONK","DEMONHUNTER","EVOKER"}
function C:ClassSupported(class) for _,value in ipairs(classes) do if value==class then return true end end; return false end
local conditionKinds={comboPoints=true,lossOfControl=true,usable=true,range=true,distance=true,moving=true,enemies=true,cdmCooldown=true,cdmBuff=true,cooldown=true,combat=true,targetType=true,learned=true,succeeded=true,cdmStacks=true,rangedEnemies=true,nearbyEnemies=true}
local function onlyFields(record,allowed,limit)
 local count=0
 local ok=pcall(function() for raw in pairs(record) do
  count=count+1; local key=S.Public(raw,"string")
  if count>limit or not key or not allowed[key] then error("CUSTOM_STRATEGY_INVALID") end
 end end)
 return ok
end
function C.CleanStrategies(raw)
 local out={}; local list,why=S.Public(raw,"table")
 if why=="NO_DATA" then return nil end
 if not list then return nil,"CUSTOM_STRATEGY_INVALID" end
 local ok,size=pcall(function() return #list end)
 if not ok or size>8 then return nil,"CUSTOM_STRATEGY_CAPACITY" end
 for i=1,size do
  local r=S.Field(list,i,"table"); local mode=S.Field(r,"mode","string")
  local conditions=S.Field(r,"conditions","table")
  if not r or not onlyFields(r,{mode=true,conditions=true},2) then return nil,"CUSTOM_STRATEGY_INVALID" end
  local measured,count=pcall(function() return conditions and #conditions end)
  if (mode~="use" and mode~="skip") or not measured or not count or count<1 or count>8 then return nil,"CUSTOM_STRATEGY_INVALID" end
  local strategy={mode=mode,conditions={}}
  for j=1,count do
   local v=S.Field(conditions,j,"table"); local kind=S.Field(v,"kind","string")
   if not v or not onlyFields(v,{kind=true,value=true,min=true,max=true,spellID=true,op=true,threshold=true,target=true,radius=true,control=true},10) then return nil,"CUSTOM_STRATEGY_INVALID" end
   local value,classification=S.Field(v,"value","boolean")
   local c={kind=kind,value=value}
   if not conditionKinds[kind] then return nil,"CUSTOM_STRATEGY_INVALID" end
   if kind=="comboPoints" or kind=="distance" or kind=="enemies" or kind=="rangedEnemies" or kind=="cdmStacks" or kind=="nearbyEnemies" then
    local op,status=S.Field(v,"op","string")
    if status~="NO_DATA" then
     local threshold=S.Field(v,"threshold","number")
     if kind~="distance" or not A.PublicConditions.ops[op] or op=="any" or not threshold or threshold<0 or threshold>2000 then return nil,"CUSTOM_STRATEGY_INVALID" end
     c.op,c.threshold=op,threshold
    end
    for _,field in ipairs({"min","max"}) do
     local n,status=S.Field(v,field,"number")
     if status~="NO_DATA" and (not n or n<0 or n>(kind=="distance" and 2000 or kind=="cdmStacks" and 255 or kind=="comboPoints" and 10 or 40) or (kind~="distance" and n%1~=0)) then return nil,"CUSTOM_STRATEGY_INVALID" end
     c[field]=n
    end
    if (not c.min and not c.max and not c.op) or (c.min and c.max and c.min>c.max) then return nil,"CUSTOM_STRATEGY_INVALID" end
    c.value=nil
   elseif kind=="targetType" then
    local target=S.Field(v,"target","string")
    if target~="enemy" and target~="friendly" and target~="self" and target~="none" then return nil,"CUSTOM_STRATEGY_INVALID" end
    c.target=target; c.value=nil
   elseif classification~="PUBLIC" then return nil,"CUSTOM_STRATEGY_INVALID" end
   if kind=="lossOfControl" then
    local control=S.Field(v,"control","string")
    if control~="any" and control~="stun" and control~="fear" and control~="confuse" then return nil,"CUSTOM_STRATEGY_INVALID" end
    c.control=control
   end
   if kind=="nearbyEnemies" then
    local radius=S.Field(v,"radius","number")
    if not radius or radius<=0 or radius>40 then return nil,"CUSTOM_STRATEGY_INVALID" end
    c.radius=radius
   end
   if kind=="cdmCooldown" or kind=="cdmBuff" or kind=="cdmStacks" or kind=="learned" or kind=="succeeded" or kind=="rangedEnemies" then
    local id,status=S.Field(v,"spellID","number")
    if status~="NO_DATA" then c.spellID=S.ID(id); if not c.spellID then return nil,"CUSTOM_STRATEGY_INVALID" end end
   end
   if kind=="rangedEnemies" then
    local radius,status=S.Field(v,"radius","number")
    if status=="NO_DATA" then radius=10 end
    if not radius or radius<=0 or radius>40 then return nil,"CUSTOM_STRATEGY_INVALID" end
    c.kind="nearbyEnemies"; c.radius=radius; c.spellID=nil
   end
   strategy.conditions[#strategy.conditions+1]=c
  end
  out[#out+1]=strategy
 end
 return out
end
function C.CleanRows(raw)
 local rows={}; raw=S.Public(raw,"table"); if not raw then return rows end
 local ok,size=pcall(function() return #raw end)
 if not ok or size>16 then return {{enabled=false,invalid="CUSTOM_CAPACITY"}} end
 for i=1,size do
  local r=S.Field(raw,i,"table"); local row={spellID=r and S.ID(S.Field(r,"spellID","number")),enabled=true,moving="any",activity="any",distanceOp="any",cdmKind="none",cdmState="inactive"}
  local behavior,behaviorError=C.CleanBehavior(r); row.behavior=behavior
  if behaviorError then row.invalid=behaviorError end
  if not r or not row.spellID then row.invalid="CUSTOM_ID_INVALID" end
  if r then
   local mode,classification=S.Field(r,"targetMode","string")
   if classification~="NO_DATA" then
    if classification~="PUBLIC" or (mode~="auto" and mode~="self" and mode~="friendly" and mode~="enemy" and mode~="ground") then row.invalid="CUSTOM_TARGET_INVALID" else row.targetMode=mode end
   end
   local strategies,strategyError=C.CleanStrategies(S.Field(r,"strategies","table"))
   local _,strategyType=S.Field(r,"strategies","table")
   if strategyType~="NO_DATA" and strategyType~="PUBLIC" then strategyError="CUSTOM_STRATEGY_INVALID" end
   row.strategies=strategies; if strategyError then row.invalid=strategyError end
   for field,kind in pairs({enabled="boolean",requireReady="boolean",moving="string",activity="string",enemyMin="number",enemyMax="number",experimentalEnemies="boolean",manaOp="string",manaValue="number",distanceOp="string",distanceValue="number",cdmKind="string",cdmState="string",cdmSpellID="number"}) do
    local _,why=S.Field(r,field,kind)
    if why~="PUBLIC" and why~="NO_DATA" then row.invalid="CUSTOM_CONDITION_INVALID" end
   end
   local count=0
   local valid=pcall(function() for k in pairs(r) do count=count+1; local key=S.Public(k,"string"); if count>24 or not key or not fields[key] then row.invalid="CUSTOM_CONDITION_UNSUPPORTED" end end end)
   if not valid then row.invalid="CUSTOM_CONDITION_UNSUPPORTED" end
   local enabled=S.Field(r,"enabled","boolean"); if enabled~=nil then row.enabled=enabled end
   -- 兼容读取旧配置；已移除的数值冷却条件不再输出。
   local moving=S.Field(r,"moving","string"); local activity=S.Field(r,"activity","string")
   if moving=="yes" or moving=="no" or moving=="any" then row.moving=moving elseif moving then row.invalid="CUSTOM_CONDITION_INVALID" end
   if activity=="active" or activity=="inactive" or activity=="any" then row.activity=activity elseif activity then row.invalid="CUSTOM_CONDITION_INVALID" end
   row.experimentalEnemies=S.Field(r,"experimentalEnemies","boolean")==true
   for _,field in ipairs({"enemyMin","enemyMax"}) do
    local n=S.Field(r,field,"number")
    if n then if n>=0 and n<=40 and n%1==0 then row[field]=n else row.invalid="CUSTOM_CONDITION_INVALID" end end
   end
   if row.enemyMin and row.enemyMax and row.enemyMin>row.enemyMax then row.invalid="CUSTOM_CONDITION_INVALID" end
   for _,prefix in ipairs({"mana","distance"}) do
    local op=S.Field(r,prefix .. "Op","string") or "any"
    local value=S.Field(r,prefix .. "Value","number")
    if not A.PublicConditions.ops[op] or (value and (value<0 or value>(prefix=="mana" and 100 or 2000)))
     or (op~="any" and value==nil) then row.invalid="CUSTOM_CONDITION_INVALID" end
    if prefix=="distance" then row.distanceOp,row.distanceValue=op,value end
   end
   local kind=S.Field(r,"cdmKind","string") or "none"
   local state=S.Field(r,"cdmState","string") or "inactive"
   if kind~="none" and kind~="buff" and kind~="cooldown" then row.invalid="CUSTOM_CONDITION_INVALID" end
   if state~="active" and state~="inactive" then row.invalid="CUSTOM_CONDITION_INVALID" end
   row.cdmKind,row.cdmState=kind,state
   local id=S.Field(r,"cdmSpellID","number"); if id then row.cdmSpellID=S.ID(id); if not row.cdmSpellID then row.invalid="CUSTOM_CONDITION_INVALID" end end
   if S.Field(r,"invalid","string") then row.invalid=row.invalid or "CUSTOM_CONDITION_INVALID" end
  end
  local group,groupType=S.Field(r,"group","table")
  if groupType~="NO_DATA" then
   local clean,why=T.SkillGroups:Clean(group)
   if groupType~="PUBLIC" or not clean then row.invalid=why or "GROUP_INVALID"
   else
    row.group=clean; local first=clean.steps[1]; row.spellID=first and first.spellID or 0
    if first then
     if row.invalid=="CUSTOM_ID_INVALID" then row.invalid=nil end
     row.targetMode=first.targetMode
    else row.invalid="GROUP_EMPTY" end
   end
  end
  if behaviorError then row.invalid=behaviorError end
  rows[#rows+1]=row
 end
 return rows
end
function C:UpgradeStrategies(row)
 local conditions={}
 if row.moving and row.moving~="any" then conditions[#conditions+1]={kind="moving",value=row.moving=="yes"}; row.moving="any" end
 if row.activity and row.activity~="any" then conditions[#conditions+1]={kind="cooldown",value=row.activity=="active"}; row.activity="any" end
 if row.distanceOp and row.distanceOp~="any" then
  conditions[#conditions+1]={kind="distance",op=row.distanceOp,threshold=row.distanceValue}; row.distanceOp="any"; row.distanceValue=nil
 end
 if row.cdmKind and row.cdmKind~="none" then
  conditions[#conditions+1]={kind=row.cdmKind=="buff" and "cdmBuff" or "cdmCooldown",value=row.cdmState=="active",spellID=row.cdmSpellID}
  row.cdmKind="none"; row.cdmSpellID=nil
 end
 if row.experimentalEnemies and (row.enemyMin or row.enemyMax) then
  conditions[#conditions+1]={kind="enemies",min=row.enemyMin,max=row.enemyMax}; row.enemyMin=nil; row.enemyMax=nil
 end
 row.strategies=row.strategies or {}
 if #conditions>0 then
  if #row.strategies>=8 then row.invalid="CUSTOM_STRATEGY_CAPACITY" else row.strategies[#row.strategies+1]={mode="use",conditions=conditions} end
 end
 return row
end
function C.CleanProfiles(raw)
 local out={}
 for _,class in ipairs(classes) do
  local p=S.Field(raw,class,"table")
  if p then out[class]={single=C.CleanRows(S.Field(p,"single","table")),multi=C.CleanRows(S.Field(p,"multi","table")),third=C.CleanRows(S.Field(p,"third","table"))} end
 end
 return out
end
function C:Rows(e,scene)
 if e.maintenanceActive and not scene then return T.Maintenance:Rows(e) end
 local p=e.db.apl.custom[e.classToken or ""]
 return p and p[scene or e.scene] or {}
end
function C:Save(e,rows,scene,class)
 if class~=e.classToken or not self:ClassSupported(class) or (scene~="single" and scene~="multi" and scene~="third") then return false,"CUSTOM_PROFILE_UNKNOWN" end
 local clean=C.CleanRows(rows)
 local valid,errors=self:Audit(clean); if not valid then return false,errors end
 for _,r in ipairs(clean) do if r.invalid then return false,r.invalid end end
 e:Reset(); e.db.apl.custom[class]=e.db.apl.custom[class] or {}
 e.db.apl.custom[class][scene]=clean; e.db.apl.template="custom"
 A:Invalidate(true); if A:IsActive(e) then e.steps=nil end
 return true
end
function C:Read(id,requireReady,targetMode)
 local known=A.State.Boolean("C_SpellBook.IsSpellKnown",id)
 local ok,info=S.Call("C_Spell.GetSpellInfo",id); local name=ok and S.Field(info,"name","string")
 local key=name and A.AbilityNames[name]; local allowed=false
 if T.Maintenance and T.Maintenance.ControlBreakers[id] and name then
  targetMode="self"
 end
 if id==5019 and name then
  key="shoot"; allowed=true; A.Abilities.shoot={name=name,target="enemy"}
 end
 for _,k in ipairs(A.RuleActions) do if k==key then allowed=true end end
 if key and self.AdditionalActions[key] then allowed=true end
 local ability=allowed and A.Abilities[key] or (key and A.Abilities[key])
 -- 所有职业已学法术可进入自定义规则；目录名称不授权未知等级。
 local target=targetMode and targetMode~="auto" and targetMode or ability and ability.target
 if not target then
  local harmful=A.State.Boolean("C_Spell.IsSpellHarmful",id)
  local helpful=A.State.Boolean("C_Spell.IsSpellHelpful",id)
  local min=S.Field(info,"minRange","number"); local max=S.Field(info,"maxRange","number")
  if min==0 and max==0 and harmful==false then target="self"
  elseif harmful==true then target="enemy" elseif helpful==true and harmful==false then target="friendly" end
 end
 if not name then return {spellID=id,known=known,reason="CUSTOM_METADATA_UNKNOWN"} end
 local passivePath=S.Resolve("C_Spell.IsSpellPassive") and "C_Spell.IsSpellPassive" or "IsPassiveSpell"
 local passive=A.State.Boolean(passivePath,id)
 if passive==true then return {spellID=id,known=known,reason="CUSTOM_PASSIVE_SPELL"} end
 if (not ability or not ability.target) and passive~=false then return {spellID=id,known=known,reason="CUSTOM_PASSIVE_UNKNOWN"} end
 if not target then return {spellID=id,known=known,reason="CUSTOM_TARGET_UNKNOWN"} end
 local action=A.State:ReadAction(key,{known=known,spellID=id,reason="CUSTOM_EXACT_ID"},requireReady==true,{target=target})
 if id==5019 and action.in_range==nil then
  local ok,raw=S.Call("C_Spell.IsSpellInRange",id,"target"); local _,why=S.Public(raw,"boolean")
  if ok and why=="NO_DATA" then
   local b=T.Dispatch:ResolveCached(id)
   if b and T.Dispatch:VerifyCurrent(b) then action.in_range=A.State.Boolean("C_ActionBar.IsActionInRange",b.slot,"target") end
  end
 end
 action.name=name; action.target=target
 return action
end
function C:SampleStrategies(state,rows,e)
 state.engine=e
 local requests={}; local countNeeded=false; local distanceNeeded=false
 state.classToken=e.classToken
 state.otherKnown={}; state.succeeded={}; state.nearbyEnemies={}
 local radiusCount=0
 local function probe(radius)
  if state.nearbyEnemies[radius] then return end
  if radiusCount>=4 then state.nearbyEnemies[radius]={state="PROBE_CAPACITY"}; return end
  radiusCount=radiusCount+1; state.nearbyEnemies[radius]=T.Research:ProbeVisibleYards(radius)
 end
 local watched,knownMeasured={},{}; local budget=0
 local function watch(id)
  if watched[id] then return true end
  if budget>=16 then return false end
  watched[id]=true; budget=budget+1; return true
 end
 local targetNeeded=false; local activeMeasured={}
 for i,row in ipairs(rows) do if row.enabled and not row.invalid and row.strategies then
  local a=state.actions["custom_" .. i]
  for _,strategy in ipairs(row.strategies) do for _,condition in ipairs(strategy.conditions) do
   local kind,id=condition.kind,condition.spellID or row.spellID
   if kind=="nearbyEnemies" or kind=="rangedEnemies" then probe(condition.radius or 10) end
   if kind=="targetType" then targetNeeded=true end
   if kind=="comboPoints" and state.classToken=="ROGUE" and not state.comboPointProbe then state.comboPointProbe=A.State.ProbePower("ComboPoints") end
   if kind=="lossOfControl" and not state.controlProbe then state.controlProbe=A.State.ProbeControl() end
   if kind=="learned" and not knownMeasured[id] and watch(id) then knownMeasured[id]=true; state.otherKnown[id]=A.State.Boolean("C_SpellBook.IsSpellKnown",id) end
   if kind=="succeeded" then state.succeeded[id]=e:StrategySucceeded(id) end
   if condition.kind=="enemies" then countNeeded=true end
   if condition.kind=="distance" then distanceNeeded=true end
   if condition.kind=="cooldown" and a then
    if not activeMeasured[row.spellID] then
     activeMeasured[row.spellID]=true
     local probe=a.cooldownProbe
     if not probe then probe=A.State.ProbeCooldown(row.spellID) end
     state.strategyCooldowns=state.strategyCooldowns or {}; state.strategyCooldowns[row.spellID]=probe
    end
    a.active=state.strategyCooldowns[row.spellID].active
   end
   if condition.kind=="cdmCooldown" or condition.kind=="cdmBuff" then
    requests[#requests+1]={enabled=true,cdmKind=condition.kind~="cdmCooldown" and "buff" or "cooldown",cdmSpellID=condition.spellID or row.spellID}
   end
  end end
  if a then a.strategyCDM={} end
 end end
 if targetNeeded then
  local exists=A.State.Boolean("UnitExists","target")
  if exists==false then state.targetType="none"
  elseif exists==true then
   local selfTarget=A.State.Boolean("UnitIsUnit","target","player")
   if selfTarget==true then state.targetType="self"
   elseif selfTarget==false then
    local enemy=A.State.Boolean("UnitCanAttack","player","target")
    local friendly=A.State.Boolean("UnitCanAssist","player","target")
    if enemy==true and friendly==false then state.targetType="enemy"
    elseif friendly==true and enemy==false then state.targetType="friendly" end
   end
  end
 end
 if countNeeded then local v=T.Research:CountVisible(); state.enemy_count=v.state=="PUBLIC_VALUE" and v.value or nil end
 if distanceNeeded then A.PublicConditions:SampleDistance(state) end
 local cdm=A.PublicConditions.CDM(requests)
 for i,row in ipairs(rows) do
  local a=state.actions["custom_" .. i]
  if a and row.strategies then a.strategyCDM=cdm end
 end
end
function C:StrategyCondition(state,row,index,c)
 local a=state.actions["custom_" .. index] or {}; local value
 if c.kind=="usable" then
  if a.usable==false or a.power_ok==false then value=false
  elseif a.usable==true and a.power_ok==true then value=true end
 elseif c.kind=="lossOfControl" then value=A.State.ControlMatch(state.controlProbe,c.control)
 elseif c.kind=="comboPoints" then
  if state.classToken~="ROGUE" then return nil end
  local p=state.comboPointProbe; local n=p and p.value
  if n==nil or n<0 or n>10 or n%1~=0 then return nil end
  return (not c.min or n>=c.min) and (not c.max or n<=c.max)
 elseif c.kind=="combat" then value=state.combat and state.combat.in_combat
 elseif c.kind=="targetType" then if not state.targetType then return nil end; return state.targetType==c.target
 elseif c.kind=="learned" then value=state.otherKnown and state.otherKnown[c.spellID or row.spellID]
 elseif c.kind=="succeeded" then value=state.succeeded and state.succeeded[c.spellID or row.spellID]
 elseif c.kind=="nearbyEnemies" or c.kind=="rangedEnemies" then
  local record=state.nearbyEnemies and state.nearbyEnemies[c.radius or 10]
  if not record or record.state~="PUBLIC_BOUNDS" then return nil end
  return T.Research.CountBoundsMatch(record.lower,record.upper,c.min,c.max)
 elseif c.kind=="cdmStacks" then
  -- 兼容旧配置供用户删除，不把移除条件静默改成无条件派发。
  return nil
 elseif c.kind=="range" then value=a.in_range
 elseif c.kind=="moving" then value=state.moving
 elseif c.kind=="cooldown" then value=a.active
 elseif c.kind=="distance" then
  if c.op then return A.PublicConditions.DistanceCompare(state,c.op,c.threshold) end
  local low,high=true,true
  if c.min then low=A.PublicConditions.DistanceCompare(state,"ge",c.min) end
  if c.max then high=A.PublicConditions.DistanceCompare(state,"le",c.max) end
  if low==false or high==false then return false end
  if low==nil or high==nil then return nil end
  return true
 elseif c.kind=="enemies" then
  if state.enemy_count==nil then return nil end
  return (not c.min or state.enemy_count>=c.min) and (not c.max or state.enemy_count<=c.max)
 elseif c.kind=="cdmBuff" or c.kind=="cdmCooldown" then
  local key=(c.kind=="cdmBuff" and "buff:" or "cooldown:") .. (c.spellID or row.spellID)
  local record=a.strategyCDM and a.strategyCDM[key]; value=record and record.value
 end
 if value==nil then return nil end
 return value==c.value
end
function C:CheckStrategies(state,row,index)
 local useFalse,useUnknown,skipUnknown
 local firstFalse,firstUnknown
 state.strategyBlockDetails=state.strategyBlockDetails or {}; state.strategyBlockDetails[index]=nil
 for si,strategy in ipairs(row.strategies or {}) do
  local failed,unknown=false,false
  local falseDetail,unknownDetail
  for ci,condition in ipairs(strategy.conditions) do
   local v=self:StrategyCondition(state,row,index,condition)
   if v==false then failed=true elseif v==nil then unknown=true end
   if (v==false and not falseDetail) or (v==nil and not unknownDetail) then
    local detail={strategy=si,condition=ci,kind=condition.kind,spellID=condition.spellID or row.spellID,
     unknown=v==nil,description="策略" .. si .. "／条件" .. ci .. " · ID " .. (condition.spellID or row.spellID or 0) .. " · " .. self:ConditionView(state,row,index,condition)}
    if v==false then falseDetail=falseDetail or detail else unknownDetail=unknownDetail or detail end
   end
  end
  if strategy.mode=="skip" then
   if not failed and not unknown then return false,"CUSTOM_SKIP_STRATEGY_MATCHED" end
   if not failed and unknown then skipUnknown=true; firstUnknown=firstUnknown or unknownDetail end
  else
   if failed then useFalse=true; firstFalse=firstFalse or falseDetail elseif unknown then useUnknown=true; firstUnknown=firstUnknown or unknownDetail end
  end
 end
 if useFalse then state.strategyBlockDetails[index]=firstFalse; return false,"CUSTOM_USE_STRATEGY_UNMATCHED" end
 if useUnknown or skipUnknown then state.strategyBlockDetails[index]=firstUnknown; return nil,"UNKNOWN:custom:strategy" end
 return true,"CUSTOM_STRATEGIES_TRUE"
end
function C:Sample(e,state,provided)
 state.combat=state.combat or {in_combat=A.State.Boolean("InCombatLockdown")}
 if T.Maintenance then T.Maintenance:Context(e,state) end
 local rows=provided or self:Rows(e); local countNeeded=false; local probes={}; local actions={}
 for i,row in ipairs(rows) do
  if row.enabled and row.experimentalEnemies and (row.enemyMin or row.enemyMax) then countNeeded=true end
  local action
  if row.enabled and not row.invalid then
   local identity=row.spellID .. ":" .. (row.targetMode or "auto")
   local cached=actions[identity]
   if not cached then cached=self:Read(row.spellID,false,row.targetMode); actions[identity]=cached end
   action={}; for k,v in pairs(cached) do action[k]=v end
  else action={spellID=row.spellID} end
  if row.enabled and not row.invalid and action.known==true and row.spellID~=61304 then
   probes[row.spellID]=probes[row.spellID] or A.State.ProbeCooldown(row.spellID)
   action.cooldownProbe=probes[row.spellID]
   if row.activity~="any" then action.active=action.cooldownProbe.active end
  end
  state.actions["custom_" .. i]=action
 end
 if countNeeded then local value=T.Research:CountVisible(); if value.state=="PUBLIC_VALUE" then state.enemy_count=value.value end end
 state.healthProbe=A.State.ProbeHealth()
 A.PublicConditions:Sample(state,rows)
 self:SampleStrategies(state,rows,e)
 for i,row in ipairs(rows) do
  local action=state.actions["custom_" .. i]
  if action then
   action.conditionObservations={}
   for _,strategy in ipairs(row.strategies or {}) do for _,condition in ipairs(strategy.conditions) do
    if #action.conditionObservations<16 then
     local id=condition.spellID or row.spellID
     local observation={kind=condition.kind,spellID=id,result=self:StrategyCondition(state,row,i,condition)}
     if condition.kind=="cdmBuff" or condition.kind=="cdmCooldown" then
      local probe=action.strategyCDM and action.strategyCDM[(condition.kind=="cdmBuff" and "buff:" or "cooldown:") .. id]
      observation.reason=probe and probe.reason or "CDM_FRAME_MISSING"
     end
     if condition.kind=="targetType" then observation.text=state.targetType end
     if condition.kind=="comboPoints" then local p=state.comboPointProbe; observation.number=p and p.value; observation.reason=state.classToken~="ROGUE" and "CLASS_UNSUPPORTED" or p and p.reason or "UNKNOWN_COMBO_POINTS" end
     if condition.kind=="lossOfControl" then observation.text=condition.control; observation.reason=state.controlProbe and state.controlProbe.reason or "UNKNOWN_CONTROL"; observation.number=state.controlProbe and state.controlProbe.count end
     if condition.kind=="cdmStacks" then
      observation.reason="CDM_STACKS_REMOVED"

     end
     if condition.kind=="nearbyEnemies" or condition.kind=="rangedEnemies" then
      local radius=condition.radius or 10
      local v=state.nearbyEnemies[radius]
      if v then
       observation.probeRadius=radius; observation.lower=v.lower; observation.upper=v.upper; observation.unknownCount=v.unknown
       observation.probeReason=v.state; observation.reason=v.state
       if v.state=="PUBLIC_BOUNDS" then observation.probeResult=T.Research.CountBoundsMatch(v.lower,v.upper,condition.min,condition.max) end
       observation.details={}; for j=1,math.min(8,#(v.details or {})) do observation.details[j]=v.details[j] end
      end
     end
     action.conditionObservations[#action.conditionObservations+1]=observation
    end
   end end
  end
 end
end
function C:Check(state,row,index)
 if not row.group and state.maintenanceOwned and state.maintenanceOwned[row.spellID] then return false,"MAINTENANCE_OWNS_SPELL","MAINTENANCE" end
 if row.invalid then return false,row.invalid,"BLOCKED" end
 if not row.enabled then return false,"CUSTOM_DISABLED","DISABLED" end
 local action=state.actions["custom_" .. index] or {}; local unknown
 if action.reason=="CUSTOM_SPELL_UNSUPPORTED" then return false,action.reason,"BLOCKED" end
 if action.reason=="CUSTOM_PASSIVE_SPELL" then return false,action.reason,"BLOCKED" end
 if action.reason=="CUSTOM_TARGET_UNKNOWN" or action.reason=="CUSTOM_PASSIVE_UNKNOWN" or action.reason=="CUSTOM_METADATA_UNKNOWN" then return nil,"UNKNOWN:custom:" .. action.reason end
 if row.group and not T.SkillGroups:Admission(state,row,index) then return false,"GROUP_CONSUMED" end
 local strategies,strategyReason=self:CheckStrategies(state,row,index)
 if row.behavior and state.engine then
  local owner=state.policyOwner or row
  self:ObservePolicy(state.engine,owner,state,index)
  local allowed,why=self:PolicyAllowed(state.engine,owner,state.readOnly)
  if allowed==false then return false,why elseif allowed==nil then return nil,why end
 end
 if strategies==false then return false,strategyReason end
 if strategies==nil then unknown=strategyReason end
 local function require(value,wanted,why)
  if value==nil then unknown=unknown or "UNKNOWN:custom:" .. why; return true end
  return value==wanted
 end
 -- Preview eligibility is independent of the transport combat gate.
 local terms=A.Conditions:ActionTerms("custom_" .. index,false)
 if row.moving~="any" then terms[#terms+1]={op="moving",equals=row.moving=="yes"} end
 local basic,why=A.Conditions:All(state,terms,{})
 if basic==false then return false,"custom:" .. (why:match("([^:]+)$") or why) end
 if basic==nil then unknown="UNKNOWN:custom:" .. (why:match("([^:]+)$") or why) end
 if row.activity~="any" and not require(action.active,row.activity=="active","activity") then return false,"custom:activity" end
 local distance=A.PublicConditions.DistanceCompare(state,row.distanceOp or "any",row.distanceValue)
 if distance==nil then unknown=unknown or "UNKNOWN:custom:distance:" .. (state.distanceReason or "UNKNOWN")
 elseif distance==false then return false,"custom:distance" end
 if row.cdmKind and row.cdmKind~="none" then
  if not require(action.cdmActive,row.cdmState=="active","cdm:" .. (action.cdmReason or "UNKNOWN")) then return false,"custom:cdm" end
 end
 if row.enemyMin or row.enemyMax then
  if not row.experimentalEnemies then return false,"CUSTOM_ENEMIES_UNVERIFIED","BLOCKED" end
  local result=A.Conditions:One(state,{op="enemy_count",min=row.enemyMin or 0,max=row.enemyMax},{})
  if result==nil then unknown=unknown or "UNKNOWN:custom:enemies"
  elseif result==false then return false,"custom:enemies" end
 end
 if unknown then return nil,unknown end
 return true,"CUSTOM_CONDITIONS_TRUE"
end
function C:Evaluate(state,config,class)
 local trace,candidate={},nil
 local rows=state.maintenanceRows or (config.custom[class] and config.custom[class][state.scene]) or {}
 for i,row in ipairs(rows) do
  local allowed,reason,status=self:Check(state,row,i)
  trace[#trace+1]={rule="custom:" .. i,result=status or (allowed==nil and "UNKNOWN" or allowed and "TRUE" or "FALSE"),reason=reason}
  if allowed==true and not candidate then
   local a=state.actions["custom_" .. i]
   if a.spellID then candidate={spellID=a.spellID,action="custom_" .. i,rule="custom:" .. i,name=a.name,target=a.target,customIndex=i} end
  end
 end
 return candidate,candidate and "APL_CANDIDATE" or "APL_NO_PUBLIC_ELIGIBLE_RULE",trace
end
function C:Ledger(e)
 local lines={"自定义优先级：从上往下选第一条满足的规则；成功后重新求值。",
  "待命也评估；必需：已学、可用、资源足够、技能范围。冷却活动可选，派发另要求战斗。"}
 local state=e.aplSnapshot; local results={}
 lines[#lines+1]="最近观察：移动=" .. tostring(state and state.moving) .. "；可见敌人数=" .. tostring(state and state.enemy_count)
 lines[#lines+1]="距离=" .. A.PublicConditions.DistanceText(state)
 for _,r in ipairs(e.aplTrace and e.aplTrace.rules or {}) do results[r.rule]=r end
 for i,row in ipairs(self:Rows(e)) do
  local a=state and state.actions["custom_" .. i]; local result=results["custom:" .. i]
  lines[#lines+1]=i .. ". ID " .. (row.spellID or "?") .. " · " .. (result and result.result .. " · " .. result.reason or "未评估")
  if a then
   local parts={}; for _,field in ipairs({"known","usable","power_ok","in_range","active"}) do parts[#parts+1]=field .. "=" .. tostring(a[field]) end
   lines[#lines+1]=table.concat(parts,"；")
  end
  lines[#lines+1]="移动=" .. row.moving .. "；冷却活动=" .. row.activity .. "；可见敌人=" .. (row.enemyMin or "不限") .. "～" .. (row.enemyMax or "不限")
  lines[#lines+1]="距离=" .. (row.distanceOp or "any") .. " " .. (row.distanceValue or "") .. "；CDM=" .. (row.cdmKind or "none") .. "/" .. (row.cdmState or "inactive") .. " ID " .. (row.cdmSpellID or row.spellID or "?") .. " · " .. tostring(a and a.cdmActive) .. " / " .. (a and a.cdmReason or "未采样")
  for si,strategy in ipairs(row.strategies or {}) do
   lines[#lines+1]="策略" .. si .. "：" .. (strategy.mode=="use" and "使用" or "跳过") .. "；条件全部满足"
   for _,condition in ipairs(strategy.conditions) do
    local result=state and self:StrategyCondition(state,row,i,condition)
    local description=condition.kind .. "=" .. tostring(condition.value)
    if condition.kind=="comboPoints" or condition.kind=="distance" or condition.kind=="enemies" or condition.kind=="cdmStacks" or condition.kind=="rangedEnemies" or condition.kind=="nearbyEnemies" then description=condition.kind .. "：" .. (condition.min or "不限") .. "～" .. (condition.max or "不限") end
    if condition.op then description="距离" .. condition.op .. condition.threshold end
    if condition.kind=="nearbyEnemies" then description=description .. "；码数 " .. condition.radius .. "（自身范围）" end
    if condition.kind=="targetType" then description="目标类型=" .. condition.target end
    if condition.kind=="lossOfControl" then description="自身失控类型=" .. condition.control .. "；" .. (condition.value and "存在" or "不存在") end
    if condition.kind=="cdmBuff" or condition.kind=="cdmCooldown" or condition.kind=="cdmStacks" or condition.kind=="rangedEnemies" or condition.kind=="learned" or condition.kind=="succeeded" then description=description .. "；ID " .. (condition.spellID or row.spellID) end
    lines[#lines+1]=description .. "；观察=" .. (result==nil and "未知" or result and "满足" or "不满足")
   end
  end
  if a and a.cdmScanReason then lines[#lines+1]="CDM扫描：跳过身份未知帧 " .. (a.cdmSkippedFrames or 0) .. "；仅精确匹配帧决定该技能状态。" end
 end
 return table.concat(lines,"\n")
end

-- 行为只消费精确成功；诊断和未知采样均不得重新授权。
function C.CleanBehavior(row)
 local raw,status=S.Field(row,"behavior","table")
 if status=="NO_DATA" then return nil end
 if status~="PUBLIC" or not onlyFields(raw,{trigger=true,scope=true,emergency=true,after=true},4) then return nil,"BEHAVIOR_INVALID" end
 local trigger=S.Field(raw,"trigger","string") or "continuous"
 local scope=S.Field(raw,"scope","string") or "entry"
 local after=S.Field(raw,"after","string") or "resume"
 for _,field in ipairs({"trigger","scope","after"}) do local _,kind=S.Field(raw,field,"string"); if kind~="PUBLIC" and kind~="NO_DATA" then return nil,"BEHAVIOR_INVALID" end end
 local emergency,why=S.Field(raw,"emergency","boolean")
 local _,groupType=S.Field(row,"group","table")
 if not ({continuous=true,edge=true,target=true,combat=true})[trigger] or not ({entry=true,spell=true})[scope]
  or not ({resume=true,exit=true})[after] or (why~="PUBLIC" and why~="NO_DATA") or (scope=="spell" and (trigger=="edge" or groupType~="NO_DATA")) then return nil,"BEHAVIOR_INVALID" end
 return {trigger=trigger,scope=scope,emergency=emergency==true,after=after}
end
function C:CopyBehavior(from,to)
 local b,why=self.CleanBehavior(from); if why then return false,why end
 to.behavior=b; return true
end
function C:LifecycleContext(e)
 local combat=A.State.Boolean("InCombatLockdown")
 local p=e.policyContext or {epoch=1}
 if p.lastCombat==true and combat==false then p.epoch=p.epoch+1 end
 -- 未知不制造战斗边界，也不清空额度。
 if combat~=nil then p.lastCombat=combat end
 p.combat= combat; e.policyContext=p
 return p
end
function C:PolicyRecord(e,row,create)
 local b=row.behavior; if not b then return nil end
 local key=self.PolicyIdentities[row] or row
 if b.scope=="spell" then key=(e.maintenanceActive and "maintenance" or e.groupRun and e.groupRun.source or T.Recommendation:BaseSource(e)) .. ":" .. (e.classToken or "?") .. ":" .. (e.scene or "?") .. ":" .. row.spellID .. ":" .. b.trigger end
 if not e.policyRecords then if not create then return nil end; e.policyRecords={} end
 local r=e.policyRecords[key]
 if not r and create then
  if (e.policyRecordCount or 0)>=256 then return nil end
  r={}; e.policyRecords[key]=r; e.policyRecordCount=(e.policyRecordCount or 0)+1
 end
 return r
end
function C:ObservePolicy(e,row,state,index)
 if not row.behavior or not T.Runtime or T.Runtime.e~=e or not T.Runtime.intent or (T.UI and T.UI.settingsOpen) or state.readOnly then return end
 if state.generation and (state.generation~=e.generation or state.receiptSerial~=(e.receiptSerial or 0) or state.revision~=(A.State.revision or 0)) then return end
 local r=self:PolicyRecord(e,row,true); if not r then return end
 -- 仅策略明确不满足重新武装；冷却、资源和范围变化不算新触发。
 if row.behavior.trigger=="edge" and self:CheckStrategies(state,row,index)==false then r.consumed=nil end
end
function C:PolicyAllowed(e,row,readOnly)
 local b=row.behavior; if not b or b.trigger=="continuous" then return true end
 if row.spellID==6603 then return nil,"POLICY_SUCCESS_UNSUPPORTED" end
 local r=self:PolicyRecord(e,row,false)
 if r and r.blocked then return nil,"POLICY_CONTEXT_LOST" end
 if not r and (e.policyRecordCount or 0)>=256 then return nil,"POLICY_CAPACITY" end
 if b.trigger=="edge" then return not (r and r.consumed),"POLICY_EDGE_CONSUMED" end
 if b.trigger=="combat" then
  local p=e.policyContext
  if not p or p.combat~=true or A.State.Boolean("InCombatLockdown")~=true then return nil,"POLICY_COMBAT_UNKNOWN_OR_OUTSIDE" end
  if e.policyProgress and e.policyProgress.row==row and e.policyProgress.stamp~=p.epoch then return nil,"POLICY_PROGRESS_SCOPE_CHANGED" end
  return not (r and r.epochs and r.epochs[p.epoch]),"POLICY_COMBAT_CONSUMED"
 end
 local key
 if readOnly then
  if A.State.Boolean("UnitExists","target")==true then
   local ok,raw=S.Call("UnitGUID","target"); local guid=ok and S.Identity(raw)
   local cached=e.usageTarget
   key=cached and cached.selection==(e.usageTargetSerial or 0) and cached.key or guid and "GUID:" .. guid or "SELECTION:" .. (e.usageTargetSerial or 0)
  end
 else key=e:UsageTargetIdentity() end
 if not key then return nil,"POLICY_TARGET_UNKNOWN" end
 if e.policyProgress and e.policyProgress.row==row and e.policyProgress.stamp~=key then return nil,"POLICY_PROGRESS_SCOPE_CHANGED" end
 if r and (r.targetCount or 0)>=256 and not (r.targets and r.targets[key]) then return nil,"POLICY_TARGET_CAPACITY" end
 return not (r and r.targets and r.targets[key]),"POLICY_TARGET_CONSUMED"
end
function C:ReconcilePolicyProgress(e)
 local p=e.policyProgress
 if not p or e.maintenanceActive then return end
 local row=e.steps and e.steps[e.index]
 if row~=p.row then e.policyProgress=nil; return end
 local generation,index=e.generation,e.index
 local stamp=self:PolicyStamp(e,row)
 if generation~=e.generation or index~=e.index or stamp==nil or stamp==p.stamp then return end
 local prior=T.Runtime.internal; T.Runtime.internal=true; e:Invalidate("POLICY_PROGRESS_SCOPE_CHANGED"); T.Runtime.internal=prior
 e.stepCasts=0; e.policyProgress=nil
end
function C:PolicySucceeded(e,row)
 if not row or not row.behavior or row.behavior.trigger=="continuous" then return end
 local r=self:PolicyRecord(e,row,true); if not r then return end
 local mode=row.behavior.trigger
 if mode=="edge" then r.consumed=true
 elseif mode=="combat" then
  local p=e.policyContext; if not p or p.combat~=true then r.blocked=true; return end
  r.epochs={[p.epoch]=true}
 else
  local key=e:UsageTargetIdentity(); if not key then r.blocked=true; return end
  r.targets=r.targets or {}
  if not r.targets[key] then
   if (r.targetCount or 0)>=256 then r.blocked=true; return end
   r.targets[key]=true; r.targetCount=(r.targetCount or 0)+1
  end
 end
end
function C:CurrentPolicyRow(e)
 if e.maintenanceActive then return T.Maintenance:Rows(e)[e.aplCandidate and e.aplCandidate.customIndex or 0] end
 if T.Recommendation:Source(e)=="apl" then return self:Rows(e)[e.aplCandidate and e.aplCandidate.customIndex or 0] end
 return e.steps and e.steps[e.index]
end
function C:PolicyStamp(e,row)
 if not row or not row.behavior then return "none" end
 local mode=row.behavior.trigger
 if mode=="target" then return e:UsageTargetIdentity() end
 if mode=="combat" then local p=e.policyContext; return p and p.combat==true and A.State.Boolean("InCombatLockdown")==true and p.epoch or nil end
 return "stable"
end
local conditionLabels={moving="移动",combat="战斗",usable="技能可用与资源",range="技能范围",distance="目标距离",enemies="可见敌人数",
 nearbyEnemies="自身范围内可见敌人数",rangedEnemies="自身范围内可见敌人数",comboPoints="连击点",cdmStacks="已移除的CDM层数条件",
 cdmBuff="CDM增益活动",cdmCooldown="CDM冷却活动",cooldown="技能冷却活动",learned="已学技能",succeeded="精确成功记录",targetType="目标类型",lossOfControl="失控状态"}
local function publicText(v)
 local n=S.Public(v,"number"); if n then return tostring(n) end
 local b,why=S.Public(v,"boolean"); if why=="PUBLIC" then return b and "是" or "否" end
 local s=S.Public(v,"string"); if s and #s<=96 and not s:find("[|%c]") then return s end
 return "未知"
end
function C:ConditionView(state,row,index,c)
 if c.kind=="cdmStacks" then return "CDM层数条件已移除：请删除或更换类型后保存；旧条件保持未知阻断。" end
 local a=state and state.actions and state.actions["custom_" .. index] or {}
 local expected=c.value==nil and "" or (c.value and "是" or "否")
 if c.min or c.max then expected=(c.min or "不限") .. "～" .. (c.max or "不限") end
 if c.op then expected=c.op .. " " .. c.threshold end
 if c.target then expected=c.target end
 if c.control then expected=c.control .. " " .. expected end
 local value
 if state then
  if c.kind=="moving" then value=state.moving elseif c.kind=="combat" then value=state.combat and state.combat.in_combat
  elseif c.kind=="range" then value=a.in_range elseif c.kind=="cooldown" then value=a.active
  elseif c.kind=="usable" then if a.usable==false or a.power_ok==false then value=false elseif a.usable==true and a.power_ok==true then value=true end
  elseif c.kind=="distance" then value=A.PublicConditions.DistanceText(state)
  elseif c.kind=="targetType" then value=state.targetType
  elseif c.kind=="enemies" then value=state.enemy_count
  elseif c.kind=="comboPoints" then value=state.comboPointProbe and state.comboPointProbe.value
  elseif c.kind=="learned" then value=state.otherKnown and state.otherKnown[c.spellID or row.spellID]
  elseif c.kind=="succeeded" then value=state.succeeded and state.succeeded[c.spellID or row.spellID]
  elseif c.kind=="lossOfControl" then value=A.State.ControlMatch(state.controlProbe,c.control)
  elseif c.kind=="nearbyEnemies" or c.kind=="rangedEnemies" then
   local v=state.nearbyEnemies and state.nearbyEnemies[c.radius or 10]; if v and v.state=="PUBLIC_BOUNDS" then value=v.lower .. "～" .. v.upper end
  elseif c.kind=="cdmStacks" or c.kind=="cdmBuff" or c.kind=="cdmCooldown" then
   local v=a.strategyCDM and a.strategyCDM[(c.kind=="cdmCooldown" and "cooldown:" or "buff:") .. (c.spellID or row.spellID)]
   if v then if c.kind=="cdmStacks" then value=v.stacks else value=v.value end end
  end
 end
 local result; if state then result=self:StrategyCondition(state,row,index,c) end
 local why=""
 if result==nil and state then
  local record=c.kind=="cdmBuff" or c.kind=="cdmCooldown"
  local probe=record and a.strategyCDM and a.strategyCDM[(c.kind=="cdmCooldown" and "cooldown:" or "buff:") .. (c.spellID or row.spellID)]
  local code=probe and probe.reason or c.kind=="distance" and state.distanceReason or c.kind=="cooldown" and a.cooldownProbe and a.cooldownProbe.activeReason
  local explanations={SECRET="客户端限制了该值",UNAVAILABLE="当前客户端未提供接口",CALL_FAILED="接口调用失败",NO_DATA="接口没有返回数据",CDM_FRAME_MISSING="请确认对应技能已加入CDM并可见",CDM_VIEWER_UNAVAILABLE="CDM面板不可用",CDM_CONFLICT="CDM存在相互冲突的结果",CDM_HIDDEN_OR_UNKNOWN="CDM隐藏或可见性未知",ITEM_RANGE_UNKNOWN="距离探针没有公开结果"}
  why="；" .. (explanations[code] or (c.kind=="comboPoints" and state.classToken~="ROGUE" and "当前职业不支持此条件" or "缺少可确认的公开结果，请检查观察对象及对应条件"))
 end
 return (conditionLabels[c.kind] or c.kind) .. "：要求 " .. expected .. "；采样 " .. publicText(value) .. "；" .. (result==nil and "未知，阻断" or result and "满足" or "不满足") .. why
end
-- 体检只检查可证明的配置问题，不用瞬时资源或未知API拒绝保存。
function C:Audit(rows,e)
 local errors,warnings={},{}
 local checked,budget={},0
 local function inspect(row,path)
  local combined={}
  if e and row.spellID and not row.group and not checked[row.spellID] and budget<64 then
   checked[row.spellID]=true; budget=budget+1
   if A.State.Boolean("C_SpellBook.IsSpellKnown",row.spellID)==false then warnings[#warnings+1]=path .. "：精确技能ID当前未学，请检查技能等级或替换。" end
  end
  if row.spellID==6603 and row.behavior and row.behavior.trigger~="continuous" then errors[#errors+1]=path .. "：自动攻击按开启状态推进，不支持按精确施法成功计数的触发方式。" end
  for si,strategy in ipairs(row.strategies or {}) do
   local issues=strategy.mode=="use" and errors or warnings
   local terms=strategy.mode=="use" and combined or {}
   for _,c in ipairs(strategy.conditions or {}) do
    local key=c.kind .. ":" .. (c.spellID or row.spellID or 0) .. ":" .. (c.radius or 0) .. ":" .. (c.control or "")
    local current=terms[key] or {}; terms[key]=current
    local fixed=c.target or c.value
    if c.target~=nil or c.value~=nil then
     if current.has and current.fixed~=fixed then issues[#issues+1]=path .. "：" .. (conditionLabels[c.kind] or c.kind) .. "要求互相矛盾。" end
     current.has=true; current.fixed=fixed
    end
    local low,high=c.min,c.max
    if c.op=="ge" or c.op=="gt" then low=c.threshold elseif c.op=="le" or c.op=="lt" then high=c.threshold elseif c.op=="eq" then low,high=c.threshold,c.threshold end
    if low then
     if not current.low or low>current.low then current.low,current.lowOpen=low,c.op=="gt"
     elseif low==current.low and c.op=="gt" then current.lowOpen=true end
    end
    if high then
     if not current.high or high<current.high then current.high,current.highOpen=high,c.op=="lt"
     elseif high==current.high and c.op=="lt" then current.highOpen=true end
    end
    if c.op=="ne" then current.excluded=current.excluded or {}; current.excluded[c.threshold]=true end
    if current.low and current.high and (current.low>current.high or (current.low==current.high and (current.lowOpen or current.highOpen or current.excluded and current.excluded[current.low]))) then
     issues[#issues+1]=path .. "：" .. (conditionLabels[c.kind] or c.kind) .. "没有共同取值。"
    end
   end
  end
  if row.behavior and row.behavior.trigger=="edge" and #(row.strategies or {})==0 then warnings[#warnings+1]=path .. "：无条件的一次触发只能在重置后再次执行。" end
  if row.group then for i,step in ipairs(row.group.steps) do inspect(step,path .. "/组内" .. i) end end
 end
 for i,row in ipairs(rows or {}) do
  inspect(row,"第" .. i .. "项")
  if row.enabled~=false and not row.group and #(row.strategies or {})==0 then warnings[#warnings+1]="第" .. i .. "项无策略条件，可能优先遮蔽后续条目；仍受技能资格限制。" end
 end
 return #errors==0,table.concat(errors,"\n"),table.concat(warnings,"\n")
end
function C:Explain(e)
 local source=T.Recommendation:Source(e)
 local rows=source=="manual" and (e.steps or {}) or self:Rows(e)
 if source=="manual" then
  local views={}
  for i,row in ipairs(rows) do
   local v={spellID=row.spellID,enabled=row.enabled~=false,group=row.group,strategies=row.strategies,behavior=row.behavior,targetMode=row.targetMode,
    moving="any",activity="any",distanceOp="any",cdmKind="none"}
   self.PolicyIdentities[v]=self.PolicyIdentities[row] or row; views[i]=v
  end
  rows=views
 end
 local now=A.State.Time()
 local state={readOnly=true,generation=e.generation,receiptSerial=e.receiptSerial or 0,revision=A.State.revision or 0,
  sampledAt=now,actions={},moving=A.State.Boolean("IsPlayerMoving")}
 self:Sample(e,state,rows)
 if state.generation~=e.generation or state.receiptSerial~=(e.receiptSerial or 0) or state.revision~=(A.State.revision or 0) then state=nil end
 local lines={"策略解释（只读现场采样，不授予派发资格）", "运行：" .. (T.Runtime.reason or "未启动") .. "；来源：" .. source}
 if not state then lines[#lines+1]="采样期间状态变化，本次结果未知。" end
 for i,row in ipairs(rows) do
  local sampled=state and state.actions and state.actions["custom_" .. i]
  local matching=sampled and sampled.spellID==row.spellID
  lines[#lines+1]=i .. ". ID " .. row.spellID .. (row.group and " 技能组" or "")
  if state then
   local allowed,reason=self:Check(state,row,i)
   lines[#lines+1]=(allowed==nil and "未知，阻断" or allowed and "条件符合" or "当前不符合") .. " · " .. (reason or "UNKNOWN")
   if source=="manual" and i~=e.index then lines[#lines+1]="当前列表尚未执行到此步。" end
  end
  if matching then
   local names={known="已学",usable="可用",power_ok="资源足够",in_range="技能范围",loss_control_clear="无技能失控阻断"}
   for _,field in ipairs({"known","usable","power_ok","in_range","loss_control_clear"}) do lines[#lines+1]=names[field] .. "=" .. publicText(sampled[field]) end
  end
  for _,strategy in ipairs(row.strategies or {}) do
   lines[#lines+1]=strategy.mode=="skip" and "跳过策略（全部满足才跳过）" or "使用策略（全部满足才允许）"
   for _,condition in ipairs(strategy.conditions) do lines[#lines+1]=self:ConditionView(matching and state or nil,row,i,condition) end
  end
 end
 local _,errors,warnings=self:Audit(rows,e)
 lines[#lines+1]="配置体检：" .. (errors~="" and errors or "未发现可证明的条件矛盾。")
 if warnings~="" then lines[#lines+1]=warnings end
 return table.concat(lines,"\n")
end
function C:Timeline(e)
 local lines={"运行事件时间线（最近24条，输入请求不等于游戏成功）"}
 for i=math.max(1,#e.db.diagnostics-23),#e.db.diagnostics do
  local r=e.db.diagnostics[i]
  lines[#lines+1]="会话 " .. publicText(r.session) .. " / 起始身份 " .. publicText(r.attempt) .. " / 起始请求 " .. publicText(r.attemptRequest) .. " / 时间 " .. publicText(r.time) .. "\n代次 " .. publicText(r.generation) .. " / 请求 " .. publicText(r.request) .. " / 轮 " .. publicText(r.cycle)
   .. " · ID " .. publicText(r.spellID) .. " · " .. publicText(r.reason) .. " · " .. publicText(r.current) .. "→" .. publicText(r.next)
 end
 lines[#lines+1]="桌面端是否真正执行须结合TEK日志核对；游戏成功仅认精确回执。"
 return table.concat(lines,"\n")
end
