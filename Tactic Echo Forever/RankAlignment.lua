local _,T=...
local U,P,C=T.UI,T.Profiles,T.APL.Custom
function U:DetectPlanBarRanks()
 if self:Combat()~=false or not self.settingsOpen then return false end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false end
 if self.groupEditing and not self:CommitGroupFields() then return false end
 local rows,source,slot=self:StudioActiveRows()
 if not rows or (source~="manual" and source~="apl" and source~="group") or slot=="maintenance" then return false end
 local copy=source=="apl" and C.CleanRows(rows) or P:Clean(rows,source=="group" and T.SkillGroups.MaxSteps or 16)
 if not copy then self:StudioMessage("当前草稿无效，不能批量替换。"); return false end
 local catalog=T.ActionSources:BarSpellCatalog(); local memo,changes,details={},{},{}
 local unchanged,unmatched=0,0
 local function visit(list,manual,path)
  for i,row in ipairs(list) do
   local where=path..i
   if row.group then visit(row.group.steps,true,where.."／组内")
   elseif not row.spellID or row.invalid then
    unmatched=unmatched+1; details[#details+1]=where.."：原条目无效，请先修正配置"
   else
    local old=row.spellID; local found=memo[old]
    if not found then local id,reason=T.ActionSources:FindBarRank(old,catalog); found={id=id,reason=reason}; memo[old]=found end
    if not found.id then
     unmatched=unmatched+1; details[#details+1]=where.."（ID "..old.."）："..found.reason
    elseif found.id==old then unchanged=unchanged+1
    else
     changes[#changes+1]={old=old,id=found.id}; details[#details+1]=where.."："..old.." → "..found.id
     row.spellID=found.id; row.invalid=nil
     if manual then row.name=T.Safety.Spell(found.id,"技能 "..found.id).name; row.matchIDs={found.id}; row.unverified=nil end
    end
   end
  end
 end
 visit(copy,source~="apl","条目")
 -- 重建父组的展示ID与匹配信息，组策略和行为由现有清洗器保留。
 copy=source=="apl" and C.CleanRows(copy) or P:Clean(copy,source=="group" and T.SkillGroups.MaxSteps or 16)
 local summary="可替换"..#changes.."项，已一致"..unchanged.."项，未匹配"..unmatched.."项。"
 local button=source=="group" and self.groupAlignRanks or self.studioAlignRanks
 self:BindControlTooltip(button,"动作条等级检测结果",summary.."\n"..table.concat(details,"\n"))
 self:StudioMessage(summary.."悬停检测按钮可查看明细；未匹配项保留原值。")
 if #changes==0 then return true end
 local tx={engine=self.engine,source=source,slot=slot,page=self.page,group=self.groupDraft,
  fingerprint=self:StudioFingerprint(rows,source),rows=copy,changes=changes}
 self:ConfirmAction(summary.."确认把匹配项全部替换为动作条上的精确等级？保留策略和显式观察ID；保存方案后生效。",function() self:ApplyPlanBarRanks(tx) end,"替换匹配项")
 return true
end
function U:ApplyPlanBarRanks(tx)
 if not self.settingsOpen or self:Combat()~=false or tx.engine~=self.engine or tx.page~=self.page then return false end
 if not self:CommitSequenceCounts() or not self:CommitCustomNumbers() then return false end
 if self.groupEditing and not self:CommitGroupFields() then return false end
 local rows,source,slot=self:StudioActiveRows()
 if source~=tx.source or slot~=tx.slot or (source=="group" and self.groupDraft~=tx.group)
  or tx.fingerprint~=self:StudioFingerprint(rows,source) then self:StudioMessage("编辑对象已改变，请重新检测等级。"); return false end
 local catalog=T.ActionSources:BarSpellCatalog(); local checked={}
 for _,change in ipairs(tx.changes) do
  if not checked[change.old] then checked[change.old]=T.ActionSources:FindBarRank(change.old,catalog) or false end
  if checked[change.old]~=change.id then self:StudioMessage("动作条或已学状态已改变，请重新检测等级。"); return false end
 end
 self.studioSelected=nil; self.sequencePolicyRow=nil; self.strategyInputs={}; self.customFormIndex=nil; self.undoDelete=nil; self.studioProbe=nil
 self:Paint(self.strategyPanel,"Hide")
 if source=="group" then
  self.groupDraft.steps=tx.rows; self.groupDirty=true; self.strategySource=nil; self:RefreshSkillGroup(); self:Paint(self.groupPanel,"Show")
 elseif source=="manual" then self:WriteDraft(tx.rows)
 else self.customDraft=tx.rows; self:RefreshCustomAPL() end
 self:RefreshStudio(); self:StudioMessage("已按动作条精确等级替换"..#tx.changes.."项草稿；策略及显式观察ID保留，保存后生效。")
 return true
end
