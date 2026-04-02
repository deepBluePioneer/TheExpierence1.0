local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
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

local PACMAN_MOVE_SPEED = 48
local PACMAN_HEIGHT = 8
local PACMAN_COUNT = 3

local LIGHT_SPACING = 2
local LIGHT_COLOR = Color3.fromRGB(200, 160, 100)
local LIGHT_BRIGHTNESS = 3
local LIGHT_RANGE = 60

local PELLET_TAG = "PacManPellet"
local PELLET_SIZE = 2.5
local PELLET_HEIGHT = 3
local PELLET_COLOR = Color3.fromRGB(255, 255, 100)
local PELLET_COLLECT_RANGE = 6

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
	_pacmans = {},
	_grid = nil,
	_gridRows = 0,
	_gridCols = 0,
	_totalPellets = 0,
	_collectedPellets = 0,
	_collectConn = nil,

	MazeGenerated = Signal.new(),
	PelletCollected = Signal.new(),
	AllPelletsCollected = Signal.new(),
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

	local pelletFolder = Instance.new("Folder")
	pelletFolder.Name = "Pellets"
	pelletFolder.Parent = folder

	self._totalPellets = 0
	self._collectedPellets = 0

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

				local pellet = Instance.new("Part")
				pellet.Name = "Pellet_" .. r .. "_" .. c
				pellet.Shape = Enum.PartType.Ball
				pellet.Size = Vector3.new(PELLET_SIZE, PELLET_SIZE, PELLET_SIZE)
				pellet.CFrame = CFrame.new(worldX, ORIGIN.Y + PELLET_HEIGHT, worldZ)
				pellet.Anchored = true
				pellet.CanCollide = false
				pellet.Material = Enum.Material.Neon
				pellet.Color = PELLET_COLOR
				pellet.CastShadow = false
				pellet.Parent = pelletFolder
				CollectionService:AddTag(pellet, PELLET_TAG)
				self._totalPellets += 1
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

function PacManMazeService:_findStartCells(count)
	if not self._grid then return {} end

	local candidates = {}
	for r = 2, self._gridRows - 1 do
		for c = 2, self._gridCols - 1 do
			if self._grid[r][c] == PATH then
				table.insert(candidates, { r = r, c = c })
			end
		end
	end

	self:_shuffle(candidates)

	local spacing = math.max(math.floor(#candidates / (count + 1)), 1)
	local results = {}
	for i = 1, count do
		local idx = math.min(i * spacing, #candidates)
		table.insert(results, candidates[idx])
	end

	return results
end

function PacManMazeService:_setCFrameOn(clone, cf)
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

function PacManMazeService:_spawnPacMans()
	self:_destroyPacMans()

	local starts = self:_findStartCells(PACMAN_COUNT)

	for i, cell in ipairs(starts) do
		local clone = PACMAN_PREFAB:Clone()
		clone.Name = "PacMan_" .. i

		local pos = self:GetCellWorldPosition(cell.r, cell.c) + Vector3.new(0, PACMAN_HEIGHT, 0)

		if clone:IsA("Model") then
			clone:PivotTo(CFrame.new(pos))
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

		local pac = {
			model = clone,
			row = cell.r,
			col = cell.c,
			dirR = 0,
			dirC = 1,
			moving = false,
		}
		table.insert(self._pacmans, pac)

		print("[PacManMazeService] Spawned PacMan_" .. i .. " at cell (" .. cell.r .. ", " .. cell.c .. ")")
	end
end

function PacManMazeService:_destroyPacMans()
	self:_stopAllMovement()

	for _, pac in ipairs(self._pacmans) do
		if pac.model then
			pac.model:Destroy()
		end
	end
	self._pacmans = {}

	for _, child in ipairs(Workspace:GetChildren()) do
		if child.Name:match("^PacMan") and child.Name ~= "PacManMaze" then
			child:Destroy()
		end
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

function PacManMazeService:_startAllMovement()
	self:_stopAllMovement()

	for _, pac in ipairs(self._pacmans) do
		pac.moving = true
		task.spawn(function()
			while pac.moving and pac.model do
				self:_pacStep(pac)
			end
		end)
	end
end

function PacManMazeService:_stopAllMovement()
	for _, pac in ipairs(self._pacmans) do
		pac.moving = false
	end
end

function PacManMazeService:_pacStep(pac)
	if not pac.model or not self._grid then
		pac.moving = false
		return
	end

	local r = pac.row
	local c = pac.col

	local forwardDir = { dr = pac.dirR, dc = pac.dirC }
	local reverseR = -pac.dirR
	local reverseC = -pac.dirC

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

	pac.dirR = nextDir.dr
	pac.dirC = nextDir.dc

	local fromPos = self:GetCellWorldPosition(r, c) + Vector3.new(0, PACMAN_HEIGHT, 0)
	local toPos = self:GetCellWorldPosition(newR, newC) + Vector3.new(0, PACMAN_HEIGHT, 0)

	local yAngle = dirToYAngle(nextDir.dr, nextDir.dc)

	local distance = (toPos - fromPos).Magnitude
	local duration = distance / PACMAN_MOVE_SPEED

	local steps = math.max(math.floor(duration / 0.03), 1)
	local stepDt = duration / steps

	for i = 1, steps do
		if not pac.moving then return end

		local alpha = i / steps
		local pos = fromPos:Lerp(toPos, alpha)
		local cf = CFrame.new(pos) * CFrame.Angles(0, yAngle, 0)
		self:_setCFrameOn(pac.model, cf)

		task.wait(stepDt)
	end

	pac.row = newR
	pac.col = newC
end

function PacManMazeService:_repositionSpawnLocation()
	local spawnLoc = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if not spawnLoc then return end

	local pos = self:GetSpawnPosition()
	spawnLoc.CFrame = CFrame.new(pos.X, ORIGIN.Y + spawnLoc.Size.Y / 2, pos.Z)
	spawnLoc.Anchored = true
	print("[PacManMazeService] Moved SpawnLocation to " .. tostring(spawnLoc.Position))
end

function PacManMazeService:_startPelletCollection()
	self:_stopPelletCollection()

	self._collectConn = RunService.Heartbeat:Connect(function()
		local pellets = CollectionService:GetTagged(PELLET_TAG)
		if #pellets == 0 then return end

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if not character then continue end
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if not hrp then continue end

			local playerPos = hrp.Position

			for _, pellet in ipairs(pellets) do
				if not pellet.Parent then continue end
				local dist = (pellet.Position - playerPos).Magnitude
				if dist <= PELLET_COLLECT_RANGE then
					CollectionService:RemoveTag(pellet, PELLET_TAG)
					pellet:Destroy()
					self._collectedPellets += 1
					self.PelletCollected:Fire(player, self._collectedPellets, self._totalPellets)

					if self._collectedPellets >= self._totalPellets then
						self.AllPelletsCollected:Fire()
						print("[PacManMazeService] All pellets collected!")
					end
				end
			end
		end
	end)
end

function PacManMazeService:_stopPelletCollection()
	if self._collectConn then
		self._collectConn:Disconnect()
		self._collectConn = nil
	end
end

function PacManMazeService:GenerateMaze()
	local grid, rows, cols = self:_generateGrid()
	self:_buildMaze(grid, rows, cols)
	self:_repositionSpawnLocation()
	self:_spawnPacMans()
	self:_startAllMovement()
	self:_startPelletCollection()
	self.MazeGenerated:Fire()
	print("[PacManMazeService] Spawned " .. self._totalPellets .. " pellets")
end

function PacManMazeService:DestroyMaze()
	self:_stopPelletCollection()
	self:_destroyPacMans()
	self:_clearMaze()
	self._grid = nil
	self._gridRows = 0
	self._gridCols = 0
	self._totalPellets = 0
	self._collectedPellets = 0
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

function PacManMazeService:GetPelletCount()
	return self._collectedPellets, self._totalPellets
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

function PacManMazeService.Client:GetPelletCount(_player)
	return self.Server:GetPelletCount()
end

return PacManMazeService
