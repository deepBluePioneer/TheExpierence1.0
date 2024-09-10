local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- Zone Modules
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local ZoneModule = require(ZoneRoot.Zone)

local ZoneService = Knit.CreateService {
    Name = "ZoneService",
    Client = {},
}

function ZoneService:KnitStart()
    -- Add service startup logic here

    -- Example 1: Detecting When a Player Enters or Leaves a Zone
    local zone1Part = workspace:WaitForChild("Zone1Part") -- A part representing the zone
    local zone1 = ZoneModule.new(zone1Part)

    zone1.playerEntered:Connect(function(player)
        print(player.Name .. " has entered Zone 1.")
    end)

    zone1.playerExited:Connect(function(player)
        print(player.Name .. " has left Zone 1.")
    end)

    -- Example 2: Triggering an Event When a Player Stays in the Zone for a Specific Time
    local stayTime = 5 -- Time in seconds

    zone1.playerEntered:Connect(function(player)
        print(player.Name .. " has entered Zone 1. Starting timer...")

        -- Start a timer to check if the player stays in the zone
        task.delay(stayTime, function()
            if zone1:findPlayer(player) then
                print(player.Name .. " has stayed in Zone 1 for " .. stayTime .. " seconds.")
                -- Trigger any event or reward the player here
            end
        end)
    end)

    -- Example 3: Creating a Safe Zone Where Players Can't Take Damage
    local safeZonePart = workspace:WaitForChild("SafeZonePart")
    local safeZone = ZoneModule.new(safeZonePart)

    safeZone.playerEntered:Connect(function(player)
        print(player.Name .. " has entered the safe zone.")
        -- Assuming the player has a "Humanoid" that tracks health
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:SetAttribute("InSafeZone", true)
        end
    end)

    safeZone.playerExited:Connect(function(player)
        print(player.Name .. " has left the safe zone.")
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:SetAttribute("InSafeZone", false)
        end
    end)

    -- Example: Check if the player can take damage based on the safe zone
    local function canTakeDamage(player)
        local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
        if humanoid and humanoid:GetAttribute("InSafeZone") then
            return false
        end
        return true
    end

    -- Example 4: Creating Multiple Zones and Checking Player Position
    local zone2Part = workspace:WaitForChild("Zone2Part")
    local zone2 = ZoneModule.new(zone2Part)

    local function checkPlayerZones(player)
        if zone1:findPlayer(player) then
            print(player.Name .. " is in Zone 1")
        elseif zone2:findPlayer(player) then
            print(player.Name .. " is in Zone 2")
        else
            print(player.Name .. " is not in any zone.")
        end
    end

    -- Hook up player movement checks
    zone1.playerEntered:Connect(checkPlayerZones)
    zone2.playerEntered:Connect(checkPlayerZones)
    zone1.playerExited:Connect(checkPlayerZones)
    zone2.playerExited:Connect(checkPlayerZones)

    -- Optionally, you can also check if a player is inside the zone
    for _, player in pairs(Players:GetPlayers()) do
        if zone1:findPlayer(player) then
            print(player.Name .. " is already inside Zone 1.")
        elseif zone2:findPlayer(player) then
            print(player.Name .. " is already inside Zone 2.")
        end
    end
end

function ZoneService:KnitInit()
    -- Add service initialization logic here
end

return ZoneService
