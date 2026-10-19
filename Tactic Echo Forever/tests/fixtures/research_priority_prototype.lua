-- 历史原型，仅用于保留旧契约回归；不在插件TOC中加载。
local function isTrue(field) return field and field.state=="PUBLIC_TRUE" and field.value==true end
local function isFalse(field) return field and field.state=="PUBLIC_FALSE" and field.value==false end
-- Contract prototype, not a ready formula. Each exact spell must receive
-- independently certified own-ready evidence before any candidate exists.
return function(rows,byID,common)
    if not isTrue(common.targetExists) or not isTrue(common.targetAttackable) or not isTrue(common.targetAlive)
        or not isTrue(common.gcdClear) or not isFalse(common.castPresent) or not isFalse(common.channelPresent)
        or not isFalse(common.moving) then return nil,"PRIORITY_COMMON_UNKNOWN_OR_BLOCKED" end
    for _,row in ipairs(rows) do
        local f=byID[row.spellID]
        if not row.unverified and f and isTrue(f.learned) and isTrue(f.ready) and isTrue(f.usable)
            and isFalse(f.insufficientPower) and isTrue(f.inRange) then
            return row.spellID,"PRIORITY_CANDIDATE"
        end
    end
    return nil,"PRIORITY_NO_CERTIFIED_READY"
end
