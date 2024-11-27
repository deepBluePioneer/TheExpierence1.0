local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")  -- For smooth transitions
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Keyboard = require(ReplicatedStorage.Packages.Input).Keyboard

local HealthController = Knit.CreateController { Name = "HealthController" }

function HealthController:KnitStart()
    local _keyboard = Keyboard.new()

    -- Ensure the LocalPlayer and their GUI exist
    local LocalPlayer = Players.LocalPlayer
    local playerGui = LocalPlayer:WaitForChild("PlayerGui") -- Access PlayerGui

    -- Locate the ScreenGui and HealthFrame
    local screenGui = playerGui:WaitForChild("ScreenGui")
    local healthFrame = screenGui:WaitForChild("HealthFrame")
    local textLabel = healthFrame:WaitForChild("TextLabel")

    -- Set the initial health value to 100%
    self.health = 100
    textLabel.Text = "Health: 100%"

    -- Table to track movement keys
    self.isMoving = {
        W = false,
        A = false,
        S = false,
        D = false
    }

    -- KeyDown event for handling key press
    self.keyDownConnection = _keyboard.KeyDown:Connect(function(key)
        if key == Enum.KeyCode.D then
            self.isMoving.D = true
        elseif key == Enum.KeyCode.A then
            self.isMoving.A = true
        elseif key == Enum.KeyCode.W then
            self.isMoving.W = true
        elseif key == Enum.KeyCode.S then
            self.isMoving.S = true
        end
    end)

    -- KeyUp event for handling key release
    self.keyUpConnection = _keyboard.KeyUp:Connect(function(key)
        if key == Enum.KeyCode.D then
            self.isMoving.D = false
        elseif key == Enum.KeyCode.A then
            self.isMoving.A = false
        elseif key == Enum.KeyCode.W then
            self.isMoving.W = false
        elseif key == Enum.KeyCode.S then
            self.isMoving.S = false
        end
    end)

    -- Continuously update health based on movement
    self.healthUpdateConnection = RunService.Heartbeat:Connect(function()
        self:UpdateHealth()
    end)
end

-- Method to update health based on movement status
function HealthController:UpdateHealth()
    local movementStatus = self.isMoving.W or self.isMoving.A or self.isMoving.S or self.isMoving.D

    -- Increase health slowly while moving, capping at 100%
    if movementStatus then
        self.health = math.min(self.health + 0.1, 100)
    else
        -- Decrease health slowly while not moving, capping at 0%
        self.health = math.max(self.health - 0.05, 0)
    end

    -- Update the health text label
    local LocalPlayer = Players.LocalPlayer
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = playerGui:WaitForChild("ScreenGui")
    local healthFrame = screenGui:WaitForChild("HealthFrame")
    local textLabel = healthFrame:WaitForChild("TextLabel")

    textLabel.Text = string.format("Health: %.0f%%", self.health)
end

function HealthController:KnitInit()
    -- Add controller initialization logic here if needed
end

return HealthController
