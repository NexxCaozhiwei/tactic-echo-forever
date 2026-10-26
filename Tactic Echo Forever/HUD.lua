local _, TEF = ...
local H, U, S = {}, TEF.UI, TEF.Safety
TEF.HUD = H
-- Presentation only: retain the Runtime reason as the diagnostic source.
local blockReasons={
    CONTINUOUS_WAIT_CURRENT_RECEIPT={"回执", "已确认起手，停止重发并等待精确成功回执"},
    CONTINUOUS_RETRY_DELAY={"重试", "施法失败，等待配置的重试间隔"},
    CONTINUOUS_RETRY_CLOCK_UNKNOWN={"重试", "重试时钟未知，暂不派发"},
    CONTINUOUS_CAST_PRESENT_OR_UNKNOWN={"施法", "正在施法、引导，或施法状态未知"},
    APL_WAIT_CURRENT_RECEIPT={"回执", "等待当前技能的施法回执"},
    SKIP_WAIT_CURRENT_RECEIPT={"回执", "等待当前技能的施法回执"},
    ATTACK_ENABLE_CONFIRMED={"攻击", "已确认自动攻击开启，推进到下一步"},
    ATTACK_ACTIVE_UNKNOWN={"攻击", "无法确认自动攻击是否已开启"},
    CONTINUOUS_TARGET_UNKNOWN_OR_BLOCKED={"目标", "目标不存在、不可攻击、已死亡，或目标状态未知"},
    RUNTIME_TARGET_CHANGED={"目标", "目标变化后等待重新确认"},
    CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED={"距离", "技能不在范围内，或距离状态未知"},
    CONTINUOUS_USABLE_UNKNOWN_OR_BLOCKED={"技能", "技能不可用、资源不足，或可用性未知"},
    SEQUENCE_USAGE_CONTEXT_UNKNOWN={"序列", "无法公开确认目标或战斗范围，等待重试"},
    SEQUENCE_USAGE_EXHAUSTED={"序列", "当前目标或战斗的限定步骤均已完成，等待范围变化"},
    SEQUENCE_USAGE_CAPACITY={"序列", "目标记录已达256个，请主动重置或重新加载"},
    SEQUENCE_USAGE_SKIPPED={"序列", "已跳过当前目标或战斗完成的步骤"},
    SEQUENCE_USAGE_SCOPE_CHANGED={"序列", "目标或战斗已变化，重新确认该步骤次数"},
    SEQUENCE_USAGE_WAIT_RECEIPT={"回执", "限定步骤等待当前施法结束或状态公开"},
    SKIP_AVAILABILITY_UNKNOWN={"技能", "无法确认该技能是否应跳过"},
    SKIP_ALL_UNAVAILABLE={"技能", "序列中的技能均不可用"},
    UNAVAILABLE_STEP_SKIPPED={"技能", "已跳过不可用的序列技能"},
    CONTINUOUS_TEXT_FOCUS_OR_UNKNOWN={"输入", "输入焦点被占用，或焦点状态未知"},
    TEK_EXACT_DIRECT_BINDING_UNAVAILABLE={"输入", "找不到当前技能经核对的技能或宏按键"},
    CONTINUOUS_BINDING_CHANGED={"输入", "技能按键已变化，等待重新确认"},
    RUNTIME_PROFILE_UNCONFIGURED={"配置", "当前推荐配置不可用"},
    RUNTIME_COMBAT_UNKNOWN={"模式", "无法确认战斗状态"},
    APL_NO_CANDIDATE={"APL", "当前没有符合条件的优先级推荐 技能"},
    STRATEGY_STEP_SKIPPED={"策略", "已跳过条件不满足的列表步骤"},
    SEQUENCE_POLICY_WAIT_RECEIPT={"回执", "条件已变化，保留已起手施法的精确回执"},
    SEQUENCE_POLICY_ALL_BLOCKED={"策略", "列表条件均未满足，等待条件变化"},
    SEQUENCE_POLICY_RECOVERED={"策略", "列表已有符合条件的技能，正在恢复"},
}
function H:BlockCategory(reason)
    local code=S.Public(reason,"string")
    if not code then return "未知", "阻断原因未知" end
    local entry=blockReasons[code]
    if entry then return entry[1],entry[2] end
    if code:match("^APL_") then return "APL", "APL 条件未满足，或推荐状态未知" end
    if code:match("^CONTINUOUS_FAILURE_") or code:match("^CONTINUOUS_MOVEMENT_FAILURE_") then
        return "回执", "施法失败，等待重新尝试"
    end
    if code:match("^CONTINUOUS_") or code:match("^TEK_") then return "输入", "派发输入条件未满足" end
    if code:match("^RUNTIME_") then return "模式", "派发运行条件未满足" end
    return "其他", "请查看诊断页中的原因码"
end
-- 文案只解释运行状态；公开施法显示不授予输入资格。
local statusReasons={
 CONTINUOUS_WAIT_CURRENT_RECEIPT={"等待回执","已确认起手，不重复派发当前技能"},
 CONTINUOUS_RETRY_DELAY={"等待重试","施法失败，等待配置的重试间隔"},
 CONTINUOUS_RETRY_CLOCK_UNKNOWN={"重试时钟未知","等待公开时钟后重新计时"},
 RUNTIME_SETTINGS_STANDBY={"设置中","关闭设置后重新确认派发"},
 RUNTIME_COMBAT_UNKNOWN={"战斗状态未知","暂不派发，等待公开战斗状态"},
 RUNTIME_PROFILE_UNCONFIGURED={"方案未配置","请选择有效方案"},
 RUNTIME_AUTO_STANDBY={"自动待命","等待进入战斗"},
 RUNTIME_MANUAL_START_REQUIRED={"手动待命","脱战派发需手动开启"},
 RUNTIME_OUT_OF_COMBAT_STOP={"脱战待命","战斗来源等待进入战斗"},
 MAINTENANCE_IDLE={"增益已维护","当前没有需要补充的增益"},
 MANUAL_TAKEOVER_PAUSED={"手动接管","等待手动接管结束"},
 CONTINUOUS_TEXT_FOCUS_OR_UNKNOWN={"输入受阻","输入焦点被占用或状态未知"},
 CONTINUOUS_TARGET_UNKNOWN_OR_BLOCKED={"目标受阻","目标无效、死亡或状态未知"},
 CONTINUOUS_RANGE_UNKNOWN_OR_BLOCKED={"距离受阻","超出技能范围或距离未知"},
 CONTINUOUS_USABLE_UNKNOWN_OR_BLOCKED={"技能受阻","技能不可用、资源不足或状态未知"},
 TEK_EXACT_DIRECT_BINDING_UNAVAILABLE={"缺少键位","未找到已核对的技能或宏按键"},
 APL_NO_CANDIDATE={"无符合技能","当前策略没有符合条件的技能"},
 SEQUENCE_POLICY_ALL_BLOCKED={"条件未满足","等待列表技能策略条件满足"},
 SEQUENCE_POLICY_UNKNOWN={"条件未知","无法确认策略条件，暂不派发"},
 SKIP_ALL_UNAVAILABLE={"暂无可用技能","列表技能均不可用，等待恢复"},
}
function H:StatusText(v)
 local reason=S.Public(v.reason,"string") or ""
 if v.state=="paused" then return "已暂停","派发已关闭，显示默认推荐",false end
 if v.state=="completed" then return "已完成","当前列表已执行完成",false end
 if v.state=="error" then return "运行异常","派发已停止，请查看诊断",false end
 local castGate=reason=="CONTINUOUS_CAST_PRESENT_OR_UNKNOWN" or reason=="TEK_CAST_PRESENT_OR_UNKNOWN"
 if castGate or v.state=="running" then
  local cast=self.castVisual
  if cast and not cast.unknown and cast.engine==self.engine and cast.generation==self.engine.generation then
   local ok,raw=S.Call("GetTime"); local now=ok and S.Public(raw,"number")
   if now and now>=cast.start and now<cast.finish then
    return cast.label=="引导" and "正在引导" or "正在施法","等待当前技能的精确成功回执",false
   end
  end
  if castGate then
   if cast and cast.unknown then return "施法状态未知","无法公开确认施法信息，暂不派发",true end
   return "等待施法结束","施法门禁尚未解除，等待重新确认",false
  end
 end
 local detail=v.detail or TEF.Dispatch:BlockDetail(reason)
 if detail then return detail.title,detail.description,detail.unknown end
 if reason:match("^UNKNOWN:custom:") then return "条件未知","无法确认当前技能的策略条件，请在编辑器只读采样查看具体条件",true end
 local entry=statusReasons[reason]
 if entry then return entry[1],entry[2],reason=="RUNTIME_COMBAT_UNKNOWN" or reason=="SEQUENCE_POLICY_UNKNOWN" end
 if v.state=="blocked" then
  if reason:find("WAIT_CURRENT_RECEIPT",1,true) or reason=="GROUP_WAIT_STEP_FINISH" or reason=="SEQUENCE_POLICY_WAIT_RECEIPT" then
   return "等待回执","等待当前技能的精确成功回执",false
  end
  local category,description=self:BlockCategory(reason)
  return category .. "受阻",description,false
 end
 if v.state=="standby" then return "待命中","等待运行条件满足",false end
 return "运行中","按当前方案派发，成功回执后推进",false
end
-- Visual-only, unprotected frames. No secure click proxy or input authority.
local function texture(parent, layer)
    local ok,t=U:Invoke(parent,"CreateTexture",nil,layer or "ARTWORK")
    return ok and t or nil
end
local function anchor(object,parent,x,y,width,height)
 U:Paint(object,"ClearAllPoints"); U:Paint(object,"SetPoint","TOPLEFT",parent,"TOPLEFT",x,y)
 if width then U:Paint(object,"SetWidth",width) end
 if height then U:Paint(object,"SetHeight",height) end
end
local media="Interface\\AddOns\\Tactic Echo Forever\\Media\\"
-- 九宫格保留固定圆角与线宽；素材和图标遮罩共用同一轮廓。
function H:RoundSurface(frame,width,height,radius,fill,border)
 self.roundSurfaces=self.roundSurfaces or setmetatable({},{__mode="k"})
 local surface=self.roundSurfaces[frame] or {}; self.roundSurfaces[frame]=surface
 local xs,ys={0,radius,width-radius},{0,radius,height-radius}
 local widths,heights={radius,width-2*radius,radius},{radius,height-2*radius,radius}
 local uv={0,.25,.75,1}
 for _,layer in ipairs({{"fill",fill,"HUDRoundedFill.tga","BACKGROUND"},{"border",border,"HUDRoundedBorder.tga","OVERLAY"}}) do
  if layer[2] then
   surface[layer[1]]=surface[layer[1]] or {}
   for row=1,3 do for col=1,3 do
    local i=(row-1)*3+col; local part=surface[layer[1]][i]
    if not part then part=texture(frame,layer[4]); surface[layer[1]][i]=part; U:Paint(part,"SetTexture",media .. layer[3]) end
    U:Paint(part,"SetTexCoord",uv[col],uv[col+1],uv[row],uv[row+1])
    anchor(part,frame,xs[col],-ys[row],math.max(0,widths[col]),math.max(0,heights[row]))
    U:Paint(part,widths[col]>0 and heights[row]>0 and "Show" or "Hide")
   end end
  end
 end
end
function H:SurfaceColor(frame,layer,r,g,b,a)
 local surface=self.roundSurfaces and self.roundSurfaces[frame]
 for _,part in ipairs(surface and surface[layer] or {}) do U:Paint(part,"SetVertexColor",r,g,b,a) end
 if layer=="border" then U:Call(frame,"SetBackdropBorderColor",r,g,b,a) end
end
function H:ApplyOpacity()
 local opacity=self.engine.db.hud.opacity
 -- 只修改HUD外壳贴图，不能使用父级透明度影响技能图标和文字。
 self:SurfaceColor(self.chrome,"fill",.025,.045,.075,opacity.background)
 self:SurfaceColor(self.chrome,"border",.30,.62,.88,opacity.border)
 self:SurfaceColor(self.chromeInner,"border",.13,.30,.47,.65*opacity.border)
end
local function mask(icon,parent)
 local ok,m=U:Invoke(parent,"CreateMaskTexture",nil,"ARTWORK")
 if ok and m then
  U:Paint(m,"SetTexture",media .. "HUDIconMask.tga","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
  U:Paint(m,"SetAllPoints",icon); U:Paint(icon,"AddMaskTexture",m)
 end
end
local function panel(parent)
 local f=U:Frame("Frame",parent,"BackdropTemplate"); U:Paint(f,"EnableMouse",false); return f
end
local quickRows={{source="apl",label="[A]",name="优先级推荐",color={.25,.85,1}},
 {source="manual",label="[S]",name="列表循环",color={.7,.45,1}}}
local quickSlots={"single","multi","third"}
function H:SelectQuickPlan(source,slot)
 source=S.Public(source,"string"); slot=S.Public(slot,"string")
 local e=self.engine
 if not e or not ({apl=true,manual=true})[source] or not ({single=true,multi=true,third=true})[slot] then return false end
 if not e.db.enabledPlans[source] or e.db.enabledPlans[source][slot]~=true then return false end
 if TEF.Recommendation:BaseSource(e)==source and e.scene==slot then return true end
 local ok=TEF.Profiles:UsePlan(e,source,slot)
 if ok then U:Refresh() end
 return ok
end
function H:CreateQuickPlans()
 self.quickPlans=U:Frame("Frame",self.frame)
 U:Paint(self.quickPlans,"SetFrameLevel",self.baseLevel+20)
 self.quickPlanRows={}
 for rowIndex,spec in ipairs(quickRows) do
  local row={label=U:Text(self.quickPlans,0,-(rowIndex-1)*13,14,"GameFontHighlightSmall"),buttons={}}
  U:ApplyControlFont(row.label,false,8); U:Paint(row.label,"SetText",spec.label)
  U:Paint(row.label,"SetTextColor",spec.color[1],spec.color[2],spec.color[3],1)
  self.quickPlanRows[rowIndex]=row
  for index,slot in ipairs(quickSlots) do
   local source,plan=spec.source,slot
   local button=U:Frame("Button",self.quickPlans,"BackdropTemplate")
   row.buttons[index]=button
   anchor(button,self.quickPlans,16+(index-1)*13,-(rowIndex-1)*13,10,10)
   U:Paint(button,"RegisterForClicks","LeftButtonUp")
   self:RoundSurface(button,10,10,1,true,true)
   U:Paint(button,"SetScript","OnClick",function(_,rawButton)
    if S.Public(rawButton,"string")=="LeftButton" then U:Guard(function() self:SelectQuickPlan(source,plan) end) end
   end)
   U:Paint(button,"SetScript","OnEnter",function()
    button.quickHover=true; self:RefreshQuickPlans()
    local e=self.engine; local enabled=e.db.enabledPlans[source][plan]==true
    local selected=TEF.Recommendation:BaseSource(e)==source and e.scene==plan
    U:Call(GameTooltip,"SetOwner",button,"ANCHOR_RIGHT")
    U:Call(GameTooltip,"AddLine",spec.name .. " / " .. TEF.Profiles:PlanName(plan,e,source))
    U:Call(GameTooltip,"AddLine",not enabled and "方案未启用，请在设置中启用" or selected and "当前使用的方案" or "点击切换方案；切换后停止派发，需手动开启",.75,.85,.95,true)
    U:Call(GameTooltip,"Show")
   end)
   U:Paint(button,"SetScript","OnLeave",function()
    button.quickHover=false; self:RefreshQuickPlans()
    local ok,owner=U:Invoke(GameTooltip,"GetOwner")
    if ok and owner==button then U:Call(GameTooltip,"Hide") end
   end)
   U:Paint(button,"SetScript","OnHide",function()
    button.quickHover=false
    local ok,owner=U:Invoke(GameTooltip,"GetOwner")
    if ok and owner==button then U:Call(GameTooltip,"Hide") end
   end)
  end
 end
end
function H:RefreshQuickPlans()
 if not self.quickPlans then return end
 U:Paint(self.quickPlans,self.displayMode=="mini" and "Hide" or "Show")
 local e=self.engine; local source=TEF.Recommendation:BaseSource(e)
 for rowIndex,spec in ipairs(quickRows) do
  for index,slot in ipairs(quickSlots) do
   local button=self.quickPlanRows[rowIndex].buttons[index]
   local enabled=e.db.enabledPlans[spec.source][slot]==true
   local selected=enabled and source==spec.source and e.scene==slot
   button.quickSelected=selected; button.quickEnabled=enabled
   local c=enabled and spec.color or {.25,.3,.36}
   local fill=selected and .8 or button.quickHover and .24 or .09
   local border=selected and 1 or button.quickHover and .8 or .35
   if spec.source=="manual" and not selected then
    fill=enabled and (button.quickHover and .44 or .30) or .15
    border=enabled and (button.quickHover and 1 or .8) or .55
   end
   self:SurfaceColor(button,"fill",c[1]*fill,c[2]*fill,c[3]*fill,1)
   self:SurfaceColor(button,"border",c[1]*border,c[2]*border,c[3]*border,1)
  end
 end
end
function H:SetMode(mode)
 mode=S.Public(mode,"string")
 if (mode~="standard" and mode~="mini") or U:Combat()~=false or not self.engine then return false end
 self.engine.db.hud.mode=mode
 self:Layout(); self:Refresh()
 if U.settingsOpen and U.page=="hud" and U.engine==self.engine then U:RefreshPage() end
 return true
end
function H:CreateModeButton()
 local button=U:Frame("Button",self.frame)
 self.modeButton=button
 U:Paint(button,"SetFrameLevel",self.baseLevel+20)
 U:Paint(button,"RegisterForClicks","LeftButtonUp")
 U:Paint(button,"SetScript","OnClick",function(_,rawButton)
  if S.Public(rawButton,"string")=="LeftButton" then
   U:Guard(function() self:SetMode(self.displayMode=="mini" and "standard" or "mini") end)
   U:Call(GameTooltip,"Hide")
  end
 end)
 U:Paint(button,"SetScript","OnEnter",function()
  U:Call(GameTooltip,"SetOwner",button,"ANCHOR_RIGHT")
  U:Call(GameTooltip,"AddLine",self.displayMode=="mini" and "切换为标准HUD" or "切换为迷你HUD")
  U:Call(GameTooltip,"AddLine","脱战可用；保留派发意图与列表进度。",.7,.8,.9,true)
  U:Call(GameTooltip,"Show")
 end)
 U:Paint(button,"SetScript","OnLeave",function() U:Call(GameTooltip,"Hide") end)
 for i=1,2 do
  local line=texture(button,"ARTWORK"); anchor(line,button,2,-(i*2+1),4,1)
  U:Paint(line,"SetColorTexture",.65,.88,1,1)
 end
end
function H:CreateChrome()
 local ok,raw=U:Invoke(self.frame,"GetFrameLevel"); self.baseLevel=(ok and S.Public(raw,"number") or 1)
 self.chrome=panel(self.frame); U:Paint(self.chrome,"SetAllPoints",self.frame)
 U:Paint(self.chrome,"SetFrameLevel",self.baseLevel+1)
 self.chromeInner=panel(self.frame); anchor(self.chromeInner,self.frame,1,-1,258,86)
 U:Paint(self.chromeInner,"SetFrameLevel",self.baseLevel+1)
 self.content=U:Frame("Frame",self.frame); U:Paint(self.content,"SetAllPoints",self.frame)
 U:Paint(self.content,"SetFrameLevel",self.baseLevel+3); U:Paint(self.content,"EnableMouse",false); U:Paint(self.content,"SetClipsChildren",true)
 self.badge=panel(self.content); self.badgeText=U:Text(self.badge,8,-7,88,"GameFontHighlightSmall")
 U:Paint(self.badgeText,"SetJustifyH","LEFT")
 self.statusDot=texture(self.content,"ARTWORK"); U:Paint(self.statusDot,"SetTexture",media .. "HUDStatusDot.tga")
 self.countText=U:Text(self.content,170,-68,114,"GameFontHighlightSmall"); U:Paint(self.countText,"SetJustifyH","RIGHT")
 self.role=U:Text(self.content,100,-86,176,"GameFontHighlightSmall")
 self.castBar=U:Frame("StatusBar",self.content,"BackdropTemplate")
 U:Paint(self.castBar,"SetStatusBarTexture","Interface\\Buttons\\WHITE8X8")
 U:Paint(self.castBar,"SetStatusBarColor",.25,.8,1,.95); U:Paint(self.castBar,"SetMinMaxValues",0,1)
 self.castTrack=texture(self.content,"BACKGROUND"); U:Paint(self.castTrack,"SetColorTexture",.14,.23,.34,1)
 U:Paint(self.castBar,"EnableMouse",false)
 self.castText=U:Text(self.castBar,8,-4,250,"GameFontHighlightSmall")
 self.castTime=U:Text(self.castBar,300,-4,100,"GameFontHighlightSmall"); U:Paint(self.castTime,"SetJustifyH","RIGHT")
 self.textSlots={}
 for _,key in ipairs({"name","status"}) do
  local f=U:Frame("Frame",self.content); U:Paint(f,"EnableMouse",false); self.textSlots[key]={frame=f}
 end
 for _,text in ipairs({self.badgeText,self.role,self.castText,self.castTime,self.countText}) do
  U:Paint(text,"SetWordWrap",false); U:Paint(text,"SetMaxLines",1)
 end
end
-- 只缓存公开的玩家施法显示信息，不参与资格、推进或回执判断。
function H:ReadCastVisual()
 local unknown=false; local label
 self.castVisual=nil
 for _,entry in ipairs({{"UnitCastingInfo","施法"},{"UnitChannelInfo","引导"}}) do
  local fn=S.Resolve(entry[1]); local ok,name,castText,castIcon,startMS,endMS
  if fn then ok,name,castText,castIcon,startMS,endMS=pcall(fn,"player") end
  local public,why=S.Public(name,"string")
  if ok and public then
   label=entry[2]
   local start,finish=S.Public(startMS,"number"),S.Public(endMS,"number")
   if start and finish and start>=0 and finish<=1e12 and finish>start and finish-start<=3600000 then
    self.castVisual={name=public,label=label,start=start/1000,finish=finish/1000,engine=self.engine,generation=self.engine.generation}
   else self.castVisual={unknown=true,label=label} end
  elseif not ok or why~="NO_DATA" then unknown=true end
 end
 if unknown then self.castVisual={unknown=true,label=label} end
 return label
end
function H:PaintCastVisual(progressOnly)
 if not self.castBar then return end
 local data=self.castVisual; local value,time,text=0,"",self.idleCastText or "等待施法信息"
 if data and data.unknown then text=(data.label or "施法") .. "信息未知"
 elseif data then
  local ok,raw=S.Call("GetTime"); local now=ok and S.Public(raw,"number")
  if data.engine~=self.engine or data.generation~=self.engine.generation then text="等待状态更新"
  elseif not now or now<0 or now>1e9 then text="施法时间未知"
  elseif now>=data.finish then text="等待状态更新"
  elseif now<data.start then text="等待施法时间同步"
  else
   local duration=data.finish-data.start; local elapsed=now-data.start
   value=data.label=="引导" and 1-elapsed/duration or elapsed/duration
   if not progressOnly then
    time=string.format("%.1f / %.1f秒",data.label=="引导" and duration-elapsed or elapsed,duration)
    text=data.label .. "中 · " .. U:ShortLabel(data.name,8)
   end
  end
 end
 U:Paint(self.castBar,"SetValue",value)
 if progressOnly then return end
 U:Paint(self.castText,"SetText",text); U:Paint(self.castTime,"SetText",time)
end
function H:Card(x,size,primary)
    local f=U:Frame(primary and "Button" or "Frame",self.content or self.frame,nil)
    U:Paint(f,"SetFrameLevel",self.baseLevel+4)
    U:Paint(f,"SetSize",size,size); U:Paint(f,"SetPoint","TOPLEFT",self.frame,"TOPLEFT",x,-8)
    local icon=texture(f); U:Paint(icon,"SetPoint","TOPLEFT",f,"TOPLEFT",3,-3)
    U:Paint(icon,"SetPoint","BOTTOMRIGHT",f,"BOTTOMRIGHT",-3,3); U:Paint(icon,"SetTexCoord",.08,.92,.08,.92); mask(icon,f)
    local borderFrame=U:Frame("Frame",f,"BackdropTemplate"); U:Call(borderFrame,"SetAllPoints",f)

    local border=borderFrame
    local clipped=U:Frame("Frame",f); U:Call(clipped,"SetAllPoints",f); U:Call(clipped,"SetClipsChildren",true)
    local cooldown=U:Frame("Cooldown",clipped,"CooldownFrameTemplate")
    U:Call(cooldown,"SetAllPoints",icon); U:Call(cooldown,"SetHideCountdownNumbers",true)
    U:Call(cooldown,"SetSwipeTexture",media .. "HUDIconMask.tga"); U:Call(cooldown,"SetDrawBling",false); U:Call(cooldown,"SetDrawEdge",false)
    local texts=U:Frame("Frame",f); U:Call(texts,"SetAllPoints",f)
    U:Call(clipped,"SetFrameLevel",self.baseLevel+5); U:Call(cooldown,"SetFrameLevel",self.baseLevel+6)
    U:Call(borderFrame,"SetFrameLevel",self.baseLevel+8); U:Call(texts,"SetFrameLevel",self.baseLevel+10)
    local key=primary and U:Text(texts,3,-3,size-6,"GameFontNormalSmall") or nil
    local overlay=texture(texts,"OVERLAY"); U:Call(overlay,"SetAllPoints",icon); U:Call(overlay,"SetColorTexture",1,1,1,0); mask(overlay,texts)
    U:Call(borderFrame,"EnableMouse",false); U:Call(clipped,"EnableMouse",false); U:Call(texts,"EnableMouse",false)
    local card={frame=f,textParent=texts,size=size,icon=icon,border=border,overlay=overlay,cooldown=cooldown,key=key}
    if primary then
        card.keycap=panel(f); U:Paint(card.keycap,"SetFrameLevel",self.baseLevel+9)
        U:Call(f,"RegisterForClicks","LeftButtonUp","RightButtonUp")
        U:Call(f,"SetScript","OnClick",function(_,rawButton)
            U:Guard(function()
                if self.dragging then return end
                local button=S.Public(rawButton,"string")
                if button=="LeftButton" then TEF_ToggleDispatchIntent()
                elseif button=="RightButton" then U:OpenSettings() end
            end)
        end)
        U:Call(f,"SetScript","OnEnter",function()
            card.hover=true; self:RefreshState()
            U:Call(GameTooltip,"SetOwner",f,"ANCHOR_RIGHT")
            U:Call(GameTooltip,"AddLine",self.primaryFullName or "TACTIC ECHO FOREVER")
            U:Call(GameTooltip,"AddLine","左键：派发启/停；右键：设置",1,1,1)
            local state=TEF.Runtime:GetViewState()
            U:Call(GameTooltip,"AddLine","当前：" .. state.label,.7,.8,.9)
            if state.state=="blocked" then
                local category,description=self:StatusText(state)
                U:Call(GameTooltip,"AddLine","阻断分类：" .. category .. " · " .. description,1,.78,.28,true)
                local code=S.Public(state.reason,"string")
                if code then U:Call(GameTooltip,"AddLine","原因码：" .. code,.7,.7,.7) end
            end
            self:TooltipDetails(card)
            U:Call(GameTooltip,"AddLine","不会直接施法",.7,.7,.7); U:Call(GameTooltip,"Show")
        end)
        U:Call(f,"SetScript","OnLeave",function() card.hover=false; card.pressed=false; self:RefreshState(); U:Call(GameTooltip,"Hide") end)
        U:Call(f,"SetScript","OnMouseDown",function() card.pressed=true; self:RefreshState() end)
        U:Call(f,"SetScript","OnMouseUp",function() card.pressed=false; self:RefreshState() end)
    end
    return card
end
function H:TooltipDetails(card)
 local step=card.displayStep
 if step then U:Call(GameTooltip,"AddLine","SpellID " .. step.spellID,.7,.8,.9) end
 local e=self.engine
 local source=e.maintenanceActive and "增益维护" or e.groupRun and "技能组" or TEF.Recommendation:Source(e)=="apl" and "优先级推荐" or "固定序列"
 local plan=e.maintenanceActive and "全局列表" or TEF.Profiles:PlanName(e.scene,e,TEF.Recommendation:BaseSource(e))
 U:Call(GameTooltip,"AddLine",source .. " / " .. plan,.7,.8,.9,true)
 if self.rangeDescription then U:Call(GameTooltip,"AddLine",self.rangeDescription,.7,.8,.9,true) end
 for _,field in ipairs({self.castText,self.castTime}) do
  local ok,raw=U:Invoke(field,"GetText"); local text=ok and S.Public(raw,"string")
  if text and text~="" then U:Call(GameTooltip,"AddLine",text,.7,.8,.9,true) end
 end
 local group=e.groupRun
 if group then U:Call(GameTooltip,"AddLine",group.group.name .. " · 第" .. group.round .. "/" .. group.group.rounds .. "轮",.7,.8,.9,true) end
 if TEF.Recommendation:Source(e)=="apl" then U:Call(GameTooltip,"AddLine","只读候选预览，不代表施放顺序。",.7,.8,.9,true) end
 if step then U:Call(GameTooltip,"AddLine","本步成功 " .. (e.stepCasts or 0) .. "/" .. (step.repeatCount or 1) .. "次",.7,.8,.9) end
 if card.fullKeyText then U:Call(GameTooltip,"AddLine","键位：" .. card.fullKeyText,.7,.8,.9) end
end
function H:CompactVisibility()
 local mini=self.displayMode=="mini"
 local styles=self.engine.db.hud.styles.global
 U:Paint(self.name,not mini and styles.name.enabled and "Show" or "Hide")
 U:Paint(self.status,not mini and "Show" or "Hide")
 U:Paint(self.badge,mini and "Hide" or "Show")
 local count=not mini or (styles.status.enabled and TEF.Recommendation:Source(self.engine)~="apl")
 U:Paint(self.countText,count and "Show" or "Hide")
 U:Paint(self.miniCountChip,mini and count and "Show" or "Hide")
 for _,field in ipairs({self.role,self.castText,self.castTime}) do U:Paint(field,mini and "Hide" or "Show") end
end
function H:Layout()
 if not self.frame then return end
 if U:Combat()~=false then self.pending=true; return end
 self.pending=false; self.displayMode=self.engine.db.hud.mode=="mini" and "mini" or "standard"
 local mini=self.displayMode=="mini"
 local width,height=mini and 156 or 260,mini and 60 or 108
 self.layoutWidth=width; self.layoutHeight=height
 local g=self.engine.db.hud.geometry
 local sizes=mini and {44,36,36} or {math.min(44,g.mainSize),math.min(36,g.preview1Size),math.min(36,g.preview2Size)}
 local gap=math.min(4,g.gap2); local previewX=254-sizes[2]-sizes[3]-gap
 local nameX=6+sizes[1]+math.min(6,g.gap1)
 local scale=math.min(1,self.engine.db.hud.scale)
 for _,axis in ipairs({{"GetWidth",width},{"GetHeight",height}}) do
  local ok,raw=U:Invoke(UIParent,axis[1]); local available=ok and S.Public(raw,"number")
  if available and available>16 then scale=math.min(scale,(available-16)/axis[2]) end
 end
 U:Paint(self.frame,"SetScale",scale); U:Paint(self.frame,"SetSize",width,height)
 self:RoundSurface(self.chrome,width,height,8,true,true)
 anchor(self.chromeInner,self.frame,1,-1,width-2,height-2)
 self:RoundSurface(self.chromeInner,width-2,height-2,7,false,true); self:ApplyOpacity()
 local xs=mini and {6,62,108} or {6,previewX,previewX+sizes[2]+gap}
 for i,card in ipairs(self.cards or {}) do
  card.size=sizes[i]; anchor(card.frame,self.frame,xs[i],mini and (i==1 and -6 or -10) or (i==1 and -8 or -12),sizes[i],sizes[i])
  self:RoundSurface(card.frame,sizes[i],sizes[i],i==1 and 6 or 4,true,false)
  self:SurfaceColor(card.frame,"fill",.025,.045,.07,1)
  self:RoundSurface(card.border,sizes[i],sizes[i],i==1 and 6 or 4,false,true)
  self:SurfaceColor(card.border,"border",i==1 and .3 or .25,i==1 and .8 or .4,i==1 and 1 or .55,1)
 end
 local badgeWidth=math.max(32,previewX-nameX-74)
 anchor(self.badge,self.content,nameX+14,-30,badgeWidth,18)
 anchor(self.badgeText,self.badge,0,0,badgeWidth,18)
 -- 两排总高23，以预览图标的水平中轴线居中。
 anchor(self.quickPlans,self.frame,previewX-58,-(12+sizes[2]/2-23/2),58,23)
 anchor(self.statusDot,self.content,nameX,-34,8,8)
 anchor(self.castBar,self.content,6,-54,248,3)
 anchor(self.castTrack,self.content,6,-54,248,3)
 anchor(self.castText,self.content,6,-58,142,16)
 anchor(self.castTime,self.content,152,-58,102,16)
 anchor(self.role,self.content,6,-90,248,16)
 for _,field in ipairs({self.castText,self.castTime,self.role}) do U:ApplyControlFont(field,false,12) end
 anchor(self.countText,self.content,132,-74,122,16)
 local slots={name={nameX,-10,previewX-nameX-62,20},status={6,-74,120,16}}
 for key,values in pairs(slots) do local slot=self.textSlots[key]; slot.width=values[3]; anchor(slot.frame,self.content,unpack(values)) end
 local top=self.cards[1].textParent
 U:Paint(self.statusDot,"SetParent",mini and top or self.content)
 U:Paint(self.countText,"SetParent",mini and top or self.content)
 self.countTextParent=mini and top or self.content
 if mini then
  anchor(self.statusDot,top,5,-34,6,6)
  anchor(self.countText,top,11,-29,32,14)
  anchor(self.castBar,self.content,8,-54,140,2); anchor(self.castTrack,self.content,8,-54,140,2)
 end
 anchor(self.miniCountChip,self.cards[1].frame,11,-29,32,14)
 self:RoundSurface(self.miniCountChip,32,14,3,true,false)
 self:SurfaceColor(self.miniCountChip,"fill",.015,.03,.055,.96)
 anchor(self.modeButton,self.frame,width-10,-2,8,8)
 self:RoundSurface(self.modeButton,8,8,2,true,true)
 self:SurfaceColor(self.modeButton,"fill",.035,.10,.16,1)
 self:SurfaceColor(self.modeButton,"border",.3,.62,.88,1)
 TEF.HudStyles:Apply(self); self:RefreshState()
end
function H:Create(e)
    self.engine=e; self.frame=U:Frame("Frame",UIParent,nil,"TEF_DeliveryHUD")
    if not self.frame then return end
    U:Paint(self.frame,"SetSize",260,88); U:Paint(self.frame,"SetPoint","CENTER",UIParent,"CENTER",e.db.hud.x or 0,e.db.hud.y or -155)
    U:Paint(self.frame,"SetClampedToScreen",true); U:Paint(self.frame,"SetMovable",true)
    U:Paint(self.frame,"EnableMouse",true); U:Paint(self.frame,"RegisterForDrag","LeftButton")
    U:Paint(self.frame,"SetScript","OnDragStart",function()
        if U:Combat()==false and not self.engine.db.hud.locked then self.dragging=true; U:Call(self.frame,"StartMoving") end
    end)
    U:Paint(self.frame,"SetScript","OnDragStop",function()
        if not self.dragging then return end
        self.dragging=false; U:Call(self.frame,"StopMovingOrSizing")
        local ok,rawX,rawY=U:Invoke(self.frame,"GetCenter")
        local parentOK,rawPX,rawPY=U:Invoke(UIParent,"GetCenter")
        local scaleOK,rawScale=U:Invoke(self.frame,"GetEffectiveScale")
        local parentScaleOK,rawParentScale=U:Invoke(UIParent,"GetEffectiveScale")
        local x=ok and S.Public(rawX,"number"); local y=ok and S.Public(rawY,"number")
        local px=parentOK and S.Public(rawPX,"number"); local py=parentOK and S.Public(rawPY,"number")
        local scale=scaleOK and S.Public(rawScale,"number"); local parentScale=parentScaleOK and S.Public(rawParentScale,"number")
        if not x or not y or not px or not py or not scale or not parentScale or scale<=0 or parentScale<=0 then return end
        x=x-px*parentScale/scale; y=y-py*parentScale/scale
        if x and y and math.abs(x)<=10000 and math.abs(y)<=10000 then self.engine.db.hud.x=x; self.engine.db.hud.y=y end
    end)
    self:CreateChrome()
    self.cards={self:Card(8,64,true),self:Card(84,44),self:Card(140,44)}
    self.miniCountChip=panel(self.cards[1].frame); U:Paint(self.miniCountChip,"SetFrameLevel",self.baseLevel+9)
    self:CreateModeButton()
    self:CreateQuickPlans()
    self.name=U:Text(self.textSlots.name.frame,0,0,230,"GameFontHighlightSmall")
    self.status=U:Text(self.textSlots.status.frame,0,0,230,"GameFontHighlightSmall")
    -- 将原显示心跳移到独立载体：隐藏HUD和关闭信号不影响设置中的只读追踪。
    self.heartbeat=U:Frame("Frame",UIParent)
    U:Call(self.heartbeat,"SetScript","OnUpdate",function(_,rawElapsed)
        local elapsed=S.Public(rawElapsed,"number")
        if not elapsed or elapsed<0 then return end
        self.traceElapsed=(self.traceElapsed or 0)+elapsed
        if self.traceElapsed>=.05 then
            self.traceElapsed=self.traceElapsed%.05
            if U.settingsOpen and U.studioTraceLive then U:Guard(U.MaybeStudioLiveProbe,U) end
        end
        local ok,shown=U:Invoke(self.frame,"IsVisible")
        if ok and S.Public(shown,"boolean")==false then return end
        -- 每帧只插值缓存的公开施法时间；其他显示查询仍保持原节拍。
        self:PaintCastVisual(true)
        self.elapsed=(self.elapsed or 0)+elapsed
        if self.elapsed>=.25 then self.elapsed=self.elapsed%.25; self:VisualTick() end
    end)
    self:Layout(); self:Refresh()
end
function H:Refresh(cooldownEvent)
    local e=self.engine; if not self.frame then return end
    self.metadata=self.metadata or {}
    local display=TEF.Recommendation:HUDSteps(e)
    for i,card in ipairs(self.cards) do
        local index=e.index+i-1
        if e.db.loop and e.steps and index>#e.steps then index=(index-1)%#e.steps+1 end
        local step=e.steps and e.steps[index]
        if display then step=display[i] end
        if i>1 and ((e.completed and not e.groupRun) or not e.db.hud.preview or (TEF.APL:IsActive(e) and not display)) then step=nil end
        local key=step and (step.spellID .. ":" .. step.name)
        local view=key and self.metadata[key]
        if step and not view then view=S.Spell(step.spellID,step.name); self.metadata[key]=view end
        if not U:Paint(card.icon,"SetTexture",view and view.icon or TEF.Placeholder) then U:Call(card.icon,"SetTexture",TEF.Placeholder) end
        card.displayStep=step
        if TEF.Presentation then TEF.Presentation:Paint(card,step,cooldownEvent) end
        if i==1 then local ok,raw=U:Invoke(card.key,"GetText"); card.fullKeyText=ok and S.Public(raw,"string") or nil end
    end
    local step=display and display[1] or (e.steps and e.steps[e.index])
    local view=step and self.metadata[step.spellID .. ":" .. step.name]
    self.primaryFullName=(e.completed and not e.groupRun) and "完成" or (view and view.name or (TEF.APL:IsActive(e) and TEF.APL.Trace:Waiting(e) or "未配置推荐序列"))
    local style=e.db.hud.styles.global.name
    local limit=math.max(3,math.floor((self.textSlots.name.width or 140)/TEF.HudStyles.EffectiveSize(style,14))-1)
    local name=U:ShortLabel(self.primaryFullName,limit+1)
    if name~=self.primaryFullName then name=U:ShortLabel(self.primaryFullName,limit) end
    U:Paint(self.name,"SetText",name)
    self:RefreshState()
end
H.colors={paused={.48,.52,.60},standby={.36,.78,.90},running={.22,.96,.56},blocked={.96,.72,.18},completed={.96,.83,.45},error={1,.25,.25}}
function H:RefreshState()
    if not self.frame or not self.cards then return end
    local e=self.engine; local v=TEF.Runtime:GetViewState()
    local step=e.steps and e.steps[e.index]
    if TEF.Runtime.e~=e then v={state=e.running and "running" or "paused",label=e.running and "推荐" or "暂停"} end
    if e.completed and not e.groupRun then v.state="completed"; v.label="完成" end
    local c=self.colors[v.state] or self.colors.paused
    local primary=self.cards[1]
    self:SurfaceColor(primary.border,"border",.3,.8,1,1)
    U:Paint(primary.overlay,"SetColorTexture",c[1],c[2],c[3],primary.pressed and .22 or primary.hover and .12 or .025)
    self:ReadCastVisual()
    for i,card in ipairs(self.cards) do
        if i>1 then U:Paint(card.frame,card.displayStep and e.db.hud.preview and "Show" or "Hide") end
    end
    local apl=TEF.Recommendation:Source(e)=="apl"
    local badge,description,unknown=self:StatusText(v)
    local tint=unknown and {.72,.62,.96} or c
    local shortBadge=({["等待施法结束"]="施法收尾",["施法状态未知"]="施法未知",["战斗状态未知"]="战斗未知",
        ["暂无可用技能"]="暂无可用",["无符合技能"]="暂无推荐",["方案未配置"]="方案缺失"})[badge] or U:ShortLabel(badge,4)
    U:Paint(self.badgeText,"SetText",shortBadge)
    U:Paint(self.badgeText,"SetTextColor",tint[1],tint[2],tint[3],1)
    U:Paint(self.statusDot,"SetVertexColor",tint[1],tint[2],tint[3],1)
    U:Paint(self.role,"SetText",U:ShortLabel(description,20))
    U:Paint(self.role,"SetTextColor",v.state=="blocked" and tint[1] or .45,v.state=="blocked" and tint[2] or .8,v.state=="blocked" and tint[3] or 1,1)
    self.idleCastText=badge
    self:PaintCastVisual()
    if apl then
        U:Paint(self.status,"SetText",e.maintenanceActive and "增益维护" or "优先级推荐")
        U:Paint(self.countText,"SetText","候选预览")
    else
        U:Paint(self.status,"SetText",(e.groupRun and "组内 " or "步骤 ") .. e.index .. "/" .. (e.steps and #e.steps or 0))
        U:Paint(self.countText,"SetText",(self.displayMode=="mini" and "" or "本步 ") .. (e.stepCasts or 0) .. "/" .. (step and step.repeatCount or 1))
    end
    local keyOK,keyRaw=U:Invoke(primary.key,"GetText"); local key=keyOK and S.Public(keyRaw,"string")
    if key and key~="" and key~="未解析" and key~="—" then
        -- 完整键位放入悬停；角标仅作紧凑显示。
        if not self.compactKey or key~=self.compactKey then primary.fullKeyText=key end
        local short=(primary.fullKeyText or key):gsub("SHIFT%-","S-"):gsub("CTRL%-","C-"):gsub("ALT%-","A-")
        local capWidth=math.min(primary.size-6,math.max(18,#short*6+6))
        self.compactKey=U:ShortLabel(short,math.max(1,math.floor((capWidth-4)/6)))
        U:Paint(primary.key,"SetText",self.compactKey)
        anchor(primary.keycap,primary.frame,primary.size-capWidth-2,-2,capWidth,18)
        self:RoundSurface(primary.keycap,capWidth,18,4,true,true)
        self:SurfaceColor(primary.keycap,"fill",.015,.03,.055,.96); self:SurfaceColor(primary.keycap,"border",.22,.5,.72,1)
        U:Paint(primary.key,"SetWidth",capWidth-4)
        U:Paint(primary.key,"SetHeight",18)
        U:Paint(primary.key,"ClearAllPoints")
        U:Paint(primary.key,"SetPoint","CENTER",primary.keycap,"CENTER",0,0)
        U:Paint(primary.key,"SetJustifyH","CENTER"); U:Paint(primary.key,"SetJustifyV","MIDDLE")
        U:Paint(primary.keycap,self.engine.db.hud.styles.main.key.enabled and "Show" or "Hide")
    else U:Paint(primary.keycap,"Hide"); U:Paint(primary.key,"SetText","") end
    self:CompactVisibility()
    self:RefreshQuickPlans()
end
function H:VisualTick()
    -- 复用显示节拍，距离及变色只读，不参与派发。
    self:PaintCastVisual()
    TEF.Presentation:UpdateRange(self)
end
