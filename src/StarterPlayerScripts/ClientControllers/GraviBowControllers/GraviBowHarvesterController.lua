local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local GRAVGUN_HOLD_DISTANCE = 8
local GRAVGUN_LERP_SPEED = 0.3
local SNAP_HOLD_DISTANCE = 12
local SNAP_SURFACE_RAYCAST = 80

local HARVESTER_GRAVITY = 40
local HARVESTER_MAX_SPEED = 16
local HARVESTER_IMPULSE = 14
local HARVESTER_IMPULSE_INTERVAL = 0.25
local HARVESTER_ALIGN_RESPONSIVENESS = 15
local HARVESTER_ALIGN_TORQUE = 50000

local GraviBowHarvesterController = Knit.CreateController({
	Name = "GraviBowHarvesterController",

	_trove = nil,
	_heldObject = nil,
	_heldObjectConn = nil,
	_activeHarvesters = {},
	_harvesterSteppedConn = nil,
	_harvesterBeamSounds = {},
	_snapItem = nil,
	_snapItemConn = nil,
	_snapRenderConn = nil,
	_snapInputConn = nil,
})

function GraviBowHarvesterController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowHarvesterController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._soundController = Knit.GetController("GraviBowSoundController")
	self._harvesterService = Knit.GetService("GraviBowHarvesterService")
	self._oreService = Knit.GetService("GraviBowOreService")

	self._oreService.ItemPurchased:Connect(function(itemName, harvesterModel)
		self:_onItemPurchased(itemName, harvesterModel)
	end)

	self._harvesterService.HarvesterTarget:Connect(function(harvesterObj, targetPos)
		self:_onHarvesterTarget(harvesterObj, targetPos)
	end)

	self._harvesterService.HarvesterMining:Connect(function(harvesterObj, isMining)
		self:_onHarvesterMining(harvesterObj, isMining)
	end)

	self:_setupHarvesterPhysicsLoop()
end

function GraviBowHarvesterController:IsHolding()
	return self._heldObject ~= nil and self._heldObject.Parent ~= nil
end

function GraviBowHarvesterController:DropHeldObject()
	self:_dropHeldObject()
end

function GraviBowHarvesterController:UpdateHeldObject(cam)
	self:_updateHeldObject(cam)
end

function GraviBowHarvesterController:_onItemPurchased(itemName, model)
	if not model then return end

	if itemName == "Harvester" then
		self:_holdServerObject(model)
	else
		self:_startSnapPlacement(model)
	end
end

function GraviBowHarvesterController:_holdServerObject(obj)
	if self._heldObject then
		self:_dropHeldObject()
	end

	self._heldObject = obj

	self._heldObjectConn = obj.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			self._heldObject = nil
			if self._heldObjectConn then
				self._heldObjectConn:Disconnect()
				self._heldObjectConn = nil
			end
		end
	end)

	print("[GraviBowHarvesterController] Now carrying server-spawned object:", obj.Name)
end

function GraviBowHarvesterController:_updateHeldObject(cam)
	if not self._heldObject or not self._heldObject.Parent then
		self._heldObject = nil
		return
	end

	local targetPos = cam.CFrame:PointToWorldSpace(Vector3.new(0, 0, -GRAVGUN_HOLD_DISTANCE))
	local lookDir = cam.CFrame.LookVector
	local upDir = cam.CFrame.UpVector
	local targetCF = CFrame.lookAt(targetPos, targetPos + lookDir, upDir)

	if self._heldObject:IsA("Model") then
		local currentCF = self._heldObject:GetPivot()
		self._heldObject:PivotTo(currentCF:Lerp(targetCF, GRAVGUN_LERP_SPEED))
	elseif self._heldObject:IsA("BasePart") then
		self._heldObject.CFrame = self._heldObject.CFrame:Lerp(targetCF, GRAVGUN_LERP_SPEED)
	end
end

function GraviBowHarvesterController:_dropHeldObject()
	if not self._heldObject then return end

	local obj = self._heldObject
	self._heldObject = nil

	if self._heldObjectConn then
		self._heldObjectConn:Disconnect()
		self._heldObjectConn = nil
	end

	if not obj.Parent then return end

	local rootPart = nil
	if obj:IsA("Model") then
		rootPart = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
	elseif obj:IsA("BasePart") then
		rootPart = obj
	end

	local dropPos = rootPart and rootPart.Position or Vector3.zero
	local lookDir = rootPart and rootPart.CFrame.LookVector or Vector3.new(0, 0, -1)

	self._harvesterService.DropHarvester:Fire(obj, dropPos, lookDir)

	print("[GraviBowHarvesterController] Dropped held object (sent to server)")
end

function GraviBowHarvesterController:_onHarvesterTarget(harvesterObj, targetPos)
	if not harvesterObj or not harvesterObj.Parent then
		print("[HarvesterClient] Target signal received but obj invalid")
		return
	end

	local entry = self._activeHarvesters[harvesterObj]
	if not entry then
		print("[HarvesterClient] First target signal - creating physics for", harvesterObj.Name, "target:", targetPos)
		local rootPart
		if harvesterObj:IsA("Model") then
			rootPart = harvesterObj.PrimaryPart or harvesterObj:FindFirstChildWhichIsA("BasePart")
		elseif harvesterObj:IsA("BasePart") then
			rootPart = harvesterObj
		end
		if not rootPart then
			print("[HarvesterClient] No rootPart found!")
			return
		end

		local attachment = Instance.new("Attachment")
		attachment.Name = "GravityAttachment"
		attachment.Parent = rootPart

		local gravityForce = Instance.new("VectorForce")
		gravityForce.Name = "PlanetGravity"
		gravityForce.Attachment0 = attachment
		gravityForce.RelativeTo = Enum.ActuatorRelativeTo.World
		gravityForce.ApplyAtCenterOfMass = true
		gravityForce.Force = Vector3.zero
		gravityForce.Parent = rootPart

		local alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "PlanetAlign"
		alignOrientation.Attachment0 = attachment
		alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.MaxTorque = HARVESTER_ALIGN_TORQUE
		alignOrientation.Responsiveness = HARVESTER_ALIGN_RESPONSIVENESS
		alignOrientation.Parent = rootPart

		local mass = 0
		if harvesterObj:IsA("BasePart") then
			mass = harvesterObj:GetMass()
		else
			for _, desc in ipairs(harvesterObj:GetDescendants()) do
				if desc:IsA("BasePart") then mass = mass + desc:GetMass() end
			end
		end

		local groundRayParams = RaycastParams.new()
		groundRayParams.FilterType = Enum.RaycastFilterType.Exclude
		local filterList = { harvesterObj }
		local char = LocalPlayer.Character
		if char then table.insert(filterList, char) end
		local gzFolder = Workspace:FindFirstChild("GravityZones")
		if gzFolder then table.insert(filterList, gzFolder) end
		local cpFolder = Workspace:FindFirstChild("CrystalPatches")
		if cpFolder then table.insert(filterList, cpFolder) end
		groundRayParams.FilterDescendantsInstances = filterList

		entry = {
			obj = harvesterObj,
			rootPart = rootPart,
			gravityForce = gravityForce,
			alignOrientation = alignOrientation,
			mass = mass,
			targetPos = targetPos,
			groundRayParams = groundRayParams,
			lastImpulseTime = 0,
		}
		self._activeHarvesters[harvesterObj] = entry
		local canApply = pcall(function() rootPart:ApplyImpulse(Vector3.zero) end)
		print("[HarvesterClient] Registered harvester, mass:", mass, "anchored:", rootPart.Anchored, "canApplyImpulse:", canApply)

		harvesterObj.AncestryChanged:Connect(function(_, newParent)
			if not newParent then
				self:_cleanupHarvester(harvesterObj)
			end
		end)
	else
		entry.targetPos = targetPos
	end

	if not targetPos then
		self._harvesterService.HarvesterReady:Fire(harvesterObj)
	end
end

function GraviBowHarvesterController:_cleanupHarvester(harvesterObj)
	local entry = self._activeHarvesters[harvesterObj]
	if not entry then return end
	if entry.gravityForce and entry.gravityForce.Parent then entry.gravityForce:Destroy() end
	if entry.alignOrientation and entry.alignOrientation.Parent then entry.alignOrientation:Destroy() end
	if entry.beamSound then
		entry.beamSound:Stop()
		entry.beamSound:Destroy()
		entry.beamSound = nil
	end
	self._activeHarvesters[harvesterObj] = nil
end

function GraviBowHarvesterController:_onHarvesterMining(harvesterObj, isMining)
	local entry = self._activeHarvesters[harvesterObj]

	if isMining then
		local rootPart
		if entry then
			rootPart = entry.rootPart
		elseif harvesterObj:IsA("Model") then
			rootPart = harvesterObj.PrimaryPart or harvesterObj:FindFirstChildWhichIsA("BasePart")
		elseif harvesterObj:IsA("BasePart") then
			rootPart = harvesterObj
		end

		if rootPart then
			local sound = self._soundController:PlayNamedLoopOnPart("HarvestBeam", "harvester", rootPart)
			if entry then
				entry.beamSound = sound
			else
				self._harvesterBeamSounds[harvesterObj] = sound
			end
		end
	else
		if entry and entry.beamSound then
			entry.beamSound:Stop()
			entry.beamSound:Destroy()
			entry.beamSound = nil
		elseif self._harvesterBeamSounds[harvesterObj] then
			self._harvesterBeamSounds[harvesterObj]:Stop()
			self._harvesterBeamSounds[harvesterObj]:Destroy()
			self._harvesterBeamSounds[harvesterObj] = nil
		end

		if entry then
			self._soundController:PlayOnPart("HarvestCollected", entry.rootPart)
		end
	end
end

function GraviBowHarvesterController:_setupHarvesterPhysicsLoop()
	self._harvesterSteppedConn = RunService.Stepped:Connect(function(_, dt)
		local now = os.clock()

		for harvesterObj, entry in pairs(self._activeHarvesters) do
			local rootPart = entry.rootPart
			if not rootPart or not rootPart.Parent then
				self:_cleanupHarvester(harvesterObj)
				continue
			end

			local pos = rootPart.Position
			local planetCenter = self._gravityController:GetNearestPlanetCenter(pos)
			local toCenter = planetCenter - pos
			if toCenter.Magnitude < 0.01 then continue end

			local gravDir = toCenter.Unit
			entry.gravityForce.Force = gravDir * HARVESTER_GRAVITY * entry.mass

			local rayResult = Workspace:Raycast(pos, gravDir * 20, entry.groundRayParams)
			local surfaceUp = -gravDir
			if rayResult then
				surfaceUp = rayResult.Normal
			end

			local fwd = rootPart.CFrame.LookVector
			if entry.targetPos then
				local toTarget = entry.targetPos - pos
				local tangent = toTarget - surfaceUp * toTarget:Dot(surfaceUp)
				if tangent.Magnitude > 0.01 then
					fwd = tangent.Unit
				end
			end

			local tangentFwd = fwd - surfaceUp * fwd:Dot(surfaceUp)
			local lookDir
			if tangentFwd.Magnitude > 0.01 then
				lookDir = tangentFwd.Unit
			else
				lookDir = surfaceUp:Cross(Vector3.new(0, 0, 1))
				if lookDir.Magnitude < 0.01 then lookDir = surfaceUp:Cross(Vector3.new(1, 0, 0)) end
				lookDir = lookDir.Unit
			end

			entry.alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, lookDir, surfaceUp)

			if entry.targetPos and (now - entry.lastImpulseTime) >= HARVESTER_IMPULSE_INTERVAL then
				local grounded = false
				if rayResult and rayResult.Distance < 6 then
					grounded = true
				end

				if grounded then
					local toTarget = entry.targetPos - pos
					local tangent = toTarget - surfaceUp * toTarget:Dot(surfaceUp)
					if tangent.Magnitude > 0.5 then
						tangent = tangent.Unit
						local currentSpeed = rootPart.AssemblyLinearVelocity:Dot(tangent)
						if currentSpeed < HARVESTER_MAX_SPEED then
							rootPart:ApplyImpulse(tangent * HARVESTER_IMPULSE * entry.mass)
							print("[HarvesterClient] Impulse applied, tangentSpeed:", string.format("%.1f", currentSpeed), "totalVel:", string.format("%.1f", rootPart.AssemblyLinearVelocity.Magnitude), "dist:", string.format("%.1f", toTarget.Magnitude))
						end
					end
					entry.lastImpulseTime = now
				else
					if not entry._lastGroundWarn or (now - entry._lastGroundWarn) > 2 then
						print("[HarvesterClient] Not grounded, rayDist:", rayResult and string.format("%.1f", rayResult.Distance) or "miss", "gravForce:", string.format("%.1f", entry.gravityForce.Force.Magnitude))
						entry._lastGroundWarn = now
					end
				end
			end
		end
	end)

	self._trove:Add(self._harvesterSteppedConn, "Disconnect")
end

function GraviBowHarvesterController:_startSnapPlacement(model)
	self:_cancelSnapPlacement()

	self._snapItem = model

	self._snapItemConn = model.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			self:_cancelSnapPlacement()
		end
	end)

	local cam = Workspace.CurrentCamera
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = { model }
	local char = LocalPlayer.Character
	if char then table.insert(filterList, char) end
	local gzFolder = Workspace:FindFirstChild("GravityZones")
	if gzFolder then table.insert(filterList, gzFolder) end
	local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
	if tpFolder then table.insert(filterList, tpFolder) end
	local cpFolder = Workspace:FindFirstChild("CrystalPatches")
	if cpFolder then table.insert(filterList, cpFolder) end
	rayParams.FilterDescendantsInstances = filterList

	self._snapRenderConn = RunService.RenderStepped:Connect(function()
		if not self._snapItem or not self._snapItem.Parent then
			self:_cancelSnapPlacement()
			return
		end

		local origin = cam.CFrame.Position
		local dir = cam.CFrame.LookVector * SNAP_SURFACE_RAYCAST

		local result = Workspace:Raycast(origin, dir, rayParams)
		local targetCF
		if result then
			local normal = result.Normal
			local up = normal.Unit
			local fwd = cam.CFrame.LookVector
			local tangent = fwd - up * fwd:Dot(up)
			if tangent.Magnitude < 0.01 then
				tangent = cam.CFrame.RightVector
			end
			tangent = tangent.Unit
			targetCF = CFrame.lookAt(result.Position, result.Position + tangent, up)
		else
			targetCF = cam.CFrame * CFrame.new(0, 0, -SNAP_HOLD_DISTANCE)
		end

		if self._snapItem:IsA("Model") then
			self._snapItem:PivotTo(targetCF)
		elseif self._snapItem:IsA("BasePart") then
			self._snapItem.CFrame = targetCF
		end
	end)

	self._snapInputConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if not self._snapItem then return end

		local isPlace = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		local isCancel = input.KeyCode == Enum.KeyCode.Q
			or input.UserInputType == Enum.UserInputType.MouseButton2

		if isPlace then
			self:_confirmSnapPlacement()
		elseif isCancel then
			self:_refundSnapPlacement()
		end
	end)

	print("[GraviBowHarvesterController] Snap placement started for:", model.Name)
end

function GraviBowHarvesterController:_confirmSnapPlacement()
	local model = self._snapItem
	if not model or not model.Parent then
		self:_cancelSnapPlacement()
		return
	end

	local cframe
	if model:IsA("Model") then
		cframe = model:GetPivot()
	elseif model:IsA("BasePart") then
		cframe = model.CFrame
	end

	self._oreService.PlaceSnapItem:Fire(model, cframe)
	print("[GraviBowHarvesterController] Placed snap item:", model.Name)
	self:_cleanupSnapConnections()
end

function GraviBowHarvesterController:_refundSnapPlacement()
	local model = self._snapItem
	if model and model.Parent then
		model:Destroy()
	end
	self:_cleanupSnapConnections()
	print("[GraviBowHarvesterController] Cancelled snap placement")
end

function GraviBowHarvesterController:_cancelSnapPlacement()
	self:_cleanupSnapConnections()
end

function GraviBowHarvesterController:_cleanupSnapConnections()
	self._snapItem = nil
	if self._snapItemConn then
		self._snapItemConn:Disconnect()
		self._snapItemConn = nil
	end
	if self._snapRenderConn then
		self._snapRenderConn:Disconnect()
		self._snapRenderConn = nil
	end
	if self._snapInputConn then
		self._snapInputConn:Disconnect()
		self._snapInputConn = nil
	end
end

function GraviBowHarvesterController:IsSnapping()
	return self._snapItem ~= nil and self._snapItem.Parent ~= nil
end

return GraviBowHarvesterController
