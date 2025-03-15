local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local WaypointUIController = Knit.CreateController { Name = "WaypointUIController" }



local function updateIndicator(targetPart)
    if not targetPart or not frame or not arrow then return end

    local camCFrame = camera.CFrame
    local targetPosition = targetPart.Position
    local screenPos, onScreen = camera:WorldToViewportPoint(targetPosition)

    -- Convert 3D position to 2D screen space
    local screenCenter = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
    local targetScreenPos = Vector2.new(screenPos.X, screenPos.Y)
    
    -- Map 3D position to 2D screen
    local relativePosition = targetScreenPos - screenCenter -- Direction from center to target in 2D space

    -- Normalize and scale within frame bounds
    local maxMoveX = viewportSize.X / 2 -- Maximum movement in X
    local maxMoveY = viewportSize.Y / 2 -- Maximum movement in Y
    local clampedX = math.clamp(relativePosition.X, -maxMoveX, maxMoveX)
    local clampedY = math.clamp(relativePosition.Y, -maxMoveY, maxMoveY)

    -- Move the arrow inside the full-screen frame
    arrow.Position = UDim2.new(0.5, clampedX, 0.5, clampedY)

    -- Rotate the arrow towards the target
    local direction = (targetScreenPos - screenCenter).unit
    arrow.Rotation = math.deg(math.atan2(direction.Y, direction.X))
end

function WaypointUIController:KnitStart()
   
end

return WaypointUIController
