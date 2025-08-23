-- Services/TargetService.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit     = require(Packages.Knit)

local TargetService = Knit.CreateService {
    Name = "TargetService",
    Client = {
        -- Client reads these live (can be changed server-side later if you like)
        Threshold    = Knit.CreateProperty(0.80), -- dot product threshold (≈36.9° cone)
        MaxDistance  = Knit.CreateProperty(300),  -- studs
        TagRandom    = Knit.CreateProperty("randomGridCube"), -- tag to scan
    },
}

-- Optional: let client ask for the list (not required if client uses the tag directly)
function TargetService.Client:GetRandomCubes(player)
    return CollectionService:GetTagged(self.Server.Client.TagRandom:Get())
end

function TargetService:KnitInit() end
function TargetService:KnitStart() end

return TargetService
