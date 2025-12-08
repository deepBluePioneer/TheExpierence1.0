--[[
	ShootingController (Gravity Gun)
	Half-Life style gravity gun - pick up and launch objects with "shape" tag
]]

local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CONFIG = require(script.Parent.LocomotionConfig)

-- Gravity Gun Config
local GRAVITY_GUN = {
	GrabRange = 30,           -- Max distance to grab objects
	HoldDistance = 5,         -- Distance object floats in front of cannon
	PullSpeed = 100,          -- Speed objects get pulled towards you
	LaunchForce = 150,        -- Force applied when launching
	HoldStiffness = 200,      -- How rigidly object follows (higher = snappier)
	MaxHoldMass = 0,          -- Max mass we can pick up (0 = unlimited)
}

local ShootingController = Knit.CreateController {
	Name = "ShootingController",
	
	-- State
	_character = nil,
	_heldObject = nil,
	_heldObjectDistance = nil,  -- Dynamic hold distance based on object size
	_holdAttachment = nil,
	_alignPosition = nil,
	_alignOrientation = nil,
	_isPulling = false,
	_pullTarget = nil,
	
	-- Callbacks
	_onRecoilUpdate = nil,
	_getCannonTipPosition = nil,
	_getCannonParts = nil,
	
	-- Connections
	_connections = {},
}

-- === SETUP ===

function ShootingController:SetupShooting(character, getCannonTipPosition, getCannonParts, onRecoilUpdate)
	self._character = character
	self._getCannonTipPosition = getCannonTipPosition
	self._getCannonParts = getCannonParts
	self._onRecoilUpdate = onRecoilUpdate
	
	-- Primary fire (left click) - Grab or Launch
	local primaryConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self._heldObject then
				self:LaunchObject()
			else
				self:TryGrabObject()
			end
		end
	end)
	table.insert(self._connections, primaryConn)
	
	-- Secondary fire (right click) - Drop gently
	local secondaryConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self._heldObject then
				self:DropObject()
			end
		end
	end)
	table.insert(self._connections, secondaryConn)
	
	-- Update held object position
	local updateConn = RunService.Heartbeat:Connect(function(dt)
		self:UpdateHeldObject(dt)
	end)
	table.insert(self._connections, updateConn)
end

-- === GRABBING ===

function ShootingController:TryGrabObject()
	print("[GravityGun] Fire button pressed - attempting grab")
	
	-- Raycast from camera center
	local camera = Workspace.CurrentCamera
	if not camera then 
		print("[GravityGun] No camera found")
		return 
	end
	
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector
	
	print("[GravityGun] Raycast from:", origin, "direction:", direction)
	
	-- First, try direct raycast
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {self._character}
	
	local result = Workspace:Raycast(origin, direction * GRAVITY_GUN.GrabRange, rayParams)
	
	if result and result.Instance then
		local part = result.Instance
		local hasTag = CollectionService:HasTag(part, "shape")
		print("[GravityGun] Direct hit:", part.Name, "| Has 'shape' tag:", hasTag)
		
		-- Check if it has "shape" tag
		if hasTag then
			-- Check mass limit
			if GRAVITY_GUN.MaxHoldMass > 0 and part:GetMass() > GRAVITY_GUN.MaxHoldMass then
				print("[GravityGun] Object too heavy:", part:GetMass())
				self:PlayRejectEffect()
				return
			end
			
			print("[GravityGun] Grabbing via direct hit:", part.Name)
			self:GrabObject(part)
			return
		end
	else
		print("[GravityGun] Raycast missed - no hit")
	end
	
	-- Direct hit wasn't a shape (or missed), try sphere overlap method
	print("[GravityGun] Searching for nearest shape...")
	local nearestShape = self:FindNearestShape(origin, direction)
	if nearestShape then
		print("[GravityGun] Found nearest shape:", nearestShape.Name, "at distance:", (nearestShape.Position - origin).Magnitude)
		
		-- Check mass limit
		if GRAVITY_GUN.MaxHoldMass > 0 and nearestShape:GetMass() > GRAVITY_GUN.MaxHoldMass then
			print("[GravityGun] Object too heavy:", nearestShape:GetMass())
			self:PlayRejectEffect()
			return
		end
		
		print("[GravityGun] Grabbing via search:", nearestShape.Name)
		self:GrabObject(nearestShape)
	else
		print("[GravityGun] No shapes found in range")
	end
end

function ShootingController:FindNearestShape(origin, direction)
	local shapes = CollectionService:GetTagged("shape")
	local bestShape = nil
	local bestScore = math.huge
	
	for _, shape in ipairs(shapes) do
		if shape:IsA("BasePart") and shape.Parent then
			local toShape = shape.Position - origin
			local distance = toShape.Magnitude
			
			if distance <= GRAVITY_GUN.GrabRange then
				-- Calculate how close the aim ray passes to the shape center
				local alignment = toShape.Unit:Dot(direction)
				
				-- Must be in front of us (alignment > 0)
				if alignment > 0 then
					-- Calculate perpendicular distance from ray to shape center
					local projectedPoint = origin + direction * (distance * alignment)
					local perpendicularDist = (shape.Position - projectedPoint).Magnitude
					
					-- Get shape radius (half of largest dimension)
					local shapeRadius = math.max(shape.Size.X, shape.Size.Y, shape.Size.Z) / 2
					
					-- Score: prefer shapes closer to the aim ray and closer to us
					-- Add shape radius as tolerance (easier to pick up larger objects)
					local effectiveDist = math.max(0, perpendicularDist - shapeRadius)
					
					-- Only consider if within reasonable cone (about 5 studs off-center at max range)
					if effectiveDist < 5 then
						local score = effectiveDist * 2 + distance * 0.1
						if score < bestScore then
							bestScore = score
							bestShape = shape
						end
					end
				end
			end
		end
	end
	
	return bestShape
end

function ShootingController:CalculateBoundingRadius(part)
	-- Get the size of the part
	local size = part.Size
	
	-- Calculate the bounding sphere radius (half diagonal of bounding box)
	-- This ensures the entire object clears the player
	local boundingRadius = math.sqrt(size.X^2 + size.Y^2 + size.Z^2) / 2
	
	return boundingRadius
end

function ShootingController:GrabObject(part)
	if self._heldObject then
		self:DropObject()
	end
	
	self._heldObject = part
	
	-- Calculate dynamic hold distance based on object size
	local boundingRadius = self:CalculateBoundingRadius(part)
	local minClearance = 2  -- Minimum distance from camera to nearest edge of object
	self._heldObjectDistance = boundingRadius + minClearance + GRAVITY_GUN.HoldDistance
	
	print("[GravityGun] Object size:", part.Size, "| Bounding radius:", boundingRadius, "| Hold distance:", self._heldObjectDistance)
	
	-- Create attachment on object
	self._holdAttachment = Instance.new("Attachment")
	self._holdAttachment.Name = "GravityGunHold"
	self._holdAttachment.Parent = part
	
	-- Create AlignPosition to hold object in place (snappy settings)
	self._alignPosition = Instance.new("AlignPosition")
	self._alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	self._alignPosition.Attachment0 = self._holdAttachment
	self._alignPosition.MaxForce = math.huge
	self._alignPosition.MaxVelocity = math.huge
	self._alignPosition.Responsiveness = GRAVITY_GUN.HoldStiffness
	self._alignPosition.Parent = part
	
	-- Create AlignOrientation to stabilize rotation (snappy settings)
	self._alignOrientation = Instance.new("AlignOrientation")
	self._alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	self._alignOrientation.Attachment0 = self._holdAttachment
	self._alignOrientation.MaxTorque = math.huge
	self._alignOrientation.Responsiveness = GRAVITY_GUN.HoldStiffness
	self._alignOrientation.Parent = part
	
	-- Visual feedback - make object glow
	self._originalColor = part.Color
	self._originalMaterial = part.Material
	
	-- Play grab effect
	self:PlayGrabEffect()
end

-- === HOLDING ===

function ShootingController:UpdateHeldObject(dt)
	if not self._heldObject or not self._alignPosition then return end
	
	-- Get camera for hold position
	local camera = Workspace.CurrentCamera
	if not camera then return end
	
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector
	
	-- Calculate hold position using dynamic distance based on object size
	local holdDistance = self._heldObjectDistance or GRAVITY_GUN.HoldDistance
	local holdPos = origin + direction * holdDistance
	
	-- Update AlignPosition target
	self._alignPosition.Position = holdPos
	
	-- Update AlignOrientation to face forward
	local camera = Workspace.CurrentCamera
	if camera and self._alignOrientation then
		self._alignOrientation.CFrame = camera.CFrame
	end
end

-- === LAUNCHING ===

function ShootingController:LaunchObject()
	if not self._heldObject then return end
	
	-- Get launch direction from camera
	local camera = Workspace.CurrentCamera
	if not camera then return end
	
	local direction = camera.CFrame.LookVector
	local part = self._heldObject
	local mass = part:GetMass()
	
	-- Clean up constraints first
	self:CleanupHoldConstraints()
	
	-- Apply launch impulse
	local impulse = direction * GRAVITY_GUN.LaunchForce * mass
	part:ApplyImpulse(impulse)
	
	-- Play launch effect
	self:PlayLaunchEffect()
	
	self._heldObject = nil
	self._heldObjectDistance = nil
end

function ShootingController:DropObject()
	if not self._heldObject then return end
	
	-- Clean up constraints
	self:CleanupHoldConstraints()
	
	-- Play drop sound/effect
	self:PlayDropEffect()
	
	self._heldObject = nil
	self._heldObjectDistance = nil
end

function ShootingController:CleanupHoldConstraints()
	if self._alignPosition then
		self._alignPosition:Destroy()
		self._alignPosition = nil
	end
	
	if self._alignOrientation then
		self._alignOrientation:Destroy()
		self._alignOrientation = nil
	end
	
	if self._holdAttachment then
		self._holdAttachment:Destroy()
		self._holdAttachment = nil
	end
end

-- === EFFECTS ===

function ShootingController:PlayGrabEffect()
	if not self._getCannonParts then return end
	local parts = self._getCannonParts()
	
	-- Flash energy core
	if parts[7] then
		local core = parts[7]
		local originalSize = core.Size
		core.Size = originalSize * 2
		core.Color = Color3.fromRGB(0, 255, 150)
		
		task.delay(0.15, function()
			if core and core.Parent then
				core.Size = originalSize
				core.Color = CONFIG.CannonGlowColor
			end
		end)
	end
	
	-- Flash barrel tip
	if parts[6] then
		local tip = parts[6]
		tip.Color = Color3.fromRGB(0, 255, 150)
		
		task.delay(0.15, function()
			if tip and tip.Parent then
				tip.Color = CONFIG.CannonGlowColor
			end
		end)
	end
end

function ShootingController:PlayLaunchEffect()
	if self._onRecoilUpdate then
		self._onRecoilUpdate(1)
		task.delay(0.15, function()
			if self._onRecoilUpdate then
				self._onRecoilUpdate(0)
			end
		end)
	end
	
	if not self._getCannonParts then return end
	local parts = self._getCannonParts()
	
	-- Flash effects
	if parts[6] then
		local tip = parts[6]
		local originalColor = tip.Color
		tip.Color = Color3.new(1, 1, 1)
		tip.Size = tip.Size * 1.5
		
		task.delay(0.1, function()
			if tip and tip.Parent then
				tip.Color = originalColor
				tip.Size = Vector3.new(0.1, CONFIG.CannonTipWidth * 0.8, CONFIG.CannonTipWidth * 0.8)
			end
		end)
	end
	
	if parts[7] then
		local core = parts[7]
		local originalSize = core.Size
		core.Size = originalSize * 3
		
		task.delay(0.15, function()
			if core and core.Parent then
				core.Size = originalSize
			end
		end)
	end
end

function ShootingController:PlayDropEffect()
	if not self._getCannonParts then return end
	local parts = self._getCannonParts()
	
	-- Dim the core briefly
	if parts[7] then
		local core = parts[7]
		local originalColor = core.Color
		core.Color = Color3.fromRGB(100, 100, 100)
		
		task.delay(0.2, function()
			if core and core.Parent then
				core.Color = originalColor
			end
		end)
	end
end

function ShootingController:PlayRejectEffect()
	if not self._getCannonParts then return end
	local parts = self._getCannonParts()
	
	-- Flash red to indicate can't pick up
	if parts[7] then
		local core = parts[7]
		local originalColor = core.Color
		core.Color = Color3.fromRGB(255, 0, 0)
		
		task.delay(0.2, function()
			if core and core.Parent then
				core.Color = originalColor
			end
		end)
	end
end

-- === CLEANUP ===

function ShootingController:Cleanup()
	-- Drop held object
	if self._heldObject then
		self:DropObject()
	end
	
	-- Disconnect all connections
	for _, conn in ipairs(self._connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	self._connections = {}
	
	self._character = nil
	self._getCannonTipPosition = nil
	self._getCannonParts = nil
	self._onRecoilUpdate = nil
end

-- === PUBLIC API ===

function ShootingController:IsHoldingObject()
	return self._heldObject ~= nil
end

function ShootingController:GetHeldObject()
	return self._heldObject
end

function ShootingController:ForceDropObject()
	if self._heldObject then
		self:DropObject()
	end
end

-- === KNIT LIFECYCLE ===

function ShootingController:KnitInit()
end

function ShootingController:KnitStart()
	-- This controller is managed by ProceduralLocomotionController
end

return ShootingController
