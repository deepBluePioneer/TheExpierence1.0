local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local CollectionService = game:GetService("CollectionService")
local PrefabFolder = ReplicatedStorage:WaitForChild("Prefabs") -- Ensure Prefabs folder is available

-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local Knit = require(Packages.Knit)

local initButtons = Knit.CreateService {
    Name = "initButtons",
    Client = {},
}

local function createWallsAndCeiling(baseplate)
    local wallsModel = Instance.new("Model")
    wallsModel.Name = "WallsAndCeiling"
    wallsModel.Parent = workspace

    local baseplateSize = baseplate.Size
    local wallThickness = 1
    local wallHeight = 50

    -- Create 4 walls
    local wallPositions = {
        -- Front Wall
        {position = baseplate.Position + Vector3.new(0, wallHeight / 2, baseplateSize.Z / 2 + wallThickness / 2), size = Vector3.new(baseplateSize.X, wallHeight, wallThickness)},
        -- Back Wall
        {position = baseplate.Position + Vector3.new(0, wallHeight / 2, -baseplateSize.Z / 2 - wallThickness / 2), size = Vector3.new(baseplateSize.X, wallHeight, wallThickness)},
        -- Right Wall
        {position = baseplate.Position + Vector3.new(baseplateSize.X / 2 + wallThickness / 2, wallHeight / 2, 0), size = Vector3.new(wallThickness, wallHeight, baseplateSize.Z)},
        -- Left Wall
        {position = baseplate.Position + Vector3.new(-baseplateSize.X / 2 - wallThickness / 2, wallHeight / 2, 0), size = Vector3.new(wallThickness, wallHeight, baseplateSize.Z)}
    }

    for _, wall in ipairs(wallPositions) do
        local part = Instance.new("Part")
        part.Color = Color3.new(0, 0, 0)
        part.Size = wall.size
        part.Position = wall.position
        part.Anchored = true
        part.Parent = wallsModel
    end

    -- Create the ceiling
    local ceiling = Instance.new("Part")
    ceiling.Color = Color3.new(0, 0, 0)
    ceiling.Size = Vector3.new(baseplateSize.X, wallThickness, baseplateSize.Z)
    ceiling.Position = baseplate.Position + Vector3.new(0, wallHeight + wallThickness / 2, 0)
    ceiling.Anchored = true
    ceiling.Parent = wallsModel
end

local function createSpotLight(part)
    local spotLightPart = Instance.new("Part")
    spotLightPart.Size = Vector3.new(2, 2, 2)
    spotLightPart.Position = part.Position + Vector3.new(0, 40, 0) -- 50 studs above the button part
    spotLightPart.Anchored = true
    spotLightPart.Transparency = 1 -- Make the part invisible
    spotLightPart.Parent = workspace

    local spotLight = Instance.new("SpotLight")
    spotLight.Face = Enum.NormalId.Bottom
    spotLight.Range = 60
    spotLight.Shadows = true
    spotLight.Angle = 90
    spotLight.Brightness = 40
    spotLight.Parent = spotLightPart
end

local function createParts(totalParts, partsPerRow, spacing, startPosition, buttonsModel)
    for index = 1, totalParts do
        local x = (index - 1) % partsPerRow
        local z = math.floor((index - 1) / partsPerRow)
        local part = Instance.new("Part")
        part.Size = Vector3.new(5, 5, 5) -- Size of each part
        part.Position = startPosition + Vector3.new(x * spacing, 1, z * spacing)
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 1 -- Make the part semi-transparent

        part.Parent = buttonsModel

        CollectionService:AddTag(part, "button")

        -- Clone the "tycoonBtn" prefab and set its position using PivotTo
        local prefab = PrefabFolder:FindFirstChild("tycoonBtn")
        if prefab then
            local clonedPrefab = prefab:Clone()
            local rotation = CFrame.Angles(0, 0, math.rad(-90)) -- Rotate 90 degrees around the X axis
            local offset = Vector3.new(0, -clonedPrefab.PrimaryPart.Size.Y / 2, 0) -- Move down by half the height of the prefab's primary part
            clonedPrefab:PivotTo(part.CFrame * rotation + offset)
            clonedPrefab.Parent = part
        end

        -- Create a spotlight above each button part
        createSpotLight(part)

        local zone = Zone.new(part)

        zone.associatedPart = part

        zone.playerEntered:Connect(function(player)
            print(player.Name .. " entered the zone of part " .. index)
            local tycoonBtn = zone.associatedPart:FindFirstChild("tycoonBtn")
            if tycoonBtn then
                local button = tycoonBtn:FindFirstChild("Button")
                if button then
                    button.Color = Color3.new(1, 0, 0) -- Set the button color to red
                end
            end
        end)
        zone.playerExited:Connect(function(player)
            print(player.Name .. " exited the zone of part " .. index)
        end)
    end
end

function initButtons:KnitStart()
    local spacing = 50 -- Adjust the spacing between parts as needed
    local totalParts = 1024
    local partsPerRow = math.floor(math.sqrt(totalParts)) -- Calculate number of parts per row
    local partsPerColumn = math.ceil(totalParts / partsPerRow) -- Calculate number of rows

    -- Calculate the total dimensions of the grid
    local gridTotalWidth = (partsPerRow - 1) * spacing + 5
    local gridTotalDepth = (partsPerColumn - 1) * spacing + 5

    -- Find or create the baseplate
    local baseplate = workspace:FindFirstChild("Baseplate")
    if not baseplate then
        baseplate = Instance.new("Part")
        baseplate.Name = "Baseplate"
        baseplate.Anchored = true
        baseplate.Position = Vector3.new(0, 0, 0)
        baseplate.Parent = workspace
    end

    -- Adjust the baseplate size to fit the grid
    baseplate.Size = Vector3.new(gridTotalWidth + spacing, 1, gridTotalDepth + spacing)
    baseplate.Position = Vector3.new(0, -0.5, 0) -- Adjust Y position to align with the grid

    -- Create the walls and ceiling
    createWallsAndCeiling(baseplate)

    -- Calculate the start position to center the grid on the baseplate and position above it
    local startPosition = baseplate.Position - Vector3.new(gridTotalWidth / 2, 0, gridTotalDepth / 2)
    startPosition = startPosition + Vector3.new(0, baseplate.Size.Y / 2 + 2.5, 0) -- Adjust to be above the baseplate

    -- Create a model to group all buttons
    local buttonsModel = Instance.new("Model")
    buttonsModel.Name = "Buttons"
    buttonsModel.Parent = workspace

    createParts(totalParts, partsPerRow, spacing, startPosition, buttonsModel)
end

function initButtons:KnitInit()
    -- Add service initialization logic here
end

return initButtons
