--[[
	PlaygroundController
	Creates a procedurally generated dungeon level with verticality
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local PlaygroundController = Knit.CreateController {
	Name = "PlaygroundController",
	
	_levelFolder = nil,
	_parts = {},
	_rooms = {},
	_grid = {},
	_spawnPos = nil,
	_exitPos = nil,
	_spawnLocation = nil,
	
	-- Atmosphere
	_flickeringLights = {},
	_flickerConnection = nil,
	_dustEmitters = {},
}

-- === CONFIG ===
local CONFIG = {
	-- Level size (in tiles)
	GridWidth = 50,
	GridHeight = 50,
	
	-- Room settings
	MinRooms = 8,
	MaxRooms = 12,
	MinRoomSize = 6,
	MaxRoomSize = 14,
	
	-- Tile scale (studs per tile) - BRUTALIST: Massive scale
	TileSize = 8,
	WallHeight = 20,
	CeilingHeight = 20,
	FloorThickness = 2,
	WallThickness = 1.5,
	
	-- Verticality
	PlatformChance = 0,        -- No raised platforms
	PlatformHeight = 6,        -- (unused)
	PillarChance = 0.5,        -- More pillars
	BeamChance = 0.6,          -- Exposed ceiling beams
	
	-- Atmosphere
	FlickeringLightChance = 0.4,  -- Chance for lights to flicker
	DebrisPerRoom = 4,            -- Average debris items per room
	DustParticlesEnabled = true,
	FogEnabled = true,
	
	-- Debris types
	DebrisColors = {
		Color3.fromRGB(50, 45, 40),
		Color3.fromRGB(60, 55, 48),
		Color3.fromRGB(40, 38, 35),
		Color3.fromRGB(70, 60, 50),
	},
	
	-- BRUTALIST Colors - Raw concrete, dark, oppressive
	Colors = {
		Floor = Color3.fromRGB(35, 33, 30),
		FloorAccent = Color3.fromRGB(25, 23, 20),
		Wall = Color3.fromRGB(45, 42, 38),
		WallDark = Color3.fromRGB(28, 26, 24),
		WallTrim = Color3.fromRGB(20, 18, 16),
		Ceiling = Color3.fromRGB(30, 28, 25),
		Corridor = Color3.fromRGB(32, 30, 28),
		Platform = Color3.fromRGB(40, 38, 35),
		PlatformEdge = Color3.fromRGB(55, 52, 48),
		Pillar = Color3.fromRGB(50, 47, 42),
		PillarDark = Color3.fromRGB(30, 28, 25),
		Stairs = Color3.fromRGB(42, 40, 36),
		Railing = Color3.fromRGB(25, 23, 20),
		Beam = Color3.fromRGB(38, 35, 32),
		Spawn = Color3.fromRGB(180, 60, 60),      -- Menacing red
		Exit = Color3.fromRGB(200, 150, 50),      -- Warning amber
		Light = Color3.fromRGB(255, 180, 120),    -- Harsh industrial
		LightDim = Color3.fromRGB(150, 100, 60),  -- Dim accent
	},
}

-- Tile types
local TILE = {
	EMPTY = 0,
	FLOOR = 1,
	WALL = 2,
	CORRIDOR = 3,
}

-- === GRID HELPERS ===

function PlaygroundController:InitGrid()
	self._grid = {}
	for y = 1, CONFIG.GridHeight do
		self._grid[y] = {}
		for x = 1, CONFIG.GridWidth do
			self._grid[y][x] = TILE.EMPTY
		end
	end
end

function PlaygroundController:SetTile(x, y, tileType)
	if x >= 1 and x <= CONFIG.GridWidth and y >= 1 and y <= CONFIG.GridHeight then
		self._grid[y][x] = tileType
	end
end

function PlaygroundController:GetTile(x, y)
	if x >= 1 and x <= CONFIG.GridWidth and y >= 1 and y <= CONFIG.GridHeight then
		return self._grid[y][x]
	end
	return TILE.EMPTY
end

-- === ROOM GENERATION ===

function PlaygroundController:CreateRoom(x, y, width, height)
	local room = {
		x = x,
		y = y,
		width = width,
		height = height,
		centerX = math.floor(x + width / 2),
		centerY = math.floor(y + height / 2),
		hasPlatform = false,
		platformHeight = 0,
		hasPillars = false,
	}
	
	-- Fill room with floor tiles
	for ry = y, y + height - 1 do
		for rx = x, x + width - 1 do
			self:SetTile(rx, ry, TILE.FLOOR)
		end
	end
	
	return room
end

function PlaygroundController:RoomsOverlap(room1, room2, padding)
	padding = padding or 2
	return not (
		room1.x + room1.width + padding < room2.x or
		room2.x + room2.width + padding < room1.x or
		room1.y + room1.height + padding < room2.y or
		room2.y + room2.height + padding < room1.y
	)
end

function PlaygroundController:GenerateRooms()
	self._rooms = {}
	local attempts = 0
	local maxAttempts = 100
	local targetRooms = math.random(CONFIG.MinRooms, CONFIG.MaxRooms)
	
	while #self._rooms < targetRooms and attempts < maxAttempts do
		attempts = attempts + 1
		
		local width = math.random(CONFIG.MinRoomSize, CONFIG.MaxRoomSize)
		local height = math.random(CONFIG.MinRoomSize, CONFIG.MaxRoomSize)
		local x = math.random(2, CONFIG.GridWidth - width - 1)
		local y = math.random(2, CONFIG.GridHeight - height - 1)
		
		local newRoom = {
			x = x,
			y = y,
			width = width,
			height = height,
			centerX = math.floor(x + width / 2),
			centerY = math.floor(y + height / 2),
			hasPlatform = false,
			platformHeight = 0,
			hasPillars = false,
		}
		
		local overlaps = false
		for _, existingRoom in ipairs(self._rooms) do
			if self:RoomsOverlap(newRoom, existingRoom, 2) then
				overlaps = true
				break
			end
		end
		
		if not overlaps then
			self:CreateRoom(x, y, width, height)
			
			-- Decide verticality features (skip first room - spawn)
			if #self._rooms > 0 then
				if math.random() < CONFIG.PlatformChance and width >= 6 and height >= 6 then
					newRoom.hasPlatform = true
					newRoom.platformHeight = CONFIG.PlatformHeight
				end
				if math.random() < CONFIG.PillarChance and width >= 5 and height >= 5 then
					newRoom.hasPillars = true
				end
				if math.random() < CONFIG.BeamChance and width >= 4 and height >= 4 then
					newRoom.hasBeams = true
				end
			end
			
			table.insert(self._rooms, newRoom)
		end
	end
	
	print("[Playground] Generated", #self._rooms, "rooms")
end

-- === CORRIDOR GENERATION ===

function PlaygroundController:CreateHorizontalCorridor(x1, x2, y)
	local minX = math.min(x1, x2)
	local maxX = math.max(x1, x2)
	
	for x = minX, maxX do
		if self:GetTile(x, y) == TILE.EMPTY then
			self:SetTile(x, y, TILE.CORRIDOR)
		end
		if self:GetTile(x, y - 1) == TILE.EMPTY then
			self:SetTile(x, y - 1, TILE.CORRIDOR)
		end
	end
end

function PlaygroundController:CreateVerticalCorridor(y1, y2, x)
	local minY = math.min(y1, y2)
	local maxY = math.max(y1, y2)
	
	for y = minY, maxY do
		if self:GetTile(x, y) == TILE.EMPTY then
			self:SetTile(x, y, TILE.CORRIDOR)
		end
		if self:GetTile(x - 1, y) == TILE.EMPTY then
			self:SetTile(x - 1, y, TILE.CORRIDOR)
		end
	end
end

function PlaygroundController:ConnectRooms(room1, room2)
	if math.random() < 0.5 then
		self:CreateHorizontalCorridor(room1.centerX, room2.centerX, room1.centerY)
		self:CreateVerticalCorridor(room1.centerY, room2.centerY, room2.centerX)
	else
		self:CreateVerticalCorridor(room1.centerY, room2.centerY, room1.centerX)
		self:CreateHorizontalCorridor(room1.centerX, room2.centerX, room2.centerY)
	end
end

function PlaygroundController:GenerateCorridors()
	for i = 1, #self._rooms - 1 do
		self:ConnectRooms(self._rooms[i], self._rooms[i + 1])
	end
	
	local extraConnections = math.random(1, 3)
	for _ = 1, extraConnections do
		local room1 = self._rooms[math.random(1, #self._rooms)]
		local room2 = self._rooms[math.random(1, #self._rooms)]
		if room1 ~= room2 then
			self:ConnectRooms(room1, room2)
		end
	end
end

-- === WALL GENERATION ===

function PlaygroundController:GenerateWalls()
	for y = 1, CONFIG.GridHeight do
		for x = 1, CONFIG.GridWidth do
			if self:GetTile(x, y) == TILE.FLOOR or self:GetTile(x, y) == TILE.CORRIDOR then
				for dy = -1, 1 do
					for dx = -1, 1 do
						if dx ~= 0 or dy ~= 0 then
							local nx, ny = x + dx, y + dy
							if self:GetTile(nx, ny) == TILE.EMPTY then
								self:SetTile(nx, ny, TILE.WALL)
							end
						end
					end
				end
			end
		end
	end
end

-- === 3D RENDERING ===

function PlaygroundController:TileToWorld(x, y)
	return x * CONFIG.TileSize, y * CONFIG.TileSize
end

function PlaygroundController:CreatePart(name, size, position, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color or CONFIG.Colors.Wall
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = self._levelFolder
	table.insert(self._parts, part)
	return part
end

function PlaygroundController:CreateWedge(name, size, position, color, rotation)
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.Position = position
	wedge.Color = color or CONFIG.Colors.Stairs
	wedge.Material = Enum.Material.SmoothPlastic
	wedge.Anchored = true
	wedge.CanCollide = true
	if rotation then
		wedge.Orientation = rotation
	end
	wedge.Parent = self._levelFolder
	table.insert(self._parts, wedge)
	return wedge
end

function PlaygroundController:RenderFloor(x, y, isCorridor)
	local wx, wz = self:TileToWorld(x, y)
	local color = isCorridor and CONFIG.Colors.Corridor or CONFIG.Colors.Floor
	
	-- Thick brutalist floor slab
	self:CreatePart(
		"Floor_" .. x .. "_" .. y,
		Vector3.new(CONFIG.TileSize, CONFIG.FloorThickness, CONFIG.TileSize),
		Vector3.new(wx, -CONFIG.FloorThickness / 2, wz),
		color,
		Enum.Material.Concrete
	)
	
	-- Random floor texture variation (recessed panels)
	if math.random() < 0.15 then
		self:CreatePart(
			"FloorRecess_" .. x .. "_" .. y,
			Vector3.new(CONFIG.TileSize * 0.7, 0.3, CONFIG.TileSize * 0.7),
			Vector3.new(wx, -0.15, wz),
			CONFIG.Colors.FloorAccent,
			Enum.Material.Concrete
		)
	end
end

function PlaygroundController:RenderCeiling(x, y)
	local wx, wz = self:TileToWorld(x, y)
	
	-- Heavy concrete ceiling
	self:CreatePart(
		"Ceiling_" .. x .. "_" .. y,
		Vector3.new(CONFIG.TileSize, CONFIG.FloorThickness * 1.5, CONFIG.TileSize),
		Vector3.new(wx, CONFIG.CeilingHeight + CONFIG.FloorThickness, wz),
		CONFIG.Colors.Ceiling,
		Enum.Material.Concrete
	)
end

function PlaygroundController:RenderWall(x, y)
	local wx, wz = self:TileToWorld(x, y)
	
	-- Massive brutalist wall (floor to ceiling)
	self:CreatePart(
		"Wall_" .. x .. "_" .. y,
		Vector3.new(CONFIG.TileSize + CONFIG.WallThickness, CONFIG.CeilingHeight + CONFIG.FloorThickness * 2, CONFIG.TileSize + CONFIG.WallThickness),
		Vector3.new(wx, CONFIG.CeilingHeight / 2, wz),
		CONFIG.Colors.Wall,
		Enum.Material.Concrete
	)
	
	-- Brutalist base - thick concrete foundation
	self:CreatePart(
		"WallBase_" .. x .. "_" .. y,
		Vector3.new(CONFIG.TileSize + CONFIG.WallThickness + 0.5, 1.5, CONFIG.TileSize + CONFIG.WallThickness + 0.5),
		Vector3.new(wx, 0.75, wz),
		CONFIG.Colors.WallDark,
		Enum.Material.Concrete
	)
	
	-- Random wall texture - vertical recesses (brutalist detail)
	if math.random() < 0.2 then
		local recessHeight = CONFIG.CeilingHeight * 0.6
		self:CreatePart(
			"WallRecess_" .. x .. "_" .. y,
			Vector3.new(CONFIG.TileSize * 0.3, recessHeight, 0.5),
			Vector3.new(wx, CONFIG.CeilingHeight * 0.4, wz + CONFIG.TileSize * 0.4),
			CONFIG.Colors.WallDark,
			Enum.Material.Concrete
		)
	end
end

function PlaygroundController:RenderRoomPlatform(room)
	local wx, wz = self:TileToWorld(room.centerX, room.centerY)
	local platformWidth = (room.width - 2) * CONFIG.TileSize
	local platformDepth = (room.height - 2) * CONFIG.TileSize
	local h = room.platformHeight
	
	-- BRUTALIST: Massive concrete platform slab
	self:CreatePart(
		"Platform_" .. room.centerX .. "_" .. room.centerY,
		Vector3.new(platformWidth, h, platformDepth),
		Vector3.new(wx, h / 2, wz),
		CONFIG.Colors.Platform,
		Enum.Material.Concrete
	)
	
	-- Heavy platform edge (cantilevered look)
	self:CreatePart(
		"PlatformEdge_" .. room.centerX .. "_" .. room.centerY,
		Vector3.new(platformWidth + 1.5, 1, platformDepth + 1.5),
		Vector3.new(wx, h + 0.5, wz),
		CONFIG.Colors.PlatformEdge,
		Enum.Material.Concrete
	)
	
	-- Brutalist support columns under platform
	local supportPositions = {
		{wx - platformWidth/3, wz - platformDepth/3},
		{wx + platformWidth/3, wz - platformDepth/3},
		{wx - platformWidth/3, wz + platformDepth/3},
		{wx + platformWidth/3, wz + platformDepth/3},
	}
	
	for i, pos in ipairs(supportPositions) do
		self:CreatePart(
			"PlatformSupport_" .. i,
			Vector3.new(2, h - 0.5, 2),
			Vector3.new(pos[1], h / 2 - 0.25, pos[2]),
			CONFIG.Colors.PillarDark,
			Enum.Material.Concrete
		)
	end
	
	-- Angular brutalist stairs
	local stairWidth = CONFIG.TileSize * 2
	local stairDepth = h * 2
	local stairX = wx - platformWidth / 2 - stairDepth / 2
	
	self:CreateWedge(
		"Stairs_" .. room.centerX,
		Vector3.new(stairWidth, h, stairDepth),
		Vector3.new(stairX, h / 2, wz),
		CONFIG.Colors.Stairs,
		Vector3.new(0, 90, 0)
	)
	
	-- Stair side walls (brutalist containment)
	self:CreatePart(
		"StairWallL_" .. room.centerX,
		Vector3.new(stairDepth, h + 1, 0.8),
		Vector3.new(stairX, h / 2 + 0.5, wz - stairWidth / 2 - 0.4),
		CONFIG.Colors.WallDark,
		Enum.Material.Concrete
	)
	self:CreatePart(
		"StairWallR_" .. room.centerX,
		Vector3.new(stairDepth, h + 1, 0.8),
		Vector3.new(stairX, h / 2 + 0.5, wz + stairWidth / 2 + 0.4),
		CONFIG.Colors.WallDark,
		Enum.Material.Concrete
	)
	
	-- Heavy concrete barrier railing
	local railingHeight = 4
	local railingThickness = 1
	
	self:CreatePart(
		"Railing_F_" .. room.centerX,
		Vector3.new(platformWidth, railingHeight, railingThickness),
		Vector3.new(wx, h + railingHeight / 2, wz + platformDepth / 2),
		CONFIG.Colors.Railing,
		Enum.Material.Concrete
	)
	
	self:CreatePart(
		"Railing_B_" .. room.centerX,
		Vector3.new(platformWidth, railingHeight, railingThickness),
		Vector3.new(wx, h + railingHeight / 2, wz - platformDepth / 2),
		CONFIG.Colors.Railing,
		Enum.Material.Concrete
	)
end

function PlaygroundController:RenderRoomPillars(room)
	local pillarSize = 2.5  -- BRUTALIST: Square pillars, not round
	local pillarHeight = CONFIG.CeilingHeight
	
	-- Place massive square pillars
	local positions = {
		{room.x + 1, room.y + 1},
		{room.x + room.width - 2, room.y + 1},
		{room.x + 1, room.y + room.height - 2},
		{room.x + room.width - 2, room.y + room.height - 2},
	}
	
	for i, pos in ipairs(positions) do
		local wx, wz = self:TileToWorld(pos[1], pos[2])
		
		-- BRUTALIST: Massive square concrete pillar
		self:CreatePart(
			"Pillar_" .. i,
			Vector3.new(pillarSize, pillarHeight, pillarSize),
			Vector3.new(wx, pillarHeight / 2, wz),
			CONFIG.Colors.Pillar,
			Enum.Material.Concrete
		)
		
		-- Heavy pillar base (stepped)
		self:CreatePart(
			"PillarBase_" .. i,
			Vector3.new(pillarSize + 1.5, 1.5, pillarSize + 1.5),
			Vector3.new(wx, 0.75, wz),
			CONFIG.Colors.PillarDark,
			Enum.Material.Concrete
		)
		
		-- Pillar capital (heavy bracket at top)
		self:CreatePart(
			"PillarCap_" .. i,
			Vector3.new(pillarSize + 2, 2, pillarSize + 2),
			Vector3.new(wx, pillarHeight - 1, wz),
			CONFIG.Colors.PillarDark,
			Enum.Material.Concrete
		)
		
		-- Vertical recess detail on pillar
		self:CreatePart(
			"PillarDetail_" .. i,
			Vector3.new(0.5, pillarHeight * 0.7, pillarSize * 0.4),
			Vector3.new(wx + pillarSize * 0.35, pillarHeight * 0.45, wz),
			CONFIG.Colors.WallDark,
			Enum.Material.Concrete
		)
	end
end

function PlaygroundController:RenderCeilingBeams(room)
	local wx, wz = self:TileToWorld(room.centerX, room.centerY)
	local roomWidth = room.width * CONFIG.TileSize
	local roomDepth = room.height * CONFIG.TileSize
	local beamHeight = 2.5
	local beamWidth = 1.5
	
	-- BRUTALIST: Exposed concrete ceiling beams
	local numBeams = math.floor(room.width / 3)
	for i = 1, numBeams do
		local beamX = wx - roomWidth / 2 + (i / (numBeams + 1)) * roomWidth
		
		self:CreatePart(
			"CeilingBeam_" .. room.centerX .. "_" .. i,
			Vector3.new(beamWidth, beamHeight, roomDepth * 0.9),
			Vector3.new(beamX, CONFIG.CeilingHeight - beamHeight / 2, wz),
			CONFIG.Colors.Beam,
			Enum.Material.Concrete
		)
	end
	
	-- Cross beam
	self:CreatePart(
		"CrossBeam_" .. room.centerX,
		Vector3.new(roomWidth * 0.9, beamHeight, beamWidth),
		Vector3.new(wx, CONFIG.CeilingHeight - beamHeight / 2, wz),
		CONFIG.Colors.Beam,
		Enum.Material.Concrete
	)
end

function PlaygroundController:RenderRoomLight(room, shouldFlicker)
	local wx, wz = self:TileToWorld(room.centerX, room.centerY)
	
	-- BRUTALIST: Industrial cage light fixture
	local fixtureSize = 3
	
	-- Light housing (dark industrial)
	self:CreatePart(
		"LightHousing_" .. room.centerX,
		Vector3.new(fixtureSize, 1.5, fixtureSize),
		Vector3.new(wx, CONFIG.CeilingHeight - 2, wz),
		CONFIG.Colors.WallDark,
		Enum.Material.Metal
	)
	
	if shouldFlicker then
		-- Create flickering light instead
		self:CreateFlickeringLight(
			Vector3.new(wx, CONFIG.CeilingHeight - 3, wz),
			CONFIG.Colors.Light,
			0.8,
			math.max(room.width, room.height) * CONFIG.TileSize * 0.6
		)
	else
		-- Light bulb (harsh, stable)
		local bulb = self:CreatePart(
			"LightBulb_" .. room.centerX,
			Vector3.new(fixtureSize * 0.6, 0.8, fixtureSize * 0.6),
			Vector3.new(wx, CONFIG.CeilingHeight - 3, wz),
			CONFIG.Colors.Light,
			Enum.Material.Neon
		)
		
		-- Harsh industrial point light
		local light = Instance.new("PointLight")
		light.Color = CONFIG.Colors.Light
		light.Brightness = 0.8
		light.Range = math.max(room.width, room.height) * CONFIG.TileSize * 0.6
		light.Shadows = true
		light.Parent = bulb
	end
	
	-- Secondary dim accent lights in corners (some flicker too)
	if room.width >= 6 and room.height >= 6 then
		local cornerOffsetX = (room.width - 2) * CONFIG.TileSize / 2
		local cornerOffsetZ = (room.height - 2) * CONFIG.TileSize / 2
		
		local cornerFlicker = math.random() < 0.3
		
		if cornerFlicker then
			self:CreateFlickeringLight(
				Vector3.new(wx - cornerOffsetX, CONFIG.CeilingHeight - 1, wz - cornerOffsetZ),
				CONFIG.Colors.LightDim,
				0.3,
				CONFIG.TileSize * 3
			)
		else
			local cornerLight = self:CreatePart(
				"CornerLight_" .. room.centerX,
				Vector3.new(1, 0.5, 1),
				Vector3.new(wx - cornerOffsetX, CONFIG.CeilingHeight - 1, wz - cornerOffsetZ),
				CONFIG.Colors.LightDim,
				Enum.Material.Neon
			)
			
			local dimLight = Instance.new("PointLight")
			dimLight.Color = CONFIG.Colors.LightDim
			dimLight.Brightness = 0.3
			dimLight.Range = CONFIG.TileSize * 3
			dimLight.Parent = cornerLight
		end
	end
end

function PlaygroundController:RenderSpawnRoom(room)
	local wx, wz = self:TileToWorld(room.centerX, room.centerY)
	
	-- BRUTALIST: Recessed floor pit for spawn
	self:CreatePart(
		"SpawnPit",
		Vector3.new(CONFIG.TileSize * 2, 1, CONFIG.TileSize * 2),
		Vector3.new(wx, -0.5, wz),
		CONFIG.Colors.WallDark,
		Enum.Material.Concrete
	)
	
	-- Warning stripes around spawn
	local marker = self:CreatePart(
		"SpawnMarker",
		Vector3.new(CONFIG.TileSize * 2.5, 0.15, CONFIG.TileSize * 2.5),
		Vector3.new(wx, 0.08, wz),
		CONFIG.Colors.Spawn,
		Enum.Material.Neon
	)
	
	-- Ominous spawn light (red glow from below)
	local light = Instance.new("PointLight")
	light.Color = CONFIG.Colors.Spawn
	light.Brightness = 1.5
	light.Range = CONFIG.TileSize * 4
	light.Shadows = true
	light.Parent = marker
	
	-- Create SpawnLocation
	self._spawnLocation = Instance.new("SpawnLocation")
	self._spawnLocation.Name = "DungeonSpawn"
	self._spawnLocation.Size = Vector3.new(CONFIG.TileSize, 1, CONFIG.TileSize)
	self._spawnLocation.Position = Vector3.new(wx, 0.5, wz)
	self._spawnLocation.Anchored = true
	self._spawnLocation.CanCollide = false
	self._spawnLocation.Transparency = 1
	self._spawnLocation.Neutral = true
	self._spawnLocation.Parent = self._levelFolder
	
	self._spawnPos = Vector3.new(wx, 3, wz)
end

function PlaygroundController:RenderExitRoom(room)
	local wx, wz = self:TileToWorld(room.centerX, room.centerY)
	
	-- BRUTALIST: Raised exit platform
	self:CreatePart(
		"ExitPlatform",
		Vector3.new(CONFIG.TileSize * 2, 1.5, CONFIG.TileSize * 2),
		Vector3.new(wx, 0.75, wz),
		CONFIG.Colors.PillarDark,
		Enum.Material.Concrete
	)
	
	-- Exit marker (amber warning)
	local marker = self:CreatePart(
		"ExitMarker",
		Vector3.new(CONFIG.TileSize * 1.8, 0.2, CONFIG.TileSize * 1.8),
		Vector3.new(wx, 1.6, wz),
		CONFIG.Colors.Exit,
		Enum.Material.Neon
	)
	
	-- Exit light
	local light = Instance.new("PointLight")
	light.Color = CONFIG.Colors.Exit
	light.Brightness = 1.5
	light.Range = CONFIG.TileSize * 5
	light.Shadows = true
	light.Parent = marker
	
	-- BRUTALIST: Monolithic exit pillar
	local beacon = self:CreatePart(
		"ExitBeacon",
		Vector3.new(2, CONFIG.CeilingHeight - 4, 2),
		Vector3.new(wx, CONFIG.CeilingHeight / 2, wz),
		CONFIG.Colors.WallDark,
		Enum.Material.Concrete
	)
	
	-- Glowing strip on pillar
	self:CreatePart(
		"ExitStrip",
		Vector3.new(0.5, CONFIG.CeilingHeight - 6, 2.2),
		Vector3.new(wx + 1, CONFIG.CeilingHeight / 2, wz),
		CONFIG.Colors.Exit,
		Enum.Material.Neon
	)
	
	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = CONFIG.Colors.Exit
	beaconLight.Brightness = 2
	beaconLight.Range = CONFIG.TileSize * 6
	beaconLight.Shadows = true
	beaconLight.Parent = beacon
	
	self._exitPos = Vector3.new(wx, 4, wz)
end

-- === ATMOSPHERE: DEBRIS ===

function PlaygroundController:CreateDebris(position, debrisType)
	local debris
	local color = CONFIG.DebrisColors[math.random(1, #CONFIG.DebrisColors)]
	
	if debrisType == "crate" then
		local size = math.random(10, 20) / 10
		debris = self:CreatePart(
			"Crate",
			Vector3.new(size, size, size),
			position + Vector3.new(0, size/2, 0),
			color,
			Enum.Material.Wood
		)
	elseif debrisType == "barrel" then
		debris = Instance.new("Part")
		debris.Name = "Barrel"
		debris.Shape = Enum.PartType.Cylinder
		debris.Size = Vector3.new(2.5, 1.2, 1.2)
		debris.Position = position + Vector3.new(0, 0.6, 0)
		debris.Orientation = Vector3.new(0, 0, 90)
		debris.Color = color
		debris.Material = Enum.Material.Metal
		debris.Anchored = true
		debris.CanCollide = true
		debris.Parent = self._levelFolder
		table.insert(self._parts, debris)
	elseif debrisType == "barrel_fallen" then
		debris = Instance.new("Part")
		debris.Name = "BarrelFallen"
		debris.Shape = Enum.PartType.Cylinder
		debris.Size = Vector3.new(2.5, 1.2, 1.2)
		debris.Position = position + Vector3.new(0, 0.6, 0)
		debris.Orientation = Vector3.new(90, math.random(0, 360), 0)
		debris.Color = color
		debris.Material = Enum.Material.Metal
		debris.Anchored = true
		debris.CanCollide = true
		debris.Parent = self._levelFolder
		table.insert(self._parts, debris)
	elseif debrisType == "rubble" then
		-- Multiple small rocks
		for i = 1, math.random(3, 6) do
			local rockSize = math.random(3, 8) / 10
			local offsetX = math.random(-10, 10) / 10
			local offsetZ = math.random(-10, 10) / 10
			local rock = self:CreatePart(
				"Rubble",
				Vector3.new(rockSize, rockSize * 0.6, rockSize),
				position + Vector3.new(offsetX, rockSize * 0.3, offsetZ),
				CONFIG.Colors.WallDark,
				Enum.Material.Slate
			)
			rock.Orientation = Vector3.new(math.random(-20, 20), math.random(0, 360), math.random(-20, 20))
		end
	elseif debrisType == "plank" then
		local length = math.random(15, 30) / 10
		debris = self:CreatePart(
			"Plank",
			Vector3.new(length, 0.15, 0.4),
			position + Vector3.new(0, 0.08, 0),
			Color3.fromRGB(80, 60, 40),
			Enum.Material.Wood
		)
		debris.Orientation = Vector3.new(0, math.random(0, 360), math.random(-5, 5))
	elseif debrisType == "pipe" then
		debris = Instance.new("Part")
		debris.Name = "Pipe"
		debris.Shape = Enum.PartType.Cylinder
		local length = math.random(20, 40) / 10
		debris.Size = Vector3.new(length, 0.3, 0.3)
		debris.Position = position + Vector3.new(0, 0.15, 0)
		debris.Orientation = Vector3.new(0, math.random(0, 360), 90)
		debris.Color = Color3.fromRGB(60, 60, 65)
		debris.Material = Enum.Material.Metal
		debris.Anchored = true
		debris.CanCollide = true
		debris.Parent = self._levelFolder
		table.insert(self._parts, debris)
	end
	
	return debris
end

function PlaygroundController:RenderRoomDebris(room)
	local debrisTypes = {"crate", "barrel", "barrel_fallen", "rubble", "plank", "pipe"}
	local numDebris = math.random(1, CONFIG.DebrisPerRoom * 2)
	
	for i = 1, numDebris do
		-- Random position within room
		local rx = room.x + math.random(1, room.width - 2)
		local ry = room.y + math.random(1, room.height - 2)
		local wx, wz = self:TileToWorld(rx, ry)
		
		-- Add some randomness to exact position
		wx = wx + math.random(-20, 20) / 10
		wz = wz + math.random(-20, 20) / 10
		
		local debrisType = debrisTypes[math.random(1, #debrisTypes)]
		self:CreateDebris(Vector3.new(wx, 0, wz), debrisType)
	end
end

-- === ATMOSPHERE: FLICKERING LIGHTS ===

function PlaygroundController:CreateFlickeringLight(position, baseColor, baseBrightness, range)
	local lightPart = self:CreatePart(
		"FlickerLight",
		Vector3.new(1.5, 0.5, 1.5),
		position,
		baseColor,
		Enum.Material.Neon
	)
	
	local light = Instance.new("PointLight")
	light.Color = baseColor
	light.Brightness = baseBrightness
	light.Range = range
	light.Shadows = true
	light.Parent = lightPart
	
	-- Store for flickering animation
	table.insert(self._flickeringLights, {
		light = light,
		part = lightPart,
		baseBrightness = baseBrightness,
		baseColor = baseColor,
		flickerPattern = math.random(1, 4), -- Different flicker patterns
		offset = math.random() * 10, -- Random phase offset
	})
	
	return lightPart, light
end

function PlaygroundController:UpdateFlickeringLights(t)
	for _, flickerData in ipairs(self._flickeringLights) do
		local light = flickerData.light
		local part = flickerData.part
		if not light or not light.Parent then continue end
		
		local offset = flickerData.offset
		local pattern = flickerData.flickerPattern
		local baseBright = flickerData.baseBrightness
		
		local flicker = 1
		
		if pattern == 1 then
			-- Slow pulse with occasional dropout
			flicker = 0.7 + math.sin((t + offset) * 2) * 0.3
			if math.sin((t + offset) * 7) > 0.95 then
				flicker = 0.1
			end
		elseif pattern == 2 then
			-- Rapid flutter
			flicker = 0.5 + math.abs(math.sin((t + offset) * 15)) * 0.5
		elseif pattern == 3 then
			-- Dying bulb - mostly dim with occasional bright
			flicker = 0.3
			if math.sin((t + offset) * 3) > 0.8 then
				flicker = 0.9 + math.random() * 0.1
			end
		elseif pattern == 4 then
			-- Irregular strobing
			local noise = math.sin((t + offset) * 5) + math.sin((t + offset) * 13) * 0.5
			flicker = math.clamp(0.5 + noise * 0.4, 0.1, 1)
		end
		
		light.Brightness = baseBright * flicker
		
		-- Also flicker the part transparency slightly
		if part then
			part.Transparency = math.clamp(1 - flicker, 0, 0.5)
		end
	end
end

function PlaygroundController:StartFlickerLoop()
	if self._flickerConnection then
		self._flickerConnection:Disconnect()
	end
	
	self._flickerConnection = RunService.Heartbeat:Connect(function(dt)
		self:UpdateFlickeringLights(tick())
	end)
end

-- === ATMOSPHERE: PARTICLES ===

function PlaygroundController:CreateDustParticles(room)
	local wx, wz = self:TileToWorld(room.centerX, room.centerY)
	local roomWidth = room.width * CONFIG.TileSize
	local roomDepth = room.height * CONFIG.TileSize
	
	-- Create emitter part (invisible)
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "DustEmitter"
	emitterPart.Size = Vector3.new(roomWidth, 1, roomDepth)
	emitterPart.Position = Vector3.new(wx, CONFIG.CeilingHeight * 0.6, wz)
	emitterPart.Transparency = 1
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.Anchored = true
	emitterPart.Parent = self._levelFolder
	
	-- Dust motes particle emitter
	local dustEmitter = Instance.new("ParticleEmitter")
	dustEmitter.Name = "DustMotes"
	dustEmitter.Color = ColorSequence.new(Color3.fromRGB(200, 190, 170))
	dustEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	dustEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.7),
		NumberSequenceKeypoint.new(0.8, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	dustEmitter.Lifetime = NumberRange.new(8, 15)
	dustEmitter.Rate = math.floor(roomWidth * roomDepth / 50)
	dustEmitter.Speed = NumberRange.new(0.1, 0.5)
	dustEmitter.SpreadAngle = Vector2.new(180, 180)
	dustEmitter.Rotation = NumberRange.new(0, 360)
	dustEmitter.RotSpeed = NumberRange.new(-20, 20)
	dustEmitter.LightEmission = 0.1
	dustEmitter.LightInfluence = 1
	dustEmitter.Parent = emitterPart
	
	table.insert(self._dustEmitters, emitterPart)
end

function PlaygroundController:CreateGroundFog(room)
	local wx, wz = self:TileToWorld(room.centerX, room.centerY)
	local roomWidth = room.width * CONFIG.TileSize
	local roomDepth = room.height * CONFIG.TileSize
	
	-- Create fog emitter part
	local fogPart = Instance.new("Part")
	fogPart.Name = "FogEmitter"
	fogPart.Size = Vector3.new(roomWidth * 0.8, 1, roomDepth * 0.8)
	fogPart.Position = Vector3.new(wx, 0.5, wz)
	fogPart.Transparency = 1
	fogPart.CanCollide = false
	fogPart.CanQuery = false
	fogPart.Anchored = true
	fogPart.Parent = self._levelFolder
	
	-- Ground fog particle emitter
	local fogEmitter = Instance.new("ParticleEmitter")
	fogEmitter.Name = "GroundFog"
	fogEmitter.Color = ColorSequence.new(Color3.fromRGB(80, 75, 70))
	fogEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(0.5, 6),
		NumberSequenceKeypoint.new(1, 3),
	})
	fogEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.85),
		NumberSequenceKeypoint.new(0.7, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	fogEmitter.Lifetime = NumberRange.new(6, 10)
	fogEmitter.Rate = math.floor(roomWidth * roomDepth / 100)
	fogEmitter.Speed = NumberRange.new(0.2, 0.8)
	fogEmitter.SpreadAngle = Vector2.new(180, 0)
	fogEmitter.Rotation = NumberRange.new(0, 360)
	fogEmitter.RotSpeed = NumberRange.new(-10, 10)
	fogEmitter.LightEmission = 0
	fogEmitter.LightInfluence = 0.5
	fogEmitter.Parent = fogPart
	
	table.insert(self._dustEmitters, fogPart)
end

function PlaygroundController:RenderLevel()
	print("[Playground] Rendering level to 3D...")
	
	local spawnRoom = self._rooms[1]
	local exitRoom = self._rooms[#self._rooms]
	
	-- Render base tiles (floor, walls, ceiling)
	for y = 1, CONFIG.GridHeight do
		for x = 1, CONFIG.GridWidth do
			local tile = self:GetTile(x, y)
			
			if tile == TILE.FLOOR or tile == TILE.CORRIDOR then
				self:RenderFloor(x, y, tile == TILE.CORRIDOR)
				self:RenderCeiling(x, y)
			elseif tile == TILE.WALL then
				self:RenderWall(x, y)
			end
		end
	end
	
	-- Render room features
	for i, room in ipairs(self._rooms) do
		if room == spawnRoom then
			self:RenderSpawnRoom(room)
		elseif room == exitRoom then
			self:RenderExitRoom(room)
		end
		
		-- Add verticality features
		if room.hasPlatform then
			self:RenderRoomPlatform(room)
		end
		
		if room.hasPillars then
			self:RenderRoomPillars(room)
		end
		
		-- BRUTALIST: Exposed ceiling beams
		if room.hasBeams then
			self:RenderCeilingBeams(room)
		end
		
		-- Add industrial lighting (some flickering)
		local shouldFlicker = math.random() < CONFIG.FlickeringLightChance
		self:RenderRoomLight(room, shouldFlicker)
		
		-- Add debris (skip spawn room)
		if room ~= spawnRoom then
			self:RenderRoomDebris(room)
		end
		
		-- Add atmospheric particles
		if CONFIG.DustParticlesEnabled then
			self:CreateDustParticles(room)
		end
		
		-- Add ground fog (50% of rooms)
		if CONFIG.FogEnabled and math.random() < 0.5 then
			self:CreateGroundFog(room)
		end
	end
	
	-- Start flickering light animation loop
	self:StartFlickerLoop()
	
	print("[Playground] Rendered", #self._parts, "parts")
	print("[Playground] Flickering lights:", #self._flickeringLights)
end

-- === PUBLIC API ===

function PlaygroundController:BuildLevel()
	self:ClearLevel()
	
	-- Remove baseplate (check multiple common names)
	local baseplateNames = {"Baseplate", "BasePlate", "baseplate", "Base Plate", "SpawnLocation"}
	for _, name in ipairs(baseplateNames) do
		local baseplate = Workspace:FindFirstChild(name)
		if baseplate then
			baseplate:Destroy()
			print("[Playground] Removed:", name)
		end
	end
	
	-- Also remove any large flat part at Y=0 that might be a baseplate
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") and child.Name:lower():find("base") then
			child:Destroy()
			print("[Playground] Removed base part:", child.Name)
		end
	end
	
	self._levelFolder = Instance.new("Folder")
	self._levelFolder.Name = "ProceduralDungeon"
	self._levelFolder.Parent = Workspace
	
	print("[Playground] Generating dungeon...")
	self:InitGrid()
	self:GenerateRooms()
	self:GenerateCorridors()
	self:GenerateWalls()
	self:RenderLevel()
	
	return self._spawnPos or Vector3.new(0, 3, 0)
end

function PlaygroundController:ClearLevel()
	-- Stop flickering light loop
	if self._flickerConnection then
		self._flickerConnection:Disconnect()
		self._flickerConnection = nil
	end
	
	-- Clear flickering lights
	self._flickeringLights = {}
	
	-- Clear dust emitters
	for _, emitter in ipairs(self._dustEmitters) do
		if emitter and emitter.Parent then
			emitter:Destroy()
		end
	end
	self._dustEmitters = {}
	
	-- Clear parts
	for _, part in ipairs(self._parts) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	self._parts = {}
	self._rooms = {}
	self._grid = {}
	
	if self._spawnLocation then
		self._spawnLocation:Destroy()
		self._spawnLocation = nil
	end
	
	if self._levelFolder then
		self._levelFolder:Destroy()
		self._levelFolder = nil
	end
	
	self._spawnPos = nil
	self._exitPos = nil
end

function PlaygroundController:GetSpawnPosition()
	return self._spawnPos or Vector3.new(0, 3, 0)
end

function PlaygroundController:GetExitPosition()
	return self._exitPos or Vector3.new(0, 3, 0)
end

function PlaygroundController:GetRooms()
	return self._rooms
end

function PlaygroundController:GetParts()
	return self._parts
end

function PlaygroundController:TeleportToSpawn()
	local player = Players.LocalPlayer
	if player and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and self._spawnPos then
			hrp.CFrame = CFrame.new(self._spawnPos)
		end
	end
end

-- === KNIT LIFECYCLE ===

function PlaygroundController:KnitInit()
end

function PlaygroundController:KnitStart()
	local spawnPos = self:BuildLevel()
	print("[Playground] Spawn position:", spawnPos)
	
	-- Teleport player to spawn after short delay
	task.delay(1, function()
		self:TeleportToSpawn()
	end)
end

return PlaygroundController
