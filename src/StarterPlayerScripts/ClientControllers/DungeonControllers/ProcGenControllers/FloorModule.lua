local Floor = {}
Floor.__index = Floor



function Floor.new(modelParent, tilesFolder, gridCells)
    local self = setmetatable({}, Floor)
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

function Floor:generateFloor(numTilesX, numTilesZ )
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

    local randomIndex = math.random(#tiles)
    for x = 1, numTilesX do
        for z = 1, numTilesZ do
            local tileTemplate = tiles[randomIndex]
            local tile = tileTemplate:Clone()

            tile.Position = Vector3.new(self.gridCells[x][z].Position.x, .2, self.gridCells[x][z].Position.z)
            
            tile.Anchored = true
            tile.Name = "Tile_" .. x .. "_" .. z

            -- Create a new part for each tile
            local TilePrimaryPart = Instance.new("Part")
            TilePrimaryPart.Size = Vector3.new(.5, 1, .5)  -- Assuming 1 is the height you want for the part
            TilePrimaryPart.Position =  tile.Position
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
                extraPart.Size = Vector3.new(0.5, 1, 0.5)  -- Size can be adjusted based on visual preference
                extraPart.Anchored = true
                extraPart.CanCollide = false
                extraPart.Color = Color3.fromRGB(120, 120, 120)  -- Distinct color for visual differentiation
                extraPart.Name = "PerimeterExtraPart_" .. x .. "_" .. z
                -- Positioning based on perimeter location
                local xOffset = 0
                local zOffset = 0
                if x == 1 then
                    xOffset = -tileSize / 2
                elseif x == numTilesX then
                    xOffset = tileSize / 2
                end
                if z == 1 then
                    zOffset = -tileSize / 2
                elseif z == numTilesZ then
                    zOffset = tileSize / 2
            end

               

            extraPart.CFrame = self.gridCells[x][z].CFrame * CFrame.new(xOffset, 0, zOffset)
        
            extraPart.Parent = TileModel  -- Parenting to the same model for organizational simplicity
        
            -- Additional adjustments for corner tiles
            if (x == 1 or x == numTilesX) and (z == 1 or z == numTilesZ) then
                local extraPartCorner = Instance.new("Part")
                extraPartCorner.Size = Vector3.new(0.75, 1, 0.75)
                extraPartCorner.Anchored = true
                extraPartCorner.CanCollide = false
                extraPartCorner.Color = Color3.fromRGB(155, 42, 255)
                extraPartCorner.Name = "CornerExtraPart_" .. x .. "_" .. z

                -- Calculate the correct offset to position the part at the edge's midpoint
                local cornerXOffset = xOffset  -- Start with existing offset for the edge
                local cornerZOffset = zOffset  -- Start with existing offset for the edge

                -- Adjust offsets based on corner location
                if x == 1 then
                    cornerXOffset = cornerXOffset - extraPartCorner.Size.X / 2
                elseif x == numTilesX then
                    cornerXOffset = cornerXOffset + extraPartCorner.Size.X / 2
                end
                if z == 1 then
                    cornerZOffset = cornerZOffset - extraPartCorner.Size.Z / 2
                elseif z == numTilesZ then
                    cornerZOffset = cornerZOffset + extraPartCorner.Size.Z / 2
                end

                -- Set the CFrame using the calculated offsets
                extraPartCorner.CFrame = self.gridCells[x][z].CFrame * CFrame.new(cornerXOffset, 0, cornerZOffset)
                extraPartCorner.Parent = TileModel
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

    Floor:processPerimeterCorners(self.models.PerimeterTiles.Corners)
    --table.insert(Floor, self.models)
    --print(models)
end


function Floor:processPerimeterCorners(corners)
    for cornerName, tiles in pairs(corners) do
        for i, tileModel in ipairs(tiles) do
            local direction = ""
            local PerimeterExtraPartString = "PerimeterExtraPart"
            local CornerExtraPartString = "CornerExtraPart"
            local TileString = "Tile"
            
            local PerimeterExtraPart, CornerExtraPart, tile
            local children = tileModel:GetChildren()
            
            for j, part in ipairs(children) do
                if string.find(part.Name, PerimeterExtraPartString) then
                    PerimeterExtraPart = part
                elseif string.find(part.Name, CornerExtraPartString) then
                    CornerExtraPart = part
                elseif string.find(part.Name, TileString) then
                    tile = part
                end
            end

            if tile and PerimeterExtraPart and CornerExtraPart then
                local tileCFrame = tile.CFrame
                local tileSize = tile.Size
                local newPos, cornerPos

                -- Adjustments for placing the PerimeterExtraPart
                if cornerName == "Northeast" then
                    direction = "Facing SouthWest"
                    newPos = tileCFrame * CFrame.new(tileSize.X / 2, 0, 0)  -- Right edge
                    cornerPos = tileCFrame * CFrame.new(0, 0, -tileSize.Z / 2)  -- Bottom edge
                elseif cornerName == "Northwest" then
                    direction = "Facing SouthEast"
                    newPos = tileCFrame * CFrame.new(-tileSize.X / 2, 0, 0)  -- Left edge
                    cornerPos = tileCFrame * CFrame.new(0, 0, -tileSize.Z / 2)  -- Bottom edge
                elseif cornerName == "Southeast" then
                    direction = "Facing NorthWest"
                    newPos = tileCFrame * CFrame.new(tileSize.X / 2, 0, 0)  -- Right edge
                    cornerPos = tileCFrame * CFrame.new(0, 0, tileSize.Z / 2)  -- Top edge
                elseif cornerName == "Southwest" then
                    direction = "Facing NorthEast"
                    newPos = tileCFrame * CFrame.new(-tileSize.X / 2, 0, 0)  -- Left edge
                    cornerPos = tileCFrame * CFrame.new(0, 0, tileSize.Z / 2)  -- Top edge
                end

                -- Explicitly set the Y position to 0 to ensure no vertical movement
                newPos = newPos + Vector3.new(0, -newPos.Y, 0)
                cornerPos = cornerPos + Vector3.new(0, -cornerPos.Y, 0)

                -- Update the CFrame of both parts to the new positions
                if newPos and cornerPos then
                    PerimeterExtraPart.CFrame = newPos
                    CornerExtraPart.CFrame = cornerPos
                end
            end
        end
    end
end








return Floor
