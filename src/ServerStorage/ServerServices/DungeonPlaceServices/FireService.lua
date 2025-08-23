local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Knit = require(ReplicatedStorage.Packages:WaitForChild("Knit"))
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

local FireService = Knit.CreateService {
    Name = "FireService",
    Client = {},
}

local gridSpacing = 8
local spreadSpeed = 0.05

-- Create flame particle emitter
local function createFireParticle()
    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxassetid://81891992819736"
    emitter.Rate = 15
    emitter.Lifetime = NumberRange.new(2, 3)
    emitter.Speed = NumberRange.new(4, 7)
    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1.2),
        NumberSequenceKeypoint.new(1, 0)
    })
    emitter.Color = ColorSequence.new(Color3.fromRGB(255, 140, 0))
    emitter.LightEmission = 1
    emitter.VelocitySpread = 50
    emitter.LockedToPart = false
    return emitter
end

local function spawnFireNode(pos, parent)
    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Size = Vector3.new(3, 1, 3)
    part.Position = pos + Vector3.new(0, 1, 0)
    part.Transparency = 1
    part.Name = "FireNode"
    part.Parent = parent

    createFireParticle().Parent = part
end

function FireService:SpreadFireInZone(zone)
    local burnedFolder = Instance.new("Folder")
    burnedFolder.Name = "FireZone_" .. tostring(zone)
    burnedFolder.Parent = Workspace

    local burnedSet = {}
    local openSet = {}

    local function gridKey(pos)
        local x = math.floor(pos.X / gridSpacing + 0.5)
        local z = math.floor(pos.Z / gridSpacing + 0.5)
        return x .. "," .. z
    end

    local function addToSpreadQueue(pos)
        local key = gridKey(pos)
        if not burnedSet[key] and zone:findPoint(pos) then
            table.insert(openSet, pos)
            burnedSet[key] = true
            spawnFireNode(pos, burnedFolder)
        end
    end

    -- Seed with multiple points
    for _ = 1, 3 do
        local seed = zone:getRandomPoint()
        if seed then
            addToSpreadQueue(seed)
        end
    end

    -- Spread loop
    task.spawn(function()
        while #openSet > 0 do
            local current = table.remove(openSet, 1)

            for _, offset in ipairs({
                Vector3.new(gridSpacing, 0, 0),
                Vector3.new(-gridSpacing, 0, 0),
                Vector3.new(0, 0, gridSpacing),
                Vector3.new(0, 0, -gridSpacing),
            }) do
                local neighbor = current + offset
                addToSpreadQueue(neighbor)
            end

            task.wait(spreadSpeed)
        end
    end)
end

function init()
    for _, zonePart in ipairs(CollectionService:GetTagged("fireZone")) do
        local zone = Zone.new(zonePart)
        self:SpreadFireInZone(zone)
    end
end

function FireService:KnitStart()
    
end

function FireService:KnitInit() end

return FireService
