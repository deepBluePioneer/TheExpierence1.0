local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local CustomPackages = ReplicatedStorage.CustomPackages

local Splines = CustomPackages.Splines
local CatmullRomSpline = require(Splines.CatmullRomSpline)
local PlaneSplineController = Knit.CreateController { Name = "SplineTestController" }
local Workspace = game:GetService("Workspace")

local points


function PlaneSplineController:CreateSplineParts(newSpline)

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
        TargetPart.Transparency = 1
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
        TargetPart.Transparency = 1
        TargetPart.CanCollide = false
        TargetPart.Anchored = true
        TargetPart.Locked = true
        TargetPart.Name = "Equidistant" .. tostring(i)
        local point = PointBillboard:Clone()
        point.Parent = TargetPart
        point.Frame.BackgroundColor3 = Color3.fromRGB(33, 255, 114)
        point.Enabled = true
        table.insert(EquidistantPoints, TargetPart)
    end
    local Tangents = {}
    for i = 1, NumPoints do
        local TargetPart = Instance.new("Part", TangentsFolder)
        TargetPart.Size = Vector3.new(0.25, 0.25, 0.25)
        TargetPart.Color = Color3.fromRGB(200, 144, 255)
        TargetPart.Transparency = 1
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

   

    local RunService = game:GetService("RunService")

    local function TweenPlaneAlongSpline(plane, spline, tweenInfo)
        local RunService = game:GetService("RunService")
        local startTime = tick()
        local duration = tweenInfo.Time
    
        local connection
        connection = RunService.Heartbeat:Connect(function()
            local elapsed = (tick() - startTime) % duration
            local alpha = elapsed / duration
    
            local position = spline:CalculatePositionRelativeToLength(alpha)
            local direction = spline:CalculateDerivativeRelativeToLength(alpha)
    
            -- Prevent zero-length direction
            if direction.Magnitude < 0.01 then
                direction = Vector3.new(0, 0, 1)
            else
                direction = direction.Unit
            end
    
            local up = Vector3.new(0, 1, 0)
    
            -- Properly calculate right and corrected up vector
            local right = up:Cross(direction).Unit
            local correctedUp = direction:Cross(right).Unit
    
            plane.CFrame = CFrame.fromMatrix(position, right, correctedUp, direction)
        end)
    
        return connection
    end
    
    
    -- Example usage:
   -- local plane = workspace.plane.PrimaryPart
    --local GlowPartTweenInfo = TweenInfo.new(.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true, 0)
    --local splineTweenConnection = TweenPlaneAlongSpline(plane, newSpline, GlowPartTweenInfo)
    
    



end

function PlaneSplineController:KnitInit()

end

local function init()

    local part_P1 = Workspace:WaitForChild("P1")
    local part_P2 = Workspace:WaitForChild("P2")
    local part_P3 = Workspace:WaitForChild("P3")
    local part_P4 = Workspace:WaitForChild("P4")
    

    points = {part_P1, part_P2, part_P3, part_P4}
    local newSpline = CatmullRomSpline.new(points, .5)
    PlaneSplineController:CreateSplineParts(newSpline)
   
end
function PlaneSplineController:KnitStart()

   -- init()

end
return PlaneSplineController
