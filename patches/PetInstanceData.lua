-- ModuleScript: ReplicatedStorage/Config/PetInstanceData
-- Individual pet records. Use these records as the authoritative inventory;
-- keep PetInventory IntValues as count-only replicas for existing collection UI.
-- Do not use pet names as unique identifiers.

local HttpService = game:GetService("HttpService")

local PetInstanceData = {}

local function validNumber(value, fallback, minimum, maximum)
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

function PetInstanceData.New(petName, rarity, scale, sizeTier)
	assert(typeof(petName) == "string" and petName ~= "", "petName required")
	assert(typeof(rarity) == "string" and rarity ~= "", "rarity required")

	return {
		PetId = HttpService:GenerateGUID(false),
		PetName = petName,
		Rarity = rarity,
		PetScale = validNumber(scale, 1, 0.2, 2.5),
		SizeTier = typeof(sizeTier) == "string" and sizeTier or "Normal",
		Mutation = "None",
		Attributes = {},
		CreatedAt = os.time(),
	}
end

-- Converts the old { Pets = { ["Fox"] = 3 } } format into three
-- individual records. Legacy pets receive the default size because their
-- original hatch sizes were never stored and cannot be recovered.
function PetInstanceData.MigrateLegacy(data)
	local result = {}
	if typeof(data) ~= "table" then
		return result
	end

	if typeof(data.PetRecords) == "table" then
		for id, record in pairs(data.PetRecords) do
			if typeof(id) == "string" and typeof(record) == "table"
				and typeof(record.PetName) == "string" then
				local copy = {
					PetId = id,
					PetName = record.PetName,
					Rarity = typeof(record.Rarity) == "string" and record.Rarity or "Common",
					PetScale = validNumber(record.PetScale, 1, 0.2, 2.5),
					SizeTier = typeof(record.SizeTier) == "string" and record.SizeTier or "Normal",
					Mutation = typeof(record.Mutation) == "string" and record.Mutation or "None",
					Attributes = typeof(record.Attributes) == "table" and record.Attributes or {},
					CreatedAt = typeof(record.CreatedAt) == "number" and record.CreatedAt or os.time(),
				}
				result[id] = copy
			end
		end
		return result
	end

	local legacyPets = typeof(data.Pets) == "table" and data.Pets or {}
	for petName, count in pairs(legacyPets) do
		if typeof(petName) == "string" and typeof(count) == "number" then
			for _ = 1, math.clamp(math.floor(count), 0, 10000) do
				local id = HttpService:GenerateGUID(false)
				result[id] = {
					PetId = id,
					PetName = petName,
					Rarity = "Common",
					PetScale = 1,
					SizeTier = "Normal",
					Mutation = "None",
					Attributes = {},
					CreatedAt = os.time(),
				}
			end
		end
	end
	return result
end

function PetInstanceData.CountByName(records)
	local counts = {}
	for _, record in pairs(records or {}) do
		if typeof(record) == "table" and typeof(record.PetName) == "string" then
			counts[record.PetName] = (counts[record.PetName] or 0) + 1
		end
	end
	return counts
end

function PetInstanceData.ApplyAttributes(instance, record)
	instance:SetAttribute("PetId", record.PetId)
	instance:SetAttribute("PetName", record.PetName)
	instance:SetAttribute("Rarity", record.Rarity)
	instance:SetAttribute("PetScale", validNumber(record.PetScale, 1, 0.2, 2.5))
	instance:SetAttribute("SizeTier", record.SizeTier or "Normal")
	instance:SetAttribute("Mutation", record.Mutation or "None")
	instance:SetAttribute("IsPetTool", true)
end

return PetInstanceData
