local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

-- Replica Modules
local Replica = CustomPackages.Replica
local ReplicaService = require(Replica.ReplicaService)

local Signal = require(Packages.Signal)
local Timer = require(Packages.timer)

-- Configurable durations
local initLobbyTime = 10
local initGameCountdownTime = 5 -- short pre-game countdown
local initMainGameTime = 1 * 60 -- 1 minute
local initReturnTime = 60

local GameManagerService = Knit.CreateService {
    Name = "GameManagerService",
    Client = {},
    OnGameTimerEnd = Signal.new(),
    OnPreGameTimerEnd = Signal.new()
}

-- === Initialize Replica ===
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

-- === Pregame Setup ===
function GameManagerService:SetupPreGameCountdown()
    self.gameTime = initGameCountdownTime

    -- Destroy old timer if it exists
    if self.gameTimer then
        self.gameTimer:Stop()
        self.gameTimer = nil
    end

    self.gameTimer = Timer.new(1)

    self.gameTimer.Tick:Connect(function()
        self.gameTime -= 1
        self.TimerReplica:SetValue({ "GameTimeRemaining" }, self.gameTime)
        print("[Pregame Tick]", self.gameTime)

        if self.gameTime <= 0 then
            self.gameTimer:Stop()
            self.OnPreGameTimerEnd:Fire()
            self:StartMainGameTimer()
        end
    end)
end

function GameManagerService:StartPreGameTimer()
    self:SetupPreGameCountdown()
    self.gameTimer:Start()
end

-- === Main Game Timer ===
function GameManagerService:StartMainGameTimer()
    self.mainGameTime = initMainGameTime

    if self.mainGameTimer then
        self.mainGameTimer:Stop()
        self.mainGameTimer = nil
    end

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

-- === Phase Restart ===
function GameManagerService:RestartPreGamePhase()
    self:StopAllTimers()

    -- Reset replica values
    self.TimerReplica:SetValue({ "GameTimeRemaining" }, initGameCountdownTime)
    self.TimerReplica:SetValue({ "TimeRemaining" }, initLobbyTime)
    self.TimerReplica:SetValue({ "ReturnTimeRemaining" }, initReturnTime)

    self:StartPreGameTimer()
end

-- === Stop All Timers ===
function GameManagerService:StopAllTimers()
    if self.gameTimer then
        self.gameTimer:Stop()
        self.gameTimer = nil
    end

    if self.mainGameTimer then
        self.mainGameTimer:Stop()
        self.mainGameTimer = nil
    end
end

-- === Knit Lifecycle ===
function GameManagerService:KnitInit()
    -- No-op for now
end

function GameManagerService:KnitStart()
    self:InitReplicas()
    self:StartPreGameTimer()
end

return GameManagerService
