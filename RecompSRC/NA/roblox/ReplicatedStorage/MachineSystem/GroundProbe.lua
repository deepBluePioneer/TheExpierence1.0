--!strict
--[[
	Ground probe: sample below machine along -Up (KAR probePos ≈ pos + up * hoverOffset).
]]

local Workspace = game:GetService("Workspace")

local MachineStats = require(script.Parent.MachineStats)

export type ProbeResult = {
	Grounded: boolean,
	HitPosition: Vector3?,
	Normal: Vector3?,
	Distance: number?,
}

local GroundProbe = {}

local DEFAULT_PARAMS: RaycastParams = RaycastParams.new()
DEFAULT_PARAMS.FilterType = Enum.RaycastFilterType.Exclude

function GroundProbe.UpdateParams(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	return params
end

function GroundProbe.Cast(
	origin: Vector3,
	up: Vector3,
	stats: MachineStats.Stats,
	params: RaycastParams
): ProbeResult
	local upUnit = if up.Magnitude > 1e-4 then up.Unit else Vector3.yAxis
	-- Probe from slightly above root, cast down along -up (ride height offset)
	local start = origin + upUnit * (stats.RideHeight * 0.35)
	local direction = -upUnit * stats.LeaveGroundRayLength

	local result = Workspace:Spherecast(start, stats.ProbeRadius, direction, params)
	if not result then
		result = Workspace:Raycast(start, direction, params)
	end

	if result then
		return {
			Grounded = true,
			HitPosition = result.Position,
			Normal = result.Normal,
			Distance = (start - result.Position).Magnitude,
		}
	end

	return {
		Grounded = false,
		HitPosition = nil,
		Normal = nil,
		Distance = nil,
	}
end

return GroundProbe
