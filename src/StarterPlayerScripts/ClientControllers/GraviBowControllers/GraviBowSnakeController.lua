local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local SEGMENT_RADIUS = 1.3
local SAMPLE_DISTANCE = 0.25
local SEGMENT_TRAIL_GAP = 2.8

local HEAD_SCALE = 1.35
local TAIL_TAPER_START = 14
local TAIL_MIN_SCALE = 0.65

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
})

function GraviBowSnakeController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowSnakeController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")

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

function GraviBowSnakeController:_segmentScale(index)
	if index == 1 then
		return HEAD_SCALE
	end
	if index >= TAIL_TAPER_START then
		local t = (index - TAIL_TAPER_START) / math.max(self._segmentCount - TAIL_TAPER_START, 1)
		return 1 - (1 - TAIL_MIN_SCALE) * math.min(t, 1)
	end
	return 1
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

function GraviBowSnakeController:_update(hrp)
	if not hrp.Parent then return end
	local pos = hrp.Position

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
		local surfaceOffset = upDir * (SEGMENT_RADIUS * scale)
		data.alignPos.Position = targetPos + surfaceOffset

		local fwd = aheadPos - targetPos
		local tangent
		if fwd.Magnitude > 0.01 then
			tangent = fwd.Unit
		else
			tangent = upDir:Cross(Vector3.new(0, 0, 1))
			if tangent.Magnitude < 0.01 then
				tangent = upDir:Cross(Vector3.new(1, 0, 0))
			end
			tangent = tangent.Unit
		end

		local radial = upDir - tangent * upDir:Dot(tangent)
		if radial.Magnitude < 0.01 then
			radial = tangent:Cross(Vector3.new(0, 0, 1))
			if radial.Magnitude < 0.01 then
				radial = tangent:Cross(Vector3.new(1, 0, 0))
			end
		end
		radial = radial.Unit
		local side = tangent:Cross(radial).Unit
		data.alignOri.CFrame = CFrame.fromMatrix(Vector3.zero, tangent, radial, -side)
	end
end

return GraviBowSnakeController
