local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local TERRAIN_WIDTH = 512
local TERRAIN_DEPTH = 512
local RESOLUTION = 4
local BASE_Y = 0
local TERRAIN_THICKNESS = 40
local TRENCH_COUNT = 4
local TRENCH_DEPTH = 12
local TRENCH_WIDTH = 32
local TRENCH_FLAT_RATIO = 0.5 -- inner 50% of width is flat floor, outer 50% is sloped wall
local SURFACE_NOISE_AMP = 2
local HILL_AMP = 12
local HILL_SCALE = 0.005
local CRATER_COUNT = 15
local CRATER_RADIUS_MIN = 8
local CRATER_RADIUS_MAX = 20
local CRATER_DEPTH = 4

local PILLAR_COUNT = 20
local PILLAR_WIDTH_MIN = 8
local PILLAR_WIDTH_MAX = 16
local PILLAR_HEIGHT_MIN = 40
local PILLAR_HEIGHT_MAX = 90
local PILLAR_DEPTH_MIN = 8
local PILLAR_DEPTH_MAX = 14
local PILLAR_TRENCH_CLEARANCE = 40

local HALF_W = TERRAIN_WIDTH / 2
local HALF_D = TERRAIN_DEPTH / 2

local ProvingGroundsTerrainService = Knit.CreateService({
	Name = "ProvingGroundsTerrainService",
	Client = {},
})

function ProvingGroundsTerrainService:KnitInit()
	self._seed = 0
	self._trenches = {}
	self._pillarFolder = nil
	self._bounds = {
		minX = -HALF_W,
		maxX = HALF_W,
		minZ = -HALF_D,
		maxZ = HALF_D,
		surfaceY = BASE_Y,
	}
end

function ProvingGroundsTerrainService:KnitStart()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	self:Generate()
end

function ProvingGroundsTerrainService:GetBounds()
	local b = self._bounds
	return b.minX, b.maxX, b.minZ, b.maxZ, b.surfaceY
end

function ProvingGroundsTerrainService:GetTrenchCount()
	return #self._trenches
end

function ProvingGroundsTerrainService:SampleTrenchWaypoints(trenchIndex, count, perpOffset)
	local trench = self._trenches[trenchIndex]
	if not trench then return {} end
	perpOffset = perpOffset or 0

	local primaryMin, primaryMax
	if trench.isXAxis then
		primaryMin = -HALF_W * 0.85
		primaryMax = HALF_W * 0.85
	else
		primaryMin = -HALF_D * 0.85
		primaryMax = HALF_D * 0.85
	end

	local centerPoints = {}
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local primary = primaryMin + t * (primaryMax - primaryMin)
		local lateral = self:_trenchLateralOffset(trench, primary)

		if trench.isXAxis then
			centerPoints[i + 1] = { x = primary, z = lateral }
		else
			centerPoints[i + 1] = { x = lateral, z = primary }
		end
	end

	if perpOffset == 0 then
		local waypoints = {}
		for i = 1, count do
			waypoints[i] = Vector3.new(centerPoints[i].x, 0, centerPoints[i].z)
		end
		return waypoints
	end

	local waypoints = {}
	for i = 1, count do
		local prev = centerPoints[math.max(1, i - 1)]
		local next = centerPoints[math.min(count, i + 1)]
		local tx = next.x - prev.x
		local tz = next.z - prev.z
		local tLen = math.sqrt(tx * tx + tz * tz)
		if tLen > 0.01 then
			tx = tx / tLen
			tz = tz / tLen
		end

		local nx = -tz * perpOffset
		local nz = tx * perpOffset

		waypoints[i] = Vector3.new(centerPoints[i].x + nx, 0, centerPoints[i].z + nz)
	end

	return waypoints
end

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function fbm2d(x, z, octaves, seed)
	local sum = 0
	local amp = 1
	local freq = 1
	local norm = 0
	for _ = 1, octaves do
		sum = sum + math.noise(x * freq + seed, z * freq + seed * 1.3) * amp
		norm = norm + amp
		amp = amp * 0.5
		freq = freq * 2
	end
	return sum / norm
end

function ProvingGroundsTerrainService:_generateTrenchPaths(rng)
	local trenches = {}
	local xCount = math.ceil(TRENCH_COUNT / 2)
	local zCount = math.floor(TRENCH_COUNT / 2)
	local xIdx = 0
	local zIdx = 0

	for i = 1, TRENCH_COUNT do
		local isXAxis = (i % 2 == 1)
		local perpBase

		if isXAxis then
			xIdx = xIdx + 1
			local span = TERRAIN_DEPTH * 0.5
			if xCount == 1 then
				perpBase = 0
			else
				perpBase = -span / 2 + (xIdx - 1) * span / (xCount - 1)
			end
		else
			zIdx = zIdx + 1
			local span = TERRAIN_WIDTH * 0.5
			if zCount == 1 then
				perpBase = 0
			else
				perpBase = -span / 2 + (zIdx - 1) * span / (zCount - 1)
			end
		end

		perpBase = perpBase + rng:NextNumber(-20, 20)

		table.insert(trenches, {
			isXAxis = isXAxis,
			perpBase = perpBase,
			a1 = rng:NextNumber(30, 80),
			a2 = rng:NextNumber(10, 30),
			f1 = rng:NextNumber(0.008, 0.02),
			f2 = rng:NextNumber(0.015, 0.04),
			noiseOffset = rng:NextNumber(-1000, 1000),
		})
	end

	return trenches
end

function ProvingGroundsTerrainService:_trenchLateralOffset(trench, primaryCoord)
	return trench.perpBase
		+ trench.a1 * math.sin(trench.f1 * primaryCoord)
		+ trench.a2 * math.sin(trench.f2 * primaryCoord)
		+ math.noise(primaryCoord * 0.01 + trench.noiseOffset) * 20
end

function ProvingGroundsTerrainService:_generateCraters(rng)
	local craters = {}
	for _ = 1, CRATER_COUNT do
		table.insert(craters, {
			x = rng:NextNumber(-HALF_W * 0.9, HALF_W * 0.9),
			z = rng:NextNumber(-HALF_D * 0.9, HALF_D * 0.9),
			radius = rng:NextNumber(CRATER_RADIUS_MIN, CRATER_RADIUS_MAX),
		})
	end
	return craters
end

function ProvingGroundsTerrainService:_isNearTrench(wx, wz)
	for _, trench in ipairs(self._trenches) do
		local dist
		if trench.isXAxis then
			dist = math.abs(wz - self:_trenchLateralOffset(trench, wx))
		else
			dist = math.abs(wx - self:_trenchLateralOffset(trench, wz))
		end
		if dist < PILLAR_TRENCH_CLEARANCE then
			return true
		end
	end
	return false
end

function ProvingGroundsTerrainService:_generatePillars(rng)
	if self._pillarFolder then
		self._pillarFolder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Pillars"
	folder.Parent = Workspace
	self._pillarFolder = folder

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { folder }

	local placed = 0
	local attempts = 0
	while placed < PILLAR_COUNT and attempts < PILLAR_COUNT * 10 do
		attempts = attempts + 1
		local px = rng:NextNumber(-HALF_W * 0.85, HALF_W * 0.85)
		local pz = rng:NextNumber(-HALF_D * 0.85, HALF_D * 0.85)

		if self:_isNearTrench(px, pz) then continue end

		local origin = Vector3.new(px, 200, pz)
		local hit = Workspace:Raycast(origin, Vector3.new(0, -400, 0), rayParams)
		local groundY = hit and hit.Position.Y or BASE_Y

		local w = rng:NextNumber(PILLAR_WIDTH_MIN, PILLAR_WIDTH_MAX)
		local h = rng:NextNumber(PILLAR_HEIGHT_MIN, PILLAR_HEIGHT_MAX)
		local d = rng:NextNumber(PILLAR_DEPTH_MIN, PILLAR_DEPTH_MAX)

		local part = Instance.new("Part")
		part.Size = Vector3.new(w, h, d)
		part.CFrame = CFrame.new(px, groundY + h / 2, pz) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		part.Material = Enum.Material.Slate
		part.Color = Color3.fromRGB(60, 55, 50)
		part.Anchored = true
		part.CanCollide = true
		part.CastShadow = true
		part.Parent = folder

		placed = placed + 1
	end

	print("[ProvingGroundsTerrainService] " .. placed .. " pillars placed")
end

function ProvingGroundsTerrainService:Generate()
	self._seed = os.clock() * 1000 + math.random(1, 100000)
	local rng = Random.new(self._seed)
	local terrain = Workspace.Terrain

	local floorY = BASE_Y - TERRAIN_THICKNESS
	local ceilY = BASE_Y + HILL_AMP + SURFACE_NOISE_AMP + 4

	local region = Region3.new(
		Vector3.new(-HALF_W, floorY, -HALF_D),
		Vector3.new(HALF_W, ceilY, HALF_D)
	):ExpandToGrid(RESOLUTION)

	terrain:FillRegion(region, RESOLUTION, Enum.Material.Air)

	local trenches = self:_generateTrenchPaths(rng)
	self._trenches = trenches
	local craters = self:_generateCraters(rng)
	local noiseSeed = rng:NextNumber(-1000, 1000)

	local materials, occupancies = terrain:ReadVoxels(region, RESOLUTION)
	local nx = #materials
	local ny = #materials[1]
	local nz = #materials[1][1]

	local regionMin = region.CFrame.Position - region.Size * 0.5
	local halfTrenchW = TRENCH_WIDTH / 2

	for ix = 1, nx do
		local wx = regionMin.X + (ix - 0.5) * RESOLUTION

		for iz = 1, nz do
			local wz = regionMin.Z + (iz - 0.5) * RESOLUTION

			local hills = fbm2d(wx * HILL_SCALE, wz * HILL_SCALE, 4, noiseSeed) * HILL_AMP
			local roughness = fbm2d(wx * 0.02, wz * 0.02, 2, noiseSeed + 50) * SURFACE_NOISE_AMP
			local surfaceY = BASE_Y + hills + roughness

			local flatRadius = halfTrenchW * TRENCH_FLAT_RATIO
			local wallZone = halfTrenchW - flatRadius

			for _, trench in ipairs(trenches) do
				local dist
				if trench.isXAxis then
					dist = math.abs(wz - self:_trenchLateralOffset(trench, wx))
				else
					dist = math.abs(wx - self:_trenchLateralOffset(trench, wz))
				end
				if dist < flatRadius then
					surfaceY = surfaceY - TRENCH_DEPTH
				elseif dist < halfTrenchW then
					local wallT = (dist - flatRadius) / wallZone
					surfaceY = surfaceY - TRENCH_DEPTH * smoothstep(1 - wallT)
				end
			end

			for _, crater in ipairs(craters) do
				local dx = wx - crater.x
				local dz = wz - crater.z
				local d = math.sqrt(dx * dx + dz * dz)
				if d < crater.radius then
					surfaceY = surfaceY - CRATER_DEPTH * (0.5 + 0.5 * math.cos(math.pi * d / crater.radius))
				end
			end

			for iy = 1, ny do
				local wy = regionMin.Y + (iy - 0.5) * RESOLUTION
				if wy <= surfaceY then
					materials[ix][iy][iz] = Enum.Material.Mud
					occupancies[ix][iy][iz] = 1
				else
					materials[ix][iy][iz] = Enum.Material.Air
					occupancies[ix][iy][iz] = 0
				end
			end
		end

		if ix % 8 == 0 then
			task.wait()
		end
	end

	terrain:WriteVoxels(region, RESOLUTION, materials, occupancies)

	self:_generatePillars(rng)

	print("[ProvingGroundsTerrainService] Terrain generated with seed " .. tostring(self._seed))
end

return ProvingGroundsTerrainService
