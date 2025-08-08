-- ReplicatedStorage.CustomPackages.Maze.source.maze.init

-- In Roblox, modules are children. No need for requireRel/arg/...
local Maze = require(script.Parent.maze)

-- Attach generator functions as a table (like the CLI init did)
Maze.generators = {
   
    sidewinder           = require(script.Parent.generators.sidewinder)}

-- If you actually use the Love helpers, you can still expose them.


return Maze
