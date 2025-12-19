--[[
	ArrowTimerService
	
	Manages a countdown timer using the Timer module and replicates
	timer state to clients using ReplicaService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Timer = require(Packages.timer)

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local ReplicaService = require(CustomPackages.Replica.ReplicaService)

local Signal = require(Packages.Signal)

local ArrowTimerService = Knit.CreateService({
	Name = "ArrowTimerService",
	Client = {
		TimerStarted = Knit.CreateSignal(),
		TimerEnded = Knit.CreateSignal(),
	},
	
	-- Server-side signals (for other services to listen to)
	TimerStartedServer = Signal.new(),
	TimerEndedServer = Signal.new(),
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	DefaultDuration = 10,     -- Default countdown duration in seconds
	TickInterval = 0.1,       -- How often to update the timer (seconds)
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local TimerClassToken = nil
local timerReplica = nil
local countdownTimer = nil
local isRunning = false

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         REPLICA SETUP                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTimerService:SetupReplica()
	TimerClassToken = ReplicaService.NewClassToken("ArrowTimer")
	
	timerReplica = ReplicaService.NewReplica({
		ClassToken = TimerClassToken,
		Tags = { Type = "GameTimer" },
		Data = {
			TimeRemaining = CONFIG.DefaultDuration,
			TotalDuration = CONFIG.DefaultDuration,
			IsRunning = false,
			IsPaused = false,
		},
		Replication = "All",
	})
	
	print("[ArrowTimerService] ✓ Timer replica created")
	return timerReplica
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         TIMER LOGIC                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Start the countdown timer
function ArrowTimerService:StartTimer(duration: number?)
	local timerDuration = duration or CONFIG.DefaultDuration
	
	-- Stop any existing timer
	self:StopTimer()
	
	-- Reset timer state
	timerReplica:SetValue({"TotalDuration"}, timerDuration)
	timerReplica:SetValue({"TimeRemaining"}, timerDuration)
	timerReplica:SetValue({"IsRunning"}, true)
	timerReplica:SetValue({"IsPaused"}, false)
	
	isRunning = true
	
	-- Create the countdown timer using Timer module
	countdownTimer = Timer.new(CONFIG.TickInterval)
	
	local startTime = tick()
	local endTime = startTime + timerDuration
	
	countdownTimer.Tick:Connect(function()
		if not isRunning then return end
		
		local currentTime = tick()
		local remaining = math.max(0, endTime - currentTime)
		
		-- Update the replica with remaining time
		timerReplica:SetValue({"TimeRemaining"}, remaining)
		
		-- Check if timer has ended
		if remaining <= 0 then
			self:OnTimerComplete()
		end
	end)
	
	countdownTimer:Start()
	
	print(string.format("[ArrowTimerService] ✓ Timer started: %.1f seconds", timerDuration))
	self.Client.TimerStarted:FireAll(timerDuration)
	self.TimerStartedServer:Fire(timerDuration)
	
	return true
end

-- Stop the countdown timer
function ArrowTimerService:StopTimer()
	if countdownTimer then
		countdownTimer:Stop()
		countdownTimer:Destroy()
		countdownTimer = nil
	end
	
	isRunning = false
	
	if timerReplica then
		timerReplica:SetValue({"IsRunning"}, false)
		timerReplica:SetValue({"IsPaused"}, false)
	end
	
	print("[ArrowTimerService] Timer stopped")
	return true
end

-- Pause the countdown timer
function ArrowTimerService:PauseTimer()
	if countdownTimer and isRunning then
		countdownTimer:Stop()
		timerReplica:SetValue({"IsPaused"}, true)
		print("[ArrowTimerService] Timer paused")
		return true
	end
	return false
end

-- Resume the countdown timer
function ArrowTimerService:ResumeTimer()
	if countdownTimer and isRunning and timerReplica.Data.IsPaused then
		-- Restart from current remaining time
		local remaining = timerReplica.Data.TimeRemaining
		timerReplica:SetValue({"IsPaused"}, false)
		
		-- Create new timer for remaining time
		self:StopTimer()
		self:StartTimer(remaining)
		
		print("[ArrowTimerService] Timer resumed")
		return true
	end
	return false
end

-- Called when timer reaches zero
function ArrowTimerService:OnTimerComplete()
	print("[ArrowTimerService] ✓ Timer complete!")
	
	self:StopTimer()
	timerReplica:SetValue({"TimeRemaining"}, 0)
	
	-- Fire signal to clients
	self.Client.TimerEnded:FireAll()
	
	-- Fire server-side signal for other services
	self.TimerEndedServer:Fire()
end

-- Reset timer to default
function ArrowTimerService:ResetTimer()
	self:StopTimer()
	
	timerReplica:SetValue({"TimeRemaining"}, CONFIG.DefaultDuration)
	timerReplica:SetValue({"TotalDuration"}, CONFIG.DefaultDuration)
	
	print("[ArrowTimerService] Timer reset")
	return true
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTimerService:GetTimeRemaining()
	if timerReplica then
		return timerReplica.Data.TimeRemaining
	end
	return 0
end

function ArrowTimerService:IsRunning()
	return isRunning
end

function ArrowTimerService:IsPaused()
	if timerReplica then
		return timerReplica.Data.IsPaused
	end
	return false
end

function ArrowTimerService:GetConfig()
	return CONFIG
end

function ArrowTimerService:SetDefaultDuration(duration: number)
	CONFIG.DefaultDuration = duration
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTimerService.Client:GetTimeRemaining(player)
	return ArrowTimerService:GetTimeRemaining()
end

function ArrowTimerService.Client:IsTimerRunning(player)
	return ArrowTimerService:IsRunning()
end

function ArrowTimerService.Client:RequestStartTimer(player, duration: number?)
	-- Add any validation/permission checks here if needed
	return ArrowTimerService:StartTimer(duration)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTimerService:KnitInit()
	print("[ArrowTimerService] Initializing...")
	self:SetupReplica()
end

function ArrowTimerService:KnitStart()
	print("[ArrowTimerService] Starting...")
	
	-- Auto-start timer for testing (remove in production)
	task.delay(3, function()
		self:StartTimer(10)
	end)
	
	print("[ArrowTimerService] Ready")
end

return ArrowTimerService

