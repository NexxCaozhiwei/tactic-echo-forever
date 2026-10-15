local _,TEF=...
local S,A=TEF.Safety,{}
TEF.HudStyles=A
-- Adapted from TE ControlPanel label controls and TacticalIconButton font
-- presentation. Independent scalar configuration, with no dispatch authority.
local points={TOPLEFT=true,TOPRIGHT=true,CENTER=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
local presets={normal=true,highlight=true,disable=true}
local defaults={
    key={12,"TOPRIGHT",-3,-3},chargeText={12,"BOTTOMRIGHT",-3,3},
    cooldownText={14,"CENTER",0,0},state={11,"BOTTOMLEFT",3,3},
    label={10,"TOPLEFT",3,-3},name={16,"TOPLEFT",8,-80},status={14,"TOPLEFT",8,-108},rangeText={12,"TOPLEFT",8,-132}}
local keys={"key","chargeText","cooldownText","state","label","name","status","rangeText"}
local colors={{"白",1,1,1},{"黄",1,.82,.2},{"绿",.3,1,.55},{"蓝",.35,.7,1},{"红",1,.35,.35},{"灰",.65,.65,.65}}
local function number(raw,key,min,max,fallback)
    local n=S.Field(raw,key,"number")
    if not n then return fallback end
    return math.max(min,math.min(max,n))
end
function A.CleanGeometry(raw)
    return {mainSize=number(raw,"mainSize",32,112,64),
        preview1Size=number(raw,"preview1Size",24,96,44),
        preview2Size=number(raw,"preview2Size",24,96,44),
        gap1=number(raw,"gap1",2,40,12),gap2=number(raw,"gap2",2,40,12)}
end
function A.Clean(raw)
    local out={}
    for _,module in ipairs({"main","preview","global"}) do
        out[module]={}; local source=S.Field(raw,module,"table")
        for _,key in ipairs(keys) do
            local d=defaults[key]; local v=S.Field(source,key,"table")
            local point=S.Field(v,"point","string"); local preset=S.Field(v,"fontPreset","string")
            local c=S.Field(v,"color","table")
            out[module][key]={enabled=S.Field(v,"enabled","boolean")~=false,
                fontSize=number(v,"fontSize",8,30,d[1]),scale=number(v,"scale",.6,2,1),
                point=points[point] and point or d[2],offsetX=number(v,"offsetX",-100,100,d[3]),
                offsetY=number(v,"offsetY",-150,150,d[4]),fontPreset=presets[preset] and preset or "normal",
                color={r=number(c,"r",0,1,1),g=number(c,"g",0,1,1),b=number(c,"b",0,1,1),a=number(c,"a",0,1,1)}}
        end
    end
    return out
end
function A:Apply(hud)
    local U=TEF.UI
    if U:Combat()~=false then hud.pending=true; return end
    local styles=hud.engine.db.hud.styles
    local function paint(text,parent,v,width)
        -- Each UI operation is independently contained by UI:Paint.
        U:Paint(text,"SetFont",STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",v.fontSize,v.fontPreset=="disable" and "" or "OUTLINE")
        U:Paint(text,"SetTextColor",v.color.r,v.color.g,v.color.b,v.color.a)
        U:Paint(text,"SetScale",v.scale); U:Paint(text,"ClearAllPoints")
        U:Paint(text,"SetWidth",width)
        U:Paint(text,"SetPoint",v.point,parent,v.point,v.offsetX,v.offsetY-(parent==hud.frame and (hud.textShift or 0) or 0))
        local align=v.point:find("RIGHT",1,true) and "RIGHT" or v.point:find("LEFT",1,true) and "LEFT" or "CENTER"
        U:Paint(text,"SetJustifyH",align); U:Paint(text,v.enabled and "Show" or "Hide")
    end
    for i,card in ipairs(hud.cards or {}) do
        local group=styles[i==1 and "main" or "preview"]
        for _,key in ipairs({"key","chargeText","cooldownText","state","label"}) do
            -- Compact labels have separate anchors; full-card width would cause
            -- top-left and top-right labels to occupy the same text region.
            paint(card[key],card.textParent,group[key],key=="label" and 28 or card.size-6)
        end
    end
    paint(hud.name,hud.frame,styles.global.name,(hud.layoutWidth or 244)-16)
    paint(hud.status,hud.frame,styles.global.status,(hud.layoutWidth or 244)-16)
    paint(hud.rangeText,hud.frame,styles.global.rangeText,(hud.layoutWidth or 244)-16)
    for _,card in ipairs(hud.cards or {}) do TEF.Presentation:PaintRange(card,card.displayStep) end
end
function A:BuildUI(U,parent)
    local module,key="main","key"
    local function current() return U.engine.db.hud.styles[module][key] end
    local function changed() TEF.HUD:Layout() end
    local function globalKey(v) return v=="name" or v=="status" or v=="rangeText" end
    U.labelModuleButtons=U:CreateSegmentedControl(parent,{{"main","主卡"},{"preview","预览卡"},{"global","整体文字"}},0,0,548,
        function() return module end,function(v) module=v; key=v=="global" and "name" or "key" end)
    local choices={{"key","键位"},{"chargeText","充能"},{"cooldownText","冷却"},{"state","状态"},{"label","卡片标题"},{"name","技能名称"},{"status","进度行"},{"rangeText","目标距离"}}
    local buttons=U:CreateSegmentedControl(parent,choices,0,-48,548,function() return key end,function(v)
        if (module=="global")==globalKey(v) then key=v end
    end)
    U.labelStyleButtons=buttons
    U:AddControlSync(function()
        for _,v in ipairs(choices) do U:SetControlEnabled(buttons[v[1]],(module=="global")==globalKey(v[1]),"请先选择标签所属的主卡、预览卡或整体文字分组。") end
    end,parent)
    U.labelEnabledButton=U:CreateToggleRow(parent,"显示当前标签",0,-96,548,function() return current().enabled end,function(v) current().enabled=v; changed() end)
    U:CreateSegmentedControl(parent,{{"normal","普通描边"},{"highlight","高亮描边"},{"disable","无描边"}},0,-144,548,
        function() return current().fontPreset end,function(v) current().fontPreset=v; changed() end)
    U:CreateSliderRow(parent,"字号",0,-200,548,8,30,1,function() return current().fontSize end,function(v) current().fontSize=v; changed() end,true)
    U:CreateSliderRow(parent,"标签缩放",0,-264,548,.6,2,.1,function() return current().scale end,function(v) current().scale=v; changed() end,true)
    U:CreateSegmentedControl(parent,{{"TOPLEFT","左上"},{"TOPRIGHT","右上"},{"CENTER","中间"},{"BOTTOMLEFT","左下"},{"BOTTOMRIGHT","右下"}},0,-328,548,
        function() return current().point end,function(v) current().point=v; changed() end)
    U:CreateSliderRow(parent,"水平偏移",0,-376,548,-100,100,1,function() return current().offsetX end,function(v) current().offsetX=v; changed() end,true)
    U:CreateSliderRow(parent,"垂直偏移",0,-440,548,-150,150,1,function() return current().offsetY end,function(v) current().offsetY=v; changed() end,true)
    for i,color in ipairs(colors) do
        U:CreateActionButton(parent,color[1],(i-1)*92,-504,80,function() current().color={r=color[2],g=color[3],b=color[4],a=1}; changed() end)
    end
    U:CreateActionButton(parent,"重置当前标签",360,-552,188,function()
        U:ConfirmAction("确认恢复当前标签的默认样式？其他标签保留。",function() U.engine.db.hud.styles[module][key]=A.Clean(nil)[module][key]; changed() end,"恢复标签")
    end)
    U:CreateHintText(parent,"目标距离属于整体文字，可独立调节字号、颜色、位置与显示。主卡和预览卡分别保存；战斗中布局变更延后。",0,-600,548)
end
