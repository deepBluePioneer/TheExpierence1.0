-- PlayerRideController
-- Client-side controller to handle jump disabling for the ride
-- Movement is handled server-side for reliable anchored part updates
-- Also handles making player parts transparent during ride

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local PlayerRideController = Knit.CreateController {
	Name = "PlayerRideController",
}

-- =========================================================
-- STATE
-- =========================================================

local player = Players.LocalPlayer
local jumpDisabled = false
local isTransparent = false
local PlayerRideService = nil
local SplineService = nil
local originalTransparencies = {}  -- Store original transparencies to restore later

-- =========================================================
-- JUMP BLOCKING
-- =========================================================

local function blockJump(actionName, inputState, inputObject)
	if jumpDisabled then
		return Enum.ContextActionResult.Sink  -- Consume the input, prevent jump
	end
	return Enum.ContextActionResult.Pass
end

function PlayerRideController:DisableJump()
	jumpDisabled = true
	
	-- Bind action to block spacebar/jump button
	ContextActionService:BindAction(
		"BlockJump",
		blockJump,
		false,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA  -- Controller jump button
	)
	
	-- Also directly disable on humanoid
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.JumpPower = 0
			humanoid.JumpHeight = 0
			
			-- Override the Jump state
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
	end
	
	print("[PlayerRideController] Jump disabled")
end

function PlayerRideController:EnableJump()
	jumpDisabled = false
	
	-- Unbind the action
	ContextActionService:UnbindAction("BlockJump")
	
	-- Re-enable on humanoid
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.JumpPower = 50
			humanoid.JumpHeight = 7.2
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end
	
	print("[PlayerRideController] Jump enabled")
end

-- =========================================================
-- TRANSPARENCY
-- =========================================================

function PlayerRideController:MakePlayerTransparent(transparent: boolean)
	print("[PlayerRideController] MakePlayerTransparent called:", transparent)
	
	local character = player.Character
	if not character then
		print("[PlayerRideController] No character, waiting...")
		character = player.CharacterAdded:Wait()
		task.wait(0.5)
	end
	
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		warn("[PlayerRideController] No humanoid found!")
		return
	end
	
	print("[PlayerRideController] Character found, setting transparency:", transparent)
	
	if transparent then
		originalTransparencies = {}
		
		-- R15 body part names
		local bodyPartNames = {
			"Head", "UpperTorso", "LowerTorso",
			"LeftUpperArm", "LeftLowerArm", "LeftHand",
			"RightUpperArm", "RightLowerArm", "RightHand",
			"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot",
			-- R6 body part names
			"Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
			-- Additional
			"HumanoidRootPart"
		}
		
		-- Make body parts transparent
		for _, partName in ipairs(bodyPartNames) do
			local part = character:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				originalTransparencies[part] = part.Transparency
				part.Transparency = 1
				print("[PlayerRideController] Made " .. partName .. " transparent")
			end
		end
		
		-- Make ALL BaseParts in character transparent (catches everything)
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if not originalTransparencies[descendant] then
					originalTransparencies[descendant] = descendant.Transparency
				end
				descendant.Transparency = 1
			elseif descendant:IsA("Decal") then
				originalTransparencies[descendant] = descendant.Transparency
				descendant.Transparency = 1
			elseif descendant:IsA("MeshPart") then
				originalTransparencies[descendant] = descendant.Transparency
				descendant.Transparency = 1
			end
		end
		
		-- Handle accessories
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Accessory") then
				local handle = child:FindFirstChild("Handle")
				if handle then
					originalTransparencies[handle] = handle.Transparency
					handle.Transparency = 1
				end
				-- Also check for MeshPart in accessory
				for _, part in ipairs(child:GetDescendants()) do
					if part:IsA("BasePart") or part:IsA("MeshPart") then
						originalTransparencies[part] = part.Transparency
						part.Transparency = 1
					end
				end
			end
		end
		
		-- Hide face decal
		local head = character:FindFirstChild("Head")
		if head then
			local face = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal")
			if face then
				originalTransparencies[face] = face.Transparency
				face.Transparency = 1
			end
		end
		
		isTransparent = true
		print("[PlayerRideController] Player is now fully transparent!")
	else
		-- Restore
		for instance, originalValue in pairs(originalTransparencies) do
			if instance and instance.Parent then
				instance.Transparency = originalValue
			end
		end
		originalTransparencies = {}
		isTransparent = false
		print("[PlayerRideController] Player visibility restored")
	end
end

-- =========================================================
-- RIDE STATE
-- =========================================================

function PlayerRideController:OnRideStateChanged(isRiding: boolean, splineName: string)
	if isRiding then
		print("[PlayerRideController] Ride started on spline:", splineName)
		self:DisableJump()
	else
		print("[PlayerRideController] Ride ended on spline:", splineName)
		self:EnableJump()
	end
end

-- =========================================================
-- KNIT LIFECYCLE
-- =========================================================

function PlayerRideController:KnitInit()
	print("[PlayerRideController] Initializing")
end

function PlayerRideController:KnitStart()
	print("[PlayerRideController] Starting")
	
	-- Connect to services in a separate thread to not block
	task.spawn(function()
		-- Get services (PlayerRideService may not exist, use pcall)
		local success, service = pcall(function()
			return Knit.GetService("PlayerRideService")
		end)
		if success and service then
			PlayerRideService = service
			print("[PlayerRideController] Connected to PlayerRideService")
			
			-- Listen for disable jump signal from server
			PlayerRideService.DisableJump:Connect(function(disabled)
				if disabled then
					self:DisableJump()
				else
					self:EnableJump()
				end
			end)
		end
	end)
	
	-- Get SplineService in separate thread
	task.spawn(function()
		local splineSuccess, splineService = pcall(function()
			return Knit.GetService("SplineService")
		end)
		
		if splineSuccess and splineService then
			SplineService = splineService
			print("[PlayerRideController] Connected to SplineService")
			
			-- Listen for transparency signal from server
			SplineService.MakePlayerTransparent:Connect(function(shouldBeTransparent)
				print("[PlayerRideController] Received MakePlayerTransparent signal:", shouldBeTransparent)
				self:MakePlayerTransparent(shouldBeTransparent)
			end)
			
			-- Listen for ride state changes
			SplineService.RideStateChanged:Connect(function(isRiding, splineName)
				print("[PlayerRideController] Received RideStateChanged signal:", isRiding, splineName)
				self:OnRideStateChanged(isRiding, splineName)
				
				-- Also make transparent when ride starts
				if isRiding then
					self:MakePlayerTransparent(true)
				end
			end)
		else
			warn("[PlayerRideController] Failed to connect to SplineService:", splineService)
		end
	end)
	
	-- Handle character spawning/respawning
	local function onCharacterAdded(character)
		print("[PlayerRideController] Character added, setting up...")
		
		-- Wait for character to fully load
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		
		-- Re-apply states if needed
		if jumpDisabled then
			self:DisableJump()
		end
		
		if isTransparent then
			self:MakePlayerTransparent(true)
		end
		
		-- Auto-detect when player sits on a ride seat and make transparent
		humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
			if humanoid.Sit then
				local seatPart = humanoid.SeatPart
				if seatPart and seatPart.Name:match("RideSeat") then
					print("[PlayerRideController] Player sat on ride seat, making transparent")
					task.wait(0.1)
					self:MakePlayerTransparent(true)
					self:DisableJump()
				end
			end
		end)
		
		-- Check if already sitting on ride seat (in case we missed the signal)
		task.delay(1, function()
			if humanoid.Sit and humanoid.SeatPart then
				local seatPart = humanoid.SeatPart
				if seatPart.Name:match("RideSeat") then
					print("[PlayerRideController] Player already on ride seat, making transparent")
					self:MakePlayerTransparent(true)
					self:DisableJump()
				end
			end
		end)
		
		-- ALWAYS make player transparent after spawning (for this ride experience)
		task.delay(2, function()
			print("[PlayerRideController] Auto-making player transparent after spawn")
			self:MakePlayerTransparent(true)
		end)
	end
	
	player.CharacterAdded:Connect(onCharacterAdded)
	
	-- Handle existing character
	if player.Character then
		onCharacterAdded(player.Character)
	end
	
	print("[PlayerRideController] Ready")
end

return PlayerRideController

