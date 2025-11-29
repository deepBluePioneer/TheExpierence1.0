local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local PlantService = Knit.CreateService {
	Name = "PlantService",
	Client = {},
}

-- === CONFIG ===
local PHOTO_TARGET_TAG = "PhotoTarget"
local TARGETS_FOLDER_NAME = "PhotoTargets"

local TARGET_CONFIG = {
	Color = Color3.fromRGB(255, 255, 0),  -- Yellow
	Size = Vector3.new(2, 2, 2),
	Material = Enum.Material.SmoothPlastic,
	SpawnCount = 20,
	SpawnRadius = 60,
	SpawnHeight = 1,  -- Height above ground
}

-- === HELPERS ===

local function getTargetsFolder()
	local folder = Workspace:FindFirstChild(TARGETS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = TARGETS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function clearTargets()
	local folder = Workspace:FindFirstChild(TARGETS_FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

local function createTarget(position)
	local model = Instance.new("Model")
	model.Name = "PhotoTarget_" .. math.random(1000, 9999)
	
	local part = Instance.new("Part")
	part.Name = "TargetPart"
	part.Size = TARGET_CONFIG.Size
	part.Position = position
	part.Color = TARGET_CONFIG.Color
	part.Material = TARGET_CONFIG.Material
	part.Anchored = true
	part.CanCollide = true
	part.Parent = model
	
	model.PrimaryPart = part
	
	-- Add tag to the model
	CollectionService:AddTag(model, PHOTO_TARGET_TAG)
	
	return model
end

-- === KNIT LIFECYCLE ===

function PlantService:KnitInit()
	print("[PlantService] Initializing...")
end

function PlantService:KnitStart()
	local folder = getTargetsFolder()
	
	-- Spawn targets scattered around
	for i = 1, TARGET_CONFIG.SpawnCount do
		local angle = math.random() * math.pi * 2
		local distance = math.random() * TARGET_CONFIG.SpawnRadius
		
		local position = Vector3.new(
			math.cos(angle) * distance,
			TARGET_CONFIG.SpawnHeight + TARGET_CONFIG.Size.Y / 2,
			math.sin(angle) * distance
		)
		
		local target = createTarget(position)
		target.Parent = folder
	end
	
	-- Print tagged targets
	local taggedTargets = CollectionService:GetTagged(PHOTO_TARGET_TAG)
	print(string.format("[PlantService] Created %d photo targets with '%s' tag:", #taggedTargets, PHOTO_TARGET_TAG))
	for _, target in ipairs(taggedTargets) do
		print("  - " .. target.Name)
	end
	
	print("[PlantService] Started!")
end

-- === PUBLIC METHODS ===

function PlantService:CreateTarget(position)
	local folder = getTargetsFolder()
	local target = createTarget(position)
	target.Parent = folder
	return target
end

function PlantService:ClearTargets()
	clearTargets()
end

function PlantService:GetAllPhotoTargets()
	return CollectionService:GetTagged(PHOTO_TARGET_TAG)
end

function PlantService:RegenerateTargets(count)
	clearTargets()
	local folder = getTargetsFolder()
	
	for i = 1, (count or TARGET_CONFIG.SpawnCount) do
		local angle = math.random() * math.pi * 2
		local distance = math.random() * TARGET_CONFIG.SpawnRadius
		
		local position = Vector3.new(
			math.cos(angle) * distance,
			TARGET_CONFIG.SpawnHeight + TARGET_CONFIG.Size.Y / 2,
			math.sin(angle) * distance
		)
		
		local target = createTarget(position)
		target.Parent = folder
	end
end

return PlantService
