local StatDecorators = {}

----------------------------------------------------------------
-- Legacy apply functions (kept for backward compatibility)
----------------------------------------------------------------

function StatDecorators.ApplyHP(vehicle, value)
	vehicle.Stats.HP = (vehicle.Stats.HP or 0) + value
end

function StatDecorators.ApplyTopSpeed(vehicle, value)
	vehicle.Stats.TopSpeed = (vehicle.Stats.TopSpeed or 0) + value
end

function StatDecorators.ApplyBoost(vehicle, value)
	vehicle.Stats.Boost = (vehicle.Stats.Boost or 0) + value
end

function StatDecorators.ApplyCharge(vehicle, value)
	vehicle.Stats.Charge = (vehicle.Stats.Charge or 0) + value
end

function StatDecorators.ApplyTurn(vehicle, value)
	vehicle.Stats.Turn = (vehicle.Stats.Turn or 0) + value
end

function StatDecorators.ApplyOffense(vehicle, value)
	vehicle.Stats.Offense = (vehicle.Stats.Offense or 0) + value
end

function StatDecorators.ApplyDefense(vehicle, value)
	vehicle.Stats.Defense = (vehicle.Stats.Defense or 0) + value
end

function StatDecorators.ApplyWeight(vehicle, value)
	vehicle.Stats.Weight = (vehicle.Stats.Weight or 0) + value
end

function StatDecorators.ApplyGlide(vehicle, value)
	vehicle.Stats.Glide = (vehicle.Stats.Glide or 0) + value
end

----------------------------------------------------------------
-- Decorator pattern: IMachineStats interface
-- Each provider implements :getStats() -> statsTable
----------------------------------------------------------------

-- BaseMachineStats: reads immutable base stats from MachinesConfig
local BaseMachineStats = {}
BaseMachineStats.__index = BaseMachineStats

function BaseMachineStats.new(machineId, machinesConfig)
	local machine = machinesConfig.machines[machineId]
	assert(machine, "Unknown machineId: " .. tostring(machineId))

	local self = setmetatable({}, BaseMachineStats)
	self._baseStats = {}
	for k, v in pairs(machine.baseStats) do
		self._baseStats[k] = v
	end
	return self
end

function BaseMachineStats:getStats()
	local copy = {}
	for k, v in pairs(self._baseStats) do
		copy[k] = v
	end
	return copy
end

StatDecorators.BaseMachineStats = BaseMachineStats

----------------------------------------------------------------
-- PatchDecorator: wraps an inner provider and applies patch bonuses
----------------------------------------------------------------

local PatchDecorator = {}
PatchDecorator.__index = PatchDecorator

function PatchDecorator.new(innerProvider, patchType, count, patchesConfig)
	local self = setmetatable({}, PatchDecorator)
	self._inner = innerProvider
	self._patchType = patchType
	self._count = count
	self._patchDef = patchesConfig.patches[patchType]
	return self
end

function PatchDecorator:getStats()
	local stats = self._inner:getStats()
	local def = self._patchDef
	if not def then return stats end

	if def.statKeys then
		for i, statKey in ipairs(def.statKeys) do
			local delta = def.deltas[i] * self._count
			local cap = def.softCaps[i]
			if cap > 0 then
				delta = math.min(delta, cap)
			else
				delta = math.max(delta, cap)
			end
			stats[statKey] = (stats[statKey] or 0) + delta
		end
	elseif def.statKey then
		local delta = def.delta * self._count
		local cap = def.softCap
		if def.floor ~= nil then
			delta = math.max(delta, cap)
			stats[def.statKey] = math.max((stats[def.statKey] or 0) + delta, def.floor)
		elseif cap >= 0 then
			stats[def.statKey] = (stats[def.statKey] or 0) + math.min(delta, cap)
		else
			stats[def.statKey] = (stats[def.statKey] or 0) + math.max(delta, cap)
		end
	end

	return stats
end

StatDecorators.PatchDecorator = PatchDecorator

----------------------------------------------------------------
-- EnvironmentDecorator: applies temporary environment effects
-- (rain, wind, etc.) as multipliers or additive modifiers
----------------------------------------------------------------

local EnvironmentDecorator = {}
EnvironmentDecorator.__index = EnvironmentDecorator

function EnvironmentDecorator.new(innerProvider, modifiers)
	local self = setmetatable({}, EnvironmentDecorator)
	self._inner = innerProvider
	self._modifiers = modifiers
	return self
end

function EnvironmentDecorator:getStats()
	local stats = self._inner:getStats()

	for statKey, mod in pairs(self._modifiers) do
		local current = stats[statKey] or 0
		if mod.multiply then
			stats[statKey] = current * mod.multiply
		end
		if mod.add then
			stats[statKey] = (stats[statKey] or current) + mod.add
		end
	end

	return stats
end

StatDecorators.EnvironmentDecorator = EnvironmentDecorator

----------------------------------------------------------------
-- Helper: build a full decorator chain from base + patches + env
----------------------------------------------------------------

function StatDecorators.BuildChain(machineId, machinesConfig, patchCounts, patchesConfig, envModifiers)
	local provider = BaseMachineStats.new(machineId, machinesConfig)

	if patchCounts then
		for patchType, count in pairs(patchCounts) do
			if count > 0 then
				provider = PatchDecorator.new(provider, patchType, count, patchesConfig)
			end
		end
	end

	if envModifiers then
		provider = EnvironmentDecorator.new(provider, envModifiers)
	end

	return provider
end

return StatDecorators
