local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Gizmo = require(ReplicatedStorage.Packages.imgizmo)
local CustomPackages = ReplicatedStorage.CustomPackages

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

local HomingMissleController = Knit.CreateController { Name = "HomingMissleController" }

-- Constants for missile behavior
local FORWARD_FORCE_MAGNITUDE = 750 -- Forward force magnitude
local ROTATION_RESPONSIVENESS = 20  -- Responsiveness of AlignOrientation for rotation
local GIZMO_ARROW_LENGTH = 10       -- Length of Gizmo arrows for visualization

-- Function to calculate the direction vector from missile to target
local function calculateDirection(missilePosition, targetPosition)
    return (targetPosition - missilePosition).Unit
end

-- Function to apply forward force
local function applyForwardForce(missile)
    -- Ensure the missile has an attachment point for the LinearVelocity
    local forwardDirection = missile.CFrame.LookVector -- Get the forward direction
    local forceMagnitude = 10 -- Set the force magnitude (adjust as needed)

    -- Create an Attachment if it doesn't exist
    local attachment = missile:FindFirstChild("Attachment") or Instance.new("Attachment", missile)

    -- Create the LinearVelocity instance
    local linearVelocity = Instance.new("LinearVelocity")
    linearVelocity.Attachment0 = attachment -- Attach the LinearVelocity to the missile's attachment
    linearVelocity.MaxForce = 1e6 -- Max force the LinearVelocity can exert
    linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World -- Force applied relative to the world
    linearVelocity.VectorVelocity = forwardDirection * forceMagnitude -- Forward direction with the specified magnitude
    linearVelocity.Parent = missile -- Parent the LinearVelocity to the missile

    print("Forward force applied to missile!")
end


-- Function to align missile rotation toward the target
local function alignRotation(missile, target)
    -- Ensure attachments exist
    local alignmentAttachment0 = Instance.new("Attachment")
    alignmentAttachment0.Name = "AlignAttachment0"
    alignmentAttachment0.Parent = missile

    local alignmentAttachment1 = Instance.new("Attachment")
    alignmentAttachment1.Name = "AlignAttachment1"
    alignmentAttachment1.Parent = target

    -- Create AlignOrientation if it doesn't exist
    local alignOrientation = Instance.new("AlignOrientation")
    alignOrientation.Name = "AlignOrientation"
    alignOrientation.Attachment0 = alignmentAttachment0
    alignOrientation.Attachment1 = alignmentAttachment1
    alignOrientation.Responsiveness = ROTATION_RESPONSIVENESS
    alignOrientation.RigidityEnabled = false

    -- Prevent rolling
    alignOrientation.PrimaryAxisOnly = true -- Only rotate around the primary axis
    alignOrientation.PrimaryAxis = Vector3.new(0, 0, 0) -- Allow rotation only around the Y-axis (up direction)

    alignOrientation.Parent = missile
end


-- Function to visualize the missile's forward direction
local function visualizeDirections(missile, target)
    local position = missile.Position
    local forwardDirection = missile.CFrame.LookVector
    local targetPosition = target.Position

    -- Visualize missile's current forward direction
    Gizmo.PushProperty("Color3", Color3.new(0, 0, 1)) -- Blue for forward direction
    Gizmo.PushProperty("Transparency", 0.25)
    local forwardArrowStart = position
    local forwardArrowEnd = position + forwardDirection * GIZMO_ARROW_LENGTH
    Gizmo.Arrow:Draw(forwardArrowStart, forwardArrowEnd, 0.1, 0.3, 0.5, true)

    -- Visualize target direction
    Gizmo.PushProperty("Color3", Color3.new(1, 0, 0)) -- Red for target direction
    Gizmo.PushProperty("Transparency", 0.25)
    local targetArrowStart = position
    local targetArrowEnd = targetPosition
    Gizmo.Arrow:Draw(targetArrowStart, targetArrowEnd, 0.1, 0.3, 0.5, true)
end

-- Main function to handle missile rotation and movement
function HomingMissleController:RotateSaw(missile, target)
    RunService.RenderStepped:Connect(function()
        if not missile or not target then return end

        -- STEP 1: Align missile rotation toward the target
        alignRotation(missile, target)

        -- STEP 2: Apply forward force
        applyForwardForce(missile)

        -- STEP 3: Visualize directions for debugging
        visualizeDirections(missile, target)
    end)
end

local function init()
      -- Locate the saw model and missile part
      local sawModel = Workspace:FindFirstChild("Saw")
      if not sawModel then
          warn("Saw model not found!")
          return
      end
  
      local missile = sawModel:FindFirstChild("SawBlade")
      if not missile then
          warn("Missile part not found in Saw model!")
          return
      end
  
      -- Player management
      require(PlayerAddedFunctions)(
          function(JoiningPlayer)
              -- Player added logic (optional)
          end,
          function(LeavingPlayer)
              -- Player leaving logic (optional)
          end,
          function(Player, Character)
              -- Ensure Character and missile exist
              if not Character or not missile then return end
  
              local humanoidRootPart = Character:WaitForChild("HumanoidRootPart")
  
              -- Start missile homing behavior
              self:RotateSaw(missile, humanoidRootPart)
          end
      )
end

function HomingMissleController:KnitStart()
  
end

function HomingMissleController:KnitInit()
    -- Initialization logic, if required
end

return HomingMissleController
