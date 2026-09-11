local Ledger = require 'origin.digimon.scan_ledger'
local Access = {}
local function completed(zone)
  return _DATA.Save:GetDungeonUnlock(zone)==RogueEssence.Data.GameProgress.UnlockState.Completed
end
function Access.ensure()
  if not Ledger.valid(SV.Digimon) then return false end
  -- Guildmaster Trail is the long endgame challenge, not the story route.
  for _,zone in ipairs({'tropical_path','guildmaster_trail'}) do
    if not GAME:DungeonUnlocked(zone) then GAME:UnlockDungeon(zone) end
  end
  if SV.forest_camp.ExpositionComplete or completed('tropical_path') then
    if not GAME:DungeonUnlocked('faultline_ridge') then GAME:UnlockDungeon('faultline_ridge') end
  end
  return true
end
function Access.destinations(existing)
  if not Access.ensure() then return existing end
  local result = {}
  for _,zone in ipairs(existing) do
    -- Legacy slice saves retain completion records, but must follow story gates.
    local allowed = true
    if zone=='faultline_ridge' then allowed=SV.forest_camp.ExpositionComplete or completed('tropical_path') end
    if zone=='trickster_woods' then allowed=completed('faultline_ridge') end
    if allowed then result[#result+1]=zone end
  end
  return result
end
function Access.entry_floor(zone)
  if Ledger.valid(SV.Digimon) and zone=='training_maze' then return 4 end
  return 0
end
function Access.grounds(existing)
  if not Ledger.valid(SV.Digimon) then return existing end
  local result = {}
  for _,entry in ipairs(existing) do
    local flag=entry.Flag
    if entry.Zone=='guildmaster_island' and entry.ID==3 and completed('tropical_path') then flag=true end
    result[#result+1]={Flag=flag,Zone=entry.Zone,ID=entry.ID,Entry=entry.Entry}
  end
  return result
end
return Access
