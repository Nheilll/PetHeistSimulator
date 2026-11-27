-- ServerScriptService/PetServerScripts/PetToolServer
-- Equip/unequip is keyed by PetId. The server validates ownership from PetRecords.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local PetConfig=require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))
local remotes=ReplicatedStorage:WaitForChild("RemoteEvents")
local function getRemote(name)
 local r=remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
 r.Name=name; r.Parent=remotes; return r
end
local equipEvent=getRemote("GrantPetTool")
local unequipEvent=getRemote("StorePetTool")
local last={}
local function allowed(player,action)
 last[player]=last[player] or {}
 local now=os.clock()
 if now-(last[player][action] or 0)<.15 then return false end
 last[player][action]=now; return true
end
local function findTemplate(name)
 for _,world in ipairs(ReplicatedStorage:GetChildren()) do
  if world.Name:match("^World%d+$") then
   local folder=world:FindFirstChild("PetTools")
   local t=folder and folder:FindFirstChild(name)
   if t and t:IsA("Tool") then return t end
  end
 end
end
local function findTools(player,petId)
 local result={}
 for _,container in ipairs({player:FindFirstChildOfClass("Backpack"),player.Character}) do
  if container then for _,obj in ipairs(container:GetChildren()) do
   if obj:IsA("Tool") and obj:GetAttribute("IsPetTool")==true and (not petId or obj:GetAttribute("PetId")==petId) then table.insert(result,obj) end
  end end
 end
 return result
end
local function applyScale(tool,scale)
 -- Prefer a Model inside the Tool so Model:ScaleTo scales parts and joints together.
 local model=tool:FindFirstChildWhichIsA("Model",true)
 if model then
  local ok,err=pcall(function() model:ScaleTo(scale) end)
  if not ok then warn("[PetToolServer] Model scaling failed:",err) end
  return
 end
 -- A Tool without a Model cannot be safely resized as a group; keep its authored geometry.
 warn("[PetToolServer] Tool has no Model descendant; kept template geometry. Add a Model around the pet mesh to enable saved sizing.")
end
equipEvent.OnServerEvent:Connect(function(player,petId)
 if typeof(petId)~="string" or #petId>64 or not allowed(player,"equip") then return end
 local records=player:FindFirstChild("PetRecords")
 local record=records and records:FindFirstChild(petId)
 if not record or not record:IsA("Folder") then return end
 if #findTools(player,petId)>0 then return end
 local petName=record:GetAttribute("PetName")
 if typeof(petName)~="string" then return end
 local template=findTemplate(petName)
 if not template then warn("[PetToolServer] Missing template:",petName); return end
 local backpack=player:FindFirstChildOfClass("Backpack")
 if not backpack then return end
 local tool=template:Clone()
 local display=PetConfig.GetDisplayName(petName)
 tool.Name=display; tool.ToolTip=display
 for _,attribute in ipairs({"PetId","PetName","Rarity","PetScale","SizeTier","Mutation","CreatedAt"}) do
  tool:SetAttribute(attribute,record:GetAttribute(attribute))
 end
 tool:SetAttribute("IsPetTool",true)
 applyScale(tool,tonumber(record:GetAttribute("PetScale")) or 1)
 tool.Parent=backpack
end)
unequipEvent.OnServerEvent:Connect(function(player,petId,removeAll)
 if not allowed(player,"unequip") then return end
 if removeAll==true then
  for _,tool in ipairs(findTools(player,nil)) do tool:Destroy() end
  return
 end
 if typeof(petId)~="string" then return end
 for _,tool in ipairs(findTools(player,petId)) do tool:Destroy(); break end
end)
Players.PlayerRemoving:Connect(function(player) last[player]=nil end)
print("[PetToolServer] PetId equip/unequip loaded.")
