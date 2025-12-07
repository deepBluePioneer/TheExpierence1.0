--[[
	ProceduralLocomotionController (CLIENT-SIDE)
	
	Coordinator for the procedural locomotion system.
	Manages sub-controllers:
	- LocomotionController: IK-driven walk cycle, foot placement, arm swing
	- ArmCannonController: Samus-style arm cannon visuals
	- ShootingController: FastCast projectiles and recoil
	- MovementController: Physics-based movement and custom jump
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- Sub-controllers
local CONFIG = require(script.Parent.LocomotionConfig)

local ProceduralLocomotionController = Knit.CreateController {
	Name = "ProceduralLocomotionController",
	
	-- Sub-controller references
	_locomotionController = nil,
	_armCannonController = nil,
	_shootingController = nil,
	_movementController = nil,
	
	-- Connections
	_connections = {},
}

-- === SETUP ===

function ProceduralLocomotionController:SetupCharacter(character)
	-- Get sub-controllers
	self._locomotionController = Knit.GetController("LocomotionController")
	self._armCannonController = Knit.GetController("ArmCannonController")
	self._shootingController = Knit.GetController("ShootingController")
	self._movementController = Knit.GetController("MovementController")
	
	-- Setup locomotion (IK, walk cycle)
	if not self._locomotionController:SetupCharacter(character) then
		warn("[ProceduralLocomotion] Failed to setup locomotion")
		return
	end
	
	-- Setup arm cannon if enabled
	if CONFIG.UseArmCannon then
		self._armCannonController:CreateArmCannon(character)
		
		-- Setup shooting with callbacks to cannon
		self._shootingController:SetupShooting(
			character,
			function() return self._armCannonController:GetCannonTipPosition() end,
			function() return self._armCannonController:GetCannonParts() end,
			function(offset) self._armCannonController:SetRecoilOffset(offset) end
		)
	end
	
	-- Setup movement smoothing and custom jump
	self._movementController:SetupMovementSmoothing(character)
	
	-- Main update loop (Heartbeat for physics)
	local heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		-- Update movement physics
		self._movementController:UpdateMovementSmoothing(dt)
		self._movementController:UpdateCustomJump(dt)
		
		-- Pass smoothed values to locomotion
		self._locomotionController:SetSmoothedValues(
			self._movementController:GetSmoothedSpeed(),
			self._movementController:GetSmoothedDirection()
		)
		
		-- Update locomotion
		self._locomotionController:UpdateLocomotion(dt)
	end)
	table.insert(self._connections, heartbeatConn)
	
	-- Render update (RenderStepped for visuals)
	local renderConn = RunService.RenderStepped:Connect(function(dt)
		-- Reset motor transforms
		self._locomotionController:ResetMotorTransforms()
		
		-- Update right arm to camera
		self._locomotionController:UpdateRightArmToCamera()
		
		-- Update cannon visuals (pass dt for motion effects)
		if CONFIG.UseArmCannon then
			self._armCannonController:UpdateArmCannon(dt)
		end
	end)
	table.insert(self._connections, renderConn)
	
	-- Cleanup on death
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			self:Cleanup()
		end)
	end
end

function ProceduralLocomotionController:Cleanup()
	-- Disconnect all connections
	for _, conn in ipairs(self._connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	self._connections = {}
	
	-- Cleanup sub-controllers
	if self._locomotionController then
		self._locomotionController:Cleanup()
	end
	if self._armCannonController then
		self._armCannonController:Cleanup()
	end
	if self._shootingController then
		self._shootingController:Cleanup()
	end
	if self._movementController then
		self._movementController:Cleanup()
	end
end

-- === PUBLIC API ===

function ProceduralLocomotionController:SetEnabled(enabled)
	CONFIG.Enabled = enabled
	if not enabled then
		self:Cleanup()
	elseif Players.LocalPlayer.Character then
		self:SetupCharacter(Players.LocalPlayer.Character)
	end
end

function ProceduralLocomotionController:SetStrideLength(walk, run)
	CONFIG.StrideLength = walk
	CONFIG.StrideLengthRun = run or walk * 1.4
end

function ProceduralLocomotionController:SetStepHeight(walk, run)
	CONFIG.StepHeight = walk
	CONFIG.StepHeightRun = run or walk * 1.5
end

function ProceduralLocomotionController:SetBodyBob(amount)
	CONFIG.BodyBobAmount = amount
	CONFIG.BodyBobAmountRun = amount * 1.5
end

function ProceduralLocomotionController:SetArmSwing(amount)
	CONFIG.ArmSwingAmount = amount
	CONFIG.ArmSwingAmountRun = amount * 1.5
end

function ProceduralLocomotionController:SetDebugTargets(show)
	CONFIG.ShowTargets = show
	local targets = self._locomotionController and self._locomotionController:GetIKTargets()
	if targets then
		for _, target in pairs(targets) do
			if target then
				target.Transparency = show and 0 or 1
			end
		end
	end
end

function ProceduralLocomotionController:SetRightArmExtended(extended)
	CONFIG.RightArmExtended = extended
end

function ProceduralLocomotionController:SetRightArmForwardDistance(distance)
	CONFIG.RightArmForwardDistance = distance
end

function ProceduralLocomotionController:SetRightArmHeight(height)
	CONFIG.RightArmHeightOffset = height
end

function ProceduralLocomotionController:SetArmCannonEnabled(enabled)
	CONFIG.UseArmCannon = enabled
	if self._armCannonController then
		if enabled then
			local character = self._locomotionController and self._locomotionController:GetCharacter()
			if character and not self._armCannonController._armCannon then
				self._armCannonController:CreateArmCannon(character)
			end
		else
			self._armCannonController:DestroyArmCannon()
		end
	end
end

function ProceduralLocomotionController:SetMovementSmoothing(enabled, accelTime, decelTime)
	if self._movementController then
		self._movementController:SetMovementSmoothing(enabled, accelTime, decelTime)
	end
end

function ProceduralLocomotionController:SetMoveSpeed(walkSpeed, runSpeed)
	if self._movementController then
		self._movementController:SetMoveSpeed(walkSpeed, runSpeed)
	end
end

function ProceduralLocomotionController:SetJumpSettings(height, duration, hangTime)
	if self._movementController then
		self._movementController:SetJumpSettings(height, duration, hangTime)
	end
end

function ProceduralLocomotionController:SetCustomJumpEnabled(enabled)
	if self._movementController then
		self._movementController:SetCustomJumpEnabled(enabled)
	end
end

function ProceduralLocomotionController:SetCannonColors(main, accent, glow)
	if self._armCannonController then
		self._armCannonController:SetCannonColors(main, accent, glow)
	end
end

-- === KNIT LIFECYCLE ===

function ProceduralLocomotionController:KnitInit()
end

function ProceduralLocomotionController:KnitStart()
	if not CONFIG.Enabled then
		warn("[ProceduralLocomotion] System is disabled")
		return
	end
	
	local player = Players.LocalPlayer
	
	-- Setup current character
	if player.Character then
		task.spawn(function()
			task.wait(1) -- Wait for character to fully load
			self:SetupCharacter(player.Character)
		end)
	end
	
	-- Handle respawns
	player.CharacterAdded:Connect(function(character)
		self:Cleanup()
		task.wait(1)
		self:SetupCharacter(character)
	end)
end

return ProceduralLocomotionController
