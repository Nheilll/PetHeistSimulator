-- ServerScriptService/EggServerScripts/PetHatchServer
-- Version 2: each pet has a permanent PetId and saved size attributes.
-- Existing egg pickup, transport, placement and crack scripts are not changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local PetConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))
local bases = Workspace:WaitForChild("Bases")
local store = DataStoreService:GetDataStore("PlayerPets_v1")
local AUTOSAVE_INTERVAL, RETRIES, ANIMATION_TIMEOUT, EGG_DESTROY_DELAY = 60, 4, 18, 2

local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
remotes.Name = "RemoteEvents"
remotes.Parent = ReplicatedStorage
local function remote(name)
 local r = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
 r.Name = name; r.Parent = remotes; return r
end
local petHatchedEvent = remote("PetHatched")
local hatchDoneEvent = remote("HatchAnimationDone")

type PetRecord = {PetId:string,PetName:string,Rarity:string,PetScale:number,SizeTier:string,Mutation:string,CreatedAt:number}
type Profile = {PetRecords:{PetRecord},CanSave:boolean,Dirty:boolean,Saving:boolean}
local profiles: {[Player]:Profile} = {}
local activeSaves = 0

local function retry(fn)
 local last
 for i=1,RETRIES do
  local ok,result=pcall(fn)
  if ok then return true,result end
  last=result; task.wait(i*1.25)
 end
 return false,last
end
local function key(player) return "Player_"..player.UserId end
local function countByName(records,name)
 local n=0; for _,r in ipairs(records) do if r.PetName==name then n+=1 end end; return n
end
local function syncInventory(player,profile)
 local inv=player:FindFirstChild("PetInventory") or Instance.new("Folder")
 inv.Name="PetInventory"; inv.Parent=player
 local counts={}
 for _,r in ipairs(profile.PetRecords) do counts[r.PetName]=(counts[r.PetName] or 0)+1 end
 for _,child in ipairs(inv:GetChildren()) do
  if child:IsA("IntValue") and not counts[child.Name] then child:Destroy() end
 end
 for name,n in pairs(counts) do
  local v=inv:FindFirstChild(name)
  if not v then v=Instance.new("IntValue"); v.Name=name; v.Parent=inv end
  v.Value=n
  local _,rarity=PetConfig.FindPet(name); v:SetAttribute("Rarity",rarity or "Common")
 end
end
local function syncRecords(player,profile)
 local folder=player:FindFirstChild("PetRecords") or Instance.new("Folder")
 folder.Name="PetRecords"; folder.Parent=player
 local keep={}
 for _,r in ipairs(profile.PetRecords) do
  keep[r.PetId]=true
  local f=folder:FindFirstChild(r.PetId) or Instance.new("Folder")
  f.Name=r.PetId
  f:SetAttribute("PetId",r.PetId)
  f:SetAttribute("PetName",r.PetName)
  f:SetAttribute("Rarity",r.Rarity)
  f:SetAttribute("PetScale",r.PetScale)
  f:SetAttribute("SizeTier",r.SizeTier)
  f:SetAttribute("Mutation",r.Mutation or "None")
  f:SetAttribute("CreatedAt",r.CreatedAt or 0)
  f.Parent=folder
 end
 for _,f in ipairs(folder:GetChildren()) do if not keep[f.Name] then f:Destroy() end end
end
local function syncAll(player,profile)
 syncRecords(player,profile); syncInventory(player,profile)
end
local function normalizeRecord(raw)
 if typeof(raw)~="table" or typeof(raw.PetName)~="string" then return nil end
 local _,rarity=PetConfig.FindPet(raw.PetName); if not rarity then return nil end
 local scale=tonumber(raw.PetScale) or 1
 scale=math.clamp(scale,PetConfig.SizeRange.Min,PetConfig.SizeRange.Max)
 return {
  PetId=typeof(raw.PetId)=="string" and raw.PetId or HttpService:GenerateGUID(false),
  PetName=raw.PetName,Rarity=rarity,PetScale=scale,
  SizeTier=typeof(raw.SizeTier)=="string" and raw.SizeTier or "Normal",
  Mutation=typeof(raw.Mutation)=="string" and raw.Mutation or "None",
  CreatedAt=tonumber(raw.CreatedAt) or os.time()
 }
end
local function loadProfile(player)
 local p=profiles[player]; if not p then return end
 local ok,data=retry(function() return store:GetAsync(key(player)) end)
 if profiles[player]~=p then return end
 if not ok then
  p.CanSave=false; warn("[PetHatch] Data load failed; saving disabled for",player.Name,data)
 else
  if typeof(data)=="table" and typeof(data.PetRecords)=="table" then
   for _,raw in ipairs(data.PetRecords) do local r=normalizeRecord(raw); if r then table.insert(p.PetRecords,r) end end
  elseif typeof(data)=="table" and typeof(data.Pets)=="table" then
   -- Legacy count-only pets cannot recover their old random size; migrate as standard 1.0.
   for name,count in pairs(data.Pets) do
    if typeof(name)=="string" and typeof(count)=="number" then
     local _,rarity=PetConfig.FindPet(name)
     for _=1,math.clamp(math.floor(count),0,1000) do
      if rarity then table.insert(p.PetRecords,{PetId=HttpService:GenerateGUID(false),PetName=name,Rarity=rarity,PetScale=1,SizeTier="Normal",Mutation="None",CreatedAt=os.time()}) end
     end
    end
   end
   p.Dirty=true
  end
  p.CanSave=true
 end
 syncAll(player,p)
 player:SetAttribute("PetsSaveEnabled",p.CanSave)
 player:SetAttribute("PetsLoaded",true)
end
local function saveProfile(player,p)
 if not p.CanSave then return false end
 while p.Saving do task.wait(.1) end
 if not p.Dirty then return true end
 p.Saving=true; p.Dirty=false; activeSaves+=1
 local snapshot={}
 for i,r in ipairs(p.PetRecords) do snapshot[i]=table.clone(r) end
 local counts={}
 for _,r in ipairs(snapshot) do counts[r.PetName]=(counts[r.PetName] or 0)+1 end
 local ok,err=retry(function()
  return store:UpdateAsync(key(player),function()
   return {Version=2,PetRecords=snapshot,Pets=counts}
  end)
 end)
 p.Saving=false; activeSaves-=1
 if not ok then p.Dirty=true; warn("[PetHatch] Save failed:",player.UserId,err) end
 return ok
end
local function awardPet(player,petName,rarity,scale,tier)
 local p=profiles[player]; if not p or not p.CanSave or player:GetAttribute("PetsLoaded")~=true then return nil end
 scale=math.clamp(tonumber(scale) or PetConfig.SizeRange.Default,PetConfig.SizeRange.Min,PetConfig.SizeRange.Max)
 tier=typeof(tier)=="string" and tier or "Normal"
 local record={PetId=HttpService:GenerateGUID(false),PetName=petName,Rarity=rarity,PetScale=scale,SizeTier=tier,Mutation="None",CreatedAt=os.time()}
 table.insert(p.PetRecords,record); p.Dirty=true
 syncAll(player,p)
 task.spawn(saveProfile,player,p)
 return record
end
local function onAdded(player)
 local p={PetRecords={},CanSave=false,Dirty=false,Saving=false}; profiles[player]=p
 player:SetAttribute("PetsLoaded",false)
 loadProfile(player)
end
Players.PlayerAdded:Connect(onAdded)
for _,p in ipairs(Players:GetPlayers()) do task.spawn(onAdded,p) end
Players.PlayerRemoving:Connect(function(player)
 local p=profiles[player]
 if p then saveProfile(player,p); profiles[player]=nil end
end)
task.spawn(function()
 while true do task.wait(AUTOSAVE_INTERVAL)
  for player,p in pairs(profiles) do if p.Dirty then task.spawn(saveProfile,player,p) end end
 end
end)
game:BindToClose(function()
 for player,p in pairs(profiles) do task.spawn(saveProfile,player,p) end
 while activeSaves>0 do task.wait(.1) end
end)

local pending={}
local watched=setmetatable({},{__mode="k"})
local function finish(egg)
 local d=pending[egg]; if not d or d.Done then return end
 d.Done=true
 local owner=Players:GetPlayerByUserId(d.OwnerId)
 if owner then
  local deadline=os.clock()+12
  while owner.Parent==Players and owner:GetAttribute("PetsLoaded")~=true and os.clock()<deadline do task.wait(.1) end
  if owner.Parent==Players then
   local record=awardPet(owner,d.PetName,d.Rarity,d.PetScale,d.SizeTier)
   if record then
    -- A hatch begins in the Pet Bag. The player equips it from the custom inventory.
    d.PetId=record.PetId
   end
  end
 end
 task.delay(EGG_DESTROY_DELAY,function() if egg.Parent then egg:Destroy() end; pending[egg]=nil end)
end
local function hatchEgg(egg)
 if pending[egg] or egg:GetAttribute("Hatched")==true then return end
 local name,rarity=PetConfig.RollPet(egg:GetAttribute("EggType"))
 if not name or not rarity then return end
 local ownerId=egg:GetAttribute("PlacedByUserId")
 if typeof(ownerId)~="number" or ownerId<=0 or not Players:GetPlayerByUserId(ownerId) then return end
 local scale,tier=PetConfig.RollPetScale()
 pending[egg]={PetName=name,Rarity=rarity,OwnerId=ownerId,PetScale=scale,SizeTier=tier,Done=false}
 egg:SetAttribute("Hatched",true)
 petHatchedEvent:FireAllClients(egg,name,rarity,ownerId,scale,tier)
 task.delay(ANIMATION_TIMEOUT,function() finish(egg) end)
end
hatchDoneEvent.OnServerEvent:Connect(function(player,egg)
 if typeof(egg)~="Instance" or not egg:IsA("Model") then return end
 local d=pending[egg]
 if not d or d.OwnerId~=player.UserId or d.Done then return end
 finish(egg)
end)
local function watchEgg(obj)
 if not obj:IsA("Model") or obj:GetAttribute("EggType")==nil or watched[obj] then return end
 watched[obj]=true
 local function check() if obj:GetAttribute("HatchRequested")==true then hatchEgg(obj) end end
 obj:GetAttributeChangedSignal("HatchRequested"):Connect(check); check()
end
for _,obj in ipairs(bases:GetDescendants()) do watchEgg(obj) end
bases.DescendantAdded:Connect(function(obj) task.defer(watchEgg,obj) end)
print("[PetHatch] Individual pet record system loaded.")
