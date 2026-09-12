require 'origin.services.baseservice'
local Ledger = require 'origin.digimon.scan_ledger'
local Catalog = require 'origin.digimon.catalog'
local Runtime = require 'origin.digimon.runtime_catalog'
local Progress = require 'origin.digimon.progression'
local Passives = require 'origin.digimon.passive_abilities'
local Service = Class('DigimonRuntime', BaseService)

function Service:NewGame()
  if not Ledger.valid(SV.Digimon) then return end
  _DATA.Save.NoRecruiting = true
  -- Fresh slice saves start with the hub services available; existing dialogue is untouched.
  SV.base_camp.IntroComplete = true
  SV.base_camp.ExpositionComplete = true
  require('origin.digimon.dungeon_access').ensure()
  Passives.team()
  for _,char in ipairs(GAME:GetPlayerPartyTable()) do
    if Runtime.species[char.BaseForm.Species] then
      char.Level=5;char.EXP=0;char.HP=char.MaxHP;Progress.progress(char)
    end
  end
end

local function cast(data, name)
  if data.BaseForm.Species=='snorlax' or name=='forest_camp:Snorlax' then
    data:Promote(RogueEssence.Dungeon.MonsterID('monzaemon',0,'normal',Gender.Genderless))
    return
  end
  if Runtime.species[data.BaseForm.Species] then return end
  local hash=Runtime.cast_seed
  for i=1,#name do hash=(hash*31+string.byte(name,i))%2147483647 end
  data:Promote(RogueEssence.Dungeon.MonsterID(Runtime.npc_pool[hash%#Runtime.npc_pool+1],0,'normal',Gender.Genderless))
end

function Service:Ground(name,map)
  require('origin.digimon.dungeon_access').ensure()
  if Ledger.valid(SV.Digimon) then Passives.team() end
  local camps={base_camp=true,base_camp_2=true,forest_camp=true,cliff_camp=true,
    canyon_camp=true,rest_stop=true,final_stop=true,guild_hut=true,post_office=true,
    guildmaster_summit=true}
  if not Ledger.valid(SV.Digimon) or not camps[name] then return end
  for i=0,map.Entities.Count-1 do
    local layer=map.Entities[i]
    for j=0,layer.MapChars.Count-1 do
      local char=layer.MapChars[j];cast(char.Data,name..':'..char.EntName)
    end
    for j=0,layer.Spawners.Count-1 do
      local spawner=layer.Spawners[j]
      if string.sub(spawner.EntName,1,9)~='ASSEMBLY_' then cast(spawner.NPCChar,name..':'..spawner.EntName) end
    end
  end
end

function Service:Floor(name,map)
  if not Ledger.valid(SV.Digimon) then return end
  Passives.team()
  if SV.Digimon.floor_identity~=map.RewardFloorIdentity then
    Ledger.begin_floor(SV.Digimon)
    SV.Digimon.floor_identity=map.RewardFloorIdentity
  end
  -- Convert fixed-map and event encounters too; procedural tables are converted in data.
  if map.MapTeams then
    for i=0,map.MapTeams.Count-1 do
      local team=map.MapTeams[i]
      for j=0,team.Players.Count-1 do
        local char=team.Players[j]
        if map:GetCharFaction(char)==RogueEssence.Dungeon.Faction.Foe then
          cast(char,_ZONE.CurrentZoneID..':'..tostring(map.RewardFloorIdentity)..':'..tostring(i)..':'..tostring(j))
          Passives.sync(char)
          if char.LuaDataTable then char.LuaDataTable.DigimonNatural=true end
        end
      end
    end
  end
end

function Service:Defeat(char)
  if not Ledger.valid(SV.Digimon) or not char.Dead or
    not char.LuaDataTable or char.LuaDataTable.DigimonNatural~=true or
    _ZONE.CurrentMap:GetCharFaction(char)~=RogueEssence.Dungeon.Faction.Foe then return end
  local award=Ledger.award(SV.Digimon,Catalog,{floor_sequence=SV.Digimon.floor_sequence,
    confirmed=true,source_kind='hostile',entity_id=char.RewardIdentity,
    species=char.BaseForm.Species,source_name=_ZONE.CurrentZoneID,variant=tostring(char.BaseForm.Form)})
  if not award then return end
  _DATA.Save.ActiveTeam.Money=_DATA.Save.ActiveTeam.Money+award.bits
  if award.credited>0 then
    _DUNGEON:LogMsg(Runtime.species[char.BaseForm.Species].name..' Scan Data '..award.points..'/'..Catalog.scan.unlock_threshold..(award.bits>0 and ' +'..award.bits..' Bits' or ''))
  end
  for _,member in ipairs(GAME:GetPlayerPartyTable()) do
    if not member.Dead and Runtime.species[member.BaseForm.Species] then
      local row=Progress.progress(member);row.bond=math.min(100,row.bond+1)
    end
  end
end

function Service:Subscribe(med)
  med:Subscribe('DigimonRuntime',EngineServiceEvents.NewGame,function() self:NewGame() end)
  med:Subscribe('DigimonRuntime',EngineServiceEvents.GroundMapInit,function(_,args) self:Ground(args[0],args[1]) end)
  med:Subscribe('DigimonRuntime',EngineServiceEvents.GroundMapEnter,function(_,args) self:Ground(args[0],args[1]) end)
  med:Subscribe('DigimonRuntime',EngineServiceEvents.DungeonFloorEnter,function(_,args) self:Floor(args[0],args[1]) end)
  med:Subscribe('DigimonRuntime','CharacterDefeated',function(_,args) self:Defeat(args[0]) end)
end
SCRIPT:AddService('DigimonRuntime',Service:new())
