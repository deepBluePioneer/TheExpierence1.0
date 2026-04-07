-- Stub PlayerModule that prevents the default Roblox PlayerModule from loading.
-- All character movement is handled by custom controllers (GraviBow, Vehicles, etc.).

local NOOP = function() end

local Controls = {}
Controls.__index = Controls
Controls.Enable = NOOP
Controls.Disable = NOOP
function Controls:GetActiveController() return nil end

local PlayerModule = {}
PlayerModule.__index = PlayerModule

function PlayerModule:GetControls()
	return setmetatable({}, Controls)
end

function PlayerModule:GetCameras()
	return nil
end

return setmetatable({}, PlayerModule)
