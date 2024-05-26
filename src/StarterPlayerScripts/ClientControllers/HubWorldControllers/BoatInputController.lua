local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local BoatInputController = Knit.CreateController { Name = "BoatInputController" }
local Keyboard = require(Packages.Input).Keyboard
local Mouse = require(Packages.Input).Mouse

function init()

    local BoatService = Knit.GetService("BoatService")

    local Keyboard = Keyboard.new()
    local isRightPaddle = false
    local isLeftPaddle = false


    local function updatePaddleState()
        if isRightPaddle then
            BoatService:BoatRight()
        elseif isLeftPaddle then
            BoatService:BoatLeft()
        end
    end
   

    
    Keyboard.KeyDown:Connect(function(key)
        if key == Enum.KeyCode.D then
            isRightPaddle = true
            isLeftPaddle = false
            updatePaddleState()
        elseif key == Enum.KeyCode.A then
            isLeftPaddle = true
            isRightPaddle = false
            updatePaddleState()
        end
    end)
    
    Keyboard.KeyUp:Connect(function(key)
        if key == Enum.KeyCode.D then
            isRightPaddle = false
            updatePaddleState()
        elseif key == Enum.KeyCode.A then
            isLeftPaddle = false
            updatePaddleState()
        end
    end)
    
end

function BoatInputController:KnitStart()
   
end

function BoatInputController:KnitInit()
    -- Add controller initialization logic here
end

return BoatInputController
