local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local SplinePointMoverToPlayerController = Knit.CreateController { Name = "SplinePointMoverToPlayerController" }

-- Function to update the position of P1 to the local player's HumanoidRootPart
function SplinePointMoverToPlayerController:updatePartPositionToLocalPlayer(part)
    local player = Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5) -- Waits for "HumanoidRootPart" for up to 5 seconds

    if humanoidRootPart then
        -- Set the part's position to the position of the HumanoidRootPart

      -- part.Position = humanoidRootPart.Position
    end
end

-- Function to start tracking and updating the part's position using RenderStepped
function SplinePointMoverToPlayerController:startTrackingLocalPlayer(part)
    if not part then
        warn("Part is not defined!")
        return
    end

    -- Connect RenderStepped to update the position
    self.renderSteppedConnection = RunService.RenderStepped:Connect(function()

        self:updatePartPositionToLocalPlayer(part)

    end)
end

-- Disconnect RenderStepped when not needed
function SplinePointMoverToPlayerController:stopTrackingLocalPlayer()
    if self.renderSteppedConnection then
        self.renderSteppedConnection:Disconnect()
        self.renderSteppedConnection = nil
    end
end

function SplinePointMoverToPlayerController:KnitStart()
    local part_P3 = Workspace:FindFirstChild("P3")

    if part_P3 then
        -- Start tracking the local player's character and updating the part's position
        self:startTrackingLocalPlayer(part_P3)
    else
        warn("Part P3 not found in the Workspace!")
    end
end

function SplinePointMoverToPlayerController:KnitInit()
    -- Add controller initialization logic here
end

return SplinePointMoverToPlayerController
