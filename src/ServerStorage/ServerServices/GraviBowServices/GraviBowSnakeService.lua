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
	_playerTroves = {},
	_charTroves = {},
	_snakeFolder = nil,
})

function GraviBowSnakeService:KnitInit()
	self._trove = Trove.new()
end

function GraviBowSnakeService:KnitStart()
	self._snakeFolder = Instance.new("Folder")
	self._snakeFolder.Name = "SnakeBodies"
	self._snakeFolder.Parent = Workspace
	self._trove:Add(self._snakeFolder)

	self._trove:Add(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end), "Disconnect")

	self._trove:Add(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end), "Disconnect")

	for _, player in ipairs(Players:GetPlayers()) do
		self:_onPlayerAdded(player)
	end
end

function GraviBowSnakeService:_onPlayerAdded(player)
	local playerTrove = Trove.new()
	self._playerTroves[player] = playerTrove

	playerTrove:Add(player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(player, character)
	end), "Disconnect")

	if player.Character then
		self:_onCharacterAdded(player, player.Character)
	end
end

function GraviBowSnakeService:_onPlayerRemoving(player)
	if self._charTroves[player] then
		self._charTroves[player]:Clean()
		self._charTroves[player] = nil
	end
	local playerTrove = self._playerTroves[player]
	if playerTrove then
		playerTrove:Clean()
		self._playerTroves[player] = nil
	end
end

function GraviBowSnakeService:_onCharacterAdded(player, character)
	local playerTrove = self._playerTroves[player]
	if not playerTrove then return end

	if self._charTroves[player] then
		self._charTroves[player]:Clean()
	end
	local charTrove = Trove.new()
	self._charTroves[player] = charTrove

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList = { character }
	local snakeBodies = Workspace:FindFirstChild("SnakeBodies")
	if snakeBodies then table.insert(excludeList, snakeBodies) end
	local gravZones = Workspace:FindFirstChild("GravityZones")
	if gravZones then table.insert(excludeList, gravZones) end
	local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
	if tpFolder then table.insert(excludeList, tpFolder) end
	rayParams.FilterDescendantsInstances = excludeList

	local grounded = false
	for _ = 1, 200 do
		if not character.Parent then return end
		local origin = hrp.Position
		local down = -origin.Unit
		if origin.Magnitude < 0.01 then down = Vector3.new(0, -1, 0) end
		local result = Workspace:Raycast(origin, down * 15, rayParams)
		if result then
			grounded = true
			break
		end
		task.wait(0.1)
	end

	if not grounded then
		warn("[GraviBowSnakeService] Player", player.Name, "never grounded, building snake anyway")
	end

	task.wait(3)
	if not character.Parent then return end

	local folder = Instance.new("Folder")
	folder.Name = "Snake_" .. player.UserId
	folder:SetAttribute("OwnerId", player.UserId)
	folder:SetAttribute("SegmentCount", SEGMENT_COUNT)
	folder.Parent = self._snakeFolder
	charTrove:Add(folder)

	local charParts = {}
	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("BasePart") then
			table.insert(charParts, desc)
		end
	end

	local segments = {}

	for i = 1, SEGMENT_COUNT do
		local diameter = SEGMENT_RADIUS * 2

		local seg = Instance.new("Part")
		seg.Name = "Seg_" .. i
		seg.Shape = Enum.PartType.Block
		seg.Size = Vector3.new(SEGMENT_LENGTH, diameter, diameter)
		seg.CFrame = CFrame.new(hrp.Position - hrp.CFrame.LookVector * (SEGMENT_TRAIL_GAP * i))
		seg.Anchored = false
		seg.CanCollide = true
		seg.CanQuery = false
		seg.CanTouch = false
		seg.Massless = true
		seg.CastShadow = false
		seg.TopSurface = Enum.SurfaceType.Smooth
		seg.BottomSurface = Enum.SurfaceType.Smooth
		seg.Material = BODY_MATERIAL

		seg.Color = BODY_COLOR
		seg.Transparency = BODY_TRANSPARENCY

		for _, charPart in ipairs(charParts) do
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0 = seg
			nc.Part1 = charPart
			nc.Parent = seg
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
		seg:SetNetworkOwner(player)
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

	print("[GraviBowSnakeService] Built snake for", player.Name)
end

function GraviBowSnakeService:_segmentScale(_index)
	return UNIFORM_SCALE
end

return GraviBowSnakeService
