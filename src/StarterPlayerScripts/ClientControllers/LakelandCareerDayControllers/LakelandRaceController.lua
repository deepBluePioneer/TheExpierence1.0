local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Signal = require(Packages.Signal)
local Input = require(Packages.Input)

local CustomPackages = ReplicatedStorage.CustomPackages
local CatmullRomSpline = require(CustomPackages.Splines.CatmullRomSpline)

local LANE_COUNT = 3
local LANE_SPACING = 10
local TRACK_LENGTH = 10000
local TRACK_HEIGHT = 3
local TRACK_START_Z = 50
local SPLINE_TENSION = 0.5

local CURVE_SEGMENTS = 40
local CURVE_AMPLITUDE = 70

local ELEVATION_PROFILE = {
	{ 0.00,   3 },   -- start flat
	{ 0.06,   3 },   -- flat run-up
	{ 0.10,  30 },   -- steep climb
	{ 0.14,  35 },   -- crest
	{ 0.17,   5 },   -- steep drop-off
	{ 0.22,   3 },   -- valley floor
	{ 0.28,   3 },   -- flat stretch
	{ 0.32,  20 },   -- moderate climb
	{ 0.36,  22 },   -- gentle ridge
	{ 0.39,  10 },   -- moderate descent
	{ 0.42,   3 },   -- valley
	{ 0.46,   3 },   -- flat
	{ 0.50,  50 },   -- big steep climb
	{ 0.54,  55 },   -- tall crest
	{ 0.56,   8 },   -- sharp cliff drop
	{ 0.60,   3 },   -- valley floor
	{ 0.65,   3 },   -- flat stretch
	{ 0.68,  15 },   -- rolling hill up
	{ 0.71,  18 },   -- small crest
	{ 0.73,   5 },   -- dip down
	{ 0.76,  25 },   -- quick climb
	{ 0.78,  28 },   -- crest
	{ 0.80,   3 },   -- steep drop
	{ 0.85,   3 },   -- flat approach
	{ 0.88,  40 },   -- final steep ramp
	{ 0.91,  45 },   -- high point
	{ 0.93,   5 },   -- big drop
	{ 0.96,   3 },   -- flat finish
	{ 1.00,   3 },   -- end flat
}

local MOVE_SPEED = 80
local BOOST_ACCEL = 120
local MAX_SPEED = 220
local LANE_SWITCH_SPEED = 8

local MAX_BANK_ANGLE = math.rad(12)
local BANK_SMOOTH_SPEED = 14
local LANE_SWITCH_BANK = math.rad(10)

local BOOST_LENGTH = 0.025
local BOOST_ZONES = {
	{ lane = 1, tStart = 0.08 },
	{ lane = 3, tStart = 0.15 },
	{ lane = 2, tStart = 0.22 },
	{ lane = 1, tStart = 0.32 },
	{ lane = 3, tStart = 0.38 },
	{ lane = 2, tStart = 0.48 },
	{ lane = 1, tStart = 0.55 },
	{ lane = 3, tStart = 0.62 },
	{ lane = 2, tStart = 0.70 },
	{ lane = 1, tStart = 0.78 },
	{ lane = 3, tStart = 0.85 },
	{ lane = 2, tStart = 0.92 },
}

local MAX_HEALTH = 100
local HAZARD_DAMAGE = 20
local HAZARD_HIT_COOLDOWN = 0.8
local HAZARD_SIZE = 0.001

local HAZARDS = {
	{ lane = 2, t = 0.05 },
	{ lane = 1, t = 0.11 },
	{ lane = 3, t = 0.11 },
	{ lane = 2, t = 0.18 },
	{ lane = 1, t = 0.25 },
	{ lane = 3, t = 0.30 },
	{ lane = 1, t = 0.35 },
	{ lane = 2, t = 0.42 },
	{ lane = 3, t = 0.42 },
	{ lane = 1, t = 0.50 },
	{ lane = 2, t = 0.57 },
	{ lane = 3, t = 0.57 },
	{ lane = 1, t = 0.64 },
	{ lane = 2, t = 0.64 },
	{ lane = 3, t = 0.72 },
	{ lane = 1, t = 0.76 },
	{ lane = 2, t = 0.82 },
	{ lane = 3, t = 0.82 },
	{ lane = 1, t = 0.88 },
	{ lane = 2, t = 0.94 },
}

local LakelandRaceController = Knit.CreateController({
	Name = "LakelandRaceController",

	_trove = nil,
	_splines = {},
	_currentLane = 2,
	_targetLane = 2,
	_laneBlend = 0,
	_t = 0,
	_currentSpeed = MOVE_SPEED,
	_running = false,
	_boosting = false,
	_renderConn = nil,
	_inputTrove = nil,
	_currentRoll = 0,
	_lastXPos = 0,
	_switchDir = 0,
	_health = MAX_HEALTH,
	_hitCooldown = 0,

	LaneChanged = Signal.new(),
	RaceProgress = Signal.new(),
	BoostChanged = Signal.new(),
	SpeedChanged = Signal.new(),
	HealthChanged = Signal.new(),
	HazardHit = Signal.new(),
})

function LakelandRaceController:KnitInit()
	self._trove = Trove.new()
	self._inputTrove = Trove.new()
	self._trove:Add(self._inputTrove)
end

function LakelandRaceController:KnitStart()
	self:_buildSplines()

	local gameController = Knit.GetController("LakelandGameController")
	gameController.GameStateChanged:Connect(function(newState)
		if newState == "COUNTDOWN" then
			self:PositionAtStart()
		elseif newState == "PLAYING" then
			self:StartRace()
		elseif newState == "MENU" then
			self:StopRace()
		end
	end)
end

function LakelandRaceController:_buildSplines()
	self._splines = {}

	local laneOffsets = {}
	for i = 1, LANE_COUNT do
		local offset = (i - math.ceil(LANE_COUNT / 2)) * LANE_SPACING
		table.insert(laneOffsets, offset)
	end

	local function sampleElevation(frac)
		local profile = ELEVATION_PROFILE
		if frac <= profile[1][1] then return profile[1][2] end
		if frac >= profile[#profile][1] then return profile[#profile][2] end

		for k = 1, #profile - 1 do
			if frac >= profile[k][1] and frac <= profile[k + 1][1] then
				local t = (frac - profile[k][1]) / (profile[k + 1][1] - profile[k][1])
				t = t * t * (3 - 2 * t)
				return profile[k][2] + (profile[k + 1][2] - profile[k][2]) * t
			end
		end
		return TRACK_HEIGHT
	end

	local centerPoints = {}
	local segmentLen = TRACK_LENGTH / CURVE_SEGMENTS
	for i = 0, CURVE_SEGMENTS do
		local frac = i / CURVE_SEGMENTS
		local z = TRACK_START_Z - i * segmentLen
		local x = math.sin(i * math.pi / 2.5) * CURVE_AMPLITUDE
		local y = sampleElevation(frac)
		table.insert(centerPoints, Vector3.new(x, y, z))
	end

	local buffer = segmentLen
	local firstDir = (centerPoints[2] - centerPoints[1]).Unit
	local lastDir = (centerPoints[#centerPoints] - centerPoints[#centerPoints - 1]).Unit
	table.insert(centerPoints, 1, centerPoints[1] + firstDir * -buffer)
	table.insert(centerPoints, centerPoints[#centerPoints] + lastDir * buffer)

	local function getTangent(pts, idx)
		local prev = pts[math.max(1, idx - 1)]
		local nxt = pts[math.min(#pts, idx + 1)]
		local dir = nxt - prev
		if dir.Magnitude < 0.001 then
			return Vector3.new(0, 0, -1)
		end
		return dir.Unit
	end

	local function getPerp(tangent)
		local flat = Vector3.new(tangent.X, 0, tangent.Z)
		if flat.Magnitude < 0.001 then
			return Vector3.new(1, 0, 0)
		end
		flat = flat.Unit
		return Vector3.new(-flat.Z, 0, flat.X)
	end

	for laneIndex, laneOffset in ipairs(laneOffsets) do
		local lanePoints = {}
		for j, center in ipairs(centerPoints) do
			local tangent = getTangent(centerPoints, j)
			local perp = getPerp(tangent)
			table.insert(lanePoints, center + perp * laneOffset)
		end

		local spline = CatmullRomSpline.new(lanePoints, SPLINE_TENSION)
		self._splines[laneIndex] = {
			spline = spline,
			offsetX = laneOffset,
		}
	end

	print("[LakelandRaceController] Built " .. #self._splines .. " lane splines with " .. (CURVE_SEGMENTS + 3) .. " control points each")

	self:_visualizeLanes()
end

function LakelandRaceController:_visualizeLanes()
	local existingVis = Workspace:FindFirstChild("LaneVisualization")
	if existingVis then existingVis:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "LaneVisualization"
	folder.Parent = Workspace
	self._trove:Add(folder)

	local SEGMENTS = 500
	local LANE_COLORS = {
		Color3.fromRGB(255, 80, 80),
		Color3.fromRGB(80, 200, 80),
		Color3.fromRGB(80, 120, 255),
	}

	for laneIndex, laneData in ipairs(self._splines) do
		local spline = laneData.spline
		local color = LANE_COLORS[laneIndex] or Color3.fromRGB(255, 255, 255)

		for s = 0, SEGMENTS - 1 do
			local t0 = s / SEGMENTS
			local t1 = (s + 1) / SEGMENTS

			local posA = spline:CalculatePositionAt(t0)
			local posB = spline:CalculatePositionAt(t1)

			local mid = (posA + posB) / 2
			local dir = posB - posA
			local length = dir.Magnitude

			local part = Instance.new("Part")
			part.Name = "Lane" .. laneIndex .. "_Seg" .. s
			part.Size = Vector3.new(0.4, 0.2, length)
			part.CFrame = CFrame.lookAt(mid, posB)
			part.Anchored = true
			part.CanCollide = false
			part.Color = color
			part.Material = Enum.Material.Neon
			part.Transparency = 0.3
			part.Parent = folder
		end

		local startPos = spline:CalculatePositionAt(0)
		local endPos = spline:CalculatePositionAt(1)

		local startMarker = Instance.new("Part")
		startMarker.Name = "Lane" .. laneIndex .. "_Start"
		startMarker.Size = Vector3.new(LANE_SPACING * 0.8, 0.3, 0.3)
		startMarker.Position = startPos
		startMarker.Anchored = true
		startMarker.CanCollide = false
		startMarker.Color = Color3.fromRGB(255, 255, 255)
		startMarker.Material = Enum.Material.Neon
		startMarker.Parent = folder

		local endMarker = Instance.new("Part")
		endMarker.Name = "Lane" .. laneIndex .. "_End"
		endMarker.Size = Vector3.new(LANE_SPACING * 0.8, 0.3, 0.3)
		endMarker.Position = endPos
		endMarker.Anchored = true
		endMarker.CanCollide = false
		endMarker.Color = Color3.fromRGB(255, 200, 50)
		endMarker.Material = Enum.Material.Neon
		endMarker.Parent = folder
	end

	local DASH_COUNT = 350

	for laneIndex = 1, LANE_COUNT - 1 do
		local splineA = self._splines[laneIndex].spline
		local splineB = self._splines[laneIndex + 1].spline

		for d = 0, DASH_COUNT - 1 do
			local t0 = d / DASH_COUNT
			local t1 = (d + 0.4) / DASH_COUNT

			local posA0 = splineA:CalculatePositionAt(t0)
			local posB0 = splineB:CalculatePositionAt(t0)
			local mid0 = (posA0 + posB0) / 2

			local posA1 = splineA:CalculatePositionAt(t1)
			local posB1 = splineB:CalculatePositionAt(t1)
			local mid1 = (posA1 + posB1) / 2

			local center = (mid0 + mid1) / 2
			local dir = mid1 - mid0
			local length = dir.Magnitude

			if length > 0.01 then
				local dash = Instance.new("Part")
				dash.Name = "Divider_" .. laneIndex .. "_" .. d
				dash.Size = Vector3.new(0.15, 0.15, length)
				dash.CFrame = CFrame.lookAt(center, mid1)
				dash.Anchored = true
				dash.CanCollide = false
				dash.Color = Color3.fromRGB(200, 200, 200)
				dash.Material = Enum.Material.Neon
				dash.Transparency = 0.5
				dash.Parent = folder
			end
		end
	end

	self:_visualizeBoostZones(folder)
	self:_visualizeHazards(folder)

	print("[LakelandRaceController] Lane visualization created")
end

function LakelandRaceController:_visualizeBoostZones(folder)
	local BOOST_SEGMENTS = 15
	local BOOST_COLOR = Color3.fromRGB(255, 200, 0)
	local BOOST_WIDTH = LANE_SPACING * 0.7

	for _, zone in ipairs(BOOST_ZONES) do
		local spline = self._splines[zone.lane].spline
		local tEnd = zone.tStart + BOOST_LENGTH

		for s = 0, BOOST_SEGMENTS - 1 do
			local t0 = zone.tStart + (tEnd - zone.tStart) * (s / BOOST_SEGMENTS)
			local t1 = zone.tStart + (tEnd - zone.tStart) * ((s + 1) / BOOST_SEGMENTS)

			local posA = spline:CalculatePositionAt(t0)
			local posB = spline:CalculatePositionAt(t1)

			local mid = (posA + posB) / 2
			local segLen = (posB - posA).Magnitude

			if segLen > 0.01 then
				local panel = Instance.new("Part")
				panel.Name = "Boost_L" .. zone.lane .. "_" .. s
				panel.Size = Vector3.new(BOOST_WIDTH, 0.3, segLen)
				panel.CFrame = CFrame.lookAt(mid, posB)
				panel.Anchored = true
				panel.CanCollide = false
				panel.Color = BOOST_COLOR
				panel.Material = Enum.Material.Neon
				panel.Transparency = 0.15
				panel.Parent = folder
			end
		end

		local arrowPos = spline:CalculatePositionAt(zone.tStart)
		local arrowDir = spline:CalculateDerivativeAt(zone.tStart)
		if arrowDir.Magnitude > 0.001 then
			local arrow = Instance.new("Part")
			arrow.Name = "BoostArrow_L" .. zone.lane
			arrow.Size = Vector3.new(2, 0.4, 4)
			arrow.CFrame = CFrame.lookAt(arrowPos + Vector3.new(0, 0.3, 0), arrowPos + arrowDir)
			arrow.Anchored = true
			arrow.CanCollide = false
			arrow.Color = Color3.fromRGB(255, 255, 100)
			arrow.Material = Enum.Material.Neon
			arrow.Shape = Enum.PartType.Cylinder
			arrow.Transparency = 0.1
			arrow.Parent = folder
		end
	end

	print("[LakelandRaceController] Visualized " .. #BOOST_ZONES .. " boost zones")
end

function LakelandRaceController:_visualizeHazards(folder)
	local BOX_SIZE = Vector3.new(4, 4, 4)
	local HAZARD_COLOR = Color3.fromRGB(200, 50, 50)
	local WARN_COLOR = Color3.fromRGB(255, 180, 0)

	for i, hazard in ipairs(HAZARDS) do
		local spline = self._splines[hazard.lane].spline
		local pos = spline:CalculatePositionAt(hazard.t)
		local dir = spline:CalculateDerivativeAt(hazard.t)
		if dir.Magnitude < 0.001 then
			dir = Vector3.new(0, 0, -1)
		end

		local box = Instance.new("Part")
		box.Name = "Hazard_" .. i
		box.Size = BOX_SIZE
		box.CFrame = CFrame.lookAt(pos + Vector3.new(0, BOX_SIZE.Y / 2, 0), pos + Vector3.new(0, BOX_SIZE.Y / 2, 0) + dir)
		box.Anchored = true
		box.CanCollide = false
		box.Color = HAZARD_COLOR
		box.Material = Enum.Material.SmoothPlastic
		box.Transparency = 0
		box.Parent = folder

		local stripe = Instance.new("Part")
		stripe.Name = "HazardStripe_" .. i
		stripe.Size = Vector3.new(BOX_SIZE.X + 0.1, 1, BOX_SIZE.Z + 0.1)
		stripe.CFrame = box.CFrame * CFrame.new(0, 0.5, 0)
		stripe.Anchored = true
		stripe.CanCollide = false
		stripe.Color = WARN_COLOR
		stripe.Material = Enum.Material.Neon
		stripe.Transparency = 0.1
		stripe.Parent = folder
	end

	print("[LakelandRaceController] Visualized " .. #HAZARDS .. " hazards")
end

function LakelandRaceController:PositionAtStart()
	self._currentLane = 2
	self._targetLane = 2
	self._laneBlend = 0
	self._t = 0
	self._currentSpeed = MOVE_SPEED
	self._boosting = false
	self._currentRoll = 0
	self._lastXPos = 0
	self._switchDir = 0
	self._health = MAX_HEALTH
	self._hitCooldown = 0

	task.spawn(function()
		local machine = Workspace:WaitForChild("ActiveMachine", 5)
		if not machine then
			warn("[LakelandRaceController] ActiveMachine not found for positioning")
			return
		end

		local spline = self._splines[2].spline
		local pos = spline:CalculatePositionAt(0)
		local dir = spline:CalculateDerivativeAt(0)
		if dir.Magnitude < 0.001 then
			dir = Vector3.new(0, 0, -1)
		end
		dir = dir.Unit

		machine:PivotTo(CFrame.lookAt(pos, pos + dir))
		print("[LakelandRaceController] Machine positioned at spline start")
	end)
end

function LakelandRaceController:StartRace()
	if self._running then return end
	self._running = true

	self:_bindInput()
	self:_startRenderLoop()

	print("[LakelandRaceController] Race started on lane " .. self._currentLane)
end

function LakelandRaceController:StopRace()
	if not self._running then return end
	self._running = false

	self._inputTrove:Clean()

	if self._renderConn then
		self._renderConn:Disconnect()
		self._renderConn = nil
	end

	print("[LakelandRaceController] Race stopped")
end

function LakelandRaceController:_bindInput()
	self._inputTrove:Clean()

	self._inputTrove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end

		if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			self:SwitchLane(-1)
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			self:SwitchLane(1)
		end
	end), "Disconnect")

	if UserInputService.GamepadEnabled then
		self._inputTrove:Add(UserInputService.InputChanged:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Thumbstick1 then
				local x = input.Position.X
				if x > 0.5 and self._targetLane < LANE_COUNT then
					self:SwitchLane(1)
				elseif x < -0.5 and self._targetLane > 1 then
					self:SwitchLane(-1)
				end
			end
		end), "Disconnect")
	end
end

function LakelandRaceController:SwitchLane(direction)
	local newLane = math.clamp(self._targetLane + direction, 1, LANE_COUNT)
	if newLane == self._targetLane then return end

	if self._laneBlend > 0 then
		self._currentLane = self._targetLane
	end

	self._laneBlend = 0
	self._targetLane = newLane
	self._switchDir = direction
	self.LaneChanged:Fire(self._targetLane)
end

function LakelandRaceController:_startRenderLoop()
	if self._renderConn then
		self._renderConn:Disconnect()
	end

	self._renderConn = RunService.RenderStepped:Connect(function(dt)
		if not self._running then return end
		self:_updateMovement(dt)
	end)

	self._trove:Add(function()
		if self._renderConn then
			self._renderConn:Disconnect()
			self._renderConn = nil
		end
	end)
end

function LakelandRaceController:_getEffectiveLane()
	if self._laneBlend < 0.5 then
		return self._currentLane
	end
	return self._targetLane
end

function LakelandRaceController:_isInBoostZone()
	local lane = self:_getEffectiveLane()
	for _, zone in ipairs(BOOST_ZONES) do
		if zone.lane == lane and self._t >= zone.tStart and self._t <= zone.tStart + BOOST_LENGTH then
			return true
		end
	end
	return false
end

function LakelandRaceController:_isInHazard()
	local lane = self:_getEffectiveLane()
	for _, hazard in ipairs(HAZARDS) do
		if hazard.lane == lane and self._t >= hazard.t and self._t <= hazard.t + HAZARD_SIZE then
			return true
		end
	end
	return false
end

function LakelandRaceController:_updateMovement(dt)
	local machine = Workspace:FindFirstChild("ActiveMachine")
	if not machine or not machine.PrimaryPart then return end

	if self._hitCooldown > 0 then
		self._hitCooldown = self._hitCooldown - dt
	end

	local inBoost = self:_isInBoostZone()
	if inBoost ~= self._boosting then
		self._boosting = inBoost
		self.BoostChanged:Fire(inBoost)
	end

	if inBoost then
		self._currentSpeed = math.min(self._currentSpeed + BOOST_ACCEL * dt, MAX_SPEED)
	end

	if self._hitCooldown <= 0 and self:_isInHazard() then
		self._health = math.max(self._health - HAZARD_DAMAGE, 0)
		self._hitCooldown = HAZARD_HIT_COOLDOWN
		self.HealthChanged:Fire(self._health)
		self.HazardHit:Fire(self._health)
	end

	self.SpeedChanged:Fire(self._currentSpeed)

	self._t = self._t + (self._currentSpeed / TRACK_LENGTH) * dt
	if self._t > 1 then
		self._t = self._t - 1
	end

	self._laneBlend = self._laneBlend + LANE_SWITCH_SPEED * dt
	if self._laneBlend >= 1 then
		self._laneBlend = 0
		self._currentLane = self._targetLane
	end

	local currentSpline = self._splines[self._currentLane].spline
	local targetSpline = self._splines[self._targetLane].spline

	local currentPos = currentSpline:CalculatePositionAt(self._t)
	local targetPos = targetSpline:CalculatePositionAt(self._t)
	local finalPos = currentPos:Lerp(targetPos, self._laneBlend)

	local currentDir = currentSpline:CalculateDerivativeAt(self._t)
	local targetDir = targetSpline:CalculateDerivativeAt(self._t)
	local dir = currentDir:Lerp(targetDir, self._laneBlend)

	if dir.Magnitude < 0.001 then
		dir = Vector3.new(0, 0, -1)
	end
	dir = dir.Unit

	local lateralDelta = finalPos.X - self._lastXPos
	self._lastXPos = finalPos.X

	local curvatureBank = 0
	if dt > 0 then
		local lateralSpeed = lateralDelta / dt
		local speedFrac = self._currentSpeed / MAX_SPEED
		curvatureBank = math.clamp(-lateralSpeed * 0.008 * (0.5 + speedFrac), -MAX_BANK_ANGLE, MAX_BANK_ANGLE)
	end

	local switchBank = 0
	if self._currentLane ~= self._targetLane then
		local blend = math.sin(self._laneBlend * math.pi)
		switchBank = -self._switchDir * LANE_SWITCH_BANK * blend
	end

	local targetRoll = curvatureBank + switchBank
	targetRoll = math.clamp(targetRoll, -MAX_BANK_ANGLE, MAX_BANK_ANGLE)
	self._currentRoll = self._currentRoll + (targetRoll - self._currentRoll) * math.min(BANK_SMOOTH_SPEED * dt, 1)

	local lookTarget = finalPos + dir
	local baseCF = CFrame.lookAt(finalPos, lookTarget)
	machine:PivotTo(baseCF * CFrame.Angles(0, 0, self._currentRoll))

	self.RaceProgress:Fire(self._t)
end

function LakelandRaceController:GetProgress()
	return self._t
end

function LakelandRaceController:GetCurrentLane()
	return self._currentLane
end

function LakelandRaceController:GetCurrentSpeed()
	return self._currentSpeed
end

function LakelandRaceController:IsBoosting()
	return self._boosting
end

function LakelandRaceController:GetHealth()
	return self._health
end

function LakelandRaceController:GetMaxHealth()
	return MAX_HEALTH
end

return LakelandRaceController
