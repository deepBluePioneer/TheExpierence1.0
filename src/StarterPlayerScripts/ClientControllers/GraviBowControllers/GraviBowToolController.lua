local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Iris = require(Packages.iris)

local Gizmo
local _gizmoOk, _gizmoMod = pcall(require, Packages.imgizmo)
if _gizmoOk then
	Gizmo = _gizmoMod
	Gizmo.Init()
end

local TOOL_TAG = "tool"

local LocalPlayer = Players.LocalPlayer

local SCANNER_VP_SIZE = UDim2.fromScale(0.55, 0.55)
local SCANNER_VP_POSITION = UDim2.fromScale(1, 1)
local SCANNER_VP_ANCHOR = Vector2.new(1, 1)
local SCANNER_HOLD_POS = Vector3.new(0.25, -1.35, -0.95)
local SCANNER_GRIP_TILT = CFrame.Angles(math.rad(24), math.rad(216), math.rad(6))
local SCANNER_SCALE = 1.75
local SCANNER_RAY_LENGTH = 200
local SCANNER_RAY_COLOR = Color3.fromRGB(0, 220, 255)

local DEBUG_SCANNER = false

local RADIAL_OPTIONS = {
	{ name = "None",      icon = "🚫", cost = 0 },
	{ name = "Harvester", icon = "⛏️",  cost = 1 },
	{ name = "Wall",      icon = "🧱", cost = 0 },
	{ name = "Floor",     icon = "🟫", cost = 0 },
	{ name = "Ramp",      icon = "📐", cost = 0 },
	{ name = "Turret",    icon = "🔫", cost = 0 },
}
local GRAVGUN_HOLD_DISTANCE = 8
local GRAVGUN_LERP_SPEED = 0.3
local RADIAL_RING_RADIUS = 120
local RADIAL_SEGMENT_SIZE = 80
local RADIAL_BG_COLOR = Color3.fromRGB(10, 12, 20)
local RADIAL_HIGHLIGHT_COLOR = Color3.fromRGB(255, 200, 50)
local RADIAL_NORMAL_COLOR = Color3.fromRGB(40, 44, 60)
local RADIAL_TEXT_COLOR = Color3.fromRGB(220, 220, 240)
local RADIAL_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local SLOT_KEYCODES = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
}

local GraviBowToolController = Knit.CreateController({
	Name = "GraviBowToolController",

	_trove = nil,
	_inventory = {},
	_activeSlot = 0,
	_viewmodelController = nil,
	_playerService = nil,

	_scannerGui = nil,
	_scannerVpFrame = nil,
	_scannerVpCamera = nil,
	_scannerWorldModel = nil,
	_scannerClone = nil,
	_scannerCrosshairGui = nil,
	_scannerPartOffsets = nil,
	_scannerRenderBound = false,
	_scannerRayPart = nil,

	_scannerCrosshairLines = {},
	_scannerCrosshairDot = nil,
	_scannerOverCrystal = false,

	_miningTarget = nil,
	_miningProgress = 0,
	_miningEmitterPart = nil,
	_lmbHeld = false,
	_lastScannerRenderTime = nil,

	_radialGui = nil,
	_radialVisible = false,
	_radialSegments = {},
	_selectedSegment = 0,

	_heldObject = nil,
	_heldObjectConn = nil,
})

local _dbgPosX, _dbgPosY, _dbgPosZ
local _dbgRotX, _dbgRotY, _dbgRotZ
local _dbgScale

function GraviBowToolController:KnitInit()
	self._trove = Trove.new()

	if DEBUG_SCANNER then
		Iris.Init()

		_dbgPosX = Iris.State(SCANNER_HOLD_POS.X)
		_dbgPosY = Iris.State(SCANNER_HOLD_POS.Y)
		_dbgPosZ = Iris.State(SCANNER_HOLD_POS.Z)
		_dbgRotX = Iris.State(15)
		_dbgRotY = Iris.State(180)
		_dbgRotZ = Iris.State(0)
		_dbgScale = Iris.State(SCANNER_SCALE)

		Iris:Connect(function()
			Iris.Window({"Scanner Debug"})

			Iris.Text({"-- Position --"})
			Iris.SliderNum({"Pos X", 0.05, -3, 3}, {number = _dbgPosX})
			Iris.SliderNum({"Pos Y", 0.05, -3, 3}, {number = _dbgPosY})
			Iris.SliderNum({"Pos Z", 0.05, -5, 0}, {number = _dbgPosZ})

			Iris.Separator()
			Iris.Text({"-- Rotation --"})
			Iris.SliderNum({"Rot X", 1, -90, 90}, {number = _dbgRotX})
			Iris.SliderNum({"Rot Y", 1, 0, 360}, {number = _dbgRotY})
			Iris.SliderNum({"Rot Z", 1, -90, 90}, {number = _dbgRotZ})

			Iris.Separator()
			Iris.Text({"-- Scale --"})
			Iris.SliderNum({"Scale", 0.05, 0.1, 3}, {number = _dbgScale})

			if Iris.Button({"Print Values"}).clicked() then
				print(string.format(
					"[ScannerDebug] HOLD_POS = Vector3.new(%.2f, %.2f, %.2f)  TILT = CFrame.Angles(math.rad(%.0f), math.rad(%.0f), math.rad(%.0f))  Scale = %.2f",
					_dbgPosX:get(), _dbgPosY:get(), _dbgPosZ:get(),
					_dbgRotX:get(), _dbgRotY:get(), _dbgRotZ:get(),
					_dbgScale:get()
				))
			end

			Iris.End()
		end)
	end
end

function GraviBowToolController:KnitStart()
	self._viewmodelController = Knit.GetController("GraviBowViewmodelController")
	self._playerService = Knit.GetService("GraviBowPlayerService")

	self._playerService.ToolPickedUp:Connect(function(toolName)
		self:_onToolPickedUp(toolName)
	end)

	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self._heldObject and self._heldObject.Parent then
				self:_dropHeldObject()
				return
			end
			self._lmbHeld = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self:GetActiveTool() == "scanner" then
				self:_showRadialMenu()
			end
		end
		for slot, keyCode in ipairs(SLOT_KEYCODES) do
			if input.KeyCode == keyCode then
				self:_switchToSlot(slot)
				break
			end
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self._lmbHeld = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self._radialVisible then
				self:_hideRadialMenu()
			end
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputChanged:Connect(function(input)
		if not self._radialVisible then return end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local dir = input.Position.Z > 0 and -1 or 1
			self:_scrollRadialSelection(dir)
		end
	end), "Disconnect")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.5)
		self:_reequipActiveTool()
	end), "Disconnect")

	self._playerService.ItemPurchased:Connect(function(itemName, harvesterModel)
		self:_onItemPurchased(itemName, harvesterModel)
	end)

	self:_createScannerViewport()
	self:_createRadialMenu()
end

function GraviBowToolController:_onToolPickedUp(toolName)
	for _, existing in ipairs(self._inventory) do
		if existing == toolName then
			return
		end
	end

	table.insert(self._inventory, toolName)
	self:_disableWorldPromptsForTool(toolName)

	print("[GraviBowToolController] Picked up:", toolName, "- slot", #self._inventory)

	self:_switchToSlot(#self._inventory)
end

function GraviBowToolController:_switchToSlot(slot)
	if slot < 1 or slot > #self._inventory then return end
	if slot == self._activeSlot then return end

	self:_unequipCurrentTool()

	self._activeSlot = slot
	local toolName = self._inventory[slot]

	print("[GraviBowToolController] Switched to slot", slot, ":", toolName)

	if toolName == "bow" then
		self:_hideScannerViewport()
		local bowTool = self:_findToolInBackpack("bow")
		if bowTool then
			self:_equipTool(bowTool)
		end
		self._viewmodelController:ShowBow(bowTool)
	elseif toolName == "scanner" then
		self._viewmodelController:HideBow()
		local scannerTool = self:_findToolInBackpack("scanner")
		if scannerTool then
			self:_equipTool(scannerTool)
		end
		self:_showScannerViewport()
	else
		self._viewmodelController:HideBow()
		self:_hideScannerViewport()
	end
end

function GraviBowToolController:_findToolInBackpack(toolName)
	local character = LocalPlayer.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child.Name:lower() == toolName then
				return child
			end
		end
	end
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child.Name:lower() == toolName then
				return child
			end
		end
	end
	return nil
end

function GraviBowToolController:_equipTool(tool)
	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid:EquipTool(tool)
end

function GraviBowToolController:_unequipCurrentTool()
	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid:UnequipTools()
end

function GraviBowToolController:_reequipActiveTool()
	if self._activeSlot < 1 or self._activeSlot > #self._inventory then return end

	local savedSlot = self._activeSlot
	self._activeSlot = 0
	self:_switchToSlot(savedSlot)
end

function GraviBowToolController:_disableWorldPromptsForTool(toolName)
	for _, instance in ipairs(CollectionService:GetTagged(TOOL_TAG)) do
		if instance:IsA("Tool") and instance.Name:lower() == toolName then
			local handle = instance:FindFirstChild("Handle")
			if handle then
				local prompt = handle:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					prompt.Enabled = false
				end
			end
		end
	end
end

function GraviBowToolController:GetActiveTool()
	if self._activeSlot < 1 or self._activeSlot > #self._inventory then
		return nil
	end
	return self._inventory[self._activeSlot]
end

function GraviBowToolController:IsRadialOpen()
	return self._radialVisible
end

function GraviBowToolController:HasTool(toolName)
	for _, name in ipairs(self._inventory) do
		if name == toolName then
			return true
		end
	end
	return false
end

function GraviBowToolController:_createScannerViewport()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ScannerGui"
	screenGui.DisplayOrder = 99
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = LocalPlayer.PlayerGui
	self._trove:Add(screenGui)
	self._scannerGui = screenGui

	local vpFrame = Instance.new("ViewportFrame")
	vpFrame.Name = "ScannerViewport"
	vpFrame.Size = SCANNER_VP_SIZE
	vpFrame.Position = SCANNER_VP_POSITION
	vpFrame.AnchorPoint = SCANNER_VP_ANCHOR
	vpFrame.BackgroundTransparency = 1
	vpFrame.ImageTransparency = 0
	vpFrame.LightDirection = Vector3.new(-1, -1, -1).Unit
	vpFrame.Ambient = Color3.fromRGB(180, 180, 180)
	vpFrame.Visible = false
	vpFrame.Parent = screenGui
	self._scannerVpFrame = vpFrame

	local vpCamera = Instance.new("Camera")
	vpCamera.Parent = vpFrame
	vpFrame.CurrentCamera = vpCamera
	self._scannerVpCamera = vpCamera

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = vpFrame
	self._scannerWorldModel = worldModel

	local crosshairGui = Instance.new("ScreenGui")
	crosshairGui.Name = "ScannerCrosshairGui"
	crosshairGui.DisplayOrder = 101
	crosshairGui.IgnoreGuiInset = true
	crosshairGui.ResetOnSpawn = false
	crosshairGui.Enabled = false
	crosshairGui.Parent = LocalPlayer.PlayerGui
	self._trove:Add(crosshairGui)
	self._scannerCrosshairGui = crosshairGui

	local container = Instance.new("Frame")
	local RING_SIZE = 32
	local RING_THICKNESS = 2
	local DOT_SIZE = 4
	local COLOR = Color3.fromRGB(0, 220, 255)

	container.Name = "ScannerCrosshair"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.fromOffset(RING_SIZE, RING_SIZE)
	container.BackgroundTransparency = 1
	container.Parent = crosshairGui

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(RING_SIZE, RING_SIZE)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.Parent = container
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = COLOR
	ringStroke.Thickness = RING_THICKNESS
	ringStroke.Transparency = 0.2
	ringStroke.Parent = ring
	self._scannerCrosshairRing = ring
	self._scannerCrosshairRingStroke = ringStroke

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
	dot.BackgroundColor3 = COLOR
	dot.BorderSizePixel = 0
	dot.Parent = container
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	self._scannerCrosshairDot = dot

	self._scannerCrosshairLines = {}
end

function GraviBowToolController:_showScannerViewport()
	if not self._scannerVpFrame then return end
	self._scannerVpFrame.Visible = true
	if self._scannerCrosshairGui then
		self._scannerCrosshairGui.Enabled = true
	end

	if not self._scannerClone then
		local scannerTool = self:_findToolInBackpack("scanner")
		if scannerTool then
			self:_cloneScannerModel(scannerTool)
		end
	end

	if not self._scannerRenderBound then
		self._scannerRenderBound = true
		local RENDER_NAME = "GraviBowScannerViewmodel"
		RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 11, function()
			local worldCam = Workspace.CurrentCamera
			if not worldCam then return end
			if not self._scannerVpFrame or not self._scannerVpFrame.Visible then return end

			self._scannerVpCamera.CFrame = worldCam.CFrame
			self._scannerVpCamera.FieldOfView = worldCam.FieldOfView

			if self._scannerClone and self._scannerPartOffsets then
				local holdPos = SCANNER_HOLD_POS
				local gripTilt = SCANNER_GRIP_TILT
				local scale = SCANNER_SCALE

				if DEBUG_SCANNER and _dbgPosX then
					holdPos = Vector3.new(_dbgPosX:get(), _dbgPosY:get(), _dbgPosZ:get())
					gripTilt = CFrame.Angles(math.rad(_dbgRotX:get()), math.rad(_dbgRotY:get()), math.rad(_dbgRotZ:get()))
					scale = _dbgScale:get()
				end

				local scannerWorldPos = worldCam.CFrame:PointToWorldSpace(holdPos)
				local aimTarget = scannerWorldPos + worldCam.CFrame.LookVector * 200
				local upDir = worldCam.CFrame.UpVector
				local handleCF = CFrame.lookAt(scannerWorldPos, aimTarget, upDir) * gripTilt
				local firePointWorldPos = nil
				local firePointWorldDir = nil
				for part, offset in pairs(self._scannerPartOffsets) do
					if part.Parent then
						local scaledOffset = CFrame.new(offset.Position * scale) * offset.Rotation
						part.CFrame = handleCF * scaledOffset

						if not part:GetAttribute("_origSize") then
							part:SetAttribute("_origSize", part.Size)
						end
						part.Size = part:GetAttribute("_origSize") * scale

						if part.Name == "firePoint" then
							local fpCF = handleCF * scaledOffset
							firePointWorldPos = fpCF.Position
							firePointWorldDir = fpCF.LookVector
						end
					end
				end

				if firePointWorldPos and firePointWorldDir then
					if not self._scannerRayPart then
						local ray = Instance.new("Part")
						ray.Name = "ScannerRay"
						ray.Anchored = true
						ray.CanCollide = false
						ray.CanQuery = false
						ray.CanTouch = false
						ray.CastShadow = false
						ray.Material = Enum.Material.Neon
						ray.Color = SCANNER_RAY_COLOR
						ray.Size = Vector3.new(0.03, 0.03, SCANNER_RAY_LENGTH)
						ray.Parent = self._scannerWorldModel
						self._scannerRayPart = ray
					end
					local midPoint = firePointWorldPos - firePointWorldDir * (SCANNER_RAY_LENGTH / 2)
					self._scannerRayPart.CFrame = CFrame.lookAt(midPoint, midPoint - firePointWorldDir)
				end
			end

			local now = tick()
			local dt = now - (self._lastScannerRenderTime or now)
			self._lastScannerRenderTime = now
			self:_updateCrystalDetection(worldCam, dt)
			self:_updateHeldObject(worldCam)
		end)
		self._trove:Add(function()
			RunService:UnbindFromRenderStep(RENDER_NAME)
		end)
	end
end

function GraviBowToolController:_hideScannerViewport()
	if self._scannerVpFrame then
		self._scannerVpFrame.Visible = false
	end
	if self._scannerCrosshairGui then
		self._scannerCrosshairGui.Enabled = false
	end
	if self._scannerRayPart then
		self._scannerRayPart:Destroy()
		self._scannerRayPart = nil
	end
	if self._scannerOverCrystal then
		self._scannerOverCrystal = false
		self:_tweenScannerCrosshair(false)
	end
	self:_stopMining()
	if self._radialVisible then
		self:_hideRadialMenu()
	end
	if self._heldObject then
		self:_dropHeldObject()
	end
end

local CRYSTAL_SCAN_RANGE = 500
local CRYSTAL_MINE_RANGE = 40
local MINE_DURATION = 2.5
local CROSSHAIR_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SCANNER_COLOR_NORMAL = Color3.fromRGB(0, 220, 255)
local SCANNER_COLOR_CRYSTAL = Color3.fromRGB(255, 200, 50)

function GraviBowToolController:_isCrystalPart(instance)
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

function GraviBowToolController:_getCrystalModel(instance)
	local crystalFolder = Workspace:FindFirstChild("CrystalPatches")
	if not crystalFolder then return nil end
	local current = instance
	while current and current.Parent ~= crystalFolder do
		current = current.Parent
	end
	return current
end

function GraviBowToolController:_updateCrystalDetection(cam, dt)
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
	if self._lmbHeld and not self._radialVisible and not self._heldObject and overCrystal and result then
		local dist = (result.Position - origin).Magnitude
		if dist <= CRYSTAL_MINE_RANGE then
			local crystalModel = self:_getCrystalModel(result.Instance)
			if crystalModel then
				if self._miningTarget ~= crystalModel then
					self:_stopMining()
					self._miningTarget = crystalModel
					self._miningProgress = 0
					self:_startMiningEffect(result.Position, result.Normal)
				else
					self:_updateMiningEffectPosition(result.Position, result.Normal)
				end

				self._miningProgress = self._miningProgress + dt / MINE_DURATION
				self:_setCrystalTransparency(crystalModel, self._miningProgress)

				if self._miningProgress >= 1 then
					self:_destroyCrystal(crystalModel)
					self:_stopMining()
				end
			end
		else
			self:_stopMining()
		end
	else
		if self._miningTarget then
			self:_stopMining()
		end
	end
end

function GraviBowToolController:_setCrystalTransparency(crystalModel, progress)
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

function GraviBowToolController:_startMiningEffect(hitPos, hitNormal)
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

function GraviBowToolController:_updateMiningEffectPosition(hitPos, hitNormal)
	if self._miningEmitterPart then
		self._miningEmitterPart.CFrame = CFrame.lookAt(hitPos, hitPos + hitNormal)
	end
end

function GraviBowToolController:_cleanMiningEffect()
	if self._miningEmitterPart then
		self._miningEmitterPart:Destroy()
		self._miningEmitterPart = nil
	end
end

function GraviBowToolController:_stopMining()
	if self._miningTarget and self._miningTarget.Parent then
		self:_setCrystalTransparency(self._miningTarget, 0)
	end
	self._miningTarget = nil
	self._miningProgress = 0
	self:_cleanMiningEffect()
end

function GraviBowToolController:_destroyCrystal(crystalModel)
	if not crystalModel or not crystalModel.Parent then return end

	self._playerService.CrystalMined:Fire()

	local pos = if crystalModel:IsA("Model") and crystalModel.PrimaryPart
		then crystalModel.PrimaryPart.Position
		else crystalModel.Position

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

function GraviBowToolController:_tweenScannerCrosshair(isCrystal)
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

function GraviBowToolController:_cloneScannerModel(toolModel)
	if self._scannerClone then
		self._scannerClone:Destroy()
		self._scannerClone = nil
		self._scannerPartOffsets = nil
	end

	local clone = toolModel:Clone()
	clone.Parent = self._scannerWorldModel
	self._scannerClone = clone

	local handle = clone:FindFirstChild("Handle") or clone:FindFirstChildWhichIsA("BasePart", true)
	if not handle then
		warn("[GraviBowToolController] Scanner model has no Handle or BasePart")
		return
	end

	local offsets = {}
	local handleCF = handle.CFrame
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			offsets[desc] = handleCF:ToObjectSpace(desc.CFrame)
			desc.Anchored = true
			desc.CanCollide = false
		end
	end
	if handle:IsA("BasePart") then
		offsets[handle] = CFrame.identity
		handle.Anchored = true
		handle.CanCollide = false
	end

	self._scannerPartOffsets = offsets
end

function GraviBowToolController:_createRadialMenu()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RadialMenuGui"
	gui.DisplayOrder = 110
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = LocalPlayer.PlayerGui
	self._trove:Add(gui)
	self._radialGui = gui

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.6
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	local centerDot = Instance.new("Frame")
	centerDot.Name = "CenterDot"
	centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
	centerDot.Position = UDim2.fromScale(0.5, 0.5)
	centerDot.Size = UDim2.fromOffset(12, 12)
	centerDot.BackgroundColor3 = Color3.fromRGB(200, 200, 220)
	centerDot.BackgroundTransparency = 0.3
	centerDot.BorderSizePixel = 0
	centerDot.Parent = gui
	local cdCorner = Instance.new("UICorner")
	cdCorner.CornerRadius = UDim.new(1, 0)
	cdCorner.Parent = centerDot

	self._radialSegments = {}
	local count = #RADIAL_OPTIONS
	for i, option in ipairs(RADIAL_OPTIONS) do
		local seg = Instance.new("Frame")
		seg.Name = "Segment_" .. option.name
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.Size = UDim2.fromOffset(RADIAL_SEGMENT_SIZE, RADIAL_SEGMENT_SIZE)
		seg.BackgroundColor3 = RADIAL_NORMAL_COLOR
		seg.BackgroundTransparency = 0.15
		seg.BorderSizePixel = 0
		seg.Parent = gui

		local segCorner = Instance.new("UICorner")
		segCorner.CornerRadius = UDim.new(1, 0)
		segCorner.Parent = seg

		local segStroke = Instance.new("UIStroke")
		segStroke.Name = "Stroke"
		segStroke.Color = Color3.fromRGB(80, 85, 110)
		segStroke.Thickness = 2
		segStroke.Transparency = 0.3
		segStroke.Parent = seg

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "Icon"
		iconLabel.Size = UDim2.new(1, 0, 0.55, 0)
		iconLabel.Position = UDim2.fromScale(0, 0.05)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = option.icon
		iconLabel.TextSize = 28
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.TextColor3 = Color3.new(1, 1, 1)
		iconLabel.Parent = seg

		local labelText = option.name
		if option.cost and option.cost > 0 then
			labelText = option.name .. " (" .. option.cost .. ")"
		end

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Label"
		nameLabel.Size = UDim2.new(1, 0, 0.35, 0)
		nameLabel.Position = UDim2.fromScale(0, 0.6)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = labelText
		nameLabel.TextSize = 12
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextColor3 = RADIAL_TEXT_COLOR
		nameLabel.Parent = seg

		self._radialSegments[i] = {
			frame = seg,
			stroke = segStroke,
			angle = 0,
			option = option,
		}
	end

	self:_positionRadialSegments()
end

function GraviBowToolController:_positionRadialSegments()
	if not self._radialGui then return end
	local count = #RADIAL_OPTIONS

	for i, data in ipairs(self._radialSegments) do
		local angle = ((i - 1) / count) * math.pi * 2 - math.pi / 2
		local ox = math.cos(angle) * RADIAL_RING_RADIUS
		local oy = math.sin(angle) * RADIAL_RING_RADIUS
		data.frame.Position = UDim2.new(0.5, ox, 0.5, oy)
		data.angle = angle
	end
end

function GraviBowToolController:_showRadialMenu()
	if self._radialVisible then return end
	self._radialVisible = true

	self:_positionRadialSegments()

	if self._radialGui then
		self._radialGui.Enabled = true
	end

	self._selectedSegment = 1
	self:_highlightRadialSegment()
end

function GraviBowToolController:_hideRadialMenu()
	if not self._radialVisible then return end
	self._radialVisible = false

	local selected = self._selectedSegment
	if selected >= 1 and selected <= #RADIAL_OPTIONS then
		local option = RADIAL_OPTIONS[selected]
		print("[GraviBowToolController] Selected build:", option.name)

		if option.cost and option.cost > 0 then
			self._playerService.PurchaseItem:Fire(option.name)
		end
	end

	if self._radialGui then
		self._radialGui.Enabled = false
	end

	self._selectedSegment = 0
end

function GraviBowToolController:_scrollRadialSelection(dir)
	local count = #RADIAL_OPTIONS
	if count == 0 then return end

	local newIdx = self._selectedSegment + dir
	if newIdx < 1 then
		newIdx = count
	elseif newIdx > count then
		newIdx = 1
	end

	self._selectedSegment = newIdx
	self:_highlightRadialSegment()
end

function GraviBowToolController:_highlightRadialSegment()
	local selected = self._selectedSegment

	for i, data in ipairs(self._radialSegments) do
		local isSelected = (i == selected)
		local targetBg = isSelected and RADIAL_HIGHLIGHT_COLOR or RADIAL_NORMAL_COLOR
		local targetSize = isSelected
			and UDim2.fromOffset(RADIAL_SEGMENT_SIZE + 10, RADIAL_SEGMENT_SIZE + 10)
			or UDim2.fromOffset(RADIAL_SEGMENT_SIZE, RADIAL_SEGMENT_SIZE)
		local targetStroke = isSelected and RADIAL_HIGHLIGHT_COLOR or Color3.fromRGB(80, 85, 110)

		TweenService:Create(data.frame, RADIAL_TWEEN_INFO, {
			BackgroundColor3 = targetBg,
			Size = targetSize,
		}):Play()
		TweenService:Create(data.stroke, RADIAL_TWEEN_INFO, {
			Color = targetStroke,
		}):Play()
	end
end

function GraviBowToolController:_onItemPurchased(itemName, harvesterModel)
	if itemName == "Harvester" and harvesterModel then
		self:_holdServerObject(harvesterModel)
	end
end

function GraviBowToolController:_holdServerObject(obj)
	if self._heldObject then
		self:_dropHeldObject()
	end

	self._heldObject = obj

	self._heldObjectConn = obj.AncestryChanged:Connect(function(_, newParent)
		if not newParent then
			self._heldObject = nil
			if self._heldObjectConn then
				self._heldObjectConn:Disconnect()
				self._heldObjectConn = nil
			end
		end
	end)

	print("[GraviBowToolController] Now carrying server-spawned object:", obj.Name)
end

function GraviBowToolController:_updateHeldObject(cam)
	if not self._heldObject or not self._heldObject.Parent then
		self._heldObject = nil
		return
	end

	local targetPos = cam.CFrame:PointToWorldSpace(Vector3.new(0, 0, -GRAVGUN_HOLD_DISTANCE))
	local lookDir = cam.CFrame.LookVector
	local upDir = cam.CFrame.UpVector
	local targetCF = CFrame.lookAt(targetPos, targetPos + lookDir, upDir)

	if self._heldObject:IsA("Model") then
		local currentCF = self._heldObject:GetPivot()
		self._heldObject:PivotTo(currentCF:Lerp(targetCF, GRAVGUN_LERP_SPEED))
	elseif self._heldObject:IsA("BasePart") then
		self._heldObject.CFrame = self._heldObject.CFrame:Lerp(targetCF, GRAVGUN_LERP_SPEED)
	end
end

function GraviBowToolController:_dropHeldObject()
	if not self._heldObject then return end

	local obj = self._heldObject
	self._heldObject = nil

	if self._heldObjectConn then
		self._heldObjectConn:Disconnect()
		self._heldObjectConn = nil
	end

	if not obj.Parent then return end

	local rootPart = nil
	if obj:IsA("Model") then
		rootPart = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
	elseif obj:IsA("BasePart") then
		rootPart = obj
	end

	local dropPos = rootPart and rootPart.Position or Vector3.zero
	local lookDir = rootPart and rootPart.CFrame.LookVector or Vector3.new(0, 0, -1)

	self._playerService.DropHarvester:Fire(obj, dropPos, lookDir)

	print("[GraviBowToolController] Dropped held object (sent to server)")
end

return GraviBowToolController
