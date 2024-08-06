local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local Vehicle = require(script.Parent.Vehicles.VehicleClass)
local StatDecorators = require(script.Parent.Vehicles.StatDecorators)

local PatchesModule = require(ReplicatedStorage.Source.PatchesModule)

-- Replica Modules



local VehicleService = Knit.CreateService {
    Name = "VehicleService",
    Client = {

        SeatOccupied = Knit.CreateSignal(), -- Define the signal
        SeatEjected = Knit.CreateSignal(), -- Define the signal


    },

}

VehicleService.Vehicles = {}



function VehicleService:PlayerLeft(LeavingPlayer)
    local vehicle = self.Vehicles[LeavingPlayer.UserId]
    if vehicle then
        vehicle:Destroy()
        self.Vehicles[LeavingPlayer.UserId] = nil
    end
end

local function createCustomVehicle(customStats)
    local vehicle = Vehicle.new()
    
    for stat, value in pairs(customStats) do
        if StatDecorators["Apply" .. stat] then
            StatDecorators["Apply" .. stat](vehicle, value)
        end
    end

    return vehicle
end

local function applyPatchToVehicle(vehicle, patchName)
    local patch = PatchesModule.Patches[patchName]
    if patch then
        if patch.Stat == "All" then
            for stat, _ in pairs(vehicle.Stats) do
                StatDecorators["Apply" .. stat](vehicle, patch.Value)
            end
        else
            if StatDecorators["Apply" .. patch.Stat] then
                StatDecorators["Apply" .. patch.Stat](vehicle, patch.Value)
            end
        end
    else
        warn("No patch found with name: " .. patchName)
    end
end


function  VehicleService:InitVehicle()
   
    
    -- Custom stats
    local customStats = {
        HP = 100,
        Boost = 0,
        Charge = 0,
        Turn = 0,
        Offense = 0,
        Defense = 0,
        Weight = 0,
        Glide = 0
    }


    -- Create the custom vehicle with the specified stats
    local customVehicle = createCustomVehicle(customStats)
    customVehicle.Model.Parent = Workspace
    local spawnPoint = Workspace:WaitForChild("SpawnLocation")
    customVehicle.Model:PivotTo(spawnPoint.CFrame)
    self.Vehicles["Custom"] = customVehicle -- Use "Custom" as a key for the custom vehicle

    -- Example of applying patches to an existing vehicle
    --applyPatchToVehicle(customVehicle, "HPPatch")
    --applyPatchToVehicle(customVehicle, "TurnPatch")
  --  applyPatchToVehicle(customVehicle, "AllPatch")
end


function VehicleService:KnitStart()

                
end


function VehicleService:KnitInit()
   -- VehicleService:InitVehicle()


end

-- Remote method to get the player's vehicle
function VehicleService.Client:GetPlayerVehicle(Player)
    return self.Server.Vehicles[Player.UserId]
end

return VehicleService
