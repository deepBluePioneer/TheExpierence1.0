local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local ARROW_LIFETIME = 10
local SPHERE_GRAVITY = 100

local ARC_POINTS = 150
local ARC_TIME_STEP = 0.05
local ARC_DOT_SIZE = 0.2
local ARC_COLOR = Color3.fromRGB(255, 200, 100)

local GraviBowViewmodelController = Knit.CreateController({
	Name = "GraviBowViewmodelController",

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
	_arcDots = nil,
	_soundController = nil,
	_drawSound = nil,
	_remoteCaster = nil,
	_remoteArrowCache = nil,
})

function GraviBowViewmodelController:KnitInit()
	self._trove = Trove.new()
	self:_setupFastCast()
end

function GraviBowViewmodelController:_getSphereCenter()
	if self._gravityController then
		return self._gravityController:GetSphereCenter()
	end
	return Vector3.zero
end

function GraviBowViewmodelController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._soundController = Knit.GetController("GraviBowSoundController")
	self._playerService = Knit.GetService("GraviBowPlayerService")

	self:_createViewport()

	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.IsAiming = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.IsDrawing = true
			if self.IsAiming then
				self:_startDrawSound()
			end
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.IsAiming = false
			self.IsDrawing = false
			self:_stopDrawSound()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self.IsAiming and self.DrawAmount >= MIN_DRAW_TO_FIRE then
				self:_fireArrow()
				self.IsAiming = false
			end
			self.IsDrawing = false
			self:_stopDrawSound()
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
	remoteParams.FilterDescendantsInstances = filterList

	local behavior = FastCast.newBehavior()
	behavior.RaycastParams = remoteParams
	behavior.Acceleration = accel
	behavior.MaxDistance = 1000
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
	trail.Lifetime = 1.2
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.3
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 50)),
	})
	trail.Parent = arrowTemplate

	local arrowContainer = Instance.new("Folder")
	arrowContainer.Name = "ArrowCache"
	arrowContainer.Parent = Workspace
	self._trove:Add(arrowContainer)

	self._arrowCache = partcache.new(arrowTemplate, 20, arrowContainer)

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

			local sphereCenter = self:_getSphereCenter()
			local toCenter = sphereCenter - newPoint
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
			end
		end
	end)

	self._caster.CastTerminating:Connect(function(cast)
		local bullet = cast.RayInfo.CosmeticBulletObject
		if bullet and cast.UserData and cast.UserData.hit then
			task.delay(ARROW_LIFETIME, function()
				local arrowTrail = bullet:FindFirstChild("ArrowTrail")
				if arrowTrail then
					arrowTrail.Enabled = false
					arrowTrail:Clear()
				end
				pcall(function()
					self._arrowCache:ReturnPart(bullet)
				end)
			end)
		end
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

			local sphereCenter = self:_getSphereCenter()
			local toCenter = sphereCenter - newPoint
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
		if result then
			cast.UserData.hit = true
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

function GraviBowViewmodelController:_onCharacterAdded(character)
	self:_cleanBow()

	local humanoid = character:WaitForChild("Humanoid", 10)

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			task.defer(function()
				self:_onBowEquipped(child)
			end)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			self:_cleanBow()
		end
	end)

	if humanoid then
		humanoid.Died:Once(function()
			self:_cleanBow()
			self:_stopDrawSound()
		end)
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			self:_onBowEquipped(child)
			break
		end
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

	local arcDots = {}
	for i = 1, ARC_POINTS do
		local dot = Instance.new("Part")
		dot.Name = "ArcDot_" .. i
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.new(ARC_DOT_SIZE, ARC_DOT_SIZE, ARC_DOT_SIZE)
		dot.Material = Enum.Material.Neon
		dot.Color = ARC_COLOR
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanQuery = false
		dot.CanTouch = false
		dot.CastShadow = false
		dot.Transparency = 1
		dot.Parent = Workspace
		self._bowTrove:Add(dot)
		arcDots[i] = dot
	end
	self._arcDots = arcDots

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

		local showArc = self.IsAiming and self.IsDrawing and self.DrawAmount >= MIN_DRAW_TO_FIRE
		if showArc then
			local character = LocalPlayer.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local aimDir = worldCam.CFrame.LookVector
				local speed = (self.DrawAmount / DRAW_MAX) * ARROW_SPEED_MAX
				local pos = hrp.Position + aimDir * 4
				local vel = aimDir * speed
				local center = self:_getSphereCenter()

				local castParams = RaycastParams.new()
				castParams.FilterType = Enum.RaycastFilterType.Exclude
				castParams.FilterDescendantsInstances = {character}

				local hitIndex = ARC_POINTS
				for i = 1, ARC_POINTS do
					local toCenter = center - pos
					local accel = toCenter.Magnitude > 0.01 and toCenter.Unit * SPHERE_GRAVITY or Vector3.zero
					vel = vel + accel * ARC_TIME_STEP
					local nextPos = pos + vel * ARC_TIME_STEP

					local ray = Workspace:Raycast(pos, nextPos - pos, castParams)
					if ray then
						arcDots[i].Position = ray.Position
						arcDots[i].Transparency = 0
						hitIndex = i
						break
					end

					arcDots[i].Position = nextPos
					arcDots[i].Transparency = 0
					pos = nextPos
				end

				for i = hitIndex + 1, ARC_POINTS do
					arcDots[i].Transparency = 1
				end
			end
		else
			for i = 1, ARC_POINTS do
				arcDots[i].Transparency = 1
			end
		end
	end)
	self._bowTrove:Add(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)

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

	self._castParams.FilterDescendantsInstances = {character}

	local toCenter = self:_getSphereCenter() - spawnPos
	local initialAccel = toCenter.Magnitude > 0.01 and toCenter.Unit * SPHERE_GRAVITY or Vector3.zero

	local behavior = FastCast.newBehavior()
	behavior.RaycastParams = self._castParams
	behavior.Acceleration = initialAccel
	behavior.MaxDistance = 1000
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
