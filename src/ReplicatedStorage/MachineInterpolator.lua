--[[
	MachineInterpolator

	Buffers server-sent CFrame/velocity snapshots and provides smooth
	interpolation between them for server-authoritative physics mode.
]]

local BUFFER_SIZE = 3
local INTERPOLATION_DELAY = 0.1

local MachineInterpolator = {}
MachineInterpolator.__index = MachineInterpolator

function MachineInterpolator.new()
	return setmetatable({
		_buffer = {},
	}, MachineInterpolator)
end

function MachineInterpolator:pushState(cframe, velocity, timestamp)
	table.insert(self._buffer, {
		cframe = cframe,
		velocity = velocity,
		timestamp = timestamp,
	})

	while #self._buffer > BUFFER_SIZE do
		table.remove(self._buffer, 1)
	end
end

function MachineInterpolator:getInterpolated(renderTime)
	local buffer = self._buffer
	if #buffer == 0 then return nil end
	if #buffer == 1 then
		return { cframe = buffer[1].cframe, velocity = buffer[1].velocity }
	end

	local targetTime = renderTime - INTERPOLATION_DELAY

	local from = buffer[1]
	local to = buffer[2]

	for i = 2, #buffer do
		if buffer[i].timestamp >= targetTime then
			to = buffer[i]
			from = buffer[i - 1] or buffer[i]
			break
		end
		from = buffer[i]
		to = buffer[math.min(i + 1, #buffer)]
	end

	local span = to.timestamp - from.timestamp
	if span <= 0 then
		return { cframe = to.cframe, velocity = to.velocity }
	end

	local alpha = math.clamp((targetTime - from.timestamp) / span, 0, 1)

	return {
		cframe = from.cframe:Lerp(to.cframe, alpha),
		velocity = from.velocity:Lerp(to.velocity, alpha),
	}
end

function MachineInterpolator:destroy()
	self._buffer = {}
end

return MachineInterpolator
