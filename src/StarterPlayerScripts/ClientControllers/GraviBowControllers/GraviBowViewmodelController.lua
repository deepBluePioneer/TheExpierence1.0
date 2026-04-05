local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage.CustomPackages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local FastCast = require(CustomPackages.FastCastFolder.FastCastRedux)
local partcache = require(Packages.partcache)

local LocalPlayer = Players.LocalPlayer

local DRAW_MAX = 2.5
local DRAW_SPEED = 6
local RETURN_SPEED = 30
local AIM_LERP_SPEED = 10
local AIM_RETURN_SPEED = 25
local STRING_WIDTH = 0.04
local STRING_COLOR = Color3.fromRGB(210, 190, 150)

local BOW_ROTATION = CFrame.Angles(0, math.rad(90), 0)

local REST_OFFSET = CFrame.new(-0.6, -1.0, -1.5)
local AIM_OFFSET = CFrame.new(0, -0.5, -1.5) * CFrame.Angles(0, 0, math.rad(-90))

local ARROW_LENGTH = 3.5
local ARROW_WIDTH = 0.06
local ARROW_COLOR = Color3.fromRGB(139, 90, 43)
local ARROW_TIP_COLOR = Color3.fromRGB(80, 80, 80)
local ARROW_SPEED_MAX = 250
local FLYBY_RANGE = 30
local MIN_DRAW_TO_FIRE = 0.3
local FOV_DRAW_ZOOM = 7
local FOV_TWEEN_IN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FOV_TWEEN_OUT = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local ARROW_LIFETIME = 10
local SPHERE_GRAVITY = 100

local ARC_SEGMENTS = 60
local ARC_TIME_STEP = 0.05
local ARC_WIDTH = 0.35
local ARC_COLOR_START = Color3.fromRGB(255, 220, 120)
local ARC_COLOR_END = Color3.fromRGB(255, 100, 30)
local ARC_LIGHT_EMISSION = 0.6

local PLANET_TAG = "planet"
local CRATER_LIFETIME = 50
local CRATER_RING_COUNT = 16
local CRATER_BASE_RADIUS = 2.35
local CRATER_DEBRIS_COUNT = 14

local HOMING_DURATION = 5
local HOMING_MARK_INTERVAL = 0.4
local HOMING_MAX_TARGETS = 12
local HOMING_FLIGHT_DURATION = 1.6
local HOMING_NOISE_FREQ = 2.5
local HOMING_NOISE_AMP = 10
local HOMING_STAGGER_MAX = 0.15
local HOMING_MARKER_COLOR = Color3.fromRGB(255, 60, 60)

local function cubicBezier(P0, P1, P2, P3, t)
	local u = 1 - t
	return u*u*u*P0 + 3*u*u*t*P1 + 3*u*t*t*P2 + t*t*t*P3
end

local function cubicBezierDeriv(P0, P1, P2, P3, t)
	local u = 1 - t
	return 3*u*u*(P1-P0) + 6*u*t*(P2-P1) + 3*t*t*(P3-P2)
end

local GraviBowViewmodelController = Knit.CreateController({
	Name = "GraviBowViewmodelController",

	ArrowMode = "Normal",
	DrawAmount = 0,
	IsAiming = false,
	IsDrawing = false,

	_trove = nil,
	_bowTrove = nil,
	_aimAlpha = 0,
	_vpCamera = nil,
	_worldModel = nil,
	_viewportFrame = nil,
	_arrowShaft = nil,
	_arrowTip = nil,
	_lastDrawPos = nil,
	_caster = nil,
	_arrowCache = nil,
	_castBehavior = nil,
	_castParams = nil,
	_gravityController = nil,
	_playerService = nil,
	_arcHost = nil,
	_arcAttachments = nil,
	_arcBeams = nil,
	_soundController = nil,
	_drawSound = nil,
	_remoteCaster = nil,
	_remoteArrowCache = nil,
	_craterFolder = nil,
	_fovTween = nil,
	_fovStored = nil,
	_homingTargets = {},
	_homingTimer = 0,
	_homingMarkAccum = 0,
	_isTargeting = false,
	_homingMarkerFolder = nil,
	_homingArrowCache = nil,
	_bowActive = false,
})

function GraviBowViewmodelController:KnitInit()
	self._trove = Trove.new()
	self:_setupFastCast()
end

function GraviBowViewmodelController:_isBowAllowed()
	return self._bowActive
end

function GraviBowViewmodelController:_isInsideHubZone(position)
	local phase = self._matchController and self._matchController.Phase
	if phase ~= "GAME_ACTIVE" and phase ~= "GAME_OVER" then
		return false
	end
	local hubPlanet = self._gravityController:GetHubPlanet()
	if not hubPlanet then return false end
	local zoneRadius = hubPlanet.radius * self._gravityController:GetHubZoneMultiplier()
	return (position - hubPlanet.center).Magnitude < zoneRadius
end

function GraviBowViewmodelController:_getSphereCenter()
	if self._gravityController then
		return self._gravityController:GetSphereCenter()
	end
	return Vector3.zero
end

function GraviBowViewmodelController:_cancelFovTween()
	if self._fovTween then
		self._fovTween:Cancel()
		self._fovTween = nil
	end
end

function GraviBowViewmodelController:_tweenCameraFovTo(targetFov, tweenInfo)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	self:_cancelFovTween()
	self._fovTween = TweenService:Create(cam, tweenInfo, { FieldOfView = targetFov })
	self._fovTween.Completed:Once(function()
		self._fovTween = nil
	end)
	self._fovTween:Play()
end

function GraviBowViewmodelController:_beginDrawFov()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	self._fovStored = cam.FieldOfView
	self:_tweenCameraFovTo(self._fovStored - FOV_DRAW_ZOOM, FOV_TWEEN_IN)
end

function GraviBowViewmodelController:_endDrawFov()
	if self._fovStored == nil then return end
	local restore = self._fovStored
	self._fovStored = nil
	self:_tweenCameraFovTo(restore, FOV_TWEEN_OUT)
end

local function surfaceFrameFromNormal(position, outwardNormal)
	local up = outwardNormal.Unit
	local tangent = up:Cross(Vector3.yAxis)
	if tangent.Magnitude < 1e-3 then
		tangent = up:Cross(Vector3.xAxis)
	end
	tangent = tangent.Unit
	local forward = tangent:Cross(up).Unit
	return CFrame.fromMatrix(position, tangent, up, -forward)
end

function GraviBowViewmodelController:_shouldSpawnArrowCrater(hitInstance)
	if not hitInstance then
		return false
	end
	if hitInstance:IsA("Terrain") then
		return true
	end
	local current = hitInstance
	while current do
		if current:IsA("Model") and CollectionService:HasTag(current, PLANET_TAG) then
			return true
		end
		current = current.Parent
	end
	return false
end

function GraviBowViewmodelController:_spawnArrowImpactCrater(hitPosition, hitNormal, hitPart)
	if not self._craterFolder then return end

	local baseColor = Color3.fromRGB(88, 72, 58)
	if hitPart:IsA("BasePart") then
		baseColor = hitPart.Color:Lerp(Color3.fromRGB(45, 38, 32), 0.4)
	end

	local sunk = hitPosition - hitNormal.Unit * 0.1
	local baseCF = surfaceFrameFromNormal(sunk, hitNormal)

	local model = Instance.new("Model")
	model.Name = "ArrowImpactCrater"
	model.Parent = self._craterFolder

	local function addPitCylinder(name, diameter, thickness, localY, color, material)
		local pit = Instance.new("Part")
		pit.Name = name
		pit.Shape = Enum.PartType.Cylinder
		pit.Size = Vector3.new(thickness, diameter, diameter)
		pit.Color = color
		pit.Material = material
		pit.Anchored = true
		pit.CanCollide = false
		pit.CanQuery = false
		pit.CastShadow = true
		pit.CFrame = baseCF * CFrame.new(0, localY, 0) * CFrame.Angles(0, 0, math.rad(90))
		pit.Parent = model
		return pit
	end

	addPitCylinder("CraterPitOuter", 4.2, 0.16, -0.02, baseColor:Lerp(Color3.fromRGB(55, 46, 38), 0.35), Enum.Material.Sand)
	addPitCylinder("CraterPitMid", 3.0, 0.14, -0.08, baseColor:Lerp(Color3.fromRGB(42, 36, 30), 0.5), Enum.Material.Slate)
	addPitCylinder("CraterPitInner", 1.85, 0.22, -0.16, Color3.fromRGB(28, 24, 21), Enum.Material.Slate)

	local wedgeLayers = {
		{ radiusMul = 0.5, yOff = -0.12, sizeMul = 0.95, tiltDeg = 24, count = CRATER_RING_COUNT },
		{ radiusMul = 0.92, yOff = -0.03, sizeMul = 1.15, tiltDeg = 22, count = CRATER_RING_COUNT },
		{ radiusMul = 1.35, yOff = 0.06, sizeMul = 1.35, tiltDeg = 20, count = CRATER_RING_COUNT },
		{ radiusMul = 1.85, yOff = 0.14, sizeMul = 1.5, tiltDeg = 16, count = 20 },
	}

	local baseWedge = Vector3.new(0.78, 0.28, 0.9)
	for _, layer in ipairs(wedgeLayers) do
		local ringRadius = CRATER_BASE_RADIUS * layer.radiusMul
		local wx = baseWedge.X * layer.sizeMul
		local wy = baseWedge.Y * layer.sizeMul
		local wz = baseWedge.Z * layer.sizeMul
		local count = layer.count
		for i = 1, count do
			local ang = (i / count) * math.pi * 2
			local lx = math.cos(ang) * ringRadius
			local lz = math.sin(ang) * ringRadius
			local rim = Instance.new("WedgePart")
			rim.Name = "CraterRim"
			rim.Size = Vector3.new(wx, wy, wz)
			rim.Color = baseColor:Lerp(Color3.fromRGB(118, 98, 78), ((i + count) % 5) * 0.08)
			rim.Material = Enum.Material.Sand
			rim.Anchored = true
			rim.CanCollide = false
			rim.CanQuery = false
			rim.CastShadow = true
			rim.CFrame = baseCF * CFrame.new(lx, layer.yOff, lz) * CFrame.Angles(0, -ang, math.rad(layer.tiltDeg)) * CFrame.Angles(math.rad(-26), 0, 0)
			rim.Parent = model
		end
	end

	for i = 1, CRATER_DEBRIS_COUNT do
		local ang = math.random() * math.pi * 2
		local radMul = 0.28 + math.random() * 0.72
		local rad = CRATER_BASE_RADIUS * radMul
		local lx = math.cos(ang) * rad
		local lz = math.sin(ang) * rad
		local s = 0.32 + math.random() * 0.38
		local chunk = Instance.new("Part")
		chunk.Name = "CraterDebris"
		chunk.Size = Vector3.new(s, s * 0.65, s * 0.9)
		chunk.Color = baseColor:Lerp(Color3.fromRGB(72, 60, 50), math.random())
		chunk.Material = Enum.Material.Rock
		chunk.Anchored = true
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CastShadow = true
		local lift = 0.05 + math.random() * 0.14
		chunk.CFrame = baseCF * CFrame.new(lx, lift, lz) * CFrame.Angles(math.rad(math.random(-45, 45)), math.rad(math.random(0, 360)), math.rad(math.random(-35, 35)))
		chunk.Parent = model
	end

	task.delay(CRATER_LIFETIME, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

local IMPACT_BURST_COUNT = 12
local IMPACT_BURST_COLOR = Color3.fromRGB(100, 200, 255)
local IMPACT_BURST_SPEED_MIN = 8
local IMPACT_BURST_SPEED_MAX = 20
local IMPACT_BURST_SIZE = 0.4
local IMPACT_BURST_LIFETIME = 0.6

function GraviBowViewmodelController:_spawnHomingImpactBurst(position, normal)
	for _ = 1, IMPACT_BURST_COUNT do
		local sphere = Instance.new("Part")
		sphere.Shape = Enum.PartType.Ball
		sphere.Size = Vector3.one * IMPACT_BURST_SIZE
		sphere.Material = Enum.Material.Neon
		sphere.Color = IMPACT_BURST_COLOR
		sphere.Anchored = false
		sphere.CanCollide = false
		sphere.CanQuery = false
		sphere.CanTouch = false
		sphere.CastShadow = false
		sphere.Position = position

		local dir = (normal + Vector3.new(
			(math.random() - 0.5) * 2,
			(math.random() - 0.5) * 2,
			(math.random() - 0.5) * 2
		)).Unit
		local speed = IMPACT_BURST_SPEED_MIN + math.random() * (IMPACT_BURST_SPEED_MAX - IMPACT_BURST_SPEED_MIN)
		sphere.AssemblyLinearVelocity = dir * speed

		sphere.Parent = Workspace

		TweenService:Create(sphere, TweenInfo.new(IMPACT_BURST_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = Vector3.zero,
			Transparency = 1,
		}):Play()

		task.delay(IMPACT_BURST_LIFETIME + 0.05, function()
			sphere:Destroy()
		end)
	end
end

function GraviBowViewmodelController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._soundController = Knit.GetController("GraviBowSoundController")
	self._cameraController = Knit.GetController("GraviBowCameraController")
	self._crosshairController = Knit.GetController("GraviBowCrosshairController")
	self._matchController = Knit.GetController("GraviBowMatchController")
	self._playerService = Knit.GetService("GraviBowPlayerService")

	local craterFolder = Instance.new("Folder")
	craterFolder.Name = "ArrowImpactCraters"
	craterFolder.Parent = Workspace
	self._trove:Add(craterFolder)
	self._craterFolder = craterFolder

	local markerFolder = Instance.new("Folder")
	markerFolder.Name = "HomingMarkers"
	markerFolder.Parent = Workspace
	self._trove:Add(markerFolder)
	self._homingMarkerFolder = markerFolder


	self:_createViewport()

	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if not self:_isBowAllowed() then return end
		if input.KeyCode == Enum.KeyCode.Q and not self._isTargeting then
			self.ArrowMode = self.ArrowMode == "Normal" and "Homing" or "Normal"
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.IsAiming = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.IsDrawing = true
			if self.IsAiming then
				self:_startDrawSound()
				self:_beginDrawFov()
				if self.ArrowMode == "Homing" then
					self:_beginTargeting()
				end
			end
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.IsAiming = false
			self.IsDrawing = false
			self:_stopDrawSound()
			self:_endDrawFov()
			self:_cancelTargeting()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self.ArrowMode == "Normal" then
				if self.IsAiming and self.DrawAmount >= MIN_DRAW_TO_FIRE then
					if self:_isBowAllowed() then
						self:_fireArrow()
					end
					self.IsAiming = false
				end
			end
			self.IsDrawing = false
			self:_stopDrawSound()
			self:_endDrawFov()
		end
	end), "Disconnect")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end

	self._playerService.ArrowFired:Connect(function(shooter, spawnPos, aimDir, speed, accel)
		self:_onRemoteArrowFired(shooter, spawnPos, aimDir, speed, accel)
	end)

	self._playerService.HomingArrowFired:Connect(function(_shooter, spawnPos, upDir, targetPositions)
		self:_onRemoteHomingSalvo(spawnPos, upDir, targetPositions)
	end)

end

function GraviBowViewmodelController:_onRemoteArrowFired(_shooter, spawnPos, aimDir, speed, accel)
	local remoteParams = RaycastParams.new()
	remoteParams.FilterType = Enum.RaycastFilterType.Exclude
	remoteParams.IgnoreWater = true

	local localChar = LocalPlayer.Character
	local filterList = {}
	if localChar then
		table.insert(filterList, localChar)
	end
	if _shooter and _shooter.Character then
		table.insert(filterList, _shooter.Character)
	end
	local gravityZones = Workspace:FindFirstChild("GravityZones")
	if gravityZones then
		table.insert(filterList, gravityZones)
	end
	local crystalPatches0 = Workspace:FindFirstChild("CrystalPatches")
	if crystalPatches0 then
		table.insert(filterList, crystalPatches0)
	end
	remoteParams.FilterDescendantsInstances = filterList

	local behavior = FastCast.newBehavior()
	behavior.RaycastParams = remoteParams
	behavior.Acceleration = accel
	behavior.MaxDistance = 50000
	behavior.AutoIgnoreContainer = false
	behavior.CosmeticBulletContainer = Workspace
	behavior.CosmeticBulletProvider = self._remoteArrowCache

	local activeCast = self._remoteCaster:Fire(spawnPos, aimDir, speed, behavior)
	activeCast.UserData = {
		trailEnabled = false,
	}

	local bullet = activeCast.RayInfo.CosmeticBulletObject
	if bullet then
		local arrowTrail = bullet:FindFirstChild("ArrowTrail")
		if arrowTrail then
			arrowTrail.Enabled = false
			arrowTrail:Clear()
		end
	end
end

function GraviBowViewmodelController:_onRemoteHomingSalvo(spawnPos, upDir, targetPositions)
	for i, td in ipairs(targetPositions) do
		local delay = math.random() * HOMING_STAGGER_MAX
		task.delay(delay, function()
			local arrow = self._homingArrowCache:GetPart()
			if not arrow then return end

			local P0 = spawnPos
			local P3 = td.position
			local dist = (P3 - P0).Magnitude
			local launchSpread = upDir * (8 + math.random() * 6)
			local tangentSpread = Vector3.new(
				(math.random() - 0.5) * dist * 0.2,
				(math.random() - 0.5) * dist * 0.2,
				(math.random() - 0.5) * dist * 0.2
			)
			local P1 = P0 + (P3 - P0).Unit * (dist * 0.3) + launchSpread + tangentSpread
			local approachNormal = td.normal or upDir
			local P2 = P3 + approachNormal * (dist * 0.25) + Vector3.new(
				(math.random() - 0.5) * dist * 0.1,
				(math.random() - 0.5) * dist * 0.1,
				(math.random() - 0.5) * dist * 0.1
			)

			local seedX = math.random() * 1000
			local seedY = math.random() * 1000

			self:_flyHomingArrow(arrow, P0, P1, P2, P3, HOMING_FLIGHT_DURATION, seedX, seedY, false)
		end)
	end
end

function GraviBowViewmodelController:_setupFastCast()
	FastCast.VisualizeCasts = false

	local arrowTemplate = Instance.new("Part")
	arrowTemplate.Name = "Arrow"
	arrowTemplate.Size = Vector3.new(ARROW_WIDTH, ARROW_WIDTH, ARROW_LENGTH)
	arrowTemplate.Material = Enum.Material.Wood
	arrowTemplate.Color = ARROW_COLOR
	arrowTemplate.Anchored = true
	arrowTemplate.CanCollide = false
	arrowTemplate.CanQuery = false
	arrowTemplate.CanTouch = false

	local tipTemplate = Instance.new("Part")
	tipTemplate.Name = "ArrowTip"
	tipTemplate.Size = Vector3.new(ARROW_WIDTH * 3, ARROW_WIDTH * 3, 0.15)
	tipTemplate.Material = Enum.Material.Metal
	tipTemplate.Color = ARROW_TIP_COLOR
	tipTemplate.Anchored = true
	tipTemplate.CanCollide = false
	tipTemplate.CanQuery = false
	tipTemplate.CanTouch = false
	tipTemplate.Parent = arrowTemplate

	local trailAttach0 = Instance.new("Attachment")
	trailAttach0.Name = "TrailAttach0"
	trailAttach0.Position = Vector3.new(0, 0, -ARROW_LENGTH / 2)
	trailAttach0.Parent = arrowTemplate

	local trailAttach1 = Instance.new("Attachment")
	trailAttach1.Name = "TrailAttach1"
	trailAttach1.Position = Vector3.new(0, 0, ARROW_LENGTH / 2)
	trailAttach1.Parent = arrowTemplate

	local trail = Instance.new("Trail")
	trail.Name = "ArrowTrail"
	trail.Attachment0 = trailAttach0
	trail.Attachment1 = trailAttach1
	trail.Lifetime = 0.8
	trail.MinLength = 0.02
	trail.FaceCamera = true
	trail.LightEmission = 0.5
	trail.LightInfluence = 0
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.4, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.3, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 210, 130)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(240, 150, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 80, 30)),
	})
	trail.Parent = arrowTemplate

	local arrowContainer = Instance.new("Folder")
	arrowContainer.Name = "ArrowCache"
	arrowContainer.Parent = Workspace
	self._trove:Add(arrowContainer)

	self._arrowCache = partcache.new(arrowTemplate, 20, arrowContainer)

	local homingTemplate = arrowTemplate:Clone()
	homingTemplate.Material = Enum.Material.Neon
	homingTemplate.Color = Color3.fromRGB(120, 200, 255)
	local homingTip = homingTemplate:FindFirstChild("ArrowTip")
	if homingTip then
		homingTip.Material = Enum.Material.Neon
		homingTip.Color = Color3.fromRGB(80, 180, 255)
	end

	local pointLight = Instance.new("PointLight")
	pointLight.Range = 8
	pointLight.Brightness = 1.5
	pointLight.Color = Color3.fromRGB(100, 200, 255)
	pointLight.Parent = homingTemplate

	local homingTrail = homingTemplate:FindFirstChild("ArrowTrail")
	if homingTrail then
		homingTrail.Lifetime = 1.0
		homingTrail.LightEmission = 0.8
		homingTrail.LightInfluence = 0
		homingTrail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.3, 0.3),
			NumberSequenceKeypoint.new(0.7, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		homingTrail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.2, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		homingTrail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 200, 255)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(60, 140, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 60, 180)),
		})
	end

	local homingContainer = Instance.new("Folder")
	homingContainer.Name = "HomingArrowCache"
	homingContainer.Parent = Workspace
	self._trove:Add(homingContainer)
	self._homingArrowCache = partcache.new(homingTemplate, 20, homingContainer)

	self._caster = FastCast.new()

	self._caster.LengthChanged:Connect(function(cast, lastPoint, rayDir, displacement, _segmentVelocity, bullet)
		if bullet then
			local newPoint = lastPoint + (rayDir * displacement)
			bullet.CFrame = CFrame.lookAt(newPoint, newPoint + rayDir)
			local tip = bullet:FindFirstChild("ArrowTip")
			if tip then
				tip.CFrame = bullet.CFrame * CFrame.new(0, 0, -ARROW_LENGTH / 2)
			end

			local arrowTrail = bullet:FindFirstChild("ArrowTrail")
			if arrowTrail and not cast.UserData.trailEnabled then
				arrowTrail.Enabled = true
				cast.UserData.trailEnabled = true
			end

			if self:_isInsideHubZone(newPoint) then
				task.defer(cast.Terminate, cast)
				return
			end

			local nearestCenter = self._gravityController:GetNearestPlanetCenter(newPoint)
			local toCenter = nearestCenter - newPoint
			if toCenter.Magnitude > 0.01 then
				cast:SetAcceleration(toCenter.Unit * SPHERE_GRAVITY)
			end

			local flybyTriggered = cast.UserData.flybyTriggered
			for _, player in ipairs(Players:GetPlayers()) do
				if not flybyTriggered[player] and player.Character then
					local charHRP = player.Character:FindFirstChild("HumanoidRootPart")
					if charHRP then
						local dist = (newPoint - charHRP.Position).Magnitude
						if dist < FLYBY_RANGE then
							flybyTriggered[player] = true
							self._soundController:PlayAtPosition("ArrowFlyby", newPoint)
						end
					end
				end
			end
		end
	end)

	self._caster.RayHit:Connect(function(cast, result, _velocity, bullet)
		if result then
			cast.UserData.hit = true

			local hitPos = result.Position
			local hitInstance = result.Instance
			local hitModel = hitInstance:FindFirstAncestorOfClass("Model")
			local hitHumanoid = hitModel and hitModel:FindFirstChildOfClass("Humanoid")

			if hitHumanoid then
				self._soundController:PlayAtPosition("ArrowImpactPlayer", hitPos)

				local victimPlayer = Players:GetPlayerFromCharacter(hitModel)
				if victimPlayer and victimPlayer ~= LocalPlayer then
					self._playerService.ArrowHit:Fire(victimPlayer)
				end
			else
				self._soundController:PlayAtPosition("ArrowImpctGround", hitPos)
				if self:_shouldSpawnArrowCrater(hitInstance) then
					self:_spawnArrowImpactCrater(hitPos, result.Normal, hitInstance)
				end
			end
		end
	end)

	self._caster.CastTerminating:Connect(function(cast)
		local bullet = cast.RayInfo.CosmeticBulletObject
		if not bullet then return end

		local lifetime = (cast.UserData and cast.UserData.hit) and ARROW_LIFETIME or 0
		task.delay(lifetime, function()
			local arrowTrail = bullet:FindFirstChild("ArrowTrail")
			if arrowTrail then
				arrowTrail.Enabled = false
				arrowTrail:Clear()
			end
			pcall(function()
				self._arrowCache:ReturnPart(bullet)
			end)
		end)
	end)

	self._castParams = RaycastParams.new()
	self._castParams.FilterType = Enum.RaycastFilterType.Exclude
	self._castParams.IgnoreWater = true

	local remoteContainer = Instance.new("Folder")
	remoteContainer.Name = "RemoteArrowCache"
	remoteContainer.Parent = Workspace
	self._trove:Add(remoteContainer)

	self._remoteArrowCache = partcache.new(arrowTemplate, 20, remoteContainer)
	self._remoteCaster = FastCast.new()

	self._remoteCaster.LengthChanged:Connect(function(cast, lastPoint, rayDir, displacement, _segmentVelocity, bullet)
		if bullet then
			local newPoint = lastPoint + (rayDir * displacement)
			bullet.CFrame = CFrame.lookAt(newPoint, newPoint + rayDir)
			local tip = bullet:FindFirstChild("ArrowTip")
			if tip then
				tip.CFrame = bullet.CFrame * CFrame.new(0, 0, -ARROW_LENGTH / 2)
			end

			local arrowTrail = bullet:FindFirstChild("ArrowTrail")
			if arrowTrail and not cast.UserData.trailEnabled then
				arrowTrail.Enabled = true
				cast.UserData.trailEnabled = true
			end

			if self:_isInsideHubZone(newPoint) then
				task.defer(cast.Terminate, cast)
				return
			end

			local nearestCenter = self._gravityController:GetNearestPlanetCenter(newPoint)
			local toCenter = nearestCenter - newPoint
			if toCenter.Magnitude > 0.01 then
				cast:SetAcceleration(toCenter.Unit * SPHERE_GRAVITY)
			end
		end
	end)

	self._remoteCaster.CastTerminating:Connect(function(cast)
		local bullet = cast.RayInfo.CosmeticBulletObject
		if bullet and cast.UserData and cast.UserData.hit then
			task.delay(ARROW_LIFETIME, function()
				local arrowTrail = bullet:FindFirstChild("ArrowTrail")
				if arrowTrail then
					arrowTrail.Enabled = false
					arrowTrail:Clear()
				end
				pcall(function()
					self._remoteArrowCache:ReturnPart(bullet)
				end)
			end)
		else
			task.delay(ARROW_LIFETIME, function()
				if bullet then
					local arrowTrail = bullet:FindFirstChild("ArrowTrail")
					if arrowTrail then
						arrowTrail.Enabled = false
						arrowTrail:Clear()
					end
					pcall(function()
						self._remoteArrowCache:ReturnPart(bullet)
					end)
				end
			end)
		end
	end)

	self._remoteCaster.RayHit:Connect(function(cast, result)
		if not result then return end
		cast.UserData.hit = true
		local hitInstance = result.Instance
		local hitModel = hitInstance:FindFirstAncestorOfClass("Model")
		local hitHumanoid = hitModel and hitModel:FindFirstChildOfClass("Humanoid")
		if not hitHumanoid and self:_shouldSpawnArrowCrater(hitInstance) then
			self:_spawnArrowImpactCrater(result.Position, result.Normal, hitInstance)
		end
	end)
end

function GraviBowViewmodelController:_createViewport()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ViewmodelGui"
	screenGui.DisplayOrder = 100
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = LocalPlayer.PlayerGui
	self._trove:Add(screenGui)

	local vpFrame = Instance.new("ViewportFrame")
	vpFrame.Name = "ViewmodelViewport"
	vpFrame.Size = UDim2.fromScale(1, 1)
	vpFrame.Position = UDim2.fromScale(0, 0)
	vpFrame.BackgroundTransparency = 1
	vpFrame.ImageTransparency = 0
	vpFrame.LightDirection = Vector3.new(-1, -1, -1).Unit
	vpFrame.Ambient = Color3.fromRGB(180, 180, 180)
	vpFrame.Parent = screenGui
	self._viewportFrame = vpFrame

	local vpCamera = Instance.new("Camera")
	vpCamera.Parent = vpFrame
	vpFrame.CurrentCamera = vpCamera
	self._vpCamera = vpCamera

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = vpFrame
	self._worldModel = worldModel
end

function GraviBowViewmodelController:ShowBow(toolModel)
	if self._bowActive then return end
	self._bowActive = true

	if toolModel then
		self:_onBowEquipped(toolModel)
		return
	end

	local character = LocalPlayer.Character
	if not character then return end

	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		self:_onBowEquipped(tool)
		return
	end

	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if backpack then
		tool = backpack:FindFirstChildOfClass("Tool")
	end
	if tool then
		self:_onBowEquipped(tool)
	end
end

function GraviBowViewmodelController:HideBow()
	self._bowActive = false
	self:_cleanBow()
	self:_stopDrawSound()
	self:_endDrawFov()
end

function GraviBowViewmodelController:_onCharacterAdded(character)
	self:_cleanBow()
	self._bowActive = false

	local humanoid = character:WaitForChild("Humanoid", 10)

	if humanoid then
		humanoid.Died:Once(function()
			self:_cleanBow()
			self:_stopDrawSound()
			self._bowActive = false
		end)
	end
end

function GraviBowViewmodelController:_cleanBow()
	if self._bowTrove then
		self._bowTrove:Clean()
		self._bowTrove = nil
	end
	self.DrawAmount = 0
	self.IsAiming = false
	self.IsDrawing = false
	self._aimAlpha = 0
	self._arrowShaft = nil
	self._arrowTip = nil
	self._lastDrawPos = nil
	self:_cancelTargeting()
end

function GraviBowViewmodelController:_onBowEquipped(tool)
	self:_cleanBow()
	self._bowTrove = self._trove:Extend()

	task.wait()

	local clone = tool:Clone()
	clone.Parent = self._worldModel
	self._bowTrove:Add(clone)

	local clonedHandle = clone:FindFirstChild("Handle")
	if not clonedHandle then
		warn("[GraviBowViewmodelController] No Handle in cloned tool")
		return
	end
	clonedHandle.Transparency = 1

	local partOffsets = {}
	local handleCF = clonedHandle.CFrame
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			partOffsets[desc] = handleCF:ToObjectSpace(desc.CFrame)
			desc.Anchored = true
			desc.CanCollide = false
		end
	end

	local topAnchor = clone:FindFirstChild("topStringAnchor", true)
	local bottomAnchor = clone:FindFirstChild("bottomStringAnchor", true)

	if topAnchor and topAnchor:IsA("BasePart") then
		topAnchor.Transparency = 1
	end
	if bottomAnchor and bottomAnchor:IsA("BasePart") then
		bottomAnchor.Transparency = 1
	end

	local topStringPart, bottomStringPart
	if topAnchor and bottomAnchor then
		local function makeStringSegment(name)
			local seg = Instance.new("Part")
			seg.Name = name
			seg.Anchored = true
			seg.CanCollide = false
			seg.CanQuery = false
			seg.CanTouch = false
			seg.Material = Enum.Material.SmoothPlastic
			seg.Color = STRING_COLOR
			seg.Size = Vector3.new(STRING_WIDTH, STRING_WIDTH, 1)
			seg.Parent = self._worldModel
			self._bowTrove:Add(seg)
			return seg
		end

		topStringPart = makeStringSegment("TopString")
		bottomStringPart = makeStringSegment("BottomString")
	end

	local arrowShaft = Instance.new("Part")
	arrowShaft.Name = "ArrowShaft"
	arrowShaft.Anchored = true
	arrowShaft.CanCollide = false
	arrowShaft.CanQuery = false
	arrowShaft.CanTouch = false
	arrowShaft.Material = Enum.Material.Wood
	arrowShaft.Color = ARROW_COLOR
	arrowShaft.Size = Vector3.new(ARROW_WIDTH, ARROW_WIDTH, ARROW_LENGTH)
	arrowShaft.Transparency = 1
	arrowShaft.Parent = self._worldModel
	self._bowTrove:Add(arrowShaft)
	self._arrowShaft = arrowShaft

	local arrowTip = Instance.new("Part")
	arrowTip.Name = "ArrowTip"
	arrowTip.Anchored = true
	arrowTip.CanCollide = false
	arrowTip.CanQuery = false
	arrowTip.CanTouch = false
	arrowTip.Material = Enum.Material.Metal
	arrowTip.Color = ARROW_TIP_COLOR
	arrowTip.Size = Vector3.new(ARROW_WIDTH * 3, ARROW_WIDTH * 3, 0.15)
	arrowTip.Transparency = 1
	arrowTip.Parent = self._worldModel
	self._bowTrove:Add(arrowTip)
	self._arrowTip = arrowTip

	local arcHost = Instance.new("Part")
	arcHost.Name = "ArcHost"
	arcHost.Anchored = true
	arcHost.CanCollide = false
	arcHost.CanQuery = false
	arcHost.CanTouch = false
	arcHost.CastShadow = false
	arcHost.Transparency = 1
	arcHost.Size = Vector3.new(1, 1, 1)
	arcHost.Position = Vector3.zero
	arcHost.Parent = Workspace
	self._bowTrove:Add(arcHost)
	self._arcHost = arcHost

	local arcAttachments = {}
	for i = 0, ARC_SEGMENTS do
		local att = Instance.new("Attachment")
		att.Name = "ArcAtt_" .. i
		att.Parent = arcHost
		arcAttachments[i] = att
	end
	self._arcAttachments = arcAttachments

	local arcBeams = {}
	for i = 0, ARC_SEGMENTS - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "ArcBeam_" .. i
		beam.Attachment0 = arcAttachments[i]
		beam.Attachment1 = arcAttachments[i + 1]
		beam.FaceCamera = true
		beam.LightEmission = ARC_LIGHT_EMISSION
		beam.LightInfluence = 0
		beam.Segments = 1
		beam.TextureMode = Enum.TextureMode.Stretch

		local t = i / ARC_SEGMENTS
		beam.Color = ColorSequence.new(ARC_COLOR_START:Lerp(ARC_COLOR_END, t), ARC_COLOR_START:Lerp(ARC_COLOR_END, math.min(t + 1 / ARC_SEGMENTS, 1)))
		beam.Transparency = NumberSequence.new(t * 0.5, math.min(t + 1 / ARC_SEGMENTS, 1) * 0.5 + 0.2)

		local widthStart = ARC_WIDTH * (1 - t * 0.6)
		local widthEnd = ARC_WIDTH * (1 - math.min(t + 1 / ARC_SEGMENTS, 1) * 0.6)
		beam.Width0 = widthStart
		beam.Width1 = widthEnd

		beam.Enabled = false
		beam.Parent = arcHost
		arcBeams[i] = beam
	end
	self._arcBeams = arcBeams

	self.DrawAmount = 0
	self._aimAlpha = 0

	local RENDER_NAME = "GraviBowViewmodel"
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 10, function(dt)
		local worldCam = Workspace.CurrentCamera
		if not worldCam then return end

		self._vpCamera.CFrame = worldCam.CFrame
		self._vpCamera.FieldOfView = worldCam.FieldOfView

		local targetAim = self.IsAiming and 1 or 0
		local lerpSpeed = targetAim == 1 and AIM_LERP_SPEED or AIM_RETURN_SPEED
		self._aimAlpha = self._aimAlpha + (targetAim - self._aimAlpha) * math.clamp(lerpSpeed * dt, 0, 1)

		if self.IsAiming and self.IsDrawing then
			self.DrawAmount = math.min(self.DrawAmount + DRAW_SPEED * dt, DRAW_MAX)
		else
			self.DrawAmount = math.max(self.DrawAmount - RETURN_SPEED * dt, 0)
		end

		local bowOffset = REST_OFFSET:Lerp(AIM_OFFSET, self._aimAlpha)
		local newHandleCF = worldCam.CFrame * bowOffset * BOW_ROTATION

		for part, offset in pairs(partOffsets) do
			part.CFrame = newHandleCF * offset
		end

		local drawPos
		if topAnchor and bottomAnchor then
			local topPos = topAnchor.Position
			local bottomPos = bottomAnchor.Position
			local restPos = (topPos + bottomPos) / 2

			local drawDir = -worldCam.CFrame.LookVector
			drawPos = restPos + drawDir * self.DrawAmount

			if topStringPart and bottomStringPart then
				local function placeSegment(seg, from, to)
					local mid = (from + to) / 2
					local dist = (to - from).Magnitude
					if dist < 0.001 then return end
					seg.Size = Vector3.new(STRING_WIDTH, STRING_WIDTH, dist)
					seg.CFrame = CFrame.lookAt(mid, to)
				end

				placeSegment(topStringPart, topPos, drawPos)
				placeSegment(bottomStringPart, drawPos, bottomPos)
			end
		end

		local showArrow = self.IsAiming and self._aimAlpha > 0.5
		local arrowAlpha = showArrow and 0 or 1
		arrowShaft.Transparency = arrowAlpha
		arrowTip.Transparency = arrowAlpha

		if showArrow and drawPos then
			self._lastDrawPos = drawPos
			local aimDir = worldCam.CFrame.LookVector
			local nockPos = drawPos
			local arrowCenter = nockPos + aimDir * (ARROW_LENGTH / 2)
			local arrowCF = CFrame.lookAt(arrowCenter, arrowCenter + aimDir)

			arrowShaft.CFrame = arrowCF
			arrowTip.CFrame = CFrame.lookAt(nockPos + aimDir * ARROW_LENGTH, nockPos + aimDir * (ARROW_LENGTH + 0.1))
		end

		self:_updateTargeting(dt)

		local showArc = self.IsAiming and self.IsDrawing and self.DrawAmount >= MIN_DRAW_TO_FIRE and self.ArrowMode == "Normal"
		local arcAtts = self._arcAttachments
		local arcBeams = self._arcBeams
		if showArc then
			local character = LocalPlayer.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local aimDir = worldCam.CFrame.LookVector
				local speed = (self.DrawAmount / DRAW_MAX) * ARROW_SPEED_MAX
				local pos = hrp.Position + aimDir * 4
				local vel = aimDir * speed
				local castParams = RaycastParams.new()
				castParams.FilterType = Enum.RaycastFilterType.Exclude
				local arcFilterList = {character, self._arcHost}
				local gzFolder = Workspace:FindFirstChild("GravityZones")
				if gzFolder then
					table.insert(arcFilterList, gzFolder)
				end
				local cpFolder = Workspace:FindFirstChild("CrystalPatches")
				if cpFolder then
					table.insert(arcFilterList, cpFolder)
				end
				castParams.FilterDescendantsInstances = arcFilterList

				arcAtts[0].WorldPosition = pos
				local lastActive = -1

				for i = 1, ARC_SEGMENTS do
					local center = self._gravityController:GetNearestPlanetCenter(pos)
					local toCenter = center - pos
					local accel = toCenter.Magnitude > 0.01 and toCenter.Unit * SPHERE_GRAVITY or Vector3.zero
					vel = vel + accel * ARC_TIME_STEP
					local nextPos = pos + vel * ARC_TIME_STEP

					local ray = Workspace:Raycast(pos, nextPos - pos, castParams)
					if ray then
						arcAtts[i].WorldPosition = ray.Position
						lastActive = i
						break
					end

					arcAtts[i].WorldPosition = nextPos
					lastActive = i
					pos = nextPos
				end

				for i = 0, ARC_SEGMENTS - 1 do
					arcBeams[i].Enabled = (i < lastActive)
				end
			else
				for i = 0, ARC_SEGMENTS - 1 do
					arcBeams[i].Enabled = false
				end
			end
		else
			for i = 0, ARC_SEGMENTS - 1 do
				arcBeams[i].Enabled = false
			end
		end
	end)
	self._bowTrove:Add(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)

end

function GraviBowViewmodelController:_beginTargeting()
	self._homingTargets = {}
	self._homingTimer = HOMING_DURATION
	self._homingMarkAccum = HOMING_MARK_INTERVAL
	self._isTargeting = true
	if self._homingMarkerFolder then
		self._homingMarkerFolder:ClearAllChildren()
	end
end

function GraviBowViewmodelController:_cancelTargeting()
	if not self._isTargeting then return end
	self._isTargeting = false
	self._homingTargets = {}
	self._homingTimer = 0
	if self._homingMarkerFolder then
		self._homingMarkerFolder:ClearAllChildren()
	end
end

function GraviBowViewmodelController:_spawnTargetMarker(position, index)
	if not self._homingMarkerFolder then return end

	local part = Instance.new("Part")
	part.Name = "TargetMarker_" .. index
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Position = position
	part.Parent = self._homingMarkerFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MarkerGui"
	billboard.Size = UDim2.fromOffset(48, 48)
	billboard.AlwaysOnTop = true
	billboard.Adornee = part
	billboard.Parent = part

	local diamond = Instance.new("TextLabel")
	diamond.Name = "Diamond"
	diamond.Size = UDim2.fromScale(1, 1)
	diamond.BackgroundTransparency = 1
	diamond.Text = "\u{25C7}"
	diamond.TextColor3 = HOMING_MARKER_COLOR
	diamond.TextSize = 36
	diamond.Font = Enum.Font.GothamBold
	diamond.TextStrokeTransparency = 0.4
	diamond.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	diamond.Parent = billboard

	local indexLabel = Instance.new("TextLabel")
	indexLabel.Name = "Index"
	indexLabel.Size = UDim2.fromScale(1, 1)
	indexLabel.BackgroundTransparency = 1
	indexLabel.Text = tostring(index)
	indexLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	indexLabel.TextSize = 14
	indexLabel.Font = Enum.Font.GothamBold
	indexLabel.Parent = billboard

	local spawnSize = UDim2.fromOffset(80, 80)
	billboard.Size = spawnSize
	TweenService:Create(billboard, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(48, 48),
	}):Play()

	task.spawn(function()
		while part.Parent do
			TweenService:Create(billboard, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = UDim2.fromOffset(54, 54),
			}):Play()
			task.wait(0.5)
			if not part.Parent then break end
			TweenService:Create(billboard, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = UDim2.fromOffset(44, 44),
			}):Play()
			task.wait(0.5)
		end
	end)

end

function GraviBowViewmodelController:_updateTargeting(dt)
	if not self._isTargeting then return end

	self._homingTimer = self._homingTimer - dt
	self._homingMarkAccum = self._homingMarkAccum + dt

	if self._homingMarkAccum >= HOMING_MARK_INTERVAL and #self._homingTargets < HOMING_MAX_TARGETS then
		self._homingMarkAccum = 0

		local cam = Workspace.CurrentCamera
		if cam then
			local character = LocalPlayer.Character
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			local filterList = {}
			if character then
				table.insert(filterList, character)
			end
			local gzFolder = Workspace:FindFirstChild("GravityZones")
			if gzFolder then
				table.insert(filterList, gzFolder)
			end
			local cpFolder1 = Workspace:FindFirstChild("CrystalPatches")
			if cpFolder1 then
				table.insert(filterList, cpFolder1)
			end
			if self._homingMarkerFolder then
				table.insert(filterList, self._homingMarkerFolder)
			end
			rayParams.FilterDescendantsInstances = filterList

			local origin = cam.CFrame.Position
			local direction = cam.CFrame.LookVector * 1000
			local result = Workspace:Raycast(origin, direction, rayParams)
			if result then
				local targetData = {
					position = result.Position,
					normal = result.Normal,
					part = result.Instance,
				}
				table.insert(self._homingTargets, targetData)
				self:_spawnTargetMarker(result.Position, #self._homingTargets)
			end
		end
	end

	if self._homingTimer <= 0 then
		self._isTargeting = false
		if #self._homingTargets > 0 then
			self:_fireHomingSalvo()
		end
		self.IsDrawing = false
		self:_stopDrawSound()
		self:_endDrawFov()
		self.DrawAmount = 0
	end
end

function GraviBowViewmodelController:_flyHomingArrow(arrow, P0, P1, P2, P3, duration, seedX, seedY, isLocal)
	local prevTangent = (P1 - P0).Unit
	local perp = prevTangent:Cross(Vector3.yAxis)
	if perp.Magnitude < 1e-4 then
		perp = prevTangent:Cross(Vector3.xAxis)
	end
	local prevNormal = perp.Unit
	local prevPos = P0

	local arrowTrail = arrow:FindFirstChild("ArrowTrail")
	if arrowTrail then
		arrowTrail.Enabled = false
		arrowTrail:Clear()
	end

	local startTime = os.clock()

	local heartbeatConn
	heartbeatConn = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		local t = math.clamp(elapsed / duration, 0, 1)

		local basePos = cubicBezier(P0, P1, P2, P3, t)
		local rawDeriv = cubicBezierDeriv(P0, P1, P2, P3, t)
		local tangent = rawDeriv.Magnitude > 1e-4 and rawDeriv.Unit or prevTangent

		local v1 = basePos - prevPos
		local c1 = v1:Dot(v1)
		if c1 > 1e-8 then
			local n0_l = prevNormal - (2 / c1) * v1:Dot(prevNormal) * v1
			local t0_l = prevTangent - (2 / c1) * v1:Dot(prevTangent) * v1
			local v2 = tangent - t0_l
			local c2 = v2:Dot(v2)
			if c2 > 1e-8 then
				prevNormal = n0_l - (2 / c2) * v2:Dot(n0_l) * v2
			end
		end

		prevTangent = tangent
		prevPos = basePos

		local frameRight = tangent:Cross(prevNormal)
		if frameRight.Magnitude < 1e-4 then
			frameRight = tangent:Cross(Vector3.yAxis)
			if frameRight.Magnitude < 1e-4 then
				frameRight = tangent:Cross(Vector3.xAxis)
			end
		end
		frameRight = frameRight.Unit
		local frameUp = frameRight:Cross(tangent).Unit

		local envelope = 1 - (1 - 2 * t) * (1 - 2 * t)
		local noiseX = HOMING_NOISE_AMP * envelope * math.noise(seedX, HOMING_NOISE_FREQ * elapsed)
		local noiseY = HOMING_NOISE_AMP * envelope * math.noise(seedY, HOMING_NOISE_FREQ * elapsed)
		local finalPos = basePos + frameRight * noiseX + frameUp * noiseY

		if self:_isInsideHubZone(finalPos) then
			heartbeatConn:Disconnect()
			if arrowTrail then
				arrowTrail.Enabled = false
				arrowTrail:Clear()
			end
			pcall(function()
				self._homingArrowCache:ReturnPart(arrow)
			end)
			return
		end

		arrow.CFrame = CFrame.lookAt(finalPos, finalPos + tangent)
		local tip = arrow:FindFirstChild("ArrowTip")
		if tip then
			tip.CFrame = arrow.CFrame * CFrame.new(0, 0, -ARROW_LENGTH / 2)
		end

		if arrowTrail and not arrowTrail.Enabled and t > 0.02 then
			arrowTrail.Enabled = true
		end

		if t >= 1 then
			heartbeatConn:Disconnect()

			local hitParams = RaycastParams.new()
			hitParams.FilterType = Enum.RaycastFilterType.Exclude
			local filterList = {}
			local character = LocalPlayer.Character
			if character then
				table.insert(filterList, character)
			end
			local gzFolder = Workspace:FindFirstChild("GravityZones")
			if gzFolder then
				table.insert(filterList, gzFolder)
			end
			local cpFolder2 = Workspace:FindFirstChild("CrystalPatches")
			if cpFolder2 then
				table.insert(filterList, cpFolder2)
			end
			hitParams.FilterDescendantsInstances = filterList

			local impactDir = tangent * 4
			local rayResult = Workspace:Raycast(finalPos - tangent * 2, impactDir, hitParams)
			if rayResult then
				local hitInstance = rayResult.Instance
				local hitModel = hitInstance:FindFirstAncestorOfClass("Model")
				local hitHumanoid = hitModel and hitModel:FindFirstChildOfClass("Humanoid")

			if hitHumanoid then
				self._soundController:PlayAtPosition("ArrowImpactPlayer", rayResult.Position)
				if isLocal then
					local victimPlayer = Players:GetPlayerFromCharacter(hitModel)
					if victimPlayer and victimPlayer ~= LocalPlayer then
						self._playerService.ArrowHit:Fire(victimPlayer)
					end
				end
			else
					self._soundController:PlayAtPosition("ArrowImpctGround", rayResult.Position)
					if self:_shouldSpawnArrowCrater(hitInstance) then
						self:_spawnArrowImpactCrater(rayResult.Position, rayResult.Normal, hitInstance)
					end
					self:_spawnHomingImpactBurst(rayResult.Position, rayResult.Normal)
				end

				task.delay(ARROW_LIFETIME, function()
					if arrowTrail then
						arrowTrail.Enabled = false
						arrowTrail:Clear()
					end
					pcall(function()
						self._homingArrowCache:ReturnPart(arrow)
					end)
				end)
			else
				if arrowTrail then
					arrowTrail.Enabled = false
					arrowTrail:Clear()
				end
				pcall(function()
					self._homingArrowCache:ReturnPart(arrow)
				end)
			end
		end
	end)
end

function GraviBowViewmodelController:_fireHomingSalvo()
	local character = LocalPlayer.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local gravityDir = self._gravityController.GravityDirection
	local upDir = -gravityDir

	local worldCam = Workspace.CurrentCamera
	local aimDir = worldCam and worldCam.CFrame.LookVector or hrp.CFrame.LookVector
	local spawnPos
	if self._lastDrawPos then
		spawnPos = self._lastDrawPos + aimDir * ARROW_LENGTH
	else
		spawnPos = hrp.Position + aimDir * 4
	end

	local targets = self._homingTargets
	local targetPositions = {}
	for _, td in ipairs(targets) do
		table.insert(targetPositions, { position = td.position, normal = td.normal })
	end

	self._playerService.HomingArrowFired:Fire(spawnPos, upDir, targetPositions)

	self._cameraController:TriggerShake(0.6, 0.4)
	self._crosshairController:FlashSalvo()

	local camRight = worldCam and worldCam.CFrame.RightVector or Vector3.xAxis
	local totalTargets = #targets

	for i, targetData in ipairs(targets) do
		local stagger = math.random() * HOMING_STAGGER_MAX
		task.delay(stagger, function()
			local arrow = self._homingArrowCache:GetPart()
			if not arrow then return end

			local currentUp = -self._gravityController.GravityDirection
			local cam = Workspace.CurrentCamera
			local currentAim = cam and cam.CFrame.LookVector or hrp.CFrame.LookVector
			local currentRight = cam and cam.CFrame.RightVector or camRight
			local P0
			if self._lastDrawPos then
				P0 = self._lastDrawPos + currentAim * ARROW_LENGTH
			else
				P0 = hrp.Position + currentAim * 4
			end

			local fanT = totalTargets > 1 and ((i - 1) / (totalTargets - 1) - 0.5) * 2 or 0
			P0 = P0 + currentRight * fanT * 1.8

			local P3 = targetData.position
			local dist = (P3 - P0).Magnitude
			local launchSpread = currentUp * (8 + math.random() * 6)
			local tangentSpread = Vector3.new(
				(math.random() - 0.5) * dist * 0.2,
				(math.random() - 0.5) * dist * 0.2,
				(math.random() - 0.5) * dist * 0.2
			)
			local P1 = P0 + (P3 - P0).Unit * (dist * 0.3) + launchSpread + tangentSpread
			local approachNormal = targetData.normal or currentUp
			local P2 = P3 + approachNormal * (dist * 0.25) + Vector3.new(
				(math.random() - 0.5) * dist * 0.1,
				(math.random() - 0.5) * dist * 0.1,
				(math.random() - 0.5) * dist * 0.1
			)

			local seedX = math.random() * 1000
			local seedY = math.random() * 1000

			self._soundController:PlayGlobal("ArrowRelease")
			self:_flyHomingArrow(arrow, P0, P1, P2, P3, HOMING_FLIGHT_DURATION, seedX, seedY, true)
		end)
	end

	self._homingTargets = {}
	if self._homingMarkerFolder then
		task.delay(0.5, function()
			if self._homingMarkerFolder then
				self._homingMarkerFolder:ClearAllChildren()
			end
		end)
	end
end

function GraviBowViewmodelController:_fireArrow()
	local worldCam = Workspace.CurrentCamera
	if not worldCam then return end

	local character = LocalPlayer.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local aimDir = worldCam.CFrame.LookVector
	local speed = (self.DrawAmount / DRAW_MAX) * ARROW_SPEED_MAX
	local spawnPos = hrp.Position + aimDir * 4

	local gravityZones = Workspace:FindFirstChild("GravityZones")
	local filterList = {character}
	if gravityZones then
		table.insert(filterList, gravityZones)
	end
	local crystalPatches3 = Workspace:FindFirstChild("CrystalPatches")
	if crystalPatches3 then
		table.insert(filterList, crystalPatches3)
	end
	self._castParams.FilterDescendantsInstances = filterList

	local nearestCenter = self._gravityController:GetNearestPlanetCenter(spawnPos)
	local toCenter = nearestCenter - spawnPos
	local initialAccel = toCenter.Magnitude > 0.01 and toCenter.Unit * SPHERE_GRAVITY or Vector3.zero

	local behavior = FastCast.newBehavior()
	behavior.RaycastParams = self._castParams
	behavior.Acceleration = initialAccel
	behavior.MaxDistance = 50000
	behavior.AutoIgnoreContainer = false
	behavior.CosmeticBulletContainer = Workspace
	behavior.CosmeticBulletProvider = self._arrowCache

	self._soundController:PlayGlobal("ArrowRelease")

	self._playerService.ArrowFired:Fire(spawnPos, aimDir, speed, initialAccel)

	local activeCast = self._caster:Fire(spawnPos, aimDir, speed, behavior)
	activeCast.UserData = {
		trailEnabled = false,
		flybyTriggered = { [LocalPlayer] = true },
	}

	local bullet = activeCast.RayInfo.CosmeticBulletObject
	if bullet then
		local arrowTrail = bullet:FindFirstChild("ArrowTrail")
		if arrowTrail then
			arrowTrail.Enabled = false
			arrowTrail:Clear()
		end
	end

	self.DrawAmount = 0

end

function GraviBowViewmodelController:_startDrawSound()
	self:_stopDrawSound()
	self._drawSound = self._soundController:PlayGlobal("StringPullBack")
end

function GraviBowViewmodelController:_stopDrawSound()
	if self._drawSound then
		self._drawSound:Stop()
		self._drawSound:Destroy()
		self._drawSound = nil
	end
end

return GraviBowViewmodelController
