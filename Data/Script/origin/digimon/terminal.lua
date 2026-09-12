local Ledger = require 'origin.digimon.scan_ledger'
local Catalog = require 'origin.digimon.catalog'
local Terminal = {}

local function choice(message, choices, cancel)
  UI:BeginChoiceMenu(message, choices, 1, cancel)
  UI:WaitForChoice()
  return UI:ChoiceResult()
end

local function select_species(title, state, unlocked_only)
  local choices, ids = {}, {}
  for _, species in ipairs(Catalog.species) do
    local row = Ledger.get(state, species.id)
    local level = Ledger.restoration_level(row.scan_points)
    if not unlocked_only or level then
      local status = tostring(row.scan_points) .. " Scan" .. (level and (" / Lv." .. level) or "")
      table.insert(choices, species.name .. "  " .. status)
      table.insert(ids, species)
    end
  end
  if #ids == 0 then
    UI:WaitShowDialogue("No DigiCodes are ready. Recover Scan Data from defeated hostile Digimon first.")
    return nil
  end
  table.insert(choices, "Back")
  UI:BeginMultiPageMenu(16, 16, 280, title, choices, 8, 1, #choices)
  UI:WaitForChoice()
  return ids[UI:ChoiceResult()]
end

function Terminal.engine_adapter()
  return {
    ready = function(id)
      local known = false
      for _, species in ipairs(Catalog.species) do if species.id == id then known = true; break end end
      if not known then return false, "This DigiCode is not in the current roster." end
      local ok, usable = pcall(function()
        -- Check the index first: GetMonster can otherwise return a fallback record.
        local index = _DATA.DataIndices[RogueEssence.Data.DataManager.DataType.Monster]
        local summary = index:Get(id)
        local monster = _DATA:GetMonster(id)
        if not summary.Released or not monster.Released or monster.Forms.Count == 0 then return false end
        local form = monster.Forms[0]
        if not form.Released or form.Intrinsic1 == "" then return false end
        local has_skill = false
        for i = 0, form.LevelSkills.Count - 1 do
          local skill = form.LevelSkills[i]
          _DATA.DataIndices[RogueEssence.Data.DataManager.DataType.Skill]:Get(skill.Skill)
          if skill.Level <= Catalog.scan.restoration_level then has_skill = true end
        end
        return has_skill
      end)
      if not ok or not usable then
        return false, "This Digimon's creature data is not available yet. Your DigiCode will be kept."
      end
      return true
    end,
    prepare = function(id, level)
      local form = _DATA:GetMonster(id).Forms[0]
      local monster_id = RogueEssence.Dungeon.MonsterID(id, 0, _DATA.DefaultSkin, Gender.Genderless)
      -- Explicit gender, intrinsic and personality avoid consuming the save RNG.
      local recruit = _DATA.Save.ActiveTeam:CreatePlayer(_DATA.Save.Rand, monster_id,
          level, form.Intrinsic1, 0)
      recruit.LuaDataTable.DigimonRestoredLevel = level
      recruit.MetAt = "Restoration terminal"
      recruit.MetLoc = RogueEssence.Dungeon.ZoneLoc(_ZONE.CurrentZoneID, _ZONE.CurrentMapID)
      recruit.ActionEvents:Add(RogueEssence.Dungeon.BattleScriptEvent("AllyInteract"))
      return recruit
    end,
    commit = function(character) GAME:AddPlayerAssembly(character) end,
    rollback = function(character)
      for index = GAME:GetPlayerAssemblyCount() - 1, 0, -1 do
        if GAME:GetPlayerAssemblyMember(index) == character then GAME:RemovePlayerAssembly(index) end
      end
    end
  }
end

function Terminal.show_ledger(state)
  while true do
    local species = select_species("Scan Data", state, false)
    if not species then return end
    local row = Ledger.get(state, species.id)
    UI:WaitShowDialogue(species.name .. " Scan Data " .. row.scan_points .. "/" .. Catalog.scan.unlock_threshold ..
        "\n" .. (Ledger.restoration_level(row.scan_points) and ("Ready: level " .. Ledger.restoration_level(row.scan_points)) or "Need 100 Scan Data") ..
        "\nRestorations: " .. row.restoration_count ..
        (row.first_source ~= "" and ("\nFirst source: " .. row.first_source) or ""))
  end
end

function Terminal.show_restoration(state, adapter)
  while true do
    local species = select_species("Restore Digimon", state, true)
    if not species then return end
    local ready, reason = adapter.ready(species.id)
    if not ready then
      UI:WaitShowDialogue(reason)
    else
      local points = Ledger.get(state, species.id).scan_points
      UI:ChoiceMenuYesNo("Spend all " .. points .. " Scan Data to restore " .. species.name ..
          " at level " .. Ledger.restoration_level(points) .. " into your reserves?", false)
      UI:WaitForChoice()
      if UI:ChoiceResult() then
        local restored, result = Ledger.restore(state, species.id, adapter)
        if restored then UI:WaitShowDialogue(species.name .. " restored to your reserves.")
        else UI:WaitShowDialogue(result) end
      end
    end
  end
end

-- Assign the stat each Digimon trains while it sits in reserve. Progress accrues per
-- dungeon floor the active party enters; see origin.digimon.farm.
function Terminal.show_training()
  local Farm = require 'origin.digimon.farm'
  local Runtime = require 'origin.digimon.runtime_catalog'
  local Progress = require 'origin.digimon.progression'
  while true do
    local characters, labels = {}, {}
    for _, team in ipairs({ GAME:GetPlayerPartyTable(), GAME:GetPlayerAssemblyTable() }) do
      for _, char in ipairs(team) do
        if Runtime.species[char.BaseForm.Species] then
          local row = Progress.progress(char)
          local regimen = row.regimen and Farm.regimen(row.regimen)
          table.insert(characters, char)
          table.insert(labels, char:GetDisplayName(true) .. " Lv." .. char.Level .. "  " .. (regimen and regimen.name or "Resting"))
        end
      end
    end
    if #characters == 0 then UI:WaitShowDialogue("There are no Digimon to train yet."); return end
    table.insert(labels, "Back")
    UI:BeginMultiPageMenu(16, 16, 280, "Training", labels, 8, 1, #labels)
    UI:WaitForChoice()
    local char = characters[UI:ChoiceResult()]
    if not char then return end
    local row = Progress.progress(char)
    local name = char:GetDisplayName(true)
    if row.skill_check_level and GAME.CheckLevelSkills then
      -- Levels gained in reserve offer their new skills here, not mid-dungeon.
      local from = row.skill_check_level
      row.skill_check_level = nil
      GAME:CheckLevelSkills(char, from)
    end
    local names = {}
    for _, regimen in ipairs(Farm.regimens) do
      table.insert(names, regimen.name .. (row.regimen == regimen.id and " (current)" or ""))
    end
    table.insert(names, "Rest")
    table.insert(names, "Back")
    UI:BeginMultiPageMenu(16, 16, 280, name .. " trains...", names, 8, 1, #names)
    UI:WaitForChoice()
    local pick = UI:ChoiceResult()
    if Farm.regimens[pick] then
      Farm.set_regimen(char, Farm.regimens[pick].id)
      UI:WaitShowDialogue(name .. " will train " .. Farm.regimens[pick].name ..
          " while in reserve. Every floor your team explores counts.")
    elseif pick == #Farm.regimens + 1 then
      Farm.set_regimen(char, nil)
      UI:WaitShowDialogue(name .. " will rest.")
    end
  end
end

-- The shared signpost retains its existing team-change animation/respawn callback.
function Terminal.show(assembly_action, adapter)
  adapter = adapter or Terminal.engine_adapter()
  while true do
    local result = choice("What would you like to do?",
        { "Adventuring Team", "Scan Data", "Restore Digimon", "Training", "Leave" }, 5)
    if result == 1 then
      assembly_action()
    elseif result == 2 or result == 3 or result == 4 then
      if not Ledger.valid(SV.Digimon) then
        UI:WaitShowDialogue("Scan Data, restoration and training require a fresh save. Adventuring Team is still available.")
      elseif result == 2 then Terminal.show_ledger(SV.Digimon)
      elseif result == 3 then Terminal.show_restoration(SV.Digimon, adapter)
      else Terminal.show_training() end
    else return end
  end
end

return Terminal
