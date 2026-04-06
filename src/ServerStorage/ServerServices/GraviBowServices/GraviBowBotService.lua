local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local BOT_TAG = "GraviBot"
local BOT_COUNT = 5
local GRAVITY_FORCE = 40
local MOVE_SPEED = 28
local STEER_STRENGTH = 14
local WANDER_TIME_MIN = 2
local WANDER_TIME_MAX = 5
local DROP_HEIGHT = 50

local BODY_COLOR = Color3.fromRGB(200, 120, 80)
local HEAD_COLOR = Color3.fromRGB(220, 160, 120)

local GraviBowBotService = Knit.CreateService({
	Name = "GraviBowBotService",
	Client = {},

	_trove = nil,
	_bots = {},
	_botFolder = nil,
	_heartbeatConn = nil,
})

function GraviBowBotService:KnitInit()
	self._trove = Trove.new()
end

function GraviBowBotService:KnitStart()
	self._terrainService = Knit.GetService("GraviBowTerrainService")
	local planet = self._terrainService:CreateSharedPlanet()
	if not planet then
		warn("[GraviBowBotService] No shared planet; bots not spawned")
		return
	end

	self._botFolder = Instance.new("Folder")
	self._botFolder.Name = "GraviBots"
	self._botFolder.Parent = Workspace

	for i = 1, BOT_COUNT do
		self:_spawnBot(i, planet)
	end
	print("[GraviBowBotService] Spawned", BOT_COUNT, "bots on planet surface")

	self._heartbeatConn = RunService.Heartbeat:Connect(function()
		self:_updateBots()
	end)
	self._trove:Add(self._heartbeatConn, "Disconnect")
end

function GraviBowBotService:_randomTangent(radial)
	local rand = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	local t = rand - radial * rand:Dot(radial)
	if t.Magnitude < 0.01 then
		t = radial:Cross(Vector3.new(0, 1, 0))
	end
	return t.Unit
end

function GraviBowBotService:_getMass(character)
	local m = 0
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and not d.Massless then
			m += d:GetMass()
		end
	end
	return math.max(m, 0.1)
end

function GraviBowBotService:_setFriction(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 0)
		end
	end
end

function GraviBowBotService:_surfaceSpawnPosition(center, radialOut, planet)
	local noiseAmp = planet.noiseAmplitude or 20
	local rayStartDist = planet.radius + noiseAmp + 100
	local origin = center + radialOut * rayStartDist
	local cast = (center - origin).Unit * (rayStartDist + 250)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	if self._botFolder then
		table.insert(exclude, self._botFolder)
	end
	local snakeBodies = Workspace:FindFirstChild("SnakeBodies")
	if snakeBodies then
		table.insert(exclude, snakeBodies)
	end
	rayParams.FilterDescendantsInstances = exclude

	local result = Workspace:Raycast(origin, cast, rayParams)
	if result then
		return result.Position + result.Normal * 4
	end

	return center + radialOut * (planet.radius + DROP_HEIGHT)
end

function GraviBowBotService:_spawnBot(index, planet)
	local center = planet.center

	local angle = math.random() * math.pi * 2
	local phi = math.acos(2 * math.random() - 1)
	local radial = Vector3.new(
		math.sin(phi) * math.cos(angle),
		math.cos(phi),
		math.sin(phi) * math.sin(angle)
	).Unit

	local spawnPos = self:_surfaceSpawnPosition(center, radial, planet)

	local model = Instance.new("Model")
	model.Name = "GraviBot_" .. index

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Color = BODY_COLOR
	hrp.Material = Enum.Material.SmoothPlastic
	hrp.CanCollide = true
	hrp.Anchored = false
	hrp.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.Parent = model

	model.PrimaryPart = hrp

	for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
		if state ~= Enum.HumanoidStateType.None then
			pcall(function()
				humanoid:SetStateEnabled(state, false)
			end)
		end
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)

	local lookDir = self:_randomTangent(radial)
	hrp.CFrame = CFrame.lookAt(spawnPos, spawnPos + lookDir, radial)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = HEAD_COLOR
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = true
	head.Parent = model
	head.CFrame = hrp.CFrame * CFrame.new(0, 1.5, 0)

	local neck = Instance.new("WeldConstraint")
	neck.Part0 = hrp
	neck.Part1 = head
	neck.Parent = hrp

	self:_setFriction(model)

	local gravAtt = Instance.new("Attachment")
	gravAtt.Name = "GravityAttachment"
	gravAtt.Parent = hrp

	local gravForce = Instance.new("VectorForce")
	gravForce.Name = "GravityForce"
	gravForce.Attachment0 = gravAtt
	gravForce.RelativeTo = Enum.ActuatorRelativeTo.World
	gravForce.ApplyAtCenterOfMass = true
	gravForce.Force = Vector3.zero
	gravForce.Parent = hrp

	local moveForce = Instance.new("VectorForce")
	moveForce.Name = "MovementForce"
	moveForce.Attachment0 = gravAtt
	moveForce.RelativeTo = Enum.ActuatorRelativeTo.World
	moveForce.ApplyAtCenterOfMass = true
	moveForce.Force = Vector3.zero
	moveForce.Parent = hrp

	local alignAtt = Instance.new("Attachment")
	alignAtt.Name = "AlignAtt"
	alignAtt.Parent = hrp

	local alignOri = Instance.new("AlignOrientation")
	alignOri.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOri.Attachment0 = alignAtt
	alignOri.MaxTorque = 400000
	alignOri.Responsiveness = 25
	alignOri.Parent = hrp

	model:SetAttribute("BotId", HttpService:GenerateGUID(false))
	model.Parent = self._botFolder
	CollectionService:AddTag(model, BOT_TAG)

	local mass = self:_getMass(model)
	local wanderDir = self:_randomTangent(radial)

	table.insert(self._bots, {
		model = model,
		hrp = hrp,
		humanoid = humanoid,
		gravForce = gravForce,
		moveForce = moveForce,
		alignOri = alignOri,
		mass = mass,
		wanderDir = wanderDir,
		nextTurn = os.clock() + math.random() * (WANDER_TIME_MAX - WANDER_TIME_MIN) + WANDER_TIME_MIN,
	})
end

function GraviBowBotService:_updateBots()
	local planet = self._terrainService:GetSharedPlanet()
	if not planet then
		return
	end
	local center = planet.center

	for _, bot in ipairs(self._bots) do
		local model = bot.model
		if not model.Parent or not bot.humanoid or bot.humanoid.Health <= 0 then
			continue
		end

		local hrp = bot.hrp
		if not hrp.Parent then
			continue
		end

		local toCenter = center - hrp.Position
		if toCenter.Magnitude < 0.1 then
			continue
		end

		local radialIn = toCenter.Unit
		local radialOut = -radialIn

		if os.clock() >= bot.nextTurn then
			bot.wanderDir = self:_randomTangent(radialOut)
			bot.nextTurn = os.clock() + math.random() * (WANDER_TIME_MAX - WANDER_TIME_MIN) + WANDER_TIME_MIN
		end

		local desired = bot.wanderDir * MOVE_SPEED
		local vel = hrp.AssemblyLinearVelocity
		local tangential = vel - radialIn * vel:Dot(radialIn)
		local steer = (desired - tangential) * STEER_STRENGTH
		bot.gravForce.Force = radialIn * GRAVITY_FORCE * bot.mass
		bot.moveForce.Force = steer * bot.mass

		local forward = bot.wanderDir
		if forward.Magnitude < 0.01 then
			forward = radialOut:Cross(Vector3.new(0, 1, 0))
		end
		local right = forward:Cross(radialOut)
		if right.Magnitude < 0.01 then
			right = forward:Cross(Vector3.new(1, 0, 0))
		end
		right = right.Unit
		local up = right:Cross(forward).Unit
		bot.alignOri.CFrame = CFrame.fromMatrix(Vector3.zero, right, up, -forward)
	end
end

return GraviBowBotService
