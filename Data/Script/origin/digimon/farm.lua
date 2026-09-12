-- Reserve training: benched Digimon train one chosen stat and catch up in level
-- while the active party explores. Time is measured in dungeon floors entered,
-- never in wall-clock time, so progress is deterministic and cannot be idled for.
-- State lives in the per-character SV.Digimon row (plain Lua, save-safe).
local Runtime = require 'origin.digimon.runtime_catalog'
local Progress = require 'origin.digimon.progression'
local Effects = require 'origin.digimon.item_effects'
local M = {}

M.regimens = {
  { id = 'MaxHPBonus', name = 'HP' },
  { id = 'AtkBonus', name = 'Attack' },
  { id = 'DefBonus', name = 'Defense' },
  { id = 'MAtkBonus', name = 'M.Attack' },
  { id = 'MDefBonus', name = 'M.Defense' },
  { id = 'SpeedBonus', name = 'Speed' },
  { id = 'sp', name = 'SP' },
  { id = 'abi', name = 'ABI' },
  { id = 'bond', name = 'Bond' },
}
-- Floors between gains. A regimen matching the personality's favored stat trains faster,
-- the same preference the training foods already honour.
M.floors_per_gain = 3
M.favored_floors_per_gain = 2
-- Reserves level toward the strongest active member minus this margin, so the bench
-- trails the party and never leads it.
M.level_margin = 5
-- Levels gained per floor are the remaining gap divided by this, at least one, so any
-- gap closes over roughly one dungeon run.
M.catch_up_divisor = 5

function M.regimen(id)
  for _, row in ipairs(M.regimens) do if row.id == id then return row end end
  return nil
end

function M.set_regimen(character, id)
  local row = Progress.progress(character)
  row.regimen = M.regimen(id) and id or nil
  row.training_floors = 0
  return row.regimen
end

local function gain(character, row, regimen)
  if regimen.id == 'bond' then row.bond = math.min(100, (row.bond or 0) + 1)
  elseif regimen.id == 'abi' then row.abi = math.min(Runtime.abi_maximum or 200, (row.abi or 0) + 1)
  elseif regimen.id == 'sp' then row.sp_bonus = math.min(256, (row.sp_bonus or 0) + 1)
  else character[regimen.id] = math.min(256, character[regimen.id] + 1) end
  row.trained_total = (row.trained_total or 0) + 1
end

-- Stat side of one floor tick. Returns the regimen name when a point was gained.
function M.train(character)
  local row = Progress.progress(character)
  local regimen = row.regimen and M.regimen(row.regimen)
  if not regimen then return nil end
  local needed = Effects.favored_field(character) == regimen.id and M.favored_floors_per_gain or M.floors_per_gain
  row.training_floors = (row.training_floors or 0) + 1
  if row.training_floors < needed then return nil end
  row.training_floors = 0
  gain(character, row, regimen)
  return regimen.name
end

function M.target_level(party)
  local top = 0
  for _, member in ipairs(party) do if member.Level > top then top = member.Level end end
  return math.max(1, top - M.level_margin)
end

-- Level side of one floor tick. Whole levels only: EXP toward the next level is kept,
-- which stays valid because the requirement never shrinks with level. Levels earned here
-- count toward ABI through the usual peak-level bookkeeping, and the lowest level since
-- the last skill check is recorded so the Training menu can offer new skills.
function M.catch_up(character, target, max_level)
  local cap = math.min(target, max_level)
  if character.Level >= cap then return 0 end
  local gap = cap - character.Level
  local gained = math.min(gap, math.max(1, math.ceil(gap / M.catch_up_divisor)))
  local row = Progress.progress(character)
  row.skill_check_level = math.min(row.skill_check_level or character.Level, character.Level)
  character.Level = character.Level + gained
  if character.Level >= max_level then character.EXP = 0 end
  character.HP = character.MaxHP
  Progress.progress(character)
  return gained
end

-- One floor tick for every reserve Digimon. Party members and non-Digimon are untouched.
function M.tick(party, reserves, max_level)
  local target = M.target_level(party)
  local active = {}
  for _, member in ipairs(party) do active[member] = true end
  local report = {}
  for _, char in ipairs(reserves) do
    if not active[char] and not char.Dead and Runtime.species[char.BaseForm.Species] then
      local levels = M.catch_up(char, target, max_level)
      local trained = M.train(char)
      if levels > 0 or trained then table.insert(report, { character = char, levels = levels, trained = trained }) end
    end
  end
  return report
end

-- Engine entry point, called once per new dungeon floor by the runtime service.
function M.floor()
  local report = M.tick(GAME:GetPlayerPartyTable(), GAME:GetPlayerAssemblyTable(), _DATA.Start.MaxLevel)
  for _, entry in ipairs(report) do
    local parts = {}
    if entry.levels > 0 then table.insert(parts, 'Lv.' .. entry.character.Level) end
    if entry.trained then table.insert(parts, entry.trained .. ' +1') end
    _DUNGEON:LogMsg(entry.character:GetDisplayName(true) .. ' (reserve): ' .. table.concat(parts, ', '))
  end
  return report
end

return M
