local _,T=...
local S,P,C=T.Safety,T.Profiles,T.APL.Custom
local X={MaxPayload=4*1024*1024,MaxCode=6*1024*1024,MaxNodes=600000}
T.PlanShare=X
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function fail(text) error(text,0) end
local function checksum(text)
 local a,b=1,0
 for i=1,#text do a=(a+text:byte(i))%65521; b=(b+a)%65521 end
 return string.format("%08x",b*65536+a)
end
local function pack64(text)
 local out={}
 for i=1,#text,3 do
  local a,b,c=text:byte(i,i+2); local n=a*65536+(b or 0)*256+(c or 0)
  out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)
   ..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)
   ..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1) or "=")
   ..(c and alphabet:sub(n%64+1,n%64+1) or "=")
 end
 return table.concat(out)
end
local function unpack64(text)
 if #text%4~=0 or text:find("[^A-Za-z0-9+/=]") then fail("分享码编码损坏。") end
 local values={}; for i=1,64 do values[alphabet:sub(i,i)]=i-1 end
 local out={}
 for i=1,#text,4 do
  local a,b,c,d=text:sub(i,i),text:sub(i+1,i+1),text:sub(i+2,i+2),text:sub(i+3,i+3)
  if values[a]==nil or values[b]==nil or (c=="=" and d~="=") or ((c=="=" or d=="=") and i+3~=#text)
   or (c~="=" and values[c]==nil) or (d~="=" and values[d]==nil) then fail("分享码编码损坏。") end
  local n=values[a]*262144+values[b]*4096+(values[c] or 0)*64+(values[d] or 0)
  out[#out+1]=string.char(math.floor(n/65536))
  if c~="=" then out[#out+1]=string.char(math.floor(n/256)%256) end
  if d~="=" then out[#out+1]=string.char(n%256) end
 end
 local payload=table.concat(out)
 if #payload>X.MaxPayload or pack64(payload)~=text then fail("分享码编码或长度无效。") end
 return payload
end
-- 长度前缀的纯数据格式；不接受代码、对象或可执行表达式。
function X:Serialize(value)
 local out,seen,nodes,bytes={}, {},0,0
 local function emit(text)
  bytes=bytes+#text; if bytes>X.MaxPayload then fail("方案内容过大。") end
  out[#out+1]=text
 end
 local function write(v,depth)
  nodes=nodes+1; if nodes>X.MaxNodes or depth>20 then fail("方案结构超过上限。") end
  local kind=type(v)
  if kind=="boolean" then emit(v and "t" or "f")
  elseif kind=="number" then
   if v~=v or math.abs(v)>1e12 then fail("方案含无效数值。") end
   emit("n"..string.format("%.17g",v)..":")
  elseif kind=="string" then
   if #v>2048 then fail("方案文本字段过长。") end
   emit("s"..#v..":"..v)
  elseif kind=="table" then
   if getmetatable(v) or seen[v] then fail("方案含循环或对象。") end
   seen[v]=true; local keys={}
   for k in pairs(v) do
    if type(k)~="string" and (type(k)~="number" or k<1 or k%1~=0) then fail("方案字段无效。") end
    keys[#keys+1]=k; if #keys>64 then fail("方案字段过多。") end
   end
   table.sort(keys,function(a,b) if type(a)~=type(b) then return type(a)<type(b) end; return a<b end)
   emit("m"..#keys..":")
   for _,k in ipairs(keys) do write(k,depth+1); write(v[k],depth+1) end
   seen[v]=nil
  else fail("方案含不支持的数据。") end
 end
 write(value,0); local text=table.concat(out)
 if #text>self.MaxPayload then fail("方案内容过大。") end
 return text
end
function X:Deserialize(text)
 if #text>self.MaxPayload then fail("方案内容过大。") end
 local at,nodes=1,0
 local function size(limit)
  local stop=text:find(":",at,true)
  if not stop or stop-at>7 then fail("分享码结构损坏。") end
  local token=text:sub(at,stop-1)
  if not token:match("^%d+$") then fail("分享码长度无效。") end
  local n=tonumber(token); if n>limit then fail("分享码结构超过上限。") end
  at=stop+1; return n
 end
 local read
 read=function(depth)
  nodes=nodes+1; if nodes>self.MaxNodes or depth>20 then fail("方案结构超过上限。") end
  local tag=text:sub(at,at); at=at+1
  if tag=="t" then return true elseif tag=="f" then return false
  elseif tag=="s" then
   local n=size(2048); if at+n-1>#text then fail("分享码文本不完整。") end
   local v=text:sub(at,at+n-1); at=at+n; return v
  elseif tag=="n" then
   local stop=text:find(":",at,true); if not stop or stop-at>32 then fail("分享码数值无效。") end
   local token=text:sub(at,stop-1)
   if token:find("[^%d%.eE+%-]") then fail("分享码数值无效。") end
   local v=tonumber(token); if not v or v~=v or math.abs(v)>1e12 then fail("分享码数值无效。") end
   at=stop+1; return v
  elseif tag=="m" then
   local count=size(64); local result={}
   for i=1,count do
    local key=read(depth+1)
    if type(key)~="string" and (type(key)~="number" or key<1 or key%1~=0) then fail("分享码字段无效。") end
    if result[key]~=nil then fail("分享码字段重复。") end
    result[key]=read(depth+1)
   end
   return result
  end
  fail("分享码含不支持的数据标记。")
 end
 local value=read(0); if at~=#text+1 then fail("分享码存在多余内容。") end
 return value
end
local function fields(record,allowed,path)
 if type(record)~="table" then fail(path.."格式无效。") end
 for key in pairs(record) do if not allowed[key] then fail(path.."含不支持字段："..tostring(key)) end end
end
local expected={name="string",spellID="number",matchIDs="table",unverified="boolean",repeatCount="number",usagePolicy="string",skipUnavailable="boolean",enabled="boolean",
 strategies="table",targetMode="string",behavior="table",group="table",requireReady="boolean",moving="string",activity="string",experimentalEnemies="boolean",
 enemyMin="number",enemyMax="number",manaOp="string",manaValue="number",distanceOp="string",distanceValue="number",cdmKind="string",cdmState="string",cdmSpellID="number",
 rounds="number",steps="table",maintain="boolean",exit="string"}
local function types(record,path)
 for key,value in pairs(record) do if expected[key] and type(value)~=expected[key] then fail(path..key.."类型无效。") end end
end
local function array(rows,limit,path)
 if type(rows)~="table" or #rows>limit then fail(path.."容量超限。") end
 local n=0; for k in pairs(rows) do if type(k)~="number" or k<1 or k>#rows or k%1~=0 then fail(path.."顺序无效。") end; n=n+1 end
 if n~=#rows then fail(path.."顺序不完整。") end
end
local manual={name=true,spellID=true,matchIDs=true,unverified=true,repeatCount=true,usagePolicy=true,skipUnavailable=true,enabled=true,strategies=true,targetMode=true,behavior=true,group=true}
local apl={spellID=true,enabled=true,strategies=true,targetMode=true,behavior=true,group=true,requireReady=true,moving=true,activity=true,experimentalEnemies=true,
 enemyMin=true,enemyMax=true,manaOp=true,manaValue=true,distanceOp=true,distanceValue=true,cdmKind=true,cdmState=true,cdmSpellID=true}
local groupFields={name=true,rounds=true,steps=true,maintain=true,exit=true}
function X:Clean(raw)
 fields(raw,{schema=true,class=true,source=true,name=true,rows=true},"方案")
 if raw.schema~=1 then fail("不支持此分享格式版本。") end
 if not C:ClassSupported(raw.class) then fail("方案职业无效。") end
 if raw.source~="manual" and raw.source~="apl" then fail("方案类型无效。") end
 local name=P:CleanPlanName(raw.name); if not name then fail("方案名称无效。") end
 array(raw.rows,16,"父列表")
 local function inspect(rows,source,path)
  for i,row in ipairs(rows) do
   local where=path.."第"..i.."项："; fields(row,source=="manual" and manual or apl,where); types(row,where)
   if row.name and (type(row.name)~="string" or row.name:find("[%c|]")) then fail(where.."技能名称无效。") end
   if row.group then
    if path~="父列表" then fail(where.."不支持嵌套技能组。") end
    fields(row.group,groupFields,where.."技能组"); types(row.group,where.."技能组")
    array(row.group.steps,T.SkillGroups.MaxSteps,where.."技能组")
    inspect(row.group.steps,"manual",where.."技能组")
   end
   if row.matchIDs then array(row.matchIDs,16,where.."匹配ID") end
   if row.strategies then
    array(row.strategies,8,where.."策略")
    for j,strategy in ipairs(row.strategies) do
     if type(strategy)~="table" then fail(where.."策略格式无效。") end
     array(strategy.conditions,8,where.."策略"..j.."条件")
    end
   end
  end
 end
 inspect(raw.rows,raw.source,"父列表")
 local rows=raw.source=="manual" and P:Clean(raw.rows) or C.CleanRows(raw.rows)
 if not rows then fail("列表技能、次数或策略无效。") end
 for i,row in ipairs(rows) do if row.invalid then fail("父列表第"..i.."项："..row.invalid) end end
 return {schema=1,class=raw.class,source=raw.source,name=name,rows=rows}
end
function X:Export(class,source,name,rows)
 local ok,result=pcall(function()
  local plan=self:Clean({schema=1,class=class,source=source,name=name,rows=rows})
  local payload=self:Serialize(plan)
  return "TEFPLAN:1:"..checksum(payload)..":"..pack64(payload)
 end)
 return ok and result or nil,not ok and tostring(result) or nil
end
function X:Import(code,class,source)
 local ok,result=pcall(function()
  code=S.Public(code,"string"); if not code or #code>self.MaxCode then fail("分享码为空或过长。") end
  code=code:gsub("%s","")
  local version,hash,body=code:match("^TEFPLAN:(%d+):(%x+):([A-Za-z0-9+/=]+)$")
  if version~="1" then fail("分享码标识或格式版本无效。") end
  local payload=unpack64(body)
  if #hash~=8 or checksum(payload)~=hash:lower() then fail("分享码校验失败，请重新复制完整内容。") end
  local plan=self:Clean(self:Deserialize(payload))
  if plan.class~=class then fail("职业不符：分享方案属于"..plan.class.."。") end
  if plan.source~=source then fail("方案类型不符，请在对应列表页面导入。") end
  return plan
 end)
 return ok and result or nil,not ok and tostring(result) or nil
end
function X:CleanPolicy(raw)
 fields(raw,{schema=true,class=true,strategies=true},"策略包")
 if raw.schema~=1 or not C:ClassSupported(raw.class) then fail("策略包版本或职业无效。") end
 array(raw.strategies,8,"策略")
 for i,strategy in ipairs(raw.strategies) do
  fields(strategy,{mode=true,conditions=true},"策略"..i)
  array(strategy.conditions,8,"策略"..i.."条件")
 end
 local strategies,reason=C.CleanStrategies(raw.strategies)
 if reason then fail("策略无效："..reason) end
 return {schema=1,class=raw.class,strategies=strategies or {}}
end
function X:ExportPolicy(class,strategies)
 local ok,result=pcall(function()
  local payload=self:Serialize(self:CleanPolicy({schema=1,class=class,strategies=strategies or {}}))
  return "TEFPOLICY:1:"..checksum(payload)..":"..pack64(payload)
 end)
 return ok and result or nil,not ok and tostring(result) or nil
end
function X:ImportPolicy(code,class)
 local ok,result=pcall(function()
  code=S.Public(code,"string"); if not code or #code>self.MaxCode then fail("分享码为空或过长。") end
  code=code:gsub("%s","")
  local version,hash,body=code:match("^TEFPOLICY:(%d+):(%x+):([A-Za-z0-9+/=]+)$")
  if version~="1" then fail("请粘贴支持版本的单项策略分享码。") end
  local payload=unpack64(body)
  if #hash~=8 or checksum(payload)~=hash:lower() then fail("分享码校验失败，请重新复制完整内容。") end
  local policy=self:CleanPolicy(self:Deserialize(payload))
  if policy.class~=class then fail("职业不符：策略包属于"..policy.class.."。") end
  return policy
 end)
 return ok and result or nil,not ok and tostring(result) or nil
end
function X:PolicyPreview(policy)
 local lines={policy.class.." · "..#policy.strategies.."条策略；确认后替换当前条目的全部使用／跳过策略。"}
 for i,strategy in ipairs(policy.strategies) do
  local names={}
  for _,condition in ipairs(strategy.conditions) do names[#names+1]=(T.UI.conditionNames[condition.kind] or condition.kind)..(condition.spellID and ("（ID "..condition.spellID.."）") or "") end
  lines[#lines+1]=(strategy.mode=="use" and "使用" or "跳过").."策略"..i.."："..table.concat(names,"、")
 end
 lines[#lines+1]="未指定ID的条件以目标技能为准；显式观察ID保留，CDM需在本机核对。技能ID、次数、顺序、施放类型及触发行为均不改变。"
 return table.concat(lines,"\n")
end
function X:CleanBundle(raw)
 fields(raw,{schema=true,class=true,plans=true,maintenance=true},"方案整包")
 if (raw.schema~=1 and raw.schema~=2) or not C:ClassSupported(raw.class) then fail("整包版本或职业无效。") end
 if raw.schema==1 and raw.maintenance~=nil then fail("旧版整包不支持增益与紧急字段。") end
 fields(raw.plans,{manual=true,apl=true},"整包来源")
 local result={schema=raw.schema,class=raw.class,plans={manual={},apl={}}}
 for _,source in ipairs({"manual","apl"}) do
  fields(raw.plans[source],{single=true,multi=true,third=true},"整包槽位")
  for _,slot in ipairs({"single","multi","third"}) do
   local plan=self:Clean(raw.plans[source][slot])
   if plan.class~=raw.class or plan.source~=source then fail("整包内的职业或来源不一致。") end
   result.plans[source][slot]=plan
  end
 end
 if raw.schema==2 then
  fields(raw.maintenance,{rows=true},"增益与紧急")
  local plan=self:Clean({schema=1,class=raw.class,source="apl",name="增益与紧急",rows=raw.maintenance.rows})
  local seen={}
  for _,row in ipairs(plan.rows) do
   if row.group or seen[row.spellID] then fail("增益与紧急不支持技能组或重复技能ID。") end
   seen[row.spellID]=true
  end
  result.maintenance={rows=plan.rows}
 end
 return result
end
function X:ExportBundle(raw)
 local ok,result=pcall(function()
  local payload=self:Serialize(self:CleanBundle(raw))
  return "TEFBUNDLE:"..raw.schema..":"..checksum(payload)..":"..pack64(payload)
 end)
 return ok and result or nil,not ok and tostring(result) or nil
end
function X:ImportBundle(code,class)
 local ok,result=pcall(function()
  code=S.Public(code,"string"); if not code or #code>self.MaxCode then fail("分享码为空或过长。") end
  code=code:gsub("%s","")
  local version,hash,body=code:match("^TEFBUNDLE:(%d+):(%x+):([A-Za-z0-9+/=]+)$")
  if version~="1" and version~="2" then fail("请粘贴支持版本的全部方案整包码。") end
  local payload=unpack64(body)
  if #hash~=8 or checksum(payload)~=hash:lower() then fail("整包校验失败，请重新复制完整内容。") end
  local bundle=self:CleanBundle(self:Deserialize(payload))
  if tostring(bundle.schema)~=version then fail("整包内外格式版本不一致。") end
  if bundle.class~=class then fail("职业不符：方案整包属于"..bundle.class.."。") end
  return bundle
 end)
 return ok and result or nil,not ok and tostring(result) or nil
end
function X:BundlePreview(bundle)
 local lines={bundle.class.." · 全部六套方案（包含各槽当前草稿）"}
 for _,source in ipairs({"manual","apl"}) do for i,slot in ipairs({"single","multi","third"}) do
  local plan=bundle.plans[source][slot]; local groups=0
  for _,row in ipairs(plan.rows) do if row.group then groups=groups+1 end end
  lines[#lines+1]=(source=="manual" and "列表循环" or "优先级推荐").."／方案"..i.."："..plan.name.."，"..#plan.rows.."项，技能组"..groups.."个"
 end end
 lines[#lines+1]=bundle.maintenance and ("增益与紧急："..#bundle.maintenance.rows.."项，将一起导入；本机启用状态保留。") or "旧版整包未包含增益与紧急，本机维护列表保持原样。"
 lines[#lines+1]="确认后替换包含的草稿和名称，再点击保存全部导入。运行来源、方案及维护启用状态、按键、HUD及派发设置保留。各技能与CDM仍需在本机核对。"
 return table.concat(lines,"\n")
end
function X:Preview(plan)
 local groups,skills,strategies,warnings=0,0,0,{}
 local warned,checks={},{}
 local function warn(id,text,kind) local key=id..(kind or text); if not warned[key] then warned[key]=true; if #warnings<12 then warnings[#warnings+1]=text.."（ID "..id.."）" end end end
 local function scan(rows,path)
  for i,row in ipairs(rows) do
   local where=path..i.."："
   strategies=strategies+#(row.strategies or {})
   for _,strategy in ipairs(row.strategies or {}) do for _,condition in ipairs(strategy.conditions) do
    if condition.kind=="cdmBuff" or condition.kind=="cdmCooldown" then warn(condition.spellID or row.spellID,where.."CDM观察需在本机核对",condition.kind) end
   end end
   if row.group then groups=groups+1; scan(row.group.steps,where..row.group.name.."／")
   else
    skills=skills+1
    local check=checks[row.spellID]
    if not check then check={known=T.APL.State.Boolean("C_SpellBook.IsSpellKnown",row.spellID)==true,bound=T.Dispatch:Resolve(row.spellID)~=nil}; checks[row.spellID]=check end
    if not check.known then warn(row.spellID,where.."未确认已学此精确等级","learned") end
    if not check.bound then warn(row.spellID,where.."未找到经核对的动作条按键","binding") end
   end
  end
 end
 scan(plan.rows,"条目")
 return plan.name.." · "..plan.class.." · "..(plan.source=="manual" and "列表循环" or "优先级推荐").."\n父列表"..#plan.rows.."项，技能组"..groups.."个，技能"..skills.."步，策略"..strategies.."条。\n"
  ..(#warnings>0 and ("本机检查提示（最多12项）：\n"..table.concat(warnings,"\n")) or "未发现已学和按键警告；实际派发仍需实时门禁确认。")
end
