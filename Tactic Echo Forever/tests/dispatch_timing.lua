local _,T,F=...
local C=T.APL.Custom
local originalGUID=UnitGUID
local function eq(a,b) assert(a==b,"timing expected " .. tostring(b) .. " got " .. tostring(a)) end
local function fixture(behavior)
 local e=F.runtime(); local now=10
 GetTime=function() return now end; IsPlayerMoving=function() return false end
 UnitGUID=function(unit) return unit=="target" and "Creature-Timing" or "Player-Timing" end
 GetCVar=function() return "400" end; C_CVar=nil
 GetActionInfo=function(slot) return "spell",slot==1 and 143 or 205 end
 ActionButton1={action=1,GetAttribute=function(self) return self.action end}
 ActionButton2={action=2,GetAttribute=function(self) return self.action end}
 GetBindingKey=function(command) if command=="ACTIONBUTTON1" then return "1" elseif command=="ACTIONBUTTON2" then return "2" end end
 assert(C:Save(e,{{spellID=143,moving="no",behavior=behavior},{spellID=205,moving="yes"}},"single","MAGE"))
 e.db.dispatch.castQueue=true; e.db.dispatch.castQueueLead=.2
 T.Dispatch:ClearBindingCache(); T.Runtime:SetIntent(true); T.Dispatch:TickContinuous()
 assert(T.Dispatch.pending)
 F.receipt("UNIT_SPELLCAST_SENT",143,"timing-origin")
 UnitCastingInfo=function() return "火球术",nil,nil,10000,11000,nil,nil,false,143 end
 return e,function(value) now=value end
end
local e,time=fixture()
IsPlayerMoving=function() return true end
time(10.5); T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
eq(T.Dispatch.castQueue,nil); eq(e.aplCandidate.spellID,143); assert(T.Dispatch:HasCurrentInitiation())
time(10.85); T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
assert(T.Dispatch.castQueue,"missing custom queue: " .. tostring(T.Dispatch.queueWindowReason))
eq(T.Dispatch.castQueue.spellID,205); eq(e.aplCandidate.spellID,143); assert(T.Dispatch:Packet())
F.receipt("UNIT_SPELLCAST_SENT",205,"timing-next")
eq(e.receiptSerial or 0,0)
F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"timing-origin")
eq(e.aplCandidate.spellID,205); eq(e.receiptSerial,1); assert(T.Dispatch:HasCurrentInitiation())
F.receipt("UNIT_SPELLCAST_SUCCEEDED",205,"timing-next"); eq(e.receiptSerial,2)
T.Runtime:Stop()

e,time=fixture(); IsPlayerMoving=function() return true end; time(10.85)
T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.castQueue)
IsPlayerMoving=function() return false end
eq(T.Dispatch:Packet(),nil); eq(e.aplCandidate.spellID,143); eq(e.receiptSerial or 0,0)
T.Runtime:Stop()

e,time=fixture()
F.receipt("UNIT_SPELLCAST_FAILED",143,"timing-origin")
eq(T.Runtime.retryClass,"REEVALUATE"); eq(e.receiptSerial or 0,0)
UnitCastingInfo=function() return nil end
IsPlayerMoving=function() return true end; time(10.2); T.Runtime:Reconcile()
eq(e.aplCandidate.spellID,205); eq(e.receiptSerial or 0,0)
IsPlayerMoving=function() return false end; time(10.4); T.Runtime:Reconcile()
eq(e.aplCandidate.spellID,143)
T.Runtime:Stop()

e,time=fixture(); time(10.85); T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
assert(T.Dispatch.castQueue); eq(T.Dispatch.castQueue.spellID,143)
F.receipt("UNIT_SPELLCAST_SENT",143,"timing-same-next")
F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"timing-origin"); eq(e.receiptSerial,1)
F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"timing-same-next"); eq(e.receiptSerial,2)
T.Runtime:Stop()

e,time=fixture(); IsPlayerMoving=function() return true end; time(10.85)
T.Runtime:Reconcile(); T.Dispatch:TickContinuous(); assert(T.Dispatch.castQueue)
UnitGUID=function() return "Creature-Changed" end
eq(T.Dispatch:Packet(),nil); eq(e.receiptSerial or 0,0); eq(e.aplCandidate.spellID,143)
T.Runtime:Stop()

e,time=fixture(); local generation=e.generation
e:UsageTargetChanged(); T.Runtime:TargetChanged()
eq(e.generation,generation); assert(T.Dispatch:HasCurrentInitiation()); eq(T.Dispatch:Packet(),nil)
F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"timing-origin"); eq(e.receiptSerial,1)
UnitCastingInfo=function() return nil end; time(11.1); T.Runtime:Reconcile()
eq(T.Runtime.targetChangePending,nil); eq(e.finishOldTargetReceipt,nil); eq(T.Runtime.intent,true)
T.Runtime:Stop()

e,time=fixture({trigger="target",scope="entry",after="resume"})
local row=C:Rows(e)[1]; local oldStamp=C:PolicyStamp(e,row)
UnitGUID=function() return "Creature-New-Target" end
e:UsageTargetChanged(); local newStamp=C:PolicyStamp(e,row); assert(oldStamp~=newStamp)
T.Runtime:TargetChanged(); F.receipt("UNIT_SPELLCAST_SUCCEEDED",143,"timing-origin")
eq(e.receiptSerial,1)
local record=C:PolicyRecord(e,row,false); assert(record.targets[oldStamp]); eq(record.targets[newStamp],nil)
T.Runtime:Stop()

e,time=fixture(); IsPlayerMoving=function() return true end; time(10.5)
local previous=e.aplCandidate
T.Dispatch:PrepareHandoff(); assert(T.Dispatch.handoff and T.Dispatch.handoff.apl)
eq(T.Dispatch.handoff.spellID,205); eq(e.aplCandidate,previous); eq(e.receiptSerial or 0,0)
eq(T.Dispatch.pending,nil); eq(T.Dispatch.castQueue,nil)
time(10.85); T.Runtime:Reconcile(); T.Dispatch:TickContinuous()
assert(T.Dispatch.castQueue); eq(T.Dispatch.castQueue.spellID,205)
T.Runtime:Stop(); UnitGUID=originalGUID
return 8
