--[[
	TramService
	
	Manages the tram shuttle system that transports players between
	the start and end shipping centers. Costs kudos to ride.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Spline module for smooth path interpolation
local CatmullRomPath = require(CustomPackages:WaitForChild("Splines"):WaitForChild("CatmullRomPath"))

local TramService = Knit.CreateService {
	Name = "TramService",
	Client = {},
	
	-- Tram state
	_tramFolder = nil,
	_tramModel = nil,
	_tramSpline = nil,        -- Catmull-Rom spline for smooth movement
	_tramT = 0,               -- Current position on spline (0-1)
	_tramDirection = 1,       -- 1 = forward, -1 = backward
	_tramRunning = false,
	_tramAtStation = true,
	_tramStationTimer = 0,
	_tramPassengers = {},
	_tramStations = {},
	_rideInProgress = false,  -- Is the tram currently moving with a passenger
	_currentRider = nil,      -- The player currently riding
	_riderConnections = {},   -- Connections for handling rider events
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Master enable/disable
	Enabled = true,
	
	-- Pricing
	Cost = 25,                                   -- Kudos cost to ride
	
	-- Movement
	Speed = 80,                                  -- Studs per second
	PauseAtStations = 5,                         -- Seconds to wait at each station
	
	-- Spline settings
	SplineControlPoints = 50,                    -- Number of control points for spline
	SplineTension = 0.5,                         -- Catmull-Rom tension (0.5 = standard)
	
	-- Capacity
	MaxPassengers = 1,                           -- Single seat roller coaster car
	
	-- Tram seat visual settings
	Size = Vector3.new(4, 1, 4),                 -- Simple seat size
	BodyColor = Color3.fromRGB(200, 50, 50),     -- Bold red seat
	AccentColor = Color3.fromRGB(255, 200, 0),   -- Safety yellow
	Material = Enum.Material.SmoothPlastic,
	
	-- Path offset (parallel to main track)
	TrackOffset = 15,                            -- Horizontal offset from main track
	HeightOffset = 12,                           -- Vertical offset above main track
	
	-- Station settings
	StationSize = Vector3.new(15, 3, 20),        -- Smaller station for single car
	StationColor = Color3.fromRGB(70, 75, 80),
	
	-- Track settings
	TrackEnabled = true,
	TrackSegments = 100,                         -- Number of track segments
	TrackWidth = 0.5,                            -- Width of each rail
	TrackGauge = 3,                              -- Distance between rails
	TrackColor = Color3.fromRGB(60, 65, 70),     -- Dark metal color
	TrackSupportInterval = 10,                   -- Support beam every N segments
	TrackSupportColor = Color3.fromRGB(80, 85, 90),
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         TRAM MODEL CREATION                                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TramService:CreateTramModel()
	local tramFolder = Instance.new("Model")
	tramFolder.Name = "TramCar"
	
	-- Just a simple seat
	local seat = Instance.new("Seat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(4, 1, 4)
	seat.Color = CONFIG.BodyColor
	seat.Material = Enum.Material.SmoothPlastic
	seat.Anchored = true
	seat.Disabled = true  -- Prevent players from sitting without paying
	seat.Parent = tramFolder
	
	tramFolder.PrimaryPart = seat
	
	return tramFolder
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         TRACK CREATION                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TramService:CreateTrack(spline, parentFolder)
	if not CONFIG.TrackEnabled then return end
	
	local trackFolder = Instance.new("Model")
	trackFolder.Name = "TramTrack"
	
	local numSegments = CONFIG.TrackSegments
	local railWidth = CONFIG.TrackWidth
	local gauge = CONFIG.TrackGauge / 2  -- Half gauge for each side
	
	-- Create track segments along the spline
	for i = 0, numSegments - 1 do
		local t0 = i / numSegments
		local t1 = (i + 1) / numSegments
		
		-- Get positions along spline
		local pos0 = spline:Position(spline:TransformRelativeToLength(t0))
		local pos1 = spline:Position(spline:TransformRelativeToLength(t1))
		
		-- Calculate segment properties
		local segmentCenter = (pos0 + pos1) / 2
		local segmentDir = (pos1 - pos0)
		local segmentLength = segmentDir.Magnitude
		
		if segmentLength < 0.1 then continue end
		
		segmentDir = segmentDir.Unit
		
		-- Get perpendicular (right) direction for rail offset
		local right = segmentDir:Cross(Vector3.new(0, 1, 0))
		if right.Magnitude < 0.1 then
			right = segmentDir:Cross(Vector3.new(0, 0, 1))
		end
		right = right.Unit
		
		-- Create left rail segment
		local leftRail = Instance.new("Part")
		leftRail.Name = "Rail_L_" .. i
		leftRail.Size = Vector3.new(railWidth, railWidth, segmentLength + 0.1)
		leftRail.CFrame = CFrame.lookAt(segmentCenter - right * gauge, segmentCenter - right * gauge + segmentDir)
		leftRail.Color = CONFIG.TrackColor
		leftRail.Material = Enum.Material.Metal
		leftRail.Anchored = true
		leftRail.CanCollide = false
		leftRail.CanQuery = false
		leftRail.CastShadow = false
		leftRail.Parent = trackFolder
		
		-- Create right rail segment
		local rightRail = Instance.new("Part")
		rightRail.Name = "Rail_R_" .. i
		rightRail.Size = Vector3.new(railWidth, railWidth, segmentLength + 0.1)
		rightRail.CFrame = CFrame.lookAt(segmentCenter + right * gauge, segmentCenter + right * gauge + segmentDir)
		rightRail.Color = CONFIG.TrackColor
		rightRail.Material = Enum.Material.Metal
		rightRail.Anchored = true
		rightRail.CanCollide = false
		rightRail.CanQuery = false
		rightRail.CastShadow = false
		rightRail.Parent = trackFolder
		
		-- Add cross ties / support beams at intervals
		if i % CONFIG.TrackSupportInterval == 0 then
			-- Cross tie (sleeper)
			local tie = Instance.new("Part")
			tie.Name = "Tie_" .. i
			tie.Size = Vector3.new(gauge * 2 + railWidth * 2, railWidth * 0.6, railWidth * 1.5)
			tie.CFrame = CFrame.lookAt(segmentCenter - Vector3.new(0, railWidth * 0.5, 0), segmentCenter - Vector3.new(0, railWidth * 0.5, 0) + segmentDir)
			tie.Color = CONFIG.TrackSupportColor
			tie.Material = Enum.Material.Wood
			tie.Anchored = true
			tie.CanCollide = false
			tie.CanQuery = false
			tie.CastShadow = false
			tie.Parent = trackFolder
			
			-- Support beam underneath (for elevated sections)
			local support = Instance.new("Part")
			support.Name = "Support_" .. i
			support.Size = Vector3.new(0.8, 8, 0.8)
			support.CFrame = CFrame.new(segmentCenter - Vector3.new(0, 4 + railWidth, 0))
			support.Color = CONFIG.TrackSupportColor
			support.Material = Enum.Material.Metal
			support.Anchored = true
			support.CanCollide = false
			support.CanQuery = false
			support.CastShadow = false
			support.Parent = trackFolder
		end
	end
	
	trackFolder.Parent = parentFolder
	print(string.format("[TramService] Created track with %d segments", numSegments))
	
	return trackFolder
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STATION CREATION                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TramService:CreateStation(position, facingDirection, isStart)
	local stationFolder = Instance.new("Model")
	stationFolder.Name = isStart and "TramStation_Start" or "TramStation_End"
	
	local size = CONFIG.StationSize
	
	-- ═══════════════════════════════════════════════════════════════════════════
	-- PLATFORM (simple elevated platform inside the building)
	-- ═══════════════════════════════════════════════════════════════════════════
	
	local platform = Instance.new("Part")
	platform.Name = "Platform"
	platform.Size = size
	platform.Position = position
	platform.Color = CONFIG.StationColor
	platform.Material = Enum.Material.Concrete
	platform.Anchored = true
	platform.CanCollide = true
	platform.Parent = stationFolder
	
	stationFolder.PrimaryPart = platform
	
	-- Yellow safety line along track edge
	local safetyLine = Instance.new("Part")
	safetyLine.Name = "SafetyLine"
	safetyLine.Size = Vector3.new(2, 0.2, size.Z)
	safetyLine.Position = position + Vector3.new(size.X / 2 - 1, size.Y / 2 + 0.1, 0)
	safetyLine.Color = CONFIG.AccentColor
	safetyLine.Material = Enum.Material.Neon
	safetyLine.Anchored = true
	safetyLine.CanCollide = false
	safetyLine.Parent = stationFolder
	
	-- ═══════════════════════════════════════════════════════════════════════════
	-- SAFETY RAILINGS (around the platform edges except track side)
	-- ═══════════════════════════════════════════════════════════════════════════
	
	local railHeight = 3.5
	local railColor = Color3.fromRGB(255, 200, 0)  -- Yellow safety rails
	
	-- Back railing (-X side)
	local backRail = Instance.new("Part")
	backRail.Name = "BackRailing"
	backRail.Size = Vector3.new(0.2, railHeight, size.Z)
	backRail.Position = position + Vector3.new(-size.X / 2 + 0.1, size.Y / 2 + railHeight / 2, 0)
	backRail.Color = railColor
	backRail.Material = Enum.Material.Metal
	backRail.Anchored = true
	backRail.CanCollide = true
	backRail.Parent = stationFolder
	
	-- Side railings (Z sides)
	for side = -1, 1, 2 do
		local sideRail = Instance.new("Part")
		sideRail.Name = "SideRailing_" .. side
		sideRail.Size = Vector3.new(size.X - 4, railHeight, 0.2)  -- Leave gap at track side
		sideRail.Position = position + Vector3.new(-2, size.Y / 2 + railHeight / 2, side * (size.Z / 2 - 0.1))
		sideRail.Color = railColor
		sideRail.Material = Enum.Material.Metal
		sideRail.Anchored = true
		sideRail.CanCollide = true
		sideRail.Parent = stationFolder
	end
	
	-- ═══════════════════════════════════════════════════════════════════════════
	-- INTEGRATED STAIRS (built into the platform)
	-- ═══════════════════════════════════════════════════════════════════════════
	
	local platformTopY = position.Y + size.Y / 2
	local groundLevel = 0
	local totalHeight = platformTopY - groundLevel
	
	local stepHeight = 0.5
	local stepDepth = 1.0
	local stairWidth = 6
	local numSteps = math.ceil(totalHeight / stepHeight)
	
	-- Stairs at the back of the platform, going down in -X direction
	local stairStartX = position.X - size.X / 2
	local stairZ = position.Z
	
	-- Solid stair base (fills underneath the steps)
	local stairBase = Instance.new("WedgePart")
	stairBase.Name = "StairBase"
	stairBase.Size = Vector3.new(stairWidth, totalHeight, numSteps * stepDepth)
	stairBase.CFrame = CFrame.new(
		stairStartX - numSteps * stepDepth / 2,
		groundLevel + totalHeight / 2,
		stairZ
	) * CFrame.Angles(0, math.rad(-90), 0)
	stairBase.Color = CONFIG.StationColor
	stairBase.Material = Enum.Material.Concrete
	stairBase.Anchored = true
	stairBase.CanCollide = true
	stairBase.Parent = stationFolder
	
	-- Individual step treads on top
	for i = 0, numSteps - 1 do
		local stepY = groundLevel + i * stepHeight + stepHeight / 2
		local stepX = stairStartX - (numSteps - i - 0.5) * stepDepth
		
		local step = Instance.new("Part")
		step.Name = "Step_" .. i
		step.Size = Vector3.new(stepDepth + 0.1, 0.15, stairWidth)
		step.Position = Vector3.new(stepX, stepY + stepHeight / 2, stairZ)
		step.Color = Color3.fromRGB(80, 85, 90)
		step.Material = Enum.Material.Concrete
		step.Anchored = true
		step.CanCollide = true
		step.Parent = stationFolder
		
		-- Yellow safety edge on each step
		local stepEdge = Instance.new("Part")
		stepEdge.Name = "StepEdge_" .. i
		stepEdge.Size = Vector3.new(0.1, 0.18, stairWidth - 0.2)
		stepEdge.Position = Vector3.new(stepX + stepDepth / 2, stepY + stepHeight / 2 + 0.02, stairZ)
		stepEdge.Color = CONFIG.AccentColor
		stepEdge.Material = Enum.Material.Neon
		stepEdge.Anchored = true
		stepEdge.CanCollide = false
		stepEdge.Parent = stationFolder
	end
	
	-- Stair handrails
	for side = -1, 1, 2 do
		local railZ = stairZ + side * (stairWidth / 2 + 0.15)
		
		-- Posts
		for i = 0, numSteps, math.floor(numSteps / 3) do
			local postY = groundLevel + i * stepHeight
			local postX = stairStartX - (numSteps - i) * stepDepth
			
			local post = Instance.new("Part")
			post.Name = "StairPost_" .. side .. "_" .. i
			post.Size = Vector3.new(0.15, 3.5, 0.15)
			post.Position = Vector3.new(postX, postY + 1.75, railZ)
			post.Color = railColor
			post.Material = Enum.Material.Metal
			post.Anchored = true
			post.CanCollide = true
			post.Parent = stationFolder
		end
		
		-- Angled top rail
		local railStartX = stairStartX - numSteps * stepDepth
		local railEndX = stairStartX
		local railStartY = groundLevel + 3.5
		local railEndY = platformTopY + 3.5
		
		local railLength = math.sqrt((railEndX - railStartX)^2 + (railEndY - railStartY)^2)
		local railAngle = math.atan2(railEndY - railStartY, railEndX - railStartX)
		
		local handrail = Instance.new("Part")
		handrail.Name = "StairHandrail_" .. side
		handrail.Size = Vector3.new(railLength, 0.12, 0.12)
		handrail.CFrame = CFrame.new(
			(railStartX + railEndX) / 2,
			(railStartY + railEndY) / 2,
			railZ
		) * CFrame.Angles(0, 0, railAngle)
		handrail.Color = railColor
		handrail.Material = Enum.Material.Metal
		handrail.Anchored = true
		handrail.CanCollide = true
		handrail.Parent = stationFolder
	end
	
	-- ═══════════════════════════════════════════════════════════════════════════
	-- BOARDING ZONE AND PROMPT
	-- ═══════════════════════════════════════════════════════════════════════════
	
	local boardingZone = Instance.new("Part")
	boardingZone.Name = "BoardingZone"
	boardingZone.Size = Vector3.new(size.X, 8, size.Z)
	boardingZone.Position = position + Vector3.new(0, 4, 0)
	boardingZone.Transparency = 1
	boardingZone.CanCollide = false
	boardingZone.Anchored = true
	boardingZone.Parent = stationFolder
	
	local boardPrompt = Instance.new("ProximityPrompt")
	boardPrompt.Name = "BoardTramPrompt"
	boardPrompt.ActionText = "Board Tram"
	boardPrompt.ObjectText = "⭐ " .. CONFIG.Cost .. " Kudos"
	boardPrompt.HoldDuration = 0.5
	boardPrompt.MaxActivationDistance = 12
	boardPrompt.Parent = boardingZone
	
	return stationFolder, boardPrompt
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SPLINE GENERATION                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TramService:GenerateSplineFromPath(sourcePath)
	if not sourcePath or #sourcePath < 10 then
		warn("[TramService] No valid source path for tram!")
		return nil
	end
	
	local offset = CONFIG.TrackOffset
	local heightOffset = CONFIG.HeightOffset
	
	-- Get start and end points from source path
	local startPoint = sourcePath[1]
	local endPoint = sourcePath[#sourcePath]
	
	-- Get tangent direction at start for offset calculation
	local startTangent = (sourcePath[2] - sourcePath[1]).Unit
	local startRight = startTangent:Cross(Vector3.new(0, 1, 0)).Unit
	
	-- Get tangent direction at end for offset calculation  
	local endTangent = (sourcePath[#sourcePath] - sourcePath[#sourcePath - 1]).Unit
	local endRight = endTangent:Cross(Vector3.new(0, 1, 0)).Unit
	
	-- Calculate offset start and end positions
	local offsetStart = startPoint + startRight * offset + Vector3.new(0, heightOffset, 0)
	local offsetEnd = endPoint + endRight * offset + Vector3.new(0, heightOffset, 0)
	
	-- Create a STRAIGHT path with evenly spaced points
	-- Catmull-Rom needs at least 4 points, so we create intermediate points
	local splinePoints = {}
	local numPoints = math.max(4, CONFIG.SplineControlPoints)
	
	for i = 0, numPoints - 1 do
		local t = i / (numPoints - 1)
		local point = offsetStart:Lerp(offsetEnd, t)
		table.insert(splinePoints, point)
	end
	
	-- Create the Catmull-Rom spline from points (will be straight since points are linear)
	local spline = CatmullRomPath.fromPoints(splinePoints, CONFIG.SplineTension)
	
	local pathLength = (offsetEnd - offsetStart).Magnitude
	print(string.format("[TramService] Created STRAIGHT track path, length: %.1f studs", pathLength))
	
	return spline, splinePoints
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MAIN SYSTEM                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TramService:Initialize(trackPath, parentFolder)
	if not CONFIG.Enabled then 
		print("[TramService] Tram system disabled in config")
		return false
	end
	
	if not trackPath or #trackPath < 10 then
		warn("[TramService] Cannot initialize tram - no valid track path!")
		return false
	end
	
	-- Generate spline from the track path
	local spline, splinePoints = self:GenerateSplineFromPath(trackPath)
	if not spline then return false end
	
	self._tramSpline = spline
	
	-- Create tram folder
	self._tramFolder = Instance.new("Folder")
	self._tramFolder.Name = "TramSystem"
	self._tramFolder.Parent = parentFolder or Workspace
	
	-- Create the track along the spline
	self:CreateTrack(spline, self._tramFolder)
	
	-- Get start and end positions from spline
	-- Station is offset to the side of the track so tram can stop next to it
	local stationSideOffset = CONFIG.StationSize.X / 2 + CONFIG.Size.X / 2 + 2  -- Gap between station and tram
	
	local startSplinePos = spline:Position(0)
	local startTangent = spline:Velocity(0).Unit
	local startRight = startTangent:Cross(Vector3.new(0, 1, 0)).Unit
	local startPos = startSplinePos + startRight * stationSideOffset + Vector3.new(0, CONFIG.StationSize.Y / 2, 0)
	local startStation, startPrompt = self:CreateStation(startPos, startTangent, true)
	startStation.Parent = self._tramFolder
	self._tramStations.start = startStation
	
	local endSplinePos = spline:Position(1)
	local endTangent = spline:Velocity(1).Unit
	local endRight = endTangent:Cross(Vector3.new(0, 1, 0)).Unit
	local endPos = endSplinePos + endRight * stationSideOffset + Vector3.new(0, CONFIG.StationSize.Y / 2, 0)
	local endStation, endPrompt = self:CreateStation(endPos, endTangent, false)
	endStation.Parent = self._tramFolder
	self._tramStations["end"] = endStation
	
	-- Create tram
	local tram = self:CreateTramModel()
	tram.Parent = self._tramFolder
	self._tramModel = tram
	
	-- Position tram at start of spline (on the track, next to the station)
	local tramStartPos = spline:Position(0)
	local tramStartDir = spline:Velocity(0).Unit
	tram:PivotTo(CFrame.new(tramStartPos + Vector3.new(0, CONFIG.Size.Y / 2, 0)) * 
		CFrame.lookAt(Vector3.zero, tramStartDir).Rotation)
	
	-- Initialize spline movement state
	self._tramT = 0
	self._tramDirection = 1
	self._tramRunning = true
	self._tramAtStation = true
	self._tramStationTimer = 0
	
	-- Helper function to clean up rider connections
	local function cleanupRiderConnections()
		for _, connection in pairs(self._riderConnections) do
			if connection and connection.Connected then
				connection:Disconnect()
			end
		end
		self._riderConnections = {}
	end
	
	-- Helper function to safely eject the rider
	local function ejectRider()
		local seat = tram:FindFirstChild("Seat")
		if seat then
			if seat.Occupant then
				local humanoid = seat.Occupant
				-- Restore jump power before ejecting
				humanoid.JumpPower = 50
				humanoid.JumpHeight = 7.2
				humanoid.Sit = false
			end
			-- Disable the seat after ejecting so others can't randomly sit
			seat.Disabled = true
		end
		cleanupRiderConnections()
		self._currentRider = nil
		self._rideInProgress = false
		self._tramPassengers = {}
	end
	
	-- Setup boarding prompts
	local function handleBoarding(player, isStartStation)
		-- Check if ride is already in progress
		if self._rideInProgress then
			print("[TramService] Ride already in progress")
			return
		end
		
		-- Check if tram is at the correct station for boarding
		local atStartStation = self._tramT <= 0.01
		local atEndStation = self._tramT >= 0.99
		if isStartStation and not atStartStation then
			print("[TramService] Tram not at start station")
			return
		end
		if not isStartStation and not atEndStation then
			print("[TramService] Tram not at end station")
			return
		end
		
		-- Check if tram is at station
		if not self._tramAtStation then
			print("[TramService] Tram not at station")
			return
		end
		
		-- Check if player can afford
		local HubService = Knit.GetService("HubService")
		local playerKudos = HubService:GetPlayerKudos(player)
		if playerKudos < CONFIG.Cost then
			print(string.format("[TramService] %s cannot afford tram (has %d, needs %d)", 
				player.Name, playerKudos, CONFIG.Cost))
			return
		end
		
		-- Check if player has a valid character
		local character = player.Character
		if not character then
			print("[TramService] Player has no character")
			return
		end
		
		local humanoid = character:FindFirstChild("Humanoid")
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp then
			print("[TramService] Player missing humanoid or HumanoidRootPart")
			return
		end
		
		-- Check if player is alive
		if humanoid.Health <= 0 then
			print("[TramService] Player is dead")
			return
		end
		
		-- Get seat
		local seat = tram:FindFirstChild("Seat")
		if not seat then
			warn("[TramService] Seat not found!")
			return
		end
		
		-- Check if seat is already occupied
		if seat.Occupant then
			print("[TramService] Seat already occupied")
			return
		end
		
		-- Charge kudos
		if not HubService:SpendKudos(player, CONFIG.Cost) then
			print("[TramService] Failed to charge kudos")
			return
		end
		
			print(string.format("[TramService] %s boarded tram for %d kudos", player.Name, CONFIG.Cost))
			
		-- Disable jumping to prevent escape
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		
		-- Enable seat FIRST so auto-sit works when player lands on it
		seat.Disabled = false
		
		-- Teleport player onto the seat
		local seatCFrame = seat.CFrame
		hrp.CFrame = seatCFrame + Vector3.new(0, 3, 0)  -- Position above seat
		
		-- Small wait for teleport and physics
		task.wait(0.1)
		
		-- Force sit if auto-sit didn't trigger
		if not humanoid.Sit then
			seat:Sit(humanoid)
		end
		
		-- Wait for the player to actually be seated
		local seatedTimeout = 0
		while not humanoid.Sit and seatedTimeout < 1 do
			task.wait(0.05)
			seatedTimeout = seatedTimeout + 0.05
			-- Keep trying to sit them
			if not humanoid.Sit then
				seat:Sit(humanoid)
			end
		end
		
		-- Check if player is actually seated
		if not humanoid.Sit or seat.Occupant ~= humanoid then
			-- Failed to seat player - refund and abort
			print("[TramService] Failed to seat player - refunding")
			humanoid.JumpPower = 50
			humanoid.JumpHeight = 7.2
			seat.Disabled = true
			local HubService = Knit.GetService("HubService")
			HubService:AwardKudos(player, CONFIG.Cost)  -- Refund
			return
		end
		
		-- Keep seat enabled while occupied (disabled seats can cause issues)
		-- We prevent other players via the _rideInProgress flag instead
		
		-- Mark ride as in progress ONLY after confirmed seated
		self._currentRider = player
		self._rideInProgress = true
		self._tramPassengers = {player}
		
		print(string.format("[TramService] %s is now seated and ready to depart", player.Name))
		
		-- Clean up any existing connections
		cleanupRiderConnections()
		
		-- Handle player leaving the game
		self._riderConnections.leaving = player.AncestryChanged:Connect(function(_, parent)
			if not parent then
				print("[TramService] Rider left the game")
				ejectRider()
			end
		end)
		
		-- Handle player dying
		self._riderConnections.died = humanoid.Died:Connect(function()
			print("[TramService] Rider died")
			ejectRider()
		end)
		
		-- Handle player somehow getting out of seat (force them back in while moving)
		self._riderConnections.seated = humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
			if not humanoid.Sit and self._rideInProgress and not self._tramAtStation then
				-- Player tried to get out while moving - teleport them back and reseat
				task.defer(function()
					if self._rideInProgress and not self._tramAtStation and humanoid and humanoid.Health > 0 then
						local hrpCheck = character:FindFirstChild("HumanoidRootPart")
						if hrpCheck then
							-- Teleport back onto seat
							seat.Disabled = false
							hrpCheck.CFrame = seat.CFrame + Vector3.new(0, 3, 0)
							task.wait(0.05)
							seat:Sit(humanoid)
							humanoid.JumpPower = 0
							humanoid.JumpHeight = 0
						end
					end
				end)
			end
		end)
		
		-- Handle character respawning
		self._riderConnections.characterRemoving = player.CharacterRemoving:Connect(function()
			print("[TramService] Rider's character is being removed")
			ejectRider()
		end)
	end
	
	-- Store ejectRider function for use in movement loop
	self._ejectRider = ejectRider
	
	startPrompt.Triggered:Connect(function(player)
		handleBoarding(player, true)
	end)
	
	endPrompt.Triggered:Connect(function(player)
		handleBoarding(player, false)
	end)
	
	-- Start tram movement loop
	self:StartMovementLoop()
	
	print("[TramService] Tram system initialized with smooth spline movement!")
	return true
end

function TramService:StartMovementLoop()
	local tramBody = self._tramModel.PrimaryPart
	local spline = self._tramSpline
	local splineLength = spline.Length
	
	-- Calculate delta-t per frame based on speed and spline length
	-- t goes from 0 to 1, so speed/length gives us the rate of change
	local deltaT = CONFIG.Speed / splineLength
	
	task.spawn(function()
		while self._tramRunning do
			-- Check if there's a passenger - must have ride in progress AND seat occupied
			local seat = self._tramModel:FindFirstChild("Seat")
			local seatOccupied = seat and seat.Occupant ~= nil
			local hasPassenger = self._rideInProgress and self._currentRider ~= nil and seatOccupied
			
			if self._tramAtStation then
				-- Waiting at station - only depart if there's a confirmed seated passenger
				if hasPassenger then
					self._tramAtStation = false
					print("[TramService] Coaster departing with seated passenger...")
				elseif self._rideInProgress and not seatOccupied then
					-- Ride was marked in progress but player isn't seated - reset
					print("[TramService] Passenger not seated - resetting ride state")
					if self._ejectRider then
						self._ejectRider()
					end
				end
			else
				-- Moving along spline
				local dt = deltaT * 0.03 * self._tramDirection  -- Frame time adjustment
				self._tramT = self._tramT + dt
				
				-- Check if reached end of spline
				if self._tramT >= 1 then
					self._tramT = 1
					self._tramDirection = -1
					self._tramAtStation = true
					print("[TramService] Coaster arrived at end station")
					-- Eject passenger using the proper cleanup function
					if self._ejectRider then
						self._ejectRider()
					end
				elseif self._tramT <= 0 then
					self._tramT = 0
					self._tramDirection = 1
					self._tramAtStation = true
					print("[TramService] Coaster arrived at start station")
					-- Eject passenger using the proper cleanup function
					if self._ejectRider then
						self._ejectRider()
					end
				else
					-- Transform t to get constant-speed movement along spline
					local tTransformed = spline:TransformRelativeToLength(self._tramT)
					
					-- Get position and direction from spline
					local position = spline:Position(tTransformed)
					local velocity = spline:Velocity(tTransformed)
					
					-- Handle direction for look-at (reverse velocity when going backwards)
					local lookDir = self._tramDirection == 1 and velocity or -velocity
							
							if lookDir.Magnitude > 0.1 then
						local newCFrame = CFrame.new(position + Vector3.new(0, CONFIG.Size.Y / 2, 0)) * 
							CFrame.lookAt(Vector3.zero, lookDir.Unit).Rotation
						self._tramModel:PivotTo(newCFrame)
					end
				end
			end
			
			task.wait(0.03)
		end
	end)
end

function TramService:Stop()
	self._tramRunning = false
	
	-- Eject any current rider
	if self._ejectRider then
		self._ejectRider()
	end
	
	-- Clean up rider connections
	for _, connection in pairs(self._riderConnections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	self._riderConnections = {}
	
	-- Clean up tram system folder
	if self._tramFolder then
		self._tramFolder:Destroy()
		self._tramFolder = nil
	end
	
	self._tramModel = nil
	self._tramSpline = nil
	self._tramStations = {}
	self._tramPassengers = {}
	self._currentRider = nil
	self._rideInProgress = false
	self._ejectRider = nil
	
	print("[TramService] Tram system stopped")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TramService:GetConfig()
	return CONFIG
end

function TramService:SetCost(cost)
	CONFIG.Cost = cost
end

function TramService:IsRunning()
	return self._tramRunning
end

function TramService:GetPassengers()
	return self._tramPassengers
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function TramService:KnitInit()
	print("[TramService] Initializing...")
end

function TramService:KnitStart()
	print("[TramService] Started (waiting for HubService to call Initialize)")
end

return TramService

