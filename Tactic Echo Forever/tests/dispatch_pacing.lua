local T,F=...
local test,eq,receipt=F.test,F.eq,F.receipt
local clock
local function setup()
 F.runtimeFixture("manual")
 local e=T.engine
 e.steps=T.Engine.Validate({{name="普通读条",spellID=116,matchIDs={116},repeatCount=1},
  {name="奥术飞弹",spellID=5144,matchIDs={5144},repeatCount=1}})
 e.db.dispatch.ordinaryContinuous=true; e.db.dispatch.castQueue=true; e.db.dispatch.castQueueLead=.25
 InCombatLockdown=function() return true end
 clock=12; GetTime=function() return clock end; C_CVar=nil; GetCVar=function() return "400" end
 UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
 GetActionInfo=function(slot) return "spell",slot==1 and 116 or 5144 end
 ActionButton1={action=1,GetAttribute=function(self) return self.action end}
 ActionButton2={action=2,GetAttribute=function(self) return self.action end}
 GetBindingKey=function(command) return command=="ACTIONBUTTON1" and "1" or "2" end
 T.Dispatch:ClearBindingCache(); T.Runtime:Start(false); T.Dispatch:TickContinuous()
 assert(T.Dispatch:Packet())
 return e
end
local function tick() T.Runtime:Reconcile(); T.Dispatch:TickContinuous() end

test("paced_sent_before_cast_query_revokes_token_without_replacing_receipt",function()
 local e=setup(); local serial=e.receiptSerial or 0
 receipt("UNIT_SPELLCAST_SENT",116,"paced-sent")
 eq(T.Dispatch.pending,nil); eq(T.Dispatch:Packet(),nil)
 for _=1,3 do tick(); eq(T.Dispatch:Packet(),nil) end
 assert(T.Dispatch:HasCurrentInitiation()); eq(e.index,1); eq(e.receiptSerial or 0,serial)
end)

test("paced_started_spell_keeps_receipt_when_resources_are_already_spent",function()
 local e=setup(); receipt("UNIT_SPELLCAST_SENT",116,"paced-resource")
 C_Spell.IsSpellUsable=function() return false,true end
 tick(); eq(T.Dispatch:Packet(),nil); assert(T.Dispatch:HasCurrentInitiation())
 eq(T.Runtime.reason,"CONTINUOUS_WAIT_CURRENT_RECEIPT")
 receipt("UNIT_SPELLCAST_SUCCEEDED",116,"paced-resource"); eq(e.index,2)
end)

test("paced_cast_to_channel_tail_never_republishes_old_cast",function()
 local e=setup(); receipt("UNIT_SPELLCAST_SENT",116,"paced-tail")
 UnitCastingInfo=function() return "普通读条",nil,nil,10000,12500,nil,nil,false,116 end
 for _,at in ipairs({12,12.26,12.31,12.49}) do
  clock=at; tick(); eq(T.Dispatch.castQueue,nil); eq(T.Dispatch:Packet(),nil); eq(e.index,1)
 end
 receipt("UNIT_SPELLCAST_SUCCEEDED",116,"paced-tail"); eq(e.index,2)
 tick(); eq(T.Dispatch:Packet(),nil) -- 成功回执早于公开读条消失时仍等待。
 UnitCastingInfo=function() return nil end; tick(); assert(T.Dispatch:Packet())
 eq(T.Dispatch.pending.binding.spellID,5144)
end)

test("paced_next_cast_reserves_once_and_stops_after_exact_acceptance",function()
 local e=setup(); e.steps[2]=T.Engine.Validate({{name="下一读条",spellID=205,matchIDs={205}}})[1]
 GetActionInfo=function(slot) return "spell",slot==1 and 116 or 205 end; T.Dispatch:ClearBindingCache()
 receipt("UNIT_SPELLCAST_SENT",116,"paced-A")
 UnitCastingInfo=function() return "普通读条",nil,nil,10000,12500,nil,nil,false,116 end
 clock=12; tick(); eq(T.Dispatch:Packet(),nil)
 clock=12.31; tick(); assert(T.Dispatch.castQueue); eq(T.Dispatch.pending.binding.spellID,205)
 assert(T.Dispatch:Packet()); local request=T.Runtime.requestSerial
 receipt("UNIT_SPELLCAST_SENT",205,"paced-B"); eq(T.Dispatch.pending,nil)
 tick(); eq(T.Dispatch:Packet(),nil); eq(T.Runtime.requestSerial,request); eq(e.index,1)
 receipt("UNIT_SPELLCAST_SUCCEEDED",116,"paced-A"); eq(e.index,2)
 assert(T.Dispatch:HasCurrentInitiation()); tick(); eq(T.Dispatch:Packet(),nil)
 receipt("UNIT_SPELLCAST_SUCCEEDED",205,"paced-B"); eq(e.completed,true); eq(e.receiptSerial,2)
end)

test("paced_failure_retries_same_step_only_after_configured_delay",function()
 local e=setup(); e.db.dispatch.retryDelay=.15
 receipt("UNIT_SPELLCAST_SENT",116,"paced-failed")
 receipt("UNIT_SPELLCAST_INTERRUPTED",116,"paced-failed")
 eq(e.index,1); eq(e.receiptSerial or 0,0); eq(T.Runtime.intent,true)
 for _,at in ipairs({12,12.10,12.14}) do clock=at; tick(); eq(T.Dispatch:Packet(),nil) end
 eq(T.Runtime.reason,"CONTINUOUS_RETRY_DELAY")
 clock=12.16; tick(); assert(T.Dispatch:Packet()); eq(T.Dispatch.pending.binding.spellID,116)
 receipt("UNIT_SPELLCAST_SUCCEEDED",116,"paced-failed"); eq(e.index,1)
 receipt("UNIT_SPELLCAST_SENT",116,"paced-retry")
 receipt("UNIT_SPELLCAST_SUCCEEDED",116,"paced-retry"); eq(e.index,2)
end)

test("paced_retry_unknown_clock_rollback_and_reset_never_guess_ready",function()
 local e=setup(); e.db.dispatch.retryDelay=.15
 GetTime=function() return F.secret end; T.Runtime:DeferRetry()
 local ready,why=T.Runtime:RetryReady(); eq(ready,false); eq(why,"CONTINUOUS_RETRY_CLOCK_UNKNOWN")
 GetTime=function() return clock end; clock=20; eq(T.Runtime:RetryReady(),false)
 clock=19; eq(T.Runtime:RetryReady(),false)
 clock=19.16; eq(T.Runtime:RetryReady(),true)
 T.Runtime:DeferRetry(); T.Runtime:Stop(); eq(T.Runtime.retryWait,nil)
 T.Runtime:SetIntent(true); eq(T.Runtime:RetryReady(),true)
end)

test("paced_retry_context_does_not_delay_another_generation_or_step",function()
 local e=setup(); e.db.dispatch.retryDelay=.5; T.Runtime:DeferRetry()
 T.Runtime:Reset(); eq(T.Runtime:RetryReady(),true)
 T.Runtime:SetIntent(true); T.Runtime:DeferRetry(); e.index=2
 eq(T.Runtime:RetryReady(),true); eq(T.Runtime.retryWait,nil)
end)

test("paced_retry_configuration_defaults_bounds_and_noop",function()
 eq(T.Runtime.Clean({}).retryDelay,.15); eq(T.Runtime.Clean({retryDelay=F.secret}).retryDelay,.15)
 eq(T.Runtime.Clean({retryDelay=9}).retryDelay,.5); eq(T.Runtime.Clean({retryDelay=-1}).retryDelay,0)
 setup(); local e=T.engine
 eq(T.Runtime:SetRetryDelay(-.1),false); eq(T.Runtime:SetRetryDelay(F.secret),false)
 eq(T.Runtime.intent,true); assert(T.Runtime:SetRetryDelay(.2)); eq(T.Runtime.intent,false)
 eq(e.db.dispatch.retryDelay,.2); T.Runtime:SetIntent(true)
 assert(T.Runtime:SetRetryDelay(.2)); eq(T.Runtime.intent,true)
end)

test("paced_settings_numeric_fields_keep_errors_and_commit_only_once",function()
 F.deliveryFixture("manual"); local U,e=T.UI,T.engine
 local input=U.retryDelayInput; assert(input); assert(U.castQueueLeadInput)
 local old=e.db.dispatch.retryDelay
 input.text="0.8"; input.scripts.OnEnterPressed(); U:RefreshControls()
 eq(e.db.dispatch.retryDelay,old); eq(input.text,"0.8")
 local setter=T.Runtime.SetRetryDelay; local calls=0
 T.Runtime.SetRetryDelay=function(self,value) calls=calls+1; return setter(self,value) end
 input.text="0.25"; input.scripts.OnEnterPressed(); input.scripts.OnEditFocusLost()
 eq(e.db.dispatch.retryDelay,.25); eq(calls,1)
 T.Runtime.SetRetryDelay=setter
 local lead=U.castQueueLeadInput
 lead.text="0.35"; lead.scripts.OnEnterPressed(); eq(e.db.dispatch.castQueueLead,.35)
 lead.text="0.7"; lead.scripts.OnEnterPressed(); eq(e.db.dispatch.castQueueLead,.35)
 U:RefreshControls(); eq(lead.text,"0.7")
 eq(e.db.dispatch.retryDelay,.25)
end)
