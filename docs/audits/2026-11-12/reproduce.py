"""只读加载生产源码，在模拟客户端与假输入接口内复现审计边界。"""
from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime

repo = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(repo))
root = repo / "Tactic Echo Forever"
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().arg = lua.table_from([root.as_posix()])
lua.globals().audit_out = lambda *args: print("AUDIT | " + " | ".join(map(str, args)), flush=True)
probe = r'''
local function auditFixture(firstRepeats)
 runtimeFixture("manual")
 local e=T.engine; local now=10
 e.steps=T.Engine.Validate({{name="A",spellID=116,matchIDs={116},repeatCount=firstRepeats},
   {name="B",spellID=205,matchIDs={205},repeatCount=1}})
 InCombatLockdown=function() return true end
 C_SpellBook={IsSpellKnown=function() return true end}
 C_Spell.GetSpellInfo=function() return {name="寒冰箭"} end
 C_Spell.IsSpellPassive=function() return false end
 C_Spell.IsSpellHarmful=function() return true end
 C_Spell.IsSpellHelpful=function() return false end
 C_CVar=nil; GetCVar=function() return "400" end
 GetTime=function() return now end
 UnitCastingInfo=function() return nil end; UnitChannelInfo=function() return nil end
 GetActionInfo=function(slot) return "spell",slot==1 and 116 or 205 end
 ActionButton1={action=1,GetAttribute=function(self) return self.action end}
 ActionButton2={action=2,GetAttribute=function(self) return self.action end}
 GetBindingKey=function(command) return command=="ACTIONBUTTON1" and "1" or "2" end
 T.Dispatch:ClearBindingCache()
 T.Runtime:Start(false); T.Dispatch:TickContinuous()
 return e,function(value) now=value end
end
for _,repeats in ipairs({1,3}) do
 local e,clock=auditFixture(repeats)
 e.groupRun={targetSerial=e.usageTargetSerial or 0,round=1,group={maintain=false,rounds=2}}
 e.db.dispatch.groupQueue=true
 for n=1,repeats do
  receipt("UNIT_SPELLCAST_SENT",116,"audit-A-"..n)
  receipt("UNIT_SPELLCAST_SUCCEEDED",116,"audit-A-"..n)
  T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
 end
 receipt("UNIT_SPELLCAST_SENT",205,"audit-last")
 UnitCastingInfo=function() return "B",nil,nil,10000,11000,nil,nil,false,205 end
 clock(10.85)
 assert(T.Dispatch:TryCastQueue())
 local q=T.Dispatch.castQueue
 receipt("UNIT_SPELLCAST_SENT",116,"audit-next-round")
 receipt("UNIT_SPELLCAST_SUCCEEDED",205,"audit-last")
 audit_out("R01", "firstRepeats",repeats,"reservedRound",q.nextRound,"actualRound",e.groupRun.round,
   "completed",e.completed,"nextReceiptRetired",e.seen["audit-next-round"],"nextInitiation",T.Dispatch:HasCurrentInitiation())
end
do
 local e,clock=auditFixture(1)
 receipt("UNIT_SPELLCAST_SENT",116,"audit-missing-terminal")
 clock(100); T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
 audit_out("R02","idle",T.Dispatch:CastIdle(),"initiation",T.Dispatch:HasCurrentInitiation(),
   "state",T.Runtime.state,"reason",T.Runtime.reason,"token",T.Dispatch:Packet(),"index",e.index)
end
do
 local e,clock=auditFixture(1)
 e.steps[1].strategies={{mode="use",conditions={{kind="moving",value=false}}}}
 local original=T.APL.Custom.Sample
 local calls=0
 T.APL.Custom.Sample=function(self,...) calls=calls+1; return original(self,...) end
 T.Dispatch.manualPolicySnapshot=nil
 T.Dispatch:Cancel(); T.Dispatch.waitReceipt=nil
 T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); local token=T.Dispatch:Packet()
 audit_out("R03","policySamplesInOnePulse",calls,"token",token,"reason",T.Runtime.reason,
   "policy",T.Dispatch.manualPolicySnapshot and T.Dispatch.manualPolicySnapshot.reason)
 T.APL.Custom.Sample=original
end
do
 local e=auditFixture(1)
 local rows,state={}, {actions={}}
 for i,radius in ipairs({5,10,20,25,30}) do
  rows[i]={spellID=116,enabled=true,strategies={{mode="use",conditions={{kind="nearbyEnemies",radius=radius,min=1}}}}}
  state.actions["custom_"..i]={}
 end
 local original=T.Research.ProbeVisibleYards
 T.Research.ProbeVisibleYards=function() return {state="PUBLIC_VALUE",lower=1,upper=1,value=1} end
 T.APL.Custom:SampleStrategies(state,rows,e)
 local valid,errors,warnings=T.APL.Custom:Audit(rows,e)
 audit_out("R05","fifthRadius",state.nearbyEnemies[30].state,"auditValid",valid,"errors",errors,"warnings",warnings)
 T.Research.ProbeVisibleYards=original
end
'''
lua.execute((root / "tests/run.lua").read_text(encoding="utf-8") + "\n" + probe)

from tek.src.windows_sendinput import WindowsSendInputDispatcher
from tek.src.input_planner import plan_binding
from tek.src.engine import TEKEngine
from tek.src.safety_gate import SafetyContext
from tek.src.teap import decode_fields, encode_fields_v3
from tek.src.action_catalog import RETRIBUTION_V2
from tek.src.profile_resolver import ProfileResolver

class Native:
    def __init__(self): self.calls = 0
    def SendInput(self, count, events, size):
        self.calls += 1
        return 1 if self.calls == 1 else count
    def GetLastError(self): return 5

native = Native()
held = [True]
dispatcher = WindowsSendInputDispatcher(user32=native, kernel32=native, physical_key_checker=lambda _: held[0])
dispatcher.dispatch(plan_binding("2"))
dispatcher.release_modifiers()
held[0] = False
class Monitor:
    def health_reason(self): return None
engine = TEKEngine(RETRIBUTION_V2, ProfileResolver.from_file(repo / "examples/profiles/laptop.json"), input_dispatcher=dispatcher)
engine.physical_input_monitor = Monitor()
context = SafetyContext(bootstrapped=True)
for freshness in range(1, 6):
    frame = decode_fields(encode_fields_v3(state="paused", session_epoch=1, sequence=freshness,
        frame_freshness_counter=freshness, action_code=0, catalog_version=2,
        catalog_fingerprint=RETRIBUTION_V2.fingerprint16, binding_token=0))
    engine.process_frame(frame, context)
print("AUDIT | R04 | pausedAfterPhysicalRelease | nativeCalls", native.calls,
      "| pendingKeys", dispatcher._unreleased_keys)
