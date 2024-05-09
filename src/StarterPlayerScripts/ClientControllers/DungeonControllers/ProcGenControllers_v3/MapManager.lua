local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Gizmo = require(Packages.imgizmo)

local FusionRoot = CustomPackages:WaitForChild("FusionRoot")
local Fusion = require(FusionRoot:WaitForChild("Fusion"))
local New = Fusion.New
local OnEvent = Fusion.OnEvent
local Value = Fusion.Value -- This is how you use Fusion's state management
local Computed = Fusion.Computed

-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local MapManager = {}

function MapManager:CreateUIAscii(gridCells)

    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    
    -- Create a ScreenGui
    local screenGui = New "ScreenGui" {
        Parent = playerGui,
        Name = "CustomUI"
    }
    
    local gridSize = #gridCells  -- Assuming gridCells is a square grid
    local cellSize = 1 / gridSize  -- Relative size of each cell in the UI

    -- Define the main frame of the UI
    local mainFrame = New "Frame" {
        Parent = screenGui,
        Size = UDim2.new(0.25, 0, 0.5, 0),
        Position = UDim2.new(0, 0, 1, 0),
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BorderSizePixel = 0,
    }

    -- Loop through each grid cell to create visual representations
    for i = 0, gridSize - 1 do
        for j = 0, gridSize - 1 do
            local cellChar = gridCells[i][j].Taken and "#" or " "  -- Using '#' for taken, '.' for free
            
            local cell = New "TextLabel" {
                Parent = mainFrame,
                Size = UDim2.new(cellSize, 0, cellSize, 0),
                Position = UDim2.new(cellSize * i, 0, cellSize * j, 0),
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                TextColor3 = Color3.fromRGB(255, 255, 255),
                BackgroundTransparency = 1,
            
                Text = cellChar,
                Font = Enum.Font.Ubuntu,  -- Using a monospace font for better alignment
                TextScaled = true,
                BorderSizePixel = 0,
                TextWrapped = true,
            }
            -- Create a zone for each taken tile
            if gridCells[i][j].Taken then
                local zoneCFrame = CFrame.new(gridCells[i][j].Position)
                local zoneSize = Vector3.new(12, 12, 12)  -- Adjust size based on your grid scale
                local zone = Zone.fromRegion(zoneCFrame, zoneSize)

                zone.playerEntered:Connect(function(player)
                   -- print(player.Name .. " entered the zone at " .. i .. ", " .. j)
                   
                    cell.Text = ""  -- Clear the ASCII character
                    cell.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    cell.BackgroundTransparency = 0
                  --  cell.TextLabel = nil
                    --cell.Image = content  -- Set the thumbnail as the image

                end)
                
                zone.playerExited:Connect(function(player)
                   -- print(player.Name .. " exited the zone at " .. i .. ", " .. j)
                    cell.Text = gridCells[i][j].Taken and "#" or " "
                    --cell.Image = nil
                    cell.BackgroundTransparency = 1

                 
                end)

                -- Track the player within this zone
                --zone:trackItem(player)
            end
                        
            
        end
    end

    
end




return MapManager