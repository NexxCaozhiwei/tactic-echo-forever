local _,T,F=...
local C,P=T.APL.Custom,T.APL.PublicConditions
local n=0
local function eq(a,b) assert(a==b,"strategy expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function test(name,fn) fn(); n=n+1 end
local function row(id,conditions) return C.CleanRows({{spellID=id,strategies={{mode="use",conditions=conditions}}}})[1] end
local function snapshot() return {actions={custom_1={}},combat={in_combat=true},moving=false} end

test("new_conditions_clean_roundtrip_secret_and_bounds",function()
 local conditions={{kind="combat",value=true},{kind="targetType",target="enemy"},{kind="learned",spellID=205,value=true},{kind="succeeded",spellID=143,value=false},{kind="cdmStacks",spellID=133,min=2,max=4},{kind="rangedEnemies",spellID=143,min=1,max=3}}
 local r=row(143,conditions); eq(r.invalid,nil); eq(#r.strategies[1].conditions,6)
 eq(C.CleanRows({r})[1].strategies[1].conditions[1].value,true)
 conditions[2].target=F.secret; assert(row(143,conditions).invalid)
 conditions[2].target="enemy"; conditions[5].min=F.secret; assert(row(143,conditions).invalid)
 conditions[5].min=5; assert(row(143,conditions).invalid)
end)

test("combat_target_and_exact_known_false_unknown",function()
 local e=F.runtime(); local oldExists,oldSelf,oldEnemy,oldAssist,oldKnown=UnitExists,UnitIsUnit,UnitCanAttack,UnitCanAssist,C_SpellBook.IsSpellKnown
 local r=row(143,{{kind="combat",value=true},{kind="targetType",target="enemy"},{kind="learned",spellID=205,value=true}})
 UnitExists=function() return true end; UnitIsUnit=function() return false end; UnitCanAttack=function() return true end; UnitCanAssist=function() return false end
 C_SpellBook.IsSpellKnown=function(id) return id==205 end
 local s=snapshot(); C:SampleStrategies(s,{r},e); eq(C:CheckStrategies(s,r,1),true)
 s.combat.in_combat=false; eq(C:CheckStrategies(s,r,1),false); s.combat.in_combat=nil; eq(C:CheckStrategies(s,r,1),nil)
 C_SpellBook.IsSpellKnown=function() return F.secret end; s=snapshot(); C:SampleStrategies(s,{r},e); eq(C:CheckStrategies(s,r,1),nil)
 UnitExists=function() return false end; s=snapshot(); C:SampleStrategies(s,{r},e); eq(s.targetType,"none")
 UnitExists=function() return true end; UnitIsUnit=function() return true end; s=snapshot(); C:SampleStrategies(s,{r},e); eq(s.targetType,"self")
 UnitIsUnit=function() return false end; UnitCanAttack=function() return false end; UnitCanAssist=function() return true end; s=snapshot(); C:SampleStrategies(s,{r},e); eq(s.targetType,"friendly")
 UnitCanAttack=function() return F.secret end; s=snapshot(); C:SampleStrategies(s,{r},e); eq(s.targetType,nil)
 UnitExists,UnitIsUnit,UnitCanAttack,UnitCanAssist,C_SpellBook.IsSpellKnown=oldExists,oldSelf,oldEnemy,oldAssist,oldKnown
end)

test("success_only_exact_accepted_receipt_and_lifecycle",function()
 local e=F.runtime(); assert(C:Save(e,{{spellID=143,strategies={{mode="skip",conditions={{kind="succeeded",value=true}}}}},{spellID=205}},"single","MAGE"))
 T.Runtime:SetIntent(true); eq(e:StrategySucceeded(143),false)
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"no-initiation"); eq(e:StrategySucceeded(143),false)
 F.receipt("UNIT_SPELLCAST_SENT",143,"failed"); F.receipt("UNIT_SPELLCAST_FAILED",143,"failed"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"failed"); eq(e:StrategySucceeded(143),false)
 e:Resume()
 F.receipt("UNIT_SPELLCAST_SENT",143,"exact-good"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"exact-good");
 eq(e:StrategySucceeded(143),true)
 e:Pause(); eq(e:StrategySucceeded(143),true); e:Resume(); eq(e:StrategySucceeded(143),true)
 e:ReplaceRecommendation({{spellID=205,matchIDs={205}}}); eq(e:StrategySucceeded(143),true)
 e:Reset(); eq(e:StrategySucceeded(143),false)
 e.strategySuccessCount=128; e:MarkStrategySuccess(205); eq(e:StrategySucceeded(205),nil)
end)

test("ranged_visible_enemies_public_false_secret_and_duplicate",function()
 local e=F.runtime(); local oldPlate,oldExists,oldEnemy,oldDead,oldRange,oldKnown=C_NamePlate,UnitExists,UnitCanAttack,UnitIsDeadOrGhost,C_Spell.IsSpellInRange,C_SpellBook.IsSpellKnown
 C_NamePlate={GetNamePlates=function() return {{namePlateUnitToken="nameplate1"},{namePlateUnitToken="nameplate2"}} end}
 UnitExists=function() return true end; UnitCanAttack=function() return true end; UnitIsDeadOrGhost=function() return false end
 C_SpellBook.IsSpellKnown=function() return true end
 C_Spell.IsSpellInRange=function(id,unit) return unit=="nameplate1" end
 eq(T.Research:CountVisible(143).value,1)
 C_Spell.IsSpellInRange=function() return F.secret end; eq(T.Research:CountVisible(143).state,"UNKNOWN_RANGE")
 C_Spell.IsSpellInRange=function() return nil end; eq(T.Research:CountVisible(143).state,"UNKNOWN_RANGE")
 C_Spell.IsSpellInRange=function() return false end; eq(T.Research:CountVisible(143).value,0)
 C_NamePlate.GetNamePlates=function() return {{namePlateUnitToken="nameplate1"},{namePlateUnitToken="nameplate1"}} end
 eq(T.Research:CountVisible(143).state,"UNKNOWN_IDENTITY")
 C_NamePlate,UnitExists,UnitCanAttack,UnitIsDeadOrGhost,C_Spell.IsSpellInRange,C_SpellBook.IsSpellKnown=oldPlate,oldExists,oldEnemy,oldDead,oldRange,oldKnown
end)

test("cdm_stacks_exact_public_secret_hidden_missing_conflict",function()
 local saved={}; for _,key in ipairs({"C_CooldownViewer","BuffIconCooldownViewer","BuffBarCooldownViewer"}) do saved[key]={_G[key]} end
 C_CooldownViewer={GetCooldownViewerCategorySet=function(cat) return cat==2 and {10} or {} end,GetCooldownViewerCooldownInfo=function() return {spellID=133} end}
 local data={spellId=133,applications=3}; local shown=true
 local frame={cooldownID=10,isActive=true,IsVisible=function() return shown end,GetAuraDataCached=function() return data end}
 local function pool(frames) return {EnumerateActive=function() local i=0; return function() i=i+1; return frames[i] end end} end
 BuffIconCooldownViewer={itemFramePool=pool({frame})}; BuffBarCooldownViewer={itemFramePool=pool({})}
 local requests={{enabled=true,cdmKind="buff",cdmSpellID=133,cdmStacks=true}}
 eq(P.CDM(requests)["buff:133"].stacks,3)
 data.applications=F.secret; eq(P.CDM(requests)["buff:133"].stacks,nil)
 data.applications=nil; eq(P.CDM(requests)["buff:133"].stacks,nil)
 data.applications=3; shown=false; eq(P.CDM(requests)["buff:133"].stacks,nil)
 shown=true; data.spellId=143; eq(P.CDM(requests)["buff:133"].stacks,nil)
 data.spellId=133
 local other={cooldownID=10,isActive=true,IsVisible=function() return true end,GetAuraDataCached=function() return {spellId=133,applications=4} end}
 BuffIconCooldownViewer.itemFramePool=pool({frame,other}); eq(P.CDM(requests)["buff:133"].stacks,nil)
 BuffIconCooldownViewer.itemFramePool=pool({}); eq(P.CDM(requests)["buff:133"].stacks,nil)
 for key,value in pairs(saved) do _G[key]=value[1] end
end)

test("new_stack_and_count_conditions_unknown_never_authorize",function()
 local r=row(143,{{kind="cdmStacks",spellID=133,min=3,max=4},{kind="rangedEnemies",spellID=205,min=2}})
 local s=snapshot(); s.actions.custom_1.strategyCDM={["buff:133"]={stacks=3}}; s.nearbyEnemies={[10]={state="PUBLIC_BOUNDS",lower=2,upper=2}}
 eq(C:CheckStrategies(s,r,1),true)
 s.actions.custom_1.strategyCDM["buff:133"].stacks=2; eq(C:CheckStrategies(s,r,1),false)
 s.actions.custom_1.strategyCDM["buff:133"].stacks=nil; eq(C:CheckStrategies(s,r,1),nil)
 s.actions.custom_1.strategyCDM["buff:133"].stacks=3; s.nearbyEnemies[10]={state="UNKNOWN_RANGE"}; eq(C:CheckStrategies(s,r,1),nil)
end)

test("self_radius_live_recheck_revokes_transport",function()
 local e=F.runtime(); local oldPlate,oldItem=C_NamePlate,C_Item
 C_NamePlate={GetNamePlates=function() return {{unitToken="nameplate1",IsVisible=function() return true end}} end}
 local inside=true
 C_Item={IsItemInRange=function(id,unit) if id==32321 then return inside end end}
 local r=row(143,{{kind="rangedEnemies",min=1}}); eq(r.strategies[1].conditions[1].kind,"nearbyEnemies")
 assert(C:Save(e,{r},"single","MAGE"))
 T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
 inside=false; eq(T.Dispatch:Packet(),nil)
 C_NamePlate,C_Item=oldPlate,oldItem
end)
test("six_condition_editor_fields_save_roundtrip",function()
 local e=F.runtime()
 local conditions={{kind="combat",value=true},{kind="targetType",target="enemy"},{kind="learned",spellID=205,value=true},{kind="succeeded",spellID=143,value=false},{kind="cdmStacks",spellID=133,min=2,max=4},{kind="rangedEnemies",spellID=143,min=1,max=3}}
 assert(C:Save(e,{row(143,conditions)},"single","MAGE"))
 T.UI:ShowPage("customapl"); T.UI.customSelected=1; T.UI.customFormIndex=nil; T.UI:RefreshCustomAPL()
 eq(#T.UI.strategyInputs,8); eq(T.UI:CommitCustomNumbers(),true)
 T.UI.strategySaveButton.scripts.OnClick()
 eq(#C:Rows(e)[1].strategies[1].conditions,6)
 local clean=T.APL.Trace.Clean({reason="APL_CANDIDATE",actions={custom_1={spellID=143,conditionObservations={{kind="cdmStacks",spellID=133,result=F.secret,number=F.secret,reason="SECRET"}}}}})
 eq(clean.actions.custom_1.conditionObservations[1].number,nil); eq(clean.actions.custom_1.conditionObservations[1].result,nil)
end)

test("native_nameplate_identity_sources_conflict_and_secret",function()
 local old=C_NamePlate; C_NamePlate={}
 local plate={unitToken="nameplate1",GetUnit=function(self) return self.unitToken end}
 local token,why,source=T.Research:NamePlateToken(plate); eq(token,"nameplate1"); eq(source,"native")
 token=T.Research:NamePlateToken({UnitFrame={unit="nameplate2"}}); eq(token,"nameplate2")
 plate.namePlateUnitToken="nameplate2"; eq(select(2,T.Research:NamePlateToken(plate)),"TOKEN_SOURCE_CONFLICT")
 plate.namePlateUnitToken=F.secret; eq(select(2,T.Research:NamePlateToken(plate)),"SECRET")
 eq(select(2,T.Research:NamePlateToken({})),"TOKEN_MISSING")
 plate.namePlateUnitToken=nil
 C_NamePlate.GetNamePlateForUnit=function() return {} end; eq(select(2,T.Research:NamePlateToken(plate)),"TOKEN_MAPPING_CONFLICT")
 C_NamePlate.GetNamePlateForUnit=function() return plate end; eq(T.Research:NamePlateToken(plate),"nameplate1")
 C_NamePlate=old
end)

test("yard_probe_traverses_units_and_retains_possible_unknown",function()
 local e=F.runtime(); local saved={}
 for _,key in ipairs({"C_NamePlate","UnitExists","UnitIsUnit","UnitCanAttack","UnitIsDeadOrGhost","C_Item"}) do saved[key]={_G[key]} end
 local plates={{unitToken="nameplate1",IsVisible=function() return true end},{UnitFrame={unit="nameplate2"},IsVisible=function() return true end},{GetUnit=function() return "nameplate3" end,IsVisible=function() return true end}}
 C_NamePlate={GetNamePlates=function() return plates end,GetNamePlateForUnit=function(unit) return plates[tonumber(unit:match("%d+"))] end}
 UnitExists=function() return true end; UnitIsUnit=function() return false end; UnitCanAttack=function() return true end; UnitIsDeadOrGhost=function() return false end
 local calls=0
 C_Item={IsItemInRange=function(id,unit)
  assert(unit~="target"); calls=calls+1
  if id==32321 then if unit=="nameplate1" then return true elseif unit=="nameplate2" then return false end end
 end}
 local result=T.Research:ProbeVisibleYards(10); eq(result.lower,1); eq(result.upper,2); eq(result.unknown,1)
 assert(calls<=9); eq(result.details[1].unit,"nameplate1")
 local r=row(143,{{kind="nearbyEnemies",radius=10,min=1}}); eq(r.invalid,nil)
 local s=snapshot(); C:SampleStrategies(s,{r},e); eq(C:CheckStrategies(s,r,1),true)
 eq(s.nearbyEnemies[10].lower,1)
 eq(T.Research.CountBoundsMatch(1,2,1,nil),true); eq(T.Research.CountBoundsMatch(1,2,3,nil),false)
 eq(T.Research.CountBoundsMatch(1,2,2,nil),nil); eq(T.Research.CountBoundsMatch(F.secret,2,1,nil),nil); eq(T.Research.CountBoundsMatch(1,2,nil,1),nil)
 C_Item.IsItemInRange=function() return F.secret end
 result=T.Research:ProbeVisibleYards(10); eq(result.lower,0); eq(result.upper,3)
 eq(T.Research:ProbeVisibleYards(F.secret).state,"RADIUS_INVALID")
 local clean=T.APL.Trace.Clean({reason="APL_CANDIDATE",actions={custom_1={spellID=143,conditionObservations={{kind="nearbyEnemies",probeRadius=10,lower=F.secret,upper=3,probeReason="PROBE_ONLY",details={{unit=F.secret,low=F.secret,identityReason="SECRET"}}}}}}})
 local v=clean.actions.custom_1.conditionObservations[1]; eq(v.lower,nil); eq(v.details[1].unit,nil); eq(v.details[1].low,nil)
 for key,value in pairs(saved) do _G[key]=value[1] end
end)

test("yard_probe_bounds_crossing_conflict_and_self_range_rejected",function()
 local old=C_Item; local oldExists,oldSelf,oldDead,oldEnemy=UnitExists,UnitIsUnit,UnitIsDeadOrGhost,UnitCanAttack
 UnitExists=function() return true end; UnitIsUnit=function() return false end; UnitIsDeadOrGhost=function() return false end; UnitCanAttack=function() return true end
 C_Item={IsItemInRange=function(id) if id==34368 then return false elseif id==32321 then return true end end}
 local low,high=P:DistanceBracket("nameplate1",9); eq(low,8); eq(high,10)
 C_Item.IsItemInRange=function(id) if id==34368 then return true elseif id==32321 then return false end end
 low,high=P:DistanceBracket("nameplate1",9); eq(low,nil); eq(high,nil)
 C_Item,UnitExists,UnitIsUnit,UnitIsDeadOrGhost,UnitCanAttack=old,oldExists,oldSelf,oldDead,oldEnemy
 local info,known=C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown
 C_Spell.GetSpellInfo=function() return {maxRange=0} end; C_SpellBook.IsSpellKnown=function() return true end
 eq(T.Research:CountVisible(1449).detailReason,"SPELL_UNIT_RANGE_UNSUPPORTED")
 C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown=info,known
 local r=row(143,{{kind="nearbyEnemies",radius=F.secret,min=1}}); assert(r.invalid)
 r=row(143,{{kind="nearbyEnemies",radius=10,min=1.5}}); assert(r.invalid)
end)

test("self_radius_editor_radius_and_unknown_live_gate",function()
 local e=F.runtime(); local r=row(143,{{kind="nearbyEnemies",radius=9.5,min=1,max=3}})
 assert(C:Save(e,{r},"single","MAGE"))
 T.UI:ShowPage("customapl"); T.UI.customSelected=1; T.UI.customFormIndex=nil; T.UI:RefreshCustomAPL()
 eq(#T.UI.strategyInputs,3); eq(T.UI:CommitCustomNumbers(),true)
 local found=false; for _,entry in ipairs(T.UI.strategyInputs) do if entry.field=="radius" then found=true; entry.box.text="8.5" end end
 assert(found); eq(T.UI:CommitCustomNumbers(),true); T.UI.strategySaveButton.scripts.OnClick()
 eq(C:Rows(e)[1].strategies[1].conditions[1].radius,8.5)
 T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil)
end)

test("self_radius_migration_and_partial_use_skip_truth",function()
 local r=row(1449,{{kind="rangedEnemies",spellID=205,min=1,max=10}})
 local c=r.strategies[1].conditions[1]; eq(c.kind,"nearbyEnemies"); eq(c.radius,10); eq(c.spellID,nil)
 local s=snapshot(); s.nearbyEnemies={[10]={state="PUBLIC_BOUNDS",lower=1,upper=2}}
 eq(C:CheckStrategies(s,r,1),true)
 c.min=2; eq(C:CheckStrategies(s,r,1),nil)
 c.min=3; eq(C:CheckStrategies(s,r,1),false)
 c.min=1; c.max=1; eq(C:CheckStrategies(s,r,1),nil)
 c.max=10; r.strategies[1].mode="skip"; eq(C:CheckStrategies(s,r,1),false)
 c.min=2; eq(C:CheckStrategies(s,r,1),nil)
 s.nearbyEnemies[10]={state="SECRET"}; eq(C:CheckStrategies(s,r,1),nil)
 local old={kind="rangedEnemies",radius=8,min=1}; eq(row(1449,{old}).strategies[1].conditions[1].radius,8)
 old.radius=F.secret; assert(row(1449,{old}).invalid)
end)

return n
