local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local CAST_RANGE = 6.0
local GRID_DIVISIONS = 3
local SPRING_FREE_LENGTH_RATIO = 2
local SPRING_SOLVE_TIME = 0.05
local SPRING_SUBSTEPS = 3
local MIN_DOWNWARD_ACCEL = -1

local GraviBowGroundController = Knit.CreateController({
	Name = "GraviBowGroundController",

	IsGrounded = false,
	GroundNormal = Vector3.new(0, 1, 0),
	GroundDistance = math.huge,
	GroundPart = nil,

	_trove = nil,
	_characterTrove = nil,
	_rayParams = nil,
	_rayAttachments = {},
	_springForce = nil,
	_dampingForce = nil,
	_hipHeight = 2.5,
})

function GraviBowGroundController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowGroundController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._characterController = Knit.GetController("GraviBowCharacterController")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end
end

function GraviBowGroundController:_computeHipHeight(character, hrp)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return 2.5 end

	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leftLeg = character:FindFirstChild("Left Leg")
		if leftLeg then
			return leftLeg.Size.Y + hrp.Size.Y * 0.5
		end
	else
		return humanoid.HipHeight + hrp.Size.Y * 0.5
	end
	return 2.5
end

function GraviBowGroundController:_onCharacterAdded(character)
	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	local centerAttachment = hrp:WaitForChild("CenterAttachment", 10)
	if not centerAttachment then
		warn("[GraviBowGroundController] Missing CenterAttachment on HumanoidRootPart")
		return
	end

	self._hipHeight = self:_computeHipHeight(character, hrp)

	self._rayParams = RaycastParams.new()
	local groundFilterList = { character }
	local gravityZones = Workspace:FindFirstChild("GravityZones")
	if gravityZones then
		table.insert(groundFilterList, gravityZones)
	end
	local terrainPlanets = Workspace:FindFirstChild("TerrainPlanets")
	if terrainPlanets then
		table.insert(groundFilterList, terrainPlanets)
	end
	local crystalPatches = Workspace:FindFirstChild("CrystalPatches")
	if crystalPatches then
		table.insert(groundFilterList, crystalPatches)
	end
	local npcFolder = Workspace:FindFirstChild("GraviNPCs")
	if npcFolder then
		table.insert(groundFilterList, npcFolder)
	end
	local botFolder = Workspace:FindFirstChild("GraviBots")
	if botFolder then
		table.insert(groundFilterList, botFolder)
	end
	self._rayParams.FilterDescendantsInstances = groundFilterList
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude

	self:_createRayAttachments(hrp)
	self:_createSpringForces(hrp, centerAttachment)

	self._characterTrove:Add(RunService.Stepped:Connect(function(_, dt)
		self:_update(hrp, dt)
	end), "Disconnect")

	self._characterTrove:Add(function()
		self:_cleanup()
	end)
end

function GraviBowGroundController:_createRayAttachments(hrp)
	self._rayAttachments = {}
	local topRight = hrp.Size * Vector3.new(1, 0, 1) / 2
	local xStep = 2 * topRight.X / GRID_DIVISIONS
	local zStep = 2 * topRight.Z / GRID_DIVISIONS

	for x = 0, GRID_DIVISIONS do
		for z = 0, GRID_DIVISIONS do
			local pos = Vector3.new(
				xStep * x - topRight.X,
				0,
				zStep * z - topRight.Z
			)
			local att = Instance.new("Attachment")
			att.Name = "RayAttachment"
			att.Position = pos
			att.Parent = hrp
			table.insert(self._rayAttachments, att)
		end
	end
end

function GraviBowGroundController:_createSpringForces(hrp, centerAttachment)
	local springForce = Instance.new("VectorForce")
	springForce.Name = "HipHeightSpring"
	springForce.Attachment0 = centerAttachment
	springForce.ApplyAtCenterOfMass = true
	springForce.Force = Vector3.zero
	springForce.RelativeTo = Enum.ActuatorRelativeTo.World
	springForce.Parent = hrp
	self._springForce = springForce

	local dampingForce = Instance.new("VectorForce")
	dampingForce.Name = "HipHeightDamping"
	dampingForce.Attachment0 = centerAttachment
	dampingForce.ApplyAtCenterOfMass = true
	dampingForce.Force = Vector3.zero
	dampingForce.RelativeTo = Enum.ActuatorRelativeTo.World
	dampingForce.Parent = hrp
	self._dampingForce = dampingForce
end

function GraviBowGroundController:_cleanup()
	if self._springForce then
		self._springForce:Destroy()
		self._springForce = nil
	end
	if self._dampingForce then
		self._dampingForce:Destroy()
		self._dampingForce = nil
	end
	for _, att in ipairs(self._rayAttachments) do
		att:Destroy()
	end
	self._rayAttachments = {}
end

function GraviBowGroundController:_update(hrp, dt)
	local gravityDir = self._gravityController.GravityDirection
	local upDir = -gravityDir

	local onGround, avgHitPos, avgNormal = self:_castGroundRays(gravityDir, upDir, hrp)

	self.IsGrounded = onGround
	self.GroundNormal = if onGround then avgNormal else upDir

	if not onGround then
		self.GroundDistance = math.huge
		self.GroundPart = nil
		if self._springForce then
			self._springForce.Force = Vector3.zero
		end
		if self._dampingForce then
			self._dampingForce.Force = Vector3.zero
		end
		return
	end

	local isJumping = self._characterController
		and self._characterController._stateMachine
		and self._characterController._stateMachine.current == "Jumping"

	if isJumping then
		self._springForce.Force = Vector3.zero
		self._dampingForce.Force = Vector3.zero
		return
	end

	local mass = hrp.AssemblyMass
	local hipHeight = self._hipHeight

	local rootPos = hrp.Position
	local currentHeight = (rootPos - avgHitPos):Dot(upDir)
	local targetHeight = hipHeight

	local currentVel = hrp.AssemblyLinearVelocity
	local verticalVel = currentVel:Dot(upDir)

	self.GroundDistance = currentHeight

	local upwardForce = self:_calculateSpringForce(
		targetHeight, currentHeight, verticalVel, mass, dt
	)

	self._springForce.Force = upDir * upwardForce
	self._dampingForce.Force = Vector3.zero
end

function GraviBowGroundController:_castGroundRays(gravityDir, upDir, hrp)
	local freeLengthOfSpring = self._hipHeight * SPRING_FREE_LENGTH_RATIO
	local rayDir = gravityDir * freeLengthOfSpring

	local hitCount = 0
	local totalHitPos = Vector3.zero
	local totalNormal = Vector3.zero
	local onGround = false

	for _, att in ipairs(self._rayAttachments) do
		local result = Workspace:Raycast(att.WorldPosition, rayDir, self._rayParams)
		if result then
			onGround = true
			hitCount += 1
			totalHitPos += result.Position
			totalNormal += result.Normal
		end
	end

	if hitCount > 0 then
		return true, totalHitPos / hitCount, (totalNormal / hitCount).Unit
	end

	return false, Vector3.zero, upDir
end

function GraviBowGroundController:_calculateSpringForce(targetHeight, currentHeight, verticalVel, mass, dt)
	local gravityAccel = self._gravityController._cachedMass > 0
		and 40
		or 40

	local t = SPRING_SOLVE_TIME

	local function solveAccel(tgtH, curH, curVel)
		local aUp = gravityAccel + 2 * ((tgtH - curH) - curVel * t) / (t * t)
		return math.max(MIN_DOWNWARD_ACCEL, aUp) * mass
	end

	local upwardForce = solveAccel(targetHeight, currentHeight, verticalVel)

	local iterForce = upwardForce
	local iterVel = verticalVel
	local iterHeight = currentHeight
	local step = dt / SPRING_SUBSTEPS

	for _ = 1, SPRING_SUBSTEPS - 1 do
		local weight = mass * gravityAccel
		local netForce = iterForce - weight
		local accel = netForce / mass
		local predictedVel = iterVel + accel * step
		local predictedDisp = iterVel * step + 0.5 * accel * step * step
		local newForce = solveAccel(targetHeight, iterHeight + predictedDisp, predictedVel)

		iterForce = (newForce + iterForce) * 0.5
		iterVel = (iterVel + predictedVel) * 0.5
		iterHeight = iterHeight + predictedDisp * 0.5
	end

	return iterForce
end

return GraviBowGroundController
