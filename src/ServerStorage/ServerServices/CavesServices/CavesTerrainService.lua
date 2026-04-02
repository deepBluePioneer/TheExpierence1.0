local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)

local Terrain = Workspace.Terrain

local VOLUME_SIZE = Vector3.new(200, 100, 200)
local VOLUME_CENTER = Vector3.new(0, -40, 0)

local WORM_COUNT = 3
local WORM_MIN_STEPS = 80
local WORM_MAX_STEPS = 150
local WORM_STEP_SIZE = 6
local WORM_MIN_RADIUS = 5
local WORM_MAX_RADIUS = 9
local WORM_INERTIA = 0.85
local WORM_BRANCH_CHANCE = 0.08
local WORM_BRANCH_STEPS = 30

local LIGHT_SPACING = 6

local LIGHT_TYPES = {
	{
		name = "Mushroom",
		weight = 4,
		color = Color3.fromRGB(30, 120, 90),
		brightness = 0.6,
		range = 14,
		size = Vector3.new(0.8, 1.2, 0.8),
		shape = "Ball",
		transparency = 0.2,
		yOffset = -2,
	},
	{
		name = "Crystal",
		weight = 3,
		color = Color3.fromRGB(90, 50, 160),
		brightness = 0.8,
		range = 16,
		size = Vector3.new(0.5, 2, 0.5),
		shape = "Block",
		transparency = 0.15,
		yOffset = 0,
	},
	{
		name = "Torch",
		weight = 3,
		color = Color3.fromRGB(180, 110, 40),
		brightness = 0.7,
		range = 15,
		size = Vector3.new(0.4, 0.6, 0.4),
		shape = "Ball",
		transparency = 0.3,
		yOffset = 2,
	},
	{
		name = "FungalCluster",
		weight = 2,
		color = Color3.fromRGB(40, 150, 60),
		brightness = 0.4,
		range = 10,
		size = Vector3.new(1.2, 0.6, 1.2),
		shape = "Ball",
		transparency = 0.1,
		yOffset = -2,
	},
	{
		name = "LavaVent",
		weight = 1,
		color = Color3.fromRGB(200, 50, 10),
		brightness = 1,
		range = 18,
		size = Vector3.new(1, 0.4, 1),
		shape = "Block",
		transparency = 0.05,
		yOffset = -3,
	},
}

local MATERIAL_PATCH_COUNT = 25
local MATERIAL_PATCH_RADIUS = 16

local MATERIAL_REPLACEMENTS = {
	{ material = Enum.Material.Mud, weight = 3 },
	{ material = Enum.Material.Slate, weight = 3 },
	{ material = Enum.Material.Sand, weight = 2 },
	{ material = Enum.Material.Snow, weight = 1 },
	{ material = Enum.Material.Sandstone, weight = 2 },
}

local function weightedPick(entries, key)
	local total = 0
	for _, entry in ipairs(entries) do
		total += entry.weight
	end
	local roll = math.random() * total
	local acc = 0
	for _, entry in ipairs(entries) do
		acc += entry.weight
		if roll <= acc then
			return key and entry[key] or entry
		end
	end
	return key and entries[1][key] or entries[1]
end

local function randomUnitVector()
	local theta = math.random() * math.pi * 2
	local phi = math.acos(2 * math.random() - 1)
	return Vector3.new(
		math.sin(phi) * math.cos(theta),
		math.sin(phi) * math.sin(theta) * 0.4,
		math.sin(phi) * math.sin(theta) -- intentionally not cos; weighted horizontal
	).Unit
end

local function clampToVolume(pos)
	local halfX = VOLUME_SIZE.X / 2 - 15
	local halfZ = VOLUME_SIZE.Z / 2 - 15
	local minY = VOLUME_CENTER.Y - VOLUME_SIZE.Y / 2 + 15
	local maxY = VOLUME_CENTER.Y + VOLUME_SIZE.Y / 2 - 15

	return Vector3.new(
		math.clamp(pos.X, -halfX, halfX),
		math.clamp(pos.Y, minY, maxY),
		math.clamp(pos.Z, -halfZ, halfZ)
	)
end

local CavesTerrainService = Knit.CreateService({
	Name = "CavesTerrainService",
	Client = {},

	_trove = nil,
	_spawnPosition = nil,
	_lightFolder = nil,
	_webFolder = nil,
	_treasureFolder = nil,
	_tunnelPoints = {},
	_tunnelSegments = {},
	_branchForks = {},

	CavesGenerated = Signal.new(),
})

function CavesTerrainService:KnitInit()
	self._trove = Trove.new()
end

function CavesTerrainService:KnitStart()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	self:_setupCaveLighting()
	self:GenerateCaves()
	print("[CavesTerrainService] Started")
end

function CavesTerrainService:_setupCaveLighting()
	Lighting.Brightness = 2
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 40
	Lighting.Ambient = Color3.fromRGB(140, 140, 140)
	Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1

	Lighting.FogColor = Color3.fromRGB(200, 210, 220)
	Lighting.FogStart = 500
	Lighting.FogEnd = 5000

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("BloomEffect")
			or child:IsA("ColorCorrectionEffect") or child:IsA("SunRaysEffect") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.25
	atmosphere.Color = Color3.fromRGB(199, 210, 225)
	atmosphere.Decay = Color3.fromRGB(92, 120, 156)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.5
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "CaveBloom"
	bloom.Intensity = 0.3
	bloom.Size = 20
	bloom.Threshold = 0.9
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "CaveCC"
	cc.Brightness = 0.05
	cc.Contrast = 0.1
	cc.Saturation = 0.1
	cc.TintColor = Color3.fromRGB(255, 250, 245)
	cc.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "CaveSunRays"
	sunRays.Intensity = 0.15
	sunRays.Spread = 0.8
	sunRays.Parent = Lighting

	print("[CavesTerrainService] Daytime cave lighting applied")
end

function CavesTerrainService:_fillSolidVolume()
	Terrain:Clear()

	local cf = CFrame.new(VOLUME_CENTER)
	Terrain:FillBlock(cf, VOLUME_SIZE, Enum.Material.Rock)

	print("[CavesTerrainService] Filled solid rock volume: " .. tostring(VOLUME_SIZE))
end

local HILL_CENTER = Vector3.new(0, -5, 0)

function CavesTerrainService:_buildHillside()
	Terrain:FillBall(HILL_CENTER, 50, Enum.Material.Grass)

	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2
		local dist = 20 + math.random() * 25
		local x = math.cos(angle) * dist
		local z = math.sin(angle) * dist
		local y = -8 + math.random() * 10
		local radius = 25 + math.random() * 20

		Terrain:FillBall(HILL_CENTER + Vector3.new(x, y, z), radius, Enum.Material.Grass)
	end

	for i = 1, 5 do
		local angle = (i / 5) * math.pi * 2
		local dist = 35 + math.random() * 15
		local x = math.cos(angle) * dist
		local z = math.sin(angle) * dist
		local radius = 15 + math.random() * 10

		Terrain:FillBall(Vector3.new(x, -12, z), radius, Enum.Material.Rock)
	end

	print("[CavesTerrainService] Built hillside terrain")
end

local ENTRANCE_MOUTH = Vector3.new(0, 5, 40)
local ENTRANCE_INTERIOR = Vector3.new(0, -20, 0)
local ENTRANCE_STEPS = 12
local ENTRANCE_RADIUS = 7

function CavesTerrainService:_carveEntrance()
	for i = 0, ENTRANCE_STEPS do
		local alpha = i / ENTRANCE_STEPS
		local pos = ENTRANCE_MOUTH:Lerp(ENTRANCE_INTERIOR, alpha)
		local radius = ENTRANCE_RADIUS + math.sin(alpha * math.pi) * 2
		Terrain:FillBall(pos, radius, Enum.Material.Air)
	end

	self._spawnPosition = ENTRANCE_MOUTH + Vector3.new(0, -2, 5)

	print("[CavesTerrainService] Carved cave entrance")
end

function CavesTerrainService:_runWorm(startPos, steps, depth)
	depth = depth or 0
	local pos = startPos
	local dir = randomUnitVector()
	local points = {}

	for i = 1, steps do
		local newDir = randomUnitVector()
		dir = (dir * WORM_INERTIA + newDir * (1 - WORM_INERTIA)).Unit

		pos = clampToVolume(pos + dir * WORM_STEP_SIZE)

		local radius = WORM_MIN_RADIUS + math.random() * (WORM_MAX_RADIUS - WORM_MIN_RADIUS)
		radius = radius + math.sin(i * 0.08) * 1.5

		Terrain:FillBall(pos, radius, Enum.Material.Air)

		if i % LIGHT_SPACING == 0 then
			table.insert(points, pos)
			table.insert(self._tunnelSegments, { pos = pos, dir = dir, radius = radius })
		end

		if math.random() < WORM_BRANCH_CHANCE and steps > 30 then
			table.insert(self._branchForks, { position = pos, direction = dir, radius = radius })

			local branchPoints = self:_runWorm(pos, math.random(20, WORM_BRANCH_STEPS), depth + 1)
			for _, bp in ipairs(branchPoints) do
				table.insert(points, bp)
			end
		end

		if i % 30 == 0 then
			task.wait()
		end
	end

	return points
end

function CavesTerrainService:_findCaveFloor(pos)
	local rayOrigin = pos
	local rayDir = Vector3.new(0, -200, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {}

	local result = Workspace:Raycast(rayOrigin, rayDir, rayParams)
	if result then
		return result.Position + Vector3.new(0, 3, 0)
	end

	return pos
end

function CavesTerrainService:_carveWormTunnels()
	self._tunnelPoints = {}
	self._tunnelSegments = {}
	self._branchForks = {}

	local startY = VOLUME_CENTER.Y
	local spread = VOLUME_SIZE.X * 0.2

	for i = 1, WORM_COUNT do
		local startPos = Vector3.new(
			(math.random() - 0.5) * spread * 2,
			startY + (math.random() - 0.5) * 20,
			(math.random() - 0.5) * spread * 2
		)

		if i == 1 then
			startPos = ENTRANCE_INTERIOR
		end

		local steps = math.random(WORM_MIN_STEPS, WORM_MAX_STEPS)
		local points = self:_runWorm(startPos, steps)

		for _, p in ipairs(points) do
			table.insert(self._tunnelPoints, p)
		end

		print("[CavesTerrainService] Worm " .. i .. "/" .. WORM_COUNT .. " carved (" .. steps .. " steps)")
		task.wait()
	end
end

function CavesTerrainService:_scatterMaterials()
	for _ = 1, MATERIAL_PATCH_COUNT do
		local center = Vector3.new(
			(math.random() - 0.5) * VOLUME_SIZE.X * 0.8,
			VOLUME_CENTER.Y + (math.random() - 0.5) * VOLUME_SIZE.Y * 0.8,
			(math.random() - 0.5) * VOLUME_SIZE.Z * 0.8
		)

		local halfR = MATERIAL_PATCH_RADIUS / 2
		local region = Region3.new(
			center - Vector3.new(halfR, halfR, halfR),
			center + Vector3.new(halfR, halfR, halfR)
		):ExpandToGrid(4)

		local mat = weightedPick(MATERIAL_REPLACEMENTS, "material")
		Terrain:ReplaceMaterial(region, 4, Enum.Material.Rock, mat)
	end

	print("[CavesTerrainService] Scattered " .. MATERIAL_PATCH_COUNT .. " material patches")
end

function CavesTerrainService:_placeLights()
	if self._lightFolder then
		self._lightFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "CaveLights"
	folder.Parent = Workspace

	self._lightFolder = folder
	self._trove:Add(folder)

	local placed = 0
	local dustCount = 0
	for _, pos in ipairs(self._tunnelPoints) do
		local info = weightedPick(LIGHT_TYPES)

		local bulb = Instance.new("Part")
		bulb.Name = info.name .. "_" .. placed

		if info.shape == "Ball" then
			bulb.Shape = Enum.PartType.Ball
		end

		bulb.Size = info.size
		bulb.Anchored = true
		bulb.CanCollide = false
		bulb.Material = Enum.Material.Neon
		bulb.Color = info.color
		bulb.Transparency = 1
		bulb.CastShadow = false

		local yOff = info.yOffset + (math.random() - 0.5) * 1
		local xJitter = (math.random() - 0.5) * 2
		local zJitter = (math.random() - 0.5) * 2
		bulb.CFrame = CFrame.new(pos + Vector3.new(xJitter, yOff, zJitter))
			* CFrame.Angles(
				(math.random() - 0.5) * 0.4,
				math.random() * math.pi * 2,
				(math.random() - 0.5) * 0.4
			)

		bulb.Parent = folder

		local pointLight = Instance.new("PointLight")
		pointLight.Color = info.color
		pointLight.Brightness = info.brightness * (0.8 + math.random() * 0.4)
		pointLight.Range = info.range * (0.85 + math.random() * 0.3)
		pointLight.Shadows = true
		pointLight.Parent = bulb

		do
			local dust = Instance.new("ParticleEmitter")
			dust.Name = "CaveDust"
			dust.Texture = "rbxassetid://6490035152"
			dust.Shape = Enum.ParticleEmitterShape.Sphere
			dust.ShapePartial = 1
			dust.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
			dust.Color = ColorSequence.new(
				Color3.fromRGB(180, 170, 155),
				Color3.fromRGB(120, 115, 105)
			)
			dust.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.3, 0.15 + math.random() * 0.1),
				NumberSequenceKeypoint.new(1, 0),
			})
			dust.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.55),
				NumberSequenceKeypoint.new(0.8, 0.65),
				NumberSequenceKeypoint.new(1, 1),
			})
			dust.Lifetime = NumberRange.new(6, 14)
			dust.Rate = 6
			dust.Speed = NumberRange.new(0.5, 2.5)
			dust.SpreadAngle = Vector2.new(360, 360)
			dust.EmissionDirection = Enum.NormalId.Top
			dust.RotSpeed = NumberRange.new(-10, 10)
			dust.Rotation = NumberRange.new(0, 360)
			dust.Drag = 0.5
			dust.LightEmission = 0
			dust.LightInfluence = 1
			dust.Parent = bulb
			dustCount += 1
		end

		placed += 1

		if placed % 50 == 0 then
			task.wait()
		end
	end

	print("[CavesTerrainService] Placed " .. placed .. " cave lights, " .. dustCount .. " dust emitters")
end

local WEB_CHANCE = 0.6
local WEB_SPOKE_COUNT = 8
local WEB_RING_COUNT = 7
local WEB_COLOR = Color3.fromRGB(220, 215, 210)
local WEB_THICKNESS = 0.15

local WEB_MAX_REACH = 20
local WEB_FALLBACK_RADIUS = 15

function CavesTerrainService:_buildWeb(center, faceDir, _tunnelRadius)
	local folder = self._webFolder

	local upVec = Vector3.new(0, 1, 0)
	if math.abs(faceDir:Dot(upVec)) > 0.9 then
		upVec = Vector3.new(1, 0, 0)
	end
	local right = faceDir:Cross(upVec).Unit
	local up = right:Cross(faceDir).Unit

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { folder }

	local spokeDirs = {}
	local spokeLengths = {}
	local spokeEndPoints = {}

	for s = 1, WEB_SPOKE_COUNT do
		local angle = (s / WEB_SPOKE_COUNT) * math.pi * 2
		local localDir = right * math.cos(angle) + up * math.sin(angle)

		local result = Workspace:Raycast(center, localDir * WEB_MAX_REACH, rayParams)
		local endPos = result and result.Position or (center + localDir * WEB_FALLBACK_RADIUS)
		local length = (endPos - center).Magnitude

		spokeDirs[s] = localDir
		spokeLengths[s] = length
		spokeEndPoints[s] = endPos
	end

	local hub = Instance.new("Part")
	hub.Name = "WebHub"
	hub.Shape = Enum.PartType.Ball
	hub.Size = Vector3.new(0.3, 0.3, 0.3)
	hub.CFrame = CFrame.new(center)
	hub.Anchored = true
	hub.CanCollide = false
	hub.Material = Enum.Material.SmoothPlastic
	hub.Color = WEB_COLOR
	hub.Transparency = 0.3
	hub.Parent = folder

	for s = 1, WEB_SPOKE_COUNT do
		local endPos = spokeEndPoints[s]
		local midPoint = (center + endPos) / 2
		local length = spokeLengths[s]

		local spoke = Instance.new("Part")
		spoke.Name = "WebSpoke"
		spoke.Size = Vector3.new(WEB_THICKNESS, WEB_THICKNESS, length)
		spoke.CFrame = CFrame.lookAt(midPoint, endPos)
		spoke.Anchored = true
		spoke.CanCollide = true
		spoke.Material = Enum.Material.SmoothPlastic
		spoke.Color = WEB_COLOR
		spoke.Transparency = 0.4
		spoke.Parent = folder
	end

	for r = 1, WEB_RING_COUNT do
		local ringFrac = r / (WEB_RING_COUNT + 1)

		for s = 1, WEB_SPOKE_COUNT do
			local nextS = (s % WEB_SPOKE_COUNT) + 1

			local p1 = center + spokeDirs[s] * (spokeLengths[s] * ringFrac)
			local p2 = center + spokeDirs[nextS] * (spokeLengths[nextS] * ringFrac)

			local mid = (p1 + p2) / 2
			local segLen = (p2 - p1).Magnitude
			if segLen < 0.01 then continue end

			local seg = Instance.new("Part")
			seg.Name = "WebRing"
			seg.Size = Vector3.new(WEB_THICKNESS, WEB_THICKNESS, segLen)
			seg.CFrame = CFrame.lookAt(mid, p2)
			seg.Anchored = true
			seg.CanCollide = true
			seg.Material = Enum.Material.SmoothPlastic
			seg.Color = WEB_COLOR
			seg.Transparency = 0.5
			seg.Parent = folder
		end
	end
end

function CavesTerrainService:_placeSpiderWebs()
	if self._webFolder then
		self._webFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "CaveWebs"
	folder.Parent = Workspace
	self._webFolder = folder
	self._trove:Add(folder)

	local placed = 0
	for _, fork in ipairs(self._branchForks) do
		if math.random() < WEB_CHANCE then
			self:_buildWeb(fork.position, fork.direction, fork.radius)
			placed += 1
		end
	end

	print("[CavesTerrainService] Placed " .. placed .. " spider webs at branch forks")
end

local GOLD_SPHERE_SIZE = 3
local GOLD_COLOR = Color3.fromRGB(255, 200, 50)
local TREASURE_TUNNEL_LENGTH = 40
local TREASURE_TUNNEL_STEPS = 8
local TREASURE_TUNNEL_RADIUS = 7
local TREASURE_ROOM_RADIUS = 12

function CavesTerrainService:_placeTreasureRoom()
	if self._treasureFolder then
		self._treasureFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "CaveTreasure"
	folder.Parent = Workspace
	self._treasureFolder = folder
	self._trove:Add(folder)

	local segs = self._tunnelSegments
	if #segs < 6 then
		print("[CavesTerrainService] Not enough segments for treasure room")
		return
	end

	local idx = math.random(math.floor(#segs * 0.3), math.floor(#segs * 0.7))
	local seg = segs[idx]

	local branchOrigin = seg.pos
	local tunnelDir = seg.dir.Unit

	local upVec = Vector3.new(0, 1, 0)
	if math.abs(tunnelDir:Dot(upVec)) > 0.9 then
		upVec = Vector3.new(1, 0, 0)
	end
	local sideDir = tunnelDir:Cross(upVec).Unit
	if math.random() > 0.5 then
		sideDir = -sideDir
	end

	local branchDir = (sideDir + Vector3.new(0, -0.15, 0)).Unit

	for i = 0, TREASURE_TUNNEL_STEPS do
		local alpha = i / TREASURE_TUNNEL_STEPS
		local pos = branchOrigin + branchDir * (alpha * TREASURE_TUNNEL_LENGTH)
		Terrain:FillBall(pos, TREASURE_TUNNEL_RADIUS, Enum.Material.Air)
	end

	local roomCenter = branchOrigin + branchDir * TREASURE_TUNNEL_LENGTH
	Terrain:FillBall(roomCenter, TREASURE_ROOM_RADIUS, Enum.Material.Air)

	local webPos = branchOrigin + branchDir * 4
	self:_buildWeb(webPos, branchDir, TREASURE_TUNNEL_RADIUS)

	local sphere = Instance.new("Part")
	sphere.Name = "GoldSphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(GOLD_SPHERE_SIZE, GOLD_SPHERE_SIZE, GOLD_SPHERE_SIZE)
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.Material = Enum.Material.Foil
	sphere.Color = GOLD_COLOR
	sphere.CastShadow = true
	sphere.Parent = folder

	local floorPos = self:_findCaveFloor(roomCenter + Vector3.new(0, 5, 0))
	sphere.CFrame = CFrame.new(floorPos + Vector3.new(0, GOLD_SPHERE_SIZE / 2, 0))

	local glow = Instance.new("PointLight")
	glow.Color = GOLD_COLOR
	glow.Brightness = 2.5
	glow.Range = 25
	glow.Shadows = false
	glow.Parent = sphere

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "GoldSparkle"
	sparkle.Texture = "rbxassetid://6490035152"
	sparkle.Color = ColorSequence.new(GOLD_COLOR, Color3.fromRGB(255, 255, 200))
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkle.Lifetime = NumberRange.new(1, 2.5)
	sparkle.Rate = 8
	sparkle.Speed = NumberRange.new(0.5, 2)
	sparkle.SpreadAngle = Vector2.new(360, 360)
	sparkle.Shape = Enum.ParticleEmitterShape.Sphere
	sparkle.LightEmission = 0.8
	sparkle.LightInfluence = 0.3
	sparkle.RotSpeed = NumberRange.new(-30, 30)
	sparkle.Rotation = NumberRange.new(0, 360)
	sparkle.Parent = sphere

	print("[CavesTerrainService] Placed treasure room at " .. tostring(roomCenter))
end

function CavesTerrainService:_repositionSpawnLocation()
	local pos = self:GetSpawnPosition()

	pos = self:_findCaveFloor(pos + Vector3.new(0, 10, 0))
	self._spawnPosition = pos

	local spawnLoc = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if not spawnLoc then return end

	spawnLoc.Size = Vector3.new(8, 1, 8)
	spawnLoc.CFrame = CFrame.new(pos)
	spawnLoc.Anchored = true
	spawnLoc.Transparency = 1
	spawnLoc.CanCollide = false
	print("[CavesTerrainService] Moved SpawnLocation to " .. tostring(pos))
end

function CavesTerrainService:GenerateCaves()
	self:_fillSolidVolume()
	self:_buildHillside()
	self:_carveEntrance()
	self:_carveWormTunnels()
	self:_scatterMaterials()
	self:_placeLights()
	self:_placeSpiderWebs()
	self:_placeTreasureRoom()
	self:_repositionSpawnLocation()
	self.CavesGenerated:Fire()
	print("[CavesTerrainService] Cave generation complete")
end

function CavesTerrainService:DestroyCaves()
	Terrain:Clear()
	if self._lightFolder then
		self._lightFolder:Destroy()
		self._lightFolder = nil
	end
	if self._webFolder then
		self._webFolder:Destroy()
		self._webFolder = nil
	end
	if self._treasureFolder then
		self._treasureFolder:Destroy()
		self._treasureFolder = nil
	end
	self._tunnelPoints = {}
	self._tunnelSegments = {}
	self._branchForks = {}
	self._spawnPosition = nil
end

function CavesTerrainService:GetSpawnPosition()
	return self._spawnPosition or ENTRANCE_MOUTH
end

function CavesTerrainService.Client:GetSpawnPosition(_player)
	return self.Server:GetSpawnPosition()
end

function CavesTerrainService.Client:GenerateCaves(_player)
	self.Server:GenerateCaves()
end

function CavesTerrainService.Client:DestroyCaves(_player)
	self.Server:DestroyCaves()
end

return CavesTerrainService
