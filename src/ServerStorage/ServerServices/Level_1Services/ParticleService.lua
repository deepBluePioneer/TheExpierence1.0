local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local ParticleService = Knit.CreateService {
	Name = "ParticleService",
	Client = {},
	_emitterGroups = {},
}

local PARTICLE_GROUP_TAG = "particleGroup"

-- === CONFIG ===
local PARTICLE_CONFIG = {
	-- Spawning
	GroupCount = 40,             -- Number of particle groups
	EmittersPerGroup = 3,        -- Emitters per group for variety
	HeightMin = 1,               -- Minimum height above ground (close to surface)
	HeightMax = 8,               -- Maximum height above ground (low to ground)
	EdgePadding = 5,             -- Keep away from baseplate edges
	
	-- Particle types and their properties
	ParticleTypes = {
		-- Floating pollen/dust
		Pollen = {
			Texture = "rbxassetid://10891594349",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 200)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 245, 180)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 150)),
			}),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.5, 0.5),
				NumberSequenceKeypoint.new(1, 0.2),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.6),
				NumberSequenceKeypoint.new(0.8, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(4, 8),
			Rate = 15,
			Speed = NumberRange.new(0.2, 0.8),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 2,
			VelocityInheritance = 0,
			Acceleration = Vector3.new(0, 0.1, 0),  -- Slight upward drift
			RotSpeed = NumberRange.new(-30, 30),
			LightEmission = 0.3,
			LightInfluence = 0.8,
		},
		
		-- Small flying bugs/gnats
		Bugs = {
			Texture = "rbxassetid://10891594349",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 50)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30)),
			}),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(0.5, 0.5),
				NumberSequenceKeypoint.new(1, 0.3),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.15, 0.3),
				NumberSequenceKeypoint.new(0.85, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(2, 5),
			Rate = 12,
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(360, 360),
			Drag = 5,  -- More erratic movement
			VelocityInheritance = 0,
			Acceleration = Vector3.new(0, 0, 0),
			RotSpeed = NumberRange.new(-180, 180),
			LightEmission = 0,
			LightInfluence = 1,
		},
		
		-- Floating dust motes
		Dust = {
			Texture = "rbxassetid://10891594349",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 195, 180)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 175, 160)),
			}),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1),
				NumberSequenceKeypoint.new(0.5, 0.25),
				NumberSequenceKeypoint.new(1, 0.1),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.7),
				NumberSequenceKeypoint.new(0.7, 0.7),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(6, 12),
			Rate = 20,
			Speed = NumberRange.new(0.1, 0.4),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 1,
			VelocityInheritance = 0,
			Acceleration = Vector3.new(0, -0.05, 0),  -- Very slow fall
			RotSpeed = NumberRange.new(-15, 15),
			LightEmission = 0.1,
			LightInfluence = 0.9,
		},
		
		-- Fireflies (for night)
		Fireflies = {
			Texture = "rbxassetid://10891594349",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 255, 100)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 255, 150)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 200, 80)),
			}),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.3, 0.6),
				NumberSequenceKeypoint.new(0.7, 0.6),
				NumberSequenceKeypoint.new(1, 0.2),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.2),
				NumberSequenceKeypoint.new(0.5, 0.8),  -- Blink effect
				NumberSequenceKeypoint.new(0.7, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(3, 6),
			Rate = 8,
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(360, 360),
			Drag = 3,
			VelocityInheritance = 0,
			Acceleration = Vector3.new(0, 0.2, 0),
			RotSpeed = NumberRange.new(-45, 45),
			LightEmission = 1,
			LightInfluence = 0,
		},
		
		-- Spores/Seeds
		Spores = {
			Texture = "rbxassetid://10891594349",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 240, 230)),
			}),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(0.5, 0.8),
				NumberSequenceKeypoint.new(1, 0.4),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.5),
				NumberSequenceKeypoint.new(0.8, 0.5),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(8, 15),
			Rate = 6,
			Speed = NumberRange.new(0.3, 0.8),
			SpreadAngle = Vector2.new(90, 90),
			Drag = 0.5,
			VelocityInheritance = 0,
			Acceleration = Vector3.new(0, -0.1, 0),  -- Slow descent
			RotSpeed = NumberRange.new(-60, 60),
			LightEmission = 0.2,
			LightInfluence = 0.8,
		},
	},
}

local PARTICLE_FOLDER_NAME = "AmbientParticles"

-- === HELPERS ===

local function getParticleFolder()
	local folder = Workspace:FindFirstChild(PARTICLE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PARTICLE_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function clearParticles()
	local folder = Workspace:FindFirstChild(PARTICLE_FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

local function getBaseplateInfo()
	-- First try to get info from WorldInitService (preferred)
	local WorldInitService = nil
	pcall(function()
		WorldInitService = Knit.GetService("WorldInitService")
	end)
	
	if WorldInitService and WorldInitService:IsInitComplete() then
		local info = WorldInitService:GetBaseplateInfo()
		if info then
			return {
				position = info.position,
				size = info.size,
				topY = info.topY,
			}
		end
	end
	
	-- Fallback: Try GridService for grid dimensions
	local GridService = nil
	pcall(function()
		GridService = Knit.GetService("GridService")
	end)
	
	if GridService then
		local gridData = GridService:GetGridData()
		if gridData and gridData.cellSize > 0 then
			local totalWidth = gridData.width * gridData.cellSize
			local totalDepth = gridData.depth * gridData.cellSize
			return {
				position = Vector3.new(gridData.centerX, gridData.topY, gridData.centerZ),
				size = Vector3.new(totalWidth, 1, totalDepth),
				topY = gridData.topY,
			}
		end
	end
	
	-- Legacy fallback: look for physical Baseplate
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		return {
			position = baseplate.Position,
			size = baseplate.Size,
			topY = baseplate.Position.Y + (baseplate.Size.Y / 2),
		}
	end
	
	-- Default fallback
	return {
		position = Vector3.new(0, 0, 0),
		size = Vector3.new(384, 1, 384),
		topY = 0,
	}
end

local function createParticleEmitter(particleType, parentPart)
	local config = PARTICLE_CONFIG.ParticleTypes[particleType]
	if not config then return nil end
	
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = particleType
	emitter.Texture = config.Texture
	emitter.Color = config.Color
	emitter.Size = config.Size
	emitter.Transparency = config.Transparency
	emitter.Lifetime = config.Lifetime
	emitter.Rate = config.Rate
	emitter.Speed = config.Speed
	emitter.SpreadAngle = config.SpreadAngle
	emitter.Drag = config.Drag
	emitter.VelocityInheritance = config.VelocityInheritance
	emitter.Acceleration = config.Acceleration
	emitter.RotSpeed = config.RotSpeed
	emitter.LightEmission = config.LightEmission
	emitter.LightInfluence = config.LightInfluence
	
	-- Emit from entire volume of the part
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	
	emitter.Parent = parentPart
	
	return emitter
end

local function createParticleGroup(position, folder)
	-- Create invisible anchor part (LARGE for wide emission area)
	local anchor = Instance.new("Part")
	anchor.Name = "ParticleAnchor"
	anchor.Size = Vector3.new(50, 10, 50)  -- Wide but low emission volume (close to ground)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = folder
	
	-- Tag for rain collision exclusion
	CollectionService:AddTag(anchor, PARTICLE_GROUP_TAG)
	
	-- Randomly select particle types for this group
	local typeNames = {}
	for typeName, _ in pairs(PARTICLE_CONFIG.ParticleTypes) do
		table.insert(typeNames, typeName)
	end
	
	-- Create 1-3 different emitter types per group
	local emitterCount = math.random(1, PARTICLE_CONFIG.EmittersPerGroup)
	local usedTypes = {}
	
	for _ = 1, emitterCount do
		-- Pick a random type we haven't used yet
		local availableTypes = {}
		for _, typeName in ipairs(typeNames) do
			if not usedTypes[typeName] then
				table.insert(availableTypes, typeName)
			end
		end
		
		if #availableTypes > 0 then
			local selectedType = availableTypes[math.random(1, #availableTypes)]
			usedTypes[selectedType] = true
			createParticleEmitter(selectedType, anchor)  -- Parent directly to the part
		end
	end
	
	return anchor
end

local function generateParticleGroups(self)
	local baseplateInfo = getBaseplateInfo()
	if not baseplateInfo then
		warn("[ParticleService] No Baseplate found!")
		return
	end
	
	-- Get LoadingService for progress updates
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	local function reportProgress(current, total, message)
		if LoadingService then
			LoadingService:ReportProgress("ParticleService", current, total, message or "Creating particles")
		end
	end
	
	reportProgress(0, 100, "Preparing ambient effects")
	
	clearParticles()
	local folder = getParticleFolder()
	
	local halfX = (baseplateInfo.size.X / 2) - PARTICLE_CONFIG.EdgePadding
	local halfZ = (baseplateInfo.size.Z / 2) - PARTICLE_CONFIG.EdgePadding
	
	reportProgress(10, 100, "Spawning particle groups")
	
	for i = 1, PARTICLE_CONFIG.GroupCount do
		-- Random position within baseplate bounds
		local x = baseplateInfo.position.X + math.random(-halfX, halfX)
		local z = baseplateInfo.position.Z + math.random(-halfZ, halfZ)
		local y = baseplateInfo.topY + math.random(PARTICLE_CONFIG.HeightMin, PARTICLE_CONFIG.HeightMax)
		
		local position = Vector3.new(x, y, z)
		local group = createParticleGroup(position, folder)
		table.insert(self._emitterGroups, group)
		
		-- Report progress
		if i % 5 == 0 then
			local progress = 10 + (i / PARTICLE_CONFIG.GroupCount) * 85
			reportProgress(math.floor(progress), 100, string.format("Creating particle groups (%d/%d)", i, PARTICLE_CONFIG.GroupCount))
			task.wait()
		end
	end
	
	print(string.format("[ParticleService] Created %d particle groups", #self._emitterGroups))
	reportProgress(100, 100, "Ambient effects ready")
	
	-- Mark step complete
	if LoadingService then
		LoadingService:MarkStepComplete("ParticleService")
	end
end

-- === KNIT LIFECYCLE ===

function ParticleService:KnitInit()
	print("[ParticleService] Initializing...")
end

function ParticleService:KnitStart()
	generateParticleGroups(self)
end

-- === PUBLIC METHODS ===

function ParticleService:RegenerateParticles()
	self._emitterGroups = {}
	generateParticleGroups(self)
end

function ParticleService:ClearParticles()
	self._emitterGroups = {}
	clearParticles()
	print("[ParticleService] All particles cleared")
end

function ParticleService:SetGroupCount(count)
	PARTICLE_CONFIG.GroupCount = math.clamp(count, 1, 100)
	print("[ParticleService] Group count set to:", count)
end

function ParticleService:EnableType(typeName, enabled)
	for _, group in ipairs(self._emitterGroups) do
		local emitter = group:FindFirstChild(typeName)
		if emitter and emitter:IsA("ParticleEmitter") then
			emitter.Enabled = enabled
		end
	end
	print(string.format("[ParticleService] %s %s", typeName, enabled and "enabled" or "disabled"))
end

function ParticleService:SetAllEnabled(enabled)
	for _, group in ipairs(self._emitterGroups) do
		for _, emitter in ipairs(group:GetChildren()) do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = enabled
			end
		end
	end
	print("[ParticleService] All particles", enabled and "enabled" or "disabled")
end

function ParticleService:GetEmitterCount()
	local count = 0
	for _, group in ipairs(self._emitterGroups) do
		for _, child in ipairs(group:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				count = count + 1
			end
		end
	end
	return count
end

return ParticleService

