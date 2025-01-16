
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local SplinePointMoverToPlayerController = Knit.CreateController { Name = "SplinePointMoverToPlayerController" }

-- Interpolation speed
local INTERPOLATION_SPEED = 0.1 -- Adjust this for smoother or faster interpolation
local OFFSET_DISTANCE = 10 -- Fixed distance to maintain between part_P4 and part_P3

-- Function to interpolate the part's position toward the player's position
function SplinePointMoverToPlayerController:interpolatePartPositionToLocalPlayer(part)
    local player = Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

    -- Interpolate position using Lerp
    part.Position = part.Position:Lerp(humanoidRootPart.Position, INTERPOLATION_SPEED)
end

-- Function to update part_P4's position based on part_P3 and ensure a fixed distance
function SplinePointMoverToPlayerController:updatePartP4Position(part_P3, part_P4, saw)
    -- Ensure all parts exist
    if not (part_P3 and part_P4 and saw) then return end

    -- Calculate Saw's movement vector
    local sawMovementVector = saw.CFrame.LookVector -- Using Saw's forward direction

    -- Calculate target position for part_P4 at a fixed distance behind part_P3
    local targetPosition = part_P3.Position - (sawMovementVector.Unit * OFFSET_DISTANCE)
    targetPosition = Vector3.new(targetPosition.X, part_P3.Position.Y, targetPosition.Z) -- Match Y with part_P3

    -- Interpolate part_P4 toward the target position
    part_P4.Position = part_P4.Position:Lerp(targetPosition, INTERPOLATION_SPEED)
end

-- Function to start tracking and updating the parts' positions using RenderStepped
function SplinePointMoverToPlayerController:startTrackingParts(part_P3, part_P4, saw)
    -- Connect RenderStepped to update positions
    self.renderSteppedConnection = RunService.RenderStepped:Connect(function()
        if part_P3 then
            self:interpolatePartPositionToLocalPlayer(part_P3)
        end
        if part_P4 and saw then
            self:updatePartP4Position(part_P3, part_P4, saw)
        end
    end)
end

function SplinePointMoverToPlayerController:KnitStart()
 --   local part_P3 = Workspace:FindFirstChild("P3")
   -- local part_P4 = Workspace:FindFirstChild("P4")
    --local saw = Workspace:FindFirstChild("Saw") and Workspace.Saw.PrimaryPart

    --if part_P3 and part_P4 and saw then
     --   self:startTrackingParts(part_P3, part_P4, saw)
   -- end
end

function SplinePointMoverToPlayerController:KnitInit()
    -- Add controller initialization logic here
end

return SplinePointMoverToPlayerController
