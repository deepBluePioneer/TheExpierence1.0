local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

local _dbgPosX, _dbgPosY, _dbgPosZ
local _dbgRotX, _dbgRotY, _dbgRotZ
local _dbgScale

local GraviBowScannerController = Knit.CreateController({
	Name = "GraviBowScannerController",

	_trove = nil,
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
	_lastScannerRenderTime = nil,

	_scannerCrosshairRing = nil,
	_scannerCrosshairRingStroke = nil,
})

function GraviBowScannerController:KnitInit()
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

function GraviBowScannerController:KnitStart()
	self._toolController = Knit.GetController("GraviBowToolController")
	self._miningController = Knit.GetController("GraviBowMiningController")
	self._harvesterController = Knit.GetController("GraviBowHarvesterController")
	self._radialMenuController = Knit.GetController("GraviBowRadialMenuController")
	self:_createScannerViewport()
end

function GraviBowScannerController:Show()
	self:_showScannerViewport()
end

function GraviBowScannerController:Hide()
	self:_hideScannerViewport()
end

function GraviBowScannerController:_createScannerViewport()
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

	self._miningController:SetCrosshairInstances(ring, ringStroke, dot)
end

function GraviBowScannerController:_showScannerViewport()
	if not self._scannerVpFrame then return end
	self._scannerVpFrame.Visible = true
	if self._scannerCrosshairGui then
		self._scannerCrosshairGui.Enabled = true
	end

	if not self._scannerClone then
		local scannerTool = self._toolController:FindToolInBackpack("scanner")
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

			local radialOpen = self._radialMenuController:IsRadialOpen()
			local holdingObj = self._harvesterController:IsHolding()
			self._miningController:Update(worldCam, dt, radialOpen, holdingObj)
			self._harvesterController:UpdateHeldObject(worldCam)
		end)
		self._trove:Add(function()
			RunService:UnbindFromRenderStep(RENDER_NAME)
		end)
	end
end

function GraviBowScannerController:_hideScannerViewport()
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
	self._miningController:ResetCrosshair()
	self._miningController:StopMining()
	if self._radialMenuController:IsRadialOpen() then
		self._radialMenuController:Hide()
	end
	if self._harvesterController:IsHolding() then
		self._harvesterController:DropHeldObject()
	end
end

function GraviBowScannerController:_cloneScannerModel(toolModel)
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
		warn("[GraviBowScannerController] Scanner model has no Handle or BasePart")
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

return GraviBowScannerController
