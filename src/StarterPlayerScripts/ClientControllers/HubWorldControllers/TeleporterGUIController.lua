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
local ReplicaController

----- Loaded Modules -----
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Replica = CustomPackages:WaitForChild("Replica")
ReplicaController = require(Replica:WaitForChild("ReplicaController"))


function TeleporterGUIController:KnitInit()
    Teleporters = CollectionService:GetTagged("teleporter")
    local SETTINGS = {}
    local ReplicaTestClient = {}

    local function GetAllMessages(messages)
        if next(messages) == nil then
            return "Empty!"
        else
            local result = ""
            for message_name, text in pairs(messages) do
                result ..= message_name .. " = \"" .. text .. "\""
                    .. (next(messages, message_name) ~= nil and "; " or "")
            end
            return result
        end
    end
    ReplicaController.RequestData()

    ----- Connections -----
    ReplicaController.ReplicaOfClassCreated("ReplicaOne", function(replica_one)
        local messages = replica_one.Data.Messages
        
        print("ReplicaOne and all its children have been replicated!")
        print("Initially received state of all replicas:")
        print("  " .. replica_one.Class .. ": " .. GetAllMessages(messages))
        for _, child in ipairs(replica_one.Children) do
            local child_data = child.Data
            print("    " .. child.Class .. ": (Tags: " .. GetAllMessages(child.Tags)
                .. "); TestValue = " .. child_data.TestValue .. "; NestedValue = " .. child_data.TestTable.NestedValue)
            
            child:ListenToChange({"TestValue"}, function(new_value)
                print("[" .. child.Class .. "]: (Index: " .. child.Tags.Index .. ") TestValue changed to " .. tostring(new_value))
            end)
            child:ListenToChange({"TestTable", "NestedValue"}, function(new_value)
                print("[" .. child.Class .. "]: (Index: " .. child.Tags.Index .. ") NestedValue changed to " .. child_data.TestTable.NestedValue)
            end)
        end
        
        print("Printing updates...")
        
        replica_one:ListenToWrite("SetMessage", function(message_name, text)
            print("[" .. replica_one.Class .. "]: SetMessage - (" .. message_name .. " = \"" .. text .. "\") " .. GetAllMessages(messages))
        end)
        
        replica_one:ListenToWrite("SetAllMessages", function(text)
            print("[" .. replica_one.Class .. "]: SetAllMessages - " .. GetAllMessages(messages))
        end)
        
        replica_one:ListenToWrite("DestroyAllMessages", function()
            print("[" .. replica_one.Class .. "]: DestroyAllMessages - " .. GetAllMessages(messages))
        end)
    end)

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
