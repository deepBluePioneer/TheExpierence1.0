local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local PatchesModule = require(ReplicatedStorage.Source.PatchesModule)

local currentVehicleModel


local ItemController = Knit.CreateController {
    Name = "ItemController",
    Client = {},
}

-- Function to create a patch part
local function createPatchPart(patchName)
    local patch = PatchesModule.Patches[patchName]
    if not patch then
        warn("No patch found with name: " .. patchName)
        return nil
    end
    
    local part = Instance.new("Part")
    part.Name = patchName
    part.Size = Vector3.new(4, 4, 4) -- Set size to 4x4x4 for the cube
    part.Anchored = true
    part.CanCollide = false
    part.Color = patch.Color -- Use the color defined in the patch
    part.Position = Vector3.new(math.random(-50, 50), 5, math.random(-50, 50)) -- Set a random initial position

    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(4, 0, 4, 0)
    billboardGui.StudsOffset = Vector3.new(0, 4, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Adornee = part

    local imageLabel = Instance.new("ImageLabel", billboardGui)
    imageLabel.Size = UDim2.new(1, 0, 1, 0)
    imageLabel.Image = "rbxassetid://" .. patch.SpriteID
    imageLabel.BackgroundTransparency = 1

    billboardGui.Parent = part
    part.Parent = Workspace

    -- Create a zone for the part
    local zone = Zone.new(part)



    -- Set up zone entered and exited events
    zone.playerEntered:Connect(function(player)
        print(player.Name .. " entered the zone for " .. patchName)
        Knit.GetService("ItemService").ApplyPatchToPlayer(player, patchName, currentVehicleModel)

        -- Add logic to apply the patch to the player's vehicle here
    end)

    zone.playerExited:Connect(function(player)
        print(player.Name .. " exited the zone for " .. patchName)
        -- Add logic to remove the patch from the player's vehicle here, if applicable
    end)

    -- Function to create a bobbing effect
    local function createBobbingEffect(part)
        local initialPosition = part.Position
        local bobbingHeight = 3.5
        local bobbingTime = 0.75

        local function bob()
            local goal = {Position = initialPosition + Vector3.new(0, bobbingHeight, 0)}
            local tweenInfo = TweenInfo.new(bobbingTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
            local tween = TweenService:Create(part, tweenInfo, goal)
            tween:Play()
        end

        bob()
    end

    -- Start the bobbing effect with a slight delay
    delay(math.random(), function()
        createBobbingEffect(part)
    end)
    
    return part, zone
end

function ItemController:KnitStart()



    local VehicleService = Knit.GetService("VehicleService")

    VehicleService.SeatOccupied:Connect(function(vehicleModel)
        currentVehicleModel = vehicleModel
    end)

    VehicleService.SeatEjected:Connect(function()
    end)

    for patchName, _ in pairs(PatchesModule.Patches) do
        createPatchPart(patchName)
    end
   

end

function ItemController:KnitInit()
    -- Add service initialization logic here
end

return ItemController
