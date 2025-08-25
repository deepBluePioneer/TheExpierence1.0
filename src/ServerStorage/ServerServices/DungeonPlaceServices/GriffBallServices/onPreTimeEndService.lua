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

-- Save original transparency before hiding
function OnPreTimeEndService:DisableBarricades()
    local barricades = CollectionService:GetTagged("barricade")

    for _, model in ipairs(barricades) do
        if model:IsA("Model") then
            for _, part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") then
                    if not part:GetAttribute("InitialTransparency") then
                        part:SetAttribute("InitialTransparency", part.Transparency)
                    end
                    part.CanCollide = false
                    part.Transparency = 1
                end
            end
        elseif model:IsA("BasePart") then
            if not model:GetAttribute("InitialTransparency") then
                model:SetAttribute("InitialTransparency", model.Transparency)
            end
            model.CanCollide = false
            model.Transparency = 1
        end
    end

    print("[OnPreTimeEndService] Disabled all barricades.")
end

-- Restore original transparency
function OnPreTimeEndService:EnableBarricades()
    local barricades = CollectionService:GetTagged("barricade")

    for _, model in ipairs(barricades) do
        if model:IsA("Model") then
            for _, part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") then
                    local original = part:GetAttribute("InitialTransparency")
                    part.CanCollide = true
                    part.Transparency = original or 0
                end
            end
        elseif model:IsA("BasePart") then
            local original = model:GetAttribute("InitialTransparency")
            model.CanCollide = true
            model.Transparency = original or 0
        end
    end

    print("[OnPreTimeEndService] Re-enabled all barricades.")
end

function OnPreTimeEndService:KnitInit()
    -- Optional init logic
end

return OnPreTimeEndService
