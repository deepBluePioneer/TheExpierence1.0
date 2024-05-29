local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local CustomPackages = ReplicatedStorage.CustomPackages
local Players = game:GetService("Players")
local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local FastCastFolder = CustomPackages.FastCastFolder
local FastCast = require(FastCastFolder.FastCastRedux)

local partcache = require(Packages.partcache)

local WeaponsService = Knit.CreateService {
    Name = "WeaponsService",
    Client = {},
}

local castParams
local castBehavior
local caster
local bulletCache

local function OnRayHit(cast, result, velocity, bullet)
    local hit = result.Instance
    -- Check if the hit object is tagged with "boil"
    if CollectionService:HasTag(hit, "boil") then
        -- print(hit.Name .. " is tagged with 'boil'")
    end
    -- Return the bullet part to the cache
    bulletCache:ReturnPart(bullet)
end

local function OnRayUpdated(cast, segmentOrigin, segmentDirection, length, velocity, bullet)
    -- Update the bullet's CFrame to move it along the cast path
    bullet.CFrame = CFrame.new(segmentOrigin, segmentOrigin + segmentDirection) * CFrame.new(0, 0, -length / 2)

    -- Example: Adjust bullet transparency based on velocity
    local speed = velocity.Magnitude
    bullet.Transparency = math.clamp(1 - (speed / 300), 0, 1) -- Adjust transparency based on speed (assuming 500 is the max speed)
end


function WeaponsService:KnitInit()
    -- Add service initialization logic here

    FastCast.VisualizeCasts = false
    caster = FastCast.new()

    -- Configure FastCast behavior to interact with tagged items
    castParams = RaycastParams.new()
    castParams.FilterType = Enum.RaycastFilterType.Exclude
    castParams.IgnoreWater = true

    castBehavior = FastCast.newBehavior()
    castBehavior.RaycastParams = castParams
    castBehavior.AutoIgnoreContainer = false

    caster.RayHit:Connect(function(cast, result, velocity)
        OnRayHit(cast, result, velocity, cast.UserData)
    end)
    
    caster.LengthChanged:Connect(function(cast, segmentOrigin, segmentDirection, length, velocity)
        OnRayUpdated(cast, segmentOrigin, segmentDirection, length, velocity, cast.UserData)
    end)

     -- Create a bullet part for the cache
     local bulletTemplate = Instance.new("Part")
     bulletTemplate.Shape = Enum.PartType.Ball -- Make it a ball shape
     bulletTemplate.Size = Vector3.new(5, 5, 5) -- Slightly bigger size
     bulletTemplate.Material = Enum.Material.Neon
     bulletTemplate.BrickColor = BrickColor.new("Bright red")
     bulletTemplate.Anchored = true
     bulletTemplate.CanCollide = false


    bulletCache = partcache.new(bulletTemplate, 100)
end

function WeaponsService:KnitStart()
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

function WeaponsService.Client:SendRay(player, rayData, vehiclePrimaryPart, speed)
    local origin = rayData.origin
    local direction = rayData.direction

    -- Exclude the player character and vehicle's primary part
    table.insert(castParams.FilterDescendantsInstances, vehiclePrimaryPart)
    local vehicleVelocity = vehiclePrimaryPart.AssemblyLinearVelocity
    local initialVelocity = (direction.Unit * 300) + vehicleVelocity

    -- Calculate the direction vector with the desired speed
    local directionWithSpeed = direction.Unit

    -- Get a bullet part from the cache
    local bullet = bulletCache:GetPart()
    bullet.Parent = workspace

    -- Set the bullet part in the cast's UserData
    local newCast = caster:Fire(origin, directionWithSpeed, initialVelocity.Magnitude, castBehavior)
    newCast.UserData = bullet
end

return WeaponsService
