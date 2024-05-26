local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Players = game:GetService("Players")
local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions
local Knit = require(Packages.Knit)
local Keyboard = require(Packages.Input).Keyboard
local TweenService = game:GetService("TweenService")

local IKControlController = Knit.CreateController { Name = "IKControlController" }

-- Function to create IKControl and target for a limb
function IKControlController:CreateIKControl(Character, limb, chainRoot, offset)
    local humanoid = Character:WaitForChild("Humanoid")
    local root = Character:WaitForChild("HumanoidRootPart")
    
    -- Create a new attachment to use as the IKControl.Target
    local target = Instance.new("Attachment")
    target.CFrame = CFrame.new(unpack(offset))
    target.Parent = root

    local ikControl = Instance.new("IKControl")
    ikControl.Type = Enum.IKControlType.Position
    ikControl.EndEffector = Character:WaitForChild(limb)
    ikControl.ChainRoot = Character:WaitForChild(chainRoot)
    ikControl.Target = target
    ikControl.Parent = humanoid
    
    return target
end

-- Function to animate a limb using IK
function IKControlController:MoveLimb(target, direction, delay)
    local tweenInfo = TweenInfo.new(
        0.25, -- Time
        Enum.EasingStyle.Sine, -- EasingStyle
        Enum.EasingDirection.InOut, -- EasingDirection
        -1, -- RepeatCount (-1 for infinite)
        true, -- Reverses
        delay -- DelayTime
    )
    
    local goal = {CFrame = target.CFrame * CFrame.new(0, 0, direction * -1)}
    
    local tween = TweenService:Create(target, tweenInfo, goal)
    tween:Play()
    
    return tween
end

function  IKControlController:init()
    local Keyboard = Keyboard.new()
    
    local currentTweens = {}
    
    Keyboard.KeyDown:Connect(function(key)
        if key == Enum.KeyCode.S then
            local player = Players.LocalPlayer
            local character = player.Character or player.CharacterAdded:Wait()
            
            if not character:FindFirstChild("LeftHand") or not character:FindFirstChild("RightHand") or not character:FindFirstChild("LeftFoot") or not character:FindFirstChild("RightFoot") then return end
            
            -- Create IKControls for all limbs
            local leftHandTarget = self:CreateIKControl(character, "LeftHand", "LeftUpperArm", {-1, 0, -1})
            local rightHandTarget = self:CreateIKControl(character, "RightHand", "RightUpperArm", {1, 0, -1})
            local leftFootTarget = self:CreateIKControl(character, "LeftFoot", "LeftUpperLeg", {-1, -2, -1})
            local rightFootTarget = self:CreateIKControl(character, "RightFoot", "RightUpperLeg", {1, -2, -1})
            
            -- Cancel existing tweens
            for _, tween in pairs(currentTweens) do
                tween:Cancel()
            end
            currentTweens = {}

            -- Start new tweens with alternating delays for more natural movement
            table.insert(currentTweens, self:MoveLimb(leftHandTarget, -1, 0))
            table.insert(currentTweens, self:MoveLimb(rightHandTarget, 1, 0.25))
            table.insert(currentTweens, self:MoveLimb(leftFootTarget, -1, 0.25))
            table.insert(currentTweens, self:MoveLimb(rightFootTarget, 1, 0))
        end
    end)
    
    Keyboard.KeyUp:Connect(function(key)
        if key == Enum.KeyCode.S then
            for _, tween in pairs(currentTweens) do
                tween:Cancel()
            end
            currentTweens = {}
        end
    end)

    require(PlayerAddedFunctions)(
        function(JoiningPlayer)
            print("Joining: " .. JoiningPlayer.Name)
        end,
        function(LeavingPlayer)
            print("LeavingPlayer: " .. LeavingPlayer.Name)
        end,
        function(Player, Character)
            local humanoid = Character:WaitForChild("Humanoid")
            local root = Character:WaitForChild("HumanoidRootPart")
            local AnimateScript = Character:WaitForChild("Animate")
            if AnimateScript then
                AnimateScript.Parent = nil
            end
            
            -- Setup IKControl for new character
            self:CreateIKControl(Character, "LeftHand", "LeftUpperArm", {-1, 0, -1})
            self:CreateIKControl(Character, "RightHand", "RightUpperArm", {1, 0, -1})
            self:CreateIKControl(Character, "LeftFoot", "LeftUpperLeg", {-1, -2, -1})
            self:CreateIKControl(Character, "RightFoot", "RightUpperLeg", {1, -2, -1})
        end
    )
end

function IKControlController:KnitStart()
   
end

function IKControlController:KnitInit()
    -- Add controller initialization logic here
end

return IKControlController

