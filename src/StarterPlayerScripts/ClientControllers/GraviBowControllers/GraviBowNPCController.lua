local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local PLANET_TAG = "planet"
local GRAVITY_FORCE = 80
local WALK_SPEED = 18
local XZ_DRAG = 3
local FLAT_FRICTION = 400
local STOP_DAMPING = 50
local ALIGN_RESPONSIVENESS = 20

local WANDER_TIME_MIN = 3
local WANDER_TIME_MAX = 8
local IDLE_CHANCE = 0.25
local IDLE_TIME_MIN = 2
local IDLE_TIME_MAX = 5

local GRID_DIVISIONS = 3
local SPRING_FREE_LENGTH_RATIO = 2
local SPRING_SOLVE_TIME = 0.05
local SPRING_SUBSTEPS = 3
local MIN_DOWNWARD_ACCEL = -1

local ANIM_IDS = {
	Idle = "rbxassetid://507766666",
	Walk = "rbxassetid://507777826",
}

local GraviBowNPCController = Knit.CreateController({
	Name = "GraviBowNPCController",

	_trove = nil,
	_npcs = {},
	_npcFolder = nil,
	_planet = nil,
})

function GraviBowNPCController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowNPCController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")

	task.spawn(function()
		self:_init()
	end)
end

function GraviBowNPCController:_init()
	local folder = Workspace:WaitForChild("GraviNPCs", 30)
	if not folder then
		warn("[GraviBowNPCController] GraviNPCs folder never appeared")
		return
	end
	self._npcFolder = folder

	self._planet = self:_waitForPlanet()
	if not self._planet then
		warn("[GraviBowNPCController] No planet found")
		return
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			self:_registerNPC(child)
		end
	end

	self._trove:Add(folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			self:_registerNPC(child)
		end
	end), "Disconnect")

	self._trove:Add(RunService.Stepped:Connect(function(_, dt)
		self:_update(dt)
	end), "Disconnect")
end

function GraviBowNPCController:_waitForPlanet()
	local tagged = CollectionService:GetTagged(PLANET_TAG)
	for _, instance in ipairs(tagged) do
		local data = self:_buildPlanetData(instance)
		if data then return data end
	end
	local instance = CollectionService:GetInstanceAddedSignal(PLANET_TAG):Wait()
	return self:_buildPlanetData(instance)
end

function GraviBowNPCController:_buildPlanetData(instance)
	local part = self:_getPlanetPart(instance)
	if not part then return nil end
	return {
		model = instance,
		center = part.Position,
		radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2,
	}
end

function GraviBowNPCController:_getPlanetPart(model)
	if model:IsA("BasePart") then return model end
	if model:IsA("Model") and model.PrimaryPart then return model.PrimaryPart end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

function GraviBowNPCController:_refreshPlanetCenter()
	if not self._planet then return end
	local part = self:_getPlanetPart(self._planet.model)
	if part then
		self._planet.center = part.Position
	end
end

function GraviBowNPCController:_randomTangent(radial)
	local rand = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	local t = rand - radial * rand:Dot(radial)
	if t.Magnitude < 0.01 then
		t = radial:Cross(Vector3.new(0, 1, 0))
	end
	return t.Unit
end

function GraviBowNPCController:_buildRayParams(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { character }
	if self._npcFolder then table.insert(exclude, self._npcFolder) end
	local localChar = Players.LocalPlayer.Character
	if localChar then table.insert(exclude, localChar) end
	local gzFolder = Workspace:FindFirstChild("GravityZones")
	if gzFolder then table.insert(exclude, gzFolder) end
	local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
	if tpFolder then table.insert(exclude, tpFolder) end
	local crystals = Workspace:FindFirstChild("CrystalPatches")
	if crystals then table.insert(exclude, crystals) end
	local snakes = Workspace:FindFirstChild("SnakeBodies")
	if snakes then table.insert(exclude, snakes) end
	params.FilterDescendantsInstances = exclude
	return params
end

function GraviBowNPCController:_computeHipHeight(character, hrp)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return 2.5 end
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leftLeg = character:FindFirstChild("Left Leg")
		if leftLeg then return leftLeg.Size.Y + hrp.Size.Y * 0.5 end
	else
		return humanoid.HipHeight + hrp.Size.Y * 0.5
	end
	return 2.5
end

function GraviBowNPCController:_createRayAttachments(hrp)
	local attachments = {}
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
			table.insert(attachments, att)
		end
	end
	return attachments
end

function GraviBowNPCController:_registerNPC(model)
	local hrp = model:WaitForChild("HumanoidRootPart", 5)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	local gravForce = hrp:WaitForChild("GravityForce", 5)
	local centerAttachment = hrp:WaitForChild("CenterAttachment", 5)
	if not gravForce or not centerAttachment then
		warn("[GraviBowNPCController] NPC missing GravityForce or CenterAttachment:", model.Name)
		return
	end

	local mass = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			mass += d:GetMass()
		end
	end
	mass = math.max(mass, 0.1)

	local movementForce = Instance.new("VectorForce")
	movementForce.Name = "MovementForce"
	movementForce.Attachment0 = centerAttachment
	movementForce.ApplyAtCenterOfMass = true
	movementForce.Force = Vector3.zero
	movementForce.RelativeTo = Enum.ActuatorRelativeTo.World
	movementForce.Parent = model

	local dragForce = Instance.new("VectorForce")
	dragForce.Name = "DragForce"
	dragForce.Attachment0 = centerAttachment
	dragForce.ApplyAtCenterOfMass = true
	dragForce.Force = Vector3.zero
	dragForce.RelativeTo = Enum.ActuatorRelativeTo.World
	dragForce.Parent = model

	local terrainAttachment = Instance.new("Attachment")
	terrainAttachment.Name = "NPCAlignAttachment_" .. model.Name
	terrainAttachment.Parent = Workspace.Terrain

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "CharacterAlign"
	alignOrientation.Attachment0 = centerAttachment
	alignOrientation.Attachment1 = terrainAttachment
	alignOrientation.MaxAngularVelocity = 100
	alignOrientation.Responsiveness = ALIGN_RESPONSIVENESS
	alignOrientation.RigidityEnabled = true
	alignOrientation.Parent = model

	local springForce = Instance.new("VectorForce")
	springForce.Name = "HipHeightSpring"
	springForce.Attachment0 = centerAttachment
	springForce.ApplyAtCenterOfMass = true
	springForce.Force = Vector3.zero
	springForce.RelativeTo = Enum.ActuatorRelativeTo.World
	springForce.Parent = hrp

	local dampingForce = Instance.new("VectorForce")
	dampingForce.Name = "HipHeightDamping"
	dampingForce.Attachment0 = centerAttachment
	dampingForce.ApplyAtCenterOfMass = true
	dampingForce.Force = Vector3.zero
	dampingForce.RelativeTo = Enum.ActuatorRelativeTo.World
	dampingForce.Parent = hrp

	local rayAttachments = self:_createRayAttachments(hrp)
	local rayParams = self:_buildRayParams(model)
	local hipHeight = self:_computeHipHeight(model, hrp)

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animTracks = {}
	for name, id in pairs(ANIM_IDS) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Core
			track.Looped = true
			animTracks[name] = track
		end
		anim:Destroy()
	end

	local radialOut = (hrp.Position - self._planet.center)
	if radialOut.Magnitude < 0.1 then radialOut = Vector3.yAxis end
	radialOut = radialOut.Unit

	local npc = {
		model = model,
		hrp = hrp,
		humanoid = humanoid,
		gravForce = gravForce,
		moveForce = movementForce,
		dragForce = dragForce,
		springForce = springForce,
		dampingForce = dampingForce,
		alignOrientation = alignOrientation,
		terrainAttachment = terrainAttachment,
		rayAttachments = rayAttachments,
		rayParams = rayParams,
		mass = mass,
		hipHeight = hipHeight,
		wanderDir = self:_randomTangent(radialOut),
		isIdle = false,
		nextActionTime = os.clock() + math.random() * (WANDER_TIME_MAX - WANDER_TIME_MIN) + WANDER_TIME_MIN,
		animTracks = animTracks,
		currentAnim = nil,
	}

	table.insert(self._npcs, npc)
	self:_playAnimation(npc, "Idle")
end

function GraviBowNPCController:_playAnimation(npc, animName)
	if npc.currentAnim == animName then return end
	if npc.currentAnim and npc.animTracks[npc.currentAnim] then
		npc.animTracks[npc.currentAnim]:Stop(0.2)
	end
	local track = npc.animTracks[animName]
	if track then track:Play(0.2) end
	npc.currentAnim = animName
end

function GraviBowNPCController:_update(dt)
	if not self._planet then return end
	self:_refreshPlanetCenter()
	local center = self._planet.center

	for _, npc in ipairs(self._npcs) do
		if not npc.model.Parent or not npc.humanoid or npc.humanoid.Health <= 0 then
			continue
		end
		local hrp = npc.hrp
		if not hrp.Parent then continue end

		local toCenter = center - hrp.Position
		if toCenter.Magnitude < 0.1 then continue end

		local gravityDir = toCenter.Unit
		local upDir = -gravityDir

		local liveMass = hrp.AssemblyMass
		npc.gravForce.Force = gravityDir * GRAVITY_FORCE * liveMass

		if os.clock() >= npc.nextActionTime then
			if npc.isIdle then
				npc.isIdle = false
				npc.wanderDir = self:_randomTangent(upDir)
				npc.nextActionTime = os.clock()
					+ math.random() * (WANDER_TIME_MAX - WANDER_TIME_MIN) + WANDER_TIME_MIN
			elseif math.random() < IDLE_CHANCE then
				npc.isIdle = true
				npc.nextActionTime = os.clock()
					+ math.random() * (IDLE_TIME_MAX - IDLE_TIME_MIN) + IDLE_TIME_MIN
			else
				npc.wanderDir = self:_randomTangent(upDir)
				npc.nextActionTime = os.clock()
					+ math.random() * (WANDER_TIME_MAX - WANDER_TIME_MIN) + WANDER_TIME_MIN
			end
		end

		local vel = hrp.AssemblyLinearVelocity
		local tangentialVel = vel - gravityDir * vel:Dot(gravityDir)
		local tangentSpeed = tangentialVel.Magnitude
		local tangentUnit = if tangentSpeed > 0.001 then tangentialVel / tangentSpeed else Vector3.zero

		local totalDrag = Vector3.zero
		if npc.isIdle then
			if tangentSpeed > 0.001 then
				totalDrag = -tangentUnit * tangentSpeed * STOP_DAMPING
				totalDrag += -tangentUnit * (tangentSpeed ^ 2) * XZ_DRAG
			end
			npc.moveForce.Force = Vector3.zero
			self:_playAnimation(npc, "Idle")
		else
			if tangentSpeed > 0.001 then
				local friction = FLAT_FRICTION * (1.0 - math.exp(-2 * tangentSpeed))
				totalDrag = -tangentUnit * friction
				totalDrag += -tangentUnit * (tangentSpeed ^ 2) * XZ_DRAG
			end
			local counterDrag = (WALK_SPEED ^ 2) * XZ_DRAG
			local counterFriction = FLAT_FRICTION
			npc.moveForce.Force = npc.wanderDir * (counterDrag + counterFriction)
			self:_playAnimation(npc, "Walk")
		end
		npc.dragForce.Force = totalDrag

		self:_updateGround(npc, gravityDir, upDir, dt)
		self:_updateOrientation(npc, upDir)

		hrp.AssemblyAngularVelocity = Vector3.zero
	end
end

function GraviBowNPCController:_updateGround(npc, gravityDir, upDir, dt)
	local hrp = npc.hrp
	local hipHeight = npc.hipHeight
	local freeLengthOfSpring = hipHeight * SPRING_FREE_LENGTH_RATIO
	local rayDir = gravityDir * freeLengthOfSpring

	local hitCount = 0
	local totalHitPos = Vector3.zero
	local totalNormal = Vector3.zero
	local onGround = false

	for _, att in ipairs(npc.rayAttachments) do
		local result = Workspace:Raycast(att.WorldPosition, rayDir, npc.rayParams)
		if result then
			onGround = true
			hitCount += 1
			totalHitPos += result.Position
			totalNormal += result.Normal
		end
	end

	if not onGround then
		npc.springForce.Force = Vector3.zero
		npc.dampingForce.Force = Vector3.zero
		return
	end

	local avgHitPos = totalHitPos / hitCount
	local mass = hrp.AssemblyMass
	local currentHeight = (hrp.Position - avgHitPos):Dot(upDir)
	local targetHeight = hipHeight
	local verticalVel = hrp.AssemblyLinearVelocity:Dot(upDir)

	local upwardForce = self:_calculateSpringForce(targetHeight, currentHeight, verticalVel, mass, dt)

	npc.springForce.Force = upDir * upwardForce
	npc.dampingForce.Force = Vector3.zero
end

function GraviBowNPCController:_calculateSpringForce(targetHeight, currentHeight, verticalVel, mass, dt)
	local gravityAccel = GRAVITY_FORCE
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

function GraviBowNPCController:_updateOrientation(npc, upDir)
	local forward = npc.wanderDir
	if forward.Magnitude < 0.01 then
		forward = upDir:Cross(Vector3.new(0, 0, 1))
		if forward.Magnitude < 0.01 then
			forward = upDir:Cross(Vector3.new(1, 0, 0))
		end
	end

	local projected = forward - upDir * forward:Dot(upDir)
	if projected.Magnitude > 0.001 then
		npc.terrainAttachment.CFrame = CFrame.lookAt(Vector3.zero, projected.Unit, upDir)
	end
end

return GraviBowNPCController
