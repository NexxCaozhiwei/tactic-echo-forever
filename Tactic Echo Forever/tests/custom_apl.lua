local _,T,F=...
local A,C=T.APL,T.APL.Custom
local n=0
local function eq(a,b) assert(a==b,"custom expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function test(name,fn) fn(); n=n+1 end
local function row(id) return {spellID=id,enabled=true,moving="any",activity="any",experimentalEnemies=false} end
local function state(rows)
 local s={combat={in_combat=true},actions={},moving=false,scene="single",enemy_count=3}
 for i,r in ipairs(rows) do s.actions["custom_" .. i]={spellID=r.spellID,name="技能",known=true,usable=true,power_ok=true,in_range=true,ready=true,active=false} end
 return s
end
local function evaluate(rows,s) return C:Evaluate(s or state(rows),{custom={MAGE={single=rows}}},"MAGE") end
test("first_eligible_in_manual_order",function()
 local rows={row(2136),row(143)}; rows[1].moving="yes"
 local s=state(rows); eq(evaluate(rows,s).spellID,143); s.moving=true; eq(evaluate(rows,s).spellID,2136)
 rows[1],rows[2]=rows[2],rows[1]; s=state(rows); s.moving=true; eq(evaluate(rows,s).spellID,143)
end)
test("unknown_skips_rule_but_never_authorizes_it",function()
 local rows={row(2136),row(143)}; rows[1].moving="yes"
 local s=state(rows); s.moving=nil; local candidate,_,trace=evaluate(rows,s)
 eq(candidate.spellID,143); eq(trace[1].result,"UNKNOWN")
end)
test("all_other_rules_also_have_visible_results",function()
 local rows={row(143),row(205)}; local candidate,_,trace=evaluate(rows)
 eq(candidate.spellID,143); eq(#trace,2); eq(trace[2].result,"TRUE")
end)
test("mandatory_guards_false_and_unknown",function()
 local rows={row(143)}
 for _,key in ipairs({"known","usable","power_ok","in_range"}) do
  local s=state(rows); s.actions.custom_1[key]=nil; eq(evaluate(rows,s),nil)
  s.actions.custom_1[key]=false; eq(evaluate(rows,s),nil)
 end
end)
test("disabled_never_selected",function() local rows={row(143)}; rows[1].enabled=false; local c,_,trace=evaluate(rows); eq(c,nil); eq(trace[1].result,"DISABLED") end)
test("experimental_count_opt_in_unknown_and_bounds",function()
 local rows={row(143)}; rows[1].enemyMin=3; local s=state(rows)
 eq(evaluate(rows,s),nil); rows[1].experimentalEnemies=true; eq(evaluate(rows,s).spellID,143)
 s.enemy_count=nil; eq(evaluate(rows,s),nil); s.enemy_count=2; eq(evaluate(rows,s),nil)
 rows[1].enemyMax=4; s.enemy_count=5; eq(evaluate(rows,s),nil)
end)
test("activity_is_not_ready",function()
 local rows={row(143)}; rows[1].activity="inactive"; rows[1].requireReady=true; local s=state(rows)
 eq(evaluate(rows,s).spellID,143); s.actions.custom_1.ready=nil; eq(evaluate(rows,s).spellID,143)
 s.actions.custom_1.ready=true; s.actions.custom_1.active=nil; eq(evaluate(rows,s),nil)
end)
test("retired_conditions_removed_on_reload",function()
 local old=row(143); old.requireReady=true; old.manaOp="lt"; old.manaValue=20
 local clean=C.CleanRows({old})[1]
 eq(clean.requireReady,nil); eq(clean.manaOp,nil); eq(clean.manaValue,nil)
 eq(evaluate({clean},state({clean})).spellID,143)
 old.requireReady=F.secret; assert(C.CleanRows({old})[1].invalid)
end)
test("optional_ready_diagnostic_probe_does_not_gate_and_live_recheck_when_enabled",function()
 local e=F.runtime(); local old=C_Spell.GetSpellCooldown; local calls=0
 C_Spell.GetSpellCooldown=function() calls=calls+1; return F.secret end
 local r=row(143); C:Save(e,{r},"single","MAGE"); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
 assert(T.Dispatch.pending); eq(calls,1); assert(T.Dispatch:Packet())
 r.requireReady=true; C:Save(e,{r},"single","MAGE"); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
 assert(T.Dispatch.pending); assert(calls>0); C_Spell.GetSpellCooldown=old
end)
test("background_health_duration_public_secret_failed_and_reload_clean",function()
 local old=C_Spell.GetSpellCooldown; local oldDuration=C_Spell.GetSpellCooldownDuration; local oldHealth=UnitHealthPercent
 C_Spell.GetSpellCooldown=function() return {isActive=false} end
 C_Spell.GetSpellCooldownDuration=function(id) eq(id,143); return {IsZero=function() return true end,GetTotalDuration=function() return 0 end,GetRemainingDuration=function() return 0 end} end
 local p=T.APL.State.ProbeCooldown(143); eq(p.active,false); eq(p.isZero,true); eq(p.total,0); eq(p.objectReason,"PUBLIC")
 UnitHealthPercent=function(unit,predicted) eq(unit,"player"); eq(predicted,true); return .75 end
 eq(T.APL.State.ProbeHealth().value,.75)
 C_Spell.GetSpellCooldownDuration=function() return {IsZero=function() return F.secret end,GetTotalDuration=function() return F.secret end,GetRemainingDuration=function() return F.secret end} end
 p=T.APL.State.ProbeCooldown(143); eq(p.isZero,nil); eq(p.zeroReason,"SECRET"); eq(p.total,nil)
 UnitHealthPercent=function() return F.secret end; local health=T.APL.State.ProbeHealth(); eq(health.value,nil); eq(health.reason,"SECRET")
 local clean=A.Trace.Clean({reason="APL_CANDIDATE",healthProbe=health,actions={custom_1={spellID=143,cooldownProbe=p}}})
 eq(clean.actions.custom_1.cooldownProbe.zeroReason,"SECRET"); eq(clean.healthProbe.reason,"SECRET")
 p.total=F.secret; health.value=F.secret
 clean=A.Trace.Clean({reason="APL_CANDIDATE",healthProbe=health,actions={custom_1={spellID=143,cooldownProbe=p}}})
 eq(clean.actions.custom_1.cooldownProbe.total,nil); eq(clean.healthProbe.value,nil)
 C_Spell.GetSpellCooldownDuration=function() return F.secret end; eq(T.APL.State.ProbeCooldown(143).objectReason,"SECRET")
 C_Spell.GetSpellCooldownDuration=function() error("PRIVATE_ERROR") end; eq(T.APL.State.ProbeCooldown(143).objectReason,"CALL_FAILED")
 C_Spell.GetSpellCooldownDuration=function() return nil end; eq(T.APL.State.ProbeCooldown(143).objectReason,"NO_DATA")
 C_Spell.GetSpellCooldownDuration=function() return {} end; eq(T.APL.State.ProbeCooldown(143).zeroReason,"NO_DATA")
 C_Spell.GetSpellCooldownDuration=function() return {GetTotalDuration=function() return -1 end} end
 eq(T.APL.State.ProbeCooldown(143).totalReason,"UNKNOWN_NUMBER")
 UnitHealthPercent=nil; eq(T.APL.State.ProbeHealth().reason,"UNAVAILABLE")
 C_Spell.GetSpellCooldown, C_Spell.GetSpellCooldownDuration,UnitHealthPercent=old,oldDuration,oldHealth
end)

test("duration_probe_deduplicates_and_never_queries_gcd",function()
 local e=F.runtime(); local old=C_Spell.GetSpellCooldownDuration; local calls=0
 C_Spell.GetSpellCooldownDuration=function(id) assert(id~=61304); calls=calls+1; return nil end
 C:Save(e,{row(143),row(143)},"single","MAGE")
 local sample={actions={}}; C:Sample(e,sample); eq(calls,1)
 eq(sample.actions.custom_1.cooldownProbe,sample.actions.custom_2.cooldownProbe)
 e.db.apl.custom.MAGE.single={C.CleanRows({row(61304)})[1]}
 C:Sample(e,{actions={}}); eq(calls,1)
 C_Spell.GetSpellCooldownDuration=old
end)

test("unsupported_conditions_are_preserved_as_blocked",function()
 for _,field in ipairs({"manaPercent","cdm","distanceYards","gcd","expression"}) do
  local r=row(143); r[field]=30; local rows=C.CleanRows({r}); eq(rows[1].invalid,"CUSTOM_CONDITION_UNSUPPORTED"); eq(evaluate(rows),nil)
 end
end)
test("secret_config_cannot_turn_into_unconditional_rule",function()
 local r=row(143); r.moving=F.secret; local rows=C.CleanRows({r}); assert(rows[1].invalid); eq(evaluate(rows),nil)
end)
test("limit_16_and_invalid_thresholds",function()
 local rows={}; for i=1,17 do rows[i]=row(143) end; eq(C.CleanRows(rows)[1].invalid,"CUSTOM_CAPACITY")
 local r=row(143); r.enemyMin=5; r.enemyMax=2; assert(C.CleanRows({r})[1].invalid)
end)
test("save_reload_class_scene_isolation_no_active_state",function()
 local e=F.runtime(); eq(C:Save(e,{row(143)},"single","MAGE"),true)
 eq(C:Save(e,{row(205)},"multi","MAGE"),true)
 eq(C:Save(e,{row(143)},"single","WARRIOR"),false)
 local copy=T.Engine.New(T.Config,e.db)
 eq(C:Rows(copy,"single")[1].spellID,143); eq(C:Rows(copy,"multi")[1].spellID,205); eq(copy.aplCandidate,nil); eq(copy.running,false)
end)
test("save_invalid_keeps_previous_config",function()
 local e=F.runtime(); C:Save(e,{row(143)},"single","MAGE")
 local r=row(205); r.cdm=133; eq(C:Save(e,{r},"single","MAGE"),false); eq(C:Rows(e)[1].spellID,143)
end)
test("same_existing_transport_success_re_evaluates",function()
 local e=F.runtime(); C:Save(e,{row(143),row(205)},"single","MAGE")
 T.Runtime:SetIntent(true); eq(e.aplCandidate.spellID,143); T.Dispatch:TickContinuous(); assert(T.Dispatch:Packet())
 F.receipt("UNIT_SPELLCAST_SENT",143,"custom-one"); F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"custom-one")
 eq(e.receiptSerial,1); eq(e.completed,false); T.Runtime:Reconcile(); eq(e.aplCandidate.spellID,143)
end)
test("live_recheck_revokes_old_moving_candidate",function()
 local e=F.runtime(); local r=row(143); r.moving="yes"; C:Save(e,{r},"single","MAGE")
 IsPlayerMoving=function() return true end; T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
 IsPlayerMoving=function() return false end; eq(T.Dispatch:Packet(),nil); eq(T.Dispatch.pending,nil)
end)
test("custom_static_api_reentry_discards_whole_sample",function()
 local e=F.runtime(); C:Save(e,{row(143)},"single","MAGE")
 C_Spell.GetSpellInfo=function() e:Reset(); return {name="火球术"} end
 T.Runtime:SetIntent(true); eq(e.aplCandidate,nil); eq(T.Dispatch.pending,nil)
end)
test("unknown_metadata_and_api_missing_do_not_guess",function()
 local e=F.runtime(); C:Save(e,{row(143)},"single","MAGE")
 C_Spell.GetSpellInfo=function() return {name=F.secret} end; T.Runtime:SetIntent(true); eq(e.aplCandidate,nil)
end)
test("custom_diagnostics_reload_whitelist",function()
 local raw={reason="APL_CANDIDATE",action="custom_1",rule="custom:1",moving=false,visibleCount=3,actions={custom_1={spellID=143,known=true,active=false}}}
 local clean=A.Trace.Clean(raw); eq(clean.action,"custom_1"); eq(clean.actions.custom_1.active,false); eq(clean.moving,false); eq(clean.visibleCount,3)
 raw.moving=F.secret; raw.visibleCount=F.secret; clean=A.Trace.Clean(raw); eq(clean.moving,nil); eq(clean.visibleCount,nil)
end)
test("standby_custom_preview_and_zero_transport",function()
 local e=F.runtime(); C:Save(e,{row(143)},"single","MAGE"); e.db.dispatch.mode="auto"
 InCombatLockdown=function() return false end
 T.Runtime:SetIntent(true); eq(T.Runtime.state,"standby"); eq(e.aplCandidate.spellID,143); eq(e.running,false)
 T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil); eq(T.Dispatch:Packet(),nil)
 T.Transport:Paint(); eq(T.Transport.fields[4],2); eq(T.Transport.fields[15],0); eq(T.Transport.fields[16],0)
 eq(T.Dispatch:Request(),false); eq(T.APL:Allowed(e,143),false)
end)
test("standby_target_range_changes_update_and_clear_preview",function()
 local e=F.runtime(); C:Save(e,{row(143)},"single","MAGE"); e.db.dispatch.mode="auto"
 InCombatLockdown=function() return false end; T.Runtime:SetIntent(true); eq(e.aplCandidate.spellID,143)
 C_Spell.IsSpellInRange=function() return nil end; local refreshedAt=GetTime()+.06; GetTime=function() return refreshedAt end; A:Invalidate(); T.Runtime:Reconcile(); eq(e.aplCandidate,nil)
 eq(A.Trace:Waiting(e),"APL待命：暂无满足条件的规则"); eq(T.Dispatch:Packet(),nil)
 C_Spell.IsSpellInRange=function() return true end; local refreshedAt=GetTime()+.06; GetTime=function() return refreshedAt end; A:Invalidate(); T.Runtime:Reconcile(); eq(e.aplCandidate.spellID,143)
 eq(T.Runtime.state,"standby"); eq(T.Dispatch.pending,nil)
end)
test("standby_self_conditions_preview_without_target",function()
 local e=F.runtime(); C:Save(e,{row(12042)},"single","MAGE"); e.db.dispatch.mode="auto"
 local info=C_Spell.GetSpellInfo; C_Spell.GetSpellInfo=function(id) return id==12042 and {name="奥术强化"} or info(id) end
 local known=C_SpellBook.IsSpellKnown; C_SpellBook.IsSpellKnown=function(id) return id==12042 or known(id) end
 InCombatLockdown=function() return false end; C_Spell.IsSpellInRange=function() return nil end
 UnitExists=function(unit) return unit=="player" end
 T.Runtime:SetIntent(true); eq(e.aplCandidate.spellID,12042); eq(e.aplCandidate.target,"self")
 eq(T.Runtime.state,"standby"); eq(T.Dispatch:Packet(),nil)
 C_Spell.GetSpellInfo=info
 C_SpellBook.IsSpellKnown=known
end)
test("standby_moving_priority_changes_and_combat_revalidates",function()
 local e=F.runtime(); local first=row(143); first.moving="no"; local second=row(205); second.moving="yes"
 C:Save(e,{first,second},"single","MAGE"); e.db.dispatch.mode="auto"; InCombatLockdown=function() return false end
 IsPlayerMoving=function() return false end; T.Runtime:SetIntent(true); eq(e.aplCandidate.spellID,143)
 IsPlayerMoving=function() return true end; local refreshedAt=GetTime()+.06; GetTime=function() return refreshedAt end; A:Invalidate(); T.Runtime:Reconcile(); eq(e.aplCandidate.spellID,205); eq(T.Dispatch.pending,nil)
 -- Enter combat after a preview dependency changes: the old visible action
 -- cannot create a request before the shared snapshot is freshly evaluated.
 InCombatLockdown=function() return true end; C_Spell.IsSpellUsable=function() return false,true end
 local refreshedAt=GetTime()+.06; GetTime=function() return refreshedAt end; A:Invalidate(); T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); eq(e.aplCandidate,nil); eq(T.Dispatch.pending,nil)
 C_Spell.IsSpellUsable=function() return true,false end; IsPlayerMoving=function() return false end
 local refreshedAt=GetTime()+.06; GetTime=function() return refreshedAt end; A:Invalidate(); T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); eq(e.aplCandidate.spellID,143); assert(T.Dispatch:Packet())
 local calls=0; InCombatLockdown=function() calls=calls+1; return calls==1 end
 eq(A:Allowed(e,143),false); eq(T.Dispatch:Packet(),nil)
end)
test("combat_unknown_still_previews_but_never_dispatches",function()
 local e=F.runtime(); C:Save(e,{row(143)},"single","MAGE"); InCombatLockdown=function() return F.secret end
 T.Runtime:SetIntent(true); eq(e.aplCandidate.spellID,143); eq(T.Runtime.state,"blocked")
 eq(T.APL:Allowed(e,143),false); T.Dispatch:TickContinuous(); eq(T.Dispatch.pending,nil); eq(T.Dispatch:Packet(),nil)
end)
test("retired_resource_threshold_does_not_survive_save",function()
 local e=F.runtime(); local r=row(143); r.manaOp,r.manaValue="lt",20
 assert(C:Save(e,{r},"single","MAGE")); eq(C:Rows(e)[1].manaOp,nil)
end)
test("manual_apl_mode_cannot_dispatch_standby_preview",function()
 local e=F.runtime(); C:Save(e,{row(143)},"single","MAGE"); e.db.dispatch.mode="manual"; InCombatLockdown=function() return false end
 T.Runtime:SetIntent(true); eq(e.aplCandidate.spellID,143); eq(T.Runtime.state,"blocked")
 eq(T.APL:Allowed(e,143),false); eq(T.Dispatch:Request(),false); eq(T.Dispatch:Packet(),nil)
end)
test("editor_order_delete_draft_and_scene_keep_saved",function()
 local e=F.runtime(); C:Save(e,{row(143),row(205)},"single","MAGE")
 T.UI:ShowPage("customapl"); eq(#T.UI.customDraft,2)
 T.UI:MoveCustomRule(1,1); eq(T.UI.customDraft[1].spellID,205); eq(C:Rows(e)[1].spellID,143)
 eq(T.UI:AddCustomSpell(2136),true); eq(#T.UI.customDraft,3)
 T.UI.customScene="multi"; T.UI:RefreshCustomAPL(); eq(#T.UI.customDraft,0)
 local cursor,clear=GetCursorInfo,ClearCursor; local cleared=0
 GetCursorInfo=function() return "spell",1,"spell",F.secret end
 ClearCursor=function() cleared=cleared+1 end
 T.UI.customDrop.scripts.OnReceiveDrag(); eq(#T.UI.customDraft,0); eq(cleared,0)
 GetCursorInfo=function() return "spell",1,"spell",205 end
 T.UI.customDrop.scripts.OnReceiveDrag(); eq(#T.UI.customDraft,1); eq(cleared,1)
 local box=T.UI.customNumbers.enemyMin; box.text="2"
 T.UI:RefreshCustomAPL(); eq(box.text,"2") -- periodic UI refresh preserves unsaved text
 T.UI:CustomRow().experimentalEnemies=true
 T.UI.customSave.scripts.OnClick(); eq(C:Rows(e,"multi")[1].enemyMin,2); eq(e.scene,"multi"); eq(T.Runtime.intent,false)
 eq(C:Rows(e,"single")[1].spellID,143)
 box.text="41"; T.UI.customSave.scripts.OnClick(); eq(C:Rows(e,"multi")[1].enemyMin,2)
 GetCursorInfo,ClearCursor=cursor,clear
end)
n=n+assert(loadfile((arg and arg[1] or ".") .. "/tests/public_conditions.lua"))("TEF",T,F)
TEF_CUSTOM_APL_TEST_COUNT=n
return n
