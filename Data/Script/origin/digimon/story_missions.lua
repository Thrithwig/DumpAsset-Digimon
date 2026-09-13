-- Deterministic primary requests for the Digimon conversion.
-- These use the native scripted-mission hooks; the optional random mission-board mod remains disabled.
local Story = {}

local missions = {
  {
    id = "DigimonStory_TropicalPath", title = "Nursery Courier",
    zone = "tropical_path", segment = 0, floor = 1, target = "falcomon", level = 5,
    request = "Falcomon's nursery check-in is overdue in Tropical Path. Botamon and Punimon were with them. Bring everyone back before the route forgets itself again.",
    accepted = "Tropical Path is your active primary request. Find Falcomon and the nursery pair, then finish the route before reporting back.",
    active = "Falcomon and the nursery pair still need help in Tropical Path.",
    objective = "Falcomon gathers Botamon and Punimon close. The three can leave together, but the Koromon guardian still blocks the route home.",
    complete = "Falcomon, Botamon, and Punimon are accounted for. Guardromon reached File Town with worse news: Beelzemon has seized the Return Protocol at Infinity Summit. We do not yet know why.",
    unlocks = { "faded_trail", "bramble_woods", "tiny_tunnel", "faultline_ridge" }
  },
  {
    id = "DigimonStory_FaultlineRidge", title = "Drill Tunnel Survey",
    zone = "faultline_ridge", segment = 0, floor = 4, target = "gotsumon", level = 15,
    request = "Gotsumon's survey team found route seals resetting in Drill Tunnel. Rescue the surveyors and bring back their chalk record.",
    accepted = "Faultline Ridge is your active primary request. Follow the lower tunnel marks; the seals may have moved again.",
    active = "The Gotsumon survey team is still trapped in Faultline Ridge.",
    objective = "Gotsumon presses the survey record into your hands. The marks show a stable passage, if the route can be cleared once more.",
    complete = "The surveyors are home. Their chalk marks expose a passage toward Signpost Forest. Trickster Woods can now be investigated.",
    unlocks = { "trickster_woods" },
    prerequisite = "DigimonStory_TropicalPath"
  },
  {
    id = "DigimonStory_TricksterWoods", title = "The Routing Plate",
    zone = "trickster_woods", segment = 0, floor = 5, target = "impmon", level = 20,
    request = "Impmon's bad signs have been hiding travelers from hijacked patrols. Find Impmon, extract the travelers' routing plate, and bring them out safely.",
    accepted = "Trickster Woods is your active primary request. Do not trust every sign, even when it looks very sure of itself.",
    active = "Impmon and the routing plate are still missing in Trickster Woods.",
    objective = "Impmon hands over the routing plate and admits the warnings were meant to hide travelers, not send them deeper into danger.",
    complete = "Impmon and the routing plate are safe. The plate confirms that someone at the summit is rewriting the safe paths. The patrol confrontation remains ahead of us.",
    unlocks = { "overgrown_wilds", "moonlit_courtyard" },
    prerequisite = "DigimonStory_FaultlineRidge"
  }
}

local by_id = {}
for _, mission in ipairs(missions) do by_id[mission.id] = mission end

local function enabled()
  return SV.Digimon ~= nil
end

local function state()
  if not enabled() then return nil end
  SV.Digimon.StoryMissions = SV.Digimon.StoryMissions or {}
  local data = SV.Digimon.StoryMissions
  data.records = data.records or {}
  data.current = data.current or ""
  for _, mission in ipairs(missions) do
    data.records[mission.id] = data.records[mission.id] or {
      accepted = false, objective_met = false, cleared = false, debriefed = false
    }
  end
  return data
end

local function record(mission_id)
  local data = state()
  return data and data.records[mission_id] or nil
end

local function monster(species)
  return RogueEssence.Dungeon.MonsterID(species, 0, "normal", Gender.Genderless)
end

local function prerequisite_met(mission, data)
  if mission.prerequisite == nil then return true end
  local prior = data.records[mission.prerequisite]
  if prior == nil or not prior.debriefed then return false end
  -- Tropical's completion returns through Forest Camp.  This prevents an imported
  -- objective flag from opening Faultline before that authored arrival.
  if mission.id == "DigimonStory_FaultlineRidge" then
    return SV.forest_camp ~= nil and SV.forest_camp.ExpositionComplete == true
  end
  return true
end

function Story.ensure()
  return state()
end

function Story.enabled()
  return enabled()
end

function Story.debriefed(mission_id)
  local entry = record(mission_id)
  return entry ~= nil and entry.debriefed == true
end

function Story.gates_unlock(zone_id)
  return enabled() and (zone_id == "faultline_ridge" or zone_id == "trickster_woods")
end

local function next_mission(data)
  for _, mission in ipairs(missions) do
    local entry = data.records[mission.id]
    if not entry.debriefed and prerequisite_met(mission, data) then return mission end
  end
  return nil
end

local function create_native_mission(mission)
  COMMON.CreateMission(mission.id, {
    Complete = COMMON.MISSION_INCOMPLETE,
    Type = COMMON.SIDEQUEST_TYPE_RESCUE,
    DestZone = mission.zone, DestSegment = mission.segment, DestFloor = mission.floor,
    FloorUnknown = false, TargetLevel = mission.level,
    TargetSpecies = monster(mission.target), ClientSpecies = monster("clockmon"),
    StoryMission = true, StoryObjectiveText = mission.objective
  })
end

function Story.accept(mission)
  local data = state()
  local entry = data.records[mission.id]
  if not prerequisite_met(mission, data) then return false end
  if SV.missions.Missions[mission.id] == nil then create_native_mission(mission) end
  entry.accepted = true
  data.current = mission.id
  return true
end

function Story.objective_met(mission_id)
  local entry = record(mission_id)
  if entry == nil or not entry.accepted then return false end
  entry.objective_met = true
  return true
end

-- A rescue interaction and Escape deliberately do not count as a cleared route.
function Story.on_zone_exit(zone_id, segment_id, result)
  local data = state()
  if data == nil or data.current == "" then return false end
  local mission = by_id[data.current]
  local entry = mission and data.records[mission.id] or nil
  if entry == nil or not entry.accepted or not entry.objective_met then return false end
  if mission.zone ~= zone_id or mission.segment ~= segment_id then return false end
  if result ~= RogueEssence.Data.GameProgress.ResultType.Cleared then return false end
  entry.cleared = true
  return true
end

local function debrief(chara, mission, data)
  local entry = data.records[mission.id]
  if not entry.objective_met or not entry.cleared then return false end
  UI:SetSpeaker(chara)
  UI:WaitShowDialogue(mission.complete)
  for _, zone in ipairs(mission.unlocks) do
    if not GAME:DungeonUnlocked(zone) then COMMON.UnlockWithFanfare(zone, false) end
  end
  -- Only archive a live native record, making repeated debriefs safe after reload.
  if SV.missions.Missions[mission.id] ~= nil then COMMON.CompleteMission(mission.id) end
  entry.debriefed = true
  if data.current == mission.id then data.current = "" end
  return true
end

function Story.interact(chara)
  local data = state()
  if data == nil then return end
  local mission = data.current ~= "" and by_id[data.current] or next_mission(data)
  UI:SetSpeaker(chara)
  if mission == nil then
    UI:WaitShowDialogue("Every request on my current ledger has a return mark. I can finally hate paperwork for ordinary reasons again.")
    return
  end
  local entry = data.records[mission.id]
  if entry.accepted then
    if entry.objective_met and entry.cleared then
      debrief(chara, mission, data)
    elseif entry.objective_met then
      UI:WaitShowDialogue("The rescue is secure, but the route still needs a successful clear before I can mark everyone safely home.")
    else
      UI:WaitShowDialogue(mission.active)
    end
    return
  end
  UI:WaitShowDialogue("Primary request: " .. mission.title)
  UI:WaitShowDialogue(mission.request)
  UI:ChoiceMenuYesNo("Accept this primary request?", true)
  UI:WaitForChoice()
  if UI:ChoiceResult() and Story.accept(mission) then
    UI:WaitShowDialogue(mission.accepted)
  else
    UI:WaitShowDialogue("I'll keep the dispatch open. The missing do not become less missing while we wait.")
  end
end

return Story
