local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

-- Replica Modules
local Replica = CustomPackages.Replica
local ReplicaService = require(Replica.ReplicaService)

local Signal = require(Packages.Signal)
local Timer = require(Packages.timer)

local initLobbyTime = 10
local initGameCountdownTime = 5 -- short pre-game countdown
local initMainGameTime = 1 * 60 -- 5 minutes in seconds
local initReturnTime = 60

local GameManagerService = Knit.CreateService {
    Name = "GameManagerService",
    Client = {},
    OnGameTimerEnd = Signal.new(),
    OnPreGameTimerEnd = Signal.new()
}

function GameManagerService:InitReplicas()
    self.TimerReplica = ReplicaService.NewReplica({
        ClassToken = ReplicaService.NewClassToken("TimerReplica"),
        Data = {
            TimeRemaining = initLobbyTime,
            GameTimeRemaining = initGameCountdownTime,
            ReturnTimeRemaining = initReturnTime,
        },
        Replication = "All",
    })
end

function GameManagerService:SetupPreGameCountdown()
    self.gameTime = initGameCountdownTime
    self.gameTimer = Timer.new(1)

    self.gameTimer.Tick:Connect(function()
        self.gameTime -= 1
        self.TimerReplica:SetValue({ "GameTimeRemaining" }, self.gameTime)
        print(self.gameTime)

        if self.gameTime <= 0 then
            self.gameTimer:Stop()
            self.OnPreGameTimerEnd:Fire()
            self:StartMainGameTimer()
        end
    end)
end

function GameManagerService:StartPreGameTimer()
    if not self.gameTimer then
        self:SetupPreGameCountdown()
    end
    if not self.gameTimer:IsRunning() then
        self.gameTimer:Start()
    end
end

function GameManagerService:StartMainGameTimer()
	self.mainGameTime = initMainGameTime
	self.mainGameTimer = Timer.new(0.01) -- tick every 10ms

	self.mainGameTimer.Tick:Connect(function()
		self.mainGameTime -= 0.01
		self.TimerReplica:SetValue({ "GameTimeRemaining" }, self.mainGameTime)

		if self.mainGameTime <= 0 then
			self.mainGameTimer:Stop()
			self.OnGameTimerEnd:Fire()
		end
	end)

	self.mainGameTimer:Start()
end



function GameManagerService:StopAllTimers()
    if self.gameTimer and self.gameTimer:IsRunning() then
        self.gameTimer:Stop()
    end
    if self.mainGameTimer and self.mainGameTimer:IsRunning() then
        self.mainGameTimer:Stop()
    end
end

function GameManagerService:KnitStart()
    self:InitReplicas()
    self:StartPreGameTimer()
end

function GameManagerService:KnitInit()
end

return GameManagerService
