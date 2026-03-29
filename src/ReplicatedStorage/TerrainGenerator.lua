local TerrainGenerator = {}

local DEFAULT_VERTICAL_STUDS = 132

local function fbm2d(x, z, octaves, lacunarity, gain, seed)
	local sum = 0
	local a = 1
	local f = 1
	local norm = 0
	for _ = 1, octaves do
		sum = sum + math.noise(x * f + seed * 0.01, z * f + seed * 0.02) * a
		norm = norm + a
		a = a * gain
		f = f * lacunarity
	end
	return sum / math.max(norm, 1e-4)
end

local function ridged2d(x, z, seed)
	local n = math.noise(x + seed * 0.03, z + seed * 0.04)
	return 1 - math.abs(n)
end

local function domainWarp(x, z, warpAmp, seed)
	local wx = x + math.noise(z * 0.08 + seed, seed * 1.1) * warpAmp
	local wz = z + math.noise(x * 0.08 + seed * 2, seed * 1.7) * warpAmp
	return wx, wz
end

local function cave3d(wx, wy, wz, scale, seed)
	return math.noise(wx * scale + seed, wy * scale * 1.15 + seed * 2, wz * scale + seed * 3)
end

function TerrainGenerator.computeSurfaceY(biome, wx, wz, baseY)
	local T = biome.terrain or {}
	local seed = biome.seed or 0
	local amp = biome.amp * (T.heightScale or 1)
	local nScale = biome.noiseScale or 0.008
	local octaves = T.octaves or 4
	local lacunarity = T.lacunarity or 2
	local gain = T.gain or 0.5
	local ridgeWeight = T.ridgeWeight or 0.2
	local warpAmp = T.warpAmp or 12
	local baseHeight = T.baseHeight or 0

	local wx2, wz2 = domainWarp(wx * nScale, wz * nScale, warpAmp * nScale, seed)
	local h = fbm2d(wx2, wz2, octaves, lacunarity, gain, seed)
	local ridge = ridged2d(wx2 * 1.3 + seed * 0.05, wz2 * 1.3 + seed * 0.06, seed)
	local combined = h * (1 - ridgeWeight) + ridge * ridgeWeight
	return baseY + baseHeight + (combined * 0.5 + 0.5) * amp
end

function TerrainGenerator.getVerticalTopY(biome, terrainBase)
	local floorY = terrainBase.BASE_Y - 20
	local T = biome and biome.terrain or {}
	return floorY + (T.verticalStuds or DEFAULT_VERTICAL_STUDS)
end

local function expandedRegionForBiome(cx, cz, floorY, topY, terrainBase)
	local halfW = terrainBase.WIDTH / 2
	local halfD = terrainBase.DEPTH / 2
	local minV = Vector3.new(cx - halfW, floorY, cz - halfD)
	local maxV = Vector3.new(cx + halfW, topY, cz + halfD)
	return Region3.new(minV, maxV):ExpandToGrid(terrainBase.RESOLUTION)
end

local function voxelBoundsFromExpandedRegion(region, res)
	local minPt = region.CFrame.Position - region.Size * 0.5
	local maxPt = region.CFrame.Position + region.Size * 0.5
	local minCornerV = Vector3int16.new(
		math.floor(minPt.X / res),
		math.floor(minPt.Y / res),
		math.floor(minPt.Z / res)
	)
	local maxCornerV = Vector3int16.new(
		math.ceil(maxPt.X / res),
		math.ceil(maxPt.Y / res),
		math.ceil(maxPt.Z / res)
	)
	return minCornerV, maxCornerV
end

-- Min voxel corner for PasteRegion; must match generateBiomeSnapshot / CopyRegion for this biome.
function TerrainGenerator.getPasteMinCorner(cx, cz, biome, terrainBase)
	local floorY = terrainBase.BASE_Y - 20
	local T = biome and biome.terrain or {}
	local topY = floorY + (T.verticalStuds or DEFAULT_VERTICAL_STUDS)
	local region = expandedRegionForBiome(cx, cz, floorY, topY, terrainBase)
	local minCornerV, _ = voxelBoundsFromExpandedRegion(region, terrainBase.RESOLUTION)
	return minCornerV
end

function TerrainGenerator.generateBiomeSnapshot(terrain, biome, cx, cz, terrainBase)
	local res = terrainBase.RESOLUTION
	local baseY = terrainBase.BASE_Y
	local floorY = baseY - 20

	local T = biome.terrain or {}
	local topY = floorY + (T.verticalStuds or DEFAULT_VERTICAL_STUDS)
	local caveEnabled = T.caveEnabled ~= false
	local caveThreshold = T.caveThreshold or 0.38
	local caveScale = T.caveScale or 0.035
	local skinVoxels = T.caveSkinVoxels or 2
	local seed = biome.seed or 0

	local region = expandedRegionForBiome(cx, cz, floorY, topY, terrainBase)

	terrain:FillRegion(region, res, Enum.Material.Air)

	local materials, occupancies = terrain:ReadVoxels(region, res)
	if not materials or not occupancies then
		warn("[TerrainGenerator] ReadVoxels failed")
		return nil
	end

	local nx = #materials
	local ny = materials[1] and #materials[1] or 0
	local nz = (materials[1] and materials[1][1]) and #materials[1][1] or 0
	if nx == 0 or ny == 0 or nz == 0 then
		warn("[TerrainGenerator] Empty voxel read")
		return nil
	end

	local regCf = region.CFrame
	local regSize = region.Size
	local minCorner = regCf.Position - regSize * 0.5
	local mat = biome.material or Enum.Material.Grass

	local clearR = terrainBase.CLEAR_RADIUS or 0
	local clearB = terrainBase.CLEAR_BLEND or 0
	local clearMaxY = terrainBase.CLEAR_MAX_Y or baseY
	local hasClear = clearR > 0

	local flatY = clearMaxY

	local skinWorld = skinVoxels * res
	for ix = 1, nx do
		for iy = 1, ny do
			for iz = 1, nz do
				local wx = minCorner.X + (ix - 0.5) * res
				local wy = minCorner.Y + (iy - 0.5) * res
				local wz = minCorner.Z + (iz - 0.5) * res

				local surfaceY = TerrainGenerator.computeSurfaceY(biome, wx, wz, baseY)

				if hasClear then
					local dx = wx - cx
					local dz = wz - cz
					local hDist = math.sqrt(dx * dx + dz * dz)
					if hDist < clearR then
						surfaceY = flatY
					elseif hDist < clearR + clearB then
						local blend = (hDist - clearR) / math.max(clearB, 0.01)
						surfaceY = flatY + (surfaceY - flatY) * blend
					end
				end

				local solid = wy <= surfaceY and wy >= floorY

				if solid and caveEnabled then
					local depthBelowSurface = surfaceY - wy
					if depthBelowSurface > skinWorld then
						local c = cave3d(wx, wy, wz, caveScale, seed)
						if c > caveThreshold then
							solid = false
						end
					end
				end

				if solid then
					materials[ix][iy][iz] = mat
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

	terrain:WriteVoxels(region, res, materials, occupancies)

	local minCornerV, maxCornerV = voxelBoundsFromExpandedRegion(region, res)
	local copyRegion = Region3int16.new(minCornerV, maxCornerV)
	local snapshot = terrain:CopyRegion(copyRegion)
	-- Strip live voxels so we do not leave a duplicate island in-world; PasteRegion restores from snapshot.
	terrain:FillRegion(region, res, Enum.Material.Air)
	if not snapshot then
		warn("[TerrainGenerator] CopyRegion failed")
	end
	return snapshot
end

function TerrainGenerator.clearGeneratedRegion(terrain, cx, cz, terrainBase, topY)
	local res = terrainBase.RESOLUTION
	local baseY = terrainBase.BASE_Y
	local floorY = baseY - 20
	local halfW = terrainBase.WIDTH / 2
	local halfD = terrainBase.DEPTH / 2
	local clearMin = Vector3.new(cx - halfW, floorY, cz - halfD)
	local clearMax = Vector3.new(cx + halfW, topY, cz + halfD)
	terrain:FillRegion(Region3.new(clearMin, clearMax):ExpandToGrid(res), res, Enum.Material.Air)
end

return TerrainGenerator
