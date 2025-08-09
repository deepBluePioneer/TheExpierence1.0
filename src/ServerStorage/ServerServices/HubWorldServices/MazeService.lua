local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local source = CustomPackages.Maze.source
local _MazeService = require(source.maze.maze)
local init = require(source.maze.initMaze)

local MazeService = Knit.CreateService {
    Name = "MazeService",
    Client = {},
}

-- ===== Settings =====
local CELL_SIZE = 10
local LUCK_MIN, LUCK_MAX = 3, 7

local RED    = Color3.fromRGB(255, 60, 60)
local WHITE  = Color3.fromRGB(255, 255, 255)
local BLUE   = Color3.fromRGB(60, 120, 255)

-- ===== Helpers =====
local function splitLines(str)
    local t = {}
    for line in string.gmatch(str, "([^\n\r]*)\r?\n?") do
        if line and line ~= "" then
            table.insert(t, line)
        end
    end
    return t
end

local function applyColorToWallCube(model: Model, color: Color3)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc.Name == "color" and (desc:IsA("Folder") or desc:IsA("Model")) then
            for _, child in ipairs(desc:GetChildren()) do
                if child:IsA("Highlight") then
                    child.FillColor = color
                    child.OutlineColor = color
                    if not child.Adornee then
                        child.Adornee = model.PrimaryPart or model
                    end
                elseif child:IsA("BasePart") then
                    child.Color = color
                end
            end
        end
    end
end

function MazeService:KnitStart()

    task.wait(3)
    math.randomseed(os.time())

    -- 1) Build a maze
    local maze = _MazeService:new(15, 15, true)
     _MazeService.generators.prim(maze)

  --  _MazeService.generators.sidewinder(maze)

    -- 2) ASCII -> rows
    local rows = splitLines(tostring(maze))

    -- 3) Dimensions + origin
    local maxCols = 0
    for _, line in ipairs(rows) do
        if #line > maxCols then maxCols = #line end
    end
    local mazeWidth  = maxCols * CELL_SIZE
    local mazeDepth  = #rows * CELL_SIZE
    local halfWidth  = mazeWidth / 2
    local halfDepth  = mazeDepth / 2

    local baseplate = workspace:FindFirstChild("Baseplate")
    local baseCenter = Vector3.new(0, 0, 0)
    local baseTopY = 0
    if baseplate and baseplate:IsA("BasePart") then
        baseCenter = baseplate.Position
        baseTopY = baseplate.Position.Y + baseplate.Size.Y / 2
    end

    local ORIGIN = Vector3.new(
        baseCenter.X - halfWidth + CELL_SIZE / 2,
        baseTopY + CELL_SIZE / 2,
        baseCenter.Z - halfDepth + CELL_SIZE / 2
    )

    -- 4) Reset container
    if workspace:FindFirstChild("MazeModel") then
        workspace.MazeModel:Destroy()
    end
    local container = Instance.new("Model")
    container.Name = "MazeModel"
    container.Parent = workspace

    -- 5) Templates
    local wallCubeTemplate = ReplicatedStorage:WaitForChild("wallCube")
    assert(wallCubeTemplate:IsA("Model") and wallCubeTemplate.PrimaryPart, "wallCube must be a Model with PrimaryPart")
    local luckTemplate = ReplicatedStorage:WaitForChild("LuckBlock")
    assert(luckTemplate:IsA("Model") and luckTemplate.PrimaryPart, "LuckBlock must be a Model with PrimaryPart")

    -- 6) Define split zones
    local leftEndCol  = math.floor(maxCols / 3)          -- last col of red zone
    local middleEndCol = math.floor(maxCols * 2 / 3)     -- last col of white zone

    local openCells = {}

    -- 7) Build maze geometry
    for z = 1, #rows do
        local row = rows[z]
        for x = 1, #row do
            local ch = row:sub(x, x)
            local posBase = ORIGIN + Vector3.new((x - 1) * CELL_SIZE, 0, (z - 1) * CELL_SIZE)

            -- Choose color based on which zone the column is in
            local tint
            if x <= leftEndCol then
                tint = RED
            elseif x <= middleEndCol then
                tint = WHITE
            else
                tint = BLUE
            end

            if ch == "#" then
                local wall = wallCubeTemplate:Clone()
                wall:SetPrimaryPartCFrame(CFrame.new(posBase))
                wall.Parent = container
                applyColorToWallCube(wall, tint)
            else
                local ceil = wallCubeTemplate:Clone()
                ceil:SetPrimaryPartCFrame(CFrame.new(posBase + Vector3.new(0, CELL_SIZE, 0)))
                ceil.Parent = container
                applyColorToWallCube(ceil, tint)

                table.insert(openCells, posBase)
            end
        end
    end

    -- 8) Spawn luck blocks
    if #openCells > 0 then
        local count = math.clamp(math.random(LUCK_MIN, LUCK_MAX), 1, #openCells)
        for i = #openCells, 2, -1 do
            local j = math.random(1, i)
            openCells[i], openCells[j] = openCells[j], openCells[i]
        end
        for i = 1, count do
            local lb = luckTemplate:Clone()
            lb:SetPrimaryPartCFrame(CFrame.new(openCells[i]))
            lb.Parent = container
        end
    end

    self.Maze = maze
end

function MazeService:KnitInit() end

return MazeService
