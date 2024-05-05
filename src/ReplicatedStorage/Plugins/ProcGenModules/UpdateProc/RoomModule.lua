local Room = {}
Room.__index = Room

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PrefabsFolder = ReplicatedStorage:WaitForChild("Prefabs")
local floorTilesFolder = PrefabsFolder:WaitForChild("FloorTiles")
local WallTilesFolder = PrefabsFolder:WaitForChild("WallTiles")
local unitCubeModel = PrefabsFolder:WaitForChild("unitCubeModel")


local Source = ReplicatedStorage.Source
local Plugins = Source.Plugins
local ProcGenModules = Plugins.ProcGenModules

local FloorModule = require(ProcGenModules.UpdateProc.FloorModule)
local WallModule = require(ProcGenModules.UpdateProc.WallModule)


function Room.new(name, size, color)
    local self = setmetatable({}, Room)
    self.name = name or "Default Room"
    self.size = size or Vector3.new(20, 10, 20)  -- Default size if none provided
    self.color = color or Color3.fromRGB(255, 255, 255)  -- Default color if none provided
    self.model = Instance.new("Model", workspace)
    self.model.Name = self.name
    return self
end

function Room:generate()
  
   local floor = FloorModule.new(self.model, floorTilesFolder)
   floor:generateFloor(5, 5)

   local wall = WallModule.new(self.model, WallTilesFolder,unitCubeModel)
   wall:generateWalls(floor, 5)

   -- self:generateFloor()  -- Automatically generate floor when generating the room
end








return Room
