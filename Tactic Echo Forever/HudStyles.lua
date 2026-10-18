local _,TEF=...
local S,A=TEF.Safety,{}
TEF.HudStyles=A
local colors={{"白",1,1,1},{"黄",1,.82,.2},{"绿",.3,1,.55},{"蓝",.35,.7,1},{"红",1,.35,.35},{"灰",.65,.65,.65}}
local function number(raw,key,min,max,fallback)
 local n=S.Field(raw,key,"number")
 return n and math.max(min,math.min(max,n)) or fallback
end
function A.CleanGeometry(raw)
 return {mainSize=number(raw,"mainSize",32,112,64),preview1Size=number(raw,"preview1Size",24,96,44),
  preview2Size=number(raw,"preview2Size",24,96,44),gap1=number(raw,"gap1",2,40,12),gap2=number(raw,"gap2",2,40,12)}
end
local labels={{module="main",key="key",name="主卡键位",size=12,cap=10},
 {module="global",key="name",name="技能名称",size=16,cap=14},
 {module="global",key="status",name="进度行",size=14,cap=12}}
function A.Clean(raw)
 local out={main={},global={}}
 for _,label in ipairs(labels) do
  local group=S.Field(raw,label.module,"table"); local v=S.Field(group,label.key,"table")
  local c=S.Field(v,"color","table")
  out[label.module][label.key]={enabled=S.Field(v,"enabled","boolean")~=false,
   fontSize=number(v,"fontSize",8,30,label.size),scale=number(v,"scale",.6,2,1),
   fontPreset=S.Field(v,"fontPreset","string")=="disable" and "disable" or "normal",
   color={r=number(c,"r",0,1,1),g=number(c,"g",0,1,1),b=number(c,"b",0,1,1),a=number(c,"a",0,1,1)}}
 end
 return out
end
function A:Apply(hud)
 local U=TEF.UI
 if U:Combat()~=false then hud.pending=true; return end
 local styles=hud.engine.db.hud.styles
 local function paint(text,parent,v,width,cap,point,x,y)
  U:Paint(text,"SetFont",STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",math.min(cap,v.fontSize*v.scale),v.fontPreset=="disable" and "" or "OUTLINE")
  U:Paint(text,"SetTextColor",v.color.r,v.color.g,v.color.b,v.color.a)
  U:Paint(text,"SetScale",1); U:Paint(text,"ClearAllPoints"); U:Paint(text,"SetWidth",width)
  U:Paint(text,"SetPoint",point or "TOPLEFT",parent,point or "TOPLEFT",x or 0,y or 0)
  U:Paint(text,"SetJustifyH",point=="TOPRIGHT" and "RIGHT" or "LEFT")
  U:Paint(text,"SetWordWrap",false); U:Paint(text,"SetMaxLines",1)
  U:Paint(text,v.enabled and "Show" or "Hide")
 end
 local card=hud.cards[1]
 paint(card.key,card.textParent,styles.main.key,card.size-8,10,"TOPRIGHT",-4,-4)
 for _,key in ipairs({"name","status"}) do
  local slot=hud.textSlots[key]; paint(hud[key],slot.frame,styles.global[key],slot.width,key=="name" and 14 or 12)
 end
 U:ApplyControlFont(hud.badgeText,false,12)
 local progress=styles.global.status
 paint(hud.countText,hud.countTextParent or hud.content,progress,hud.displayMode=="mini" and 32 or 122,hud.displayMode=="mini" and 10 or 12,"TOPLEFT",hud.displayMode=="mini" and 11 or 132,hud.displayMode=="mini" and -29 or -74)
 U:Paint(hud.countText,"SetJustifyH","RIGHT")
 hud:CompactVisibility()
 for _,item in ipairs(hud.cards) do TEF.Presentation:PaintRange(item,item.displayStep) end
end
function A:BuildUI(U,parent)
 local selected=labels[1]
 local function current() return U.engine.db.hud.styles[selected.module][selected.key] end
 local function changed() TEF.HUD:Layout() end
 local choices={}; for _,label in ipairs(labels) do choices[#choices+1]={label.key,label.name} end
 U.labelStyleButtons=U:CreateSegmentedControl(parent,choices,0,0,548,function() return selected.key end,function(key)
  for _,label in ipairs(labels) do if label.key==key then selected=label; break end end
 end)
 local function fixedProgress() return U.engine.db.hud.mode~="mini" and selected.key=="status" end
 U.labelEnabledButton=U:CreateToggleRow(parent,"显示当前标签",0,-48,548,function() return fixedProgress() or current().enabled end,function(v)
  if fixedProgress() then return end
  current().enabled=v; changed()
 end)
 U:AddControlSync(function() U:SetControlEnabled(U.labelEnabledButton,not fixedProgress(),"标准HUD固定显示步骤与次数。") end,parent)
 U:CreateSegmentedControl(parent,{{"normal","描边"},{"disable","无描边"}},0,-96,548,
  function() return current().fontPreset end,function(v) current().fontPreset=v; changed() end)
 U:CreateSliderRow(parent,"字号",0,-152,548,8,30,1,function() return current().fontSize end,function(v) current().fontSize=v; changed() end,true)
 U:CreateSliderRow(parent,"标签缩放",0,-216,548,.6,2,.1,function() return current().scale end,function(v) current().scale=v; changed() end,true)
 for i,color in ipairs(colors) do U:CreateActionButton(parent,color[1],(i-1)*92,-280,80,function()
  current().color={r=color[2],g=color[3],b=color[4],a=1}; changed()
 end) end
 U:CreateActionButton(parent,"重置当前标签",360,-328,188,function()
  U:ConfirmAction("确认恢复当前标签的默认样式？其他标签保留。",function()
   U.engine.db.hud.styles[selected.module][selected.key]=A.Clean(nil)[selected.module][selected.key]; changed()
  end,"恢复标签")
 end)
 U:CreateHintText(parent,"仅设置实际显示的主卡键位、技能名称和进度行。标准HUD固定显示进度；迷你版隐藏名称，可关闭次数。位置采用固定布局。实际字号上限：键位10、名称14、进度12（迷你次数10）。",0,-376,548)
end
