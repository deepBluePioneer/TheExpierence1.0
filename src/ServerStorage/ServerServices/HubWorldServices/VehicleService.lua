local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

local PrefabsFolder = ReplicatedStorage.Prefabs
local Balloon

local VehicleService = Knit.CreateService {
    Name = "VehicleService",
    Client = {},
}

VehicleService.Vehicles = {}

-- Function to create a balloon model
function VehicleService:CreateBalloon()
    local balloon = Instance.new("Part")
    balloon.Name = "BalloonPart"
    balloon.Shape = Enum.PartType.Ball
    balloon.Size = Vector3.new(3, 3, 3) -- Example size
    balloon.Material = Enum.Material.SmoothPlastic
    balloon.BrickColor = BrickColor.new("Bright red")
    balloon.Massless = true
    balloon.Anchored = false
    balloon.CanCollide = false
    return balloon
end

function CreateBalloon()
    -- Create and attach balloons
    local balloonPositions = {
        Vector3.new(0, 15, 0),
        Vector3.new(5, 15, 5),
        Vector3.new(-5, 15, -5)
    }

    for _, position in ipairs(balloonPositions) do
        local balloon = self:CreateBalloon()
        balloon.CFrame = sphere.CFrame
        balloon.Parent = vehicleModel

        -- Create and configure rope constraint
        local attachment0 = Instance.new("Attachment")
        attachment0.Position = sphere.Position -- Set position relative to the sphere
        attachment0.Parent = sphere

        local attachment1 = Instance.new("Attachment")
        attachment1.Position = balloon.Position -- Set position relative to the balloon
        attachment1.Parent = balloon

        local ropeConstraint = Instance.new("RopeConstraint")
        ropeConstraint.Visible = true
        ropeConstraint.Attachment0 = attachment0
        ropeConstraint.Attachment1 = attachment1
        ropeConstraint.Length =15 -- Set the desired length
        ropeConstraint.Restitution = 0.5 -- Adjust the restitution to control the bounciness
        ropeConstraint.Parent = sphere

        local linearVelocity = Instance.new("LinearVelocity")
        linearVelocity.Attachment0 = attachment1
        linearVelocity.MaxForce = 9000
        linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        linearVelocity.VectorVelocity = Vector3.new(0, 5000, 0) -- Apply upward force
        linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
        linearVelocity.Parent = balloon

        local angularVelocity = Instance.new("AngularVelocity")
        angularVelocity.Attachment0 = attachment1
        angularVelocity.AngularVelocity = Vector3.new(0, 1, 0) -- Rotate around the Y-axis
        angularVelocity.MaxTorque = 5
        angularVelocity.Parent = balloon
    end

end
-- Function to create the vehicle model
-- Function to create the vehicle model
function VehicleService:CreateVehicle()
    local vehicleModel = Instance.new("Model")
    vehicleModel.Name = "VehicleModel"
    
    local sphere = Instance.new("Part")
    sphere.Shape = Enum.PartType.Ball
    sphere.Size = Vector3.new(10, 10, 10) -- Example size
    sphere.Transparency = 1
    sphere.Name = "Sphere"
    sphere.Anchored = false
    sphere.CanCollide = true
    sphere.Parent = vehicleModel

    vehicleModel.PrimaryPart = sphere

    -- Create the firing point part
    local firingPoint = Instance.new("Part")
    firingPoint.Size = Vector3.new(1, 1, 1) -- Example size
    firingPoint.Transparency = 0
    firingPoint.Name = "FiringPoint"
    firingPoint.Anchored = false
    firingPoint.CanCollide = false
    firingPoint.Color = Color3.new(1, 0, 0) -- Red color for visibility (can be adjusted)

    -- Position the firing point at the front of the sphere
    local sphereSize = sphere.Size.X / 2 -- Assuming the sphere is a perfect ball
    firingPoint.CFrame = sphere.CFrame * CFrame.new(0, 0, -sphereSize - 0.5) -- Positioned just outside the front of the sphere

    firingPoint.Parent = sphere

    -- Weld the firing point to the sphere
    local weldConstraint = Instance.new("WeldConstraint")
    weldConstraint.Part0 = sphere
    weldConstraint.Part1 = firingPoint
    weldConstraint.Parent = sphere

    return vehicleModel
end

function VehicleService:HandleCharacterAdded(Player, Character)
    local vehicleModel = self:CreateVehicle()
    vehicleModel.Parent = Workspace
    local spawnPoint = Workspace:WaitForChild("SpawnLocation")
    vehicleModel:PivotTo(spawnPoint.CFrame)
    local humanoidRootPart = Character:WaitForChild("HumanoidRootPart")
    
    vehicleModel.PrimaryPart:SetNetworkOwner(Player)
    Character:SetPrimaryPartCFrame(vehicleModel.PrimaryPart.CFrame)
    
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = vehicleModel.PrimaryPart
    weld.Part1 = humanoidRootPart
    weld.Parent = vehicleModel.PrimaryPart
    
    self.Vehicles[Player.UserId] = vehicleModel
end

function VehicleService:PlayerLeft(LeavingPlayer)
    local vehicle = self.Vehicles[LeavingPlayer.UserId]
    if vehicle then
        vehicle:Destroy()
        self.Vehicles[LeavingPlayer.UserId] = nil
    end
end

function VehicleService:KnitStart()
    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
        end,
        function(LeavingPlayer)
            self:PlayerLeft(LeavingPlayer)
        end,
        function(Player, Character)
            self:HandleCharacterAdded(Player, Character)
        end
    )
end

function VehicleService:KnitInit()
end

-- Remote method to get the player's vehicle
function VehicleService.Client:GetPlayerVehicle(Player)
    return self.Server.Vehicles[Player.UserId]
end

return VehicleService
