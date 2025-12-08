--[[
	ReticleController
	Fusion-based reticle UI with object highlighting for gravity gun
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Fusion = require(CustomPackages:WaitForChild("FusionRoot"):WaitForChild("Fusion"))

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring

local ReticleController = Knit.CreateController {
	Name = "ReticleController",
	
	-- UI
	_screenGui = nil,
	_highlight = nil,
	
	-- State
	_targetObject = nil,
	_character = nil,
	
	-- Connections
	_connections = {},
}

-- === CONFIG ===
local CONFIG = {
	-- Reticle appearance
	ReticleSize = 40,
	ReticleThickness = 2,
	ReticleGap = 8,
	ReticleColor = Color3.fromRGB(255, 255, 255),
	ReticleTargetColor = Color3.fromRGB(0, 255, 200),
	
	-- Highlight
	HighlightFillColor = Color3.fromRGB(0, 255, 200),
	HighlightOutlineColor = Color3.fromRGB(255, 255, 255),
	HighlightFillTransparency = 0.7,
	HighlightOutlineTransparency = 0,
	
	-- Targeting
	TargetRange = 30,
}

-- === FUSION STATE ===
local isTargeting = Value(false)
local reticleScale = Value(1)

-- Computed colors based on targeting state
local reticleColor = Computed(function()
	return isTargeting:get() and CONFIG.ReticleTargetColor or CONFIG.ReticleColor
end)

-- Spring for smooth scale animation
local smoothScale = Spring(reticleScale, 25, 0.7)

-- === UI CREATION ===

function ReticleController:CreateReticleUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Reticle line creator
	local function CreateReticleLine(rotation, offsetX, offsetY)
		return New "Frame" {
			Name = "ReticleLine",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, offsetX, 0.5, offsetY),
			Size = Computed(function()
				local scale = smoothScale:get()
				local length = (CONFIG.ReticleSize / 2 - CONFIG.ReticleGap) * scale
				return UDim2.new(0, length, 0, CONFIG.ReticleThickness)
			end),
			Rotation = rotation,
			BackgroundColor3 = reticleColor,
			BorderSizePixel = 0,
			
			[Children] = {
				New "UICorner" {
					CornerRadius = UDim.new(0, 1),
				},
			},
		}
	end
	
	-- Center dot
	local function CreateCenterDot()
		return New "Frame" {
			Name = "CenterDot",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = Computed(function()
				local scale = smoothScale:get()
				local size = 4 * scale
				return UDim2.new(0, size, 0, size)
			end),
			BackgroundColor3 = reticleColor,
			BorderSizePixel = 0,
			
			[Children] = {
				New "UICorner" {
					CornerRadius = UDim.new(1, 0),
				},
			},
		}
	end
	
	-- Outer ring (appears when targeting)
	local function CreateOuterRing()
		return New "Frame" {
			Name = "OuterRing",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = Computed(function()
				local scale = smoothScale:get()
				local size = CONFIG.ReticleSize * 1.5 * scale
				return UDim2.new(0, size, 0, size)
			end),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			
			[Children] = {
				New "UIStroke" {
					Color = reticleColor,
					Thickness = Computed(function()
						return isTargeting:get() and 2 or 0
					end),
					Transparency = Computed(function()
						return isTargeting:get() and 0.3 or 1
					end),
				},
				New "UICorner" {
					CornerRadius = UDim.new(1, 0),
				},
			},
		}
	end
	
	-- Corner brackets (appear when targeting)
	local function CreateCornerBracket(anchorX, anchorY, rotZ)
		return New "Frame" {
			Name = "CornerBracket",
			AnchorPoint = Vector2.new(anchorX, anchorY),
			Position = Computed(function()
				local scale = smoothScale:get()
				local offset = CONFIG.ReticleSize * 0.8 * scale
				local x = anchorX == 0 and -offset or offset
				local y = anchorY == 0 and -offset or offset
				return UDim2.new(0.5, x, 0.5, y)
			end),
			Size = Computed(function()
				local scale = smoothScale:get()
				return UDim2.new(0, 12 * scale, 0, 12 * scale)
			end),
			Rotation = rotZ,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = Computed(function()
				return isTargeting:get()
			end),
			
			[Children] = {
				-- Horizontal line
				New "Frame" {
					AnchorPoint = Vector2.new(0, 0),
					Position = UDim2.new(0, 0, 0, 0),
					Size = UDim2.new(1, 0, 0, 2),
					BackgroundColor3 = reticleColor,
					BorderSizePixel = 0,
				},
				-- Vertical line
				New "Frame" {
					AnchorPoint = Vector2.new(0, 0),
					Position = UDim2.new(0, 0, 0, 0),
					Size = UDim2.new(0, 2, 1, 0),
					BackgroundColor3 = reticleColor,
					BorderSizePixel = 0,
				},
			},
		}
	end
	
	-- Main GUI
	self._screenGui = New "ScreenGui" {
		Name = "ReticleUI",
		Parent = playerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		
		[Children] = {
			-- Reticle container
			New "Frame" {
				Name = "ReticleContainer",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(0, CONFIG.ReticleSize * 2, 0, CONFIG.ReticleSize * 2),
				BackgroundTransparency = 1,
				
				[Children] = {
					-- Center dot
					CreateCenterDot(),
					
					-- Cross lines
					CreateReticleLine(0, CONFIG.ReticleGap + CONFIG.ReticleSize/4, 0),   -- Right
					CreateReticleLine(0, -(CONFIG.ReticleGap + CONFIG.ReticleSize/4), 0), -- Left
					CreateReticleLine(90, 0, CONFIG.ReticleGap + CONFIG.ReticleSize/4),  -- Down
					CreateReticleLine(90, 0, -(CONFIG.ReticleGap + CONFIG.ReticleSize/4)), -- Up
					
					-- Outer ring
					CreateOuterRing(),
					
					-- Corner brackets
					CreateCornerBracket(0, 0, 0),    -- Top-left
					CreateCornerBracket(1, 0, 90),   -- Top-right
					CreateCornerBracket(1, 1, 180),  -- Bottom-right
					CreateCornerBracket(0, 1, 270),  -- Bottom-left
				},
			},
		},
	}
end

-- === HIGHLIGHT ===

function ReticleController:CreateHighlight()
	self._highlight = Instance.new("Highlight")
	self._highlight.Name = "GravityGunHighlight"
	self._highlight.FillColor = CONFIG.HighlightFillColor
	self._highlight.OutlineColor = CONFIG.HighlightOutlineColor
	self._highlight.FillTransparency = CONFIG.HighlightFillTransparency
	self._highlight.OutlineTransparency = CONFIG.HighlightOutlineTransparency
	self._highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	self._highlight.Enabled = false
	self._highlight.Parent = Workspace
end

function ReticleController:SetHighlightTarget(target)
	if self._highlight then
		if target then
			self._highlight.Adornee = target
			self._highlight.Enabled = true
		else
			self._highlight.Adornee = nil
			self._highlight.Enabled = false
		end
	end
end

-- === TARGETING ===

function ReticleController:UpdateTargeting()
	if not self._character then return end
	
	local camera = Workspace.CurrentCamera
	if not camera then return end
	
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector
	
	-- Raycast for shapes
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {self._character}
	
	local result = Workspace:Raycast(origin, direction * CONFIG.TargetRange, rayParams)
	
	local newTarget = nil
	
	if result and result.Instance then
		local part = result.Instance
		if CollectionService:HasTag(part, "shape") then
			newTarget = part
		end
	end
	
	-- Check if target changed
	if newTarget ~= self._targetObject then
		self._targetObject = newTarget
		
		-- Update highlight
		self:SetHighlightTarget(newTarget)
		
		-- Update reticle state
		isTargeting:set(newTarget ~= nil)
		reticleScale:set(newTarget and 1.2 or 1)
	end
end

-- === PUBLIC API ===

function ReticleController:SetCharacter(character)
	self._character = character
end

function ReticleController:GetTargetObject()
	return self._targetObject
end

function ReticleController:SetReticleColor(normal, targeting)
	CONFIG.ReticleColor = normal
	CONFIG.ReticleTargetColor = targeting
end

function ReticleController:SetHighlightColors(fill, outline)
	CONFIG.HighlightFillColor = fill
	CONFIG.HighlightOutlineColor = outline
	
	if self._highlight then
		self._highlight.FillColor = fill
		self._highlight.OutlineColor = outline
	end
end

function ReticleController:SetVisible(visible)
	if self._screenGui then
		self._screenGui.Enabled = visible
	end
end

-- === CLEANUP ===

function ReticleController:Cleanup()
	for _, conn in ipairs(self._connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	self._connections = {}
	
	if self._screenGui then
		self._screenGui:Destroy()
		self._screenGui = nil
	end
	
	if self._highlight then
		self._highlight:Destroy()
		self._highlight = nil
	end
	
	self._targetObject = nil
	self._character = nil
end

-- === KNIT LIFECYCLE ===

function ReticleController:KnitInit()
end

function ReticleController:KnitStart()
	-- Create UI
	self:CreateReticleUI()
	self:CreateHighlight()
	
	-- Get character
	local player = Players.LocalPlayer
	if player.Character then
		self._character = player.Character
	end
	
	player.CharacterAdded:Connect(function(character)
		self._character = character
	end)
	
	-- Update targeting every frame
	local updateConn = RunService.Heartbeat:Connect(function()
		self:UpdateTargeting()
	end)
	table.insert(self._connections, updateConn)
end

return ReticleController

