local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

local RunService = game:GetService("RunService")

local MonsterMovementService = Knit.CreateService {
    Name = "MonsterMovementService",
    Client = {},
}

function init()

    local OrbitRadius = 15  -- Radius of the orbit
    local OrbitSpeed = 50    -- Speed of the orbit (radians per second)

    -- Add service startup logic here
    local WaveSpawnerService = Knit.GetService("WaveSpawnerService")
    -- Access the monsters table from WaveSpawnerService
    local monsters = WaveSpawnerService.Monsters

    local firstPlayer = nil

    -- Register player added functions
    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
            print("Joining: " .. JoiningPlayer.Name)
            if not firstPlayer then
                firstPlayer = JoiningPlayer
            end
        end,
        function(LeavingPlayer)
            print("Leaving: " .. LeavingPlayer.Name)
            if firstPlayer == LeavingPlayer then
                firstPlayer = nil
                -- Optionally handle case where the first player leaves
            end
        end,
        function(Player, Character)
            if firstPlayer == Player then
                self:OrbitPlayer(Character, monsters, OrbitRadius, OrbitSpeed)
            end
        end
    )
    
end

function MonsterMovementService:KnitStart()
   
  
end

function MonsterMovementService:OrbitPlayer(character, monsters, orbitRadius, orbitSpeed)
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    for _, monster in ipairs(monsters) do
        -- Unanchor the monster
        monster.Anchored = false
        
        -- Set the network owner to the player
        monster:SetNetworkOwner(character.Parent)

        -- Create an attachment for the player's HumanoidRootPart
        local playerAttachment = Instance.new("Attachment")
        playerAttachment.CFrame = CFrame.new(0, 0, 0) -- Position attachment at the player's HumanoidRootPart
        playerAttachment.Parent = humanoidRootPart  -- Parent the attachment to the HumanoidRootPart

        -- Create an attachment for the monster
        local monsterAttachment = Instance.new("Attachment")
        monsterAttachment.CFrame = CFrame.new(0, 0, orbitRadius) -- Offset the attachment to set the orbit radius
        monsterAttachment.Parent = monster

        -- Create the HingeConstraint
        local hinge = Instance.new("HingeConstraint")
        hinge.Attachment0 = monsterAttachment
        hinge.Attachment1 = playerAttachment
        hinge.LimitsEnabled = false
        hinge.ActuatorType = Enum.ActuatorType.Motor
        hinge.MotorMaxTorque = math.huge
        hinge.AngularVelocity = math.rad(orbitSpeed) -- Orbit speed in radians per second
        hinge.Parent = monster

        -- Create the RodConstraint to maintain the orbit radius
        local rod = Instance.new("RodConstraint")
        rod.Attachment0 = monsterAttachment
        rod.Attachment1 = playerAttachment
        rod.Length = orbitRadius
        rod.Parent = monster
    end
end

function MonsterMovementService:KnitInit()
    -- Add service initialization logic here
end

return MonsterMovementService
