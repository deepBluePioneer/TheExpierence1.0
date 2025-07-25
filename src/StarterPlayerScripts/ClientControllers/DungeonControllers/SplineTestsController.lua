local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SplineTestsController = Knit.CreateController { Name = "SplineTestsController" }

local Splines = CustomPackages.Splines
local CatmullRomSpline = require(Splines.CatmullRomSpline)

local points
local activeSpline
local CameraController

function SplineTestsController:SetupMachine(machine)
	local controllerManager = machine:FindFirstChildWhichIsA("ControllerManager", true)
	local groundController = machine:FindFirstChildWhichIsA("GroundController", true)
	local groundSensor = machine:FindFirstChildWhichIsA("ControllerPartSensor", true)
	local rootPart = machine:FindFirstChild("RootPart")
	local seat = machine:FindFirstChildWhichIsA("Seat", true)

	if not rootPart or not seat then return end

	if controllerManager then
		controllerManager.ActiveController = nil
	end
	if groundController then
		groundController.Enabled = false
	end
	if groundSensor then
		groundSensor.Enabled = false
	end

    CameraController:StopFollowing()
	CameraController:StartFixed(seat, rootPart)

	self:AttachToSpline(machine, rootPart, seat)
end

function SplineTestsController:GetMachines()
	task.wait(5)
	local machines = CollectionService:GetTagged("machine")
	for _, machine in ipairs(machines) do
		if machine:IsDescendantOf(workspace) then
			self:SetupMachine(machine)
		end
	end
end

function SplineTestsController:CreateSplineParts(newSpline)
	activeSpline = newSpline -- store globally so we can reuse it in other functions

	local PointBillboard = Instance.new("BillboardGui")
	PointBillboard.Size = UDim2.new(1, 0, 1, 0)
	local frame = Instance.new("Frame", PointBillboard)
	frame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	frame.Size = UDim2.new(1, 0, 1, 0)

	local BezierFolder = Instance.new("Folder", workspace)
	BezierFolder.Name = "Bezier"

	local PointsFolder = Instance.new("Folder", BezierFolder)
	PointsFolder.Name = "Points"

	local TangentsFolder = Instance.new("Folder", BezierFolder)
	TangentsFolder.Name = "Tangents"

	local LinesFolder = Instance.new("Folder", BezierFolder)
	LinesFolder.Name = "Lines"

	local NumPoints = 10
	local DefaultPoints, EquidistantPoints = {}, {}

	for i = 1, NumPoints do
		local TargetPart = Instance.new("Part", PointsFolder)
		TargetPart.Size = Vector3.new(0.85, 0.85, 0.85)
		TargetPart.Color = Color3.fromRGB(255, 15, 159)
		TargetPart.Transparency = 0
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
		TargetPart.Transparency = 0
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
		TargetPart.Transparency = .0
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

	-- Add Touch Detection on First Point
	local firstPoint = points[1]
	firstPoint.Touched:Connect(function(hit)
		local machine = hit:FindFirstAncestorOfClass("Model")
		if machine and CollectionService:HasTag(machine, "machine") then
			local rootPart = machine:FindFirstChild("RootPart")
			if rootPart and hit == rootPart then
				self:AttachToSpline(machine, rootPart)
			end
		end
	end)
end

function SplineTestsController:AttachToSpline(machine, rootPart, seat)
	if not activeSpline then return end

	local t = 0
	local speed = 0.25
	local conn

	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt * speed
		if t >= 1 then
			local pos = activeSpline:CalculatePositionAt(1)
			local dir = activeSpline:CalculateDerivativeAt(1)
			rootPart.CFrame = CFrame.new(pos, pos + dir)
			conn:Disconnect()
            task.delay(0.2, function()
                    CameraController:StopFollowing()
                end)
		
			return
		end

		local pos = activeSpline:CalculatePositionAt(t)
		local dir = activeSpline:CalculateDerivativeAt(t)
		rootPart.CFrame = CFrame.new(pos, pos + dir)

        CameraController:UpdateFixed(rootPart)

	end)
end

function SplineTestsController:init()
	local SplinePoints = workspace:WaitForChild("SplinePoints")
	points = {
		SplinePoints.p1,
		SplinePoints.p2,
		SplinePoints.p3,
		SplinePoints.p4,
		SplinePoints.p5,
		SplinePoints.p6,
		SplinePoints.p7
	}
	local newSpline = CatmullRomSpline.new(points, .5)
	self:CreateSplineParts(newSpline)
end

function SplineTestsController:KnitStart()
     CameraController = Knit.GetController("CameraController")


	self:init()
end

function SplineTestsController:KnitInit() end

return SplineTestsController
