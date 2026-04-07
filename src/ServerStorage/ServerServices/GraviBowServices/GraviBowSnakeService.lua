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

local BODY_COLOR = Color3.fromRGB(139, 90, 43)
local HEAD_COLOR = Color3.fromRGB(139, 90, 43)
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

		seg.Color = BODY_COLOR
		seg.Transparency = BODY_TRANSPARENCY

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

return GraviBowSnakeService
