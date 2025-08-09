local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SplineTestsController = Knit.CreateController { Name = "SplineTestsController" }

local Splines = CustomPackages.Splines
local CatmullRomSpline = require(Splines.CatmullRomSpline)
local MachineController
local points
local activeSpline
local CameraController



function SplineTestsController:CreateSplineParts(newSpline)
	activeSpline = newSpline

	local BezierFolder = workspace:FindFirstChild("Bezier")
	if BezierFolder then
		BezierFolder:Destroy()
	end

	BezierFolder = Instance.new("Folder")
	BezierFolder.Name = "Bezier"
	BezierFolder.Parent = workspace

	local LinesFolder = Instance.new("Folder")
	LinesFolder.Name = "Lines"
	LinesFolder.Parent = BezierFolder

	local NumPoints = 50
	local SplinePositions = {}
	for i = 1, NumPoints do
		local t = (i - 1) / (NumPoints - 1)
		local pos = newSpline:CalculatePositionAt(t)
		table.insert(SplinePositions, pos)
	end

	-- Store line parts so we can animate them each frame
	local AnimatedLines = {}

	for i = 1, NumPoints - 1 do
		local p1 = SplinePositions[i]
		local p2 = SplinePositions[i + 1]
		local dir = p2 - p1

		local line = Instance.new("Part")
		line.Name = "Line_" .. i
		line.Size = Vector3.new(0.25, 0.25, dir.Magnitude)
		line.CFrame = CFrame.new(p1 + dir * 0.5, p2)
		line.Anchored = true
		line.CanCollide = false
		line.Locked = true
		line.Material = Enum.Material.Neon
		line.Transparency = 0
		line.Parent = LinesFolder
		table.insert(AnimatedLines, {Part = line, T = (i - 1) / (NumPoints - 1)})
	end

	-- Animate colors every frame
	local RunService = game:GetService("RunService")
	if self._gradientConnection then
		self._gradientConnection:Disconnect()
	end
	self._gradientConnection = RunService.RenderStepped:Connect(function()
		local timeOffset = (tick() * 0.25) % 1
		local startColor = Color3.fromRGB(255, 0, 0)
		local endColor = Color3.fromRGB(0, 255, 255)
		for _, data in ipairs(AnimatedLines) do
			local shiftedT = (data.T + timeOffset) % 1
			local color = startColor:Lerp(endColor, shiftedT)
			data.Part.Color = color
		end
	end)

	-- Live update on control part move
	local LastChangeTick = tick()
	for _, controlPart in pairs(points or {}) do
		controlPart.Changed:Connect(function()
			if tick() - LastChangeTick > 0 then
				LastChangeTick = tick()
				self:CreateSplineParts(newSpline)
			end
		end)
	end

	-- Touch start
	local firstPoint = points and points[1]
	if firstPoint then
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
end




function SplineTestsController:AttachToSpline(machine, rootPart, seat)
	local t = 0
	local baseSpeed = 0.25
	local conn

	workspace.Gravity = 0
	MachineController:PauseMovement()

	-- Create ghost part to follow the spline
	local ghostPart = Instance.new("Part")
	ghostPart.Size = Vector3.new(1, 1, 1)
	ghostPart.Anchored = true
	ghostPart.CanCollide = false
	ghostPart.Transparency = 0.5
	ghostPart.Color = Color3.fromRGB(255, 255, 255)
	ghostPart.Material = Enum.Material.Neon
	ghostPart.Name = "SplineGhost"
	ghostPart.Parent = workspace

	-- Position it at the start of the spline
	local startPos = activeSpline:CalculatePositionAt(t)
	local startDir = activeSpline:CalculateDerivativeAt(t).Unit
	ghostPart.CFrame = CFrame.new(startPos, startPos + startDir)

	-- Setup attachments
	local rootAttachment = Instance.new("Attachment")
	rootAttachment.Name = "RootAttachment"
	rootAttachment.Position = Vector3.zero
	rootAttachment.Parent = rootPart

	local ghostAttachment = Instance.new("Attachment")
	ghostAttachment.Name = "GhostAttachment"
	ghostAttachment.Position = Vector3.zero
	ghostAttachment.Parent = ghostPart

	-- AlignPosition for following
	local alignPos = Instance.new("AlignPosition")
	alignPos.Name = "SplineAlignPosition"
	alignPos.Attachment0 = rootAttachment
	alignPos.Attachment1 = ghostAttachment
	alignPos.MaxForce = 1e9
	alignPos.Responsiveness = 1000
	alignPos.RigidityEnabled = true
	alignPos.ApplyAtCenterOfMass = true
	alignPos.Parent = rootPart

	-- AlignOrientation for rotation
	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "SplineAlignOrientation"
	alignOrientation.Attachment0 = rootAttachment
	alignOrientation.Attachment1 = ghostAttachment
	alignOrientation.MaxTorque = 1e9
	alignOrientation.Responsiveness = 1000
	alignOrientation.RigidityEnabled = true
	alignOrientation.Parent = rootPart

	-- Optional immediate snap at start
	rootPart.CFrame = ghostPart.CFrame

	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt * baseSpeed

		local pos = activeSpline:CalculatePositionAt(math.min(t, 1))
		local dir = activeSpline:CalculateDerivativeAt(math.min(t, 1)).Unit

		-- Flatten direction for level orientation
		local flatDir = Vector3.new(dir.X, 0, dir.Z)
		if flatDir.Magnitude < 0.01 then
			flatDir = Vector3.new(0, 0, -1)
		end
		flatDir = flatDir.Unit

		ghostPart.CFrame = CFrame.lookAt(pos, pos + flatDir, Vector3.yAxis)

		-- If too far behind, snap rootPart to ghostPart
		if (rootPart.Position - ghostPart.Position).Magnitude > 10 then
			rootPart.CFrame = ghostPart.CFrame
		end

		CameraController:UpdateFixed(rootPart)

		if t >= 1 then
			conn:Disconnect()
			MachineController:ResumeMovement()

			ghostPart:Destroy()
			alignPos:Destroy()
			alignOrientation:Destroy()
			rootAttachment:Destroy()
			ghostAttachment:Destroy()
			return
		end
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
	MachineController = Knit.GetController("MachineController")
	CameraController = Knit.GetController("CameraController")
	self:init()
end

function SplineTestsController:KnitInit() end

return SplineTestsController
