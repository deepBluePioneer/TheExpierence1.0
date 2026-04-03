local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local FEET_OFFSET = 2.5
local CAST_RADIUS = 1.0
local CAST_RANGE = 3.0

local GraviBowGroundController = Knit.CreateController({
	Name = "GraviBowGroundController",

	IsGrounded = false,
	GroundNormal = Vector3.new(0, 1, 0),
	GroundDistance = math.huge,
	GroundPart = nil,

	_trove = nil,
	_characterTrove = nil,
	_rayParams = nil,
})

function GraviBowGroundController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowGroundController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end

	print("[GraviBowGroundController] Started")
end

function GraviBowGroundController:_onCharacterAdded(character)
	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	self._rayParams = RaycastParams.new()
	self._rayParams.FilterDescendantsInstances = { character }
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude

	self._characterTrove:Add(RunService.Heartbeat:Connect(function(_dt)
		self:_updateGround(hrp)
	end), "Disconnect")
end

function GraviBowGroundController:_updateGround(hrp)
	local gravityDir = self._gravityController.GravityDirection

	local feetOrigin = hrp.Position + gravityDir * FEET_OFFSET
	local castDir = gravityDir * CAST_RANGE

	local result = Workspace:Spherecast(feetOrigin, CAST_RADIUS, castDir, self._rayParams)

	if result then
		self.IsGrounded = true
		self.GroundNormal = result.Normal
		self.GroundDistance = result.Distance
		self.GroundPart = result.Instance
	else
		self.IsGrounded = false
		self.GroundNormal = -gravityDir
		self.GroundDistance = math.huge
		self.GroundPart = nil
	end
end

return GraviBowGroundController
