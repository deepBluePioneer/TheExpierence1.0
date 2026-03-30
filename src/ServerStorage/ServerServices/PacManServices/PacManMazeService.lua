local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)

local CELL_SIZE = 32
local WALL_HEIGHT = 20
local WALL_THICKNESS = 1
local FLOOR_THICKNESS = 1

local MAZE_ROWS = 15
local MAZE_COLS = 21

local ORIGIN = Vector3.new(0, 0, 0)

local WALL = 1
local PATH = 0

local FLOOR_COLOR = Color3.fromRGB(50, 48, 42)
local WALL_COLOR = Color3.fromRGB(70, 65, 55)
local WALL_TOP_COLOR = Color3.fromRGB(85, 80, 68)

local DIRECTIONS = {
	{ dr = -2, dc = 0 },
	{ dr = 2, dc = 0 },
	{ dr = 0, dc = -2 },
	{ dr = 0, dc = 2 },
}

local MOVE_DIRS = {
	{ dr = -1, dc = 0 },
	{ dr = 1, dc = 0 },
	{ dr = 0, dc = -1 },
	{ dr = 0, dc = 1 },
}

local PACMAN_MOVE_SPEED = 24
local PACMAN_HEIGHT = 8

local LIGHT_SPACING = 2
local LIGHT_COLOR = Color3.fromRGB(200, 160, 100)
local LIGHT_BRIGHTNESS = 3
local LIGHT_RANGE = 60

local function dirToYAngle(dr, dc)
	local worldX = dc
	local worldZ = dr
	return math.atan2(-worldX, -worldZ)
end

local PACMAN_PREFAB = ReplicatedStorage:WaitForChild("Prefabs"):WaitForChild("pacman")

local PacManMazeService = Knit.CreateService({
	Name = "PacManMazeService",
	Client = {},

	_trove = nil,
	_mazeFolder = nil,
	_pacmanModel = nil,
	_grid = nil,
	_gridRows = 0,
	_gridCols = 0,
	_pacRow = 0,
	_pacCol = 0,
	_pacMoving = false,
	_pacDirR = 0,
	_pacDirC = 1,

	MazeGenerated = Signal.new(),
})

function PacManMazeService:KnitInit()
	self._trove = Trove.new()
end

function PacManMazeService:KnitStart()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	self:_setupDarkLighting()
	self:GenerateMaze()
	print("[PacManMazeService] Started")
end

function PacManMazeService:_setupDarkLighting()
	Lighting.Brightness = 0
	Lighting.ClockTime = 0
	Lighting.Ambient = Color3.fromRGB(15, 15, 20)
	Lighting.OutdoorAmbient = Color3.fromRGB(10, 10, 15)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0

	Lighting.FogColor = Color3.fromRGB(8, 8, 12)
	Lighting.FogStart = 80
	Lighting.FogEnd = 400

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("BloomEffect")
			or child:IsA("ColorCorrectionEffect") or child:IsA("SunRaysEffect") then
			child:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(10, 10, 15)
	atmosphere.Decay = Color3.fromRGB(5, 5, 8)
	atmosphere.Glare = 0
	atmosphere.Haze = 3
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "MazeBloom"
	bloom.Intensity = 0.4
	bloom.Size = 24
	bloom.Threshold = 0.8
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MazeCC"
	cc.Brightness = 0
	cc.Contrast = 0.1
	cc.Saturation = -0.2
	cc.TintColor = Color3.fromRGB(255, 240, 220)
	cc.Parent = Lighting

	print("[PacManMazeService] Dark lighting with fog applied")
end

function PacManMazeService:_initGrid(rows, cols)
	local grid = {}
	for r = 1, rows do
		grid[r] = {}
		for c = 1, cols do
			grid[r][c] = WALL
		end
	end
	return grid
end

function PacManMazeService:_shuffle(tbl)
	for i = #tbl, 2, -1 do
		local j = math.random(1, i)
		tbl[i], tbl[j] = tbl[j], tbl[i]
	end
end

function PacManMazeService:_carve(grid, rows, cols, r, c)
	grid[r][c] = PATH

	local dirs = {}
	for i, d in ipairs(DIRECTIONS) do
		dirs[i] = d
	end
	self:_shuffle(dirs)

	for _, d in ipairs(dirs) do
		local nr = r + d.dr
		local nc = c + d.dc
		if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols and grid[nr][nc] == WALL then
			local mr = r + d.dr / 2
			local mc = c + d.dc / 2
			grid[mr][mc] = PATH
			self:_carve(grid, rows, cols, nr, nc)
		end
	end
end

function PacManMazeService:_openDeadEnds(grid, rows, cols)
	for r = 2, rows - 1 do
		for c = 2, cols - 1 do
			if grid[r][c] == PATH then
				local wallCount = 0
				if grid[r - 1][c] == WALL then wallCount += 1 end
				if grid[r + 1][c] == WALL then wallCount += 1 end
				if grid[r][c - 1] == WALL then wallCount += 1 end
				if grid[r][c + 1] == WALL then wallCount += 1 end

				if wallCount == 3 and math.random() < 0.35 then
					local candidates = {}
					if r - 1 > 1 and grid[r - 1][c] == WALL then table.insert(candidates, { r - 1, c }) end
					if r + 1 < rows and grid[r + 1][c] == WALL then table.insert(candidates, { r + 1, c }) end
					if c - 1 > 1 and grid[r][c - 1] == WALL then table.insert(candidates, { r, c - 1 }) end
					if c + 1 < cols and grid[r][c + 1] == WALL then table.insert(candidates, { r, c + 1 }) end

					if #candidates > 0 then
						local pick = candidates[math.random(1, #candidates)]
						grid[pick[1]][pick[2]] = PATH
					end
				end
			end
		end
	end
end

function PacManMazeService:_generateGrid()
	local gridRows = MAZE_ROWS * 2 + 1
	local gridCols = MAZE_COLS * 2 + 1

	local grid = self:_initGrid(gridRows, gridCols)

	local startR = 2
	local startC = 2
	self:_carve(grid, gridRows, gridCols, startR, startC)

	self:_openDeadEnds(grid, gridRows, gridCols)

	self._grid = grid
	self._gridRows = gridRows
	self._gridCols = gridCols

	return grid, gridRows, gridCols
end

function PacManMazeService:_clearMaze()
	if self._mazeFolder then
		self._mazeFolder:Destroy()
		self._mazeFolder = nil
	end
end

function PacManMazeService:_buildMaze(grid, gridRows, gridCols)
	self:_clearMaze()

	local folder = Instance.new("Folder")
	folder.Name = "PacManMaze"
	self._mazeFolder = folder

	local floorFolder = Instance.new("Folder")
	floorFolder.Name = "Floors"
	floorFolder.Parent = folder

	local wallFolder = Instance.new("Folder")
	wallFolder.Name = "Walls"
	wallFolder.Parent = folder

	local lightFolder = Instance.new("Folder")
	lightFolder.Name = "Lights"
	lightFolder.Parent = folder

	local totalWidth = gridCols * CELL_SIZE
	local totalDepth = gridRows * CELL_SIZE
	local baseOrigin = ORIGIN - Vector3.new(totalWidth / 2, 0, totalDepth / 2)

	local floorY = ORIGIN.Y - FLOOR_THICKNESS / 2
	local wallY = ORIGIN.Y + WALL_HEIGHT / 2

	for r = 1, gridRows do
		for c = 1, gridCols do
			local worldX = baseOrigin.X + (c - 0.5) * CELL_SIZE
			local worldZ = baseOrigin.Z + (r - 0.5) * CELL_SIZE

			if grid[r][c] == PATH then
				local floor = Instance.new("Part")
				floor.Name = "Floor_" .. r .. "_" .. c
				floor.Size = Vector3.new(CELL_SIZE, FLOOR_THICKNESS, CELL_SIZE)
				floor.CFrame = CFrame.new(worldX, floorY, worldZ)
				floor.Anchored = true
				floor.Material = Enum.Material.CorrodedMetal
				floor.Color = FLOOR_COLOR
				floor.TopSurface = Enum.SurfaceType.Smooth
				floor.BottomSurface = Enum.SurfaceType.Smooth
				floor.Parent = floorFolder

				if r % LIGHT_SPACING == 0 and c % LIGHT_SPACING == 0 then
					local bulb = Instance.new("Part")
					bulb.Name = "Light_" .. r .. "_" .. c
					bulb.Shape = Enum.PartType.Ball
					bulb.Size = Vector3.new(1.5, 1.5, 1.5)
					bulb.CFrame = CFrame.new(worldX, ORIGIN.Y + WALL_HEIGHT - 2, worldZ)
					bulb.Anchored = true
					bulb.CanCollide = false
					bulb.Material = Enum.Material.Neon
					bulb.Color = LIGHT_COLOR
					bulb.CastShadow = false
					bulb.Parent = lightFolder

					local pointLight = Instance.new("PointLight")
					pointLight.Color = LIGHT_COLOR
					pointLight.Brightness = LIGHT_BRIGHTNESS
					pointLight.Range = LIGHT_RANGE
					pointLight.Shadows = true
					pointLight.Parent = bulb
				end
			else
				local floor = Instance.new("Part")
				floor.Name = "WallBase_" .. r .. "_" .. c
				floor.Size = Vector3.new(CELL_SIZE, FLOOR_THICKNESS, CELL_SIZE)
				floor.CFrame = CFrame.new(worldX, floorY, worldZ)
				floor.Anchored = true
				floor.Material = Enum.Material.CorrodedMetal
				floor.Color = FLOOR_COLOR
				floor.TopSurface = Enum.SurfaceType.Smooth
				floor.BottomSurface = Enum.SurfaceType.Smooth
				floor.Parent = floorFolder

				local wall = Instance.new("Part")
				wall.Name = "Wall_" .. r .. "_" .. c
				wall.Size = Vector3.new(CELL_SIZE, WALL_HEIGHT, CELL_SIZE)
				wall.CFrame = CFrame.new(worldX, wallY, worldZ)
				wall.Anchored = true
				wall.Material = Enum.Material.Metal
				wall.Color = WALL_COLOR
				wall.TopSurface = Enum.SurfaceType.Smooth
				wall.BottomSurface = Enum.SurfaceType.Smooth
				wall.CastShadow = false
				wall.Parent = wallFolder

				local topCap = Instance.new("Part")
				topCap.Name = "WallTop_" .. r .. "_" .. c
				topCap.Size = Vector3.new(CELL_SIZE, WALL_THICKNESS, CELL_SIZE)
				topCap.CFrame = CFrame.new(worldX, ORIGIN.Y + WALL_HEIGHT + WALL_THICKNESS / 2, worldZ)
				topCap.Anchored = true
				topCap.Material = Enum.Material.Metal
				topCap.Color = WALL_TOP_COLOR
				topCap.TopSurface = Enum.SurfaceType.Smooth
				topCap.BottomSurface = Enum.SurfaceType.Smooth
				topCap.CastShadow = false
				topCap.Parent = wallFolder
			end
		end
	end

	folder.Parent = Workspace
	print("[PacManMazeService] Built maze: " .. gridRows .. "x" .. gridCols .. " (" .. (gridRows * gridCols) .. " cells)")
end

function PacManMazeService:_findPacManStartCell()
	if not self._grid then return 2, 2 end

	local centerR = math.floor(self._gridRows / 2)
	local centerC = math.floor(self._gridCols / 2)
	local bestR, bestC, bestDist = 2, 2, math.huge

	for r = 2, self._gridRows - 1 do
		for c = 2, self._gridCols - 1 do
			if self._grid[r][c] == PATH then
				local dist = math.abs(r - centerR) + math.abs(c - centerC)
				if dist < bestDist then
					bestR, bestC, bestDist = r, c, dist
				end
			end
		end
	end

	return bestR, bestC
end

function PacManMazeService:_setPacManCFrame(cf)
	local clone = self._pacmanModel
	if not clone then return end

	if clone:IsA("Model") then
		clone:PivotTo(cf)
	else
		local anchor = clone:FindFirstChildWhichIsA("BasePart", true)
		if not anchor then return end
		local oldAnchorCF = anchor.CFrame
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				local rel = oldAnchorCF:ToObjectSpace(desc.CFrame)
				desc.CFrame = cf * rel
			end
		end
	end
end

function PacManMazeService:_spawnPacMan()
	self:_destroyPacMan()

	local clone = PACMAN_PREFAB:Clone()
	clone.Name = "PacMan"

	local startR, startC = self:_findPacManStartCell()
	self._pacRow = startR
	self._pacCol = startC

	local pos = self:GetCellWorldPosition(startR, startC) + Vector3.new(0, PACMAN_HEIGHT, 0)
	local cf = CFrame.new(pos)

	if clone:IsA("Model") then
		clone:PivotTo(cf)
	else
		local anchor = clone:FindFirstChildWhichIsA("BasePart", true)
		if anchor then
			local offset = anchor.Position
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.CFrame = desc.CFrame - offset + pos
				end
			end
		end
	end

	clone.Parent = Workspace
	self._pacmanModel = clone
	self._pacMoving = false

	print("[PacManMazeService] Spawned PacMan at cell (" .. startR .. ", " .. startC .. ")")
end

function PacManMazeService:_destroyPacMan()
	self:_stopPacManMovement()

	if self._pacmanModel then
		self._pacmanModel:Destroy()
		self._pacmanModel = nil
	end
	local existing = Workspace:FindFirstChild("PacMan")
	if existing then
		existing:Destroy()
	end
end

function PacManMazeService:_isWalkable(r, c)
	if r < 1 or r > self._gridRows or c < 1 or c > self._gridCols then
		return false
	end
	return self._grid[r][c] == PATH
end

function PacManMazeService:_getValidMoveDirections(r, c, excludeDr, excludeDc)
	local valid = {}
	for _, d in ipairs(MOVE_DIRS) do
		if not (d.dr == excludeDr and d.dc == excludeDc) then
			if self:_isWalkable(r + d.dr, c + d.dc) then
				table.insert(valid, d)
			end
		end
	end
	return valid
end

function PacManMazeService:_startPacManMovement()
	self:_stopPacManMovement()
	self._pacMoving = true

	task.spawn(function()
		while self._pacMoving and self._pacmanModel do
			self:_pacManStep()
		end
	end)
end

function PacManMazeService:_stopPacManMovement()
	self._pacMoving = false
end

function PacManMazeService:_pacManStep()
	if not self._pacmanModel or not self._grid then
		self._pacMoving = false
		return
	end

	local r = self._pacRow
	local c = self._pacCol

	local forwardDir = { dr = self._pacDirR, dc = self._pacDirC }
	local reverseR = -self._pacDirR
	local reverseC = -self._pacDirC

	local nextDir = nil

	if self:_isWalkable(r + forwardDir.dr, c + forwardDir.dc) then
		local others = self:_getValidMoveDirections(r, c, reverseR, reverseC)
		if #others > 1 and math.random() < 0.4 then
			nextDir = others[math.random(1, #others)]
		else
			nextDir = forwardDir
		end
	else
		local options = self:_getValidMoveDirections(r, c, reverseR, reverseC)
		if #options > 0 then
			nextDir = options[math.random(1, #options)]
		else
			nextDir = { dr = reverseR, dc = reverseC }
			if not self:_isWalkable(r + nextDir.dr, c + nextDir.dc) then
				task.wait(0.5)
				return
			end
		end
	end

	local newR = r + nextDir.dr
	local newC = c + nextDir.dc

	self._pacDirR = nextDir.dr
	self._pacDirC = nextDir.dc

	local fromPos = self:GetCellWorldPosition(r, c) + Vector3.new(0, PACMAN_HEIGHT, 0)
	local toPos = self:GetCellWorldPosition(newR, newC) + Vector3.new(0, PACMAN_HEIGHT, 0)

	local yAngle = dirToYAngle(nextDir.dr, nextDir.dc)

	local distance = (toPos - fromPos).Magnitude
	local duration = distance / PACMAN_MOVE_SPEED

	local steps = math.max(math.floor(duration / 0.03), 1)
	local stepDt = duration / steps

	for i = 1, steps do
		if not self._pacMoving then return end

		local alpha = i / steps
		local pos = fromPos:Lerp(toPos, alpha)
		local cf = CFrame.new(pos) * CFrame.Angles(0, yAngle, 0)
		self:_setPacManCFrame(cf)

		task.wait(stepDt)
	end

	self._pacRow = newR
	self._pacCol = newC
end

function PacManMazeService:_repositionSpawnLocation()
	local spawnLoc = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if not spawnLoc then return end

	local pos = self:GetSpawnPosition()
	spawnLoc.CFrame = CFrame.new(pos.X, ORIGIN.Y + spawnLoc.Size.Y / 2, pos.Z)
	spawnLoc.Anchored = true
	print("[PacManMazeService] Moved SpawnLocation to " .. tostring(spawnLoc.Position))
end

function PacManMazeService:GenerateMaze()
	local grid, rows, cols = self:_generateGrid()
	self:_buildMaze(grid, rows, cols)
	self:_repositionSpawnLocation()
	self:_spawnPacMan()
	self:_startPacManMovement()
	self.MazeGenerated:Fire()
end

function PacManMazeService:DestroyMaze()
	self:_destroyPacMan()
	self:_clearMaze()
	self._grid = nil
	self._gridRows = 0
	self._gridCols = 0
end

function PacManMazeService:GetGrid()
	return self._grid, self._gridRows, self._gridCols
end

function PacManMazeService:GetCellWorldPosition(row, col)
	local totalWidth = self._gridCols * CELL_SIZE
	local totalDepth = self._gridRows * CELL_SIZE
	local baseOrigin = ORIGIN - Vector3.new(totalWidth / 2, 0, totalDepth / 2)
	local worldX = baseOrigin.X + (col - 0.5) * CELL_SIZE
	local worldZ = baseOrigin.Z + (row - 0.5) * CELL_SIZE
	return Vector3.new(worldX, ORIGIN.Y + 1, worldZ)
end

function PacManMazeService:GetSpawnPosition()
	if not self._grid then return ORIGIN + Vector3.new(0, 5, 0) end

	local centerR = math.floor(self._gridRows / 2)
	local centerC = math.floor(self._gridCols / 2)

	local candidates = {}
	for r = 2, self._gridRows - 1 do
		for c = 2, self._gridCols - 1 do
			if self._grid[r][c] == PATH then
				local dist = math.abs(r - centerR) + math.abs(c - centerC)
				table.insert(candidates, { r = r, c = c, dist = dist })
			end
		end
	end

	table.sort(candidates, function(a, b) return a.dist < b.dist end)

	local poolSize = math.min(8, #candidates)
	if poolSize > 0 then
		local pick = candidates[math.random(1, poolSize)]
		return self:GetCellWorldPosition(pick.r, pick.c)
	end

	return ORIGIN + Vector3.new(0, 5, 0)
end

function PacManMazeService.Client:GenerateMaze(_player)
	self.Server:GenerateMaze()
end

function PacManMazeService.Client:DestroyMaze(_player)
	self.Server:DestroyMaze()
end

function PacManMazeService.Client:GetSpawnPosition(_player)
	return self.Server:GetSpawnPosition()
end

return PacManMazeService
