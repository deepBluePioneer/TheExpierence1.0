local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local PLANET_CENTER = Vector3.new(0, 0, 0)
local PLANET_RADIUS = 90
local GRAVITY_ACCEL = 120
local STRUCTURE_COUNT = 24
local POST_SINK = 3
local PART_DENSITY = 4
local SEED = 42

local MATERIAL = Enum.Material.DiamondPlate
local PLANK_MATERIAL = Enum.Material.WoodPlanks
local METAL_COLOR = Color3.fromRGB(115, 115, 120)
local PLANK_COLOR = Color3.fromRGB(140, 110, 70)
local BRACE_COLOR = Color3.fromRGB(170, 160, 50)
local DARK_METAL = Color3.fromRGB(80, 80, 85)

local GraviBowStructureService = Knit.CreateService({
	Name = "GraviBowStructureService",
	Client = {},
	_structureFolder = nil,
	_structures = {},
	_releasedParts = {},
})

function GraviBowStructureService:KnitInit()
end

function GraviBowStructureService:KnitStart()
	self._structureFolder = Instance.new("Folder")
	self._structureFolder.Name = "Structures"
	self._structureFolder.Parent = Workspace

	RunService.Heartbeat:Connect(function()
		self:_updateGravity()
	end)

	task.defer(function()
		self:_buildStructures()
	end)
end

function GraviBowStructureService:_updateGravity()
	for i = #self._releasedParts, 1, -1 do
		local entry = self._releasedParts[i]
		local part = entry.part
		local vf = entry.vf

		if not part.Parent then
			table.remove(self._releasedParts, i)
			continue
		end

		local gravDir = (PLANET_CENTER - part.Position)
		if gravDir.Magnitude > 0.01 then
			gravDir = gravDir.Unit
		else
			gravDir = Vector3.new(0, -1, 0)
		end

		vf.Force = gravDir * GRAVITY_ACCEL * part.AssemblyMass
	end
end

function GraviBowStructureService:_getSurfacePoint(direction)
	local rayOrigin = PLANET_CENTER + direction * (PLANET_RADIUS + 50)
	local rayDir = -direction * 100

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList = {}
	local snakeBodies = Workspace:FindFirstChild("SnakeBodies")
	if snakeBodies then table.insert(excludeList, snakeBodies) end
	local gravZones = Workspace:FindFirstChild("GravityZones")
	if gravZones then table.insert(excludeList, gravZones) end
	local npcFolder = Workspace:FindFirstChild("GraviNPCs")
	if npcFolder then table.insert(excludeList, npcFolder) end
	local structures = Workspace:FindFirstChild("Structures")
	if structures then table.insert(excludeList, structures) end
	rayParams.FilterDescendantsInstances = excludeList

	local result = Workspace:Raycast(rayOrigin, rayDir, rayParams)
	if result then
		return result.Position, result.Normal
	end

	return PLANET_CENTER + direction * PLANET_RADIUS, direction
end

function GraviBowStructureService:_surfaceCFrame(surfacePos, upDir, yawAngle)
	local forward = upDir:Cross(Vector3.new(0, 0, 1))
	if forward.Magnitude < 0.01 then
		forward = upDir:Cross(Vector3.new(1, 0, 0))
	end
	forward = forward.Unit
	local right = forward:Cross(upDir).Unit
	local cf = CFrame.fromMatrix(surfacePos, right, upDir, -forward)
	if yawAngle and yawAngle ~= 0 then
		cf = cf * CFrame.Angles(0, yawAngle, 0)
	end
	return cf
end

function GraviBowStructureService:_isSnakeSegment(part)
	local parent = part.Parent
	if not parent then return false end
	return string.find(parent.Name, "^Snake_") ~= nil
end

function GraviBowStructureService:_releaseStructure(structureGroup)
	if structureGroup.released then return end
	structureGroup.released = true

	for _, part in ipairs(structureGroup.parts) do
		if not part.Parent then continue end

		part.Anchored = false

		local att = Instance.new("Attachment")
		att.Name = "GravAtt"
		att.Parent = part

		local vf = Instance.new("VectorForce")
		vf.Name = "PlanetGravity"
		vf.Attachment0 = att
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = true
		vf.Force = Vector3.zero
		vf.Parent = part

		table.insert(self._releasedParts, { part = part, vf = vf })
	end
end

function GraviBowStructureService:_addPart(group, name, size, cf, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = true
	part.Material = material or MATERIAL
	part.Color = color or METAL_COLOR
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	local props = PhysicalProperties.new(PART_DENSITY, 0.5, 0.3, 1, 1)
	part.CustomPhysicalProperties = props

	part.Parent = self._structureFolder
	table.insert(group.parts, part)
	return part
end

function GraviBowStructureService:_wireUpGroup(group)
	for _, part in ipairs(group.parts) do
		part.Touched:Connect(function(hit)
			if self:_isSnakeSegment(hit) then
				self:_releaseStructure(group)
			end
		end)
	end
	table.insert(self._structures, group)
end

function GraviBowStructureService:_addPosts(group, baseCF, width, depth, height, postThick)
	local hx = width / 2
	local hz = depth / 2
	local corners = {
		Vector3.new(-hx, 0, -hz),
		Vector3.new( hx, 0, -hz),
		Vector3.new(-hx, 0,  hz),
		Vector3.new( hx, 0,  hz),
	}
	for i, off in ipairs(corners) do
		local cf = baseCF * CFrame.new(off) * CFrame.new(0, height / 2, 0)
		self:_addPart(group, "Post_" .. i, Vector3.new(postThick, height, postThick), cf, METAL_COLOR)
	end
end

function GraviBowStructureService:_addDeck(group, baseCF, width, depth, y, thickness)
	thickness = thickness or 0.6
	local cf = baseCF * CFrame.new(0, y, 0)
	self:_addPart(group, "Deck", Vector3.new(width + 1, thickness, depth + 1), cf, PLANK_COLOR, PLANK_MATERIAL)
end

function GraviBowStructureService:_addRails(group, baseCF, width, depth, y, railHeight, railThick)
	railHeight = railHeight or 3
	railThick = railThick or 0.4
	local hx = width / 2 + 0.3
	local hz = depth / 2 + 0.3

	local sides = {
		{ pos = Vector3.new(0, y + railHeight / 2, -hz), size = Vector3.new(width + 1, railThick, railThick) },
		{ pos = Vector3.new(0, y + railHeight / 2,  hz), size = Vector3.new(width + 1, railThick, railThick) },
		{ pos = Vector3.new(-hx, y + railHeight / 2, 0), size = Vector3.new(railThick, railThick, depth + 1) },
		{ pos = Vector3.new( hx, y + railHeight / 2, 0), size = Vector3.new(railThick, railThick, depth + 1) },
	}
	for i, s in ipairs(sides) do
		local cf = baseCF * CFrame.new(s.pos)
		self:_addPart(group, "Rail_" .. i, s.size, cf, BRACE_COLOR)
	end
end

function GraviBowStructureService:_addCrossBraces(group, baseCF, width, depth, yBottom, yTop, braceThick)
	braceThick = braceThick or 0.4
	local hx = width / 2
	local hz = depth / 2
	local spanH = yTop - yBottom

	local faces = {
		{ a = Vector3.new(-hx, yBottom, -hz), b = Vector3.new(hx, yTop, -hz) },
		{ a = Vector3.new(hx, yBottom, hz),   b = Vector3.new(-hx, yTop, hz) },
		{ a = Vector3.new(-hx, yBottom, -hz), b = Vector3.new(-hx, yTop, hz) },
		{ a = Vector3.new(hx, yBottom, hz),   b = Vector3.new(hx, yTop, -hz) },
	}

	for i, face in ipairs(faces) do
		local mid = (face.a + face.b) / 2
		local dir = face.b - face.a
		local length = dir.Magnitude
		local cf = baseCF * CFrame.lookAt(mid, mid + dir) * CFrame.Angles(math.rad(90), 0, 0)
		cf = cf + (baseCF * CFrame.new(mid)).Position - cf.Position
		local worldA = baseCF * CFrame.new(face.a)
		local worldB = baseCF * CFrame.new(face.b)
		local worldMid = worldA.Position:Lerp(worldB.Position, 0.5)
		local worldDir = (worldB.Position - worldA.Position)
		local braceCF = CFrame.lookAt(worldMid, worldMid + worldDir)
		braceCF = braceCF * CFrame.Angles(0, 0, math.rad(90))
		self:_addPart(group, "Brace_" .. i, Vector3.new(length, braceThick, braceThick), braceCF, BRACE_COLOR)
	end
end

function GraviBowStructureService:_buildScaffoldSmall(baseCF)
	local group = { parts = {}, released = false }
	local w, d, postThick = 8, 8, 0.8
	local levels = 2
	local levelH = 8

	local totalH = levels * levelH
	self:_addPosts(group, baseCF * CFrame.new(0, -POST_SINK, 0), w, d, totalH + POST_SINK, postThick)

	for lv = 1, levels do
		local y = lv * levelH - POST_SINK
		self:_addDeck(group, baseCF, w, d, y)
		if lv < levels then
			self:_addCrossBraces(group, baseCF, w, d, (lv - 1) * levelH - POST_SINK, y)
		end
	end

	self:_addRails(group, baseCF, w, d, levels * levelH - POST_SINK)
	self:_wireUpGroup(group)
end

function GraviBowStructureService:_buildScaffoldTall(baseCF)
	local group = { parts = {}, released = false }
	local w, d, postThick = 8, 8, 1.0
	local levels = 4
	local levelH = 7

	local totalH = levels * levelH
	self:_addPosts(group, baseCF * CFrame.new(0, -POST_SINK, 0), w, d, totalH + POST_SINK, postThick)

	for lv = 1, levels do
		local y = lv * levelH - POST_SINK
		self:_addDeck(group, baseCF, w, d, y)
		self:_addCrossBraces(group, baseCF, w, d, (lv - 1) * levelH - POST_SINK, y)
	end

	self:_addRails(group, baseCF, w, d, levels * levelH - POST_SINK)
	self:_wireUpGroup(group)
end

function GraviBowStructureService:_buildScaffoldWide(baseCF)
	local group = { parts = {}, released = false }
	local w, d, postThick = 16, 8, 0.8
	local levels = 2
	local levelH = 8

	local totalH = levels * levelH
	self:_addPosts(group, baseCF * CFrame.new(0, -POST_SINK, 0), w, d, totalH + POST_SINK, postThick)

	local midCF = baseCF * CFrame.new(0, -POST_SINK, 0)
	for _, xOff in ipairs({0}) do
		local cf = midCF * CFrame.new(xOff, 0, 0)
		self:_addPart(group, "MidPost_F", Vector3.new(postThick, totalH + POST_SINK, postThick),
			cf * CFrame.new(0, (totalH + POST_SINK) / 2, -d / 2), METAL_COLOR)
		self:_addPart(group, "MidPost_B", Vector3.new(postThick, totalH + POST_SINK, postThick),
			cf * CFrame.new(0, (totalH + POST_SINK) / 2, d / 2), METAL_COLOR)
	end

	for lv = 1, levels do
		local y = lv * levelH - POST_SINK
		self:_addDeck(group, baseCF, w, d, y)
		self:_addCrossBraces(group, baseCF, w, d, (lv - 1) * levelH - POST_SINK, y)
	end

	self:_addRails(group, baseCF, w, d, levels * levelH - POST_SINK)
	self:_wireUpGroup(group)
end

function GraviBowStructureService:_buildScaffoldTapered(baseCF)
	local group = { parts = {}, released = false }
	local postThick = 0.8
	local levels = 3
	local levelH = 7

	local widths = { 12, 9, 6 }
	local y = -POST_SINK

	for lv = 1, levels do
		local w = widths[lv] or 6
		local hx = w / 2
		local corners = {
			Vector3.new(-hx, 0, -hx),
			Vector3.new( hx, 0, -hx),
			Vector3.new(-hx, 0,  hx),
			Vector3.new( hx, 0,  hx),
		}
		for i, off in ipairs(corners) do
			local cf = baseCF * CFrame.new(off) * CFrame.new(0, y + levelH / 2, 0)
			self:_addPart(group, "Post_L" .. lv .. "_" .. i, Vector3.new(postThick, levelH, postThick), cf, METAL_COLOR)
		end

		y = y + levelH
		self:_addDeck(group, baseCF, w, w, y)

		if lv < levels then
			self:_addCrossBraces(group, baseCF, w, w, y - levelH, y)
		end
	end

	local topW = widths[levels] or 6
	self:_addRails(group, baseCF, topW, topW, y)
	self:_wireUpGroup(group)
end

function GraviBowStructureService:_buildScaffoldOpen(baseCF)
	local group = { parts = {}, released = false }
	local w, d, postThick = 10, 10, 0.8
	local levelH = 10

	local totalH = levelH
	self:_addPosts(group, baseCF * CFrame.new(0, -POST_SINK, 0), w, d, totalH + POST_SINK, postThick)

	local y = levelH - POST_SINK
	self:_addDeck(group, baseCF, w, d, y)
	self:_addCrossBraces(group, baseCF, w, d, -POST_SINK, y)
	self:_addRails(group, baseCF, w, d, y, 4)
	self:_wireUpGroup(group)
end

function GraviBowStructureService:_buildDoubleTower(baseCF)
	local group = { parts = {}, released = false }
	local w, d, postThick = 6, 6, 0.8
	local levels = 3
	local levelH = 7
	local separation = 10

	for _, xOff in ipairs({ -separation / 2, separation / 2 }) do
		local towerBase = baseCF * CFrame.new(xOff, 0, 0)
		local totalH = levels * levelH

		self:_addPosts(group, towerBase * CFrame.new(0, -POST_SINK, 0), w, d, totalH + POST_SINK, postThick)

		for lv = 1, levels do
			local y = lv * levelH - POST_SINK
			self:_addDeck(group, towerBase, w, d, y)
			if lv < levels then
				self:_addCrossBraces(group, towerBase, w, d, (lv - 1) * levelH - POST_SINK, y)
			end
		end

		self:_addRails(group, towerBase, w, d, levels * levelH - POST_SINK)
	end

	for lv = 1, levels do
		local y = lv * levelH - POST_SINK
		local bridgeCF = baseCF * CFrame.new(0, y, 0)
		self:_addPart(group, "Bridge_" .. lv,
			Vector3.new(separation - w, 0.6, d * 0.6),
			bridgeCF, PLANK_COLOR, PLANK_MATERIAL)
	end

	self:_wireUpGroup(group)
end

function GraviBowStructureService:_fibonacciSphere(count, seed)
	local rng = Random.new(seed)
	local points = {}
	local goldenAngle = math.pi * (3 - math.sqrt(5))

	for i = 0, count - 1 do
		local y = 1 - (i / (count - 1)) * 2
		local radius = math.sqrt(1 - y * y)
		local theta = goldenAngle * i + rng:NextNumber() * 0.3

		table.insert(points, Vector3.new(
			math.cos(theta) * radius,
			y,
			math.sin(theta) * radius
		).Unit)
	end

	return points
end

function GraviBowStructureService:_buildStructures()
	local directions = self:_fibonacciSphere(STRUCTURE_COUNT, SEED)
	local rng = Random.new(SEED)

	local builders = {
		self._buildScaffoldSmall,
		self._buildScaffoldTall,
		self._buildScaffoldWide,
		self._buildScaffoldTapered,
		self._buildScaffoldOpen,
		self._buildDoubleTower,
	}

	local built = 0
	for _, dir in ipairs(directions) do
		local surfacePos, surfaceNormal = self:_getSurfacePoint(dir)
		local yaw = rng:NextNumber() * math.pi * 2
		local baseCF = self:_surfaceCFrame(surfacePos, surfaceNormal, yaw)

		local idx = rng:NextInteger(1, #builders)
		builders[idx](self, baseCF)
		built += 1
	end

	print("[GraviBowStructureService] Built", built, "scaffolding structures")
end

return GraviBowStructureService
