--[[
	GuidanceController
	Dead Space-style guidance system - continuous glowing line following terrain to audio logs
	Press G to activate the guidance path
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local Player = Players.LocalPlayer

local GuidanceController = Knit.CreateController {
	Name = "GuidanceController",
	_isActive = false,
	_targetLog = nil,
	_updateConnection = nil,
	_pathFolder = nil,
	_pathAttachments = {},
	_beam = nil,
}

-- === CONFIG ===
local GUIDANCE_CONFIG = {
	-- Activation
	ActivationKey = Enum.KeyCode.G,
	
	-- Collection Service Tags
	AudioLogTag = "audioLog",
	TerrainCubeTag = "terrainCube",
	
	-- Visual Style
	PathColor = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 255, 255)),      -- Bright cyan at start
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 200, 220)),    -- Teal middle
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 255, 255)),    -- Light cyan at end
	}),
	PathTransparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 0.8),
	}),
	PathWidth = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 0.3),
	}),
	
	-- Path settings
	SampleDistance = 3,           -- Distance between terrain sample points
	TerrainOffset = 0.5,          -- Height above terrain
	MaxPathLength = 500,          -- Max path distance in studs
	
	-- Animation
	TextureSpeed = 2,             -- Speed of texture scrolling
	PulseSpeed = 3,
	FadeInTime = 0.4,
	FadeOutTime = 0.6,
	
	-- Beam texture (arrow pattern)
	BeamTexture = "rbxassetid://446111271",  -- Arrow/chevron pattern
	
	-- Target marker
	MarkerColor = Color3.fromRGB(0, 255, 255),
	MarkerPulseSpeed = 2,
}

-- === STATE ===
local animationPhase = 0
local targetMarker = nil

-- === HELPER FUNCTIONS ===

local function getPlayerPosition()
	local character = Player.Character
	if not character then return nil end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	
	return hrp.Position
end

-- Get terrain height at a world position using CollectionService tagged terrain cubes
local function getTerrainHeightAt(worldX, worldZ)
	local terrainCubes = CollectionService:GetTagged(GUIDANCE_CONFIG.TerrainCubeTag)
	
	local closestCube = nil
	local closestDist = math.huge
	
	for _, cube in ipairs(terrainCubes) do
		if cube:IsA("BasePart") then
			local cubePos = cube.Position
			local cubeSize = cube.Size
			
			-- Check if position is within cube's XZ bounds
			local halfX = cubeSize.X / 2
			local halfZ = cubeSize.Z / 2
			
			if worldX >= (cubePos.X - halfX) and worldX <= (cubePos.X + halfX) and
			   worldZ >= (cubePos.Z - halfZ) and worldZ <= (cubePos.Z + halfZ) then
				-- Position is inside this cube's XZ bounds
				return cubePos.Y + (cubeSize.Y / 2) + GUIDANCE_CONFIG.TerrainOffset
			end
			
			-- Track closest cube as fallback
			local dist = math.sqrt((cubePos.X - worldX)^2 + (cubePos.Z - worldZ)^2)
			if dist < closestDist then
				closestDist = dist
				closestCube = cube
			end
		end
	end
	
	-- Use closest cube if no direct hit
	if closestCube then
		return closestCube.Position.Y + (closestCube.Size.Y / 2) + GUIDANCE_CONFIG.TerrainOffset
	end
	
	-- Fallback: raycast down
	local rayOrigin = Vector3.new(worldX, 100, worldZ)
	local rayDirection = Vector3.new(0, -200, 0)
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {Player.Character}
	
	local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
	if result then
		return result.Position.Y + GUIDANCE_CONFIG.TerrainOffset
	end
	
	return 0 + GUIDANCE_CONFIG.TerrainOffset
end

-- Get all audio logs using CollectionService
local function getAllAudioLogs()
	local logs = {}
	local taggedLogs = CollectionService:GetTagged(GUIDANCE_CONFIG.AudioLogTag)
	
	for _, log in ipairs(taggedLogs) do
		if log:IsA("Model") or log:IsA("BasePart") then
			table.insert(logs, log)
		end
	end
	
	return logs
end

local function getRandomAudioLog()
	local logs = getAllAudioLogs()
	if #logs == 0 then return nil end
	return logs[math.random(1, #logs)]
end

local function getLogPosition(log)
	if not log then return nil end
	
	if log:IsA("Model") then
		if log.PrimaryPart then
			return log.PrimaryPart.Position
		else
			local firstPart = log:FindFirstChildWhichIsA("BasePart")
			if firstPart then
				return firstPart.Position
			end
		end
	elseif log:IsA("BasePart") then
		return log.Position
	end
	
	return nil
end

-- === PATH CREATION ===

local function createPathFolder()
	-- Clean up existing folder
	local existing = Workspace:FindFirstChild("GuidancePath")
	if existing then
		existing:Destroy()
	end
	
	local folder = Instance.new("Folder")
	folder.Name = "GuidancePath"
	folder.Parent = Workspace
	return folder
end

-- Generate path points that follow terrain
local function generatePathPoints(startPos, endPos)
	local points = {}
	
	local direction = endPos - startPos
	local distance = direction.Magnitude
	local dirNormalized = direction.Unit
	
	-- Clamp distance
	if distance > GUIDANCE_CONFIG.MaxPathLength then
		distance = GUIDANCE_CONFIG.MaxPathLength
	end
	
	local numSamples = math.ceil(distance / GUIDANCE_CONFIG.SampleDistance)
	numSamples = math.max(numSamples, 2)
	
	for i = 0, numSamples do
		local t = i / numSamples
		local worldX = startPos.X + dirNormalized.X * distance * t
		local worldZ = startPos.Z + dirNormalized.Z * distance * t
		
		-- Get terrain height at this point
		local terrainY = getTerrainHeightAt(worldX, worldZ)
		
		local point = Vector3.new(worldX, terrainY, worldZ)
		table.insert(points, point)
	end
	
	return points
end

-- Create attachments for the beam to follow
local function createPathAttachments(points, folder)
	local attachments = {}
	
	-- Create a single part to hold all attachments
	local pathPart = Instance.new("Part")
	pathPart.Name = "PathLine"
	pathPart.Anchored = true
	pathPart.CanCollide = false
	pathPart.CanQuery = false
	pathPart.CanTouch = false
	pathPart.Transparency = 1
	pathPart.Size = Vector3.new(1, 1, 1)
	pathPart.Position = points[1]
	pathPart.Parent = folder
	
	-- Create attachments at each path point
	for i, point in ipairs(points) do
		local attachment = Instance.new("Attachment")
		attachment.Name = "PathPoint_" .. i
		attachment.WorldPosition = point
		attachment.Parent = pathPart
		table.insert(attachments, attachment)
	end
	
	return attachments, pathPart
end

-- Create the continuous beam
local function createBeam(attachments, folder)
	if #attachments < 2 then return nil end
	
	-- We need to create multiple beam segments between consecutive attachments
	local beams = {}
	
	for i = 1, #attachments - 1 do
		local beam = Instance.new("Beam")
		beam.Name = "GuidanceBeam_" .. i
		beam.Attachment0 = attachments[i]
		beam.Attachment1 = attachments[i + 1]
		
		-- Visual properties
		beam.Color = GUIDANCE_CONFIG.PathColor
		beam.Transparency = GUIDANCE_CONFIG.PathTransparency
		beam.Width0 = 0.8
		beam.Width1 = 0.7
		beam.FaceCamera = true
		beam.LightEmission = 0.8
		beam.LightInfluence = 0
		
		-- Texture for flowing effect
		beam.Texture = GUIDANCE_CONFIG.BeamTexture
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 2
		beam.TextureSpeed = GUIDANCE_CONFIG.TextureSpeed
		
		-- Segments for smooth curves
		beam.Segments = 3
		
		-- Start invisible for fade-in
		beam.Enabled = true
		beam.Brightness = 0
		
		beam.Parent = folder
		table.insert(beams, beam)
	end
	
	return beams
end

-- Create target marker at destination
local function createTargetMarker(position, folder)
	-- Main ring
	local ring = Instance.new("Part")
	ring.Name = "TargetRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, 4, 4)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = GUIDANCE_CONFIG.MarkerColor
	ring.Transparency = 1  -- Start invisible
	ring.CastShadow = false
	ring.Parent = folder
	
	-- Vertical beam
	local vertBeam = Instance.new("Part")
	vertBeam.Name = "TargetBeam"
	vertBeam.Size = Vector3.new(0.2, 20, 0.2)
	vertBeam.Position = position + Vector3.new(0, 10, 0)
	vertBeam.Anchored = true
	vertBeam.CanCollide = false
	vertBeam.CanQuery = false
	vertBeam.Material = Enum.Material.Neon
	vertBeam.Color = GUIDANCE_CONFIG.MarkerColor
	vertBeam.Transparency = 1  -- Start invisible
	vertBeam.CastShadow = false
	vertBeam.Parent = folder
	
	-- Point light
	local light = Instance.new("PointLight")
	light.Color = GUIDANCE_CONFIG.MarkerColor
	light.Brightness = 0
	light.Range = 15
	light.Parent = ring
	
	return {ring = ring, beam = vertBeam, light = light}
end

-- Fade in the path
local function fadeInPath(beams, marker)
	-- Fade in beams with wave effect
	for i, beam in ipairs(beams) do
		task.delay(i * 0.03, function()
			if beam and beam.Parent then
				local tween = TweenService:Create(beam, 
					TweenInfo.new(GUIDANCE_CONFIG.FadeInTime, Enum.EasingStyle.Quad), 
					{Brightness = 2}
				)
				tween:Play()
			end
		end)
	end
	
	-- Fade in marker
	if marker then
		task.delay(#beams * 0.03, function()
			if marker.ring and marker.ring.Parent then
				TweenService:Create(marker.ring, 
					TweenInfo.new(0.5, Enum.EasingStyle.Quad), 
					{Transparency = 0.2}
				):Play()
			end
			if marker.beam and marker.beam.Parent then
				TweenService:Create(marker.beam, 
					TweenInfo.new(0.5, Enum.EasingStyle.Quad), 
					{Transparency = 0.4}
				):Play()
			end
			if marker.light then
				TweenService:Create(marker.light, 
					TweenInfo.new(0.5, Enum.EasingStyle.Quad), 
					{Brightness = 1.5}
				):Play()
			end
		end)
	end
end

-- Fade out and cleanup
local function fadeOutPath(beams, marker, folder)
	-- Fade out beams
	for _, beam in ipairs(beams) do
		if beam and beam.Parent then
			TweenService:Create(beam, 
				TweenInfo.new(GUIDANCE_CONFIG.FadeOutTime, Enum.EasingStyle.Quad), 
				{Brightness = 0}
			):Play()
		end
	end
	
	-- Fade out marker
	if marker then
		if marker.ring and marker.ring.Parent then
			TweenService:Create(marker.ring, 
				TweenInfo.new(GUIDANCE_CONFIG.FadeOutTime, Enum.EasingStyle.Quad), 
				{Transparency = 1}
			):Play()
		end
		if marker.beam and marker.beam.Parent then
			TweenService:Create(marker.beam, 
				TweenInfo.new(GUIDANCE_CONFIG.FadeOutTime, Enum.EasingStyle.Quad), 
				{Transparency = 1}
			):Play()
		end
		if marker.light then
			TweenService:Create(marker.light, 
				TweenInfo.new(GUIDANCE_CONFIG.FadeOutTime, Enum.EasingStyle.Quad), 
				{Brightness = 0}
			):Play()
		end
	end
	
	-- Destroy after fade
	task.delay(GUIDANCE_CONFIG.FadeOutTime + 0.1, function()
		if folder and folder.Parent then
			folder:Destroy()
		end
	end)
end

-- Update path to follow player
local function updatePath(self, beams, attachments, pathPart)
	local playerPos = getPlayerPosition()
	if not playerPos or not self._targetLog then return end
	
	local targetPos = getLogPosition(self._targetLog)
	if not targetPos then return end
	
	-- Generate new path points from current player position
	local groundPlayerPos = Vector3.new(
		playerPos.X, 
		getTerrainHeightAt(playerPos.X, playerPos.Z),
		playerPos.Z
	)
	
	local groundTargetPos = Vector3.new(
		targetPos.X,
		getTerrainHeightAt(targetPos.X, targetPos.Z),
		targetPos.Z
	)
	
	local points = generatePathPoints(groundPlayerPos, groundTargetPos)
	
	-- Update attachment positions
	for i, attachment in ipairs(attachments) do
		if points[i] then
			attachment.WorldPosition = points[i]
		end
	end
end

-- Animate the marker
local function animateMarker(marker)
	if not marker then return end
	
	animationPhase = animationPhase + 0.05
	local pulse = (math.sin(animationPhase * GUIDANCE_CONFIG.MarkerPulseSpeed) + 1) / 2
	
	if marker.ring and marker.ring.Parent then
		marker.ring.Size = Vector3.new(0.1, 3.5 + pulse * 1, 3.5 + pulse * 1)
		marker.ring.Transparency = 0.2 + pulse * 0.3
	end
	
	if marker.beam and marker.beam.Parent then
		marker.beam.Transparency = 0.3 + pulse * 0.3
	end
	
	if marker.light then
		marker.light.Brightness = 1 + pulse * 0.5
	end
end

-- === ACTIVATION ===

local function activateGuidance(self)
	if self._isActive then return end
	
	local playerPos = getPlayerPosition()
	if not playerPos then
		warn("[GuidanceController] Cannot activate - no player position")
		return
	end
	
	-- Find a random audio log to guide to
	local targetLog = getRandomAudioLog()
	if not targetLog then
		warn("[GuidanceController] No audio logs found (check 'audioLog' tag)")
		return
	end
	
	local targetPos = getLogPosition(targetLog)
	if not targetPos then
		warn("[GuidanceController] Cannot get target position")
		return
	end
	
	print("[GuidanceController] Guiding to:", targetLog.Name)
	
	self._isActive = true
	self._targetLog = targetLog
	
	-- Create path folder
	self._pathFolder = createPathFolder()
	
	-- Generate path points following terrain
	local groundPlayerPos = Vector3.new(
		playerPos.X, 
		getTerrainHeightAt(playerPos.X, playerPos.Z),
		playerPos.Z
	)
	
	local groundTargetPos = Vector3.new(
		targetPos.X,
		getTerrainHeightAt(targetPos.X, targetPos.Z),
		targetPos.Z
	)
	
	local points = generatePathPoints(groundPlayerPos, groundTargetPos)
	
	-- Create attachments and beam
	local attachments, pathPart = createPathAttachments(points, self._pathFolder)
	self._pathAttachments = attachments
	
	local beams = createBeam(attachments, self._pathFolder)
	self._beams = beams
	
	-- Create target marker
	targetMarker = createTargetMarker(groundTargetPos, self._pathFolder)
	
	-- Fade in
	fadeInPath(beams, targetMarker)
	
	-- Start update loop
	self._updateConnection = RunService.RenderStepped:Connect(function()
		if not self._isActive then return end
		
		-- Update path to follow player
		updatePath(self, beams, attachments, pathPart)
		
		-- Animate marker
		animateMarker(targetMarker)
		
		-- Check if reached target
		local currentPos = getPlayerPosition()
		if currentPos and targetPos then
			local dist = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
			if dist < 5 then
				print("[GuidanceController] Target reached!")
				self:Deactivate()
			end
		end
	end)
end

local function deactivateGuidance(self)
	if not self._isActive then return end
	
	print("[GuidanceController] Deactivating")
	
	self._isActive = false
	self._targetLog = nil
	
	-- Stop update loop
	if self._updateConnection then
		self._updateConnection:Disconnect()
		self._updateConnection = nil
	end
	
	-- Fade out and cleanup
	fadeOutPath(self._beams or {}, targetMarker, self._pathFolder)
	
	self._beams = nil
	self._pathAttachments = {}
	self._pathFolder = nil
	targetMarker = nil
end

-- === INPUT HANDLING ===

local function setupInput(self)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == GUIDANCE_CONFIG.ActivationKey then
			if self._isActive then
				deactivateGuidance(self)
			else
				activateGuidance(self)
			end
		end
	end)
end

-- === KNIT LIFECYCLE ===

function GuidanceController:KnitInit()
	print("[GuidanceController] Initializing...")
end

function GuidanceController:KnitStart()
	setupInput(self)
	
	-- Count available targets
	local logs = getAllAudioLogs()
	local terrainCubes = CollectionService:GetTagged(GUIDANCE_CONFIG.TerrainCubeTag)
	print(string.format("[GuidanceController] Ready - Found %d audio logs, %d terrain cubes", #logs, #terrainCubes))
	print("[GuidanceController] Press G to show guidance path")
end

-- === PUBLIC METHODS ===

function GuidanceController:Activate()
	activateGuidance(self)
end

function GuidanceController:Deactivate()
	deactivateGuidance(self)
end

function GuidanceController:Toggle()
	if self._isActive then
		self:Deactivate()
	else
		self:Activate()
	end
end

function GuidanceController:IsActive()
	return self._isActive
end

function GuidanceController:SetTarget(targetObject)
	if self._isActive then
		self:Deactivate()
	end
	
	-- Store target and activate
	task.spawn(function()
		task.wait(0.1)
		self._targetLog = targetObject
		activateGuidance(self)
	end)
end

function GuidanceController:GuideToClosest()
	local playerPos = getPlayerPosition()
	if not playerPos then return end
	
	local logs = getAllAudioLogs()
	local closest = nil
	local closestDist = math.huge
	
	for _, log in ipairs(logs) do
		local logPos = getLogPosition(log)
		if logPos then
			local dist = (logPos - playerPos).Magnitude
			if dist < closestDist then
				closestDist = dist
				closest = log
			end
		end
	end
	
	if closest then
		if self._isActive then
			self:Deactivate()
		end
		task.wait(0.1)
		self._targetLog = closest
		activateGuidance(self)
	end
end

function GuidanceController:GetTargetDistance()
	if not self._targetLog then return nil end
	
	local playerPos = getPlayerPosition()
	local targetPos = getLogPosition(self._targetLog)
	
	if playerPos and targetPos then
		return (targetPos - playerPos).Magnitude
	end
	
	return nil
end

function GuidanceController:GetTargetName()
	if self._targetLog then
		return self._targetLog.Name
	end
	return nil
end

-- Configuration
function GuidanceController:SetActivationKey(keyCode)
	GUIDANCE_CONFIG.ActivationKey = keyCode
end

function GuidanceController:SetPathColor(colorSequence)
	GUIDANCE_CONFIG.PathColor = colorSequence
end

function GuidanceController:SetTerrainOffset(offset)
	GUIDANCE_CONFIG.TerrainOffset = offset
end

return GuidanceController
