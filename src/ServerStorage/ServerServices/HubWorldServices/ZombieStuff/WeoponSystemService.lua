-- Server/Services/WeoponSystemService.lua
--Brainrot Headhunter--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players          = game:GetService("Players")

local Packages       = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage.CustomPackages
local Knit           = require(Packages.Knit)

-- Prefabs/guns (no WaitForChild by request/style)
local Prefabs    = ReplicatedStorage.Prefabs
local GunsFolder = Prefabs and Prefabs.guns

local WeoponSystemService = Knit.CreateService {
    Name = "WeoponSystemService",
    Client = {},
}

-- ===== Helpers =====

local function getFirstGunTemplate()
    if not GunsFolder then
        warn("[WeoponSystemService] Prefabs.guns folder not found.")
        return nil
    end
    for _, child in ipairs(GunsFolder:GetChildren()) do
        if child:IsA("Model") and child.PrimaryPart then
            return child
        end
    end
    -- Fallback: accept first model and set a PrimaryPart if needed
    for _, child in ipairs(GunsFolder:GetChildren()) do
        if child:IsA("Model") then
            local bp = child:FindFirstChildWhichIsA("BasePart", true)
            if bp then
                child.PrimaryPart = bp
                return child
            end
        end
    end
    warn("[WeoponSystemService] No gun model with a PrimaryPart found in Prefabs.guns.")
    return nil
end

local function attachModelToHead(gunModel: Model, character: Model)
    -- R6 & R15 both have a "Head" BasePart
    local head = character:FindFirstChild("Head")
    if not (head and head:IsA("BasePart")) then
        warn("[WeoponSystemService] No Head on character:", character.Name)
        return
    end

    if not gunModel.PrimaryPart then
        local firstPart = gunModel:FindFirstChildWhichIsA("BasePart", true)
        if not firstPart then
            warn("[WeoponSystemService] Gun model has no BasePart:", gunModel.Name)
            return
        end
        gunModel.PrimaryPart = firstPart
    end

    gunModel.Name = "EquippedGun"
    gunModel.Parent = character

    -- Safe physics for attaching to character
    for _, d in ipairs(gunModel:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.Anchored = false
            d.Massless = true
        end
    end

    -- Position relative to the head:
    -- Slightly forward of the face and a bit down; tweak as needed for your asset
    local offset = CFrame.new(0, -0.25, -0.75) -- (X,Y,Z) from head center
    -- Optional: rotate the gun if its forward axis needs adjustment
    -- local rotate = CFrame.Angles(0, math.rad(90), 0)
    -- gunModel:PivotTo(head.CFrame * offset * rotate)
    gunModel:PivotTo(head.CFrame * offset)

    -- Weld the gun to the head so it follows head movement
    local weld = Instance.new("WeldConstraint")
    weld.Name = "GunWeld"
    weld.Part0 = head
    weld.Part1 = gunModel.PrimaryPart
    weld.Parent = head
end

local function equipGunToPlayer(player: Player)
    local character = player.Character
    if not character then return end

    -- Avoid duplicates on respawn
    if character:FindFirstChild("EquippedGun") then return end

    local template = getFirstGunTemplate()
    if not template then return end

    local clone = template:Clone()
    attachModelToHead(clone, character)
end

-- ===== Knit lifecycle =====

function WeoponSystemService:KnitStart()
    -- Equip on player joins / respawns
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            task.defer(function()
                equipGunToPlayer(player)
            end)
        end)

        -- Studio play-solo case: character may already exist
        if player.Character then
            task.defer(function()
                equipGunToPlayer(player)
            end)
        end
    end)

    -- Also equip for any players already present (e.g., server hot reload)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then
            task.defer(function()
                equipGunToPlayer(plr)
            end)
        else
            plr.CharacterAdded:Connect(function()
                task.defer(function()
                    equipGunToPlayer(plr)
                end)
            end)
        end
    end
end

function WeoponSystemService:KnitInit()
    -- init if needed
end

return WeoponSystemService
