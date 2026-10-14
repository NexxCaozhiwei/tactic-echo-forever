local _,TEF=...
local A,S=TEF.APL,TEF.Safety
local P={}; A.State=P
function P.Boolean(path,...)
 local ok,raw,reason=S.Call(path,...)
 if not ok then return nil,reason end
 return S.Public(raw,"boolean")
end
function P.Time()
 local ok,value=S.Call("GetTime"); local n=ok and S.Public(value,"number")
 if n and n>=0 then return n end
end
local function int(value,max)
 local v=S.Public(value,"number"); if v and v>=0 and v<=max and v%1==0 then return v end
end
function P:Invalidate(static)
 self.revision=(self.revision or 0)+1; self.dirty=true
 if static then self.learned=nil; self.talents=nil; self.build=nil end
end
-- 编辑时按需完整扫描；等级只来自同一公开法术书槽位，绝不按ID大小推断。
function P.HighestLearnedRank(rawID)
 local current=S.ID(rawID); if not current then return nil,"CURRENT_ID_UNKNOWN" end
 local got,info=S.Call("C_Spell.GetSpellInfo",current)
 local name=got and S.Field(info,"name","string"); if not name then return nil,"CURRENT_NAME_UNKNOWN" end
 local family=A.AbilityNames[name]
 local bank=S.Field(S.Field(Enum,"SpellBookSpellBank","table"),"Player","number")
 local spellType=S.Field(S.Field(Enum,"SpellBookItemType","table"),"Spell","number")
 local ok,raw=S.Call("C_SpellBook.GetNumSpellBookSkillLines"); local total=ok and int(raw,16)
 if not total or bank==nil or spellType==nil then return nil,"SPELLBOOK_UNKNOWN" end
 local highest,highestRank,seenRanks,seenIDs,slots=nil,nil,{},{},0
 for line=1,total do
  local read,record=S.Call("C_SpellBook.GetSpellBookSkillLineInfo",line)
  local offset=read and int(S.Field(record,"itemIndexOffset","number"),512)
  local count=read and int(S.Field(record,"numSpellBookItems","number"),256)
  if not offset or not count or slots+count>256 then return nil,"SPELLBOOK_UNKNOWN" end
  for index=offset+1,offset+count do
   slots=slots+1
   local valid,item=S.Call("C_SpellBook.GetSpellBookItemInfo",index,bank)
   local kind=valid and S.Field(item,"itemType","number")
   if kind==nil then return nil,"SPELLBOOK_UNKNOWN" end
   if kind==spellType then
    local id=S.ID(S.Field(item,"spellID","number")); local slotName=S.Field(item,"name","string")
    local nameFn=S.Resolve("C_SpellBook.GetSpellBookItemName")
    local named,rawName,rawRank
    if nameFn then named,rawName,rawRank=pcall(nameFn,index,bank) end
    local bookName=named and S.Public(rawName,"string"); local text=named and S.Public(rawRank,"string")
    if slotName and bookName and slotName~=bookName then return nil,"SPELLBOOK_NAME_CONFLICT" end
    slotName=slotName or bookName
    if not id or not slotName then return nil,"SPELLBOOK_UNKNOWN" end
    if slotName==name or (family and A.AbilityNames[slotName]==family) then
     if S.Field(item,"isPassive","boolean")~=false then return nil,"RANK_PASSIVE_UNKNOWN" end
     local known=P.Boolean("C_SpellBook.IsSpellKnown",id)
     if known==nil then return nil,"RANK_LEARNED_UNKNOWN" end
     if known==true then
      local rank=S.Field(item,"rank","number")
      local textRank=text and tonumber(text:match("^Rank (%d+)$") or text:match("^等级%s*(%d+)$"))
      if rank and textRank and rank~=textRank then return nil,"RANK_NUMBER_CONFLICT" end
      rank=rank or textRank
      if not rank or rank<1 or rank>100 or rank%1~=0 then return nil,"RANK_NUMBER_UNKNOWN" end
      if seenRanks[rank] and seenRanks[rank]~=id then return nil,"RANK_ID_AMBIGUOUS" end
      if seenIDs[id] and seenIDs[id]~=rank then return nil,"RANK_NUMBER_CONFLICT" end
      seenRanks[rank]=id; seenIDs[id]=rank
      if not highestRank or rank>highestRank then highest,highestRank=id,rank end
     end
    end
   end
  end
 end
 return highest,highest and "PUBLIC_HIGHEST_LEARNED_RANK" or "RANK_NOT_FOUND",highestRank
end
function P:Learned(config)
 local sets,complete={},false
 local bank=S.Field(S.Field(Enum,"SpellBookSpellBank","table"),"Player","number")
 local spellType=S.Field(S.Field(Enum,"SpellBookItemType","table"),"Spell","number")
 local ok,total=S.Call("C_SpellBook.GetNumSpellBookSkillLines"); total=ok and int(total,16)
 if total and bank~=nil and spellType~=nil then
  complete=true; local slots=0
  for line=1,total do
   local got,info=S.Call("C_SpellBook.GetSpellBookSkillLineInfo",line)
   local offset=got and int(S.Field(info,"itemIndexOffset","number"),512)
   local count=got and int(S.Field(info,"numSpellBookItems","number"),256)
   if not offset or not count or slots+count>256 then complete=false; break end
   for index=offset+1,offset+count do
    slots=slots+1
    local read,item=S.Call("C_SpellBook.GetSpellBookItemInfo",index,bank)
    local kind=read and S.Field(item,"itemType","number")
    if kind==nil then complete=false
    elseif kind==spellType then
     local id=S.ID(S.Field(item,"spellID","number"))
     local name=S.Field(item,"name","string")
     local passive=S.Field(item,"isPassive","boolean")
     local key=id and name and A.AbilityNames[name]
     if not id or not name or passive==nil then complete=false
     elseif key and passive==false and id~=7268 then
      -- Rank text is accepted only from the same public spellbook slot and
      -- matching semantic name. Unsupported localizations remain unresolved.
      local rank=S.Field(item,"rank","number")
      local fn=S.Resolve("C_SpellBook.GetSpellBookItemName")
      if not rank and fn then
       local ok,rawName,rawRank=pcall(fn,index,bank)
       local bookName=ok and S.Public(rawName,"string")
       local text=ok and S.Public(rawRank,"string")
       if bookName and A.AbilityNames[bookName]==key and text then
        rank=tonumber(text:match("^Rank (%d+)$") or text:match("^等级 (%d+)$"))
       end
      end
      sets[key]=sets[key] or {}; sets[key][id]={ability=key,rank=rank}
     end
    end
   end
  end
 end
 local learned={}
 for key,ability in pairs(A.Abilities) do
  local ids=sets[key] or {}; local explicit=config.exactIDs[key]
  -- Observed/candidate IDs only add positive known results. A false result
  -- for a catalogue rank does not prove all other ranks unlearned.
  if explicit then
   local known=P.Boolean("C_SpellBook.IsSpellKnown",explicit)
   local got,info=S.Call("C_Spell.GetSpellInfo",explicit)
   local name=got and S.Field(info,"name","string")
   if known==true and name and A.AbilityNames[name]==key then ids[explicit]=ids[explicit] or {ability=key}
   else
    local value; if known==false then value=false end
    learned[key]={known=value,reason="EXACT_ID_NOT_CERTIFIED"}; ids={}
   end
  elseif not next(ids) and ability.observedID then
   local id=ability.observedID
   local known=P.Boolean("C_SpellBook.IsSpellKnown",id)
   local got,info=S.Call("C_Spell.GetSpellInfo",id)
   local name=got and S.Field(info,"name","string")
   if known==true and name and A.AbilityNames[name]==key then ids[id]={ability=key} end
  end
  if not learned[key] then
   local resolved=A.RankResolver:Resolve(key,ids,explicit)
   local value
   if #resolved.candidates>0 then value=true elseif complete and not resolved.unknownKnown then value=false end
   learned[key]={known=value,spellID=resolved.spellID,reason=resolved.reason,candidates=resolved.candidates}
  end
 end
 return learned
end
-- Public 0/0 is sufficient evidence of inactivity; isActive alone is not.
-- No clock-based CD/GCD expiration, DurationObject or isOnGCD inference.
function P.Ready(id)
 local ok,record=S.Call("C_Spell.GetSpellCooldown",id)
 if not ok then return nil,"COOLDOWN_API_UNAVAILABLE" end
 local start=S.Field(record,"startTime","number")
 local duration=S.Field(record,"duration","number")
 local enabled=S.Field(record,"isEnabled","boolean")
 if enabled==false then return false,"COOLDOWN_DISABLED" end
 if enabled~=true or start==nil or duration==nil or start<0 or duration<0 then return nil,"COOLDOWN_UNKNOWN" end
 if start==0 and duration==0 then return true,"PUBLIC_ZERO_COOLDOWN" end
 return false,"PUBLIC_COOLDOWN_ACTIVE"
end
-- 对象、方法与返回值均先规范化；只保存标量，不保存Duration对象。
local function durationMethod(object,name,kind)
 local ok,raw=pcall(function() return object[name] end)
 if not ok then return nil,"FIELD_FAILED" end
 local method,why=S.Public(raw,"function"); if not method then return nil,why end
 local got,value=pcall(method,object); if not got then return nil,"CALL_FAILED" end
 local result,reason=S.Public(value,kind)
 if kind=="number" and result and result<0 then return nil,"UNKNOWN_NUMBER" end
 return result,reason
end
function P.ProbeHealth()
 local probe={}
 local ok,raw,why=S.Call("UnitHealthPercent","player",true)
 if not ok then probe.reason=why; return probe end
 probe.value,probe.reason=S.Public(raw,"number")
 if probe.value and (probe.value<0 or probe.value>100) then probe.value=nil; probe.reason="UNKNOWN_NUMBER" end
 return probe
end
function P.ProbeCooldown(id)
 local probe={}
 local ok,record,why=S.Call("C_Spell.GetSpellCooldown",id)
 if ok then probe.active,probe.activeReason=S.Field(record,"isActive","boolean")
 else probe.activeReason=why end
 local got,raw,reason=S.Call("C_Spell.GetSpellCooldownDuration",id)
 if not got then probe.objectReason=reason; return probe end
 local object,status=S.Public(raw,"table")
 if status=="UNKNOWN_TYPE" then object,status=S.Public(raw,"userdata") end
 probe.objectReason=status
 if not object then return probe end
 probe.isZero,probe.zeroReason=durationMethod(object,"IsZero","boolean")
 probe.total,probe.totalReason=durationMethod(object,"GetTotalDuration","number")
 probe.remaining,probe.remainingReason=durationMethod(object,"GetRemainingDuration","number")
 return probe
end
function P.FriendlyUnit()
 local exists=P.Boolean("UnitExists","target")
 if exists==nil then return nil,"FRIENDLY_TARGET_UNKNOWN" end
 if exists then
  local assist=P.Boolean("UnitCanAssist","player","target")
  if assist==nil then return nil,"FRIENDLY_TARGET_UNKNOWN" end
  if assist then
   if P.Boolean("UnitIsDeadOrGhost","target")~=false then return nil,"FRIENDLY_TARGET_DEAD_OR_UNKNOWN" end
   return "target","FRIENDLY_TARGET"
  end
 end
 -- 直接按键遵循游戏自身的自动自施法设置，不改目标、宏或绑定。
 local path=S.Resolve("C_CVar.GetCVarBool") and "C_CVar.GetCVarBool" or "GetCVarBool"
 if P.Boolean(path,"autoSelfCast")~=true then return nil,"AUTO_SELF_CAST_DISABLED_OR_UNKNOWN" end
 if P.Boolean("UnitExists","player")~=true or P.Boolean("UnitIsDeadOrGhost","player")~=false then return nil,"PLAYER_DEAD_OR_UNKNOWN" end
 return "player","PUBLIC_AUTO_SELF_CAST"
end
-- 失控冷却与普通冷却分离；未知不能视为未锁定。
P.ControlTypes={stun={STUN=true,STUN_MECHANIC=true},fear={FEAR=true,FEAR_MECHANIC=true},confuse={CONFUSE=true}}
function P.ProbeControl()
 local probe={types={},reason="UNKNOWN_CONTROL"}
 local ok,raw,why=S.Call("C_LossOfControl.GetActiveLossOfControlDataCount")
 local count=ok and int(raw,16)
 if not count then probe.reason=ok and "CONTROL_COUNT_UNKNOWN" or why; return probe end
 probe.count=count; probe.complete=true
 for i=1,count do
  local got,data=S.Call("C_LossOfControl.GetActiveLossOfControlData",i)
  local kind,status; if got then kind,status=S.Field(data,"locType","string") end
  if kind and #kind<=40 and kind:match("^[A-Z_]+$") then probe.types[kind]=true
  else probe.complete=false; probe.reason=status or "CONTROL_RECORD_UNKNOWN" end
 end
 if probe.complete then probe.reason="PUBLIC_CONTROL_TYPES" end
 return probe
end
function P.ControlMatch(probe,kind)
 if not probe then return nil end
 if kind=="any" then
  if next(probe.types or {}) then return true end
 else
  local types=P.ControlTypes[kind]; if not types then return nil end
  for token in pairs(types) do if probe.types and probe.types[token] then return true end end
 end
 if probe.complete==true then return false end
end
function P.LossOfControl(id)
 local ok,record,reason=S.Call("C_Spell.GetSpellLossOfControlCooldownInfo",id)
 if not ok then return nil,reason end
 local active,why=S.Field(record,"isActive","boolean")
 if active==nil then return nil,why end
 return not active,active and "PUBLIC_LOSS_OF_CONTROL_ACTIVE" or "PUBLIC_LOSS_OF_CONTROL_CLEAR"
end
function P:ReadAction(key,learned,readReady,override)
 local result={known=learned.known,spellID=learned.spellID,reason=learned.reason}
 local ability=override or A.Abilities[key]; local id=result.spellID
 if result.known~=true or not id then return result end
 result.loss_control_clear,result.lossControlReason=P.LossOfControl(id)
 local fn=S.Resolve("C_Spell.IsSpellUsable")
 if fn then
  local ok,usable,power=pcall(fn,id)
  if ok then
   result.usable=S.Public(usable,"boolean")
   local insufficient=S.Public(power,"boolean")
   if insufficient~=nil then result.power_ok=not insufficient end
  end
 end
 if ability.target=="friendly" then
  local unit,reason=P.FriendlyUnit(); result.targetUnit,result.targetReason=unit,reason
  if unit=="player" then result.in_range=true
  elseif unit=="target" then result.in_range=P.Boolean("C_Spell.IsSpellInRange",id,unit) end
 elseif ability.target=="self" or ability.target=="ground" then result.in_range=true
 else result.in_range=P.Boolean("C_Spell.IsSpellInRange",id,"target") end
 if readReady==true then result.ready,result.cooldownReason=P.Ready(id)
 else result.cooldownReason="NOT_REQUESTED" end
 return result
end
function P:Sample(e)
 local generation,serial,revision=e.generation,e.receiptSerial or 0,self.revision or 0
 local now=P.Time(); if not now then return nil,"APL_TIME_UNKNOWN" end
 local function fresh() return generation==e.generation and serial==(e.receiptSerial or 0) and revision==(self.revision or 0) end
 if not fresh() then return nil,"APL_STALE_SAMPLE" end
 if e.maintenanceActive or e.db.apl.template=="custom" then
  local state={generation=generation,receiptSerial=serial,revision=revision,sampledAt=now,
   combat={in_combat=P.Boolean("InCombatLockdown")},gcd={},actions={},talents={},buildSignature={},scene=e.scene,moving=P.Boolean("IsPlayerMoving")}
  A.Custom:Sample(e,state)
  if not fresh() then return nil,"APL_STALE_SAMPLE" end
  return state
 end
 local config=e.db.apl
 local learned,talents,build,provider=self.learned,self.talents,self.build,self.talentProvider
 if not learned then
  learned=self:Learned(config)
  if not fresh() then return nil,"APL_STALE_SAMPLE" end
  self.learned=learned
 end
 if not talents then
  talents,build,provider=A.TalentState:Read()
  if not fresh() then return nil,"APL_STALE_SAMPLE" end
  self.talents,self.build,self.talentProvider=talents,build,provider
 end
 local state={generation=generation,receiptSerial=serial,revision=revision,sampledAt=now,
  combat={in_combat=P.Boolean("InCombatLockdown")},gcd={},actions={},talents=talents,
  buildSignature=build,mana_band="UNKNOWN",scene=e.scene,moving=P.Boolean("IsPlayerMoving")}
 -- GCD is intentionally not queried or required by this APL policy.
 if not fresh() then return nil,"APL_STALE_SAMPLE" end
 local visible=TEF.Research:CountVisible()
 if visible.state=="PUBLIC_VALUE" then state.enemy_count=visible.value end
 -- Bounded live reads for the active v0 rules/fillers only. Registry coverage
 -- does not create a per-frame full spell or talent scan.
 for _,key in ipairs(A.RuleActions) do
  if not fresh() then return nil,"APL_STALE_SAMPLE" end
  state.actions[key]=self:ReadAction(key,learned[key],A:NeedsReady(config,key))
 end
 if generation~=e.generation or serial~=(e.receiptSerial or 0) or revision~=(self.revision or 0) then return nil,"APL_STALE_SAMPLE" end
 return state
end
