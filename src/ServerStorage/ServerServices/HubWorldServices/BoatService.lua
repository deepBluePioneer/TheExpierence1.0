local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Players = game:GetService("Players")

local RunService = game:GetService("RunService")
local Terrain = workspace:WaitForChild("Terrain")

local BoatService = Knit.CreateService { Name = "BoatService" }

local boat_1
local boat_1_Seat_1
local boat_1_Seat_2
local boat_1_Seat_3
local corePart



local rightPaddleTorque = Vector3.new(0, -0.5, 0) -- Turn right (counterclockwise)
local leftPaddleTorque = Vector3.new(0, 0.5, 0) -- Turn left (clockwise)


local MoveSpeed = 20 -- Adjust the maximum force as needed
local RotationSpeed = 2 -- Adjust the maximum torque as needed

-- Function to calculate buoyant force
local function calculateBuoyantForce(part, waterLevel, fluidDensity)
    local gravity = workspace.Gravity
    local volume = part.Size.X * part.Size.Y * part.Size.Z
    local submergedVolume = math.max(0, math.min(part.Position.Y + part.Size.Y / 2, waterLevel) - (part.Position.Y - part.Size.Y / 2)) * part.Size.X * part.Size.Z
    local buoyantForceMagnitude = fluidDensity * gravity * submergedVolume
    return Vector3.new(0, buoyantForceMagnitude, 0)
end

-- Function to get the water height at a specific position
local function getWaterHeight(position)
    local size = Vector3.new(4, 4, 4) -- A small region around the boat
    local min = position - (size / 2)
    local max = position + (size / 2)
    
    local region = Region3.new(min, max):ExpandToGrid(4)

    -- Read the voxels in the region
    local materials = Terrain:ReadVoxels(region, 4)[1][1][1]
    if materials == Enum.Material.Water then
        return region.CFrame.Position.Y -- Calculate the height of the water voxel
    end

    return nil
end
-- Function to calculate wind force on the boat
local function calculateWindForce(part, wind)
    -- Assuming a simple drag model, you can scale this based on the boat's exposed surface area and shape
    local dragCoefficient = 1 -- Adjust this value based on the boat's aerodynamics
    local area = part.Size.X * part.Size.Z -- Approximate exposed area
    local windForceMagnitude = dragCoefficient * area * wind.Magnitude
    local windForce = wind.Unit * windForceMagnitude
    return windForce
end

-- Function to check if any seat is occupied
local function isAnySeatOccupied()
    return (boat_1_Seat_1.Occupant ~= nil or boat_1_Seat_2.Occupant ~= nil or boat_1_Seat_3.Occupant ~= nil)
end


function BoatService:init()
    boat_1 = workspace:WaitForChild("boat_1")
    boat_1_Seat_1 = boat_1.PrimaryPart:WaitForChild("Seat_1")
    boat_1_Seat_2 = boat_1.PrimaryPart:WaitForChild("Seat_2")
    boat_1_Seat_3 = boat_1.PrimaryPart:WaitForChild("Seat_3")
    corePart = boat_1.PrimaryPart

   

    boat_1.PrimaryPart:SetNetworkOwner(nil)
end

function BoatService:KnitStart()
   -- BoatService:init()
end

function BoatService:KnitInit()
end

function BoatService.Client:BoatRight(player)
    if isAnySeatOccupied() then
        corePart.AssemblyLinearVelocity = corePart.CFrame.LookVector * MoveSpeed -- Adjust the force multiplier as needed
        corePart.AssemblyAngularVelocity = rightPaddleTorque * RotationSpeed -- Adjust the torque multiplier as needed
    end
end

function BoatService.Client:BoatLeft(player)
    if isAnySeatOccupied() then
        corePart.AssemblyLinearVelocity = corePart.CFrame.LookVector * MoveSpeed -- Adjust the force multiplier as needed
        corePart.AssemblyAngularVelocity = leftPaddleTorque * RotationSpeed -- Adjust the torque multiplier as needed
    end
end

return BoatService
