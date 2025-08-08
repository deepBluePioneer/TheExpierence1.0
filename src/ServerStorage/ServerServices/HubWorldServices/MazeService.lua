local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local source = CustomPackages.Maze.source
local _MazeService = require(source.maze.maze)
local init = require(source.maze.initMaze)


local MazeService = Knit.CreateService {
    Name = "MazeService",
    Client = {},
}

function MazeService:KnitStart()
     math.randomseed(os.time())
    local maze = _MazeService:new(17, 19, true)
    maze.generators.sidewinder(maze)
     print(maze)

end

function MazeService:KnitInit()
    -- Add service initialization logic here
end

return MazeService