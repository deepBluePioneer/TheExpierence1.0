local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local StatUIController = Knit.CreateController { Name = "StatUIController" }

local PatchesModule = require(ReplicatedStorage.Source.PatchesModule)

local FusionRoot = CustomPackages:WaitForChild("FusionRoot")
local Fusion = require(FusionRoot:WaitForChild("Fusion"))

local New = Fusion.New
local OnEvent = Fusion.OnEvent
local Value = Fusion.Value -- This is how you use Fusion's state management
local Computed = Fusion.Computed
local Replica = CustomPackages:WaitForChild("Replica")

local ReplicaController = require(Replica:WaitForChild("ReplicaController"))

-- Create a table to store Fusion state values for each patch
local patchStates = {}

-- Function to create the UI for each stat
function StatUIController:createStatUI(patch, index, statValue)
    return New "Frame" {
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, (index - 1) * 40),
        BackgroundTransparency = 1,
        [Fusion.Children] = {
            New "ImageLabel" {
                Size = UDim2.new(0, 30, 0, 30),
                Position = UDim2.new(0, 10, 0.5, -15),
                BackgroundTransparency = 1,
                Image = "rbxassetid://" .. patch.SpriteID,
            },
            New "TextLabel" {
                Size = UDim2.new(0, 100, 1, 0),
                Position = UDim2.new(0, 50, 0, 0),
                BackgroundTransparency = 1,
                Text = patch.Stat,
                TextColor3 = patch.Color,
                Font = Enum.Font.SourceSans,
                TextSize = 24,
                TextXAlignment = Enum.TextXAlignment.Left,
            },
            New "TextLabel" {
                Size = UDim2.new(0, 50, 1, 0),
                Position = UDim2.new(0, 160, 0, 0),
                BackgroundTransparency = 1,
                Text = Computed(function()
                    return tostring(statValue and statValue:get() or 0)
                end),
                TextColor3 = Color3.new(1, 1, 1),
                Font = Enum.Font.SourceSans,
                TextSize = 24,
                TextXAlignment = Enum.TextXAlignment.Left,
            },
            New "Frame" {
                Size = UDim2.new(0.4, 0, 0.6, 0),
                Position = UDim2.new(0, 220, 0.5, -15),
                BackgroundTransparency = 0.5,
                BackgroundColor3 = Color3.new(0.5, 0.5, 0.5),
                [Fusion.Children] = {
                    New "Frame" {
                        Size = Computed(function()
                            return UDim2.new(statValue and statValue:get() / 100 or 0, 0, 1, 0)
                        end),
                        BackgroundColor3 = patch.Color,
                    }
                }
            }
        }
    }
end

function StatUIController:KnitStart()
    local screenGui = New "ScreenGui" {
        Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui"),
        ResetOnSpawn = false,
        [Fusion.Children] = {
            New "Frame" {
                Size = UDim2.new(0, 400, 1, 0),
                Position = UDim2.new(0, 0, 0, 0),
                BackgroundTransparency = 0.5,
                BackgroundColor3 = Color3.new(0, 0, 0),
                [Fusion.Children] = Computed(function()
                    local children = {}
                    local index = 1
                    for patchName, patch in pairs(PatchesModule.Patches) do
                        table.insert(children, self:createStatUI(patch, index, patchStates[patchName]))
                        index = index + 1
                    end
                    return children
                end)
            }
        }
    }
end

function init()
     -- Setup to listen for changes in the StatReplica and update Fusion state
     ReplicaController.ReplicaOfClassCreated("StatReplica", function(stat_replica)

        for patchName, patch in pairs(PatchesModule.Patches) do
            -- Initialize patchStates with Fusion values from the replica
            if not patchStates[patchName] then
                patchStates[patchName] = Value(11888)
            end

            warn(patch.Stat)

            -- Listen for changes in the replica and update the Fusion state
            stat_replica:ListenToChange({patch.Stat}, function(new_value)
                patchStates[patchName]:set(new_value)
            end)
        end
    end)
    
end

function StatUIController:KnitInit()
   
end

return StatUIController
