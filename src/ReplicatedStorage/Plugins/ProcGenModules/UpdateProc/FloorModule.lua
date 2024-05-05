local Floor = {}
Floor.__index = Floor



function Floor.new(modelParent, tilesFolder)
    local self = setmetatable({}, Floor)
    self.modelParent = modelParent
    self.tilesFolder = tilesFolder

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

function Floor:generateFloor(numTilesX, numTilesZ)
	local tiles = self.tilesFolder:GetChildren()
	if #tiles == 0 then
		warn("No tile templates found in tilesFolder")
		return
	end

	local tileSize = tiles[1].Size.X



	local floorTileModel = Instance.new("Model")
	floorTileModel.Name = "FloorTiles"
	floorTileModel.Parent = self.modelParent

	local perimeterTileModel = Instance.new("Model")
	perimeterTileModel.Name = "PerimeterTiles"
	perimeterTileModel.Parent = self.modelParent

	local northTileModel = Instance.new("Model")
	northTileModel.Name = "North"
	northTileModel.Parent = perimeterTileModel

	local southTileModel = Instance.new("Model")
	southTileModel.Name = "South"
	southTileModel.Parent = perimeterTileModel

	local eastTileModel = Instance.new("Model")
	eastTileModel.Name = "East"
	eastTileModel.Parent = perimeterTileModel

	local westTileModel = Instance.new("Model")
	westTileModel.Name = "West"
	westTileModel.Parent = perimeterTileModel

	local CornersTileModel = Instance.new("Model")
	CornersTileModel.Name = "CornersTileModel"
	CornersTileModel.Parent = perimeterTileModel

	local NorthwestcornerTileModel = Instance.new("Model")
	NorthwestcornerTileModel.Name = "NorthwestcornerTileModel"
	NorthwestcornerTileModel.Parent = CornersTileModel

    local SouthwestcornerTileModel = Instance.new("Model")
	SouthwestcornerTileModel.Name = "SouthwestcornerTileModel"
	SouthwestcornerTileModel.Parent = CornersTileModel

    local NortheastcornerTileModel = Instance.new("Model")
	NortheastcornerTileModel.Name = "NortheastcornerTileModel"
	NortheastcornerTileModel.Parent = CornersTileModel

    local SoutheastcornerTileModel = Instance.new("Model")
	SoutheastcornerTileModel.Name = "SoutheastcornerTileModel"
	SoutheastcornerTileModel.Parent = CornersTileModel

    numTilesX = numTilesX
    numTilesZ = numTilesZ 

    for x = 1, numTilesX do
        for z = 1, numTilesZ do
            local randomIndex = math.random(#tiles)
            local tileTemplate = tiles[randomIndex]
            local tile = tileTemplate:Clone()

            tile.Position = Vector3.new((x - 0.5) * tileSize, 0, (z - 0.5) * tileSize)
            tile.Anchored = true
            tile.Name = "Tile_" .. x .. "_" .. z

            -- Create a new part for each tile
            local TilePrimaryPart = Instance.new("Part")
            TilePrimaryPart.Size = Vector3.new(.5, 1, .5)  -- Assuming 1 is the height you want for the part
            TilePrimaryPart.Position = Vector3.new((x - 0.5) * tileSize, 0, (z - 0.5) * tileSize)
            TilePrimaryPart.Anchored = true
            TilePrimaryPart.CanCollide = false
            TilePrimaryPart.Name = "BasePart_" .. x .. "_" .. z

            -- Create a new part for each tile
            local TileModel = Instance.new("Model")
            TileModel.Name = "Tile_Model_" .. x .. "_" .. z

            TilePrimaryPart.Parent = TileModel
            TileModel.PrimaryPart = TilePrimaryPart

               -- Additional Part for Perimeter Tiles
               if x == 1 or x == numTilesX or z == 1 or z == numTilesZ then
                local extraPart = Instance.new("Part")
                extraPart.Size = Vector3.new(.5, 1, .5)  -- Size can be adjusted based on visual preference
                extraPart.Anchored = true
                extraPart.CanCollide = false
                extraPart.Color = Color3.fromRGB(120, 120, 120)  -- Distinct color for visual differentiation
                extraPart.Name = "PerimeterExtraPart_" .. x .. "_" .. z
            
                -- First part position based on the tile's perimeter location
                if x == 1 then
                    extraPart.Position = Vector3.new((x - 1) * tileSize, 0, (z - 0.5) * tileSize)
                elseif x == numTilesX then
                    extraPart.Position = Vector3.new((x) * tileSize, 0, (z - 0.5) * tileSize)
                elseif z == 1 then
                    extraPart.Position = Vector3.new((x - 0.5) * tileSize, 0, (z - 1) * tileSize)
                elseif z == numTilesZ then
                    extraPart.Position = Vector3.new((x - 0.5) * tileSize, 0, (z) * tileSize)
                end
            
                extraPart.Parent = TileModel  -- Parenting to the same model for organizational simplicity
            
                -- Additional part for corner tiles (adding the second part on the adjacent edge)
                -- Additional part for corner tiles (adding the second part on the adjacent edge)
                if (x == 1 or x == numTilesX) and (z == 1 or z == numTilesZ) then
                    local extraPartCorner = Instance.new("Part")
                    extraPartCorner.Size = Vector3.new(.5, 1, .5)
                    extraPartCorner.Anchored = true
                    extraPartCorner.CanCollide = false
                    extraPartCorner.Color = Color3.fromRGB(120, 120, 120)
                    extraPartCorner.Name = "CornerExtraPart_" .. x .. "_" .. z

                    -- Adjust corner part position to be centered on the other adjacent edge
                    if x == 1 and z == 1 then
                        extraPartCorner.Position = Vector3.new((x - 0.5) * tileSize, 0, (z - 1) * tileSize)  -- West edge
                    elseif x == 1 and z == numTilesZ then
                        extraPartCorner.Position = Vector3.new((x - 0.5) * tileSize, 0, (z) * tileSize)      -- West edge
                    elseif x == numTilesX and z == 1 then
                        extraPartCorner.Position = Vector3.new((x - 0.5) * tileSize, 0, (z - 1) * tileSize)  -- East edge
                    elseif x == numTilesX and z == numTilesZ then
                        extraPartCorner.Position = Vector3.new((x - 0.5) * tileSize, 0, (z) * tileSize)      -- East edge
                    end

                    extraPartCorner.Parent = TileModel  -- Parenting to the same model
                end


            end
            

            if x == 1 and z == 1 then
                tile.Name = tile.Name .. "_Northwest"
                TileModel.Parent = NorthwestcornerTileModel
                tile.Parent = TileModel

                table.insert(self.models.PerimeterTiles.Corners.Northwest, TileModel)
            elseif x == 1 and z == numTilesZ then
                tile.Name = tile.Name .. "_Southwest"
                TileModel.Parent = SouthwestcornerTileModel
                table.insert(self.models.PerimeterTiles.Corners.Southwest, TileModel)
                tile.Parent = TileModel

            elseif x == numTilesX and z == 1 then
                tile.Name = tile.Name .. "_Northeast"
                TileModel.Parent = NortheastcornerTileModel
                table.insert(self.models.PerimeterTiles.Corners.Northeast, TileModel)
                tile.Parent = TileModel

            elseif x == numTilesX and z == numTilesZ then
                tile.Name = tile.Name .. "_Southeast"
                TileModel.Parent = SoutheastcornerTileModel
                table.insert(self.models.PerimeterTiles.Corners.Southeast, TileModel)
                tile.Parent = TileModel

          
            elseif x == 1 or x == numTilesX or z == 1 or z == numTilesZ then
                tile.Name = tile.Name .. "_Perimeter"
                tile.Color = Color3.fromRGB(255, 150, 150)
                if x == 1 then
                    TileModel.Parent = westTileModel
                    tile.Parent = TileModel

                elseif x == numTilesX then
                    TileModel.Parent = eastTileModel
                    tile.Parent = TileModel

                elseif z == 1 then
                   
                    TileModel.Parent = northTileModel
                    tile.Parent = TileModel

                elseif z == numTilesZ then
                   
                    TileModel.Parent = southTileModel
                    tile.Parent = TileModel

                end
                local modelKey = x == 1 and "West" or x == numTilesX and "East" or z == 1 and "North" or "South"
                table.insert(self.models.PerimeterTiles[modelKey], TileModel)


            else
                tile.Color = tileTemplate.Color
                TileModel.Parent = floorTileModel
                tile.Parent = TileModel

                table.insert(self.models.FloorTiles, TileModel)

            end
        end
    end

    Floor:processPerimeterTiles(self.models)
    --table.insert(Floor, self.models)
    --print(models)
end

function Floor:processPerimeterTiles(models)
    -- Ensure the models table and necessary sub-tables are properly set
    if not models or not models.PerimeterTiles then
        warn("Invalid models table or missing PerimeterTiles key")
        return
    end

    local function processTiles(tileList)
       
        
    end

    -- Process each category of perimeter tiles with specific operations
    processTiles(models.PerimeterTiles.Corners)
    processTiles(models.PerimeterTiles.East)
    processTiles(models.PerimeterTiles.West)
    processTiles(models.PerimeterTiles.North)
    processTiles(models.PerimeterTiles.South)
    
end

return Floor
