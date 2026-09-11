-- Persistent, plain-Lua Scan Data state. No engine objects are stored in SV.
local Ledger = {}
local Catalog = require 'origin.digimon.catalog'

function Ledger.new()
  return { version = 1, species = {}, floor_sequence = 0, floor = nil }
end

function Ledger.valid(state)
  return type(state) == "table" and state.version == 1 and type(state.species) == "table"
end

local function blank()
  return { scan_points = 0, code_unlocked = false, unlock_count = 0,
           restoration_count = 0, first_source = "", variants_discovered = {} }
end

function Ledger.get(state, id)
  assert(Ledger.valid(state), "A fresh Digimon save is required")
  return state.species[id] or blank()
end

function Ledger.begin_floor(state)
  assert(Ledger.valid(state), "A fresh Digimon save is required")
  state.floor_sequence = state.floor_sequence + 1
  state.floor = { sequence = state.floor_sequence, seen = {}, points = {} }
  return state.floor_sequence
end

-- Called by a confirmed-defeat integration, never from the signpost UI.
-- sequence and entity_id must identify this floor visit and the unique spawn.
-- Scan points remain banked until restoration; they are never converted to Bits.
function Ledger.award(state, catalog, event)
  if not Ledger.valid(state) or type(event) ~= "table" then return nil end
  local floor = state.floor
  if not floor or event.floor_sequence ~= floor.sequence or event.confirmed ~= true
      or event.source_kind ~= "hostile" or type(event.entity_id) ~= "string"
      or event.entity_id == "" or floor.seen[event.entity_id] then return nil end
  local known = false
  for _, species in ipairs(catalog.species) do
    if species.id == event.species then known = true; break end
  end
  if not known then return nil end
  local policy = catalog.scan
  local used = floor.points[event.species] or 0
  local credited = math.min(policy.points_per_defeat, math.max(0, policy.points_per_species_per_floor - used))
  floor.seen[event.entity_id] = true
  floor.points[event.species] = used + credited
  local row = state.species[event.species] or blank()
  state.species[event.species] = row
  if credited > 0 and row.first_source == "" then row.first_source = event.source_name or "Dungeon" end
  local total = row.scan_points + credited
  row.scan_points = total
  if row.scan_points >= policy.unlock_threshold and not row.code_unlocked then
    row.code_unlocked = true
    row.unlock_count = row.unlock_count + 1
  end
  if credited > 0 and type(event.variant) == "string" then row.variants_discovered[event.variant] = true end
  return { credited = credited, points = row.scan_points, unlocked = row.code_unlocked,
           bits = 0 }
end

function Ledger.restoration_level(points)
  if points < Catalog.scan.unlock_threshold then return nil end
  return math.min(Catalog.scan.restoration_maximum_level,
    Catalog.scan.restoration_level + (math.floor(points / Catalog.scan.unlock_threshold) - 1) *
    Catalog.scan.restoration_levels_per_threshold)
end

-- Revalidate after confirmation. Adapter.prepare must not mutate the team/RNG;
-- adapter.commit either adds one reserve or throws; rollback removes that exact reserve.
function Ledger.restore(state, id, adapter)
  if not Ledger.valid(state) then return false, "Start a new save to use DigiCode restoration." end
  local row = state.species[id]
  if not row or not Ledger.restoration_level(row.scan_points) then return false, "At least 100 Scan Data is required." end
  local ready, reason = adapter.ready(id)
  if not ready then return false, reason end
  local ok, character = pcall(adapter.prepare, id, Ledger.restoration_level(row.scan_points))
  if not ok or not character then return false, "Restoration could not be prepared. Your DigiCode is unchanged." end
  local committed, error_message = pcall(adapter.commit, character)
  if not committed then
    adapter.rollback(character)
    return false, "Restoration failed. Your DigiCode is unchanged."
  end
  row.scan_points = 0
  row.code_unlocked = false
  row.restoration_count = row.restoration_count + 1
  return true, character
end

return Ledger
