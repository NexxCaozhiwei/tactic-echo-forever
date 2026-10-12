local _,T=...
local B={}; T.APL.BuildSelector=B
local features={arcane={"arcane_power","presence_of_mind"},fire={"pyroblast","combustion"},frost={"cold_snap","ice_barrier","fingers_of_frost"}}
function B:Select(talents,actions)
 local choices,reasons={},{}; local complete=true
 for _,template in ipairs({"arcane","fire","frost"}) do
  local matched=false
  for _,key in ipairs(features[template]) do
   local t=talents[key]
   if not t or t.known==nil then complete=false; reasons[#reasons+1]="UNKNOWN:" .. key
   elseif t.known==true and t.rank and t.rank>0 then
    if actions[key] and actions[key].known~=true then complete=false end
    matched=true; reasons[#reasons+1]=key .. " rank=" .. t.rank
   end
  end
  if matched then choices[#choices+1]=template end
 end
 local template=#choices==1 and complete and choices[1] or "unresolved"
 return {template=template,confidence=template~="unresolved" and "PUBLIC_KEY_TALENTS" or #choices>1 and "AMBIGUOUS" or "UNKNOWN",reasons=reasons}
end
