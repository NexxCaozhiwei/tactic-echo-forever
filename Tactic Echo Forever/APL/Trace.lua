local _,TEF=...
local T={}; TEF.APL.Trace=T
function T:Record(e,trace,reason,candidate,state,channel)
 local field=channel=="maintenance" and "maintenanceTrace" or "aplTrace"
 local old=e[field]
 local parts={reason}
 if state then parts[#parts+1]=tostring(state.gcd.ready); for _,key in ipairs({"fireball","frostbolt","scorch","arcane_missiles"}) do local a=state.actions[key]; if a then for _,field in ipairs({"known","usable","power_ok","in_range","loss_control_clear","ready"}) do parts[#parts+1]=tostring(a[field]) end end end end
 for _,r in ipairs(trace) do parts[#parts+1]=r.rule .. ":" .. r.result .. ":" .. r.reason end
 for _,tree in ipairs({"ARCANE","FIRE","FROST"}) do parts[#parts+1]=state and state.buildSignature[tree] or "UNKNOWN" end
 if state then
  local health=state.healthProbe
  if health then parts[#parts+1]="health=" .. tostring(health.value) .. ":" .. (health.reason or "UNKNOWN") end
  parts[#parts+1]="moving=" .. tostring(state.moving)
  parts[#parts+1]="visible=" .. tostring(state.enemy_count)
  parts[#parts+1]="mana=" .. tostring(state.manaPercent) .. ":" .. (state.manaReason or "UNKNOWN")
  parts[#parts+1]="distance=" .. TEF.APL.PublicConditions.DistanceText(state) .. ":" .. (state.distanceReason or "UNKNOWN")
  for i=1,16 do
   local a=state.actions["custom_" .. i]
   if a then
    parts[#parts+1]="custom_" .. i .. "=" .. tostring(a.spellID)
    for _,field in ipairs({"known","usable","power_ok","in_range","loss_control_clear","ready","active"}) do parts[#parts+1]=tostring(a[field]) end
    parts[#parts+1]=a.lossControlReason or "UNKNOWN"
    parts[#parts+1]=tostring(a.cdmActive) .. ":" .. (a.cdmReason or "UNKNOWN")
    parts[#parts+1]=(a.cdmScanReason or "NONE") .. ":" .. tostring(a.cdmSkippedFrames)
    for _,v in ipairs(a.conditionObservations or {}) do
     parts[#parts+1]=v.kind .. ":" .. tostring(v.result) .. ":" .. tostring(v.number) .. ":" .. (v.reason or "UNKNOWN") .. ":" .. (v.text or "UNKNOWN")
     if v.catalogEntryCount~=nil then
      for _,field in ipairs({"catalogEntryCount","frameScanCount","catalogMatchCount","frameMatchCount"}) do parts[#parts+1]=field .. "=" .. tostring(v[field]) end
      for _,id in ipairs(v.catalogSpellIDs or {}) do parts[#parts+1]="catalogID=" .. id end
     end
     for _,field in ipairs({"probeRadius","lower","upper","unknownCount","probeReason","probeResult","identitySource","identityIndex"}) do parts[#parts+1]=field .. "=" .. tostring(v[field]) end
     for _,d in ipairs(v.details or {}) do
      parts[#parts+1]=(d.identityReason or "UNKNOWN") .. ":" .. (d.source or "UNKNOWN") .. ":" .. (d.rangeReason or "UNKNOWN") .. ":" .. (d.visibleReason or "UNKNOWN") .. ":" .. tostring(d.inside)
     end
    end
    local p=a.cooldownProbe
    if p then
     for _,field in ipairs({"active","isZero","activeReason","objectReason","zeroReason","totalReason","remainingReason"}) do
      parts[#parts+1]="probe:" .. field .. "=" .. tostring(p[field])
     end
    end
   end
  end
  for _,key in ipairs({"arcane_power","presence_of_mind","pyroblast","improved_scorch"}) do
   local t=state.talents[key]; parts[#parts+1]=t and t.status or "UNKNOWN"; parts[#parts+1]=t and t.rank or "UNKNOWN"
  end
 end
 local fingerprint=table.concat(parts,"|")
 local recorded={reason=reason,rule=candidate and candidate.rule,action=candidate and candidate.action,
  spellID=candidate and candidate.spellID,rules=trace,build=state and state.buildSignature or {},fingerprint=fingerprint}
 e[field]=recorded
 local changed=not old or old.fingerprint~=fingerprint or old.rule~=recorded.rule or old.spellID~=recorded.spellID
 if changed then
  e:Log("observed",candidate and "APL_SELECTED" or "APL_NO_CANDIDATE",candidate and candidate.spellID)
  local row=e.db.diagnostics[#e.db.diagnostics]
  row.apl={reason=reason,rule=recorded.rule,action=recorded.action,build=recorded.build,rules=trace}
  if state then
   row.apl.gcd=state.gcd and state.gcd.ready
   row.apl.inCombat=state.combat.in_combat
   row.apl.moving=state.moving
   row.apl.healthProbe=state.healthProbe
   row.apl.visibleCount=state.enemy_count
   row.apl.manaPercent,row.apl.distance=state.manaPercent,state.distance
   row.apl.manaReason,row.apl.distanceReason=state.manaReason,state.distanceReason
   row.apl.distanceLow,row.apl.distanceHigh=state.distanceLow,state.distanceHigh
   row.apl.actions={}; row.apl.talents={}
   for key,action in pairs(state.actions) do
    row.apl.actions[key]={spellID=action.spellID,known=action.known,usable=action.usable,power_ok=action.power_ok,in_range=action.in_range,loss_control_clear=action.loss_control_clear,lossControlReason=action.lossControlReason,ready=action.ready,active=action.active,cdmActive=action.cdmActive,cdmReason=action.cdmReason,cooldownReason=action.cooldownReason,cdmScanReason=action.cdmScanReason,cdmSkippedFrames=action.cdmSkippedFrames}
    row.apl.actions[key].cooldownProbe=action.cooldownProbe
    row.apl.actions[key].conditionObservations=action.conditionObservations
   end
   for _,key in ipairs({"arcane_power","presence_of_mind","pyroblast","improved_scorch"}) do
    local t=state.talents[key]; if t then row.apl.talents[key]={status=t.status,known=t.known,rank=t.rank,maxRank=t.maxRank} end
   end
  end
 end
end
function T.Clean(raw)
 local S=TEF.Safety
 local reason=S.Field(raw,"reason","string")
 if not reason or #reason>80 or not reason:match("^[A-Z_]+$") then return nil end
 local out={reason=reason,build={},rules={},actions={},talents={},inCombat=S.Field(raw,"inCombat","boolean"),gcd=S.Field(raw,"gcd","boolean")}
 local sampledAt=S.Field(raw,"sampledAt","number"); if sampledAt and sampledAt>=0 then out.sampledAt=sampledAt end
 local block=S.Field(raw,"policyBlock","table")
 if block then
  local si=S.Field(block,"strategyIndex","number"); local ci=S.Field(block,"conditionIndex","number")
  local kind=S.Field(block,"kind","string")
  if si and ci and si>=1 and si<=8 and si%1==0 and ci>=1 and ci<=8 and ci%1==0 and kind and #kind<=24 and kind:match("^[A-Za-z]+$") then
   out.policyBlock={strategyIndex=si,conditionIndex=ci,kind=kind,spellID=S.ID(S.Field(block,"spellID","number"))}
   local why=S.Field(block,"cdmReason","string"); if why and #why<=80 and why:match("^[A-Z_]+$") then out.policyBlock.cdmReason=why end
  end
 end
 out.moving=S.Field(raw,"moving","boolean")
 local health=S.Field(raw,"healthProbe","table")
 if health then
  local p={}; local value=S.Field(health,"value","number")
  if value and value>=0 and value<=100 then p.value=value end
  local why=S.Field(health,"reason","string"); if why and #why<=80 and why:match("^[A-Z_]+$") then p.reason=why end
  out.healthProbe=p
 end
 local count=S.Field(raw,"visibleCount","number")
 if count and count>=0 and count<=40 and count%1==0 then out.visibleCount=count end
 for _,spec in ipairs({{"manaPercent",100},{"distance",1000000},{"distanceLow",2000},{"distanceHigh",2000}}) do
  local value=S.Field(raw,spec[1],"number"); if value and value>=0 and value<=spec[2] then out[spec[1]]=value end
 end
 for _,field in ipairs({"manaReason","distanceReason"}) do
  local value=S.Field(raw,field,"string"); if value and #value<=80 and value:match("^[A-Z_]+$") then out[field]=value end
 end
 local rule=S.Field(raw,"rule","string"); local action=S.Field(raw,"action","string")
 if rule and #rule<=80 and rule:match("^[A-Za-z_:%d]+$") then out.rule=rule end
 if action and (TEF.APL.Abilities[action] or action:match("^custom_%d+$")) then out.action=action end
 local build=S.Field(raw,"build","table")
 for _,key in ipairs({"ARCANE","FIRE","FROST"}) do
  local n=build and S.Field(build,key,"number"); if n and n>=0 and n<=100 and n%1==0 then out.build[key]=n end
 end
 local rows=S.Field(raw,"rules","table")
 if rows then for i=1,48 do
  local r=S.Field(rows,i,"table"); if not r then break end
  local id=S.Field(r,"rule","string"); local value=S.Field(r,"result","string"); local why=S.Field(r,"reason","string")
  if id and #id<=80 and id:match("^[A-Za-z_:%d]+$") and (value=="TRUE" or value=="FALSE" or value=="UNKNOWN" or value=="BLOCKED" or value=="DISABLED")
   and why and #why<=100 and why:match("^[A-Za-z_:]+$") then out.rules[#out.rules+1]={rule=id,result=value,reason=why} end
 end end
 local actions=S.Field(raw,"actions","table")
 local keys={}; for _,key in ipairs(TEF.APL.RuleActions) do keys[#keys+1]=key end; for i=1,16 do keys[#keys+1]="custom_" .. i end
 for _,key in ipairs(keys) do
  local r=actions and S.Field(actions,key,"table")
  if r then
   local a={spellID=S.ID(S.Field(r,"spellID","number"))}
   for _,field in ipairs({"known","usable","power_ok","in_range","loss_control_clear","ready","active","cdmActive"}) do a[field]=S.Field(r,field,"boolean") end
   local loc=S.Field(r,"lossControlReason","string"); if loc and #loc<=80 and loc:match("^[A-Z_]+$") then a.lossControlReason=loc end
   local cooldown=S.Field(r,"cooldownReason","string"); if cooldown and #cooldown<=80 and cooldown:match("^[A-Z_]+$") then a.cooldownReason=cooldown end
   local why=S.Field(r,"cdmReason","string"); if why and #why<=80 and why:match("^[A-Z_]+$") then a.cdmReason=why end
   local scan=S.Field(r,"cdmScanReason","string"); if scan=="CDM_FRAME_ID_UNKNOWN" then a.cdmScanReason=scan end
   local skipped=S.Field(r,"cdmSkippedFrames","number"); if skipped and skipped>=1 and skipped<=160 and skipped%1==0 then a.cdmSkippedFrames=skipped end
   local probe=S.Field(r,"cooldownProbe","table")
   if probe then
    local p={}
    for _,field in ipairs({"active","enabled","publicZero","isZero"}) do p[field]=S.Field(probe,field,"boolean") end
    for _,field in ipairs({"startTime","duration","total","remaining"}) do
     local n=S.Field(probe,field,"number"); if n and n>=0 then p[field]=n end
    end
    for _,field in ipairs({"activeReason","numericReason","startReason","durationReason","enabledReason","objectReason","zeroReason","totalReason","remainingReason"}) do
     local why=S.Field(probe,field,"string"); if why and #why<=80 and why:match("^[A-Z_]+$") then p[field]=why end
    end
    a.cooldownProbe=p
   end
   local observations=S.Field(r,"conditionObservations","table")
   if observations then
    a.conditionObservations={}
    for i=1,16 do
     local raw=S.Field(observations,i,"table"); if not raw then break end
     local kind=S.Field(raw,"kind","string")
     if kind and #kind<=24 and kind:match("^[A-Za-z]+$") then
      local v={kind=kind,spellID=S.ID(S.Field(raw,"spellID","number")),result=S.Field(raw,"result","boolean")}
      for _,field in ipairs({"catalogEntryCount","frameScanCount","catalogMatchCount","frameMatchCount"}) do
       local n=S.Field(raw,field,"number"); if n and n>=0 and n<=256 and n%1==0 then v[field]=n end
      end
      local ids=S.Field(raw,"catalogSpellIDs","table")
      if ids then
       v.catalogSpellIDs={}
       for j=1,16 do local id=S.ID(S.Field(ids,j,"number")); if not id then break end; v.catalogSpellIDs[#v.catalogSpellIDs+1]=id end
      end
      for _,field in ipairs({"strategyIndex","conditionIndex"}) do
       local index=S.Field(raw,field,"number"); if index and index>=1 and index<=8 and index%1==0 then v[field]=index end
      end
      local number=S.Field(raw,"number","number"); if number and number>=0 and number<=255 then v.number=number end
      local reason=S.Field(raw,"reason","string"); if reason and #reason<=80 and reason:match("^[A-Z_]+$") then v.reason=reason end
      local text=S.Field(raw,"text","string"); if text=="enemy" or text=="friendly" or text=="self" or text=="none" or text=="stun" or text=="fear" or text=="confuse" or text=="any" then v.text=text end
      for _,field in ipairs({"probeRadius","lower","upper","unknownCount","identityIndex"}) do
       local number=S.Field(raw,field,"number"); if number and number>=0 and number<=40 then v[field]=number end
      end
      v.probeResult=S.Field(raw,"probeResult","boolean")
      local probeReason=S.Field(raw,"probeReason","string"); if probeReason and #probeReason<=80 and probeReason:match("^[A-Z_]+$") then v.probeReason=probeReason end
      local source=S.Field(raw,"identitySource","string"); if source=="legacy" or source=="native" or source=="unitFrame" or source=="method" then v.identitySource=source end
      local function cleanFields(rawFields)
       local out={}; local fields=S.Public(rawFields,"table"); if not fields then return out end
       for _,field in ipairs({"legacy","native","unitFrame","method"}) do
        local reason=S.Field(fields,field,"string"); if reason and #reason<=80 and reason:match("^[A-Z_]+$") then out[field]=reason end
       end
       return out
      end
      v.fields=cleanFields(S.Field(raw,"fields","table"))
      local details=S.Field(raw,"details","table")
      if details then
       v.details={}
       for j=1,8 do
        local d=S.Field(details,j,"table"); if not d then break end
        local row={inside=S.Field(d,"inside","boolean"),fields=cleanFields(S.Field(d,"fields","table"))}
        for _,field in ipairs({"index","low","high"}) do local number=S.Field(d,field,"number"); if number and number>=0 and number<=40 then row[field]=number end end
        for _,field in ipairs({"identityReason","rangeReason","visibleReason"}) do local reason=S.Field(d,field,"string"); if reason and #reason<=80 and reason:match("^[A-Z_]+$") then row[field]=reason end end
        local source=S.Field(d,"source","string"); if source=="legacy" or source=="native" or source=="unitFrame" or source=="method" then row.source=source end
        local unit=S.Field(d,"unit","string"); if unit and #unit<=32 and (unit=="player" or unit:match("^nameplate%d+$")) then row.unit=unit end
        v.details[#v.details+1]=row
       end
      end
      a.conditionObservations[#a.conditionObservations+1]=v
     end
    end
   end
   out.actions[key]=a
  end
 end
 local talents=S.Field(raw,"talents","table")
 for _,key in ipairs({"arcane_power","presence_of_mind","pyroblast","improved_scorch"}) do
  local r=talents and S.Field(talents,key,"table")
  local status=r and S.Field(r,"status","string")
  if status=="KNOWN" or status=="NOT_KNOWN" or status=="UNKNOWN" then
   local t={status=status,known=S.Field(r,"known","boolean")}
   for _,field in ipairs({"rank","maxRank"}) do
    local v=S.Field(r,field,"number"); if v and v>=0 and v<=10 and v%1==0 then t[field]=v end
   end
   out.talents[key]=t
  end
 end
 return out
end
function T:View(e)
 if e.maintenanceActive then return "增益维护 | " .. (e.aplCandidate and e.aplCandidate.rule or "等待符合条件的增益") end
 local t=e.aplTrace; if not t then return "法师 APL · 等待启动采样" end
 if e.db.apl.template=="custom" then return "优先级推荐 | " .. (t.rule or t.reason) .. "\n从上往下选择首条满足规则；详见优先级推荐页。" end
 local b=t.build or {}
 return "法师 APL（" .. e.db.apl.template .. "） | " .. (t.rule or t.reason) .. "\n天赋：" .. (b.ARCANE or "?") .. "/" .. (b.FIRE or "?") .. "/" .. (b.FROST or "?") .. "（仅诊断）"
end
function T:Waiting(e)
 if e.aplTrace and e.aplTrace.reason=="APL_TEMPLATE_UNRESOLVED" then return "APL策略未解析：请手选模板" end
 local runtime=TEF.Runtime
 if runtime and runtime.e==e and runtime.state=="standby" then return "APL待命：暂无满足条件的规则" end
 local t=e.aplTrace
 if t then for _,r in ipairs(t.rules or {}) do
  if r.reason=="combat:" or r.reason=="custom:combat" then return "APL待命：等待重新评估" end
 end end
 return "APL暂无满足条件的规则"
end
