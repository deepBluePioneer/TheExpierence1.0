local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local AmbienceService = Knit.CreateService {
    Name = "AmbienceService",
    Client = {
        Start = Knit.CreateSignal(),  -- :Fire(player, {key=..., parentPath=..., volume=..., useReverb=true})
        Stop  = Knit.CreateSignal(),  -- :Fire(player, {})
        SetLowpass = Knit.CreateSignal(), -- optional mood toggle
    },
}

function AmbienceService:StartForPlayer(player: Player, opts)
    self.Client.Start:Fire(player, opts or {})
end

function AmbienceService:StopForPlayer(player: Player)
    self.Client.Stop:Fire(player, {})
end

function AmbienceService:BroadcastStart(opts)
    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
        self.Client.Start:Fire(p, opts or {})
    end
end

function AmbienceService:BroadcastStop()
    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
        self.Client.Stop:Fire(p, {})
    end
end

function AmbienceService:SetLowpassForPlayer(player: Player, enabled: boolean)
    self.Client.SetLowpass:Fire(player, {enabled = enabled})
end

return AmbienceService
