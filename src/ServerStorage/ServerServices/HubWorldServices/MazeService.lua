local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local source = CustomPackages.Maze.source
local _MazeService = require(source.maze.maze)
local init = require(source.maze.initMaze) -- attaches .generators onto the class

local MazeService = Knit.CreateService {
    Name = "MazeService",
    Client = {},
}

-- voxel render settings
local CELL_SIZE = 10

-- luck block settings
local LUCK_MIN = 3
local LUCK_MAX = 7

local function splitLines(str)
    local t = {}
    for line in string.gmatch(str, "([^\n\r]*)\r?\n?") do
        if line and line ~= "" then
            table.insert(t, line)
        end
    end
    return t
end

function MazeService:KnitStart()
    math.randomseed(os.time())

    -- 1) Build the maze and run a generator
    local maze = _MazeService:new(5, 5, true)
    _MazeService.generators.sidewinder(maze)
    print(maze)

    -- 2) Convert ASCII -> rows
    local ascii = tostring(maze)
    local rows = splitLines(ascii)

    -- 3) Compute maze footprint in studs
    local maxCols = 0
    for _, line in ipairs(rows) do
        if #line > maxCols then
            maxCols = #line
        end
    end
    local mazeWidth  = maxCols * CELL_SIZE
    local mazeDepth  = #rows   * CELL_SIZE
    local halfWidth  = mazeWidth / 2
    local halfDepth  = mazeDepth / 2

    -- 4) Find Baseplate center/top; default to (0,0,0) if not found
    local baseplate = workspace:FindFirstChild("Baseplate")
    local baseCenter = Vector3.new(0, 0, 0)
    local baseTopY = 0
    if baseplate and baseplate:IsA("BasePart") then
        baseCenter = baseplate.Position
        baseTopY = baseplate.Position.Y + baseplate.Size.Y / 2
    end

    -- 5) ORIGIN = center of the bottom layer voxel at (row=1, col=1)
    local ORIGIN = Vector3.new(
        baseCenter.X - halfWidth + CELL_SIZE / 2,
        baseTopY + CELL_SIZE / 2,
        baseCenter.Z - halfDepth + CELL_SIZE / 2
    )

    -- 6) (Re)create a container
    if workspace:FindFirstChild("MazeModel") then
        workspace.MazeModel:Destroy()
    end
    local container = Instance.new("Model")
    container.Name = "MazeModel"
    container.Parent = workspace

    -- 7) Get templates from ReplicatedStorage
    local wallCubeTemplate = ReplicatedStorage:WaitForChild("wallCube")
    assert(wallCubeTemplate:IsA("Model"), "wallCube must be a Model")
    assert(wallCubeTemplate.PrimaryPart, "wallCube must have a PrimaryPart set")

    local luckTemplate = ReplicatedStorage:WaitForChild("LuckBlock")
    assert(luckTemplate:IsA("Model"), "LuckBlock must be a Model")
    assert(luckTemplate.PrimaryPart, "LuckBlock must have a PrimaryPart set")

    -- 8) Build walls/ceilings and collect empty-cell positions for luck blocks
    local openCells = {} -- store Vector3 positions (bottom layer centers)
    for z = 1, #rows do
        local row = rows[z]
        for x = 1, #row do
            local ch = row:sub(x, x)
            local posBase = ORIGIN + Vector3.new((x - 1) * CELL_SIZE, 0, (z - 1) * CELL_SIZE)

            if ch == "#" then
                -- wall cube (bottom layer)
                local wall = wallCubeTemplate:Clone()
                wall:SetPrimaryPartCFrame(CFrame.new(posBase))
                wall.Parent = container
            else
                -- ceiling cube (one block above)
                local ceil = wallCubeTemplate:Clone()
                ceil:SetPrimaryPartCFrame(CFrame.new(posBase + Vector3.new(0, CELL_SIZE, 0)))
                ceil.Parent = container

                -- remember this open cell for potential luck block placement
                table.insert(openCells, posBase)
            end
        end
    end

    -- 9) Randomly drop LuckBlocks in some open cells
    if #openCells > 0 then
        -- decide how many to drop
        local want = math.random(LUCK_MIN, LUCK_MAX)
        local count = math.clamp(want, 1, #openCells)

        -- simple Fisher-Yates shuffle then take first N
        for i = #openCells, 2, -1 do
            local j = math.random(1, i)
            openCells[i], openCells[j] = openCells[j], openCells[i]
        end

        for i = 1, count do
            local pos = openCells[i]
            local lb = luckTemplate:Clone()
            -- Place at floor level (center of open cell). Adjust Y if your model needs it.
            lb:SetPrimaryPartCFrame(CFrame.new(pos))
            lb.Parent = container
        end
    end

    self.Maze = maze
end

function MazeService:KnitInit()
    -- Add service initialization logic here
end

return MazeService
