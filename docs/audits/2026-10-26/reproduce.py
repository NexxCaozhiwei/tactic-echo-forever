from pathlib import Path
import json
import sys
sys.path.insert(0,str(Path.cwd()))
from lupa.lua51 import LuaRuntime

root = Path('Tactic Echo Forever').resolve()
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().print = lambda *args: None
lua.globals()._audit_out = lambda *args: print(' | '.join(str(v) for v in args))
lua.globals().arg = lua.table_from([root.as_posix()])
probe = r'''
local function audit(name,fn)
 local ok,err=pcall(fn)
 if not ok then _audit_out(name,"REPRO_ERROR",err) end
end
audit("R01_manual_ooc_packet",function()
 deliveryFixture("manual"); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
 local token,combat=T.Dispatch:Packet()
 _audit_out("R01", "combat",combat,"maintenance",T.engine.maintenanceActive,"token",token,"state",T.Runtime.state)
end)
audit("R02_require_ready",function()
 local row=T.APL.Custom.CleanRows({{spellID=143,enabled=true,requireReady=true}})[1]
 local state={actions={custom_1={known=true,usable=true,power_ok=true,in_range=true,loss_control_clear=true,ready=false}}}
 local value,reason=T.APL.Custom:Check(state,row,1)
 _audit_out("R02","inputRequireReady",true,"cleanedRequireReady",row.requireReady,"ready",state.actions.custom_1.ready,"allowed",value,"reason",reason)
end)
audit("R03_parent_child_usage_collision",function()
 deliveryFixture("manual"); local e=T.engine; InCombatLockdown=function() return true end
 local function step(id) return {name="技能",spellID=id,matchIDs={id},repeatCount=1,usagePolicy="target",enabled=true} end
 local group={name="隔离验证",rounds=1,steps={step(205),{name="技能",spellID=2136,matchIDs={2136},repeatCount=1}}}
 assert(T.Profiles:Save(e,"single",{step(116),T.SkillGroups:Row(group)}))
 T.Runtime:SetIntent(true)
 receipt("UNIT_SPELLCAST_SENT",116,"audit-parent")
 receipt("UNIT_SPELLCAST_SUCCEEDED",116,"audit-parent")
 T.Runtime:Reconcile()
 _audit_out("R03","group",e.groupRun~=nil,"childIndex",e.index,"childID",e.steps[e.index].spellID,"reason",T.Runtime.reason)
end)
audit("R04_queue_channel_rank",function()
 deliveryFixture("manual"); local e=T.engine; InCombatLockdown=function() return true end
 e.db.dispatch.castQueue=true; e.db.dispatch.castQueueLead=.5
 assert(T.Profiles:Save(e,"single",{{name="寒冰箭",spellID=116,matchIDs={116}},{name="飞弹",spellID=5144,matchIDs={5144}}}))
 GetTime=function() return 10 end
 T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
 receipt("UNIT_SPELLCAST_SENT",116,"audit-cast")
 UnitCastingInfo=function() return "寒冰箭",nil,nil,8000,10300,nil,nil,false,116 end
 UnitChannelInfo=function() return nil end
 C_CVar={GetCVar=function() return "400" end}
 local index,nextStep=T.Dispatch:CastQueueWindow()
 _audit_out("R04","queueIndex",index,"nextID",nextStep and nextStep.spellID,"reason",T.Dispatch.queueWindowReason)
end)
audit("R05_cdm_category_isolation",function()
 C_CooldownViewer={GetCooldownViewerCategorySet=function(cat) return cat==2 and {10} or {} end,
  GetCooldownViewerCooldownInfo=function() return {spellID=400588} end}
 local frame={cooldownID=10,isActive=true,IsVisible=function() return true end}
 BuffIconCooldownViewer={itemFramePool={EnumerateActive=function() local n=0; return function() n=n+1; if n==1 then return frame end end end}}
 BuffBarCooldownViewer={itemFramePool={EnumerateActive=function() return function() end end}}
 local request={{enabled=true,cdmKind="buff",cdmSpellID=400588}}
 local a=T.APL.PublicConditions.CDM(request)["buff:400588"]
 BuffBarCooldownViewer=nil
 local b=T.APL.PublicConditions.CDM(request)["buff:400588"]
 _audit_out("R05","bothViewers",a.value,"iconStillVisible",frame:IsVisible(),"missingUnrelatedBar",b.value,"reason",b.reason)
end)
audit("R06_unknown_log_reload",function()
 deliveryFixture("manual"); local e=T.engine
 e:Log("transport","UNKNOWN:custom:strategy",116)
 local before=#e.db.diagnostics
 local reload=T.Engine.New(T.Config,e.db)
 local found=false; for _,row in ipairs(reload.db.diagnostics) do if row.reason=="UNKNOWN:custom:strategy" then found=true end end
 _audit_out("R06","before",before,"unknownReasonRetained",found)
end)
audit("R09_apl_cdm_scans_per_packet",function()
 deliveryFixture("manual"); local e=T.engine; InCombatLockdown=function() return true end
 UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
 C_Spell.IsSpellPassive=function() return false end; C_Spell.IsSpellHarmful=function() return true end
 C_SpellBook.IsSpellKnown=function() return true end
 local calls=0
 C_CooldownViewer={GetCooldownViewerCategorySet=function(cat) calls=calls+1; return cat==2 and {10} or {} end,
  GetCooldownViewerCooldownInfo=function() return {spellID=400588} end}
 local frame={cooldownID=10,isActive=true,IsVisible=function() return true end}
 BuffIconCooldownViewer={itemFramePool={EnumerateActive=function() local n=0; return function() n=n+1; if n==1 then return frame end end end}}
 BuffBarCooldownViewer={itemFramePool={EnumerateActive=function() return function() end end}}
 local row={spellID=116,enabled=true,strategies={{mode="use",conditions={{kind="cdmBuff",spellID=400588,value=true}}}}}
 assert(T.APL.Custom:Save(e,{row},"single","MAGE"))
 assert(T.Recommendation:SetSource(e,"apl","single"))
 T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
 calls=0; local token=T.Dispatch:Packet()
 _audit_out("R09","token",token,"categoryCallsInOnePacket",calls)
end)
audit("R10_hud_rearms_edge_policy",function()
 deliveryFixture("manual"); local e=T.engine; InCombatLockdown=function() return true end
 UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
 local first={name="寒冰箭",spellID=116,matchIDs={116}}
 local other={name="火球术",spellID=143,matchIDs={143},
  strategies={{mode="use",conditions={{kind="moving",value=true}}}},
  behavior={trigger="edge",scope="entry",emergency=false,after="resume"}}
 assert(T.Profiles:Save(e,"single",{first,other}))
 T.Runtime:SetIntent(true); IsPlayerMoving=function() return false end
 local row=e.steps[2]; T.APL.Custom:PolicySucceeded(e,row)
 local record=T.APL.Custom:PolicyRecord(e,row,false)
 local before=record.consumed
 T.Recommendation:HUDSteps(e)
 _audit_out("R10","consumedBeforeHUD",before,"consumedAfterHUD",record.consumed,"index",e.index)
end)
audit("R11_runtime_defaults",function()
 local defaults=T.Runtime.Clean(nil)
 _audit_out("R11","defaultMode",defaults.mode,"autoStart",defaults.autoStart,"ordinaryContinuous",defaults.ordinaryContinuous)
end)
audit("R12_invalid_maintenance_initialization",function()
 deliveryFixture("manual"); local e=T.engine
 local db={maintenance={MAGE={enabled=false,rows={{spellID=0,enabled=false}}}}}
 local ok,err=pcall(T.Engine.New,T.Config,db)
 _audit_out("R12","disabledInvalidMaintenanceLoginOK",ok,"error",err)
end)
'''
lua.execute((root/'tests/run.lua').read_text(encoding='utf-8')+'\n'+probe)

from tek.app.settings_store import AppSettings
changed=AppSettings.from_dict({'auto_start_ui_linked':False,'sampling_interval_ms':'invalid'})
print('R07b | input_auto_start=False | normalized_auto_start='+str(changed.auto_start_ui_linked))
try:
    AppSettings.from_dict(json.loads('{"sampling_interval_ms":1e309}'))
    print('R07 | no_exception')
except Exception as exc:
    print('R07 | ' + type(exc).__name__ + ' | ' + str(exc))

from tek.src.windows_sendinput import WindowsSendInputDispatcher
from tek.src.input_planner import plan_binding
class Native:
    def __init__(self): self.calls=[]
    def SendInput(self,count,events,size):
        self.calls.append([(int(events[i].union.ki.wVk),int(events[i].union.ki.dwFlags)) for i in range(count)])
        return 1 if len(self.calls)==1 else count
    def GetLastError(self): return 5
native=Native()
dispatcher=WindowsSendInputDispatcher(user32=native,kernel32=native)
plan=plan_binding('2')
result=dispatcher.dispatch(plan)
dispatcher.release_modifiers(plan)
print('R08 | partial='+str(result.events_sent)+' | recovery='+str(native.calls[-1])+' | main_up_present='+str((0x32,2) in native.calls[-1]))
