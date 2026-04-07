local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local PLANET_TAG = "planet"
local CRYSTAL_TAG = "crystal"

local PATCHES_PER_100_RADIUS = 30
local CRYSTALS_PER_PATCH_MIN = 8
local CRYSTALS_PER_PATCH_MAX = 18
local PATCH_SPREAD = 12
local SCALE_MIN = 0.5
local SCALE_MAX = 1.8
local SURFACE_RAYCAST_HEIGHT = 60

local GraviBowCrystalService = Knit.CreateService({
	Name = "GraviBowCrystalService",
	Client = {},
	_crystalFolder = nil,
	_prefab = nil,
	_prefabUpVector = Vector3.new(0, 1, 0),
	_prefabRotation = CFrame.identity,
})

function GraviBowCrystalService:KnitInit() end

function GraviBowCrystalService:KnitStart()
	do return end -- crystals disabled

	self._prefab = self:_findPrefab()
	if not self._prefab then
		warn("[GraviBowCrystalService] No crystal prefab found")
		return
	end

	local pivot
	if self._prefab:IsA("Model") then
		pivot = self._prefab:GetPivot()
	else
		pivot = self._prefab.CFrame
	end
	self._prefabUpVector = pivot.UpVector
	self._prefabRotation = pivot - pivot.Position

	self._crystalFolder = Instance.new("Folder")
	self._crystalFolder.Name = "CrystalPatches"
	self._crystalFolder.Parent = Workspace

	task.defer(function()
		task.wait(2)
		self:_scatterAllPlanets()
	end)
end

function GraviBowCrystalService:_findPrefab()
	local tagged = CollectionService:GetTagged(CRYSTAL_TAG)
	for _, inst in ipairs(tagged) do
		if inst:IsA("Model") or inst:IsA("BasePart") then
			return inst
		end
	end

	local prefabs = ReplicatedStorage:FindFirstChild("prefabs")
		or ReplicatedStorage:FindFirstChild("Prefabs")
	if prefabs then
		for _, child in ipairs(prefabs:GetChildren()) do
			if CollectionService:HasTag(child, CRYSTAL_TAG) then
				return child
			end
			if child.Name:lower():find("crystal") then
				return child
			end
		end
	end

	return nil
end

function GraviBowCrystalService:_getPlanetPart(model)
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

function GraviBowCrystalService:_getAllPlanets()
	local planets = {}

	for _, model in ipairs(CollectionService:GetTagged(PLANET_TAG)) do
		local part = self:_getPlanetPart(model)
		if part then
			table.insert(planets, {
				center = part.Position,
				radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2,
			})
		end
	end

	return planets
end

function GraviBowCrystalService:_scatterAllPlanets()
	local planets = self:_getAllPlanets()
	print("[GraviBowCrystalService] Scattering crystals on", #planets, "planet(s)")

	for _, planet in ipairs(planets) do
		local patchCount = math.max(3, math.floor(planet.radius / 100 * PATCHES_PER_100_RADIUS))
		self:_scatterPlanet(planet, patchCount)
		task.wait()
	end

	print("[GraviBowCrystalService] Crystal scattering complete")
end

function GraviBowCrystalService:_scatterPlanet(planet, patchCount)
	local center = planet.center
	local radius = planet.radius

	for _ = 1, patchCount do
		local patchDir = self:_randomUnitSphere()
		local crystalCount = math.random(CRYSTALS_PER_PATCH_MIN, CRYSTALS_PER_PATCH_MAX)

		self:_spawnPatch(center, radius, patchDir, crystalCount)
	end
end

function GraviBowCrystalService:_spawnPatch(planetCenter, planetRadius, patchDir, count)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	local gzFolder = Workspace:FindFirstChild("GravityZones")
	if gzFolder then table.insert(filterList, gzFolder) end
	local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
	if tpFolder then table.insert(filterList, tpFolder) end
	if self._crystalFolder then table.insert(filterList, self._crystalFolder) end
	rayParams.FilterDescendantsInstances = filterList

	for _ = 1, count do
		local jitter = self:_randomTangentOffset(patchDir, PATCH_SPREAD / planetRadius)
		local dir = (patchDir + jitter).Unit

		local rayOrigin = planetCenter + dir * (planetRadius + SURFACE_RAYCAST_HEIGHT)
		local rayDirection = -dir * (SURFACE_RAYCAST_HEIGHT * 2)

		local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
		if not result then continue end

		local surfacePos = result.Position
		local surfaceNormal = result.Normal

		local distFromCenter = (surfacePos - planetCenter).Magnitude
		if distFromCenter > planetRadius * 1.15 or distFromCenter < planetRadius * 0.5 then
			continue
		end

		local scale = SCALE_MIN + math.random() * (SCALE_MAX - SCALE_MIN)

		local crystal = self._prefab:Clone()

		self:_makeDecoration(crystal)

		local alignCF = self:_alignToNormal(surfacePos, surfaceNormal)

		if crystal:IsA("Model") then
			local primaryPart = crystal.PrimaryPart
			if not primaryPart then
				crystal:Destroy()
				continue
			end

			self:_scaleModel(crystal, scale)
			crystal:PivotTo(alignCF)
		elseif crystal:IsA("BasePart") then
			crystal.Size = crystal.Size * scale
			crystal.CFrame = alignCF
		end

		crystal.Parent = self._crystalFolder
	end
end

function GraviBowCrystalService:_makeDecoration(instance)
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
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = true
		part.CanTouch = false
	end
end

function GraviBowCrystalService:_rotateFromTo(from, to)
	local f = from.Unit
	local t = to.Unit
	local dot = math.clamp(f:Dot(t), -1, 1)

	if dot > 0.9999 then
		return CFrame.identity
	end

	if dot < -0.9999 then
		local axis = Vector3.new(1, 0, 0):Cross(f)
		if axis.Magnitude < 0.001 then
			axis = Vector3.new(0, 1, 0):Cross(f)
		end
		return CFrame.fromAxisAngle(axis.Unit, math.pi)
	end

	local axis = f:Cross(t).Unit
	local angle = math.acos(dot)
	return CFrame.fromAxisAngle(axis, angle)
end

function GraviBowCrystalService:_alignToNormal(position, normal)
	local rotation = self:_rotateFromTo(self._prefabUpVector, normal.Unit)
	return CFrame.new(position) * rotation * self._prefabRotation
end

function GraviBowCrystalService:_scaleModel(model, scale)
	local primaryPart = model.PrimaryPart
	if not primaryPart then return end

	local pivotCF = model:GetPivot()

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			local offset = pivotCF:ToObjectSpace(desc.CFrame)
			desc.Size = desc.Size * scale
			desc.CFrame = pivotCF * CFrame.new(offset.Position * scale) * (offset - offset.Position)
		end
	end
end

function GraviBowCrystalService:_randomUnitSphere()
	local theta = math.random() * math.pi * 2
	local phi = math.acos(2 * math.random() - 1)
	return Vector3.new(
		math.sin(phi) * math.cos(theta),
		math.cos(phi),
		math.sin(phi) * math.sin(theta)
	).Unit
end

function GraviBowCrystalService:_randomTangentOffset(normal, maxAngle)
	local worldRef = Vector3.new(0, 1, 0)
	if math.abs(normal:Dot(worldRef)) > 0.99 then
		worldRef = Vector3.new(1, 0, 0)
	end

	local tangent1 = normal:Cross(worldRef).Unit
	local tangent2 = normal:Cross(tangent1).Unit

	local angle = math.random() * math.pi * 2
	local mag = math.random() * maxAngle

	return (tangent1 * math.cos(angle) + tangent2 * math.sin(angle)) * mag
end

return GraviBowCrystalService
