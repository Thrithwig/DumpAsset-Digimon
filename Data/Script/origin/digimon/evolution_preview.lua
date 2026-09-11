local M = {}

-- An actual secondary menu, also available for locked forms. No state changes here.
function M.show(character, edge, ready, requirements)
  local Runtime = require 'origin.digimon.runtime_catalog'
  local Art = luanet.import_type('PMDC.Menu.DigimonArtElement')
  local confirmed, page, lastDirection = false, 1, RogueElements.Dir8.None
  local lines = {}
  for line in requirements:gmatch('[^\n]+') do
    line=(line:sub(1,2)=='OK' and '[color=#80FF80]' or '[color=#FF9090]')..line..'[color]'
    for wrapped in luanet.each(RogueEssence.Menu.MenuText.BreakIntoLines(line, 280)) do
      table.insert(lines, wrapped)
    end
  end
  if #lines == 0 then lines={'No additional requirements.'} end
  local pages=math.max(1,math.ceil(#lines/4))
  local currentArt, targetArt
  local menu
  local function rebuild()
    menu.Elements:Clear()
    local function text(value,x,y) menu.Elements:Add(RogueEssence.Menu.MenuText(value,RogueElements.Loc(x,y))) end
    text('Tree of Life',8,6)
    text(Runtime.species[character.BaseForm.Species].name,8,22)
    text(Runtime.species[edge.to].name,158,22)
    menu.Elements:Add(currentArt);menu.Elements:Add(targetArt)
    text('Lv.'..character.Level,8,105)
    text('Lv.1 / '..Runtime.species[edge.to].stage,158,105)
    text('Requirements '..page..'/'..pages..'  (Left/Right)',8,120)
    for i=(page-1)*4+1,math.min(page*4,#lines) do text(lines[i],8,134+(i-1)%4*12) end
    text(ready and 'Confirm: Digivolve   Cancel: Back' or 'Requirements unmet. Cancel: Back',8,187)
    text('Level resets to 1. Skills and training stay.',8,201)
  end
  local ok,err=pcall(function()
    currentArt=Art(character.BaseForm.Species,8,38,64)
    targetArt=Art(edge.to,158,38,64)
    menu=RogueEssence.Menu.ScriptableMenu(8,8,304,224,function(input)
      local keys=RogueEssence.FrameInput.InputType
      if input:JustPressed(keys.Cancel) or input:JustPressed(keys.Menu) then _MENU:RemoveMenu()
      elseif input:JustPressed(keys.Confirm) and ready then confirmed=true;_MENU:RemoveMenu()
      elseif input.Direction == RogueElements.Dir8.Right and lastDirection ~= input.Direction then page=page%pages+1;rebuild()
      elseif input.Direction == RogueElements.Dir8.Left and lastDirection ~= input.Direction then page=(page-2)%pages+1;rebuild() end
      lastDirection=input.Direction
    end)
    rebuild();UI:SetCustomMenu(menu);UI:WaitForChoice()
  end)
  if currentArt then currentArt:Dispose() end
  if targetArt then targetArt:Dispose() end
  if not ok then error(err) end
  return confirmed
end
return M
