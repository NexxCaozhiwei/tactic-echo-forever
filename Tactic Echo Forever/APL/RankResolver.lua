local _,T=...
local A,S=T.APL,T.Safety
local R={}; A.RankResolver=R
-- Only public, independently learned exact IDs enter this resolver. Static
-- catalogue ordering, numeric ID ordering and macro names are never ranks.
function R:Resolve(key,candidates,override)
 local ids,bound={},{}; local unknownKnown=false
 for id,metadata in pairs(candidates) do
  local known=S.ID(id) and A.State.Boolean("C_SpellBook.IsSpellKnown",id)
  if known==nil then unknownKnown=true end
  if known==true then
   ids[#ids+1]=id
   local b=T.Dispatch and T.Dispatch:ResolveCached(id)
   if b and T.Dispatch:VerifyCurrent(b) then bound[#bound+1]=id end
  end
 end
 table.sort(ids) -- diagnostic order only
 local function result(id,reason)
  return {spellID=id,status=id and "RESOLVED" or "UNKNOWN",reason=reason,candidates=ids,unknownKnown=unknownKnown}
 end
 -- An explicit user selection must be certified as the same learned ability.
 if override then
  for _,id in ipairs(ids) do if id==override then return result(id,"EXACT_ID_OVERRIDE") end end
  return result(nil,"EXACT_ID_NOT_CERTIFIED")
 end
 if #bound==1 then return result(bound[1],"UNIQUE_DIRECT_ACTIONBAR_RANK") end
 if #bound>1 then return result(nil,"RANK_ID_AMBIGUOUS") end
 if unknownKnown then return result(nil,"LEARNED_UNKNOWN_OR_ABSENT") end
 if #ids==1 then return result(ids[1],"PUBLIC_EXACT_LEARNED") end
 local highest,rank,seen=nil,nil,{}
 for _,id in ipairs(ids) do
  local m=candidates[id]
  local n=type(m)=="table" and S.Field(m,"rank","number")
  local family=type(m)=="table" and S.Field(m,"ability","string")
  if not n or n<1 or n%1~=0 or family~=key or seen[n] then return result(nil,"RANK_ID_AMBIGUOUS") end
  seen[n]=true
  if not rank or n>rank then highest,rank=id,n end
 end
 return result(highest,highest and "PUBLIC_HIGHEST_LEARNED_RANK" or "LEARNED_UNKNOWN_OR_ABSENT")
end
