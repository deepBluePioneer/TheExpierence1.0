--[[
	ServerAuthoritativePhysics

	Stub for future competitive mode. Client sends raw input to server;
	server runs physics and replicates state. Client uses MachineInterpolator
	to smooth rendered position.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MachineInterpolator = require(ReplicatedStorage.Source.MachineInterpolator)

local ServerAuthoritativePhysics = {}
ServerAuthoritativePhysics.__index = ServerAuthoritativePhysics

function ServerAuthoritativePhysics.new()
	return setmetatable({
		_model = nil,
		_rootPart = nil,
		_interpolator = nil,
		_inputState = {
			throttle = 0,
			steer = 0,
			boost = false,
			drift = false,
			brake = false,
		},
	}, ServerAuthoritativePhysics)
end

function ServerAuthoritativePhysics:init(machineModel, _statsProvider)
	self._model = machineModel
	self._rootPart = machineModel.PrimaryPart
	self._interpolator = MachineInterpolator.new()
end

function ServerAuthoritativePhysics:setInput(inputState)
	self._inputState = inputState
	-- TODO: send input to server via unreliable remote at 20-30Hz
end

function ServerAuthoritativePhysics:update(_dt)
	-- Physics runs on server; client only interpolates
	if self._interpolator and self._rootPart then
		local state = self._interpolator:getInterpolated(os.clock())
		if state then
			self._rootPart.CFrame = state.cframe
		end
	end
end

function ServerAuthoritativePhysics:getState()
	if self._interpolator then
		local state = self._interpolator:getInterpolated(os.clock())
		if state then
			return {
				cframe = state.cframe,
				velocity = state.velocity,
				grounded = true,
				currentSpeed = state.velocity.Magnitude,
				hoverDistance = 0,
			}
		end
	end

	return {
		cframe = self._rootPart and self._rootPart.CFrame or CFrame.new(),
		velocity = self._rootPart and self._rootPart.AssemblyLinearVelocity or Vector3.zero,
		grounded = true,
		currentSpeed = 0,
		hoverDistance = 0,
	}
end

function ServerAuthoritativePhysics:pushServerState(cframe, velocity, timestamp)
	if self._interpolator then
		self._interpolator:pushState(cframe, velocity, timestamp)
	end
end

function ServerAuthoritativePhysics:destroy()
	self._model = nil
	self._rootPart = nil
	if self._interpolator then
		self._interpolator:destroy()
		self._interpolator = nil
	end
end

return ServerAuthoritativePhysics
