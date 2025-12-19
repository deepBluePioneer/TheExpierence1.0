-- SplineService
-- Creates and manages splines from workspace point folders
-- Uses CatmullRomSpline module for smooth curve interpolation
-- Handles player ride along spline with seat

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local CatmullRomSpline = require(CustomPackages.Splines.CatmullRomSpline)

local SplineService = Knit.CreateService {
	Name = "SplineService",
	Client = {
		-- Client can request spline data
		SplineCreated = Knit.CreateSignal(),
		-- Signal to tell client to make player transparent
		MakePlayerTransparent = Knit.CreateSignal(),
		-- Signal to tell client ride started/ended
		RideStateChanged = Knit.CreateSignal(),
	},
}

-- =========================================================
-- CONFIG
-- =========================================================

local CONFIG = {
	-- Default spline settings
	DefaultTension = 0.5,           -- Catmull-Rom tension (0.5 = centripetal)
	
	-- Visualization settings
	VisualizeSplines = true,        -- Create visual representation of splines
	VisualSegmentCount = 100,       -- Number of segments for visualization
	VisualPartSize = Vector3.new(0.3, 0.3, 1),
	VisualMaterial = Enum.Material.Neon,
	VisualColor = Color3.fromRGB(0, 170, 255),
	UseRainbowGradient = true,      -- Rainbow color along spline
	
	-- Ride settings
	RideSplineName = "spline_1",    -- Which spline to use for the ride
	RideDuration = 60,              -- Time in seconds to complete the ride
	RideEasingStyle = Enum.EasingStyle.Linear,
	RideEasingDirection = Enum.EasingDirection.InOut,
	SeatSize = Vector3.new(2, 0.5, 2),
	SeatTransparency = 1,           -- Make seat invisible
	SeatHeightOffset = 3,           -- Height above spline path
	AutoStartRide = true,           -- Automatically start ride when player sits
	LoopRide = true,                -- Loop the ride continuously
}

-- =========================================================
-- STATE
-- =========================================================

local splines = {}  -- [splineName] = { spline = CatmullRomSplineObject, points = {}, visual = Folder }
local visualFolder = nil

-- Ride state
local rideSeat = nil           -- The Seat instance for the ride
local rideFolder = nil         -- Folder containing ride elements
local activeRides = {}         -- [player] = { tween = Tween, seat = Seat }
local playerConnections = {}   -- [player] = {connections}

-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================

-- Get sorted control points from a folder based on pointNumber attribute
local function getSortedPointsFromFolder(folder)
	local pointData = {}
	
	for _, child in ipairs(folder:GetChildren()) do
		local pointNumber = child:GetAttribute("pointNumber")
		if pointNumber then
			local position = nil
			
			if child:IsA("BasePart") then
				position = child.Position
				table.insert(pointData, {
					instance = child,
					pointNumber = pointNumber,
					position = position,
				})
			elseif child:IsA("Attachment") then
				position = child.WorldPosition
				table.insert(pointData, {
					instance = child,
					pointNumber = pointNumber,
					position = position,
				})
			end
		end
	end
	
	-- Sort by pointNumber
	table.sort(pointData, function(a, b)
		return a.pointNumber < b.pointNumber
	end)
	
	return pointData
end

-- =========================================================
-- SPLINE CREATION
-- =========================================================

function SplineService:CreateSplineFromFolder(folderName: string, tension: number?)
	local folder = Workspace:FindFirstChild(folderName)
	if not folder then
		warn("[SplineService] Folder not found in workspace:", folderName)
		return nil
	end
	
	local pointData = getSortedPointsFromFolder(folder)
	
	if #pointData < 4 then
		warn("[SplineService] Need at least 4 points to create a spline, found:", #pointData)
		return nil
	end
	
	-- Extract positions or BaseParts for the spline
	local controlPoints = {}
	for _, data in ipairs(pointData) do
		-- Use BasePart directly so spline auto-updates when parts move
		if data.instance:IsA("BasePart") then
			table.insert(controlPoints, data.instance)
		else
			table.insert(controlPoints, data.position)
		end
	end
	
	-- Create the CatmullRom spline
	local splineTension = tension or CONFIG.DefaultTension
	local spline = CatmullRomSpline.new(controlPoints, splineTension)
	
	-- Store spline data
	splines[folderName] = {
		spline = spline,
		points = pointData,
		folderName = folderName,
		tension = splineTension,
		visual = nil,
	}
	
	print(string.format("[SplineService] Created spline '%s' with %d control points, length: %.2f studs", 
		folderName, #pointData, spline.Length))
	
	-- Create visualization if enabled
	if CONFIG.VisualizeSplines then
		self:CreateSplineVisualization(folderName)
	end
	
	-- Fire signal for clients
	self.Client.SplineCreated:FireAll(folderName, #pointData, spline.Length)
	
	return splines[folderName]
end

function SplineService:CreateSplineVisualization(splineName: string)
	local splineData = splines[splineName]
	if not splineData then
		warn("[SplineService] Spline not found:", splineName)
		return
	end
	
	-- Create or get visual folder
	if not visualFolder then
		visualFolder = Workspace:FindFirstChild("SplineVisuals")
		if not visualFolder then
			visualFolder = Instance.new("Folder")
			visualFolder.Name = "SplineVisuals"
			visualFolder.Parent = Workspace
		end
	end
	
	-- Remove existing visualization for this spline
	if splineData.visual then
		splineData.visual:Destroy()
	end
	
	-- Create folder for this spline's visualization
	local splineVisual = Instance.new("Folder")
	splineVisual.Name = splineName .. "_visual"
	splineVisual.Parent = visualFolder
	splineData.visual = splineVisual
	
	local spline = splineData.spline
	local segmentCount = CONFIG.VisualSegmentCount
	
	-- Generate visual segments
	for i = 0, segmentCount - 1 do
		local t0 = i / segmentCount
		local t1 = (i + 1) / segmentCount
		
		local pos0 = spline:CalculatePositionRelativeToLength(t0)
		local pos1 = spline:CalculatePositionRelativeToLength(t1)
		
		local midPoint = (pos0 + pos1) / 2
		local distance = (pos1 - pos0).Magnitude
		
		if distance > 0.01 then
			local part = Instance.new("Part")
			part.Name = "Segment_" .. i
			part.Anchored = true
			part.CanCollide = false
			part.CastShadow = false
			part.Size = Vector3.new(CONFIG.VisualPartSize.X, CONFIG.VisualPartSize.Y, distance)
			part.CFrame = CFrame.lookAt(midPoint, pos1)
			part.Material = CONFIG.VisualMaterial
			
			if CONFIG.UseRainbowGradient then
				part.Color = Color3.fromHSV((i / segmentCount) * 0.7, 1, 1)
			else
				part.Color = CONFIG.VisualColor
			end
			
			part.Parent = splineVisual
		end
	end
	
	print(string.format("[SplineService] Created visualization for '%s' with %d segments", splineName, segmentCount))
end

-- =========================================================
-- SPLINE METHODS
-- =========================================================

function SplineService:GetSpline(splineName: string)
	local splineData = splines[splineName]
	if splineData then
		return splineData.spline
	end
	return nil
end

function SplineService:GetSplineData(splineName: string)
	return splines[splineName]
end

function SplineService:GetAllSplineNames(): {string}
	local names = {}
	for name, _ in pairs(splines) do
		table.insert(names, name)
	end
	return names
end

function SplineService:GetPositionAt(splineName: string, t: number, relativeToLength: boolean?): Vector3?
	local splineData = splines[splineName]
	if not splineData then
		warn("[SplineService] Spline not found:", splineName)
		return nil
	end
	
	local spline = splineData.spline
	if relativeToLength then
		return spline:CalculatePositionRelativeToLength(t)
	else
		return spline:CalculatePositionAt(t)
	end
end

function SplineService:GetDerivativeAt(splineName: string, t: number, relativeToLength: boolean?): Vector3?
	local splineData = splines[splineName]
	if not splineData then
		warn("[SplineService] Spline not found:", splineName)
		return nil
	end
	
	local spline = splineData.spline
	if relativeToLength then
		return spline:CalculateDerivativeRelativeToLength(t)
	else
		return spline:CalculateDerivativeAt(t)
	end
end

function SplineService:GetCFrameAt(splineName: string, t: number, relativeToLength: boolean?): CFrame?
	local position = self:GetPositionAt(splineName, t, relativeToLength)
	local derivative = self:GetDerivativeAt(splineName, t, relativeToLength)
	
	if position and derivative then
		local direction = derivative.Unit
		return CFrame.lookAt(position, position + direction)
	end
	
	return nil
end

function SplineService:GetLength(splineName: string): number?
	local splineData = splines[splineName]
	if splineData then
		return splineData.spline.Length
	end
	return nil
end

function SplineService:CreateTween(splineName: string, instance: Instance, tweenInfo: TweenInfo, propertyTable: {string}, relativeToLength: boolean?): Tween?
	local splineData = splines[splineName]
	if not splineData then
		warn("[SplineService] Spline not found:", splineName)
		return nil
	end
	
	return splineData.spline:CreateTween(instance, tweenInfo, propertyTable, relativeToLength)
end

function SplineService:RemoveSpline(splineName: string)
	local splineData = splines[splineName]
	if splineData then
		-- Destroy visualization
		if splineData.visual then
			splineData.visual:Destroy()
		end
		
		splines[splineName] = nil
		print("[SplineService] Removed spline:", splineName)
	end
end

function SplineService:ClearAllSplines()
	for splineName, splineData in pairs(splines) do
		if splineData.visual then
			splineData.visual:Destroy()
		end
	end
	splines = {}
	print("[SplineService] Cleared all splines")
end

function SplineService:RefreshVisualization(splineName: string)
	local splineData = splines[splineName]
	if splineData then
		-- Update spline length (in case points moved)
		splineData.spline:UpdateLength()
		
		-- Recreate visualization
		self:CreateSplineVisualization(splineName)
	end
end

-- =========================================================
-- RIDE SYSTEM
-- =========================================================

function SplineService:CreateRideSeat(splineName: string)
	local splineData = splines[splineName]
	if not splineData then
		warn("[SplineService] Cannot create ride seat - spline not found:", splineName)
		return nil
	end
	
	-- Create ride folder if not exists
	if not rideFolder then
		rideFolder = Instance.new("Folder")
		rideFolder.Name = "SplineRide"
		rideFolder.Parent = Workspace
	end
	
	-- Get position at the start of the spline (t = 0)
	local startPos = splineData.spline:CalculatePositionAt(0)
	local startDerivative = splineData.spline:CalculateDerivativeAt(0)
	local startCFrame = CFrame.lookAt(startPos, startPos + startDerivative.Unit)
	
	-- Offset seat height
	startCFrame = startCFrame + Vector3.new(0, CONFIG.SeatHeightOffset, 0)
	
	-- Create the seat (regular Seat, not VehicleSeat)
	local seat = Instance.new("Seat")
	seat.Name = "RideSeat_" .. splineName
	seat.Size = CONFIG.SeatSize
	seat.CFrame = startCFrame
	seat.Anchored = true
	seat.CanCollide = false
	seat.Transparency = CONFIG.SeatTransparency
	seat.Parent = rideFolder
	
	-- Store reference
	rideSeat = seat
	splineData.seat = seat
	
	print(string.format("[SplineService] Created ride seat for '%s' at (%.1f, %.1f, %.1f)", 
		splineName, startPos.X, startPos.Y, startPos.Z))
	
	return seat
end

function SplineService:SeatPlayer(player: Player)
	if not rideSeat then
		warn("[SplineService] No ride seat available")
		return false
	end
	
	local character = player.Character
	if not character then
		warn("[SplineService] Player has no character:", player.Name)
		return false
	end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("[SplineService] Character has no humanoid:", player.Name)
		return false
	end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		warn("[SplineService] Character has no HumanoidRootPart:", player.Name)
		return false
	end
	
	print("[SplineService] Seating player:", player.Name)
	
	-- Anchor all character parts so they don't fall off
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false -- Must be unanchored to be welded
		end
	end
	
	-- Move player to seat position
	rootPart.CFrame = rideSeat.CFrame * CFrame.new(0, 1, 0)
	
	-- Create a weld to attach player to seat
	local existingWeld = rideSeat:FindFirstChild("PlayerWeld")
	if existingWeld then
		existingWeld:Destroy()
	end
	
	local weld = Instance.new("WeldConstraint")
	weld.Name = "PlayerWeld"
	weld.Part0 = rideSeat
	weld.Part1 = rootPart
	weld.Parent = rideSeat
	
	-- Force sit on the seat
	humanoid.Sit = true
	rideSeat:Sit(humanoid)
	
	-- Disable player controls while on ride
	humanoid.PlatformStand = true
	
	print("[SplineService] Seated and welded player:", player.Name)
	
	-- Wait a moment for client to be ready, then tell client to make player transparent
	task.delay(0.3, function()
		print("[SplineService] Sending MakePlayerTransparent signal to", player.Name)
		self.Client.MakePlayerTransparent:Fire(player, true)
	end)
	
	-- Auto-start ride if enabled
	if CONFIG.AutoStartRide then
		task.delay(0.5, function()
			print("[SplineService] Auto-starting ride for", player.Name)
			self:StartRide(player, CONFIG.RideSplineName)
		end)
	end
	
	return true
end

function SplineService:StartRide(player: Player, splineName: string)
	local splineData = splines[splineName]
	if not splineData then
		warn("[SplineService] Cannot start ride - spline not found:", splineName)
		return false
	end
	
	local seat = splineData.seat or rideSeat
	if not seat then
		warn("[SplineService] No seat available for ride")
		return false
	end
	
	-- Cancel any existing ride for this player
	if activeRides[player] and activeRides[player].tween then
		activeRides[player].tween:Cancel()
	end
	
	-- Create tween info
	local tweenInfo = TweenInfo.new(
		CONFIG.RideDuration,
		CONFIG.RideEasingStyle,
		CONFIG.RideEasingDirection,
		CONFIG.LoopRide and -1 or 0,  -- -1 for infinite loops
		false,
		0
	)
	
	-- Use the spline's CreateTween method to animate the seat along the path
	-- This will smoothly interpolate the CFrame along the spline
	local tween = splineData.spline:CreateTween(seat, tweenInfo, {"CFrame"}, true)
	
	-- Store active ride
	activeRides[player] = {
		tween = tween,
		seat = seat,
		splineName = splineName,
	}
	
	-- Start the tween
	tween:Play()
	
	-- Notify client that ride started
	self.Client.RideStateChanged:Fire(player, true, splineName)
	
	print(string.format("[SplineService] Started ride for %s on '%s' (duration: %ds)", 
		player.Name, splineName, CONFIG.RideDuration))
	
	return true
end

function SplineService:StopRide(player: Player)
	local rideData = activeRides[player]
	if not rideData then
		return false
	end
	
	-- Stop the tween
	if rideData.tween then
		rideData.tween:Cancel()
	end
	
	-- Notify client
	self.Client.RideStateChanged:Fire(player, false, rideData.splineName)
	self.Client.MakePlayerTransparent:Fire(player, false)
	
	-- Clean up
	activeRides[player] = nil
	
	print("[SplineService] Stopped ride for:", player.Name)
	return true
end

function SplineService:SetupPlayerSpawnHandler()
	-- Handle new players
	Players.PlayerAdded:Connect(function(player)
		-- Wait for character to spawn
		local connection = player.CharacterAdded:Connect(function(character)
			-- Wait for character to fully load
			task.wait(1)
			
			-- Seat the player
			self:SeatPlayer(player)
		end)
		
		-- Store connection for cleanup
		playerConnections[player] = {connection}
		
		-- Handle if character already exists
		if player.Character then
			task.delay(1, function()
				self:SeatPlayer(player)
			end)
		end
	end)
	
	-- Handle player leaving
	Players.PlayerRemoving:Connect(function(player)
		-- Stop any active ride
		self:StopRide(player)
		
		-- Clean up connections
		if playerConnections[player] then
			for _, conn in ipairs(playerConnections[player]) do
				conn:Disconnect()
			end
			playerConnections[player] = nil
		end
	end)
	
	-- Handle existing players (in case service starts after players join)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			task.defer(function()
				self:SeatPlayer(player)
			end)
		end
		
		local connection = player.CharacterAdded:Connect(function(character)
			task.wait(1)
			self:SeatPlayer(player)
		end)
		
		playerConnections[player] = playerConnections[player] or {}
		table.insert(playerConnections[player], connection)
	end
	
	print("[SplineService] Player spawn handler set up")
end

-- =========================================================
-- CLIENT METHODS
-- =========================================================

function SplineService.Client:GetSplineNames(player)
	return SplineService:GetAllSplineNames()
end

function SplineService.Client:GetPositionAt(player, splineName: string, t: number, relativeToLength: boolean?)
	return SplineService:GetPositionAt(splineName, t, relativeToLength)
end

function SplineService.Client:GetCFrameAt(player, splineName: string, t: number, relativeToLength: boolean?)
	return SplineService:GetCFrameAt(splineName, t, relativeToLength)
end

function SplineService.Client:GetLength(player, splineName: string)
	return SplineService:GetLength(splineName)
end

-- =========================================================
-- KNIT LIFECYCLE
-- =========================================================

function SplineService:KnitInit()
	print("[SplineService] Initializing")
end

function SplineService:KnitStart()
	print("[SplineService] Starting")
	
	-- Auto-create splines from folders with naming pattern "spline_" followed by numbers only
	-- This excludes folders like "spline_1_visual"
	task.defer(function()
		for _, child in ipairs(Workspace:GetChildren()) do
			if child:IsA("Folder") and child.Name:match("^spline_%d+$") then
				self:CreateSplineFromFolder(child.Name)
			end
		end
		
		-- Create ride seat for the configured spline
		if splines[CONFIG.RideSplineName] then
			self:CreateRideSeat(CONFIG.RideSplineName)
			
			-- Set up player spawn handling
			self:SetupPlayerSpawnHandler()
		else
			warn("[SplineService] Ride spline not found:", CONFIG.RideSplineName)
		end
	end)
	
	print("[SplineService] Ready")
end

return SplineService

