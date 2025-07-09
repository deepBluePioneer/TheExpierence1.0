local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local CustomPackages = ReplicatedStorage.CustomPackages
local Players = game:GetService("Players")
local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local partcache = require(Packages.partcache)

local FastCastFolder = CustomPackages.FastCastFolder
local FastCast = require(FastCastFolder.FastCastRedux)

local WeaponsService = Knit.CreateService {
    Name = "WeaponsService",
    Client = {
        RayHit = Knit.CreateSignal()
    },
}

local castParams
local castBehavior
local caster
local bulletCache
local activeCasts = {}

local function OnRayHit(cast, result, velocity)
    local hit = result.Instance
    local hitPosition = result.Position
    local hitNormal = result.Normal
      -- Remove the cast from active casts
    activeCasts[cast] = nil
    -- Handle visual and other effects on hit
   -- WeaponsService.Client.RayHit:Fire(cast.UserData.Player, hit, hitPosition, hitNormal)
end

local function initPool()

    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local bulletFireEvent = Instance.new("UnreliableRemoteEvent")
    bulletFireEvent.Name = "BulletFireEvent"
    bulletFireEvent.Parent = ReplicatedStorage

    local bulletTemplate = Instance.new("Part")
    bulletTemplate.Transparency = 1
    bulletTemplate.Shape = Enum.PartType.Ball
    bulletTemplate.Size = Vector3.new(5, 5, 5)
    bulletTemplate.Material = Enum.Material.Neon
    bulletTemplate.BrickColor = BrickColor.new("Bright blue")
    bulletTemplate.Anchored = true
    bulletTemplate.CanCollide = false

    bulletCache = partcache.new(bulletTemplate, 200)

    FastCast.VisualizeCasts = true

    caster = FastCast.new()
   
    castParams = RaycastParams.new()
    castParams.FilterType = Enum.RaycastFilterType.Exclude
    castParams.IgnoreWater = true

    castBehavior = FastCast.newBehavior()
    castBehavior.RaycastParams = castParams
    castBehavior.AutoIgnoreContainer = false

    caster.RayHit:Connect(function(cast, result, velocity)
        OnRayHit(cast, result, velocity)
    end)
    
    caster.LengthChanged:Connect(function(cast, lastPoint, rayDir, displacement, segmentVelocity)
        local bullet = cast.UserData.Bullet
        if bullet then
            local newPoint = lastPoint + (rayDir * displacement)
            bullet.CFrame = CFrame.new(newPoint, newPoint + rayDir)
        end
    end)

    bulletFireEvent.OnServerEvent:Connect(function(player, rayData, vehiclePrimaryPart)
        self:HandleBulletFiring(player, rayData, vehiclePrimaryPart)
    end)

    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
            -- Player added logic
        end,
        function(LeavingPlayer)
            -- Player leaving logic
        end,
        function(Player, Character)
            castParams.FilterDescendantsInstances = {Character}
        end
    )
end

function WeaponsService:KnitInit()

    

  
end

function WeaponsService:KnitStart()
 
end

--[[

function WeaponsService.Client:SendRay(player, rayData, vehiclePrimaryPart)
    local origin = rayData.origin
    local direction = rayData.direction

    table.insert(castParams.FilterDescendantsInstances, vehiclePrimaryPart)
    local vehicleVelocity = vehiclePrimaryPart.AssemblyLinearVelocity
    local initialVelocity = (direction.Unit * 250) + vehicleVelocity

    -- Create the bullet part on the server
    local bullet = bulletCache:GetPart()
    bullet.CFrame = CFrame.new(origin)
    bullet.Parent = workspace

    -- Fire the ray and associate the bullet part with the cast
    local newCast = caster:Fire(origin, direction.Unit, initialVelocity.Magnitude, castBehavior)
    newCast.UserData = {
        Player = player,
        Bullet = bullet
    }
end

]]


function WeaponsService:AdvanceCast(rayData, cast, timeElapsed)
    local totalDistance = cast:GetVelocity().Magnitude * timeElapsed
    local origin = rayData.origin
    local direction = rayData.direction

    local newOrigin = origin + direction * totalDistance

    cast:SetPosition(newOrigin)
end

function WeaponsService:HandleBulletFiring(player, rayData, vehiclePrimaryPart)
    local origin = rayData.origin
    local direction = rayData.direction

    table.insert(castParams.FilterDescendantsInstances, vehiclePrimaryPart)
    local vehicleVelocity = vehiclePrimaryPart.AssemblyLinearVelocity
    local initialVelocity = (direction.Unit * 200) + vehicleVelocity

    -- Create the bullet part on the server
    local bullet = bulletCache:GetPart()
    bullet.CFrame = CFrame.new(origin)
    bullet.Parent = workspace
    local timestamp = rayData.timestamp  -- Get timestamp from client

    -- Fire the ray and associate the bullet part with the cast
    local newCast = caster:Fire(origin, direction.Unit, initialVelocity.Magnitude, castBehavior)
    newCast.UserData = {
        Player = player,
        Bullet = bullet,
        Timestamp = timestamp,
        origin = origin,
        Destination = direction
    }
    -- Add the cast to the active casts table
    activeCasts[newCast] = newCast.UserData

     -- Calculate time difference and advance the cast
     local currentTime = tick()
     local timeElapsed = currentTime - timestamp
     WeaponsService:AdvanceCast(rayData, newCast, timeElapsed)
end

return WeaponsService
