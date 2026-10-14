local _,T,F=...
local A=T.APL; local n=0
local function eq(a,b) assert(a==b,"foundation expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function test(name,fn) fn(); n=n+1; print("PASS " .. name) end
local function strategy() return A.Clean({template="fire",filler="fireball"}) end
local function rule(ready) return {id="foundation",action="fireball",status="KEEP",if_all={},requireReady=ready} end
local function state() return {combat={},actions={fireball={known=true,usable=true,loss_control_clear=true,power_ok=true,in_range=true}},talents={},scene="single"} end
test("apl_normal_spell_does_not_require_cooldown_ready",function() eq(A:RuleAllowed(state(),rule(),strategy()),true) end)
test("apl_rule_can_explicitly_require_ready",function() local s=state(); s.actions.fireball.ready=true; eq(A:RuleAllowed(s,rule(true),strategy()),true) end)
test("apl_unknown_required_ready_fail_closed",function() eq(A:RuleAllowed(state(),rule(true),strategy()),nil) end)
test("apl_secret_cooldown_does_not_block_usable_filler",function()
 local e=F.runtime(); local calls=0; C_Spell.GetSpellCooldown=function() calls=calls+1; return F.secret end
 T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch:Packet()); eq(calls,0)
end)
local function ranks(ids,binding,override)
 local oldKnown=C_SpellBook.IsSpellKnown; local resolve,verify=T.Dispatch.ResolveCached,T.Dispatch.VerifyCurrent
 C_SpellBook.IsSpellKnown=function(id) return ids[id]~=nil end
 T.Dispatch.ResolveCached=function(_,id) return binding[id] and {spellID=id} end
 T.Dispatch.VerifyCurrent=function() return true end
 local result=A.RankResolver:Resolve("fireball",ids,override)
 C_SpellBook.IsSpellKnown=oldKnown; T.Dispatch.ResolveCached,T.Dispatch.VerifyCurrent=resolve,verify
 return result
end
test("rank_resolver_unique_actionbar_rank",function() eq(ranks({[143]=true,[133]=true},{[143]=true}).spellID,143) end)
test("rank_resolver_multiple_rank_ambiguous",function() eq(ranks({[143]=true,[133]=true},{[143]=true,[133]=true}).spellID,nil) end)
test("rank_resolver_public_highest_rank_when_certified",function() eq(ranks({[900]={ability="fireball",rank=1},[100]={ability="fireball",rank=2}},{}).spellID,100) end)
test("rank_resolver_never_uses_max_spell_id",function() eq(ranks({[900]=true,[100]=true},{}).spellID,nil) end)
test("rank_resolver_exact_override",function() eq(ranks({[143]=true,[133]=true},{[143]=true,[133]=true},133).spellID,133) end)
for _,key in ipairs({"fireball","frostbolt","arcane_missiles","scorch"}) do
 test("rank_resolver_" .. key .. "_multi_rank",function()
  local resolve,verify=T.Dispatch.ResolveCached,T.Dispatch.VerifyCurrent; local known=C_SpellBook.IsSpellKnown
  T.Dispatch.ResolveCached=function() return nil end; C_SpellBook.IsSpellKnown=function() return true end
  eq(A.RankResolver:Resolve(key,{[900]={ability=key,rank=1},[100]={ability=key,rank=2}}).spellID,100)
  T.Dispatch.ResolveCached,T.Dispatch.VerifyCurrent=resolve,verify; C_SpellBook.IsSpellKnown=known
 end)
end
test("profile_identity_does_not_use_getspecialization",function()
 local spec,info=GetSpecialization,GetSpecializationInfo
 GetSpecialization=function() error("FORBIDDEN") end; GetSpecializationInfo=GetSpecialization
 UnitClass=function() return "Mage","MAGE" end; eq(T.Profiles:Identity(),"MAGE:base")
 GetSpecialization,GetSpecializationInfo=spec,info
end)
test("legacy_spec_profile_migration_safe",function()
 local rows={{name="Fireball",spellID=143,matchIDs={143}}}
 local e=T.Engine.New(T.Config,{classProfiles={["MAGE:62"]={single=rows,multi={}}},sourceByProfile={["MAGE:62"]={single="code"}}})
 eq(e.db.classProfiles["MAGE:base"].single[1].spellID,143); eq(e.db.sourceByProfile["MAGE:base"].single,"manual")
 e=T.Engine.New(T.Config,{classProfiles={["MAGE:62"]={single=rows,multi={}},["MAGE:63"]={single=rows,multi={}}}})
 eq(#e.db.classProfiles["MAGE:base"].single,0); eq(e.db.classProfiles["MAGE:63"].single[1].spellID,143)
end)
test("template_auto_does_not_infer_from_filler",function() eq(A.Clean({filler="frostbolt"}).template,"custom"); eq(A.Clean({filler="arcane_blast"}).template,"custom") end)
local function talents()
 local t={}; for _,k in ipairs({"arcane_power","presence_of_mind","pyroblast","combustion","cold_snap","ice_barrier","fingers_of_frost"}) do t[k]={known=false,rank=0} end
 return t
end
test("build_selector_key_talent",function() local t=talents(); t.arcane_power={known=true,rank=1}; eq(A.BuildSelector:Select(t,{}).template,"arcane") end)
test("build_selector_ambiguous_fail_closed",function() local t=talents(); t.arcane_power={known=true,rank=1}; t.pyroblast={known=true,rank=1}; eq(A.BuildSelector:Select(t,{}).confidence,"AMBIGUOUS") end)
test("build_selector_unknown_fail_closed",function() local t=talents(); t.arcane_power={known=true,rank=1}; t.cold_snap={}; eq(A.BuildSelector:Select(t,{}).template,"unresolved") end)
test("manual_template_override_preserved",function() eq(A:SelectTemplate({talents={},actions={}},A.Clean({template="frost"})).template,"frost") end)
test("apl_candidate_replace_preserves_runtime_intent",function()
 local e=F.runtime(); T.Runtime:SetIntent(true)
 eq(T.Runtime:ReplaceRecommendation({{name="Frostbolt",spellID=205,matchIDs={205}}}),true)
 eq(T.Runtime.intent,true); eq(e.index,1); eq(e.running,true)
end)
test("apl_candidate_replace_does_not_log_user_reset",function()
 local e=F.runtime(); T.Runtime:SetIntent(true); local start=#e.db.diagnostics
 T.Runtime:ReplaceRecommendation({{name="Frostbolt",spellID=205,matchIDs={205}}})
 for i=start+1,#e.db.diagnostics do assert(e.db.diagnostics[i].reason~="RESET") end
end)
test("apl_candidate_replace_retires_unsent_pending",function()
 local e=F.runtime(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch.pending)
 T.Runtime:ReplaceRecommendation({{name="Frostbolt",spellID=205,matchIDs={205}}}); eq(T.Dispatch.pending,nil)
end)
test("apl_current_initiation_not_replaced_until_receipt",function()
 local e=F.runtime(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); F.receipt("UNIT_SPELLCAST_SENT",143,"foundation-lock")
 local generation=e.generation
 eq(T.Runtime:ReplaceRecommendation({{name="Frostbolt",spellID=205,matchIDs={205}}}),false); eq(e.generation,generation); eq(e.steps[1].spellID,143)
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"foundation-lock"); eq(e.receiptSerial,1)
 eq(T.Runtime:ReplaceRecommendation({{name="Frostbolt",spellID=205,matchIDs={205}}}),true)
end)
test("apl_dirty_refresh_under_250ms_and_cached_static_providers",function()
 local e=F.runtime(); local time=10; GetTime=function() return time end; T.Runtime:SetIntent(true)
 local bookCalls,talentCalls=0,0; local book=C_SpellBook.GetNumSpellBookSkillLines; local talent=A.TalentState.Read
 C_SpellBook.GetNumSpellBookSkillLines=function(...) bookCalls=bookCalls+1; return book(...) end
 A.TalentState.Read=function(...) talentCalls=talentCalls+1; return talent(...) end
 local old=e.aplSnapshot; time=10.02; A:Invalidate(); A:Refresh(e); eq(e.aplSnapshot,old)
 time=10.06; A:Refresh(e); eq(e.aplSnapshot.sampledAt,10.06)
 old=e.aplSnapshot; time=10.19; A:Refresh(e); eq(e.aplSnapshot,old)
 time=10.27; A:Refresh(e); eq(e.aplSnapshot.sampledAt,10.27)
 eq(bookCalls,0); eq(talentCalls,0)
 C_SpellBook.GetNumSpellBookSkillLines=book; A.TalentState.Read=talent
end)
test("apl_direct_sent_association_locks_without_continuous_marker",function()
 local e=F.runtime(); T.Runtime:SetIntent(true); T.Dispatch.initiation=nil
 e:Handle(e.generation,"UNIT_SPELLCAST_SENT","player","direct-lock",143)
 eq(T.Runtime:ReplaceRecommendation({{name="Frostbolt",spellID=205,matchIDs={205}}}),false)
 e:Handle(e.generation,"UNIT_SPELLCAST_FAILED","player","direct-lock",143)
 eq(T.Runtime:ReplaceRecommendation({{name="Frostbolt",spellID=205,matchIDs={205}}}),true)
end)
test("wotlk_support_summary_preserves_all_source_rules",function() local _,c=A:RuleSummary(); eq(c.total,84); eq(c.active,14); eq(c.blocked,33); eq(c.dropped,37) end)
test("loss_of_control_public_secret_missing_and_failure",function()
 local e=F.runtime(); local old=C_Spell.GetSpellLossOfControlCooldownInfo
 C_Spell.GetSpellLossOfControlCooldownInfo=function(id) return {isActive=id==143} end
 eq(A.State.LossOfControl(143),false); eq(A.State.LossOfControl(205),true)
 C_Spell.GetSpellLossOfControlCooldownInfo=function() return {isActive=F.secret} end
 eq(A.State.LossOfControl(143),nil)
 C_Spell.GetSpellLossOfControlCooldownInfo=function() error("PRIVATE_ERROR") end
 eq(A.State.LossOfControl(143),nil)
 C_Spell.GetSpellLossOfControlCooldownInfo=nil; eq(A.State.LossOfControl(143),nil)
 C_Spell.GetSpellLossOfControlCooldownInfo=old
end)
test("loss_of_control_blocks_candidate_and_live_dispatch",function()
 local e=F.runtime(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch:Packet())
 local old=C_Spell.GetSpellLossOfControlCooldownInfo
 C_Spell.GetSpellLossOfControlCooldownInfo=function() return {isActive=true} end
 eq(T.Dispatch:Packet(),nil)
 local s=state(); s.actions.fireball.loss_control_clear=false
 eq(A:RuleAllowed(s,rule(),strategy()),false)
 s.actions.fireball.loss_control_clear=nil; eq(A:RuleAllowed(s,rule(),strategy()),nil)
 C_Spell.GetSpellLossOfControlCooldownInfo=old
end)
test("loss_of_control_trace_sanitizes_secret",function()
 local a=A.Trace.Clean({reason="APL_CANDIDATE",actions={custom_1={spellID=143,loss_control_clear=false,lossControlReason="PUBLIC_LOSS_OF_CONTROL_ACTIVE"}}}).actions.custom_1
 eq(a.loss_control_clear,false); eq(a.lossControlReason,"PUBLIC_LOSS_OF_CONTROL_ACTIVE")
 a=A.Trace.Clean({reason="APL_CANDIDATE",actions={custom_1={spellID=143,loss_control_clear=F.secret,lossControlReason=F.secret}}}).actions.custom_1
 eq(a.loss_control_clear,nil); eq(a.lossControlReason,nil)
end)
test("custom_loss_of_control_falls_back_and_rechecks_live",function()
 local e=F.runtime(); local C=A.Custom
 assert(C:Save(e,{{spellID=143},{spellID=205}},"single","MAGE"))
 local old=C_Spell.GetSpellLossOfControlCooldownInfo
 C_Spell.GetSpellLossOfControlCooldownInfo=function(id) return {isActive=id==143} end
 local oldAction=GetActionInfo; GetActionInfo=function() return "spell",205 end
 T.Runtime:SetIntent(true); eq(T.Recommendation:Current(e).spellID,205)
 T.Dispatch:TickContinuous(); assert(T.Dispatch:Packet())
 C_Spell.GetSpellLossOfControlCooldownInfo=function() return {isActive=F.secret} end
 eq(T.Dispatch:Packet(),nil)
 C_Spell.GetSpellLossOfControlCooldownInfo=old; GetActionInfo=oldAction
end)
test("manual_opener_requires_human_intent_and_public_combat",function()
 local e=F.runtime(); e.db.dispatch.mode="manual"; InCombatLockdown=function() return false end
 T.Runtime:SetIntent(true,"RUNTIME_AUTO_WORLD"); eq(T.APL:Allowed(e,143),false)
 T.Dispatch:TickContinuous(); eq(T.Dispatch:Packet(),nil)
 T.Runtime:Stop(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous(); assert(T.Dispatch:Packet())
 InCombatLockdown=function() return F.secret end; eq(T.Dispatch:Packet(),nil)
 T.Runtime:Stop(); InCombatLockdown=function() return true end; T.Runtime:Reconcile(); eq(T.Runtime.intent,false)
end)
test("manual_opener_maintenance_idle_does_not_block_battle_source",function()
 local e=F.runtime(); e.db.dispatch.mode="manual"; InCombatLockdown=function() return false end
 e.db.maintenance[e.classToken]={enabled=true,rows={}}
 T.Runtime:SetIntent(true); eq(T.Runtime.state,"running"); T.Dispatch:TickContinuous(); assert(T.Dispatch:Packet())
end)
return n
