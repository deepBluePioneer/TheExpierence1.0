local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage.CustomPackages

local Knit = require(Packages.Knit)
local ReplicaService = require(CustomPackages.Replica.ReplicaService)
local Timer = require(Packages.timer)

local GameRoundManagerService = Knit.CreateService {
    Name = "GameRoundManagerService",
    Client = {},
}

local ROUND_TIME = 5 * 60 -- 5 minutes in seconds

function GameRoundManagerService:InitReplica()
    self.TimerReplica = ReplicaService.NewReplica({
        ClassToken = ReplicaService.NewClassToken("GameTimerReplica"),
        Data = {
            TimeRemaining = ROUND_TIME,
            FormattedTime = self:FormatTime(ROUND_TIME),
        },
        Replication = "All",
    })
end

function GameRoundManagerService:StartTimer()
    self.CurrentTime = ROUND_TIME

    self.RoundTimer = Timer.new(1) -- Tick every second
    self.RoundTimer.Tick:Connect(function()
        self:OnTimerTick()
    end)

    self.RoundTimer:Start()
end

function GameRoundManagerService:OnTimerTick()
    self.CurrentTime = self.CurrentTime - 1

    self.TimerReplica:SetValue({"TimeRemaining"}, self.CurrentTime)
    self.TimerReplica:SetValue({"FormattedTime"}, self:FormatTime(self.CurrentTime))
   -- print("Current Time: " .. self:FormatTime(self.CurrentTime))

    if self.CurrentTime <= 0 then
        self.RoundTimer:Stop()
        print("Round timer ended.")
        -- You can fire an event here to handle end-of-round logic
    end
end

function GameRoundManagerService:FormatTime(totalSeconds)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return string.format("%02d:%02d", minutes, seconds)
end

function GameRoundManagerService:KnitInit()
    self:InitReplica()
end

function GameRoundManagerService:KnitStart()
    self:StartTimer()
end

return GameRoundManagerService