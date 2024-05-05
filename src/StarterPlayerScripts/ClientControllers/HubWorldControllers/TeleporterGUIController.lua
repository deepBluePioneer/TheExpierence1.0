local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local TeleporterGUIController = Knit.CreateController { Name = "TeleporterGUIController" }

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

function TeleporterGUIController:KnitInit()
    
    Teleporters = CollectionService:GetTagged("teleporter")

    
    local SETTINGS = {

    }

    local ReplicaTestClient = {

    }

    ----- Loaded Modules -----
    local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
    local Replica = CustomPackages:WaitForChild("Replica")
    ReplicaController = require(Replica:WaitForChild("ReplicaController"))
   
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
        
        print("ReplicaOne and all it's children have been replicated!")
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


    self:createBillboardGUI(Teleporters)
end



function TeleporterGUIController:createBillboardGUI(Teleporters)
    -- Iterate through the list of teleporter objects
    for _, teleporter in ipairs(Teleporters) do
        -- Find the child named "TeleportZone" in each teleporter
        local teleportZone = teleporter:FindFirstChild("TeleportZone")
        
        if teleportZone then

            local testValue = Value(0)  -- Initialize with a default value

            local textValue = Computed(function()
                return tostring(testValue:get().."/5")  -- Automatically updates text based on testValue
            end)

            local billboardGui = New "BillboardGui" {
                Parent = teleporter,
                Size = UDim2.fromOffset(200, 50),
                Adornee = teleporter,
                AlwaysOnTop = true
            }
         

            local textLabel = New "TextLabel" {
                Parent = billboardGui,
                Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                BackgroundTransparency = 0.5,
                Text = textValue,  -- Text is reactively updated
                TextColor3 = Color3.fromRGB(0, 0, 0),
                TextScaled = true
            }
        
            -- Setup to listen for TestValue changes and update the Fusion state
            ReplicaController.ReplicaOfClassCreated("ReplicaOne", function(replica_one)
                local child = replica_one.Children[1]  -- Example: adjust this access based on your actual data structure
        
                child:ListenToChange({"TestValue"}, function(new_value)
                    testValue:set(new_value)  -- Update the reactive state on change
                    --print("[" .. child.Class .. "]: (Index: " .. child.Tags.Index .. ") TestValue changed to " .. tostring(new_value))
                end)
            end)

            
        end
    end
end




return TeleporterGUIController
