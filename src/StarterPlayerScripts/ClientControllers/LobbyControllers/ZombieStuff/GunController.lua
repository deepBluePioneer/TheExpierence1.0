-- Client/Controllers/GunController.lua

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Knit = require(ReplicatedStorage.Packages.Knit)

local LocalPlayer = Players.LocalPlayer

local GunController = Knit.CreateController {
    Name = "GunController"
}

-- ===== CONFIG =====
GunController.fireRate = 0.15 -- seconds per shot (increase to slow down)
GunController.isFiring = false
GunController.lastFireTime = 0
GunController.fireConnection = nil
GunController.forwardOffset = 5 -- push origin a bit forward to avoid self-hit

-- === Audio helper ===
local function playRandomMachineGunShotAt(origin: Vector3)
    local group = SoundService:FindFirstChild("SoundGroup_MachineGun")
    if not group then return end

    -- Collect only Sound children
    local pool = {}
    for _, child in ipairs(group:GetChildren()) do
        if child:IsA("Sound") then
            table.insert(pool, child)
        end
    end
    if #pool == 0 then return end

    -- Choose one and clone so multiple shots can overlap
    local chosen: Sound = pool[math.random(1, #pool)]:Clone()

    -- 3D: anchor the sound at the muzzle/origin using an Attachment
    local att = Instance.new("Attachment")
    att.WorldPosition = origin
    att.Parent = workspace.Terrain -- safe parent for world attachments

    chosen.Parent = att
    chosen.RollOffMaxDistance = chosen.RollOffMaxDistance -- (touch to ensure property replication)
    chosen:Play()

    -- Cleanup when done (fallback in case Ended doesn't fire)
    chosen.Ended:Connect(function()
        if att and att.Parent then att:Destroy() end
    end)
    Debris:AddItem(att, (chosen.TimeLength > 0 and chosen.TimeLength or 1.5) + 0.25)
end

-- Origin/direction strictly from HRP look
function GunController:GetShotFromLook()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local origin    = hrp.Position + hrp.CFrame.LookVector * self.forwardOffset
    local direction = hrp.CFrame.LookVector -- keep original behavior
    return origin, direction
end

function GunController:FireOnce()
    local origin, direction = self:GetShotFromLook()
    if origin and direction then
        self.GunService.FireGunSignal:Fire(origin, direction)
        playRandomMachineGunShotAt(origin) -- 🔊 play local random shot
    end
end

function GunController:StartAutomaticFiring()
    if self.isFiring then return end
    self.isFiring = true
    self.lastFireTime = 0

    self.fireConnection = RunService.RenderStepped:Connect(function()
        if not self.isFiring then return end
        local now = tick()
        if (now - self.lastFireTime) >= self.fireRate then
            self:FireOnce()
            self.lastFireTime = now
        end
    end)
end

function GunController:StopAutomaticFiring()
    self.isFiring = false
    if self.fireConnection then
        self.fireConnection:Disconnect()
        self.fireConnection = nil
    end
end

function GunController:KnitStart()
    self.GunService = Knit.GetService("GunService")

    -- LMB hold to auto-fire
    local function handlePrimary(_, state)
        if state == Enum.UserInputState.Begin then
            self:StartAutomaticFiring()
        elseif state == Enum.UserInputState.End then
            self:StopAutomaticFiring()
        end
        return Enum.ContextActionResult.Sink
    end
    ContextActionService:BindAction("AutoFire_LMB", handlePrimary, false, Enum.UserInputType.MouseButton1)

    -- Safety stops
    UserInputService.WindowFocusReleased:Connect(function()
        self:StopAutomaticFiring()
    end)
    Players.LocalPlayer.CharacterAdded:Connect(function(char)
        task.spawn(function()
            local hum = char:WaitForChild("Humanoid", 10)
            if hum then
                hum.Died:Connect(function() self:StopAutomaticFiring() end)
            end
        end)
    end)
end

return GunController
