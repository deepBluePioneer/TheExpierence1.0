--[[
	LoadingTrackerController
	Tracks loading times from LoadingService and reports to PerformanceProfilerController.
	
	Features:
	- Listens to LoadingService progress
	- Records timing for each loading step
	- Reports to profiler for display
	- Shows loading status in console
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local LoadingTrackerController = Knit.CreateController {
	Name = "LoadingTrackerController",
	_stepStartTimes = {},     -- { stepName = startTime }
	_stepDurations = {},      -- { stepName = duration }
	_totalStartTime = nil,
	_profiler = nil,
}

-- === HELPER FUNCTIONS ===

local function formatTime(seconds)
	if seconds < 0.001 then
		return string.format("%.2f μs", seconds * 1000000)
	elseif seconds < 1 then
		return string.format("%.2f ms", seconds * 1000)
	else
		return string.format("%.2f s", seconds)
	end
end

local function log(...)
	print("[LoadingTracker]", ...)
end

-- === LOADING TRACKING ===

function LoadingTrackerController:OnLoadingProgress(progress, description)
	local now = tick()
	
	-- Handle case where progress is a table (some services return {progress, description})
	local progressValue = progress
	local descriptionValue = description
	
	if type(progress) == "table" then
		progressValue = progress.progress or progress[1] or 0
		descriptionValue = progress.description or progress[2] or description or "Unknown"
	end
	
	-- Ensure progressValue is a number
	if type(progressValue) ~= "number" then
		progressValue = 0
	end
	
	-- Handle nil description
	if not descriptionValue or type(descriptionValue) ~= "string" then
		descriptionValue = "Unknown"
	end
	
	-- Extract step name from description (rough parsing)
	local stepName = descriptionValue:match("^(%w+)") or descriptionValue
	
	-- If we have a previous step running, end its timer
	for name, startTime in pairs(self._stepStartTimes) do
		if startTime and not self._stepDurations[name] then
			-- This step just completed
			local duration = now - startTime
			self._stepDurations[name] = duration
			
			-- Report to profiler
			if self._profiler then
				self._profiler:RecordLoadingTime(name, duration)
			end
			
			log(string.format("Step '%s' completed in %s", name, formatTime(duration)))
		end
	end
	
	-- Start timing the new step
	self._stepStartTimes[stepName] = now
	
	-- Update profiler counter
	if self._profiler then
		self._profiler:SetCounter("LoadingProgress", progressValue * 100)
		self._profiler:SetCounter("CurrentStep", stepName)
	end
	
	log(string.format("%.0f%% - %s", progressValue * 100, descriptionValue))
end

function LoadingTrackerController:OnServerReady()
	local totalTime = tick() - (self._totalStartTime or tick())
	
	-- Record total loading time
	if self._profiler then
		self._profiler:RecordLoadingTime("TOTAL", totalTime)
	end
	
	log(string.format("=== SERVER READY === Total loading time: %s", formatTime(totalTime)))
	
	-- Print summary
	self:PrintLoadingSummary()
end

function LoadingTrackerController:PrintLoadingSummary()
	log("=== Loading Time Summary ===")
	
	-- Sort by duration (longest first)
	local sortedSteps = {}
	for name, duration in pairs(self._stepDurations) do
		table.insert(sortedSteps, { name = name, duration = duration })
	end
	table.sort(sortedSteps, function(a, b) return a.duration > b.duration end)
	
	for _, step in ipairs(sortedSteps) do
		local bar = string.rep("█", math.min(20, math.floor(step.duration * 10)))
		log(string.format("  %s %s: %s", bar, step.name, formatTime(step.duration)))
	end
	
	log("============================")
end

function LoadingTrackerController:GetLoadingTimes()
	return self._stepDurations
end

function LoadingTrackerController:GetSlowestStep()
	local slowest = nil
	local maxDuration = 0
	
	for name, duration in pairs(self._stepDurations) do
		if duration > maxDuration then
			maxDuration = duration
			slowest = name
		end
	end
	
	return slowest, maxDuration
end

-- === KNIT LIFECYCLE ===

function LoadingTrackerController:KnitInit()
	log("Initializing...")
	self._totalStartTime = tick()
end

function LoadingTrackerController:KnitStart()
	log("Starting - tracking loading progress...")
	
	-- Get profiler reference
	pcall(function()
		self._profiler = Knit.GetController("PerformanceProfilerController")
	end)
	
	-- Connect to LoadingService
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	if LoadingService then
		-- Listen for progress updates
		LoadingService.LoadingProgress:Connect(function(progress, description)
			self:OnLoadingProgress(progress, description)
		end)
		
		-- Listen for server ready
		LoadingService.ServerReady:Connect(function()
			self:OnServerReady()
		end)
		
		-- Get initial progress (safely)
		local success, progress, description = pcall(function()
			return LoadingService:GetLoadingProgress()
		end)
		if success and progress ~= nil then
			self:OnLoadingProgress(progress, description or "Initial")
		end
		
		log("Connected to LoadingService")
	else
		log("LoadingService not available - tracking disabled")
	end
	
	-- Start a timer to track total client-side initialization
	if self._profiler then
		self._profiler:StartTimer("ClientInit")
		
		-- End the timer after a short delay (controllers should be loaded by then)
		task.delay(1, function()
			local duration = self._profiler:EndTimer("ClientInit")
			if duration then
				log(string.format("Client initialization: %s", formatTime(duration)))
			end
		end)
	end
end

return LoadingTrackerController

