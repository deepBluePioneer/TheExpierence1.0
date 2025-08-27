local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local IkConfigService = Knit.CreateService {
    Name = "IkConfigService",
    Client = {},
}

-- ===== Helpers =====
local function isR15(character: Model): boolean
    return character:FindFirstChild("UpperTorso") ~= nil or character:FindFirstChild("RightHand") ~= nil
end

local function getArmChain(character: Model, side: "Right" | "Left")
    if isR15(character) then
        return character:FindFirstChild(side .. "UpperArm"), character:FindFirstChild(side .. "Hand")
    else
        return character:FindFirstChild("Torso"), character:FindFirstChild(side .. " Arm")
    end
end

local function ensureAttachment(parent: Instance, name: string, cf: CFrame): Attachment
    local att = parent:FindFirstChild(name)
    if not att then
        att = Instance.new("Attachment")
        att.Name = name
        att.Parent = parent
    end
    att.CFrame = cf
    return att
end

local function ensureHandTarget(hrp: BasePart, side: "Right" | "Left"): Attachment
    local x = (side == "Right") and 0.4 or -0.4
    local y = 0.6
    local z = -1.5
    return ensureAttachment(hrp, "HandTarget_" .. side, CFrame.new(x, y, z))
end

local function makeOutwardPole(hrp: BasePart, side: "Right" | "Left"): Attachment
    local lateral = (side == "Right") and 1.0 or -1.0
    local up = 0.6
    local forward = 0.4
    return ensureAttachment(hrp, "HandPole_" .. side, CFrame.new(lateral, up, -forward))
end

local function moveHandInFront(character: Model, side: "Right" | "Left")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not (humanoid and hrp) then return end

    local chainRoot, endEffector = getArmChain(character, side)
    if not (chainRoot and endEffector) then return end

    local target = ensureHandTarget(hrp, side)
    local pole = makeOutwardPole(hrp, side)

    local ikName = side .. "HandIK"
    local ik = humanoid:FindFirstChild(ikName)
    if not ik then
        ik = Instance.new("IKControl")
        ik.Name = ikName
        ik.Type = Enum.IKControlType.Position
        ik.ChainRoot = chainRoot
        ik.EndEffector = endEffector
        ik.Parent = humanoid
    end

    ik.Target = target
    ik.Pole = pole
    ik.SmoothTime = 0.06
    ik.Priority = 1
    ik.Weight = 1
    ik.Enabled = true
end

local function cleanupHandIK(character: Model, side: "Right" | "Left")
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if humanoid then
        local ik = humanoid:FindFirstChild(side .. "HandIK")
        if ik then
            ik:Destroy()
        end
    end

    if hrp then
        local target = hrp:FindFirstChild("HandTarget_" .. side)
        local pole = hrp:FindFirstChild("HandPole_" .. side)
        if target then target:Destroy() end
        if pole then pole:Destroy() end
    end
end

-- ===== Knit lifecycle =====
function IkConfigService:KnitStart() end

function IkConfigService:KnitInit()
    local BombSpawnService = Knit.GetService("BombSpawnService")

    BombSpawnService.BombSpawned:Connect(function(bombModel)
        print("[IkConfigService] Bomb spawned:", bombModel)
    end)

    BombSpawnService.BombPickedUp:Connect(function(player, bombModel)
        print("[IkConfigService] Bomb picked up by", player.Name)
        local char = player.Character
        if char then
           -- moveHandInFront(char, "Right")
        end
    end)

    if BombSpawnService.BombDropped then
        BombSpawnService.BombDropped:Connect(function(player, bombModel)
            print("[IkConfigService] Bomb dropped by", player.Name)
            local char = player.Character
            if char then
               -- cleanupHandIK(char, "Right")
            end
        end)
    end

    if BombSpawnService.BombDestroyed then
        BombSpawnService.BombDestroyed:Connect(function()
            print("[IkConfigService] Bomb destroyed signal received")
            for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
                local char = player.Character
                if char then
                    cleanupHandIK(char, "Right")
                end
            end
        end)
    end
end

return IkConfigService
