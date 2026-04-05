local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local ItemRegistry = require(ReplicatedStorage.Source.GraviBowItemRegistry)

local LocalPlayer = Players.LocalPlayer

local SURFACE_RAY_DISTANCE = 200
local FALLBACK_HOLD_DISTANCE = 15
local ROTATION_STEP = math.rad(15)
local PLACEMENT_LERP_SPEED = 0.35

local snapItems = {}
for _, item in ipairs(ItemRegistry) do
	if item.placement == "snap" then
		snapItems[item.name] = true
	end
end

local GraviBowBuildController = Knit.CreateController({
	Name = "GraviBowBuildController",

	_trove = nil,
	_placingModel = nil,
	_placingConn = nil,
	_rotationOffset = 0,
	_rayParams = nil,
})

function GraviBowBuildController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowBuildController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._oreService = Knit.GetService("GraviBowOreService")
	self._buildService = Knit.GetService("GraviBowBuildService")

	self._oreService.ItemPurchased:Connect(function(itemName, model)
		if snapItems[itemName] and model then
			self:_enterPlacementMode(model)
		end
	end)

	self._buildService.BuildablePlaced:Connect(function()
		self:_exitPlacementMode()
	end)

	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
end

function GraviBowBuildController:IsPlacing()
	return self._placingModel ~= nil
end

function GraviBowBuildController:ConfirmPlacement()
	if not self._placingModel or not self._placingModel.Parent then
		self:_exitPlacementMode()
		return
	end

	local cf
	if self._placingModel:IsA("Model") then
		cf = self._placingModel:GetPivot()
	else
		cf = self._placingModel.CFrame
	end

	self._buildService.PlaceBuildable:Fire(self._placingModel, cf)
	print("[GraviBowBuildController] Confirmed placement")
end

function GraviBowBuildController:CancelPlacement()
	if not self._placingModel then return end

	self._buildService.CancelBuildable:Fire(self._placingModel)
	self:_exitPlacementMode()
	print("[GraviBowBuildController] Cancelled placement")
end

function GraviBowBuildController:Rotate(direction)
	self._rotationOffset = self._rotationOffset + (direction * ROTATION_STEP)
end

function GraviBowBuildController:_enterPlacementMode(model)
	if self._placingModel then
		self:CancelPlacement()
	end

	self._placingModel = model
	self._rotationOffset = 0

	self:_rebuildRayFilter()

	self._placingConn = RunService.RenderStepped:Connect(function()
		self:_updatePlacement()
	end)
	self._trove:Add(self._placingConn, "Disconnect")

	print("[GraviBowBuildController] Entered placement mode for", model.Name)
end

function GraviBowBuildController:_exitPlacementMode()
	if self._placingConn then
		self._placingConn:Disconnect()
		self._placingConn = nil
	end
	self._placingModel = nil
	self._rotationOffset = 0
end

function GraviBowBuildController:_rebuildRayFilter()
	local filterList = {}
	local character = LocalPlayer.Character
	if character then table.insert(filterList, character) end
	if self._placingModel then table.insert(filterList, self._placingModel) end
	local gzFolder = Workspace:FindFirstChild("GravityZones")
	if gzFolder then table.insert(filterList, gzFolder) end
	self._rayParams.FilterDescendantsInstances = filterList
end

function GraviBowBuildController:_updatePlacement()
	local model = self._placingModel
	if not model or not model.Parent then
		self:_exitPlacementMode()
		return
	end

	local cam = Workspace.CurrentCamera
	if not cam then return end

	local origin = cam.CFrame.Position
	local direction = cam.CFrame.LookVector * SURFACE_RAY_DISTANCE

	local result = Workspace:Raycast(origin, direction, self._rayParams)

	local targetCF
	if result then
		local hitPos = result.Position
		local surfaceNormal = result.Normal

		local baseForward = cam.CFrame.LookVector
		local projected = baseForward - surfaceNormal * baseForward:Dot(surfaceNormal)
		if projected.Magnitude < 0.01 then
			projected = surfaceNormal:Cross(Vector3.new(0, 0, 1))
			if projected.Magnitude < 0.01 then
				projected = surfaceNormal:Cross(Vector3.new(1, 0, 0))
			end
		end
		projected = projected.Unit

		local rotatedForward = CFrame.fromAxisAngle(surfaceNormal, self._rotationOffset):VectorToWorldSpace(projected)

		local placeCF = CFrame.lookAt(hitPos, hitPos + rotatedForward, surfaceNormal)

		local offset = self:_getBaseOffset(model, placeCF)
		targetCF = placeCF + surfaceNormal * offset
	else
		local fallbackPos = cam.CFrame:PointToWorldSpace(Vector3.new(0, 0, -FALLBACK_HOLD_DISTANCE))
		local planetCenter = self._gravityController:GetNearestPlanetCenter(fallbackPos)
		local upDir = (fallbackPos - planetCenter)
		upDir = upDir.Magnitude > 0.01 and upDir.Unit or Vector3.new(0, 1, 0)

		local lookDir = cam.CFrame.LookVector
		local tangent = lookDir - upDir * lookDir:Dot(upDir)
		if tangent.Magnitude < 0.01 then
			tangent = upDir:Cross(Vector3.new(0, 0, 1))
		end
		tangent = tangent.Unit

		local rotated = CFrame.fromAxisAngle(upDir, self._rotationOffset):VectorToWorldSpace(tangent)
		targetCF = CFrame.lookAt(fallbackPos, fallbackPos + rotated, upDir)
	end

	local currentCF
	if model:IsA("Model") then
		currentCF = model:GetPivot()
	else
		currentCF = model.CFrame
	end

	local smoothed = currentCF:Lerp(targetCF, PLACEMENT_LERP_SPEED)

	if model:IsA("Model") then
		model:PivotTo(smoothed)
	else
		model.CFrame = smoothed
	end
end

function GraviBowBuildController:_getBaseOffset(model, placeCF)
	local upAxis = placeCF.UpVector
	local parts = {}
	if model:IsA("BasePart") then
		table.insert(parts, model)
	end
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end

	local maxBelow = 0
	local pivotPos = placeCF.Position
	for _, part in ipairs(parts) do
		local corners = self:_getPartCorners(part)
		for _, corner in ipairs(corners) do
			local displacement = (corner - pivotPos):Dot(upAxis)
			if displacement < -maxBelow then
				maxBelow = -displacement
			end
		end
	end

	return maxBelow
end

function GraviBowBuildController:_getPartCorners(part)
	local cf = part.CFrame
	local half = part.Size * 0.5
	local corners = {}
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				table.insert(corners, cf:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z)))
			end
		end
	end
	return corners
end

return GraviBowBuildController
