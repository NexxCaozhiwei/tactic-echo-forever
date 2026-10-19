local _,T,F=...
local A=T.APL
local n=0
local function eq(a,b) assert(a==b,"maintenance expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function scenario(locked)
 local e=F.runtime()
 local saved={}
 for _,key in ipairs({"C_CooldownViewer","BuffIconCooldownViewer","BuffBarCooldownViewer","InCombatLockdown","IsPlayerMoving","GetTime","UnitExists","UnitCastingInfo"}) do saved[key]={_G[key]} end
 local info,known=C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown
 C_Spell.GetSpellInfo=function(id) return {name=id==7301 and "霜甲术" or "寒冰箭"} end
 C_SpellBook.IsSpellKnown=function() return true end
 assert(T.Recommendation:SetSource(e,"manual","single"))
 assert(T.Profiles:Save(e,"single",{{spellID=205,name="寒冰箭",matchIDs={205},repeatCount=3}}))
 local base=e.steps; e.stepCasts=1
 local frame={cooldownID=10,isActive=false,IsVisible=function() return true end}
 local function pool(frames) return {EnumerateActive=function() local i=0; return function() i=i+1; return frames[i] end end} end
 C_CooldownViewer={GetCooldownViewerCategorySet=function(cat) return cat==2 and {10} or {} end,
  GetCooldownViewerCooldownInfo=function() return {spellID=168} end}
 BuffIconCooldownViewer={itemFramePool=pool({frame})}; BuffBarCooldownViewer={itemFramePool=pool({})}
 InCombatLockdown=function() return false end; IsPlayerMoving=function() return false end; UnitExists=function(unit) return unit=="player" end
 local now=10; GetTime=function() return now end
 assert(T.Maintenance:Save(e,{{spellID=7301,strategies={{mode="use",conditions={{kind="cdmBuff",spellID=168,value=false}}}}}}))
 T.Maintenance:SetEnabled(e,true); T.Runtime:SetIntent(true)
 eq(e.maintenanceActive,true); eq(e.aplCandidate.spellID,7301)
 F.receipt("UNIT_SPELLCAST_SENT",7301,"rearm-first")
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",7301,"rearm-first")
 T.Runtime:Reconcile(); eq(e.maintenanceActive,nil); eq(e.maintenanceDone[7301],true)
 if locked=="cast" then UnitCastingInfo=function() return "寒冰箭" end
 elseif locked=="settings" then T.UI.settingsOpen=true end
 frame.isActive=true; now=now+.25; A:Invalidate(); T.Runtime:Reconcile()
 -- 即使当前读条锁住推荐替换，也应记录公开的增益已存在，解除本次成功去重。
 eq(e.maintenanceDone[7301],nil)
 if locked then
  eq(e.maintenanceActive,nil); eq(e.steps,base); eq(e.stepCasts,1); eq(T.Dispatch:Packet(),nil)
 end
 frame.isActive=false; UnitCastingInfo=saved.UnitCastingInfo[1]; T.UI.settingsOpen=false
 now=now+.25; A:Invalidate(); T.Runtime:Reconcile()
 eq(e.maintenanceActive,true); eq(e.aplCandidate.spellID,7301)
 F.receipt("UNIT_SPELLCAST_SENT",7301,"rearm-second")
 F.receipt("UNIT_SPELLCAST_SUCCEEDED",7301,"rearm-second")
 T.Runtime:Reconcile(); eq(e.steps,base); eq(e.stepCasts,1); eq(T.Runtime.intent,true)
 frame.isActive=F.secret; now=now+.25; A:Invalidate(); T.Runtime:Reconcile()
 eq(e.maintenanceDone[7301],true); eq(e.maintenanceActive,nil); eq(T.Dispatch:Packet(),nil)
 local trace=T.APL.Trace.Clean(e.db.diagnostics[#e.db.diagnostics].apl)
 assert(trace); eq(trace.reason,"MAINTENANCE_IDLE"); eq(trace.rules[1].result,"UNKNOWN")
 eq(trace.actions.custom_1.conditionObservations[1].reason,"SECRET")
 local count=#e.db.diagnostics; T.Runtime:Reconcile(); eq(#e.db.diagnostics,count)
 -- 已公开复位后，缺失或受限信号仍不授予补增益资格。
 frame.isActive=true; now=now+.25; A:Invalidate(); T.Runtime:Reconcile(); eq(e.maintenanceDone[7301],nil)
 BuffIconCooldownViewer.itemFramePool=pool({}); now=now+.25; A:Invalidate(); T.Runtime:Reconcile()
 eq(e.maintenanceActive,nil); eq(T.Dispatch:Packet(),nil)
 trace=T.APL.Trace.Clean(e.db.diagnostics[#e.db.diagnostics].apl)
 eq(trace.actions.custom_1.conditionObservations[1].reason,"CDM_FRAME_MISSING")
 T.Runtime:Stop()
 for key,value in pairs(saved) do _G[key]=value[1] end
 C_Spell.GetSpellInfo,C_SpellBook.IsSpellKnown=info,known
 n=n+1
end
scenario(false)
scenario("cast")
scenario("settings")
return n
