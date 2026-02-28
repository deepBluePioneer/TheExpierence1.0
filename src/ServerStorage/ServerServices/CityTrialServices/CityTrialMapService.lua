local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local MAP_FOLDER_NAME = "CityTrialMap"

local BASEPLATE_SIZE = Vector3.new(512, 4, 512)
local BASEPLATE_COLOR = Color3.fromRGB(85, 170, 85)
local BASEPLATE_MATERIAL = Enum.Material.Ground

local RAMP_MATERIAL = Enum.Material.SmoothPlastic
local RAMP_COLOR = Color3.fromRGB(180, 140, 60)

local RAMP_DEFINITIONS = {
	{
		name = "Ramp_North",
		size = Vector3.new(30, 2, 50),
		position = Vector3.new(0, 3, -120),
		orientation = Vector3.new(-12, 0, 0),
	},
	{
		name = "Ramp_South",
		size = Vector3.new(30, 2, 50),
		position = Vector3.new(0, 3, 120),
		orientation = Vector3.new(12, 0, 0),
	},
	{
		name = "Ramp_East",
		size = Vector3.new(50, 2, 30),
		position = Vector3.new(120, 3, 0),
		orientation = Vector3.new(0, 0, 12),
	},
	{
		name = "Ramp_West",
		size = Vector3.new(50, 2, 30),
		position = Vector3.new(-120, 3, 0),
		orientation = Vector3.new(0, 0, -12),
	},
	{
		name = "Ramp_Center_Small",
		size = Vector3.new(20, 2, 30),
		position = Vector3.new(60, 3, -60),
		orientation = Vector3.new(-18, 45, 0),
	},
	{
		name = "Ramp_Center_Small2",
		size = Vector3.new(20, 2, 30),
		position = Vector3.new(-60, 3, 60),
		orientation = Vector3.new(-18, -45, 0),
	},
	{
		name = "Ramp_Jump_NE",
		size = Vector3.new(16, 2, 24),
		position = Vector3.new(80, 4, -80),
		orientation = Vector3.new(-25, -30, 0),
	},
	{
		name = "Ramp_Jump_SW",
		size = Vector3.new(16, 2, 24),
		position = Vector3.new(-80, 4, 80),
		orientation = Vector3.new(-25, 150, 0),
	},
}

local CityTrialMapService = Knit.CreateService({
	Name = "CityTrialMapService",
	Client = {},

	_trove = nil,
	_mapFolder = nil,
})

function CityTrialMapService:KnitInit()
	self._trove = Trove.new()
end

function CityTrialMapService:KnitStart()
	self:_buildMap()
end

function CityTrialMapService:_buildMap()
	self:_clearExistingMap()

	local folder = Instance.new("Folder")
	folder.Name = MAP_FOLDER_NAME
	folder.Parent = Workspace
	self._mapFolder = folder
	self._trove:Add(folder)

	self:_buildBaseplate(folder)
	self:_buildRamps(folder)
	self:_buildWalls(folder)

	print("[CityTrialMapService] Map built: " .. BASEPLATE_SIZE.X .. "x" .. BASEPLATE_SIZE.Z .. " baseplate with " .. #RAMP_DEFINITIONS .. " ramps")
end

function CityTrialMapService:_clearExistingMap()
	local existing = Workspace:FindFirstChild(MAP_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
end

function CityTrialMapService:_buildBaseplate(parent)
	local plate = Instance.new("Part")
	plate.Name = "Baseplate"
	plate.Size = BASEPLATE_SIZE
	plate.Position = Vector3.new(0, -BASEPLATE_SIZE.Y / 2, 0)
	plate.Anchored = true
	plate.Color = BASEPLATE_COLOR
	plate.Material = BASEPLATE_MATERIAL
	plate.TopSurface = Enum.SurfaceType.Smooth
	plate.BottomSurface = Enum.SurfaceType.Smooth
	plate.Parent = parent
end

function CityTrialMapService:_buildRamps(parent)
	for _, def in RAMP_DEFINITIONS do
		local ramp = Instance.new("Part")
		ramp.Name = def.name
		ramp.Size = def.size
		ramp.CFrame = CFrame.new(def.position)
			* CFrame.Angles(
				math.rad(def.orientation.X),
				math.rad(def.orientation.Y),
				math.rad(def.orientation.Z)
			)
		ramp.Anchored = true
		ramp.Color = def.color or RAMP_COLOR
		ramp.Material = def.material or RAMP_MATERIAL
		ramp.TopSurface = Enum.SurfaceType.Smooth
		ramp.BottomSurface = Enum.SurfaceType.Smooth
		ramp.Parent = parent
	end
end

function CityTrialMapService:_buildWalls(parent)
	local halfX = BASEPLATE_SIZE.X / 2
	local halfZ = BASEPLATE_SIZE.Z / 2
	local wallHeight = 12
	local wallThickness = 4

	local walls = {
		{ name = "Wall_North", size = Vector3.new(BASEPLATE_SIZE.X, wallHeight, wallThickness), pos = Vector3.new(0, wallHeight / 2, -halfZ) },
		{ name = "Wall_South", size = Vector3.new(BASEPLATE_SIZE.X, wallHeight, wallThickness), pos = Vector3.new(0, wallHeight / 2, halfZ) },
		{ name = "Wall_East",  size = Vector3.new(wallThickness, wallHeight, BASEPLATE_SIZE.Z), pos = Vector3.new(halfX, wallHeight / 2, 0) },
		{ name = "Wall_West",  size = Vector3.new(wallThickness, wallHeight, BASEPLATE_SIZE.Z), pos = Vector3.new(-halfX, wallHeight / 2, 0) },
	}

	for _, def in walls do
		local wall = Instance.new("Part")
		wall.Name = def.name
		wall.Size = def.size
		wall.Position = def.pos
		wall.Anchored = true
		wall.Transparency = 0.6
		wall.Color = Color3.fromRGB(200, 200, 220)
		wall.Material = Enum.Material.ForceField
		wall.CanCollide = true
		wall.Parent = parent
	end
end

function CityTrialMapService:GetMapFolder()
	return self._mapFolder
end

function CityTrialMapService:GetBaseplateSize()
	return BASEPLATE_SIZE
end

return CityTrialMapService
