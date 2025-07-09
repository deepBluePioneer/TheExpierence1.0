local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local VehicleConfigController = Knit.CreateController { Name = "VehicleConfigController" }

function VehicleConfigController:KnitStart()
    local VehicleService = Knit.GetService("VehicleService")

    VehicleService.SeatOccupied:Connect(function(vehicleModel)
        VehicleConfigController:initConfig(vehicleModel)
    end)

    VehicleService.SeatEjected:Connect(function()
        self:Cleanup()
    end)
end

function VehicleConfigController:initConfig(vehicleModel)
    self.VehicleModel = vehicleModel
    self.PrimaryPart = vehicleModel.PrimaryPart

    -- Disable default player controls and animations, set parts to massless, and configure humanoid
    --self:DisablePlayerControlsAndAnimations()
    self:SetPlayerPartsMassless()
    self:DisableCharacterCollisions()
    self:ConfigureHumanoidSettings()

    -- Set the camera subject to the primary part of the vehicle
     Camera.CameraSubject = self.PrimaryPart
end

function VehicleConfigController:DisablePlayerControlsAndAnimations()
    -- Disable the default player controls by disabling the ControlModule
    local PlayerModule = require(Player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
    local ControlModule = PlayerModule:GetControls()
    ControlModule:Disable()

    -- Disable the player's animations
    local character = Player.Character or Player.CharacterAdded:Wait()
    local animateScript = character:FindFirstChild("Animate")
    if animateScript then
        animateScript.Disabled = true
    end
end

function VehicleConfigController:SetPlayerPartsMassless()
    -- Set all base parts of the player's character to massless
    local character = Player.Character or Player.CharacterAdded:Wait()
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Massless = true
        end
    end
end

function VehicleConfigController:DisableCharacterCollisions()
    -- Disable collisions between the player's character and the vehicle
    local character = Player.Character or Player.CharacterAdded:Wait()
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
end

function VehicleConfigController:ConfigureHumanoidSettings()
    -- Configure humanoid settings
    local character = Player.Character or Player.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 0 -- Disable walking
        humanoid.JumpPower = 50 -- Disable jumping
        humanoid.AutoRotate = false -- Prevent automatic rotation
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false) -- Disable physics state
       -- humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- Force into physics state
        --humanoid.EvaluateStateMachine = false -- Disable state machine evaluation
        -- Add any other humanoid settings you want to configure here
    end
end

function VehicleConfigController:Cleanup()
    -- Re-enable player controls and animations
    local PlayerModule = require(Player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
    local ControlModule = PlayerModule:GetControls()
    ControlModule:Enable()

    -- Re-enable the player's animations
    local character = Player.Character or Player.CharacterAdded:Wait()
    local animateScript = character:FindFirstChild("Animate")
    if animateScript then
        animateScript.Disabled = false
    end

    -- Reset parts to be non-massless and re-enable collisions
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Massless = false
            part.CanCollide = true
        end
    end

    -- Reset humanoid settings
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 45 -- Default walking speed
        humanoid.JumpPower = 50 -- Default jumping power
        humanoid.AutoRotate = true -- Enable automatic rotation
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true) -- Enable physics state
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) -- Change state to default
        humanoid.EvaluateStateMachine = true -- Enable state machine evaluation
    end

    -- Reset camera subject
    Camera.CameraSubject = Player.Character:FindFirstChild("Humanoid") or Player.Character.PrimaryPart

    -- Clear vehicle model and primary part references
    self.VehicleModel = nil
    self.PrimaryPart = nil
end

function VehicleConfigController:KnitInit()
    -- Add controller initialization logic here
end

return VehicleConfigController
