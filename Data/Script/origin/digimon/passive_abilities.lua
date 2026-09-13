local Runtime = require 'origin.digimon.runtime_catalog'
local M = {}

-- Upgrade existing party/assembly members through the native intrinsic API so
-- current trait references and the evolution slot stay synchronized.
function M.sync(char)
  if not char or not char.BaseForm or not Runtime.species[char.BaseForm.Species]
    or not char.BaseIntrinsics or not char.LearnIntrinsic then return false end
  if char.EnsureFormHistory then char:EnsureFormHistory() end
  local form = _DATA:GetMonster(char.BaseForm.Species).Forms[char.BaseForm.Form]
  local expected = form.Intrinsic1
  if not expected or string.sub(expected,1,5)~='digi_' or char.BaseIntrinsics[0]==expected then return false end
  char:LearnIntrinsic(expected,0)
  return true
end

function M.team()
  if GAME.GetPlayerPartyTable then
    for _,char in ipairs(GAME:GetPlayerPartyTable()) do M.sync(char) end
  end
  if GAME.GetPlayerAssemblyTable then
    for _,char in ipairs(GAME:GetPlayerAssemblyTable()) do M.sync(char) end
  end
end

return M
