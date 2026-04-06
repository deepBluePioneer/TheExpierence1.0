local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local RESOLUTION = 4
local PLANET_TAG = "planet"
local DEFAULT_RADIUS = 90

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
	_sharedPlanet = nil,
})

function GraviBowTerrainService:KnitInit() end
function GraviBowTerrainService:KnitStart() end


function GraviBowTerrainService:CreateSharedPlanet()
	if self._sharedPlanet then
		return self._sharedPlanet
	end

	local center = Vector3.new(0, 0, 0)
	local biome = BIOME_PRESETS[2]
	local seed = 42

	local config = {
		name = "SharedPlanet",
		center = center,
		radius = DEFAULT_RADIUS,
		seed = seed,
		surfaceMaterial = biome.surfaceMaterial,
		coreMaterial = biome.coreMaterial,
		noise = {
			amplitude = biome.noise.amplitude,
			frequency = biome.noise.frequency,
			octaves = biome.noise.octaves,
			lacunarity = biome.noise.lacunarity,
			gain = biome.noise.gain,
			warpStrength = biome.noise.warpStrength,
		},
		layers = biome.layers,
		caves = biome.caves,
	}

	local ok, err = pcall(function()
		self:_generateTerrain(config)
	end)

	if not ok then
		warn("[GraviBowTerrainService] Failed to generate shared planet:", err)
		return nil
	end

	local anchor = self:_createPlanetAnchor(config)
	self:_createDustStorm(anchor, center, DEFAULT_RADIUS + biome.noise.amplitude)
	print("[GraviBowTerrainService] Created shared planet at", center)

	self._sharedPlanet = {
		anchor = anchor,
		center = center,
		radius = DEFAULT_RADIUS,
		noiseAmplitude = biome.noise.amplitude,
		config = config,
	}
	return self._sharedPlanet
end

function GraviBowTerrainService:GetSharedPlanet()
	return self._sharedPlanet
end

function GraviBowTerrainService:_createDustStorm(anchor, center, surfaceRadius)
	local EMITTER_COUNT = 26
	local DUST_COLOR = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(210, 180, 130)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(190, 160, 110)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 130, 90)),
	})
	local DUST_TRANSPARENCY = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.6),
		NumberSequenceKeypoint.new(0.7, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	local DUST_SIZE = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(0.3, 12),
		NumberSequenceKeypoint.new(0.7, 18),
		NumberSequenceKeypoint.new(1, 8),
	})

	local goldenAngle = math.pi * (3 - math.sqrt(5))

	for i = 1, EMITTER_COUNT do
		local t = (i - 0.5) / EMITTER_COUNT
		local phi = math.acos(1 - 2 * t)
		local theta = goldenAngle * i

		local dir = Vector3.new(
			math.sin(phi) * math.cos(theta),
			math.cos(phi),
			math.sin(phi) * math.sin(theta)
		).Unit

		local pos = center + dir * (surfaceRadius + 5)

		local att = Instance.new("Attachment")
		att.Name = "DustAtt_" .. i
		att.WorldPosition = pos
		att.Parent = anchor

		local tangent = dir:Cross(Vector3.new(0, 1, 0))
		if tangent.Magnitude < 0.01 then
			tangent = dir:Cross(Vector3.new(1, 0, 0))
		end
		tangent = tangent.Unit

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "DustStorm"
		emitter.Color = DUST_COLOR
		emitter.Transparency = DUST_TRANSPARENCY
		emitter.Size = DUST_SIZE
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Rate = 8
		emitter.Lifetime = NumberRange.new(4, 8)
		emitter.Speed = NumberRange.new(6, 14)
		emitter.SpreadAngle = Vector2.new(40, 40)
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-30, 30)
		emitter.LightEmission = 0.05
		emitter.LightInfluence = 0.9
		emitter.Drag = 1
		emitter.Acceleration = tangent * 3
		emitter.Parent = att
	end
end

function GraviBowTerrainService:_generateTerrain(config)
	local terrain = Workspace.Terrain
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
	task.wait()
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

	return anchor
end

return GraviBowTerrainService
