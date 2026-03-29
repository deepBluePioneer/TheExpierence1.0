local Workspace = game:GetService("Workspace")

local TerrainGenerator = require(script.Parent.TerrainGenerator)
local LSystemEngine = require(script.Parent.LSystemEngine)

local BiomeElementPlacer = {}

local QUEUE_CELLS_PER_FRAME = 800
local SPAWN_PER_FRAME = 6

local function getOrCreateFolder()
	local f = Workspace:FindFirstChild("BiomeElements")
	if f then f:Destroy() end
	f = Instance.new("Folder")
	f.Name = "BiomeElements"
	f.Parent = Workspace
	return f
end

local function analyticalSurface(wx, wz, biome, terrainBase)
	local baseY = terrainBase.BASE_Y
	local sy = TerrainGenerator.computeSurfaceY(biome, wx, wz, baseY)
	return Vector3.new(wx, sy, wz), Vector3.new(0, 1, 0)
end

local function raycastTerrain(wx, wz, rayTopY, biome, terrainBase)
	local origin = Vector3.new(wx, rayTopY, wz)
	local dir = Vector3.new(0, -1, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local fl = {}
	local be = Workspace:FindFirstChild("BiomeElements")
	local lv = Workspace:FindFirstChild("LaneVisualization")
	if be then table.insert(fl, be) end
	if lv then table.insert(fl, lv) end
	params.FilterDescendantsInstances = fl
	local hit = Workspace:Raycast(origin, dir * 500, params)
	if hit and hit.Instance == Workspace.Terrain then
		return hit.Position, hit.Normal
	end
	return analyticalSurface(wx, wz, biome, terrainBase)
end

local function hideDescendants(instance)
	for _, desc in ipairs(instance:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = 1
		end
	end
end

function BiomeElementPlacer.cleanup()
	local f = Workspace:FindFirstChild("BiomeElements")
	if f then f:Destroy() end
end

function BiomeElementPlacer.startLazySpawn(biome, terrainBase, centerXZ, seed, opts)
	BiomeElementPlacer.cleanup()
	local folder = getOrCreateFolder()
	local cx, cz = centerXZ.X, centerXZ.Z
	local halfW = terrainBase.WIDTH / 2
	local halfD = terrainBase.DEPTH / 2
	local floorY = terrainBase.BASE_Y - 20
	local topY = TerrainGenerator.getVerticalTopY(biome, terrainBase)
	local rayTop = topY + 80

	opts = opts or {}
	local hidden = opts.hidden == true
	local useAnalytical = opts.analyticalHeight == true

	local elements = biome.elements or {}
	if #elements == 0 then
		return { cancel = function() end, done = true, reveal = function() end }
	end

	local clearR = (terrainBase.CLEAR_RADIUS or 0) + (terrainBase.CLEAR_BLEND or 0)
	local clearSq = clearR * clearR

	local cancelled = false
	local handle = { done = false }

	function handle.cancel()
		cancelled = true
	end

	function handle.reveal()
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				child.Transparency = 0
			elseif child:IsA("Model") then
				for _, desc in ipairs(child:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.Transparency = 0
					end
				end
			end
		end
	end

	task.spawn(function()
		local queue = {}
		local rng = Random.new(seed)
		local cellCount = 0

		for _, el in ipairs(elements) do
			local density = el.density or 0.01
			local cell = el.cell or 10
			local gx0 = math.floor((cx - halfW) / cell)
			local gx1 = math.ceil((cx + halfW) / cell)
			local gz0 = math.floor((cz - halfD) / cell)
			local gz1 = math.ceil((cz + halfD) / cell)
			for gx = gx0, gx1 do
				for gz = gz0, gz1 do
					if cancelled then return end
					cellCount = cellCount + 1
					if cellCount % QUEUE_CELLS_PER_FRAME == 0 then
						task.wait()
					end

					local jitterX = (rng:NextNumber() - 0.5) * cell * 0.9
					local jitterZ = (rng:NextNumber() - 0.5) * cell * 0.9
					local wx = gx * cell + jitterX
					local wz = gz * cell + jitterZ
					if math.abs(wx - cx) < halfW - 4 and math.abs(wz - cz) < halfD - 4 then
						local dx = wx - cx
						local dz = wz - cz
						if dx * dx + dz * dz < clearSq then
							rng:NextNumber()
							continue
						end
						local n = math.noise(wx * 0.03 + seed, wz * 0.03 + seed * 2)
						if rng:NextNumber() < density * (0.6 + n) * 4 then
							table.insert(queue, { el = el, wx = wx, wz = wz })
						end
					end
				end
			end
		end

		local qi = 1
		while not cancelled and qi <= #queue do
			for _ = 1, SPAWN_PER_FRAME do
				if cancelled or qi > #queue then
					break
				end
				local job = queue[qi]
				qi = qi + 1
				local el = job.el
				local pos, normal
				if useAnalytical then
					pos, normal = analyticalSurface(job.wx, job.wz, biome, terrainBase)
				else
					pos, normal = raycastTerrain(job.wx, job.wz, rayTop, biome, terrainBase)
				end
				if pos.Y > floorY + 4 and pos.Y < topY - 2 then
					local up = normal.Unit
					if up.Y >= 0.35 then
						local scale = (el.minScale or 0.8) + rng:NextNumber() * ((el.maxScale or 1.2) - (el.minScale or 0.8))
						if el.type == "lsystem" and el.rule then
							local yAxis = Vector3.new(0, 1, 0)
							local u = up.Unit
							local d = math.clamp(yAxis:Dot(u), -1, 1)
							local baseRot = CFrame.new()
							if math.abs(d - 1) < 1e-3 then
								baseRot = CFrame.new()
							elseif math.abs(d + 1) < 1e-3 then
								baseRot = CFrame.Angles(math.pi, 0, 0)
							else
								local axis = yAxis:Cross(u)
								baseRot = CFrame.fromAxisAngle(axis.Unit, math.acos(d))
							end
							local cf = CFrame.new(pos) * baseRot
							local m = LSystemEngine.generate(el.rule, cf, scale, rng:NextInteger(1, 1000000000))
							if hidden then
								hideDescendants(m)
							end
							m.Parent = folder
						elseif el.type == "simple" then
							local p = Instance.new("Part")
							p.Name = el.name or "Prop"
							p.Anchored = true
							p.CanCollide = false
							p.Material = el.material or Enum.Material.Slate
							p.Color = el.color or Color3.new(0.5, 0.5, 0.5)
							local smin = el.sizeMin or Vector3.new(2, 2, 2)
							local smax = el.sizeMax or Vector3.new(4, 4, 4)
							p.Size = Vector3.new(
								smin.X + rng:NextNumber() * (smax.X - smin.X),
								smin.Y + rng:NextNumber() * (smax.Y - smin.Y),
								smin.Z + rng:NextNumber() * (smax.Z - smin.Z)
							)
							if el.shape == "Ball" then
								p.Shape = Enum.PartType.Ball
							end
							p.CFrame = CFrame.lookAt(pos + up * (p.Size.Y * 0.5), pos + up * 2, Vector3.new(1, 0, 0))
							if hidden then
								p.Transparency = 1
							end
							p.Parent = folder
						end
					end
				end
			end
			task.wait()
		end
		handle.done = true
	end)

	return handle
end

return BiomeElementPlacer
