local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local TeleporterGUIController = Knit.CreateController { 
    Name = "TeleporterGUIController" 
}

----- Loaded Modules -----
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local FusionRoot = CustomPackages:WaitForChild("FusionRoot")
local Fusion = require(FusionRoot:WaitForChild("Fusion"))

local New = Fusion.New
local OnEvent = Fusion.OnEvent
local Value = Fusion.Value -- This is how you use Fusion's state management
local Computed = Fusion.Computed

local Teleporters

----- Loaded Modules -----
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica:WaitForChild("ReplicaController"))


function TeleporterGUIController:KnitInit()
    Teleporters = CollectionService:GetTagged("teleporter")
 
    
    ReplicaController.RequestData() --Should only be called once according to thte documentation

    self:createScreenGUI(Teleporters)
end

function TeleporterGUIController:createScreenGUI(Teleporters)
    for _, teleporter in ipairs(Teleporters) do
        local teleportZone = teleporter:FindFirstChild("TeleportZone")
        
        if teleportZone then
            local timeRemaining = Value("00:00.000")  -- Initialize with a default formatted time string
            local timerType = Value("Lobby")

            local textValue = Computed(function()
                if timerType:get() == "Lobby" then
                    return "Next Match in " .. timeRemaining:get()
                elseif timerType:get() == "Game" then
                    return "Game starts in " .. timeRemaining:get()
                elseif timerType:get() == "Return" then
                    return timeRemaining:get()
                end
            end)

            local screenGui = New "ScreenGui" {
                Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
                Name = "TeleporterScreenGui"
            }

            local textLabel = New "TextLabel" {
                Parent = screenGui,
                Size = UDim2.new(0.5, 0, 0.1, 0),
                Position = UDim2.new(0.25, 0, 0, 0),
                BackgroundTransparency = 1,
                Text = textValue,
                TextColor3 = Color3.fromRGB(248, 246, 128),
                TextScaled = true,
                Font = Enum.Font.GothamBold
            }

            -- Setup to listen for TimeRemaining changes and update the Fusion state
            ReplicaController.ReplicaOfClassCreated("TimerReplica", function(timer_replica)
                timer_replica:ListenToChange({"TimeRemaining"}, function(new_value)
                    timerType:set("Lobby")
                    timeRemaining:set(new_value)
                end)

                timer_replica:ListenToChange({"GameTimeRemaining"}, function(new_value)
                    timerType:set("Game")
                    timeRemaining:set(new_value)
                end)
                
                timer_replica:ListenToChange({"ReturnTimeRemaining"}, function(new_value)
                    timerType:set("Return")
                    timeRemaining:set(new_value)
                end)
            end)
        end
    end
end


return TeleporterGUIController
