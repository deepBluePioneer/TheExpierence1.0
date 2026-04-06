local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local SEGMENT_RADIUS = 2.2
local SAMPLE_DISTANCE = 0.25
local SEGMENT_TRAIL_GAP = 2.8

local UNIFORM_SCALE = 1

local GraviBowSnakeController = Knit.CreateController({
	Name = "GraviBowSnakeController",

	_trove = nil,
	_characterTrove = nil,
	_segments = {},
	_segmentCount = 0,
	_samplesPerSegF = 0,
	_trail = {},
	_trailHead = 0,
	_trailCount = 0,
	_bufferSize = 0,
	_lastSamplePos = nil,
	_wasDigging = false,
	_lastDigBezier = nil,
})

function GraviBowSnakeController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowSnakeController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._characterController = Knit.GetController("GraviBowCharacterController")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end
end

function GraviBowSnakeController:_onCharacterAdded(character)
	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()
	self._segments = {}
	self._trail = {}
	self._trailHead = 0
	self._trailCount = 0
	self._lastSamplePos = nil

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	local folder = self:_waitForSnakeFolder()
	if not folder then return end

	local segmentCount = folder:GetAttribute("SegmentCount") or 20
	self._segmentCount = segmentCount
	self._samplesPerSegF = SEGMENT_TRAIL_GAP / SAMPLE_DISTANCE
	self._bufferSize = math.ceil(segmentCount * self._samplesPerSegF) + 30

	for i = 1, self._bufferSize do
		self._trail[i] = hrp.Position
	end
	self._trailHead = self._bufferSize
	self._trailCount = self._bufferSize
	self._lastSamplePos = hrp.Position

	self:_collectSegments(folder)

	self._characterTrove:Add(RunService.RenderStepped:Connect(function()
		self:_update(hrp)
	end), "Disconnect")
end

function GraviBowSnakeController:_waitForSnakeFolder()
	local snakeBodies = Workspace:WaitForChild("SnakeBodies", 15)
	if not snakeBodies then return nil end

	local folderName = "Snake_" .. LocalPlayer.UserId
	local folder = snakeBodies:FindFirstChild(folderName)
	if folder then return folder end

	local startTime = os.clock()
	while os.clock() - startTime < 15 do
		folder = snakeBodies:FindFirstChild(folderName)
		if folder then return folder end
		task.wait(0.1)
	end

	warn("[GraviBowSnakeController] Timed out waiting for snake folder")
	return nil
end

function GraviBowSnakeController:_collectSegments(folder)
	self._segments = {}
	for i = 1, self._segmentCount do
		local seg = folder:FindFirstChild("Seg_" .. i)
		if not seg then continue end

		local alignPos = seg:FindFirstChild("TrailAlign")
		local alignOri = seg:FindFirstChild("TrailOrient")
		if not alignPos or not alignOri then continue end

		self._segments[i] = {
			part = seg,
			alignPos = alignPos,
			alignOri = alignOri,
		}
	end
end

function GraviBowSnakeController:_segmentScale(_index)
	return UNIFORM_SCALE
end

function GraviBowSnakeController:_cubeOrientation(upDir, fwd)
	local look = fwd - upDir * fwd:Dot(upDir)
	if look.Magnitude < 0.01 then
		look = upDir:Cross(Vector3.new(0, 0, 1))
		if look.Magnitude < 0.01 then
			look = upDir:Cross(Vector3.new(1, 0, 0))
		end
	end
	look = look.Unit
	local right = look:Cross(upDir).Unit
	return CFrame.fromMatrix(Vector3.zero, right, upDir, -look)
end

function GraviBowSnakeController:_pushSample(pos)
	self._trailHead = (self._trailHead % self._bufferSize) + 1
	self._trail[self._trailHead] = pos
	if self._trailCount < self._bufferSize then
		self._trailCount += 1
	end
end

function GraviBowSnakeController:_getRawSample(stepsBack)
	if stepsBack >= self._trailCount then
		stepsBack = self._trailCount - 1
	end
	local idx = self._trailHead - stepsBack
	if idx < 1 then idx += self._bufferSize end
	return self._trail[idx]
end

function GraviBowSnakeController:_getSampleLerped(fractionalSteps)
	local lo = math.floor(fractionalSteps)
	local hi = lo + 1
	local alpha = fractionalSteps - lo
	local a = self:_getRawSample(lo)
	local b = self:_getRawSample(hi)
	return a:Lerp(b, alpha)
end

function GraviBowSnakeController:_bezierPosAndTangent(bez, t)
	local u = 1 - t
	local pos = u*u*u * bez.p0 + 3*u*u*t * bez.p1 + 3*u*t*t * bez.p2 + t*t*t * bez.p3
	local tan = 3*u*u * (bez.p1 - bez.p0) + 6*u*t * (bez.p2 - bez.p1) + 3*t*t * (bez.p3 - bez.p2)
	if tan.Magnitude < 0.01 then
		tan = (bez.p3 - bez.p0)
	end
	if tan.Magnitude > 0.01 then tan = tan.Unit end
	return pos, tan
end

function GraviBowSnakeController:_update(hrp)
	if not hrp.Parent then return end
	local pos = hrp.Position

	local character = hrp.Parent
	local head = character and character:FindFirstChild("Head")
	local lookTarget = head and head.Position or pos

	if self._lastSamplePos then
		local delta = pos - self._lastSamplePos
		local dist = delta.Magnitude
		if dist >= SAMPLE_DISTANCE then
			local dir = delta.Unit
			local traveled = 0
			while traveled + SAMPLE_DISTANCE <= dist do
				traveled += SAMPLE_DISTANCE
				self:_pushSample(self._lastSamplePos + dir * traveled)
			end
			self._lastSamplePos = self._lastSamplePos + dir * traveled
		end
	else
		self._lastSamplePos = pos
	end

	local planetCenter = self._gravityController:GetSphereCenter()
	if not planetCenter then return end

	local digging = self._characterController and self._characterController:IsDigging()
	local bezier = digging and self._characterController:GetDigBezier() or nil

	local digJustEnded = self._wasDigging and not digging
	if digJustEnded then
		local lastBezier = self._lastDigBezier
		if lastBezier then
			local headAlpha = lastBezier.alpha
			local totalTrailT = self._segmentCount / (self._segmentCount + 1)
			for i = 1, self._bufferSize do
				local frac = (self._bufferSize - i) / math.max(self._bufferSize - 1, 1)
				local t = math.clamp(headAlpha - frac * totalTrailT, 0, headAlpha)
				local u = 1 - t
				self._trail[i] = u*u*u * lastBezier.p0 + 3*u*u*t * lastBezier.p1 + 3*u*t*t * lastBezier.p2 + t*t*t * lastBezier.p3
			end
		else
			for i = 1, self._bufferSize do
				self._trail[i] = pos
			end
		end
		self._trailHead = self._bufferSize
		self._trailCount = self._bufferSize
		self._lastSamplePos = pos
		self._lastDigBezier = nil

		for i = 1, self._segmentCount do
			local data = self._segments[i]
			if not data then continue end
			local seg = data.part
			if not seg.Parent then continue end

			local trailF = i * self._samplesPerSegF
			if trailF < 0 then trailF = 0 end
			local targetPos = self:_getSampleLerped(trailF)
			local aheadF = math.max(0, trailF - self._samplesPerSegF)
			local aheadPos = self:_getSampleLerped(aheadF)

			local toCenter = planetCenter - targetPos
			local upDir
			if toCenter.Magnitude > 0.01 then upDir = -toCenter.Unit else upDir = Vector3.yAxis end

			local scale = self:_segmentScale(i)
			local finalPos = targetPos + upDir * (SEGMENT_RADIUS * scale)
			local fwd = aheadPos - targetPos
			if fwd.Magnitude < 0.01 then fwd = upDir:Cross(Vector3.new(0, 0, 1)) end
			local ori = self:_cubeOrientation(upDir, fwd)

			seg.CFrame = ori + finalPos
			data.alignPos.Position = finalPos
			data.alignOri.CFrame = ori
		end
	end
	self._wasDigging = digging

	if bezier then
		self._lastDigBezier = bezier
		local headAlpha = bezier.alpha
		local segSpacing = 1 / (self._segmentCount + 1)

		for i = 1, self._segmentCount do
			local data = self._segments[i]
			if not data then continue end
			local seg = data.part
			if not seg.Parent then continue end

			local t = math.clamp(headAlpha - i * segSpacing, 0, headAlpha)
			local bPos, bTan = self:_bezierPosAndTangent(bezier, t)

			local curveUp = (bPos - planetCenter)
			if curveUp.Magnitude > 0.01 then curveUp = curveUp.Unit else curveUp = Vector3.yAxis end

			local scale = self:_segmentScale(i)
			local offset = curveUp * (SEGMENT_RADIUS * scale)
			local finalPos = bPos + offset

			local ori
			if i == 1 then
				local toHead = lookTarget - finalPos
				if toHead.Magnitude > 0.01 then
					ori = CFrame.lookAt(Vector3.zero, toHead.Unit, curveUp) - CFrame.lookAt(Vector3.zero, toHead.Unit, curveUp).Position
				else
					ori = self:_cubeOrientation(curveUp, bTan)
				end
			else
				ori = self:_cubeOrientation(curveUp, bTan)
			end

			seg.CFrame = ori + finalPos
			data.alignPos.Position = finalPos
			data.alignOri.CFrame = ori
		end
		return
	end

	local residual = 0
	if self._lastSamplePos then
		local d = (pos - self._lastSamplePos).Magnitude
		residual = d / SAMPLE_DISTANCE
	end

	for i = 1, self._segmentCount do
		local data = self._segments[i]
		if not data then continue end
		local seg = data.part
		if not seg.Parent then continue end

		local trailF = i * self._samplesPerSegF - residual
		if trailF < 0 then trailF = 0 end
		local targetPos = self:_getSampleLerped(trailF)

		local aheadF = math.max(0, trailF - self._samplesPerSegF)
		local aheadPos = self:_getSampleLerped(aheadF)

		local toCenter = planetCenter - targetPos
		local upDir
		if toCenter.Magnitude > 0.01 then
			upDir = -toCenter.Unit
		else
			upDir = Vector3.new(0, 1, 0)
		end

		local scale = self:_segmentScale(i)
		local finalPos = targetPos + upDir * (SEGMENT_RADIUS * scale)

		local ori
		if i == 1 then
			local toHead = lookTarget - finalPos
			if toHead.Magnitude > 0.01 then
				ori = CFrame.lookAt(Vector3.zero, toHead.Unit, upDir) - CFrame.lookAt(Vector3.zero, toHead.Unit, upDir).Position
			else
				ori = self:_cubeOrientation(upDir, upDir:Cross(Vector3.new(0, 0, 1)))
			end
		else
			local fwd = aheadPos - targetPos
			if fwd.Magnitude < 0.01 then fwd = upDir:Cross(Vector3.new(0, 0, 1)) end
			ori = self:_cubeOrientation(upDir, fwd)
		end

		data.alignPos.Position = finalPos
		data.alignOri.CFrame = ori
	end
end

return GraviBowSnakeController
