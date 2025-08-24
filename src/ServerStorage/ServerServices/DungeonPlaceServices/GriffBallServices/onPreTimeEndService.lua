local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")

local OnPreTimeEndService = Knit.CreateService {
    Name = "OnPreTimeEndService",
    Client = {},
}

function OnPreTimeEndService:KnitStart()
    local GameManagerService = Knit.GetService("GameManagerService")

    GameManagerService.OnPreGameTimerEnd:Connect(function()
        print("[OnPreTimeEndService] Pre-game timer ended! Signal received.")
        self:DisableBarricades()
    end)
end

function OnPreTimeEndService:DisableBarricades()
    local barricades = CollectionService:GetTagged("barricade")

    for _, model in ipairs(barricades) do
        if model:IsA("Model") then
            for _, part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                    part.Transparency = 1
                end
            end
        elseif model:IsA("BasePart") then
            model.CanCollide = false
            model.Transparency = 1
        end
    end

    print("[OnPreTimeEndService] Disabled all barricades.")
end

function OnPreTimeEndService:KnitInit()
    -- Optional init logic
end

return OnPreTimeEndService
