-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

-- Packages
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

-- ZonePlus
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

-- Service Definition
local TornadoService = Knit.CreateService {
    Name = "TornadoService",
    Client = {},
}

-- Track players in the tornado
local playersInTornado = {}

-- Create upward vortex particle
local function createVortexParticleEmitter()
    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxassetid://6023426915" -- Change to a smoky or swirly texture
    emitter.Rate = 6
    emitter.Lifetime = NumberRange.new(8, 12)
    emitter.Speed = NumberRange.new(8, 15)
    emitter.VelocitySpread = 20
    emitter.EmissionDirection = Enum.NormalId.Top
    emitter.Size = NumberSequence.new(1)
    emitter.LightEmission = 0.5
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1)
    })
    emitter.Color = ColorSequence.new(Color3.fromRGB(80, 80, 80), Color3.fromRGB(150, 150, 150))
    return emitter
end

-- Create burst of debris near the bottom
local function createGroundDebrisEmitter()
    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxassetid://26356442" -- Small leaf/rock/dust
    emitter.Rate = 20
    emitter.Lifetime = NumberRange.new(2, 4)
    emitter.Speed = NumberRange.new(15, 25)
    emitter.EmissionDirection = Enum.NormalId.Top
    emitter.VelocitySpread = 360
    emitter.RotSpeed = NumberRange.new(100, 200)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8),
        NumberSequenceKeypoint.new(1, 0.3)
    })
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1)
    })
    emitter.Color = ColorSequence.new(Color3.fromRGB(120, 90, 60))
    return emitter
end

-- Create cone-shaped particle funnel
local function createTornadoFunnel(tornadoModel, position, height, baseRadius, segments)
    for i = 0, segments - 1 do
        local ratio = i / segments
        local radius = baseRadius * (0.3 + ratio) -- wider at the top
        local y = ratio * height
        local angleOffset = i * 25

        local part = Instance.new("Part")
        part.Name = "FunnelLayer"
        part.Shape = Enum.PartType.Cylinder
        part.Size = Vector3.new(radius * 2, 1, radius * 2)
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 1
        part.CFrame = CFrame.new(position + Vector3.new(0, y - height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
        part.Parent = tornadoModel

        local emitter = createVortexParticleEmitter()
        emitter.Speed = NumberRange.new(6 + ratio * 8, 10 + ratio * 12)
        emitter.Rotation = NumberRange.new(angleOffset, angleOffset + 30)
        emitter.Parent = part
    end
end

-- Create the full tornado and zone
function TornadoService:CreateTornado(position, height, baseRadius)
    local tornadoModel = Instance.new("Model")
    tornadoModel.Name = "Tornado"
    tornadoModel.Parent = Workspace

    -- Base invisible zone part (used for ZonePlus)
    local zonePart = Instance.new("Part")
    zonePart.Name = "TornadoZone"
    zonePart.Size = Vector3.new(baseRadius * 2, height, baseRadius * 2)
    zonePart.Anchored = true
    zonePart.CanCollide = false
    zonePart.Transparency = 1
    zonePart.CFrame = CFrame.new(position)
    zonePart.Parent = tornadoModel

    -- Ground burst emitter
    local groundBurst = Instance.new("Part")
    groundBurst.Name = "GroundBurst"
    groundBurst.Size = Vector3.new(4, 1, 4)
    groundBurst.Anchored = true
    groundBurst.CanCollide = false
    groundBurst.Transparency = 1
    groundBurst.Position = position - Vector3.new(0, height / 2 - 1, 0)
    groundBurst.Parent = tornadoModel

    createGroundDebrisEmitter().Parent = groundBurst

    -- Funnel
    createTornadoFunnel(tornadoModel, position, height, baseRadius, 16)

    -- ZonePlus detection
    local zone = Zone.new(zonePart)
    zone.playerEntered:Connect(function(player)
        print(player.Name .. " entered the tornado!")
        playersInTornado[player] = true
    end)
    zone.playerExited:Connect(function(player)
        print(player.Name .. " exited the tornado.")
        playersInTornado[player] = nil
    end)
 
end

-- Knit lifecycle
function TornadoService:KnitInit()
end

function TornadoService:KnitStart()
  --  self:CreateTornado(Vector3.new(0, 100, 0), 150, 40)
end

return TornadoService
