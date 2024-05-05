local DecoratorModule = {}
DecoratorModule.__index = DecoratorModule



function DecoratorModule.new(modelParent, tilesFolder, gridCells)
    local self = setmetatable({}, DecoratorModule)
    self.modelParent = modelParent
    self.tilesFolder = tilesFolder
    self.gridCells = gridCells  -- Now storing a subset of grid cells

    -- Initialize the models table here within the constructor
    self.models = {
        FloorTiles = {},
        PerimeterTiles = {
            North = {},
            South = {},
            East = {},
            West = {},
            Corners = {
                Northeast = {},
                Northwest = {},
                Southeast = {},
                Southwest = {}
            }
        }
    }
    return self
end

function DecoratorModule:generateDecorations(numTilesX, numTilesZ)
    -- Fetch all decoration objects from the folder
    local decorationsFolder = self.tilesFolder:GetChildren()

    if #decorationsFolder == 0 then
        warn("No decoration templates found in tilesFolder")
        return
    end

    -- We need to ensure each grid cell can potentially receive a decoration
    for x = 1, numTilesX do
        for z = 1, numTilesZ do
            -- Determine if a decoration should be placed in this cell
            if math.random() < 0.75 then -- Assuming a 20% chance to place a decoration
                local randomIndex = math.random(#decorationsFolder)
                local decorationTemplate = decorationsFolder[randomIndex]
                local decoration = decorationTemplate:Clone()

                -- Calculate the position for the decoration based on the cell's CFrame
                -- Assuming each cell has a CFrame and a Position stored in gridCells
                if self.gridCells[x] and self.gridCells[x][z] then
                    local targetCFrame = self.gridCells[x][z].CFrame * CFrame.new(0, .2, 0)

                    decoration:PivotTo(targetCFrame)
                    
                    decoration.Parent = self.modelParent -- Ensure the decoration is parented to the model
                else
                    warn("Grid cell at " .. x .. ", " .. z .. " does not exist.")
                end
            end
        end
    end
end






return DecoratorModule
