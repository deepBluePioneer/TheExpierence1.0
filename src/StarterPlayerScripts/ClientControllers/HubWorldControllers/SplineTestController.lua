local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local CustomPackages = ReplicatedStorage.CustomPackages

local Splines = CustomPackages.Splines
local CatmullRomSpline = require(Splines.CatmullRomSpline)
local SplineTestController = Knit.CreateController { Name = "SplineTestController" }

local points

function SplineTestController:CreateSplineParts(newSpline)

    -- Create a new BillboardGui for each part
    local PointBillboard = Instance.new("BillboardGui", TargetPart)
    PointBillboard.Size = UDim2.new(1, 0, 1, 0)

    -- Create a Frame inside the BillboardGui
    local frame = Instance.new("Frame", PointBillboard)
    frame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    frame.Size = UDim2.new(1, 0, 1, 0)
    
    local BezierFolder = Instance.new("Folder", workspace)
    local PointsFolder = Instance.new("Folder", BezierFolder)
    local TangentsFolder = Instance.new("Folder", BezierFolder)
    local LinesFolder = Instance.new("Folder", BezierFolder)
    BezierFolder.Name = "Bezier"
    PointsFolder.Name = "Points"
    TangentsFolder.Name = "Tangents"
    LinesFolder.Name = "Lines"


    local NumPoints = 100


    local DefaultPoints, EquidistantPoints = {}, {}
    for i = 1, NumPoints do
        local TargetPart = Instance.new("Part", PointsFolder)
        TargetPart.Size = Vector3.new(0.85, 0.85, 0.85)
        TargetPart.Color = Color3.fromRGB(255, 15, 159)
        TargetPart.Transparency = .5
        TargetPart.CanCollide = false
        TargetPart.Anchored = true
        TargetPart.Locked = true
        TargetPart.Name = "Default" .. tostring(i)
        local point = PointBillboard:Clone()
        point.Parent = TargetPart
        point.Frame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        point.Enabled = false
        table.insert(DefaultPoints, TargetPart)
    end
    for i = 1, NumPoints do
        local TargetPart = Instance.new("Part", PointsFolder)
        TargetPart.Size = Vector3.new(0.85, 0.85, 0.85)
        TargetPart.Color = Color3.fromRGB(255, 15, 159)
        TargetPart.Transparency =.5
        TargetPart.CanCollide = false
        TargetPart.Anchored = true
        TargetPart.Locked = true
        TargetPart.Name = "Equidistant" .. tostring(i)
        local point = PointBillboard:Clone()
        point.Parent = TargetPart
        point.Frame.BackgroundColor3 = Color3.fromRGB(33, 255, 114)
        point.Enabled = false
        table.insert(EquidistantPoints, TargetPart)
    end
    local Tangents = {}
    for i = 1, NumPoints do
        local TargetPart = Instance.new("Part", TangentsFolder)
        TargetPart.Size = Vector3.new(0.25, 0.25, 0.25)
        TargetPart.Color = Color3.fromRGB(200, 144, 255)
        TargetPart.Transparency = .5
        TargetPart.CanCollide = false
        TargetPart.Anchored = true
        TargetPart.Locked = true
        TargetPart.Name = tostring(i)
        table.insert(Tangents, TargetPart)
    end
    local Lines, ControlLines = {}, {}
    for i = 1, NumPoints - 1 do
        local TargetPart = Instance.new("Part", LinesFolder)
        TargetPart.Size = Vector3.new(0.55, 0.55, 1)
        TargetPart.Color = Color3.fromRGB(33, 33, 40)
        TargetPart.CanCollide = false
        TargetPart.Transparency = .5

        TargetPart.Anchored = true
        TargetPart.Locked = true
        TargetPart.Name = tostring(i)
        table.insert(Lines, TargetPart)
    end
    for i = 1, #points - 1 do
        local TargetPart = Instance.new("Part", LinesFolder)
        TargetPart.Size = Vector3.new(0.55, 0.55, 1)
        TargetPart.Color = Color3.fromRGB(194, 194, 234)
        TargetPart.Transparency = 0.95
        TargetPart.CanCollide = false
        TargetPart.Anchored = true
        TargetPart.Locked = true
        TargetPart.Name = tostring(i)
        table.insert(ControlLines, TargetPart)
    end


    local function UpdateBezier()
        for i = 1, NumPoints do
            local t = (i - 1) / (#DefaultPoints - 1)
            local p1 = newSpline:CalculatePositionAt(t)
            local d1 = newSpline:CalculateDerivativeAt(t)
            local p2 = newSpline:CalculatePositionRelativeToLength(t)
            local d2 = newSpline:CalculateDerivativeRelativeToLength(t)
            Tangents[i].Size = Vector3.new(Tangents[i].Size.X, Tangents[i].Size.Y, 0.5 * d2.Magnitude)
            Tangents[i].CFrame = CFrame.new(p1, p1 + d2)
            DefaultPoints[i].CFrame = CFrame.new(p1, p1 + d1)
            EquidistantPoints[i].CFrame = CFrame.new(p2, p2 + d2)
        end
        for i = 1, #Lines do
            local line = Lines[i]
            local p1, p2 = DefaultPoints[i].Position, DefaultPoints[i + 1].Position
            line.Size = Vector3.new(line.Size.X, line.Size.Y, (p2 - p1).Magnitude)
            line.CFrame = CFrame.new(0.5 * (p1 + p2), p2)
        end
        for i = 1, #ControlLines do
            local line = ControlLines[i]
            local p1, p2 = points[i].Position, points[i + 1].Position
            line.Size = Vector3.new(line.Size.X, line.Size.Y, (p2 - p1).Magnitude)
            line.CFrame = CFrame.new(0.5 * (p1 + p2), p2)
        end
    end
    UpdateBezier()

    local LastChangeTick = tick()
    for _, controlPart in pairs(points) do
        controlPart.Changed:Connect(function()
            if tick() - LastChangeTick > 0 then
                LastChangeTick = tick()
                UpdateBezier()
            end
        end)
    end

   -- local Tween1 = newSpline:CreateTween(Saw, GlowPartTweenInfo, {"CFrame"}, true)
    --local splineTween = newSpline:CreateTween(Saw, nil, {"CFrame"}, true)
   -- local splineTween = newSpline:CreateTweenWithLinearVelocity(Saw, {"CFrame"}, true)


   

end

function SplineTestController:KnitInit()

end

local function init()

    Saw = workspace.Saw.PrimaryPart
    points = {workspace.P1, workspace.P2, workspace.P5 ,workspace.P7}
    local newSpline = CatmullRomSpline.new(points, 0)
    SplineTestController:CreateSplineParts(newSpline)
   
end
function SplineTestController:KnitStart()

    init()

end
return SplineTestController
