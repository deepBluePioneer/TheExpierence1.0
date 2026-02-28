local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Input = require(Packages.Input)
local Signal = require(Packages.Signal)

local CustomPackages = ReplicatedStorage.CustomPackages
local ReplicaController = require(CustomPackages.Replica.ReplicaController)

local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local MachinePhysicsConfig = require(ReplicatedStorage.Source.MachinePhysicsConfig)
local MachineInputMap = require(ReplicatedStorage.Source.MachineInputMap)
local ClientPredictedPhysics = require(ReplicatedStorage.Source.ClientPredictedPhysics)
local ServerAuthoritativePhysics = require(ReplicatedStorage.Source.ServerAuthoritativePhysics)

local IS_STUDIO = RunService:IsStudio()

local Gizmo
if IS_STUDIO then
	local ok, mod = pcall(require, Packages.imgizmo)
	if ok then
		Gizmo = mod
		Gizmo.Init()
	end
end

local LocalPlayer = Players.LocalPlayer

local STATES = {
	IDLE = "IDLE",
	DRIVING = "DRIVING",
	BOOSTING = "BOOSTING",
	DRIFTING = "DRIFTING",
	AIRBORNE = "AIRBORNE",
	STUNNED = "STUNNED",
	DEAD = "DEAD",
	FROZEN = "FROZEN",
}

local MachineController = Knit.CreateController({
	Name = "MachineController",

	_trove = nil,
	_physics = nil,
	_machineModel = nil,
	_machineReplica = nil,
	_state = STATES.IDLE,

	_boostCharge = 0,
	_boostCooldownRemaining = 0,
	_isDrifting = false,
	_stunTimer = 0,

	_inputState = {
		throttle = 0,
		steer = 0,
		pitch = 0,
		boost = false,
		drift = false,
		brake = false,
	},

	_mobileController = nil,
	_renderConn = nil,

	StateChanged = Signal.new(),
})

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function MachineController:KnitStart()
	self._trove = Trove.new()

	self:_waitForMachineReplica()
end

function MachineController:_waitForMachineReplica()
	local timeout = 30
	local startTime = os.clock()
	local found = false

	ReplicaController.ReplicaOfClassCreated("MachineState", function(replica)
		local tags = replica.Tags
		if tags.Player ~= LocalPlayer then return end
		if found then return end
		found = true

		self._machineReplica = replica

		replica:ListenToChange({ "state" }, function(newState)
			self:_onServerStateChange(newState)
		end)

		self._trove:Add(function()
			self._machineReplica = nil
		end)

		self:_findAndInitMachine()
	end)

	task.spawn(function()
		while not found and (os.clock() - startTime) < timeout do
			task.wait(0.5)
		end
		if not found then
			warn("[MachineController] Timed out waiting for MachineState replica")
		end
	end)
end

function MachineController:_findAndInitMachine()
	local userId = LocalPlayer.UserId

	local machinesFolder = workspace:WaitForChild("CityTrialMachines", 15)
	if not machinesFolder then
		warn("[MachineController] CityTrialMachines folder not found")
		return
	end

	local model
	for _ = 1, 60 do
		for _, child in machinesFolder:GetChildren() do
			if child:GetAttribute("OwnerUserId") == userId then
				model = child
				break
			end
		end
		if model then break end
		task.wait(0.25)
	end

	if not model then
		warn("[MachineController] Could not find machine model for local player")
		return
	end

	self._machineModel = model
	self:_initPhysics()
	self:_startRenderLoop()

	print("[MachineController] Machine initialized: " .. model.Name)
end

function MachineController:_initPhysics()
	if not self._machineModel then return end

	local physicsMode = GameConfig.physicsMode

	if physicsMode == "ServerAuthoritative" then
		self._physics = ServerAuthoritativePhysics.new()
	else
		self._physics = ClientPredictedPhysics.new()
	end

	local function statsProvider()
		if self._machineReplica then
			return self._machineReplica.Data.stats
		end
		return {
			topSpeed = 85,
			acceleration = 6,
			handling = 6,
			weight = 5,
			boostPower = 30,
			boostChargeRate = 1.0,
			maxHealth = 80,
		}
	end

	self._physics:init(self._machineModel, statsProvider)

	self._trove:Add(function()
		if self._physics then
			self._physics:destroy()
			self._physics = nil
		end
	end)

	local preferredInput = Input.PreferredInput
	if preferredInput == "Touch" then
		local ok, MobileMachineInputController = pcall(function()
			return Knit.GetController("MobileMachineInputController")
		end)
		if ok and MobileMachineInputController then
			self._mobileController = MobileMachineInputController
		end
	end
end

----------------------------------------------------------------
-- Input
----------------------------------------------------------------

function MachineController:_gatherInput()
	if self._mobileController then
		self._inputState = self._mobileController:GetInput()
		return
	end

	local throttle = 1
	local steer = 0
	local pitch = 0
	local boost = false
	local drift = false
	local brake = false

	local gamepadConnected = UserInputService.GamepadEnabled

	if gamepadConnected and Input.PreferredInput == "Gamepad" then
		local binds = MachineInputMap.gamepad
		if UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, binds.brake) then
			brake = true
		end
		if UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, binds.boost) then
			boost = true
		end
		if UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, binds.drift) then
			drift = true
		end

		local state = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
		for _, inputObj in state do
			if inputObj.KeyCode == binds.steerAxis then
				steer = inputObj.Position.X
			elseif inputObj.KeyCode == binds.pitchAxis then
				pitch = -inputObj.Position.Y
			end
		end
	else
		local binds = MachineInputMap.keyboard
		if UserInputService:IsKeyDown(binds.brake) then
			brake = true
		end
		if UserInputService:IsKeyDown(binds.steerLeft) then
			steer = steer - 1
		end
		if UserInputService:IsKeyDown(binds.steerRight) then
			steer = steer + 1
		end
		if UserInputService:IsKeyDown(binds.boost) then
			boost = true
		end
		if UserInputService:IsKeyDown(binds.drift) then
			drift = true
		end
		if UserInputService:IsKeyDown(binds.pitchUp) then
			pitch = pitch - 1
		end
		if UserInputService:IsKeyDown(binds.pitchDown) then
			pitch = pitch + 1
		end
	end

	self._inputState = {
		throttle = throttle,
		steer = steer,
		pitch = pitch,
		boost = boost,
		drift = drift,
		brake = brake,
	}
end

----------------------------------------------------------------
-- State machine
----------------------------------------------------------------

function MachineController:_setState(newState)
	if self._state == newState then return end
	local old = self._state
	self._state = newState
	self.StateChanged:Fire(newState, old)
end

function MachineController:_onServerStateChange(serverState)
	if serverState == "IDLE" then
		self:_setState(STATES.IDLE)
	elseif serverState == "DRIVING" then
		if self._state == STATES.IDLE or self._state == STATES.DEAD or self._state == STATES.FROZEN then
			self:_setState(STATES.DRIVING)
		end
	elseif serverState == "STUNNED" then
		self:_setState(STATES.STUNNED)
		self._stunTimer = MachinePhysicsConfig.collisionStunDuration
	elseif serverState == "DEAD" then
		self:_setState(STATES.DEAD)
	elseif serverState == "FROZEN" then
		self:_setState(STATES.FROZEN)
	end
end

function MachineController:_updateStateMachine(dt)
	local state = self._state
	local input = self._inputState

	if state == STATES.STUNNED then
		self._stunTimer = self._stunTimer - dt
		if self._stunTimer <= 0 then
			self:_setState(STATES.DRIVING)
		end
	end

	if state == STATES.IDLE or state == STATES.DEAD or state == STATES.STUNNED or state == STATES.FROZEN then
		self._inputState = {
			throttle = 0,
			steer = 0,
			pitch = 0,
			boost = false,
			drift = false,
			brake = false,
		}
		return
	end

	if state == STATES.DRIVING or state == STATES.BOOSTING or state == STATES.DRIFTING then
		local physState = self._physics and self._physics:getState()
		if physState and not physState.grounded then
			self:_setState(STATES.AIRBORNE)
		end
	end

	if state == STATES.AIRBORNE then
		local physState = self._physics and self._physics:getState()
		if physState and physState.grounded then
			self:_setState(STATES.DRIVING)
		end
	end

	if state == STATES.DRIVING then
		if input.boost and self._boostCharge > 0 and self._boostCooldownRemaining <= 0 then
			self:_setState(STATES.BOOSTING)
		elseif input.drift and math.abs(input.steer) > 0.1 then
			self:_setState(STATES.DRIFTING)
		end
	end

	if state == STATES.BOOSTING then
		if not input.boost or self._boostCharge <= 0 then
			self._boostCooldownRemaining = MachinePhysicsConfig.boostCooldown
			self:_setState(STATES.DRIVING)
		end
	end

	if state == STATES.DRIFTING then
		if not input.drift then
			if MachinePhysicsConfig.miniBoostOnDriftExit > 0 and self._boostCharge < MachinePhysicsConfig.maxBoostCharge then
				self._boostCharge = math.min(self._boostCharge + MachinePhysicsConfig.miniBoostOnDriftExit, MachinePhysicsConfig.maxBoostCharge)
			end
			self:_setState(STATES.DRIVING)
		end
	end
end

function MachineController:_updateBoost(dt)
	local state = self._state
	local config = MachinePhysicsConfig

	self._boostCooldownRemaining = math.max(0, self._boostCooldownRemaining - dt)

	if state == STATES.BOOSTING then
		self._boostCharge = self._boostCharge - config.boostDecay * dt
		self._boostCharge = math.max(0, self._boostCharge)
		self._inputState.boost = true
	else
		if self._boostCooldownRemaining <= 0 then
			local stats = self._machineReplica and self._machineReplica.Data.stats
			local chargeRate = stats and stats.boostChargeRate or 1

			if state == STATES.DRIFTING then
				chargeRate = chargeRate * config.driftBoostChargeMultiplier
			end

			self._boostCharge = math.min(self._boostCharge + chargeRate * dt, config.maxBoostCharge)
		end
		self._inputState.boost = false
	end
end

----------------------------------------------------------------
-- Render loop
----------------------------------------------------------------

function MachineController:_startRenderLoop()
	if self._renderConn then return end

	self._renderConn = RunService.RenderStepped:Connect(function(dt)
		self:_gatherInput()
		self:_updateStateMachine(dt)
		self:_updateBoost(dt)

		if self._physics then
			self._physics:setInput(self._inputState)
			self._physics:update(dt)
		end
	end)

	self._trove:Add(self._renderConn)
end

----------------------------------------------------------------
-- Camera state (for MachineCameraController)
----------------------------------------------------------------

function MachineController:GetCameraState()
	local physState = self._physics and self._physics:getState()
	if not physState then
		return {
			rootCFrame = CFrame.new(),
			velocity = Vector3.zero,
			isBoosting = false,
			isStunned = false,
			isDead = false,
			currentSpeed = 0,
		}
	end

	return {
		rootCFrame = physState.cframe,
		velocity = physState.velocity,
		isBoosting = self._state == STATES.BOOSTING,
		isStunned = self._state == STATES.STUNNED,
		isDead = self._state == STATES.DEAD,
		isFrozen = self._state == STATES.FROZEN,
		currentSpeed = physState.currentSpeed,
		grounded = physState.grounded,
		steer = self._inputState and self._inputState.steer or 0,
		pitch = physState.pitch or 0,
		airTime = physState.airTime or 0,
	}
end

function MachineController:GetState()
	return self._state
end

function MachineController:GetBoostCharge()
	return self._boostCharge
end

function MachineController:GetMachineModel()
	return self._machineModel
end

function MachineController:GetMachineReplica()
	return self._machineReplica
end

return MachineController
