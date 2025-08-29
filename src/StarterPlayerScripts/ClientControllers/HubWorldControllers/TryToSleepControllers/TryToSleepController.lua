-- Client/Controllers/TryToSleepController.lua

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit     = require(Packages.Knit)

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local TryToSleepController = Knit.CreateController {
    Name = "TryToSleepController"
}

-- Runtime state
local blackOverlay
local fadeTween
local isHolding = false

-- === Helpers ===

local function createSleepOverlay()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SleepGui"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 100 -- ensure it's above everything else
    screenGui.Parent = PlayerGui

    local overlay = Instance.new("Frame")
    overlay.Name = "BlackOverlay"
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.Position = UDim2.new(0, 0, 0, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 1 -- fully transparent to start
    overlay.BorderSizePixel = 0
    overlay.ZIndex = 10
    overlay.Parent = screenGui

    return overlay
end

local function fadeIn()
    if not blackOverlay then return end
    if fadeTween then fadeTween:Cancel() end
    fadeTween = TweenService:Create(blackOverlay, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0
    })
    fadeTween:Play()
end

local function fadeOut()
    if not blackOverlay then return end
    if fadeTween then fadeTween:Cancel() end
    fadeTween = TweenService:Create(blackOverlay, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 1
    })
    fadeTween:Play()
end

-- === Knit lifecycle ===

function TryToSleepController:KnitInit()
    blackOverlay = createSleepOverlay()
end

function TryToSleepController:KnitStart()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.E and not isHolding then
            isHolding = true
            fadeIn()
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.E and isHolding then
            isHolding = false
            fadeOut()
        end
    end)
end

return TryToSleepController
