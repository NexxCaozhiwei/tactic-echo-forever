local _,T,F=...
local A=T.APL
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
 eq(#T.UI.strategyInputs,7); eq(T.UI:CommitCustomNumbers(),true)
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
 eq(#T.UI.strategyInputs,2); eq(T.UI:CommitCustomNumbers(),true)
 -- 旧半径保留语义，编辑器不再允许任意输入半径。
 for _,entry in ipairs(T.UI.strategyInputs) do assert(entry.field~="radius") end
 T.UI.strategySaveButton.scripts.OnClick()
 eq(C:Rows(e)[1].strategies[1].conditions[1].radius,9.5)
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

test("control_condition_clean_and_secret",function()
 local r=row(1259718,{{kind="lossOfControl",control="stun",value=true}}); eq(r.invalid,nil)
 eq(C.CleanRows({r})[1].strategies[1].conditions[1].control,"stun")
 r.strategies[1].conditions[1].control=F.secret; assert(C.CleanRows({r})[1].invalid)
 eq(row(1259718,{{kind="lossOfControl",control="invented",value=true}}).invalid,"CUSTOM_STRATEGY_INVALID")
end)
test("control_probe_multiple_types_partial_unknown_and_capacity",function()
 local old=C_LossOfControl
 C_LossOfControl={GetActiveLossOfControlDataCount=function() return 2 end,GetActiveLossOfControlData=function(i) return {locType=i==1 and "STUN_MECHANIC" or "FEAR"} end}
 local p=A.State.ProbeControl(); eq(A.State.ControlMatch(p,"stun"),true); eq(A.State.ControlMatch(p,"fear"),true); eq(A.State.ControlMatch(p,"confuse"),false)
 C_LossOfControl.GetActiveLossOfControlData=function(i) return {locType=i==1 and "CONFUSE" or F.secret} end
 p=A.State.ProbeControl(); eq(A.State.ControlMatch(p,"confuse"),true); eq(A.State.ControlMatch(p,"stun"),nil)
 C_LossOfControl.GetActiveLossOfControlDataCount=function() return 0 end; p=A.State.ProbeControl(); eq(A.State.ControlMatch(p,"any"),false)
 C_LossOfControl.GetActiveLossOfControlDataCount=function() return 17 end; eq(A.State.ControlMatch(A.State.ProbeControl(),"stun"),nil)
 C_LossOfControl=nil; eq(A.State.ControlMatch(A.State.ProbeControl(),"stun"),nil)
 C_LossOfControl=old
end)
test("control_condition_unknown_is_not_absent",function()
 local e=F.runtime(); local old=C_LossOfControl
 local r=row(1259718,{{kind="lossOfControl",control="stun",value=false}})
 C_LossOfControl={GetActiveLossOfControlDataCount=function() return F.secret end}
 local s=snapshot(); C:SampleStrategies(s,{r},e); eq(C:CheckStrategies(s,r,1),nil)
 C_LossOfControl.GetActiveLossOfControlDataCount=function() return 0 end
 s=snapshot(); C:SampleStrategies(s,{r},e); eq(C:CheckStrategies(s,r,1),true)
 C_LossOfControl=old
end)
test("maintenance_control_breaker_prioritizes_and_live_condition_revokes",function()
 local e=F.runtime(); local oldLoc,info,known,action,passive=C_LossOfControl,C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown,GetActionInfo,C_Spell.IsSpellPassive
 C_LossOfControl={GetActiveLossOfControlDataCount=function() return 1 end,GetActiveLossOfControlData=function() return {locType="STUN"} end}
 C_Spell.GetSpellInfo=function(id) return {name=id==1259718 and "生存意志" or "火球术"} end
 C_Spell.IsSpellPassive=function() return false end; C_SpellBook.IsSpellKnown=function() return true end
 GetActionInfo=function() return "spell",1259718 end
 assert(T.Maintenance:Save(e,{{spellID=1259718,strategies={{mode="use",conditions={{kind="lossOfControl",control="stun",value=true}}}}}}))
 T.Maintenance:SetEnabled(e,true); T.Runtime:SetIntent(true); eq(e.maintenanceActive,true); eq(e.aplCandidate.spellID,1259718)
 T.Dispatch:TickContinuous(); assert(T.Dispatch:Packet())
 C_LossOfControl.GetActiveLossOfControlDataCount=function() return 0 end
 eq(T.Dispatch:Packet(),nil)
 C_LossOfControl,C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown,GetActionInfo,C_Spell.IsSpellPassive=oldLoc,info,known,action,passive
end)
test("maintenance_control_breaker_requires_exact_learned_and_own_loc_gate",function()
 local e=F.runtime(); local info,known,passive,loc=C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown,C_Spell.IsSpellPassive,C_Spell.GetSpellLossOfControlCooldownInfo
 C_Spell.GetSpellInfo=function() return {name="生存意志"} end; C_Spell.IsSpellPassive=function() return false end
 C_SpellBook.IsSpellKnown=function() return false end; eq(C:Read(1259718).known,false)
 C_SpellBook.IsSpellKnown=function() return true end
 C_Spell.GetSpellLossOfControlCooldownInfo=function() return {isActive=true} end
 local a=C:Read(1259718); eq(a.target,"self"); eq(a.loss_control_clear,false)
 eq(C:Check({actions={custom_1=a}},C.CleanRows({{spellID=1259718}})[1],1),false)
 C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown,C_Spell.IsSpellPassive,C_Spell.GetSpellLossOfControlCooldownInfo=info,known,passive,loc
end)
test("maintenance_control_editor_default_and_reload",function()
 local e=F.runtime(); local info=C_Spell.GetSpellInfo
 C_Spell.GetSpellInfo=function() return {name="生存意志"} end
 T.UI:ShowPage("maintenance")
 local cursor,clear=GetCursorInfo,ClearCursor; local cleared=0
 GetCursorInfo=function() return "spell",7,"spell",1259718 end
 ClearCursor=function() cleared=cleared+1 end
 eq(T.UI:ReceiveCustomSpell(),true); eq(cleared,1)
 GetCursorInfo,ClearCursor=cursor,clear
 eq(T.Maintenance.ControlBreakers[59752],nil)
 local c=T.UI.customDraft[1].strategies[1].conditions[1]; eq(c.kind,"lossOfControl"); eq(c.control,"stun"); eq(c.value,true)
 T.UI.customSelected=1; T.UI:RefreshStrategyForm()
 T.UI.customSave.scripts.OnClick(); eq(T.Maintenance:Rows(e)[1].spellID,1259718)
 local copy=T.Engine.New(T.Config,e.db); eq(T.Maintenance:Rows(copy)[1].strategies[1].conditions[1].control,"stun")
 local clean=A.Trace.Clean({reason="MAINTENANCE_CANDIDATE",actions={custom_1={spellID=1259718,conditionObservations={{kind="lossOfControl",text="stun",result=true,reason="PUBLIC_CONTROL_TYPES"}}}}})
 eq(clean.actions.custom_1.conditionObservations[1].text,"stun")
 C_Spell.GetSpellInfo=info
end)
test("strategy_replace_apl_preserves_conditions_and_saved_draft",function()
 local e=F.runtime(); local r=row(143,{{kind="learned",spellID=143,value=true},{kind="distance",min=10,max=30}})
 assert(C:Save(e,{r},"single","MAGE")); T.UI:ShowPage("customapl"); T.UI.customSelected=1; T.UI.customFormIndex=nil; T.UI:RefreshCustomAPL()
 T.UI.strategySpellID.text="205"; T.UI.strategyReplaceID.scripts.OnClick(); eq(T.UI.customDraft[1].spellID,205); eq(C:Rows(e)[1].spellID,143)
 local c=T.UI.customDraft[1].strategies[1].conditions; eq(c[1].spellID,143); eq(c[2].max,30)
 T.UI.strategySaveButton.scripts.OnClick(); eq(C:Rows(e)[1].spellID,205)
 local known=C_SpellBook.IsSpellKnown; C_SpellBook.IsSpellKnown=function() return F.secret end
 eq(T.UI:ReplaceStrategySpell(143),false); eq(T.UI.customDraft[1].spellID,205)
 C_SpellBook.IsSpellKnown=known; eq(T.UI:ReplaceStrategySpell(61304),false); eq(T.UI:ReplaceStrategySpell(7268),false)
end)
test("strategy_replace_manual_updates_exact_identity_and_preserves_count",function()
 local e=F.runtime(); assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{{spellID=143,name="火球术",matchIDs={143},repeatCount=3,strategies={{mode="use",conditions={{kind="combat",value=true}}}}}}))
 T.UI.editScene="single"; T.UI:ShowPage("profiles"); T.UI:OpenSequencePolicy(1)
 local cursor,clear=GetCursorInfo,ClearCursor
 GetCursorInfo=function() return "spell",3,"spell",205 end; ClearCursor=function() end
 eq(T.UI:ReceiveStrategySpell(),true)
 local rows=T.UI:DraftRows(); eq(rows[1].spellID,205); eq(rows[1].matchIDs[1],205); eq(rows[1].repeatCount,3); eq(rows[1].strategies[1].conditions[1].kind,"combat")
 T.UI.strategySaveButton.scripts.OnClick(); eq(e.db.profiles.single[1].spellID,205); eq(e.steps[1].matches[143],nil)
 GetCursorInfo,ClearCursor=cursor,clear
end)
test("strategy_replace_maintenance_rejects_damage_and_duplicates",function()
 local e=F.runtime(); local info,known=C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown
 C_Spell.GetSpellInfo=function(id) return {name=id==168 and "霜甲术" or id==7300 and "霜甲术" or "火球术"} end
 C_SpellBook.IsSpellKnown=function() return true end
 assert(T.Maintenance:Save(e,{{spellID=168,strategies={{mode="use",conditions={{kind="combat",value=false}}}}}}))
 T.UI:ShowPage("maintenance"); eq(T.UI:ReplaceStrategySpell(143),false); eq(T.UI:ReplaceStrategySpell(7300),true)
 eq(T.UI.customDraft[1].strategies[1].conditions[1].value,false)
 T.UI.customDraft[2]=C.CleanRows({{spellID=168}})[1]; eq(T.UI:ReplaceStrategySpell(168),false)
 T.UI.strategySaveButton.scripts.OnClick(); eq(T.Maintenance:Rows(e)[1].spellID,7300)
 C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown=info,known
end)
test("highest_rank_uses_public_rank_not_id_or_binding",function()
 local e=F.runtime(); local book,info=C_SpellBook,C_Spell.GetSpellInfo
 C_Spell.GetSpellInfo=function() return {name="火球术"} end
 local rows={{id=143,rank=1},{id=133,rank=3},{id=999,rank=2}}
 C_SpellBook={GetNumSpellBookSkillLines=function() return 1 end,GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0,numSpellBookItems=#rows} end,
  GetSpellBookItemInfo=function(i) local r=rows[i]; return {spellID=r.id,name="火球术",rank=r.rank,itemType=1,isPassive=false} end,IsSpellKnown=function() return true end}
 eq(A.State.HighestLearnedRank(143),133)
 rows[3].rank=3; eq(A.State.HighestLearnedRank(143),nil)
 rows[3].rank=F.secret; eq(A.State.HighestLearnedRank(143),nil)
 C_SpellBook.GetNumSpellBookSkillLines=function() return 17 end; eq(A.State.HighestLearnedRank(143),nil)
 C_SpellBook,C_Spell.GetSpellInfo=book,info
end)
test("highest_rank_text_identity_and_unknown_learning",function()
 local e=F.runtime(); local book,info=C_SpellBook,C_Spell.GetSpellInfo
 C_Spell.GetSpellInfo=function() return {name="火球术"} end
 C_SpellBook={GetNumSpellBookSkillLines=function() return 1 end,GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0,numSpellBookItems=1} end,
  GetSpellBookItemInfo=function() return {spellID=133,itemType=1,isPassive=false} end,GetSpellBookItemName=function() return "火球术","等级 3" end,IsSpellKnown=function() return true end}
 eq(A.State.HighestLearnedRank(143),133)
 C_SpellBook.GetSpellBookItemName=function() return "火球术",F.secret end; eq(A.State.HighestLearnedRank(143),nil)
 C_SpellBook.GetSpellBookItemName=function() return "火球术","Rank 3" end
 C_SpellBook.IsSpellKnown=function() return F.secret end; eq(A.State.HighestLearnedRank(143),nil)
 C_SpellBook.GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0,numSpellBookItems=257} end; eq(A.State.HighestLearnedRank(143),nil)
 C_SpellBook,C_Spell.GetSpellInfo=book,info
end)
test("highest_rank_button_preserves_strategy_and_waits_for_save",function()
 local e=F.runtime(); local r=row(143,{{kind="distance",min=20}}); assert(C:Save(e,{r},"single","MAGE"))
 T.UI:ShowPage("customapl"); T.UI.customSelected=1; T.UI.customFormIndex=nil; T.UI:RefreshCustomAPL()
 local book,info=C_SpellBook,C_Spell.GetSpellInfo
 C_Spell.GetSpellInfo=function() return {name="火球术"} end
 C_SpellBook={GetNumSpellBookSkillLines=function() return 1 end,GetSpellBookSkillLineInfo=function() return {itemIndexOffset=0,numSpellBookItems=1} end,
  GetSpellBookItemInfo=function() return {spellID=133,name="火球术",rank=3,itemType=1,isPassive=false} end,IsSpellKnown=function() return true end}
 T.UI.strategyUpgrade.scripts.OnClick(); eq(T.UI.customDraft[1].spellID,133); eq(C:Rows(e)[1].spellID,143)
 eq(T.UI.customDraft[1].strategies[1].conditions[1].min,20)
 eq(T.UI:UpgradeStrategySpell(),true)
 T.UI.strategySaveButton.scripts.OnClick(); eq(C:Rows(e)[1].spellID,133)
 C_SpellBook,C_Spell.GetSpellInfo=book,info
end)
test("resource_probe_public_and_secret_independent_values",function()
 local e=F.runtime(); local enum,power,maximum=Enum.PowerType,UnitPower,UnitPowerMax
 Enum.PowerType={Rage=1,Energy=3,ComboPoints=4}
 UnitPower=function(_,id) return id==1 and 35 or F.secret end; UnitPowerMax=function() return 100 end
 local p=A.State.ProbePower("Rage"); eq(p.value,35); eq(p.maximum,100); eq(p.reason,"PUBLIC")
 p=A.State.ProbePower("Energy"); eq(p.value,nil); eq(p.reason,"SECRET"); eq(p.maximum,100)
 UnitPowerMax=function() return F.secret end; p=A.State.ProbePower("Rage"); eq(p.value,35); eq(p.maximum,nil); eq(p.maxReason,"SECRET")
 Enum.PowerType,UnitPower,UnitPowerMax=enum,power,maximum
end)
test("resource_probe_paused_sampling_dedup_frequency_and_target_combo",function()
 local e=F.runtime(); T.Runtime:Stop(); e.classToken="ROGUE"
 local enum,power,maximum,combo,time,exists=Enum.PowerType,UnitPower,UnitPowerMax,GetComboPoints,GetTime,UnitExists
 local now,energy=20,70; local calls=0
 Enum.PowerType={Rage=1,Energy=3,ComboPoints=4}; GetTime=function() return now end; UnitExists=function() return true end
 UnitPower=function(_,id) calls=calls+1; return id==3 and energy or 3 end; UnitPowerMax=function(_,id) return id==3 and 100 or 5 end
 GetComboPoints=function() return 3 end
 A.State.SampleResources(e); eq(#e.db.resourceDiagnostics,1); eq(e.db.resourceDiagnostics[1].resources.energy.value,70); eq(e.db.resourceDiagnostics[1].resources.targetComboPoints.value,3)
 now=20.1; A.State.SampleResources(e); eq(calls,2)
 now=20.3; A.State.SampleResources(e); eq(#e.db.resourceDiagnostics,1); eq(e.db.resourceProbeSummary.samples,2)
 energy=20; now=20.6; A.State.SampleResources(e); eq(#e.db.resourceDiagnostics,2)
 UnitExists=function() return F.secret end; now=20.9; A.State.SampleResources(e); eq(e.db.resourceProbeSummary.latest.resources.targetComboPoints.reason,"TARGET_UNKNOWN")
 eq(T.Runtime.intent,false); eq(T.Dispatch:Packet(),nil)
 Enum.PowerType,UnitPower,UnitPowerMax,GetComboPoints,GetTime,UnitExists=enum,power,maximum,combo,time,exists
end)
test("resource_probe_capacity_reload_sanitization_and_no_secret_persistence",function()
 local e=F.runtime(); e.classToken="WARRIOR"
 local enum,power,maximum,time=Enum.PowerType,UnitPower,UnitPowerMax,GetTime
 local now,value=30,0; Enum.PowerType={Rage=1}; GetTime=function() return now end
 UnitPower=function() return value end; UnitPowerMax=function() return 100 end
 for i=1,260 do now=now+.25; value=i; A.State.SampleResources(e) end
 eq(#e.db.resourceDiagnostics,256); eq(e.db.resourceEvicted,4)
 local copy=T.Engine.New(T.Config,e.db); eq(#copy.db.resourceDiagnostics,256); eq(copy.db.resourceEvicted,4); eq(copy.db.resourceProbeSummary,nil)
 local clean=A.State.CleanResourceProbe({class="WARRIOR",resources={rage={value=F.secret,reason="SECRET",maximum=100,maxReason="PUBLIC"}}})
 eq(clean.resources.rage.value,nil); eq(clean.resources.rage.reason,"SECRET")
 Enum.PowerType,UnitPower,UnitPowerMax,GetTime=enum,power,maximum,time
end)
test("resource_probe_api_failure_unknown_enum_and_reentry",function()
 local e=F.runtime(); local enum,power,maximum,time=Enum.PowerType,UnitPower,UnitPowerMax,GetTime
 Enum.PowerType={Rage=F.secret}; eq(A.State.ProbePower("Rage").reason,"SECRET")
 Enum.PowerType={Rage=1}; UnitPower=function() error("PRIVATE_ERROR") end; UnitPowerMax=function() return nil end
 local p=A.State.ProbePower("Rage"); eq(p.reason,"CALL_FAILED"); eq(p.maxReason,"NO_DATA")
 e.classToken="WARRIOR"; GetTime=function() return 50 end; UnitPower=function() e:Reset(); return 0 end
 A.State.SampleResources(e); eq(#e.db.resourceDiagnostics,0)
 Enum.PowerType,UnitPower,UnitPowerMax,GetTime=enum,power,maximum,time
end)
test("combo_condition_bounds_class_gate_and_unknown",function()
 local e=F.runtime(); local enum,power,maximum=Enum.PowerType,UnitPower,UnitPowerMax
 Enum.PowerType={ComboPoints=4}; UnitPower=function() return 5 end; UnitPowerMax=function() return F.secret end
 e.classToken="ROGUE"; local r=row(143,{{kind="comboPoints",min=5,max=5}}); eq(r.invalid,nil)
 local s=snapshot(); C:SampleStrategies(s,{r},e); eq(C:CheckStrategies(s,r,1),true)
 UnitPower=function() return 4 end; s=snapshot(); C:SampleStrategies(s,{r},e); eq(C:CheckStrategies(s,r,1),false)
 UnitPower=function() return F.secret end; s=snapshot(); C:SampleStrategies(s,{r},e); eq(C:CheckStrategies(s,r,1),nil)
 e.classToken="MAGE"; UnitPower=function() error("OTHER_CLASS_MUST_NOT_READ") end
 s=snapshot(); C:SampleStrategies(s,{r},e); eq(C:CheckStrategies(s,r,1),nil)
 r.strategies[1].mode="skip"; eq(C:CheckStrategies(s,r,1),nil)
 eq(row(143,{{kind="comboPoints",min=11}}).invalid,"CUSTOM_STRATEGY_INVALID")
 Enum.PowerType,UnitPower,UnitPowerMax=enum,power,maximum
end)
test("combo_condition_live_recheck_revokes_and_logs",function()
 local e=F.runtime(); e.classToken="ROGUE"
 local enum,power,maximum=Enum.PowerType,UnitPower,UnitPowerMax
 local points=5; Enum.PowerType={ComboPoints=4}; UnitPower=function() return points end; UnitPowerMax=function() return 5 end
 assert(C:Save(e,{row(143,{{kind="comboPoints",min=5}})},"single","ROGUE")); assert(T.Recommendation:SetSource(e,"apl","single"))
 T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch:Packet())
 points=1; eq(T.Dispatch:Packet(),nil)
 local clean=A.Trace.Clean({reason="APL_CANDIDATE",actions={custom_1={spellID=143,conditionObservations={{kind="comboPoints",number=5,reason="PUBLIC",result=true}}}}})
 eq(clean.actions.custom_1.conditionObservations[1].number,5)
 Enum.PowerType,UnitPower,UnitPowerMax=enum,power,maximum
end)
test("combo_menu_only_rogue_and_editor_save_roundtrip",function()
 local e=F.runtime(); e.classToken="ROGUE"; assert(C:Save(e,{row(143,{{kind="usable",value=true}})},"single","ROGUE"))
 T.UI:ShowPage("customapl"); T.UI:RefreshStrategyKinds(); eq(T.UI.strategyKindButtons.comboPoints.shown,true)
 T.UI.strategyKindTarget=T.UI.customDraft[1].strategies[1].conditions[1]
 T.UI.strategyKindButtons.comboPoints.scripts.OnClick(); eq(T.UI.strategyKindTarget.kind,"comboPoints"); eq(T.UI.strategyKindTarget.min,5)
 T.UI.strategySaveButton.scripts.OnClick(); eq(C:Rows(e)[1].strategies[1].conditions[1].kind,"comboPoints")
 for _,class in ipairs({"MAGE","WARRIOR","PALADIN","DRUID","HUNTER","PRIEST","WARLOCK","SHAMAN","MONK","DEATHKNIGHT","DEMONHUNTER","EVOKER"}) do
  e.classToken=class; T.UI:RefreshStrategyKinds(); eq(T.UI.strategyKindButtons.comboPoints.shown,false)
 end
end)
return n
