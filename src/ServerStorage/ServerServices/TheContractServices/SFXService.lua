local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local SFXService = Knit.CreateService {
    Name = "SFXService",
    Client = {
        Play = Knit.CreateSignal(), -- :Fire(player, {key=..., parentPath=..., spatialize=true, volume=...})
    },
}

function SFXService:PlayForPlayer(player, opts) self.Client.Play:Fire(player, opts or {}) end
function SFXService:PlayForAll(opts)
    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
        self.Client.Play:Fire(p, opts or {})
    end
end

return SFXService
