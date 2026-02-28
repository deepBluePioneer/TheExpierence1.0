--[[
	IMachinePhysics

	Interface contract for machine physics strategies.
	Both ClientPredictedPhysics and ServerAuthoritativePhysics implement this.
]]

local IMachinePhysics = {}
IMachinePhysics.__index = IMachinePhysics

function IMachinePhysics.new()
	return setmetatable({}, IMachinePhysics)
end

function IMachinePhysics:init(_machineModel, _statsProvider)
	error("IMachinePhysics:init must be implemented")
end

function IMachinePhysics:setInput(_inputState)
	error("IMachinePhysics:setInput must be implemented")
end

function IMachinePhysics:update(_dt)
	error("IMachinePhysics:update must be implemented")
end

function IMachinePhysics:getState()
	error("IMachinePhysics:getState must be implemented")
end

function IMachinePhysics:destroy()
	error("IMachinePhysics:destroy must be implemented")
end

return IMachinePhysics
