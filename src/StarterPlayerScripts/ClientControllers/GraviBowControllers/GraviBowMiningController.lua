local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local CRYSTAL_SCAN_RANGE = 500
local CRYSTAL_MINE_RANGE = 40
local MINE_DURATION = 2.5
local CROSSHAIR_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SCANNER_COLOR_NORMAL = Color3.fromRGB(0, 220, 255)
local SCANNER_COLOR_CRYSTAL = Color3.fromRGB(255, 200, 50)

local GraviBowMiningController = Knit.CreateController({
	Name = "GraviBowMiningController",

	_trove = nil,
	_miningTarget = nil,
	_miningProgress = 0,
	_miningEmitterPart = nil,
	_lmbHeld = false,
	_scannerBeamSound = nil,

	_scannerCrosshairRing = nil,
	_scannerCrosshairRingStroke = nil,
	_scannerCrosshairDot = nil,
	_scannerOverCrystal = false,
})

function GraviBowMiningController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowMiningController:KnitStart()
	self._soundController = Knit.GetController("GraviBowSoundController")
	self._oreService = Knit.GetService("GraviBowOreService")
end

function GraviBowMiningController:SetLmbHeld(held)
	self._lmbHeld = held
end

function GraviBowMiningController:GetLmbHeld()
	return self._lmbHeld
end

function GraviBowMiningController:SetCrosshairInstances(ring, ringStroke, dot)
	self._scannerCrosshairRing = ring
	self._scannerCrosshairRingStroke = ringStroke
	self._scannerCrosshairDot = dot
end

function GraviBowMiningController:Update(cam, dt, radialVisible, holdingObject)
	dt = math.clamp(dt or 0.016, 0, 0.1)

	local origin = cam.CFrame.Position
	local direction = cam.CFrame.LookVector * CRYSTAL_SCAN_RANGE

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList = {}
	local character = LocalPlayer.Character
	if character then table.insert(filterList, character) end
	local gzFolder = Workspace:FindFirstChild("GravityZones")
	if gzFolder then table.insert(filterList, gzFolder) end
	local tpFolder = Workspace:FindFirstChild("TerrainPlanets")
	if tpFolder then table.insert(filterList, tpFolder) end
	rayParams.FilterDescendantsInstances = filterList

	local result = Workspace:Raycast(origin, direction, rayParams)
	local overCrystal = result and self:_isCrystalPart(result.Instance) or false

	if overCrystal ~= self._scannerOverCrystal then
		self._scannerOverCrystal = overCrystal
		self:_tweenScannerCrosshair(overCrystal)
	end

	if self._lmbHeld and not radialVisible and not holdingObject and overCrystal and result then
		local dist = (result.Position - origin).Magnitude
		if dist <= CRYSTAL_MINE_RANGE then
			local crystalModel = self:_getCrystalModel(result.Instance)
			if crystalModel then
				if self._miningTarget ~= crystalModel then
					self:StopMining()
					self._miningTarget = crystalModel
					self._miningProgress = 0
					self:_startMiningEffect(result.Position, result.Normal)
					if self._miningEmitterPart then
						self._scannerBeamSound = self._soundController:PlayNamedLoopOnPart("HarvestBeam", "scanner", self._miningEmitterPart)
					end
				else
					self:_updateMiningEffectPosition(result.Position, result.Normal)
				end

				self._miningProgress = self._miningProgress + dt / MINE_DURATION
				self:_setCrystalTransparency(crystalModel, self._miningProgress)

				if self._miningProgress >= 1 then
					self:_destroyCrystal(crystalModel)
					self:StopMining()
				end
			end
		else
			self:StopMining()
		end
	else
		if self._miningTarget then
			self:StopMining()
		end
	end
end

function GraviBowMiningController:StopMining()
	if self._miningTarget and self._miningTarget.Parent then
		self:_setCrystalTransparency(self._miningTarget, 0)
	end
	self._miningTarget = nil
	self._miningProgress = 0
	self:_cleanMiningEffect()
	if self._scannerBeamSound then
		self._scannerBeamSound:Stop()
		self._scannerBeamSound:Destroy()
		self._scannerBeamSound = nil
	end
end

function GraviBowMiningController:ResetCrosshair()
	if self._scannerOverCrystal then
		self._scannerOverCrystal = false
		self:_tweenScannerCrosshair(false)
	end
end

function GraviBowMiningController:_isCrystalPart(instance)
	if not instance then return false end
	local crystalFolder = Workspace:FindFirstChild("CrystalPatches")
	if not crystalFolder then return false end
	local current = instance
	while current do
		if current == crystalFolder then return true end
		current = current.Parent
	end
	return false
end

function GraviBowMiningController:_getCrystalModel(instance)
	local crystalFolder = Workspace:FindFirstChild("CrystalPatches")
	if not crystalFolder then return nil end
	local current = instance
	while current and current.Parent ~= crystalFolder do
		current = current.Parent
	end
	return current
end

function GraviBowMiningController:_setCrystalTransparency(crystalModel, progress)
	local t = math.clamp(progress, 0, 1)
	if crystalModel:IsA("BasePart") then
		crystalModel.Transparency = t
	else
		local primary = crystalModel:IsA("Model") and crystalModel.PrimaryPart or nil
		for _, desc in ipairs(crystalModel:GetDescendants()) do
			if desc:IsA("BasePart") and desc ~= primary and desc.Name ~= "harvestPoint" then
				desc.Transparency = t
			end
		end
	end
end

function GraviBowMiningController:_startMiningEffect(hitPos, hitNormal)
	self:_cleanMiningEffect()

	local part = Instance.new("Part")
	part.Name = "MiningEffect"
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.lookAt(hitPos, hitPos + hitNormal)
	part.Parent = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MineParticles"
	emitter.Color = ColorSequence.new(
		Color3.fromRGB(255, 200, 50),
		Color3.fromRGB(255, 120, 20)
	)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Rate = 60
	emitter.Speed = NumberRange.new(2, 6)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0.2
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Parent = part

	local glow = Instance.new("PointLight")
	glow.Name = "MineGlow"
	glow.Color = Color3.fromRGB(255, 200, 50)
	glow.Brightness = 2
	glow.Range = 8
	glow.Parent = part

	self._miningEmitterPart = part
end

function GraviBowMiningController:_updateMiningEffectPosition(hitPos, hitNormal)
	if self._miningEmitterPart then
		self._miningEmitterPart.CFrame = CFrame.lookAt(hitPos, hitPos + hitNormal)
	end
end

function GraviBowMiningController:_cleanMiningEffect()
	if self._miningEmitterPart then
		self._miningEmitterPart:Destroy()
		self._miningEmitterPart = nil
	end
end

function GraviBowMiningController:_destroyCrystal(crystalModel)
	if not crystalModel or not crystalModel.Parent then return end

	self._oreService.CrystalMined:Fire()

	local pos = if crystalModel:IsA("Model") and crystalModel.PrimaryPart
		then crystalModel.PrimaryPart.Position
		else crystalModel.Position

	self._soundController:PlayAtPosition("HarvestCollected", pos)

	local burstPart = Instance.new("Part")
	burstPart.Size = Vector3.new(0.5, 0.5, 0.5)
	burstPart.Transparency = 1
	burstPart.Anchored = true
	burstPart.CanCollide = false
	burstPart.CanQuery = false
	burstPart.CanTouch = false
	burstPart.Position = pos
	burstPart.Parent = Workspace

	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(
		Color3.fromRGB(255, 220, 80),
		Color3.fromRGB(255, 100, 20)
	)
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.Lifetime = NumberRange.new(0.4, 0.8)
	burst.Speed = NumberRange.new(5, 15)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.LightEmission = 1
	burst.LightInfluence = 0
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Parent = burstPart

	burst:Emit(30)
	burst.Enabled = false

	task.delay(1, function()
		burstPart:Destroy()
	end)

	crystalModel:Destroy()
end

function GraviBowMiningController:_tweenScannerCrosshair(isCrystal)
	local targetColor = isCrystal and SCANNER_COLOR_CRYSTAL or SCANNER_COLOR_NORMAL

	if self._scannerCrosshairDot then
		TweenService:Create(self._scannerCrosshairDot, CROSSHAIR_TWEEN_INFO, {
			BackgroundColor3 = targetColor,
			Size = isCrystal and UDim2.fromOffset(6, 6) or UDim2.fromOffset(4, 4),
		}):Play()
	end

	if self._scannerCrosshairRing then
		TweenService:Create(self._scannerCrosshairRing, CROSSHAIR_TWEEN_INFO, {
			Size = isCrystal and UDim2.fromOffset(42, 42) or UDim2.fromOffset(32, 32),
		}):Play()
	end

	if self._scannerCrosshairRingStroke then
		TweenService:Create(self._scannerCrosshairRingStroke, CROSSHAIR_TWEEN_INFO, {
			Color = targetColor,
			Thickness = isCrystal and 3 or 2,
			Transparency = isCrystal and 0 or 0.2,
		}):Play()
	end
end

return GraviBowMiningController
