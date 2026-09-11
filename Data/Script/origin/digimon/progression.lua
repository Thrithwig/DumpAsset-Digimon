local Ledger = require 'origin.digimon.scan_ledger'
local Catalog = require 'origin.digimon.catalog'
local Runtime = require 'origin.digimon.runtime_catalog'
local M = {}

function M.hub()
  local map = _ZONE.CurrentGround
  return map and map.AssetName == 'luminous_spring'
end

function M.progress(character)
  SV.Digimon.characters = SV.Digimon.characters or {}
  local key = character.RewardIdentity
  local row = SV.Digimon.characters[key]
  if not row then
    local initial = character.LuaDataTable and character.LuaDataTable.DigimonRestoredLevel or 5
    row = {bond=10, abi=0, peak=initial, cycle_start=initial, sp_bonus=0}
    SV.Digimon.characters[key] = row
  end
  if character.Level > row.peak then
    row.abi = math.min(Runtime.abi_maximum or 100, row.abi + character.Level - row.peak)
    row.peak = character.Level
  end
  return row
end

function M.preview(character, edge)
  local row = M.progress(character)
  local species = Runtime.species[character.BaseForm.Species]
  local stats = {max_hp=character.MaxHP, attack=character.BaseAtk, defense=character.BaseDef,
    magic_attack=character.BaseMAtk, magic_defense=character.BaseMDef, speed=character.BaseSpeed,
    source_sp=species.sp[character.Level] + row.sp_bonus}
  local eligible, lines = true, {}
  for _, req in ipairs(edge.requirements) do
    local actual = req.kind == 'stat' and stats[req.stat] or
      ({level=character.Level, bond=row.bond, training=row.abi})[req.kind]
    local label = req.stat or req.kind
    if req.kind == 'party' then
      actual = 0; label = Runtime.species[req.species].name .. ' in active party, level'
      local active = false
      for _, member in ipairs(GAME:GetPlayerPartyTable()) do if member == character then active=true end end
      for _, partner in ipairs(GAME:GetPlayerPartyTable()) do
        if active and partner.BaseForm.Species == req.species then actual = math.max(actual, partner.Level) end
      end
    elseif req.kind == 'item' then
      actual = 0; label = req.name .. ' in bag or equipped'
      for i=0,GAME:GetPlayerBagCount()-1 do
        if GAME:GetPlayerBagItem(i).ID == req.item then actual=1 end
      end
      for _, member in ipairs(GAME:GetPlayerPartyTable()) do
        if member.EquippedItem and member.EquippedItem.ID == req.item then actual=1 end
      end
    end
    local met = actual >= req.minimum
    eligible = eligible and met
    table.insert(lines, (met and 'OK ' or 'Need ') .. label .. ': ' .. actual .. '/' .. req.minimum)
  end
  return eligible, table.concat(lines, '\n')
end

-- Preserve the same Character object, nickname, equipment, skills and persistent identity.
function M.change(character, edge)
  if not Ledger.valid(SV.Digimon) or not M.hub() or edge.from ~= character.BaseForm.Species then
    return false, 'Digivolution requires the Tree of Life.'
  end
  local known = false
  for _, candidate in ipairs(Runtime.transitions) do if candidate == edge then known = true end end
  if not known then return false, 'Unknown transition.' end
  local eligible, reason = M.preview(character, edge)
  if not eligible then return false, reason end
  local ok = pcall(function()
    _DATA.DataIndices[RogueEssence.Data.DataManager.DataType.Monster]:Get(edge.to)
    assert(_DATA:GetMonster(edge.to).Forms[0].Released)
  end)
  if not ok then return false, 'Target creature data is unavailable.' end
  local fields = {'Level','EXP','HP','MaxHPBonus','AtkBonus','DefBonus','MAtkBonus','MDefBonus','SpeedBonus'}
  local snapshot, old_form, ratio = {}, character.BaseForm, character.HP / character.MaxHP
  for _, field in ipairs(fields) do snapshot[field] = character[field] end
  local row = M.progress(character)
  local row_copy = {}; for k,v in pairs(row) do row_copy[k]=v end
  local changed, err = pcall(function()
    local retained = {}
    local form = _DATA:GetMonster(old_form.Species).Forms[old_form.Form]
    local stat_names = {'HP','Attack','Defense','MAtk','MDef','Speed'}
    local bonus_fields = {'MaxHPBonus','AtkBonus','DefBonus','MAtkBonus','MDefBonus','SpeedBonus'}
    for i, field in ipairs(bonus_fields) do
      local prior = math.min(character[field], (row.retained or {})[field] or 0)
      local stat = RogueEssence.Data.Stat[stat_names[i]]
      local growth = math.max(0, form:GetStat(character.Level, stat, 0) - form:GetStat(row.cycle_start, stat, 0))
      retained[field] = math.min(256, prior + math.floor((growth + math.max(0, character[field] - prior)) / 5))
      character[field] = retained[field]
    end
    local prior_sp = math.min(row.sp_bonus, row.retained_sp or 0)
    local sp = Runtime.species[old_form.Species].sp
    row.sp_bonus = math.min(256, prior_sp + math.floor((math.max(0, sp[character.Level] - sp[row.cycle_start]) + row.sp_bonus - prior_sp) / 5))
    row.retained_sp = row.sp_bonus
    row.retained = retained
    if edge.direction == 'dedigivolve' then
      local earned = math.max(0, character.Level - row.cycle_start)
      row.abi = math.min(Runtime.abi_maximum or 100, row.abi + math.floor(earned / 5))
    end
    row.cycle_start, row.peak = 1, 1
    character.Level, character.EXP = 1, 0
    character:Promote(RogueEssence.Dungeon.MonsterID(edge.to, 0, old_form.Skin, Gender.Genderless))
    character.HP = math.max(1, math.floor(character.MaxHP * ratio))
  end)
  if not changed then
    for _, field in ipairs(fields) do character[field]=snapshot[field] end
    character:Promote(old_form)
    character.HP=snapshot.HP
    for k in pairs(row) do row[k]=nil end
    for k,v in pairs(row_copy) do row[k]=v end
    return false, 'Transition failed; original form restored.'
  end
  character.LuaDataTable = character.LuaDataTable or {}
  for field, value in pairs(row.retained) do
    character.LuaDataTable['DigimonRetained' .. field] = value
  end
  _DATA.Save:RegisterMonster(character.BaseForm)
  COMMON.RespawnAllies()
  return true, Runtime.species[edge.to].name .. ' is ready.'
end

function M.show()
  if not Ledger.valid(SV.Digimon) or not M.hub() then
    UI:WaitShowDialogue('Digivolution requires a fresh save and the Tree of Life.'); return
  end
  local characters, labels = {}, {}
  for _, team in ipairs({GAME:GetPlayerPartyTable(), GAME:GetPlayerAssemblyTable()}) do
    for _, char in ipairs(team) do
      if Runtime.species[char.BaseForm.Species] then
        table.insert(characters,char)
        table.insert(labels,char:GetDisplayName(true) .. ' Lv.' .. char.Level .. ' (' .. require('origin.digimon.item_effects').personality(char) .. ')')
      end
    end
  end
  table.insert(labels,'Back')
  UI:BeginMultiPageMenu(16,16,280,'Digivolution',labels,8,1,#labels);UI:WaitForChoice()
  local char=characters[UI:ChoiceResult()]; if not char then return end
  local edges, names = {}, {}
  for _,edge in ipairs(Runtime.transitions) do
    if edge.from==char.BaseForm.Species then
      local ready=M.preview(char,edge)
      table.insert(edges,edge)
      table.insert(names,(ready and '' or '[Locked] ') .. Runtime.species[edge.to].name ..
        (edge.direction=='dedigivolve' and ' (devolve)' or ''))
    end
  end
  table.insert(names,'Back')
  UI:BeginMultiPageMenu(16,16,280,'Choose form',names,8,1,#names);UI:WaitForChoice()
  local edge=edges[UI:ChoiceResult()];if not edge then return end
  local ready, preview=M.preview(char,edge)
  if require('origin.digimon.evolution_preview').show(char,edge,ready,preview) then
    local _,message=M.change(char,edge);UI:WaitShowDialogue(message)
  end
end

return M
