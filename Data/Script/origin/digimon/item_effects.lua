local M={}
M.personalities={'Durable','Lively','Fighter','Defender','Brainy','Nimble','Builder','Searcher'}
local fields={'MaxHPBonus','MDefBonus','AtkBonus','DefBonus','MAtkBonus','SpeedBonus'}
local values={'MaxHP','BaseMDef','BaseAtk','BaseDef','BaseMAtk','BaseSpeed'}
function M.personality(character)
  local row=require('origin.digimon.progression').progress(character)
  if not row.personality then
    local hash=0
    for byte in tostring(character.RewardIdentity):gmatch('.') do hash=(hash*31+byte:byte())%65521 end
    row.personality=M.personalities[hash%#M.personalities+1]
  end
  return row.personality,row
end
function M.food(character, stat)
  if not SV.Digimon then return end
  local personality,row=M.personality(character)
  if stat=='bond' then row.bond=math.min(100,row.bond+5)
  elseif stat=='abi' then row.abi=math.min(200,row.abi+5)
  elseif stat=='sp' then row.sp_bonus=math.min(256,row.sp_bonus+1)
  else character[stat]=math.min(256,character[stat]+1) end
  local favored
  for i,name in ipairs(M.personalities) do if name==personality then favored=i end end
  if favored<=6 then
    local field=fields[favored]
    character[field]=math.min(256,character[field]+math.max(1,math.ceil(character[values[favored]]*0.05)))
  else
    for _,field in ipairs(fields) do character[field]=math.min(256,character[field]+1) end
    -- These factors are consumed by future farm jobs; no fake running timers.
    row.development_time_multiplier=personality=='Builder' and 0.95 or 1
    row.investigation_time_multiplier=personality=='Searcher' and 0.95 or 1
  end
  character.Fullness=math.min(character.MaxFullness,character.Fullness+5)
end
function M.experience(character, amount)
  if character.Dead or character.Level>=99 then return false end
  character.EXP=character.EXP+amount
  _DUNGEON.LevelGains:Add(_ZONE.CurrentMap:GetCharIndex(character))
  return true
end
function M.restraint(character, stat)
  if stat=='HP' then
    character.MaxHPBonus=math.max(0,character.MaxHPBonus-8)
    character.HP=math.min(character.HP,character.MaxHP)
  elseif stat=='SP' and SV.Digimon then
    local row=require('origin.digimon.progression').progress(character)
    row.sp_bonus=math.max(0,row.sp_bonus-8)
  end
end
return M
