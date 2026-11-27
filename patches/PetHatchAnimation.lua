-- LocalScript: StarterPlayer/StarterPlayerScripts/PetHatchAnimation
-- Visuals for the egg:
--   * every tap (crack 1, 2, 3): shell shards, dust and a crack sound
--   * after the 3rd crack: wobble -> burst -> pet grows out of the egg -> rarity reveal
--   * the egg's owner also gets a "You hatched ..." banner
--   * once the animation finishes for the owner, requests the pet Tool from the server

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local PetConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PetConfig"))
local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local crackEvent = remotes:WaitForChild("EggCrackAnimation")
local hatchedEvent = remotes:WaitForChild("PetHatched")
local hatchDoneEvent = remotes:WaitForChild("HatchAnimationDone") :: RemoteEvent

-- SETTINGS (seconds)
local WOBBLE_TIME = 1.0
local PET_GROW_TIME = 0.9
local PET_SHOW_TIME = 3.2
local PET_LEAVE_TIME = 0.4

local rng = Random.new()

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function tween(object: Instance, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(
		object,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goal
	)
	t:Play()
	return t
end

local function makeAnchor(cf: CFrame): Part
	local part = Instance.new("Part")
	part.Name = "HatchFx"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = cf
	part.Parent = Workspace
	return part
end

local function playSoundAt(soundId: string?, parent: Instance, volume: number?, speed: number?)
	if not soundId or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.7
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMaxDistance = 90
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 4)
end

local function burstParticles(parent: Instance, color: Color3, count: number, speed: number, size: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.45, 0.9)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Drag = 2
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = parent
	emitter:Emit(count)
	return emitter
end

-- Colour of the biggest part of the egg (used for shards / dust).
local function getEggColor(egg: Model): Color3
	local bestPart: BasePart? = nil
	local bestVolume = -1
	for _, descendant in ipairs(egg:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
			if volume > bestVolume then
				bestVolume = volume
				bestPart = descendant
			end
		end
	end
	return if bestPart then bestPart.Color else Color3.new(1, 1, 1)
end

-- Little pieces of shell that pop out, then fall and fade.
local function spawnShards(center: Vector3, size: Vector3, color: Color3, count: number)
	for _ = 1, count do
		local shard = Instance.new("Part")
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanTouch = false
		shard.CanQuery = false
		shard.Material = Enum.Material.SmoothPlastic
		shard.Color = color
		local d = math.max(size.Y * rng:NextNumber(0.07, 0.15), 0.12)
		shard.Size = Vector3.new(d, d * 0.45, d * rng:NextNumber(0.6, 1))

		local startPos = center
			+ Vector3.new(
				rng:NextNumber(-1, 1) * size.X * 0.3,
				rng:NextNumber(-0.2, 0.6) * size.Y * 0.5,
				rng:NextNumber(-1, 1) * size.Z * 0.3
			)
		shard.CFrame = CFrame.new(startPos)
			* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
		shard.Parent = Workspace
		Debris:AddItem(shard, 2)

		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.6, 1.4), rng:NextNumber(-1, 1)).Unit
		local peak = startPos + dir * (size.Y * rng:NextNumber(0.5, 1.1))
		local rise = tween(shard, 0.35, {
			Position = peak,
			Orientation = Vector3.new(rng:NextNumber(0, 360), rng:NextNumber(0, 360), rng:NextNumber(0, 360)),
		})
		rise.Completed:Connect(function()
			if shard.Parent then
				local fall = tween(shard, 0.45, {
					Position = peak - Vector3.new(0, size.Y * 0.9, 0),
					Transparency = 1,
				}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				fall.Completed:Connect(function()
					shard:Destroy()
				end)
			end
		end)
	end
end

-- Flat glowing ring that expands outwards on the floor.
local function spawnShockwave(position: Vector3, color: Color3, maxDiameter: number)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.3
	ring.Size = Vector3.new(0.15, 1, 1)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace
	Debris:AddItem(ring, 1.5)

	local t = tween(ring, 0.7, { Size = Vector3.new(0.15, maxDiameter, maxDiameter), Transparency = 1 })
	t.Completed:Connect(function()
		ring:Destroy()
	end)
end

--------------------------------------------------
-- TAP / CRACK EFFECT (plays on every crack, 1-3)
--------------------------------------------------

local function playCrackEffect(egg: Model, crackNumber: number)
	if not egg.Parent then
		return
	end
	local cf, size = egg:GetBoundingBox()
	local color = getEggColor(egg)

	local fx = makeAnchor(CFrame.new(cf.Position + Vector3.new(0, size.Y * 0.3, 0)))
	Debris:AddItem(fx, 2)

	playSoundAt(PetConfig.Sounds.Crack, fx, 0.8, 0.85 + 0.15 * crackNumber)
	burstParticles(fx, color, 6 + 4 * crackNumber, math.max(size.Y * 1.5, 3), 0.5)
	spawnShards(cf.Position, size, color, 3 + 3 * crackNumber)
end

crackEvent.OnClientEvent:Connect(function(egg, crackNumber)
	if typeof(egg) ~= "Instance" or not egg:IsA("Model") or typeof(crackNumber) ~= "number" then
		return
	end
	task.spawn(playCrackEffect, egg, crackNumber)
end)

--------------------------------------------------
-- OWNER BANNER: "You hatched a Fox!"
--------------------------------------------------

local toastGui: ScreenGui? = nil

local function getToastGui(): ScreenGui
	if toastGui and toastGui.Parent then
		return toastGui
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PetRevealToast"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")
	toastGui = gui
	return gui
end

local function showToast(petName: string, displayName: string, rarity: string, color: Color3)
	local gui = getToastGui()

	-- "NEW!" if this is the first one of this pet in the collection.
	local isNew = false
	local inventory = player:FindFirstChild("PetInventory")
	local entry = inventory and inventory:FindFirstChild(petName)
	if entry and entry:IsA("IntValue") and entry.Value == 1 then
		isNew = true
	end

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, -120)
	card.Size = UDim2.fromOffset(340, 84)
	card.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
	card.BorderSizePixel = 0
	card.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 3
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 8)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 30
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = (if isNew then "NEW! " else "") .. displayName
	title.Parent = card

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 48)
	subtitle.Size = UDim2.new(1, 0, 0, 26)
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextSize = 16
	subtitle.TextColor3 = color
	subtitle.Text = string.upper(rarity) .. "  •  Added to your pets"
	subtitle.Parent = card

	tween(card, 0.45, { Position = UDim2.new(0.5, 0, 0, 16) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.wait(3.2)
	local out = tween(card, 0.3, { Position = UDim2.new(0.5, 0, 0, -120) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	out.Completed:Wait()
	card:Destroy()
end

--------------------------------------------------
-- NAME + RARITY TAG ABOVE THE PET
--------------------------------------------------

local function makeNameTag(adornee: BasePart, displayName: string, rarity: string, color: Color3, studsUp: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PetRevealTag"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 150
	gui.Size = UDim2.fromOffset(300, 100)
	gui.StudsOffsetWorldSpace = Vector3.new(0, studsUp, 0)
	gui.Parent = adornee

	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = gui

	local function makeLabel(text: string, size: number, textColor: Color3, y: number, height: number)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.new(0, 0, y, 0)
		label.Size = UDim2.new(1, 0, height, 0)
		label.Font = Enum.Font.FredokaOne
		label.TextSize = size
		label.TextColor3 = textColor
		label.Text = text
		label.Parent = gui

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = Color3.fromRGB(20, 20, 28)
		stroke.Parent = label
	end

	makeLabel(displayName, 40, Color3.new(1, 1, 1), 0, 0.5)
	makeLabel(string.upper(rarity), 30, color, 0.5, 0.5)

	tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	return gui, scale
end

--------------------------------------------------
-- THE HATCH
--------------------------------------------------

local activeHatch = {}

local function getContext(egg: Model)
	local eggCF, eggSize = egg:GetBoundingBox()
	local center = eggCF.Position
	return {
		Center = center,
		EggSize = eggSize,
		FloorPos = Vector3.new(center.X, center.Y - eggSize.Y / 2, center.Z),
		EggColor = getEggColor(egg),
	}
end

-- PART 1: the egg wobbles, flashes and the shell flies apart.
local function playEggBurst(egg: Model, ctx, rarity: string, temp: { Instance })
	local center, eggSize, floorPos, eggColor = ctx.Center, ctx.EggSize, ctx.FloorPos, ctx.EggColor
	local rarityColor = PetConfig.RarityColors[rarity] or Color3.new(1, 1, 1)
	local rarityIndex = PetConfig.GetRarityIndex(rarity)
	local baseCF = CFrame.new(floorPos)
	local original = egg:GetPivot()

	-- Hide the egg's timer, glow, sparkles and prompt.
	local parts = {}
	for _, descendant in ipairs(egg:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		elseif descendant:IsA("BillboardGui") or descendant:IsA("Highlight") or descendant:IsA("ProximityPrompt") then
			descendant.Enabled = false
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end

	local fx = makeAnchor(CFrame.new(center))
	table.insert(temp, fx)
	local light = Instance.new("PointLight")
	light.Color = rarityColor
	light.Range = math.max(eggSize.Y * 3, 12)
	light.Brightness = 0
	light.Parent = fx

	-- Wobble: the egg shakes harder and harder.
	local startTime = os.clock()
	local wobbleConnection
	wobbleConnection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startTime
		if t >= WOBBLE_TIME or not egg.Parent then
			wobbleConnection:Disconnect()
			return
		end
		local a = t / WOBBLE_TIME
		local amp = math.rad(3 + 13 * a)
		local rot = CFrame.Angles(math.sin(t * 37) * amp * 0.6, 0, math.sin(t * 29) * amp)
		egg:PivotTo(baseCF * rot * baseCF:ToObjectSpace(original))
		light.Brightness = 0.5 + 4 * a
	end)

	for _, delayTime in ipairs({ 0.25, 0.55, 0.8 }) do
		task.delay(delayTime, function()
			if egg.Parent then
				playSoundAt(PetConfig.Sounds.Crack, fx, 0.7, 0.9 + delayTime * 0.4)
				spawnShards(center, eggSize, eggColor, 5)
			end
		end)
	end

	task.wait(WOBBLE_TIME)
	if wobbleConnection.Connected then
		wobbleConnection:Disconnect()
	end
	if egg.Parent then
		egg:PivotTo(original)
	end

	-- Burst
	playSoundAt(PetConfig.Sounds.Burst, fx, 0.9, 1)

	local flash = Instance.new("Part")
	table.insert(temp, flash)
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = rarityColor:Lerp(Color3.new(1, 1, 1), 0.5)
	flash.Transparency = 0.2
	flash.Size = Vector3.one * math.max(eggSize.Y * 0.6, 1)
	flash.CFrame = CFrame.new(center)
	flash.Parent = Workspace
	tween(flash, 0.45, { Size = Vector3.one * math.max(eggSize.Y * 3.2, 4), Transparency = 1 })

	light.Brightness = 8
	tween(light, 0.8, { Brightness = 1.5 })

	for _, part in ipairs(parts) do
		local away = part.Position - center
		local dir = if away.Magnitude > 0.05 then away.Unit else Vector3.yAxis
		dir = (dir + Vector3.new(0, 0.6, 0)).Unit
		local distance = eggSize.Y * rng:NextNumber(0.6, 1.3)
		tween(part, 0.6, {
			CFrame = part.CFrame * CFrame.Angles(rng:NextNumber(-2, 2), rng:NextNumber(-2, 2), rng:NextNumber(-2, 2))
				+ dir * distance,
			Transparency = 1,
		})
	end

	spawnShards(center, eggSize, eggColor, 22)
	burstParticles(fx, eggColor, 30, math.max(eggSize.Y * 3, 6), 0.9)
	burstParticles(fx, rarityColor, 25 + 12 * rarityIndex, math.max(eggSize.Y * 4, 8), 0.7)
	spawnShockwave(floorPos, rarityColor, eggSize.Y * (2 + rarityIndex * 0.6))
end

-- PART 2: the pet grows out of the egg and its rarity is revealed.
local function playPetReveal(ctx, petName: string, rarity: string, temp: { Instance })
	local template = PetConfig.FindPet(petName)
	if not template then
		warn("[PetHatch] No pet model named", petName, "in ReplicatedStorage.World1.Pets")
		return
	end

	local floorPos, eggSize = ctx.FloorPos, ctx.EggSize
	local displayName = PetConfig.GetDisplayName(petName)
	local rarityColor = PetConfig.RarityColors[rarity] or Color3.new(1, 1, 1)
	local rarityIndex = PetConfig.GetRarityIndex(rarity)

	local pet = template:Clone()
	table.insert(temp, pet)

	local petParts = {}
	for _, descendant in ipairs(pet:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			table.insert(petParts, descendant)
		elseif
			descendant:IsA("Weld")
			or descendant:IsA("WeldConstraint")
			or descendant:IsA("ManualWeld")
			or descendant:IsA("Motor6D")
			or descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("ProximityPrompt")
		then
			descendant:Destroy()
		end
	end
	if #petParts == 0 then
		warn("[PetHatch] Pet model has no parts:", petName)
		return
	end

	local boxCF, boxSize = pet:GetBoundingBox()
	local anchorPoint = Vector3.new(boxCF.Position.X, boxCF.Position.Y - boxSize.Y / 2, boxCF.Position.Z)
	local partData = {}
	for _, part in ipairs(petParts) do
		table.insert(partData, {
			Part = part,
			Size = part.Size,
			Rel = part.Position - anchorPoint,
			Rot = part.CFrame - part.Position,
		})
	end

	local camera = Workspace.CurrentCamera
	local toCamera = if camera then camera.CFrame.Position - ctx.Center else Vector3.zAxis
	toCamera = Vector3.new(toCamera.X, 0, toCamera.Z)
	local rotation = CFrame.identity
	if toCamera.Magnitude > 0.1 then
		rotation = CFrame.lookAt(Vector3.zero, toCamera)
	end

	local naturalMax = math.max(boxSize.X, boxSize.Y, boxSize.Z, 0.1)
	local targetMax = math.max(eggSize.Y * 0.9, 2.5)
	local targetMult = targetMax / naturalMax
	local petHeight = boxSize.Y * targetMult

	local function applyMult(mult: number, lift: number, sway: CFrame)
		mult = math.max(mult, 0.01)
		local root = CFrame.new(floorPos + Vector3.new(0, lift, 0)) * rotation * sway
		for _, data in ipairs(partData) do
			local s = data.Size * mult
			data.Part.Size = Vector3.new(math.max(s.X, 0.001), math.max(s.Y, 0.001), math.max(s.Z, 0.001))
			data.Part.CFrame = root * CFrame.new(data.Rel * mult) * data.Rot
		end
	end

	local multValue = Instance.new("NumberValue")
	table.insert(temp, multValue)
	multValue.Value = targetMult * 0.05
	applyMult(multValue.Value, 0, CFrame.identity)
	pet.Parent = Workspace

	local growConnection = multValue:GetPropertyChangedSignal("Value"):Connect(function()
		applyMult(multValue.Value, 0, CFrame.identity)
	end)

	tween(multValue, PET_GROW_TIME, { Value = targetMult }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.wait(PET_GROW_TIME * 0.7)

	local petFx = makeAnchor(CFrame.new(floorPos + Vector3.new(0, petHeight / 2, 0)))
	table.insert(temp, petFx)
	local petLight = Instance.new("PointLight")
	petLight.Color = rarityColor
	petLight.Range = math.max(petHeight * 4, 10)
	petLight.Brightness = 1 + rarityIndex * 0.4
	petLight.Parent = petFx

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Rate = 14 + rarityIndex * 10
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Speed = NumberRange.new(2, 6)
	sparkles.SpreadAngle = Vector2.new(360, 360)
	sparkles.Acceleration = Vector3.new(0, 3, 0)
	sparkles.LightEmission = 1
	sparkles.Color = ColorSequence.new(rarityColor)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Parent = petFx

	playSoundAt(PetConfig.Sounds.Reveal, petFx, 0.8, 0.8 + rarityIndex * 0.08)
	if rarityIndex >= 4 then
		burstParticles(petFx, rarityColor, 40 + rarityIndex * 10, math.max(petHeight * 4, 10), 0.9)
		spawnShockwave(floorPos, rarityColor, petHeight * 4)
	end

	local tagGui, tagScale = makeNameTag(petFx, displayName, rarity, rarityColor, petHeight / 2 + 1.6)
	table.insert(temp, tagGui)

	task.wait(PET_GROW_TIME * 0.3)

	local showStart = os.clock()
	local showConnection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - showStart
		local hop = math.abs(math.sin(t * 3)) * petHeight * 0.08
		applyMult(targetMult, hop, CFrame.Angles(0, math.sin(t * 2) * 0.25, 0))
	end)
	task.wait(PET_SHOW_TIME)
	showConnection:Disconnect()
	sparkles.Enabled = false

	tween(multValue, PET_LEAVE_TIME, { Value = targetMult * 0.02 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(tagScale, PET_LEAVE_TIME, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.wait(PET_LEAVE_TIME)
	growConnection:Disconnect()
end

hatchedEvent.OnClientEvent:Connect(function(egg, petName, rarity, ownerUserId)
	if typeof(egg) ~= "Instance" or not egg:IsA("Model") then
		return
	end
	if typeof(petName) ~= "string" or typeof(rarity) ~= "string" then
		return
	end
	if activeHatch[egg] then
		return
	end
	activeHatch[egg] = true
	ownerUserId = if typeof(ownerUserId) == "number" then ownerUserId else 0

	task.spawn(function()
		local temp = {}

		local okContext, ctx = pcall(getContext, egg)
		if not okContext then
			warn("[PetHatch] could not read egg:", ctx)
			activeHatch[egg] = nil
			return
		end

		local okBurst, burstError = pcall(playEggBurst, egg, ctx, rarity, temp)
		if not okBurst then
			warn("[PetHatch] egg burst error:", burstError)
		end

		if ownerUserId == player.UserId then
			local displayName = PetConfig.GetDisplayName(petName)
			local color = PetConfig.RarityColors[rarity] or Color3.new(1, 1, 1)
			task.delay(0.8, showToast, petName, displayName, rarity, color)
		end

		local okPet, petError = pcall(playPetReveal, ctx, petName, rarity, temp)
		if not okPet then
			warn("[PetHatch] pet reveal error:", petError)
		end

		for _, instance in ipairs(temp) do
			if instance.Parent then
				instance:Destroy()
			end
		end

		-- Tell the server the reveal animation is complete. The pet is saved in the Pet Bag; equip it from there.
		if ownerUserId == player.UserId then
			hatchDoneEvent:FireServer(egg)
		end

		activeHatch[egg] = nil
	end)
end)