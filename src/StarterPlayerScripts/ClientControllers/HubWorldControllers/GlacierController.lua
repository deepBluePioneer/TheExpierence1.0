local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Terrain = workspace:WaitForChild("Terrain")
local Packages = ReplicatedStorage.Packages
local Gizmo = require(Packages.imgizmo)
local CustomPackages = ReplicatedStorage.CustomPackages

-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local Knit = require(Packages.Knit)

local GlacierController = Knit.CreateController { Name = "GlacierController" }

-- Function to calculate buoyant force
local function calculateBuoyantForce(part, waterLevel, fluidDensity)
    local gravity = workspace.Gravity
    local submergedHeight = math.max(0, math.min(waterLevel - (part.Position.Y - part.Size.Y / 2), part.Size.Y))
    local submergedVolume = submergedHeight * part.Size.X * part.Size.Z
    local buoyantForceMagnitude = fluidDensity * gravity * submergedVolume
    return Vector3.new(0, buoyantForceMagnitude, 0)
end

-- Function to get the water height at a specific position
local function getWaterHeight(position)
    -- Set color properties for the gizmo
    Gizmo.PushProperty("Color3", Color3.new(0.403921, 0.082352, 1))
    Gizmo.PushProperty("AlwaysOnTop", true)
    Gizmo.PushProperty("Transparency", .25)
    
    local size = Vector3.new(4, 4, 4) -- A small region around the object
    local min = position - (size / 2)
    local max = position + (size / 2)
    
    local region = Region3.new(min, max):ExpandToGrid(4)

    local materials = Terrain:ReadVoxels(region, 4)[1][1][1]
    if materials == Enum.Material.Water then
        return region.CFrame.Position.Y -- Calculate the height of the water voxel
    end

    return nil
end

function init()

    Gizmo.Init()
    local fluidDensity = 1 -- Density of water (can be adjusted)
    local glaciers = CollectionService:GetTagged("glacier") -- Fetch glaciers each frame in case new ones are added

    -- Continuously apply buoyant forces to all glaciers
    RunService.Stepped:Connect(function(_, dt)
        for _, glacier in pairs(glaciers) do
            local primaryPart = glacier
            local waterLevel = getWaterHeight(primaryPart.Position)
            if waterLevel then
                local buoyantForce = calculateBuoyantForce(primaryPart, waterLevel, fluidDensity)
                primaryPart:ApplyImpulse(buoyantForce * dt)

                -- Add AlignOrientation to stabilize orientation with damping
                local alignOrientation = primaryPart:FindFirstChild("AlignOrientation")
                if not alignOrientation then
                    local attachment0 = Instance.new("Attachment", primaryPart)
                    local attachment1 = Instance.new("Attachment", primaryPart)

                    alignOrientation = Instance.new("AlignOrientation")
                    alignOrientation.Attachment0 = attachment0
                    alignOrientation.Attachment1 = attachment1
                    alignOrientation.RigidityEnabled = false -- Use damping
                    alignOrientation.Responsiveness = 10 -- Adjust as needed for smoother damping
                    alignOrientation.MaxTorque = 1000 -- Adjust to limit torque and apply smoother motion
                    alignOrientation.MaxAngularVelocity = 10 -- Limit the angular velocity for damping effect
                    alignOrientation.AlignType = Enum.AlignType.PrimaryAxisParallel -- Only align primary axes
                    alignOrientation.PrimaryAxis = Vector3.new(0, 1, 0) -- Y-axis alignment
                    alignOrientation.Parent = primaryPart
                end
            end
        end
    end)
    
end
-- Function to apply a force to push the glacier away from the item
local function applyPushForce(glacier, item)
    if glacier and item then
        local direction = (glacier.Position - item.Position).Unit
        local forceMagnitude = 50000000 -- Adjust this value as needed
        local force = direction * forceMagnitude
        glacier:ApplyImpulse(force)
    end
end
function GlacierController:KnitStart()
    local glaciers = CollectionService:GetTagged("glacier") -- Fetch glaciers each frame in case new ones are added

    -- Create a zone for each glacier and track it
    for _, glacier in pairs(glaciers) do
        local zone = Zone.new(glacier)

        zone.itemEntered:Connect(function(item)
            print(("%s entered the zone of %s!"):format(item.Name, glacier.Name))
            applyPushForce(glacier, item) -- Apply force to push the glacier away from the item
        end)
        
        zone.itemExited:Connect(function(item)
            print(("%s exited the zone of %s!"):format(item.Name, glacier.Name))
        end)
        
        -- Example: Track an additional item if needed
        zone:trackItem(workspace.boat_1.PrimaryPart)
    end
end


function GlacierController:KnitInit()
    -- Add any initialization logic here
end

return GlacierController
