local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)
local RunService = game:GetService("RunService")

local WalkieTalkieController = Knit.CreateController { Name = "WalkieTalkieController" }

function WalkieTalkieController:KnitStart()
    -- Add controller startup logic here if needed
end

function WalkieTalkieController:KnitInit()
    local LocalPlayer = Players.LocalPlayer
    local backpack = LocalPlayer.Backpack
    local Tool = backpack:FindFirstChild("WalkieTalkie")
    local RadioTower = workspace:FindFirstChild("RadioTower")
    local camera = workspace.CurrentCamera

    if Tool then
        Tool.Equipped:Connect(function()
            print("Equipped tool: " .. Tool.Name)
            local handle = Tool:FindFirstChild("Handle")
            local Sound = handle:FindFirstChild("WalkieTalkieStatic")
            
            if Sound then
                Sound.Looped = true
                Sound.Playing = true

                -- Continuously adjust the volume based on camera's direction and distance
                RunService.Heartbeat:Connect(function()
                    if RadioTower and Sound.Playing then
                        -- Get the direction from the camera to the radio tower
                        local cameraToTower = (RadioTower.Position - camera.CFrame.Position).unit

                        -- Get the camera's look direction
                        local cameraLookDirection = camera.CFrame.LookVector

                        -- Calculate the dot product between the camera's look direction and the direction to the radio tower
                        local dotProduct = cameraLookDirection:Dot(cameraToTower)

                        -- Calculate the distance between the camera and the radio tower
                        local distance = (RadioTower.Position - camera.CFrame.Position).magnitude

                        -- Adjust the volume based on the dot product (direction) and the distance
                        local directionFactor = math.clamp(dotProduct, 0, 1)  -- 0 to 1, camera facing tower
                        local distanceFactor = math.clamp(1 / (distance / 50), 0, 1)  -- Inverse distance, max range of 50 studs

                        -- Combine direction and distance
                        local volume = directionFactor * distanceFactor

                        -- Set the volume of the sound
                        Sound.Volume = volume
                    end
                end)
            end
        end)

        Tool.Unequipped:Connect(function()
            local handle = Tool:FindFirstChild("Handle")
            local Sound = handle:FindFirstChild("WalkieTalkieStatic")
            if Sound then
                Sound.Playing = false
            end
        end)
    end
end

return WalkieTalkieController
