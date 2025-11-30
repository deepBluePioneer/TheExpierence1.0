--[[
	PhotoTargetController
	Handles photo target detection, crosshair changes, and gaze progress bar
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Fusion = require(CustomPackages:WaitForChild("FusionRoot"):WaitForChild("Fusion"))
local Gizmo = require(Packages.imgizmo)

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring

-- Tags
local ENTITY_TAG = "entity"
local GRID_CUBE_TAG = "gridCube"
local PHOTO_TARGET_TAG = "PhotoTarget"
local PARTICLE_GROUP_TAG = "particleGroup"

local PhotoTargetController = Knit.CreateController {
	Name = "PhotoTargetController",
	screenGui = nil,
	worldReticle = nil, -- Container for world-space reticle parts
}

-- === CONFIG ===
local TARGET_CONFIG = {
	-- Raycast
	RaycastMaxDistance = 2000,
	
	-- Gaze progress
	GazeFillTime = 2.0,
	
	-- Debug
	DebugGizmosEnabled = true,
	DebugGizmosOnClick = true,
	DebugLineColor = Color3.fromRGB(0, 255, 0),
	DebugLineMissColor = Color3.fromRGB(255, 0, 0),
	DebugLineNoTagColor = Color3.fromRGB(255, 255, 0),
	DebugHitPointSize = 0.5,
	DebugLineDuration = 0.1,
	
	-- Crosshair
	CrosshairEnabled = true,
	OverlayColor = Color3.fromRGB(255, 255, 255),
	TargetColor = Color3.fromRGB(0, 255, 0),
	TargetActiveColor = Color3.fromRGB(50, 255, 100),
	CapturedColor = Color3.fromRGB(100, 255, 150),
	
	-- Capture UI
	ProgressBarSegments = 20,
	ScanLineSpeed = 1.5,
	
	-- World-Space Reticle
	WorldReticleEnabled = true,
	WorldReticleColor = Color3.fromRGB(0, 255, 100),
	WorldReticleActiveColor = Color3.fromRGB(100, 255, 150),
	WorldReticleCapturedColor = Color3.fromRGB(150, 255, 200),
	WorldReticleThickness = 0.03, -- Thickness of bracket lines
	WorldReticlePadding = 0.15, -- Extra padding around target bounding box
	WorldReticleCornerLength = 0.25, -- Length of corner brackets (as fraction of size)
	WorldReticleTransparency = 0.2,
}

-- === STATE ===
local isLookingAtPhotoTarget = Value(false)
local currentTargetInstance = nil
local gazeProgress = Value(0)
local crosshairScale = Value(1)
local crosshairScaleSpring = Spring(crosshairScale, 25, 0.8)
local isMouseButtonHeld = false
local targetName = Value("---")
local scanLineOffset = Value(0)
local isCaptured = Value(false)

-- Crosshair bracket animation state (module level for proper reactivity)
local bracketInsetValue = Value(1.0)
local bracketInsetSpring = Spring(bracketInsetValue, 25, 0.8)
local crosshairSizeValue = Value(1.0)
local crosshairSizeSpring = Spring(crosshairSizeValue, 30, 0.7)

-- === DEBUG GIZMOS ===
local gizmoInitialized = false

local function initGizmo()
	if not gizmoInitialized then
		Gizmo.Init()
		gizmoInitialized = true
	end
end

local function shouldDrawGizmos()
	if not TARGET_CONFIG.DebugGizmosEnabled then return false end
	if TARGET_CONFIG.DebugGizmosOnClick then
		return isMouseButtonHeld
	end
	return true
end

local function drawDebugRay(startPos, endPos, color, duration)
	if not shouldDrawGizmos() then return end
	initGizmo()
	
	-- Set style: Color, Transparency, AlwaysOnTop
	Gizmo.SetStyle(color, 0, true)
	-- Ray:Draw(Origin, Direction)
	Gizmo.Ray:Draw(startPos, endPos - startPos)
end

local function drawDebugSphere(position, color, radius, duration, label)
	if not shouldDrawGizmos() then return end
	initGizmo()
	
	-- Set style: Color, Transparency, AlwaysOnTop
	Gizmo.SetStyle(color, 0, true)
	-- Sphere:Draw(Transform, Radius, Subdivisions, Angle)
	Gizmo.Sphere:Draw(CFrame.new(position), radius, 8, 360)
end

-- === WORLD-SPACE RETICLE ===

local worldReticleFolder = nil
local worldReticleParts = {}
local currentReticleTarget = nil
local reticleTargetSize = Value(Vector3.new(1, 1, 1))
local reticleTargetCFrame = Value(CFrame.new())
local reticleSizeSpring = Spring(reticleTargetSize, 20, 0.8)
local reticleCFrameSpring = Spring(reticleTargetCFrame, 25, 0.7)

local function getModelBoundingBox(instance)
	-- Get the bounding box of a model or part
	if instance:IsA("Model") then
		local cf, size = instance:GetBoundingBox()
		return cf, size
	elseif instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	else
		-- Try to find a primary part or any BasePart
		local primaryPart = instance:FindFirstChild("PrimaryPart") or instance:FindFirstChildWhichIsA("BasePart", true)
		if primaryPart then
			if instance:IsA("Model") then
				return instance:GetBoundingBox()
			else
				return primaryPart.CFrame, primaryPart.Size
			end
		end
	end
	return CFrame.new(), Vector3.new(1, 1, 1)
end

local function createWorldReticlePart(name, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = TARGET_CONFIG.WorldReticleColor
	part.Transparency = TARGET_CONFIG.WorldReticleTransparency
	part.Parent = parent
	return part
end

local function createWorldReticle()
	if worldReticleFolder then return end
	
	worldReticleFolder = Instance.new("Folder")
	worldReticleFolder.Name = "WorldReticle"
	worldReticleFolder.Parent = workspace.CurrentCamera
	
	-- Create corner bracket parts (8 corners x 3 lines each = 24 parts)
	local cornerNames = {
		"TopFrontLeft", "TopFrontRight", "TopBackLeft", "TopBackRight",
		"BottomFrontLeft", "BottomFrontRight", "BottomBackLeft", "BottomBackRight"
	}
	
	for _, cornerName in ipairs(cornerNames) do
		worldReticleParts[cornerName] = {
			X = createWorldReticlePart(cornerName .. "_X", worldReticleFolder),
			Y = createWorldReticlePart(cornerName .. "_Y", worldReticleFolder),
			Z = createWorldReticlePart(cornerName .. "_Z", worldReticleFolder),
		}
	end
end

local function updateWorldReticleVisibility(visible)
	if not worldReticleFolder then return end
	
	for _, cornerParts in pairs(worldReticleParts) do
		for _, part in pairs(cornerParts) do
			part.Transparency = visible and TARGET_CONFIG.WorldReticleTransparency or 1
		end
	end
end

local function updateWorldReticleColor(color)
	if not worldReticleFolder then return end
	
	for _, cornerParts in pairs(worldReticleParts) do
		for _, part in pairs(cornerParts) do
			part.Color = color
		end
	end
end

local function updateWorldReticle(targetInstance, deltaTime)
	if not TARGET_CONFIG.WorldReticleEnabled then
		updateWorldReticleVisibility(false)
		return
	end
	
	if not worldReticleFolder then
		createWorldReticle()
	end
	
	if not targetInstance then
		updateWorldReticleVisibility(false)
		currentReticleTarget = nil
		return
	end
	
	-- Get target bounding box
	local targetCF, targetSize = getModelBoundingBox(targetInstance)
	
	-- Add padding
	local padding = TARGET_CONFIG.WorldReticlePadding
	local paddedSize = targetSize + Vector3.new(padding * 2, padding * 2, padding * 2)
	
	-- Update spring targets
	if currentReticleTarget ~= targetInstance then
		-- New target - snap to position first time
		reticleTargetSize:set(paddedSize)
		reticleTargetCFrame:set(targetCF)
		currentReticleTarget = targetInstance
	else
		-- Same target - smooth interpolation
		reticleTargetSize:set(paddedSize)
		reticleTargetCFrame:set(targetCF)
	end
	
	-- Get animated values
	local animSize = reticleSizeSpring:get()
	local animCF = reticleCFrameSpring:get()
	
	local halfSize = animSize / 2
	local thickness = TARGET_CONFIG.WorldReticleThickness
	local cornerLength = TARGET_CONFIG.WorldReticleCornerLength
	
	-- Calculate actual corner lengths based on size
	local cornerLenX = math.min(animSize.X * cornerLength, animSize.X * 0.4)
	local cornerLenY = math.min(animSize.Y * cornerLength, animSize.Y * 0.4)
	local cornerLenZ = math.min(animSize.Z * cornerLength, animSize.Z * 0.4)
	
	-- Update color based on state
	local color = TARGET_CONFIG.WorldReticleColor
	if isCaptured:get() then
		color = TARGET_CONFIG.WorldReticleCapturedColor
	elseif gazeProgress:get() > 0 then
		-- Lerp between base and active color
		local t = gazeProgress:get()
		color = TARGET_CONFIG.WorldReticleColor:Lerp(TARGET_CONFIG.WorldReticleActiveColor, t)
	end
	updateWorldReticleColor(color)
	
	-- Corner offsets (relative to center)
	local corners = {
		TopFrontLeft = Vector3.new(-1, 1, -1),
		TopFrontRight = Vector3.new(1, 1, -1),
		TopBackLeft = Vector3.new(-1, 1, 1),
		TopBackRight = Vector3.new(1, 1, 1),
		BottomFrontLeft = Vector3.new(-1, -1, -1),
		BottomFrontRight = Vector3.new(1, -1, -1),
		BottomBackLeft = Vector3.new(-1, -1, 1),
		BottomBackRight = Vector3.new(1, -1, 1),
	}
	
	-- Direction multipliers for each corner's bracket lines
	local cornerDirs = {
		TopFrontLeft = { X = 1, Y = -1, Z = 1 },
		TopFrontRight = { X = -1, Y = -1, Z = 1 },
		TopBackLeft = { X = 1, Y = -1, Z = -1 },
		TopBackRight = { X = -1, Y = -1, Z = -1 },
		BottomFrontLeft = { X = 1, Y = 1, Z = 1 },
		BottomFrontRight = { X = -1, Y = 1, Z = 1 },
		BottomBackLeft = { X = 1, Y = 1, Z = -1 },
		BottomBackRight = { X = -1, Y = 1, Z = -1 },
	}
	
	for cornerName, offset in pairs(corners) do
		local cornerPos = animCF:PointToWorldSpace(Vector3.new(
			offset.X * halfSize.X,
			offset.Y * halfSize.Y,
			offset.Z * halfSize.Z
		))
		
		local dirs = cornerDirs[cornerName]
		local parts = worldReticleParts[cornerName]
		
		if parts then
			-- X line (horizontal along X axis)
			local xLinePos = cornerPos + animCF:VectorToWorldSpace(Vector3.new(dirs.X * cornerLenX / 2, 0, 0))
			parts.X.Size = Vector3.new(cornerLenX, thickness, thickness)
			parts.X.CFrame = CFrame.new(xLinePos) * animCF.Rotation
			
			-- Y line (vertical along Y axis)
			local yLinePos = cornerPos + animCF:VectorToWorldSpace(Vector3.new(0, dirs.Y * cornerLenY / 2, 0))
			parts.Y.Size = Vector3.new(thickness, cornerLenY, thickness)
			parts.Y.CFrame = CFrame.new(yLinePos) * animCF.Rotation
			
			-- Z line (horizontal along Z axis)
			local zLinePos = cornerPos + animCF:VectorToWorldSpace(Vector3.new(0, 0, dirs.Z * cornerLenZ / 2))
			parts.Z.Size = Vector3.new(thickness, thickness, cornerLenZ)
			parts.Z.CFrame = CFrame.new(zLinePos) * animCF.Rotation
		end
	end
	
	updateWorldReticleVisibility(true)
end

local function cleanupWorldReticle()
	if worldReticleFolder then
		worldReticleFolder:Destroy()
		worldReticleFolder = nil
		worldReticleParts = {}
		currentReticleTarget = nil
	end
end

-- === TAG HELPERS ===

local function hasEntityTag(instance)
	if not instance then return false, nil end
	
	local current = instance
	while current do
		if CollectionService:HasTag(current, ENTITY_TAG) then
			return true, current
		end
		current = current.Parent
	end
	return false, nil
end

local function hasPhotoTargetTag(instance)
	if not instance then return false, nil end
	
	local current = instance
	while current do
		if CollectionService:HasTag(current, PHOTO_TARGET_TAG) then
			return true, current
		end
		current = current.Parent
	end
	return false, nil
end

-- === RAYCAST ===

local function performRaycast()
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	
	local viewportSize = camera.ViewportSize
	local centerScreenPos = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
	local unitRay = camera:ViewportPointToRay(centerScreenPos.X, centerScreenPos.Y)
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local excludeList = {}
	
	-- Exclude player character
	local player = Players.LocalPlayer
	if player and player.Character then
		table.insert(excludeList, player.Character)
		for _, descendant in ipairs(player.Character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(excludeList, descendant)
			end
		end
	end
	
	-- Exclude grid cubes
	local gridCubes = CollectionService:GetTagged(GRID_CUBE_TAG)
	for _, cube in ipairs(gridCubes) do
		table.insert(excludeList, cube)
	end
	
	-- Exclude particle groups
	local particleGroups = CollectionService:GetTagged(PARTICLE_GROUP_TAG)
	for _, part in ipairs(particleGroups) do
		table.insert(excludeList, part)
	end
	
	raycastParams.FilterDescendantsInstances = excludeList
	
	return workspace:Raycast(
		unitRay.Origin,
		unitRay.Direction * TARGET_CONFIG.RaycastMaxDistance,
		raycastParams
	), unitRay
end

-- === CROSSHAIR UI ===

local function createCrosshair(parent, animatedTransparency)
	-- Crosshair dimensions
	local crossSizeX = 0.015
	local crossSizeY = 0.027
	local gapSizeX = 0.007
	local gapSizeY = 0.013
	local thicknessX = 0.0014
	local thicknessY = 0.0026
	
	local crosshairColor = Computed(function()
		if isCaptured:get() then
			return TARGET_CONFIG.CapturedColor
		elseif isLookingAtPhotoTarget:get() then
			return TARGET_CONFIG.TargetColor
		else
			return TARGET_CONFIG.OverlayColor
		end
	end)
	
	-- Use module-level spring for size animation
	local animatedSize = crosshairSizeSpring
	
	return New "Frame" {
		Name = "Crosshair",
		Size = Computed(function()
			local mult = animatedSize:get()
			return UDim2.new(0.08 * mult, 0, 0.14 * mult, 0)
		end),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
		
		[Children] = {
			-- Center dot (small)
			New "Frame" {
				Name = "CenterDot",
				Size = UDim2.new(0.04, 0, 0.022, 0),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = Computed(function()
					return 0.3 + animatedTransparency:get() * 0.7
				end),
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(1, 0) },
					New "UIAspectRatioConstraint" { AspectRatio = 1 },
				},
			},
			
			-- Center circle (outer ring)
			New "Frame" {
				Name = "CenterCircle",
				Size = Computed(function()
					local mult = animatedSize:get()
					return UDim2.new(0.12 * mult, 0, 0.068 * mult, 0)
				end),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(1, 0) },
					New "UIStroke" {
						Color = crosshairColor,
						Thickness = 1.5,
						Transparency = animatedTransparency,
					},
					New "UIAspectRatioConstraint" { AspectRatio = 1 },
				},
			},
			
			-- Cross lines: Top
			New "Frame" {
				Size = Computed(function()
					local mult = animatedSize:get()
					return UDim2.new(thicknessX * mult, 0, crossSizeY * mult, 0)
				end),
				Position = Computed(function()
					local mult = animatedSize:get()
					return UDim2.new(0.5, 0, 0.5 - gapSizeY * mult - crossSizeY * mult, 0)
				end),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Cross lines: Bottom
			New "Frame" {
				Size = Computed(function()
					local mult = animatedSize:get()
					return UDim2.new(thicknessX * mult, 0, crossSizeY * mult, 0)
				end),
				Position = Computed(function()
					local mult = animatedSize:get()
					return UDim2.new(0.5, 0, 0.5 + gapSizeY * mult, 0)
				end),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Cross lines: Left
			New "Frame" {
				Size = Computed(function()
					local mult = animatedSize:get()
					return UDim2.new(crossSizeX * mult, 0, thicknessY * mult, 0)
				end),
				Position = Computed(function()
					local mult = animatedSize:get()
					return UDim2.new(0.5 - gapSizeX * mult - crossSizeX * mult, 0, 0.5, 0)
				end),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Cross lines: Right
			New "Frame" {
				Size = Computed(function()
					local mult = animatedSize:get()
					return UDim2.new(crossSizeX * mult, 0, thicknessY * mult, 0)
				end),
				Position = Computed(function()
					local mult = animatedSize:get()
					return UDim2.new(0.5 + gapSizeX * mult, 0, 0.5, 0)
				end),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = crosshairColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
		},
	}
end

-- === GAZE PROGRESS BAR ===

local function createSegmentedProgressBar(parent, animatedTransparency)
	local segments = {}
	local segmentCount = TARGET_CONFIG.ProgressBarSegments
	local segmentWidth = 1 / segmentCount
	local segmentGap = 0.15 -- Gap between segments as fraction of segment width
	
	for i = 1, segmentCount do
		local segmentProgress = (i - 1) / segmentCount
		table.insert(segments, New "Frame" {
			Name = "Segment" .. i,
			Size = UDim2.new(segmentWidth * (1 - segmentGap), 0, 1, 0),
			Position = UDim2.new((i - 1) * segmentWidth, 0, 0, 0),
			BackgroundColor3 = Computed(function()
				local progress = gazeProgress:get()
				local captured = isCaptured:get()
				if captured then
					return TARGET_CONFIG.CapturedColor
				elseif progress > segmentProgress then
					return TARGET_CONFIG.TargetActiveColor
				else
					return Color3.fromRGB(60, 60, 60)
				end
			end),
			BackgroundTransparency = Computed(function()
				local progress = gazeProgress:get()
				if progress > segmentProgress then
					return animatedTransparency:get()
				else
					return 0.6 + animatedTransparency:get() * 0.4
				end
			end),
			BorderSizePixel = 0,
			[Children] = {
				New "UICorner" { CornerRadius = UDim.new(0.3, 0) },
			},
		})
	end
	
	return New "Frame" {
		Name = "SegmentedProgress",
		Size = UDim2.new(1, 0, 0.18, 0),
		Position = UDim2.new(0, 0, 0.55, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		[Children] = segments,
	}
end

local function createGazeProgressBar(parent, animatedTransparency)
	return New "Frame" {
		Name = "CaptureUI",
		Size = UDim2.new(0.22, 0, 0.12, 0),
		Position = UDim2.new(0.5, 0, 0.82, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = Computed(function()
			return isLookingAtPhotoTarget:get()
		end),
		Parent = parent,
		
		[Children] = {
			-- Top bracket left
			New "Frame" {
				Size = UDim2.new(0.04, 0, 0.008, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = TARGET_CONFIG.TargetColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0.006, 0, 0.08, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = TARGET_CONFIG.TargetColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Top bracket right
			New "Frame" {
				Size = UDim2.new(0.04, 0, 0.008, 0),
				Position = UDim2.new(1, 0, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = TARGET_CONFIG.TargetColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0.006, 0, 0.08, 0),
				Position = UDim2.new(1, 0, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = TARGET_CONFIG.TargetColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Bottom bracket left
			New "Frame" {
				Size = UDim2.new(0.04, 0, 0.008, 0),
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = TARGET_CONFIG.TargetColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0.006, 0, 0.08, 0),
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = TARGET_CONFIG.TargetColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			-- Bottom bracket right
			New "Frame" {
				Size = UDim2.new(0.04, 0, 0.008, 0),
				Position = UDim2.new(1, 0, 1, 0),
				AnchorPoint = Vector2.new(1, 1),
				BackgroundColor3 = TARGET_CONFIG.TargetColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			New "Frame" {
				Size = UDim2.new(0.006, 0, 0.08, 0),
				Position = UDim2.new(1, 0, 1, 0),
				AnchorPoint = Vector2.new(1, 1),
				BackgroundColor3 = TARGET_CONFIG.TargetColor,
				BackgroundTransparency = animatedTransparency,
				BorderSizePixel = 0,
			},
			
			-- Content container
			New "Frame" {
				Name = "Content",
				Size = UDim2.new(0.88, 0, 0.85, 0),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				
				[Children] = {
					-- Status indicator
					New "Frame" {
						Name = "StatusRow",
						Size = UDim2.new(1, 0, 0.28, 0),
						Position = UDim2.new(0, 0, 0, 0),
						BackgroundTransparency = 1,
						
						[Children] = {
							-- Blinking dot
							New "Frame" {
								Name = "StatusDot",
								Size = UDim2.new(0.035, 0, 0.7, 0),
								Position = UDim2.new(0, 0, 0.5, 0),
								AnchorPoint = Vector2.new(0, 0.5),
								BackgroundColor3 = Computed(function()
									if isCaptured:get() then
										return TARGET_CONFIG.CapturedColor
									else
										return TARGET_CONFIG.TargetColor
									end
								end),
								BackgroundTransparency = Computed(function()
									local t = scanLineOffset:get()
									if isCaptured:get() then
										return animatedTransparency:get()
									else
										return math.abs(math.sin(t * 3)) * 0.5 + animatedTransparency:get()
									end
								end),
								BorderSizePixel = 0,
								[Children] = {
									New "UICorner" { CornerRadius = UDim.new(1, 0) },
									New "UIAspectRatioConstraint" { AspectRatio = 1 },
								},
							},
							-- Status text
							New "TextLabel" {
								Name = "StatusText",
								Size = UDim2.new(0.45, 0, 1, 0),
								Position = UDim2.new(0.055, 0, 0, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.RobotoMono,
								TextScaled = true,
								TextColor3 = Computed(function()
									if isCaptured:get() then
										return TARGET_CONFIG.CapturedColor
									else
										return TARGET_CONFIG.TargetColor
									end
								end),
								TextTransparency = animatedTransparency,
								TextXAlignment = Enum.TextXAlignment.Left,
								Text = Computed(function()
									if isCaptured:get() then
										return "◉ CAPTURED"
									else
										return "◎ SCANNING"
									end
								end),
							},
							-- Progress percentage
							New "TextLabel" {
								Name = "ProgressPercent",
								Size = UDim2.new(0.35, 0, 1, 0),
								Position = UDim2.new(1, 0, 0, 0),
								AnchorPoint = Vector2.new(1, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.RobotoMono,
								TextScaled = true,
								TextColor3 = TARGET_CONFIG.OverlayColor,
								TextTransparency = animatedTransparency,
								TextXAlignment = Enum.TextXAlignment.Right,
								Text = Computed(function()
									local progress = gazeProgress:get()
									return string.format("%d%%", math.floor(progress * 100))
								end),
							},
						},
					},
					
					-- Segmented progress bar
					createSegmentedProgressBar(nil, animatedTransparency),
					
					-- Target info row
					New "Frame" {
						Name = "TargetRow",
						Size = UDim2.new(1, 0, 0.25, 0),
						Position = UDim2.new(0, 0, 0.78, 0),
						BackgroundTransparency = 1,
						
						[Children] = {
							New "TextLabel" {
								Name = "TargetLabel",
								Size = UDim2.new(0.25, 0, 1, 0),
								Position = UDim2.new(0, 0, 0, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.RobotoMono,
								TextScaled = true,
								TextColor3 = Color3.fromRGB(150, 150, 150),
								TextTransparency = animatedTransparency,
								TextXAlignment = Enum.TextXAlignment.Left,
								Text = "TARGET:",
							},
							New "TextLabel" {
								Name = "TargetName",
								Size = UDim2.new(0.72, 0, 1, 0),
								Position = UDim2.new(0.28, 0, 0, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.RobotoMono,
								TextScaled = true,
								TextColor3 = TARGET_CONFIG.OverlayColor,
								TextTransparency = animatedTransparency,
								TextXAlignment = Enum.TextXAlignment.Left,
								Text = Computed(function()
									return targetName:get()
								end),
							},
						},
					},
				},
			},
		},
	}
end

-- === TARGET DETECTION ===

local function checkPhotoTargetInView(deltaTime)
	local raycastResult, unitRay = performRaycast()
	
	-- Debug visualization
	if TARGET_CONFIG.DebugGizmosEnabled and unitRay then
		local endPos = unitRay.Origin + unitRay.Direction * TARGET_CONFIG.RaycastMaxDistance
		if raycastResult then
			endPos = raycastResult.Position
			local hasTag, _ = hasPhotoTargetTag(raycastResult.Instance)
			local color = hasTag and TARGET_CONFIG.DebugLineColor or TARGET_CONFIG.DebugLineNoTagColor
			drawDebugRay(unitRay.Origin, endPos, color, TARGET_CONFIG.DebugLineDuration)
			drawDebugSphere(endPos, color, TARGET_CONFIG.DebugHitPointSize, TARGET_CONFIG.DebugLineDuration)
		else
			drawDebugRay(unitRay.Origin, endPos, TARGET_CONFIG.DebugLineMissColor, TARGET_CONFIG.DebugLineDuration)
		end
	end
	
	local hitPhotoTarget = false
	local hitTargetInstance = nil
	if raycastResult then
		hitPhotoTarget, hitTargetInstance = hasPhotoTargetTag(raycastResult.Instance)
	end
	
	local dt = deltaTime or 0.016
	
	-- Update scan line animation
	scanLineOffset:set(scanLineOffset:get() + dt * TARGET_CONFIG.ScanLineSpeed)
	
	if hitPhotoTarget then
		-- Check if target changed
		if hitTargetInstance ~= currentTargetInstance then
			gazeProgress:set(0)
			isCaptured:set(false)
			currentTargetInstance = hitTargetInstance
		end
		
		-- Update target name
		if hitTargetInstance then
			local name = hitTargetInstance.Name or "Unknown"
			-- Clean up the name
			name = name:gsub("_", " "):upper()
			if #name > 20 then
				name = name:sub(1, 17) .. "..."
			end
			targetName:set(name)
		end
		
		-- Set targeting state
		isLookingAtPhotoTarget:set(true)
		
		-- Always update crosshair animations when targeting
		crosshairSizeValue:set(1.2)
		bracketInsetValue:set(1.15)
		
		-- Update gaze progress
		local currentProgress = gazeProgress:get()
		if currentProgress < 1 then
			local newProgress = currentProgress + (dt / TARGET_CONFIG.GazeFillTime)
			gazeProgress:set(math.min(newProgress, 1))
			
			-- Check if just captured
			if newProgress >= 1 and not isCaptured:get() then
				isCaptured:set(true)
			end
		end
		
		-- Update world-space reticle around target
		updateWorldReticle(hitTargetInstance, dt)
	else
		-- Reset when not looking at target
		isLookingAtPhotoTarget:set(false)
		
		-- Always reset crosshair animations when not targeting
		crosshairSizeValue:set(1.0)
		bracketInsetValue:set(1.0)
		
		gazeProgress:set(0)
		isCaptured:set(false)
		targetName:set("---")
		currentTargetInstance = nil
		
		-- Hide world-space reticle
		updateWorldReticle(nil, dt)
	end
end

-- === UI CREATION ===

local function createTargetUI(self)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	local effectTransparency = Value(0)
	local animatedTransparency = Spring(effectTransparency, 20, 1)
	
	local screenGui = New "ScreenGui" {
		Name = "PhotoTargetUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 51,
		Parent = playerGui,
		
		[Children] = {
			TARGET_CONFIG.CrosshairEnabled and createCrosshair(nil, animatedTransparency) or nil,
			createGazeProgressBar(nil, animatedTransparency),
		},
	}
	
	self.screenGui = screenGui
	return screenGui
end

-- === KNIT LIFECYCLE ===

function PhotoTargetController:KnitInit()
	-- Nothing to init
end

function PhotoTargetController:KnitStart()
	createTargetUI(self)
	
	-- Initialize gizmo
	if TARGET_CONFIG.DebugGizmosEnabled then
		initGizmo()
	end
	
	-- Track mouse button for debug gizmos
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isMouseButtonHeld = true
		end
	end)
	
	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isMouseButtonHeld = false
		end
	end)
	
	-- Use RenderStepped for smoother gizmo updates
	RunService.RenderStepped:Connect(function(deltaTime)
		-- Clear previous frame's gizmos
		if TARGET_CONFIG.DebugGizmosEnabled then
			Gizmo.ScheduleCleaning()
		end
		
		checkPhotoTargetInView(deltaTime)
	end)
	
	print("[PhotoTargetController] Initialized with debug gizmos on click")
end

-- === PUBLIC METHODS ===

function PhotoTargetController:IsLookingAtTarget()
	return isLookingAtPhotoTarget:get()
end

function PhotoTargetController:GetGazeProgress()
	return gazeProgress:get()
end

function PhotoTargetController:GetCurrentTarget()
	return currentTargetInstance
end

function PhotoTargetController:EnableDebugGizmos()
	TARGET_CONFIG.DebugGizmosEnabled = true
end

function PhotoTargetController:DisableDebugGizmos()
	TARGET_CONFIG.DebugGizmosEnabled = false
	if gizmoInitialized then
		Gizmo.DoCleaning()
	end
end

function PhotoTargetController:ToggleDebugGizmos()
	if TARGET_CONFIG.DebugGizmosEnabled then
		self:DisableDebugGizmos()
	else
		self:EnableDebugGizmos()
	end
	return TARGET_CONFIG.DebugGizmosEnabled
end

-- World Reticle Methods
function PhotoTargetController:EnableWorldReticle()
	TARGET_CONFIG.WorldReticleEnabled = true
end

function PhotoTargetController:DisableWorldReticle()
	TARGET_CONFIG.WorldReticleEnabled = false
	updateWorldReticleVisibility(false)
end

function PhotoTargetController:ToggleWorldReticle()
	if TARGET_CONFIG.WorldReticleEnabled then
		self:DisableWorldReticle()
	else
		self:EnableWorldReticle()
	end
	return TARGET_CONFIG.WorldReticleEnabled
end

function PhotoTargetController:SetWorldReticleColor(color)
	TARGET_CONFIG.WorldReticleColor = color
end

function PhotoTargetController:SetWorldReticlePadding(padding)
	TARGET_CONFIG.WorldReticlePadding = padding
end

function PhotoTargetController:SetWorldReticleThickness(thickness)
	TARGET_CONFIG.WorldReticleThickness = thickness
end

function PhotoTargetController:CleanupWorldReticle()
	cleanupWorldReticle()
end

return PhotoTargetController

