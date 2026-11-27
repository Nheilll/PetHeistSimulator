-- StarterGui/PetBackpackGui/PetBackpackController
-- One card per unique saved PetId. Equipped pets disappear from this Pet Bag.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local PetConfig=require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))
local remotes=ReplicatedStorage:WaitForChild("RemoteEvents")
local equipEvent=remotes:WaitForChild("GrantPetTool")
local unequipEvent=remotes:WaitForChild("StorePetTool")
local gui=script.Parent
gui.ResetOnSpawn=false; gui.Enabled=true; gui.DisplayOrder=math.max(gui.DisplayOrder,15)
local backpackButton=gui:WaitForChild("BackpackButton")
local panel=gui:WaitForChild("Panel")
local grid=panel:WaitForChild("Grid")
local cardTemplate=panel:WaitForChild("CardTemplate")
local closeButton=panel:FindFirstChild("CloseButton",true)
local unequipAllButton=gui:FindFirstChild("UnequipButton") or gui:FindFirstChild("UneqiupButton")
cardTemplate.Visible=false; panel.Visible=false
if unequipAllButton then unequipAllButton.Visible=false end
local cards={}
local refreshQueued=false
local function getRecords()
 local folder=player:FindFirstChild("PetRecords")
 local list={}
 if folder then
  for _,f in ipairs(folder:GetChildren()) do
   if f:IsA("Folder") and typeof(f:GetAttribute("PetName"))=="string" then
    table.insert(list,{id=f.Name,folder=f,name=f:GetAttribute("PetName"),rarity=f:GetAttribute("Rarity") or "Common",scale=f:GetAttribute("PetScale") or 1,tier=f:GetAttribute("SizeTier") or "Normal",mutation=f:GetAttribute("Mutation") or "None"})
   end
  end
 end
 table.sort(list,function(a,b)
  local ra,rb=PetConfig.GetRarityIndex(a.rarity),PetConfig.GetRarityIndex(b.rarity)
  if ra~=rb then return ra<rb end
  if a.name~=b.name then return a.name<b.name end
  return a.id<b.id
 end)
 return list
end
local function findTool(petId)
 for _,container in ipairs({player:FindFirstChildOfClass("Backpack"),player.Character}) do
  if container then for _,obj in ipairs(container:GetChildren()) do
   if obj:IsA("Tool") and obj:GetAttribute("IsPetTool")==true and obj:GetAttribute("PetId")==petId then return obj end
  end end
 end
 return nil
end
local function clearViewport(v)
 for _,x in ipairs(v:GetChildren()) do if x:IsA("WorldModel") or x:IsA("Camera") then x:Destroy() end end
 v.CurrentCamera=nil
end
local function preview(v,entry)
 clearViewport(v)
 local source=PetConfig.FindPet(entry.name)
 if not source then return end
 local world=Instance.new("WorldModel"); world.Parent=v
 local clone=source:Clone()
 for _,d in ipairs(clone:GetDescendants()) do
  if d:IsA("BasePart") then d.Anchored=true; d.CanCollide=false; d.CanTouch=false; d.CanQuery=false
  elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") then d:Destroy() end
 end
 clone.Parent=world
 pcall(function() clone:ScaleTo(math.clamp(entry.scale,PetConfig.SizeRange.Min,PetConfig.SizeRange.Max)) end)
 clone:PivotTo(CFrame.identity)
 local cf,size=clone:GetBoundingBox()
 local maxDim=math.max(size.X,size.Y,size.Z,.75)
 local camera=Instance.new("Camera"); camera.FieldOfView=35
 camera.CFrame=CFrame.lookAt(cf.Position+Vector3.new(maxDim*.85,maxDim*.65,-maxDim*2.3),cf.Position)
 camera.Parent=v; v.CurrentCamera=camera
end
local function refresh()
 for _,c in pairs(cards) do if c and c.Parent then c:Destroy() end end
 table.clear(cards)
 local entries=getRecords()
 local unequipped=0
 for _,e in ipairs(entries) do if not findTool(e.id) then unequipped+=1 end end
 for order,e in ipairs(entries) do
  local equipped=findTool(e.id)~=nil
  if not equipped then
   local card=cardTemplate:Clone()
   card.Name="Pet_"..e.id; card.LayoutOrder=order; card.Visible=true; card.Parent=grid
   cards[e.id]=card
   local name=card:FindFirstChild("NameLabel",true)
   local rarity=card:FindFirstChild("RarityLabel",true)
   local size=card:FindFirstChild("SizeLabel",true)
   local action=card:FindFirstChild("ActionButton",true)
   local viewport=card:FindFirstChild("Preview",true)
   local display=PetConfig.GetDisplayName(e.name)
   if name then name.Text=display end
   if rarity then rarity.Text=string.upper(e.rarity)..(e.mutation~="None" and " • "..string.upper(e.mutation) or ""); rarity.TextColor3=PetConfig.RarityColors[e.rarity] or Color3.new(1,1,1) end
   if size then size.Text=string.format("Size: %.2fx (%s)",e.scale,e.tier) end
   local stroke=card:FindFirstChildWhichIsA("UIStroke")
   if stroke then stroke.Color=PetConfig.RarityColors[e.rarity] or Color3.new(1,1,1) end
   if viewport and viewport:IsA("ViewportFrame") then preview(viewport,e) end
   if action then
    action.Text="Equip"; action.Active=true
    local busy=false
    action.MouseButton1Click:Connect(function()
     if busy or not e.folder.Parent then return end
     busy=true; equipEvent:FireServer(e.id)
     task.delay(.4,function() busy=false end)
    end)
   end
  end
 end
 if unequipAllButton then unequipAllButton.Visible=panel.Visible and #entries>unequipped end
end
local function queueRefresh()
 if refreshQueued then return end
 refreshQueued=true
 task.defer(function() refreshQueued=false; refresh() end)
end
backpackButton.MouseButton1Click:Connect(function() panel.Visible=not panel.Visible; if panel.Visible then refresh() end end)
if closeButton and closeButton:IsA("GuiButton") then closeButton.MouseButton1Click:Connect(function() panel.Visible=false end) end
if unequipAllButton and unequipAllButton:IsA("GuiButton") then unequipAllButton.MouseButton1Click:Connect(function() unequipEvent:FireServer(nil,true); task.delay(.2,refresh) end) end
local function hook(container)
 if container then container.ChildAdded:Connect(queueRefresh); container.ChildRemoved:Connect(queueRefresh) end
end
local function bind()
 hook(player:FindFirstChildOfClass("Backpack")); hook(player.Character)
end
player.ChildAdded:Connect(function(c) if c:IsA("Backpack") then bind(); queueRefresh() elseif c.Name=="PetRecords" then c.ChildAdded:Connect(queueRefresh); c.ChildRemoved:Connect(queueRefresh); queueRefresh() end end)
player.CharacterAdded:Connect(function() task.wait(.2); bind(); queueRefresh() end)
local records=player:WaitForChild("PetRecords")
records.ChildAdded:Connect(queueRefresh); records.ChildRemoved:Connect(queueRefresh)
bind(); refresh()
print("[PetBackpackController] PetId-based Pet Bag loaded.")
