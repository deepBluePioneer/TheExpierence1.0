local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Replica Module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica.ReplicaController)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local MapController = Knit.CreateController {
	Name = "MapController",
	gridCells = {},  -- Store references to grid cell frames
	playerMarkers = {},  -- Store player marker frames
	gridWidth = 25,
	gridDepth = 25,
}

-- === CONFIG ===
local MAP_SIZE = 200  -- Size of the minimap in pixels
local MAP_PADDING = 20  -- Padding from screen edge
local CELL_COLOR = Color3.fromRGB(40, 40, 50)
local CELL_COLOR_ALT = Color3.fromRGB(50, 50, 60)
local PLAYER_COLOR = Color3.fromRGB(0, 255, 100)
local OTHER_PLAYER_COLOR = Color3.fromRGB(255, 100, 100)
local HIGHLIGHT_COLOR = Color3.fromRGB(100, 200, 255)

-- Fog of War colors
local FOG_COLOR = Color3.fromRGB(15, 15, 20)  -- Dark unexplored
local FOG_TRANSPARENCY = 0  -- Fully opaque fog

-- === GUI CREATION ===

local function createMapGui(self)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MapGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = PlayerGui
	
	-- Main container frame (bottom left)
	local container = Instance.new("Frame")
	container.Name = "MapContainer"
	container.Size = UDim2.new(0, MAP_SIZE + 20, 0, MAP_SIZE + 40)
	container.Position = UDim2.new(0, MAP_PADDING, 1, -MAP_SIZE - 60)
	container.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	container.BorderSizePixel = 0
	container.Parent = screenGui
	
	-- Corner rounding
	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 12)
	containerCorner.Parent = container
	
	-- Stroke
	local containerStroke = Instance.new("UIStroke")
	containerStroke.Color = Color3.fromRGB(80, 80, 100)
	containerStroke.Thickness = 2
	containerStroke.Parent = container
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Position = UDim2.new(0, 0, 0, 5)
	title.BackgroundTransparency = 1
	title.Text = "GRID MAP"
	title.TextColor3 = Color3.fromRGB(180, 180, 200)
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.Parent = container
	
	-- Map frame (holds the grid)
	local mapFrame = Instance.new("Frame")
	mapFrame.Name = "MapFrame"
	mapFrame.Size = UDim2.new(0, MAP_SIZE, 0, MAP_SIZE)
	mapFrame.Position = UDim2.new(0, 10, 0, 35)
	mapFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	mapFrame.BorderSizePixel = 0
	mapFrame.ClipsDescendants = true
	mapFrame.Parent = container
	
	local mapCorner = Instance.new("UICorner")
	mapCorner.CornerRadius = UDim.new(0, 8)
	mapCorner.Parent = mapFrame
	
	return mapFrame
end

local function createGridCells(self, mapFrame, gridWidth, gridDepth, exploredCells)
	local cellSize = MAP_SIZE / math.max(gridWidth, gridDepth)
	
	for x = 1, gridWidth do
		for z = 1, gridDepth do
			local cell = Instance.new("Frame")
			cell.Name = string.format("Cell_%d_%d", x, z)
			cell.Size = UDim2.new(0, cellSize, 0, cellSize)
			cell.Position = UDim2.new(0, (x - 1) * cellSize, 0, (z - 1) * cellSize)
			cell.BorderSizePixel = 0
			
			local key = string.format("%d_%d", x, z)
			local isExplored = exploredCells and exploredCells[key]
			
			-- Start with fog of war (dark) unless already explored
			if isExplored then
				if (x + z) % 2 == 0 then
					cell.BackgroundColor3 = CELL_COLOR
				else
					cell.BackgroundColor3 = CELL_COLOR_ALT
				end
			else
				cell.BackgroundColor3 = FOG_COLOR
			end
			
			cell.Parent = mapFrame
			
			-- Store reference
			self.gridCells[key] = cell
		end
	end
end

local function revealCell(self, key)
	local cell = self.gridCells[key]
	if cell then
		local x, z = key:match("(%d+)_(%d+)")
		x, z = tonumber(x), tonumber(z)
		
		-- Reveal with checkerboard color
		if (x + z) % 2 == 0 then
			cell.BackgroundColor3 = CELL_COLOR
		else
			cell.BackgroundColor3 = CELL_COLOR_ALT
		end
	end
end

local function createPlayerMarker(self, mapFrame, userId, playerName, isLocalPlayer)
	local cellSize = MAP_SIZE / math.max(self.gridWidth, self.gridDepth)
	local markerSize = cellSize * 0.8
	
	local marker = Instance.new("Frame")
	marker.Name = "PlayerMarker_" .. userId
	marker.Size = UDim2.new(0, markerSize, 0, markerSize)
	marker.BackgroundColor3 = isLocalPlayer and PLAYER_COLOR or OTHER_PLAYER_COLOR
	marker.BorderSizePixel = 0
	marker.ZIndex = 10
	marker.Parent = mapFrame
	
	local markerCorner = Instance.new("UICorner")
	markerCorner.CornerRadius = UDim.new(1, 0)  -- Circle
	markerCorner.Parent = marker
	
	-- Player name label (only for other players)
	if not isLocalPlayer then
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "NameLabel"
		nameLabel.Size = UDim2.new(0, 50, 0, 12)
		nameLabel.Position = UDim2.new(0.5, -25, 1, 2)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = playerName
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextSize = 8
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.ZIndex = 11
		nameLabel.Parent = marker
	end
	
	self.playerMarkers[userId] = marker
	return marker
end

local function updatePlayerPosition(self, mapFrame, userId, x, z, playerName)
	local cellSize = MAP_SIZE / math.max(self.gridWidth, self.gridDepth)
	local markerSize = cellSize * 0.8
	
	local isLocalPlayer = userId == tostring(Player.UserId)
	
	-- Create marker if doesn't exist
	if not self.playerMarkers[userId] then
		createPlayerMarker(self, mapFrame, userId, playerName, isLocalPlayer)
	end
	
	local marker = self.playerMarkers[userId]
	if marker then
		-- Center the marker in the cell
		local posX = (x - 1) * cellSize + (cellSize - markerSize) / 2
		local posZ = (z - 1) * cellSize + (cellSize - markerSize) / 2
		marker.Position = UDim2.new(0, posX, 0, posZ)
	end
	
	-- Highlight current cell for local player
	if isLocalPlayer then
		-- Reset all explored cells first
		for cellKey, cell in pairs(self.gridCells) do
			local cellX, cellZ = cell.Name:match("Cell_(%d+)_(%d+)")
			cellX, cellZ = tonumber(cellX), tonumber(cellZ)
			-- Only reset if not fog (explored)
			if cell.BackgroundColor3 ~= FOG_COLOR then
				if (cellX + cellZ) % 2 == 0 then
					cell.BackgroundColor3 = CELL_COLOR
				else
					cell.BackgroundColor3 = CELL_COLOR_ALT
				end
			end
		end
		
		-- Highlight current cell
		local key = string.format("%d_%d", x, z)
		if self.gridCells[key] then
			self.gridCells[key].BackgroundColor3 = HIGHLIGHT_COLOR
		end
	end
end

local function removePlayerMarker(self, userId)
	if self.playerMarkers[userId] then
		self.playerMarkers[userId]:Destroy()
		self.playerMarkers[userId] = nil
	end
end

-- === KNIT LIFECYCLE ===

function MapController:KnitInit()
	-- Request replica data (if not already done by TimerController)
	if not ReplicaController.InitialDataReceived then
		ReplicaController.RequestData()
	end
end

function MapController:KnitStart()
	local mapFrame = createMapGui(self)
	
	-- Listen for the GridMapReplica
	ReplicaController.ReplicaOfClassCreated("GridMapReplica", function(replica)
		print("[MapController] Received GridMapReplica")
		
		-- Store grid dimensions
		self.gridWidth = replica.Data.GridWidth
		self.gridDepth = replica.Data.GridDepth
		
		-- Create grid cells with initial explored state (fog of war)
		createGridCells(self, mapFrame, self.gridWidth, self.gridDepth, replica.Data.ExploredCells)
		
		-- Set initial player positions
		for userId, posData in pairs(replica.Data.PlayerPositions) do
			updatePlayerPosition(self, mapFrame, userId, posData.X, posData.Z, posData.Name)
		end
		
		-- Listen for new players entering zones
		replica:ListenToNewKey({"PlayerPositions"}, function(newValue, newKey)
			print("[MapController] New player on map:", newKey)
			updatePlayerPosition(self, mapFrame, newKey, newValue.X, newValue.Z, newValue.Name)
		end)
		
		-- Listen for player position changes
		replica:ListenToChange({"PlayerPositions"}, function(newPositions)
			for userId, posData in pairs(newPositions) do
				updatePlayerPosition(self, mapFrame, userId, posData.X, posData.Z, posData.Name)
			end
		end)
		
		-- Listen for fog of war reveals (ExploredCells)
		replica:ListenToNewKey({"ExploredCells"}, function(newValue, cellKey)
			revealCell(self, cellKey)
		end)
		
		-- Listen for raw changes to catch individual updates
		replica:ListenToRaw(function(actionName, pathArray, ...)
			if actionName == "SetValue" then
				-- Player position update
				if pathArray[1] == "PlayerPositions" and pathArray[2] then
					local userId = pathArray[2]
					local posData = ...
					if posData then
						updatePlayerPosition(self, mapFrame, userId, posData.X, posData.Z, posData.Name)
					end
				-- Fog of war reveal
				elseif pathArray[1] == "ExploredCells" and pathArray[2] then
					local cellKey = pathArray[2]
					revealCell(self, cellKey)
				end
			end
		end)
	end)
	
	-- Clean up markers when players leave
	Players.PlayerRemoving:Connect(function(player)
		removePlayerMarker(self, tostring(player.UserId))
	end)
end

return MapController

