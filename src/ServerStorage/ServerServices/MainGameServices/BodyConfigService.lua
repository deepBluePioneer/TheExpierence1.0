local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local WALKER_TAG = "islanderWalker"

local BodyConfigService = Knit.CreateService {
    Name = "BodyConfigService",
    Client = {},
}

-- Helper: Removes Roblox default name label
local function removeNameDisplay(npcModel: Model)
    local hum = npcModel:FindFirstChildWhichIsA("Humanoid")
    if hum then
        hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        hum.NameDisplayDistance = 0
        hum.NameOcclusion = Enum.NameOcclusion.NoOcclusion -- optional
    end
end

function BodyConfigService:KnitStart()
    -- Handle NPCs that already exist
    for _, npc in ipairs(CollectionService:GetTagged(WALKER_TAG)) do
        if npc:IsA("Model") then
            removeNameDisplay(npc)
        end
    end

    -- Handle NPCs added later
    CollectionService:GetInstanceAddedSignal(WALKER_TAG):Connect(function(npc)
        if npc:IsA("Model") then
            removeNameDisplay(npc)
        end
    end)
end

function BodyConfigService:KnitInit()
    -- Nothing special here yet
end

return BodyConfigService
