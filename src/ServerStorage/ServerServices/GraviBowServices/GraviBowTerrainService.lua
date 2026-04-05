local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local RESOLUTION = 4
local PLANET_TAG = "planet"
local HUB_PLANET_TAG = "planetHub"

local BIOME_PRESETS = {
	{
		surfaceMaterial = Enum.Material.Grass,
		coreMaterial = Enum.Material.Rock,
		noise = {
			amplitude = 12,
			frequency = 0.06,
			octaves = 5,
			lacunarity = 2.1,
			gain = 0.45,
			warpStrength = 0.3,
		},
		layers = {
			{ depth = 0.85, material = Enum.Material.Rock },
			{ depth = 0.94, material = Enum.Material.Ground },
			{ depth = 1.0, material = Enum.Material.Grass },
		},
		caves = { enabled = true, threshold = 0.42, scale = 0.05, minDepth = 0.5 },
	},
	{
		surfaceMaterial = Enum.Material.Sand,
		coreMaterial = Enum.Material.Sandstone,
		noise = {
			amplitude = 8,
			frequency = 0.08,
			octaves = 4,
			lacunarity = 2.0,
			gain = 0.5,
			warpStrength = 0.2,
		},
		layers = {
			{ depth = 0.8, material = Enum.Material.Sandstone },
			{ depth = 0.95, material = Enum.Material.Sand },
			{ depth = 1.0, material = Enum.Material.Sand },
		},
		caves = { enabled = false },
	},
	{
		surfaceMaterial = Enum.Material.Snow,
		coreMaterial = Enum.Material.Glacier,
		noise = {
			amplitude = 18,
			frequency = 0.05,
			octaves = 6,
			lacunarity = 2.2,
			gain = 0.42,
			warpStrength = 0.35,
		},
		layers = {
			{ depth = 0.75, material = Enum.Material.Glacier },
			{ depth = 0.9, material = Enum.Material.Rock },
			{ depth = 1.0, material = Enum.Material.Snow },
		},
		caves = { enabled = true, threshold = 0.4, scale = 0.045, minDepth = 0.4 },
	},
	{
		surfaceMaterial = Enum.Material.CrackedLava,
		coreMaterial = Enum.Material.Basalt,
		noise = {
			amplitude = 14,
			frequency = 0.07,
			octaves = 5,
			lacunarity = 2.3,
			gain = 0.48,
			warpStrength = 0.4,
		},
		layers = {
			{ depth = 0.7, material = Enum.Material.Basalt },
			{ depth = 0.88, material = Enum.Material.Slate },
			{ depth = 1.0, material = Enum.Material.CrackedLava },
		},
		caves = { enabled = true, threshold = 0.38, scale = 0.06, minDepth = 0.35 },
	},
}

local function fbm3d(x, y, z, octaves, lacunarity, gain, seed)
	local sum = 0
	local amp = 1
	local freq = 1
	local norm = 0
	for _ = 1, octaves do
		sum += math.noise(x * freq + seed, y * freq + seed * 1.3, z * freq + seed * 0.7) * amp
		norm += amp
		amp *= gain
		freq *= lacunarity
	end
	return sum / math.max(norm, 1e-6)
end

local function domainWarp3d(nx, ny, nz, strength, seed)
	local wx = nx + math.noise(ny * 3 + seed, nz * 3 + seed * 1.1, seed * 0.3) * strength
	local wy = ny + math.noise(nz * 3 + seed * 2, nx * 3 + seed * 1.7, seed * 0.6) * strength
	local wz = nz + math.noise(nx * 3 + seed * 3, ny * 3 + seed * 2.1, seed * 0.9) * strength
	return wx, wy, wz
end

local function cave3d(x, y, z, scale, seed)
	return math.noise(x * scale + seed * 0.1, y * scale * 1.15 + seed * 0.2, z * scale + seed * 0.3)
end

local function getMaterialForDepth(normalizedDist, layers, coreMaterial)
	for _, layer in ipairs(layers) do
		if normalizedDist <= layer.depth then
			return layer.material
		end
	end
	return coreMaterial
end

local GraviBowTerrainService = Knit.CreateService({
	Name = "GraviBowTerrainService",
	Client = {},
	_anchorFolder = nil,
})

function GraviBowTerrainService:KnitInit() end

function GraviBowTerrainService:KnitStart()
	self:GenerateAllPlanets()
end

function GraviBowTerrainService:GenerateAllPlanets()
	local terrain = Workspace.Terrain

	local tagged = CollectionService:GetTagged(PLANET_TAG)
	local spheres = {}
	for _, instance in ipairs(tagged) do
		if CollectionService:HasTag(instance, HUB_PLANET_TAG) then continue end

		local part = nil
		if instance:IsA("BasePart") then
			part = instance
		elseif instance:IsA("Model") then
			part = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
		end
		if part then
			table.insert(spheres, { instance = instance, part = part })
		end
	end

	if #spheres == 0 then
		print("[GraviBowTerrainService] No non-hub planet spheres found; nothing to replace")
		return
	end

	self._replacedSpheres = {}

	for i, entry in ipairs(spheres) do
		local part = entry.part
		local center = part.Position
		local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2

		local biome = BIOME_PRESETS[((i - 1) % #BIOME_PRESETS) + 1]
		local seed = i * 137 + 42

		local config = {
			name = entry.instance.Name,
			center = center,
			radius = radius,
			seed = seed,
			surfaceMaterial = biome.surfaceMaterial,
			coreMaterial = biome.coreMaterial,
			noise = biome.noise,
			layers = biome.layers,
			caves = biome.caves,
			skipAnchor = true,
		}

		local ok, err = pcall(function()
			self:_generatePlanet(terrain, config)
		end)
		if ok then
			self:_hideSphere(entry.instance)
			table.insert(self._replacedSpheres, { instance = entry.instance, config = config })
			print("[GraviBowTerrainService] Replaced sphere", entry.instance.Name, "with terrain at", center, "r:", radius)
		else
			warn("[GraviBowTerrainService] Failed to generate terrain for", entry.instance.Name, ":", err)
		end
		task.wait()
	end

	print("[GraviBowTerrainService] All planets generated (" .. #self._replacedSpheres .. " replaced)")
end

function GraviBowTerrainService:_hideSphere(instance)
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, desc in ipairs(instance:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end
	for _, part in ipairs(parts) do
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
end

function GraviBowTerrainService:_generatePlanet(terrain, config)
	local center = config.center
	local radius = config.radius
	local seed = config.seed
	local noiseConfig = config.noise
	local caveConfig = config.caves or {}

	local outerRadius = radius + noiseConfig.amplitude + 4

	local minV = center - Vector3.new(outerRadius, outerRadius, outerRadius)
	local maxV = center + Vector3.new(outerRadius, outerRadius, outerRadius)
	local region = Region3.new(minV, maxV):ExpandToGrid(RESOLUTION)

	local materials, occupancies = terrain:ReadVoxels(region, RESOLUTION)
	if not materials or not occupancies then
		warn("[GraviBowTerrainService] ReadVoxels failed for", config.name)
		return
	end

	local nx = #materials
	local ny = materials[1] and #materials[1] or 0
	local nz = (materials[1] and materials[1][1]) and #materials[1][1] or 0
	if nx == 0 or ny == 0 or nz == 0 then
		warn("[GraviBowTerrainService] Empty voxel grid for", config.name)
		return
	end

	local regionPos = region.CFrame.Position
	local regionSize = region.Size
	local minCorner = regionPos - regionSize * 0.5

	local amp = noiseConfig.amplitude
	local freq = noiseConfig.frequency
	local octaves = noiseConfig.octaves
	local lac = noiseConfig.lacunarity
	local gain = noiseConfig.gain
	local warp = noiseConfig.warpStrength
	local caveEnabled = caveConfig.enabled == true
	local caveThreshold = caveConfig.threshold or 0.4
	local caveScale = caveConfig.scale or 0.05
	local caveMinDepth = caveConfig.minDepth or 0.4

	for ix = 1, nx do
		for iy = 1, ny do
			for iz = 1, nz do
				local wx = minCorner.X + (ix - 0.5) * RESOLUTION
				local wy = minCorner.Y + (iy - 0.5) * RESOLUTION
				local wz = minCorner.Z + (iz - 0.5) * RESOLUTION

				local dx = wx - center.X
				local dy = wy - center.Y
				local dz = wz - center.Z
				local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

				if dist < 0.001 then
					materials[ix][iy][iz] = config.coreMaterial
					occupancies[ix][iy][iz] = 1
					continue
				end

				local dirX = dx / dist
				local dirY = dy / dist
				local dirZ = dz / dist

				local sampleX = dirX * freq
				local sampleY = dirY * freq
				local sampleZ = dirZ * freq

				local warpedX, warpedY, warpedZ = domainWarp3d(sampleX, sampleY, sampleZ, warp, seed)
				local heightNoise = fbm3d(warpedX, warpedY, warpedZ, octaves, lac, gain, seed)

				local surfaceRadius = radius + heightNoise * amp

				local solid = dist <= surfaceRadius

				if solid and caveEnabled then
					local normalizedDist = dist / surfaceRadius
					if normalizedDist < caveMinDepth then
						local c = cave3d(wx, wy, wz, caveScale, seed)
						if c > caveThreshold then
							solid = false
						end
					end
				end

				if solid then
					local normalizedDist = dist / surfaceRadius
					local mat = getMaterialForDepth(normalizedDist, config.layers, config.coreMaterial)
					materials[ix][iy][iz] = mat

					local edgeDist = surfaceRadius - dist
					if edgeDist < RESOLUTION then
						occupancies[ix][iy][iz] = math.clamp(edgeDist / RESOLUTION, 0.1, 1)
					else
						occupancies[ix][iy][iz] = 1
					end
				else
					materials[ix][iy][iz] = Enum.Material.Air
					occupancies[ix][iy][iz] = 0
				end
			end
		end

		if ix % 4 == 0 then
			task.wait()
		end
	end

	terrain:WriteVoxels(region, RESOLUTION, materials, occupancies)

	if not config.skipAnchor then
		self:_createPlanetAnchor(config)
	end
end

function GraviBowTerrainService:_createPlanetAnchor(config)
	if not self._anchorFolder then
		self._anchorFolder = Instance.new("Folder")
		self._anchorFolder.Name = "TerrainPlanets"
		self._anchorFolder.Parent = Workspace
	end

	local diameter = config.radius * 2

	local anchor = Instance.new("Part")
	anchor.Name = config.name
	anchor.Shape = Enum.PartType.Ball
	anchor.Size = Vector3.new(diameter, diameter, diameter)
	anchor.Position = config.center
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Parent = self._anchorFolder

	CollectionService:AddTag(anchor, PLANET_TAG)

	print("[GraviBowTerrainService] Tagged terrain anchor", config.name, "as", PLANET_TAG)
end

function GraviBowTerrainService:ClearAllPlanets()
	local terrain = Workspace.Terrain

	if self._replacedSpheres then
		for _, entry in ipairs(self._replacedSpheres) do
			local config = entry.config
			local outerRadius = config.radius + config.noise.amplitude + 4
			local minV = config.center - Vector3.new(outerRadius, outerRadius, outerRadius)
			local maxV = config.center + Vector3.new(outerRadius, outerRadius, outerRadius)
			local region = Region3.new(minV, maxV):ExpandToGrid(RESOLUTION)
			terrain:FillRegion(region, RESOLUTION, Enum.Material.Air)
		end
		self._replacedSpheres = nil
	end

	if self._anchorFolder then
		self._anchorFolder:Destroy()
		self._anchorFolder = nil
	end

	print("[GraviBowTerrainService] All planets cleared")
end

function GraviBowTerrainService:RegenerateAllPlanets()
	self:ClearAllPlanets()
	task.wait(0.1)
	self:GenerateAllPlanets()
end

return GraviBowTerrainService
