--[[
	DebugLogger
	Centralized logging utility with service-level control
	
	Usage:
		local Logger = require(ReplicatedStorage.DebugLogger)
		local log = Logger.new("MyServiceName")
		
		log("This is a message")
		log("Formatted: %d items", count)
		
	To enable/disable logging:
		Logger.SetEnabled(true)                    -- Enable all logging
		Logger.SetServiceEnabled("MyService", true) -- Enable specific service
]]

local DebugLogger = {}

-- Global settings
local GLOBAL_ENABLED = false  -- Master switch for ALL logging
local SERVICE_ENABLED = {}    -- Per-service overrides: { ["ServiceName"] = true/false }

-- Default services to enable (useful for debugging specific services)
local DEFAULT_ENABLED_SERVICES = {
	-- "GridService",
	-- "TreeService",
	-- Add service names here to enable their logging by default
}

-- Initialize default enabled services
for _, serviceName in ipairs(DEFAULT_ENABLED_SERVICES) do
	SERVICE_ENABLED[serviceName] = true
end

-- Create a logger for a specific service
function DebugLogger.new(serviceName)
	return function(message, ...)
		-- Check if logging is enabled for this service
		local serviceEnabled = SERVICE_ENABLED[serviceName]
		
		-- If service has explicit setting, use it; otherwise use global
		local shouldLog = serviceEnabled ~= nil and serviceEnabled or GLOBAL_ENABLED
		
		if not shouldLog then
			return
		end
		
		-- Format message if additional args provided
		local output
		if select("#", ...) > 0 then
			output = string.format("[%s] " .. tostring(message), serviceName, ...)
		else
			output = string.format("[%s] %s", serviceName, tostring(message))
		end
		
		print(output)
	end
end

-- Enable/disable ALL logging globally
function DebugLogger.SetEnabled(enabled)
	GLOBAL_ENABLED = enabled
	print(string.format("[DebugLogger] Global logging %s", enabled and "ENABLED" or "DISABLED"))
end

-- Enable/disable logging for a specific service
function DebugLogger.SetServiceEnabled(serviceName, enabled)
	SERVICE_ENABLED[serviceName] = enabled
	print(string.format("[DebugLogger] %s logging %s", serviceName, enabled and "ENABLED" or "DISABLED"))
end

-- Enable multiple services at once
function DebugLogger.EnableServices(serviceNames)
	for _, name in ipairs(serviceNames) do
		SERVICE_ENABLED[name] = true
	end
end

-- Disable all service-specific overrides (revert to global setting)
function DebugLogger.ResetServiceOverrides()
	SERVICE_ENABLED = {}
end

-- Check if logging is enabled
function DebugLogger.IsEnabled()
	return GLOBAL_ENABLED
end

function DebugLogger.IsServiceEnabled(serviceName)
	local serviceEnabled = SERVICE_ENABLED[serviceName]
	return serviceEnabled ~= nil and serviceEnabled or GLOBAL_ENABLED
end

-- Get current status (useful for debugging)
function DebugLogger.GetStatus()
	return {
		globalEnabled = GLOBAL_ENABLED,
		serviceOverrides = SERVICE_ENABLED,
	}
end

return DebugLogger

