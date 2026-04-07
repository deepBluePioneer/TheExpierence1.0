local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local SEGMENT_COUNT = 55
local SEGMENT_RADIUS = 2.2
local SEGMENT_LENGTH = 4.4
local SEGMENT_TRAIL_GAP = 1.8

local ALIGN_RESPONSIVENESS = 35
local ALIGN_MAX_FORCE = 100000
local ALIGN_MAX_VELOCITY = 120
local ORIENT_RESPONSIVENESS = 20

local UNIFORM_SCALE = 1

local HEAD_COLOR = Color3.fromRGB(225, 165, 55)
local BODY_COLOR_START = Color3.fromRGB(175, 115, 50)
local BODY_COLOR_END = Color3.fromRGB(90, 55, 28)
local BODY_MATERIAL = Enum.Material.SmoothPlastic
local BODY_TRANSPARENCY = 0

local GraviBowSnakeService = Knit.CreateService({
	Name = "GraviBowSnakeService",
	Client = {},

	_trove = nil,
	_snakeFolder = nil,
	_snakeTroves = {},
	_touchConnections = {},
})

function GraviBowSnakeService:KnitInit()
	self._trove = Trove.new()
end

function GraviBowSnakeService:KnitStart()
	self._matchService = Knit.GetService("GraviBowMatchService")

	self._snakeFolder = Instance.new("Folder")
	self._snakeFolder.Name = "SnakeBodies"
	self._snakeFolder.Parent = Workspace
	self._trove:Add(self._snakeFolder)

	self._trove:Add(Players.PlayerRemoving:Connect(function(player)
		self:DestroySnakeForPlayer(player)
	end), "Disconnect")
end

function GraviBowSnakeService:BuildSnakeForPlayer(player)
	self:DestroySnakeForPlayer(player)

	local character = player.Character
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		hrp = character:WaitForChild("HumanoidRootPart", 10)
		if not hrp then return end
	end

	local snakeTrove = Trove.new()
	self._snakeTroves[player] = snakeTrove

	local folder = Instance.new("Folder")
	folder.Name = "Snake_" .. player.UserId
	folder:SetAttribute("OwnerId", player.UserId)
	folder:SetAttribute("SegmentCount", SEGMENT_COUNT)
	snakeTrove:Add(folder)

	local segments = {}

	for i = 1, SEGMENT_COUNT do
		local diameter = SEGMENT_RADIUS * 2
		local t = (i - 1) / math.max(SEGMENT_COUNT - 1, 1)

		local seg = Instance.new("Part")
		seg.Name = "Seg_" .. i
		seg.Shape = Enum.PartType.Block
		seg.Size = Vector3.new(SEGMENT_LENGTH, diameter, diameter)
		seg.CFrame = CFrame.new(hrp.Position - hrp.CFrame.LookVector * (SEGMENT_TRAIL_GAP * i))
		seg.Anchored = false
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = true
		seg.Massless = true
		seg.CastShadow = false
		seg.TopSurface = Enum.SurfaceType.Smooth
		seg.BottomSurface = Enum.SurfaceType.Smooth
		seg.Material = BODY_MATERIAL
		seg.Transparency = BODY_TRANSPARENCY

		local baseColor
		if i == 1 then
			baseColor = HEAD_COLOR
		else
			baseColor = BODY_COLOR_START:Lerp(BODY_COLOR_END, t)
		end
		seg.Color = baseColor

		self:_weldBodyDetails(seg, diameter, baseColor)
		if i == 1 then
			self:_weldHeadDetails(seg, diameter)
		end

		local att = Instance.new("Attachment")
		att.Name = "CenterAtt"
		att.Parent = seg

		local alignPos = Instance.new("AlignPosition")
		alignPos.Name = "TrailAlign"
		alignPos.Attachment0 = att
		alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
		alignPos.MaxForce = ALIGN_MAX_FORCE
		alignPos.MaxVelocity = ALIGN_MAX_VELOCITY
		alignPos.Responsiveness = ALIGN_RESPONSIVENESS
		alignPos.Position = seg.Position
		alignPos.Parent = seg

		local alignOri = Instance.new("AlignOrientation")
		alignOri.Name = "TrailOrient"
		alignOri.Attachment0 = att
		alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOri.MaxTorque = 30000
		alignOri.Responsiveness = ORIENT_RESPONSIVENESS
		alignOri.CFrame = seg.CFrame - seg.CFrame.Position
		alignOri.Parent = seg

		seg.Parent = folder
		table.insert(segments, seg)
	end

	for i = 1, #segments do
		for j = i + 1, #segments do
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = segments[i]
			nc.Part1 = segments[j]
			nc.Parent = segments[i]
		end
	end

	self:_addCharacterNoCollision(character, segments, snakeTrove)

	folder.Parent = self._snakeFolder

	for _, seg in ipairs(segments) do
		seg:SetNetworkOwner(player)
	end

	self:_connectTouchDetection(player, segments, snakeTrove)

	print("[GraviBowSnakeService] Built snake for", player.Name)
end

function GraviBowSnakeService:DestroySnakeForPlayer(player)
	local trove = self._snakeTroves[player]
	if trove then
		trove:Clean()
		self._snakeTroves[player] = nil
	end
end

function GraviBowSnakeService:_addCharacterNoCollision(character, segments, snakeTrove)
	local function addNoCollisionForPart(charPart)
		if not charPart:IsA("BasePart") then return end
		for _, seg in ipairs(segments) do
			if not seg.Parent then continue end
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = seg
			nc.Part1 = charPart
			nc.Parent = seg
		end
	end

	for _, desc in ipairs(character:GetDescendants()) do
		addNoCollisionForPart(desc)
	end

	snakeTrove:Add(character.DescendantAdded:Connect(function(desc)
		addNoCollisionForPart(desc)
	end), "Disconnect")
end

function GraviBowSnakeService:_connectTouchDetection(ownerPlayer, segments, snakeTrove)
	for _, seg in ipairs(segments) do
		local conn = seg.Touched:Connect(function(hit)
			if not self._matchService:IsRoundActive() then return end

			local hitCharacter = hit.Parent
			if not hitCharacter then return end
			local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
			if not humanoid then return end

			local victimPlayer = Players:GetPlayerFromCharacter(hitCharacter)
			if not victimPlayer then return end
			if victimPlayer == ownerPlayer then return end
			if self._matchService:IsSnakePlayer(victimPlayer) then return end

			self._matchService:ConvertToSnake(victimPlayer)
		end)
		snakeTrove:Add(conn, "Disconnect")
	end
end

function GraviBowSnakeService:_segmentScale(_index)
	return UNIFORM_SCALE
end

function GraviBowSnakeService:_makeDetailPart(parent)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Block
	p.Material = BODY_MATERIAL
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function GraviBowSnakeService:_weldTo(part0, part1, offset)
	local w = Instance.new("Weld")
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = offset
	w.Parent = part1
end

function GraviBowSnakeService:_weldBodyDetails(seg, diameter, baseColor)
	local r = diameter / 2

	local spine = self:_makeDetailPart(seg)
	spine.Name = "Spine"
	spine.Size = Vector3.new(r * 0.35, 0.3, diameter * 0.88)
	spine.Color = baseColor:Lerp(Color3.new(0, 0, 0), 0.35)
	self:_weldTo(seg, spine, CFrame.new(0, r + 0.12, 0))

	local belly = self:_makeDetailPart(seg)
	belly.Name = "Belly"
	belly.Size = Vector3.new(diameter * 0.55, 0.2, diameter * 0.88)
	belly.Color = baseColor:Lerp(Color3.new(1, 1, 1), 0.2)
	self:_weldTo(seg, belly, CFrame.new(0, -(r + 0.08), 0))
end

function GraviBowSnakeService:_weldHeadDetails(seg, diameter)
	local r = diameter / 2
	local eyeSize = r * 0.5
	local pupilSize = r * 0.28

	local brow = self:_makeDetailPart(seg)
	brow.Name = "Brow"
	brow.Size = Vector3.new(diameter * 0.8, 0.35, 0.35)
	brow.Color = HEAD_COLOR:Lerp(Color3.new(0, 0, 0), 0.35)
	self:_weldTo(seg, brow, CFrame.new(0, r * 0.45, -(r + 0.1)))

	for _, side in ipairs({-1, 1}) do
		local eye = Instance.new("Part")
		eye.Name = side == 1 and "EyeR" or "EyeL"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.one * eyeSize
		eye.Color = Color3.new(1, 1, 1)
		eye.Material = Enum.Material.SmoothPlastic
		eye.Anchored = false
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.Massless = true
		eye.CastShadow = false
		eye.Parent = seg
		self:_weldTo(seg, eye, CFrame.new(side * r * 0.42, r * 0.18, -(r * 0.82)))

		local pupil = Instance.new("Part")
		pupil.Name = "Pupil"
		pupil.Shape = Enum.PartType.Ball
		pupil.Size = Vector3.one * pupilSize
		pupil.Color = Color3.fromRGB(15, 15, 15)
		pupil.Material = Enum.Material.SmoothPlastic
		pupil.Anchored = false
		pupil.CanCollide = false
		pupil.CanQuery = false
		pupil.CanTouch = false
		pupil.Massless = true
		pupil.CastShadow = false
		pupil.Parent = seg
		self:_weldTo(eye, pupil, CFrame.new(side * eyeSize * 0.1, eyeSize * 0.05, -(eyeSize * 0.35)))
	end

	local light = Instance.new("PointLight")
	light.Color = HEAD_COLOR
	light.Brightness = 0.4
	light.Range = 8
	light.Shadows = false
	light.Parent = seg
end

return GraviBowSnakeService
