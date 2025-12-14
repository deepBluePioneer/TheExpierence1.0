--[[
	KudosFlyController
	
	Creates satisfying flying kudos effects when earning kudos.
	Kudos icons spawn in 3D space and fly toward the UI counter.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

local KudosFlyController = Knit.CreateController {
	Name = "KudosFlyController",
	_screenGui = nil,
	_kudosUIPosition = nil,  -- Position of kudos counter for targeting
	_activeEffects = {},
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIG                                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Icon settings
	IconSize = UDim2.new(0, 40, 0, 40),
	IconText = "⭐",
	IconTextSize = 28,
	IconColor = Color3.fromRGB(255, 200, 50),
	
	-- Spawn settings
	MaxIconsPerBurst = 15,       -- Max icons per kudos award
	IconsPerKudos = 0.5,         -- Icons spawned per kudos (e.g., 100 kudos = 50 icons, capped)
	SpawnSpread = 80,            -- Random spread when spawning (pixels)
	SpawnDelay = 0.03,           -- Delay between each icon spawn
	
	-- Flight settings
	FlightDuration = 0.6,        -- Base flight time
	FlightDurationVariance = 0.2, -- Random variance in flight time
	EasingStyle = Enum.EasingStyle.Back,
	EasingDirection = Enum.EasingDirection.In,
	
	-- Trail settings
	TrailEnabled = true,
	TrailFadeTime = 0.3,
	
	-- Scale animation
	StartScale = 1.5,            -- Icons start big
	EndScale = 0.5,              -- Icons shrink as they reach target
	
	-- Sound (optional - set to nil to disable)
	CollectSound = nil,  -- Could be a sound ID
	
	-- Target offset from kudos UI
	TargetOffset = Vector2.new(0, 0),
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SETUP                                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function KudosFlyController:CreateScreenGui()
	self._screenGui = Instance.new("ScreenGui")
	self._screenGui.Name = "KudosFlyGui"
	self._screenGui.ResetOnSpawn = false
	self._screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self._screenGui.IgnoreGuiInset = true
	self._screenGui.DisplayOrder = 100  -- Above most UI
	self._screenGui.Parent = PlayerGui
end

function KudosFlyController:FindKudosUI()
	-- Find the kudos counter UI to get target position
	local kudosGui = PlayerGui:FindFirstChild("KudosGui")
	if kudosGui then
		local container = kudosGui:FindFirstChild("Container", true)
		if container then
			self._kudosUIPosition = container.AbsolutePosition + container.AbsoluteSize / 2
			return true
		end
	end
	
	-- Fallback position (top left area)
	self._kudosUIPosition = Vector2.new(100, 80)
	return false
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         EFFECT CREATION                                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function KudosFlyController:CreateKudosIcon(startPosition)
	local icon = Instance.new("TextLabel")
	icon.Name = "FlyingKudos"
	icon.Size = CONFIG.IconSize
	icon.Position = UDim2.new(0, startPosition.X - CONFIG.IconSize.X.Offset/2, 0, startPosition.Y - CONFIG.IconSize.Y.Offset/2)
	icon.BackgroundTransparency = 1
	icon.Text = CONFIG.IconText
	icon.TextSize = CONFIG.IconTextSize
	icon.TextColor3 = CONFIG.IconColor
	icon.Font = Enum.Font.GothamBold
	icon.ZIndex = 10
	icon.Parent = self._screenGui
	
	-- Add glow effect
	local glow = Instance.new("UIStroke")
	glow.Color = CONFIG.IconColor
	glow.Thickness = 2
	glow.Transparency = 0.5
	glow.Parent = icon
	
	-- Start scaled up
	icon.TextSize = CONFIG.IconTextSize * CONFIG.StartScale
	
	return icon
end

function KudosFlyController:SpawnFlyingKudos(worldPosition, amount)
	-- Update target position
	self:FindKudosUI()
	
	-- Convert world position to screen position
	local screenPos, onScreen = Camera:WorldToScreenPoint(worldPosition)
	if not onScreen then
		-- If off screen, use center of screen
		screenPos = Vector3.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2, 0)
	end
	
	local startScreenPos = Vector2.new(screenPos.X, screenPos.Y)
	
	-- Calculate number of icons to spawn
	local numIcons = math.min(math.ceil(amount * CONFIG.IconsPerKudos), CONFIG.MaxIconsPerBurst)
	numIcons = math.max(numIcons, 3)  -- Minimum 3 icons
	
	-- Spawn icons with staggered timing
	for i = 1, numIcons do
		task.delay((i - 1) * CONFIG.SpawnDelay, function()
			self:SpawnSingleIcon(startScreenPos, i, numIcons)
		end)
	end
end

function KudosFlyController:SpawnSingleIcon(startPos, index, total)
	-- Add random spread to start position
	local spreadX = (math.random() - 0.5) * CONFIG.SpawnSpread * 2
	local spreadY = (math.random() - 0.5) * CONFIG.SpawnSpread * 2
	local actualStart = Vector2.new(startPos.X + spreadX, startPos.Y + spreadY)
	
	-- Create icon
	local icon = self:CreateKudosIcon(actualStart)
	
	-- Calculate target position
	local targetPos = self._kudosUIPosition + CONFIG.TargetOffset
	
	-- Random flight duration
	local duration = CONFIG.FlightDuration + (math.random() - 0.5) * CONFIG.FlightDurationVariance * 2
	
	-- Create flight path with slight curve
	local midPoint = actualStart:Lerp(targetPos, 0.5)
	local curveOffset = (math.random() - 0.5) * 100
	midPoint = midPoint + Vector2.new(curveOffset, -50 - math.random() * 30)  -- Arc upward
	
	-- Animate using bezier-like motion
	self:AnimateIconFlight(icon, actualStart, midPoint, targetPos, duration)
end

function KudosFlyController:AnimateIconFlight(icon, startPos, midPos, endPos, duration)
	local startTime = tick()
	local connection
	
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local progress = math.min(elapsed / duration, 1)
		
		-- Ease the progress
		local easedProgress = TweenService:GetValue(progress, CONFIG.EasingStyle, CONFIG.EasingDirection)
		
		-- Quadratic bezier interpolation
		local p1 = startPos:Lerp(midPos, easedProgress)
		local p2 = midPos:Lerp(endPos, easedProgress)
		local currentPos = p1:Lerp(p2, easedProgress)
		
		-- Update position
		icon.Position = UDim2.new(0, currentPos.X - icon.AbsoluteSize.X/2, 0, currentPos.Y - icon.AbsoluteSize.Y/2)
		
		-- Scale down as it approaches target
		local scale = CONFIG.StartScale - (CONFIG.StartScale - CONFIG.EndScale) * easedProgress
		icon.TextSize = CONFIG.IconTextSize * scale
		
		-- Fade out near the end
		if progress > 0.7 then
			local fadeProgress = (progress - 0.7) / 0.3
			icon.TextTransparency = fadeProgress
			local stroke = icon:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0.5 + fadeProgress * 0.5
			end
		end
		
		-- Rotation for extra flair
		icon.Rotation = math.sin(elapsed * 15) * 10 * (1 - progress)
		
		-- Complete
		if progress >= 1 then
			connection:Disconnect()
			icon:Destroy()
			
			-- Trigger UI pulse effect on kudos counter
			if progress >= 1 then
				self:PulseKudosUI()
			end
		end
	end)
	
	-- Safety cleanup
	task.delay(duration + 1, function()
		if connection then
			connection:Disconnect()
		end
		if icon and icon.Parent then
			icon:Destroy()
		end
	end)
end

function KudosFlyController:PulseKudosUI()
	-- Pulse is now handled by KudosController when kudos are added
	-- This function is kept for compatibility but does nothing
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Spawn flying kudos from a world position
function KudosFlyController:FlyKudosFromWorld(worldPosition, amount)
	self:SpawnFlyingKudos(worldPosition, amount)
end

-- Spawn flying kudos from a screen position
function KudosFlyController:FlyKudosFromScreen(screenPosition, amount)
	self:FindKudosUI()
	
	local numIcons = math.min(math.ceil(amount * CONFIG.IconsPerKudos), CONFIG.MaxIconsPerBurst)
	numIcons = math.max(numIcons, 3)
	
	for i = 1, numIcons do
		task.delay((i - 1) * CONFIG.SpawnDelay, function()
			self:SpawnSingleIcon(screenPosition, i, numIcons)
		end)
	end
end

-- Spawn flying kudos from player's position
function KudosFlyController:FlyKudosFromPlayer(amount)
	local character = Player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			self:FlyKudosFromWorld(hrp.Position + Vector3.new(0, 3, 0), amount)
			return
		end
	end
	
	-- Fallback to center of screen
	self:FlyKudosFromScreen(Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2), amount)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         LIFECYCLE                                           ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function KudosFlyController:KnitInit()
	print("[KudosFlyController] Initializing...")
end

function KudosFlyController:KnitStart()
	print("[KudosFlyController] Starting...")
	
	-- Create screen GUI
	self:CreateScreenGui()
	
	-- Find kudos UI position
	task.delay(1, function()
		self:FindKudosUI()
	end)
	
	-- Listen for kudos earned events from HubService
	local HubService = Knit.GetService("HubService")
	
	-- Listen for the KudosEarned signal if it exists
	if HubService.KudosEarned then
		HubService.KudosEarned:Connect(function(amount, worldPosition)
			if worldPosition then
				self:FlyKudosFromWorld(worldPosition, amount)
			else
				self:FlyKudosFromPlayer(amount)
			end
		end)
		print("[KudosFlyController] Connected to KudosEarned signal")
	else
		print("[KudosFlyController] KudosEarned signal not found - manual triggering only")
	end
	
	print("[KudosFlyController] Started!")
end

return KudosFlyController

