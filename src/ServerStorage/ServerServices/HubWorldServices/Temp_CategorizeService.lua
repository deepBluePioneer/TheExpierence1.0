local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local CastleAssets = workspace.CastleAssets
local Baseplate = workspace:WaitForChild("Baseplate") -- Assuming the Baseplate is named "Baseplate"

local Temp_Categorize = Knit.CreateService {
    Name = "Temp_Categorize",
    Client = {},
}

function Temp_Categorize:KnitStart()
   -- self:SetPrimaryPartsAndAlignInGrid()
end

function Temp_Categorize:KnitInit()
    -- Add service initialization logic here
end

function Temp_Categorize:SetPrimaryPartsAndAlignInGrid()
    local gridSpacing = 10 -- Spacing between each asset
    local startPosition = Baseplate.Position - Vector3.new(Baseplate.Size.X / 2, 0, Baseplate.Size.Z / 2) + Vector3.new(gridSpacing, 0, gridSpacing)
    local currentX = startPosition.X
    local currentZ = startPosition.Z

    for _, asset in ipairs(CastleAssets:GetChildren()) do
        if asset:IsA("Model") then
            -- Set the PrimaryPart to the first child if not already set
            if not asset.PrimaryPart then
                local firstChild = asset:FindFirstChildWhichIsA("BasePart")
                if firstChild then
                    asset.PrimaryPart = firstChild
                else
                    warn(asset.Name .. " does not have any BasePart children.")
                    continue
                end
            end

            -- Align the asset in the grid
            asset:SetPrimaryPartCFrame(CFrame.new(Vector3.new(currentX, Baseplate.Position.Y + asset.PrimaryPart.Size.Y / 2, currentZ)))
            currentX = currentX + asset.PrimaryPart.Size.X + gridSpacing

            -- Move to the next row if the current row is full
            if currentX > startPosition.X + Baseplate.Size.X - gridSpacing then
                currentX = startPosition.X
                currentZ = currentZ + asset.PrimaryPart.Size.Z + gridSpacing
            end
        elseif asset:IsA("BasePart") then
            -- Directly align the part if it's not a model
            asset.CFrame = CFrame.new(Vector3.new(currentX, Baseplate.Position.Y + asset.Size.Y / 2, currentZ))
            currentX = currentX + asset.Size.X + gridSpacing

            -- Move to the next row if the current row is full
            if currentX > startPosition.X + Baseplate.Size.X - gridSpacing then
                currentX = startPosition.X
                currentZ = currentZ + asset.Size.Z + gridSpacing
            end
        end
    end
end

return Temp_Categorize
