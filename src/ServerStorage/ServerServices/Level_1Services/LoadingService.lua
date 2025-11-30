local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)

local LoadingService = Knit.CreateService {
	Name = "LoadingService",
	Client = {
		-- Signal fired when server is ready for players
		ServerReady = Knit.CreateSignal(),
		-- Signal fired to update loading progress
		LoadingProgress = Knit.CreateSignal(),
	},
	_isServerReady = false,
	_loadingSteps = {},
	_completedSteps = {},
	_playersWaiting = {},
	
	-- Server-side signals for inter-service communication
	StepCompleted = nil,  -- Signal(stepName: string) - fired when any step completes
}

-- === CONFIG ===
local LOADING_CONFIG = {
	-- Minimum time to show loading screen (for effect)
	MinLoadingTime = 2,
	-- Services to wait for (in order)
	ServicesToWait = {
		"GridService",
		"TreeService",
		"ParticleService",
		"WeatherService",
		"RoomService",
		-- Add more services as needed
	},
}

-- === LOADING STEPS ===

local function registerLoadingStep(self, stepName, stepDescription)
	table.insert(self._loadingSteps, {
		name = stepName,
		description = stepDescription,
		completed = false,
	})
end

local function completeLoadingStep(self, stepName)
	for i, step in ipairs(self._loadingSteps) do
		if step.name == stepName then
			step.completed = true
			self._completedSteps[stepName] = true
			
			-- Calculate progress
			local completedCount = 0
			for _, s in ipairs(self._loadingSteps) do
				if s.completed then
					completedCount = completedCount + 1
				end
			end
			
			local progress = completedCount / #self._loadingSteps
			local currentStep = self._loadingSteps[i]
			
			print(string.format("[LoadingService] Step completed: %s (%.0f%%)", stepName, progress * 100))
			
			-- Notify all waiting clients
			self.Client.LoadingProgress:FireAll(progress, currentStep.description)
			
			-- Fire server-side signal for inter-service communication
			if self.StepCompleted then
				self.StepCompleted:Fire(stepName)
			end
			
			break
		end
	end
end

local function checkAllStepsComplete(self, excludeFinalizing)
	for _, step in ipairs(self._loadingSteps) do
		-- Skip Finalizing step if requested
		if excludeFinalizing and step.name == "Finalizing" then
			continue
		end
		if not step.completed then
			return false
		end
	end
	return true
end

local function getIncompleteSteps(self)
	local incomplete = {}
	for _, step in ipairs(self._loadingSteps) do
		if not step.completed then
			table.insert(incomplete, step.name)
		end
	end
	return incomplete
end

-- === PLAYER SPAWNING ===

local function spawnPlayer(player)
	if player.Character then
		return -- Already has character
	end
	
	print("[LoadingService] Spawning player:", player.Name)
	player:LoadCharacter()
end

local function onPlayerAdded(self, player)
	print("[LoadingService] Player joined:", player.Name)
	
	-- Add to waiting list
	self._playersWaiting[player] = true
	
	-- If server is already ready, spawn them after a brief delay (for loading screen)
	if self._isServerReady then
		task.delay(LOADING_CONFIG.MinLoadingTime, function()
			if player.Parent then -- Still in game
				self.Client.ServerReady:Fire(player)
				task.wait(0.5) -- Give client time to process
				spawnPlayer(player)
				self._playersWaiting[player] = nil
			end
		end)
	end
end

local function onPlayerRemoving(self, player)
	self._playersWaiting[player] = nil
end

-- === INITIALIZATION ===

local function initializeLoading(self)
	-- Register loading steps (order matters for display)
	registerLoadingStep(self, "Initializing", "Initializing game systems...")
	registerLoadingStep(self, "GridService", "Generating world grid...")
	registerLoadingStep(self, "TerrainService", "Generating terrain...")
	registerLoadingStep(self, "TreeService", "Growing alien forest...")
	registerLoadingStep(self, "FormationService", "Creating alien formations...")
	registerLoadingStep(self, "ParticleService", "Adding ambient effects...")
	registerLoadingStep(self, "WeatherService", "Setting up weather system...")
	registerLoadingStep(self, "RoomService", "Building rooms...")
	registerLoadingStep(self, "MonolithEntityService", "Awakening the Monolith...")
	registerLoadingStep(self, "AudioLogService", "Placing audio logs...")
	registerLoadingStep(self, "Finalizing", "Finalizing world...")
	
	-- Complete initial step immediately
	completeLoadingStep(self, "Initializing")
end

local function waitForServices(self)
	print("[LoadingService] Waiting for services to initialize...")
	print("[LoadingService] Services will mark themselves complete when ready")
	
	-- Services mark their own steps complete via MarkStepComplete()
	-- We just wait for all steps to be done
	
	-- Set a timeout to prevent infinite waiting
	task.spawn(function()
		task.wait(30)  -- 30 second timeout
		
		-- Check if any services haven't completed
		for _, step in ipairs(self._loadingSteps) do
			if not step.completed and step.name ~= "Finalizing" then
				warn("[LoadingService] Timeout: Service didn't complete:", step.name)
				-- Force complete to prevent infinite hang
				completeLoadingStep(self, step.name)
			end
		end
	end)
end

local function finalizeLoading(self)
	print("[LoadingService] Waiting for all services to complete...")
	
	-- Wait until all steps (except Finalizing) are complete
	local waitStart = tick()
	while not checkAllStepsComplete(self, true) do  -- true = exclude Finalizing
		-- Log progress every 2 seconds
		if (tick() - waitStart) % 2 < 0.15 then
			local incomplete = getIncompleteSteps(self)
			print("[LoadingService] Still waiting for:", table.concat(incomplete, ", "))
		end
		task.wait(0.1)
	end
	
	print("[LoadingService] All services complete!")
	
	-- Add minimum loading time
	local startTime = tick()
	while (tick() - startTime) < LOADING_CONFIG.MinLoadingTime do
		task.wait(0.1)
	end
	
	-- Complete final step
	completeLoadingStep(self, "Finalizing")
	
	-- Mark server as ready
	self._isServerReady = true
	print("[LoadingService] *** SERVER READY ***")
	
	-- Notify all waiting players and spawn them
	for player, _ in pairs(self._playersWaiting) do
		if player.Parent then
			self.Client.ServerReady:Fire(player)
			task.wait(0.5)
			spawnPlayer(player)
		end
	end
	self._playersWaiting = {}
end

-- === CLIENT METHODS ===

function LoadingService.Client:IsServerReady()
	return self.Server._isServerReady
end

function LoadingService.Client:GetLoadingProgress()
	local completedCount = 0
	for _, step in ipairs(self.Server._loadingSteps) do
		if step.completed then
			completedCount = completedCount + 1
		end
	end
	
	local progress = #self.Server._loadingSteps > 0 
		and completedCount / #self.Server._loadingSteps 
		or 0
	
	-- Get current step description
	local currentDescription = "Loading..."
	for _, step in ipairs(self.Server._loadingSteps) do
		if not step.completed then
			currentDescription = step.description
			break
		end
	end
	
	return progress, currentDescription
end

function LoadingService.Client:RequestSpawn(player)
	if self.Server._isServerReady then
		spawnPlayer(player)
		return true
	end
	return false
end

-- === KNIT LIFECYCLE ===

function LoadingService:KnitInit()
	-- Create server-side signal for inter-service communication
	self.StepCompleted = Signal.new()
	
	-- Disable auto character loading
	Players.CharacterAutoLoads = false
	
	-- Initialize loading steps
	initializeLoading(self)
	
	-- Connect player events
	Players.PlayerAdded:Connect(function(player)
		onPlayerAdded(self, player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		onPlayerRemoving(self, player)
	end)
	
	-- Handle players already in game
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(self, player)
	end
	
	print("[LoadingService] Initialized - CharacterAutoLoads disabled")
end

function LoadingService:KnitStart()
	-- Start waiting for services
	waitForServices(self)
	
	-- Finalize loading in background
	task.spawn(function()
		finalizeLoading(self)
	end)
end

-- === PUBLIC METHODS ===

function LoadingService:MarkStepComplete(stepName)
	completeLoadingStep(self, stepName)
end

function LoadingService:IsReady()
	return self._isServerReady
end

function LoadingService:ForceSpawnPlayer(player)
	spawnPlayer(player)
end

-- Services can call this to update their loading status
function LoadingService:UpdateStatus(serviceName, statusMessage, subProgress)
	-- subProgress is optional (0-1) for sub-progress within a step
	local fullMessage = string.format("[%s] %s", serviceName, statusMessage)
	print("[LoadingService] Status update:", fullMessage)
	
	-- Calculate overall progress
	local completedCount = 0
	local currentStepIndex = 0
	for i, step in ipairs(self._loadingSteps) do
		if step.completed then
			completedCount = completedCount + 1
		elseif step.name == serviceName then
			currentStepIndex = i
		end
	end
	
	-- Add sub-progress if provided
	local baseProgress = completedCount / #self._loadingSteps
	if subProgress and currentStepIndex > 0 then
		local stepSize = 1 / #self._loadingSteps
		baseProgress = baseProgress + (stepSize * subProgress)
	end
	
	-- Fire to all clients
	self.Client.LoadingProgress:FireAll(baseProgress, statusMessage)
end

-- Shorthand for services to report progress
function LoadingService:ReportProgress(serviceName, current, total, action)
	local percent = total > 0 and (current / total) or 0
	local message = string.format("%s... (%d/%d)", action, current, total)
	self:UpdateStatus(serviceName, message, percent)
end

-- Check if a step is already completed
function LoadingService:IsStepComplete(stepName)
	return self._completedSteps[stepName] == true
end

-- Wait for a specific step to complete (returns immediately if already done)
-- Returns a Promise-like pattern using a callback
function LoadingService:OnStepComplete(stepName, callback)
	-- If already complete, call immediately
	if self._completedSteps[stepName] then
		callback(stepName)
		return
	end
	
	-- Otherwise, listen for the signal
	local connection
	connection = self.StepCompleted:Connect(function(completedStep)
		if completedStep == stepName then
			connection:Disconnect()
			callback(stepName)
		end
	end)
	
	return connection
end

-- Wait for multiple steps to complete
function LoadingService:OnStepsComplete(stepNames, callback)
	local remaining = {}
	for _, name in ipairs(stepNames) do
		if not self._completedSteps[name] then
			remaining[name] = true
		end
	end
	
	-- If all already complete, call immediately
	if next(remaining) == nil then
		callback()
		return
	end
	
	-- Listen for each step
	local connection
	connection = self.StepCompleted:Connect(function(completedStep)
		if remaining[completedStep] then
			remaining[completedStep] = nil
			
			-- Check if all done
			if next(remaining) == nil then
				connection:Disconnect()
				callback()
			end
		end
	end)
	
	return connection
end

return LoadingService

