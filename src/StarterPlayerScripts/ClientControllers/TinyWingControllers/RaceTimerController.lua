--[[
	RaceTimerController
	
	Displays a polished, juicy race timer GUI using Fusion.
	Features smooth client-side interpolation, urgency effects, and polish.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Replica Module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica.ReplicaController)

-- Fusion
local Fusion = require(CustomPackages:WaitForChild("FusionRoot"):WaitForChild("Fusion"))
local New = Fusion.New
local Children = Fusion.Children
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring
local OnEvent = Fusion.OnEvent

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local RaceTimerController = Knit.CreateController {
	Name = "RaceTimerController",
	_screenGui = nil,
	_displayTime = nil,     -- Smoothly interpolated time for display
	_serverTime = nil,      -- Last time received from server
	_isRunning = nil,
	_isVisible = nil,
	_pulseValue = nil,      -- For pulsing effects
	_startLocalTime = nil,  -- Local time when we started
	_connection = nil,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIG                                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Position & Size
	Position = UDim2.new(0.5, 0, 0, 30),
	Size = UDim2.new(0, 200, 0, 80),
	
	-- Colors - Dynamic based on time
	BackgroundColor = Color3.fromRGB(15, 15, 25),
	
	-- Time thresholds for urgency colors (seconds)
	UrgencyThresholds = {
		{ time = 0,   color = Color3.fromRGB(100, 255, 180) },   -- Green - fresh start
		{ time = 30,  color = Color3.fromRGB(255, 255, 100) },   -- Yellow - picking up
		{ time = 60,  color = Color3.fromRGB(255, 180, 80) },    -- Orange - getting serious
		{ time = 90,  color = Color3.fromRGB(255, 100, 100) },   -- Red - urgent!
		{ time = 120, color = Color3.fromRGB(255, 50, 80) },     -- Deep red - intense!
	},
	
	-- Styling
	CornerRadius = UDim.new(0, 12),
	StrokeThickness = 2,
	
	-- Animation
	PulseSpeed = 2,        -- Pulses per second
	PulseIntensity = 0.1,  -- How much the scale changes
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         HELPER FUNCTIONS                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Get urgency color based on elapsed time
local function getUrgencyColor(seconds)
	local thresholds = CONFIG.UrgencyThresholds
	
	for i = #thresholds, 1, -1 do
		if seconds >= thresholds[i].time then
			if i == #thresholds then
				return thresholds[i].color
			end
			-- Interpolate to next threshold
			local current = thresholds[i]
			local next = thresholds[i + 1]
			local t = math.clamp((seconds - current.time) / (next.time - current.time), 0, 1)
			return current.color:Lerp(next.color, t)
		end
	end
	
	return thresholds[1].color
end

-- Format time into components
local function formatTimeComponents(seconds)
	local mins = math.floor(seconds / 60)
	local secs = math.floor(seconds % 60)
	local ms = math.floor((seconds % 1) * 100)
	return mins, secs, ms
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         UI COMPONENTS                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function createTimerUI(displayTime, isRunning, isVisible, pulseValue)
	-- Smooth visibility transition
	local visibilitySpring = Spring(Computed(function()
		return isVisible:get() and 1 or 0
	end), 20, 0.7)
	
	-- Dynamic urgency color
	local urgencyColor = Computed(function()
		return getUrgencyColor(displayTime:get())
	end)
	
	-- Smooth color transition
	local smoothColor = Spring(urgencyColor, 8, 0.9)
	
	-- Pulse scale effect
	local pulseScale = Computed(function()
		if not isRunning:get() then return 1 end
		local pulse = pulseValue:get()
		return 1 + math.sin(pulse * math.pi * 2) * CONFIG.PulseIntensity * 0.3
	end)
	
	-- Formatted time string (M:SS.ms format)
	local timeString = Computed(function()
		local t = displayTime:get()
		local mins = math.floor(t / 60)
		local secs = math.floor(t % 60)
		local ms = math.floor((t % 1) * 100)
		return string.format("%d:%02d.%02d", mins, secs, ms)
	end)
	
	return New "ScreenGui" {
		Name = "RaceTimerGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 50,
		Parent = PlayerGui,
		
		[Children] = {
			-- Main container with pulse effect
			New "Frame" {
				Name = "TimerContainer",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = CONFIG.Position,
				Size = Computed(function()
					local scale = pulseScale:get()
					return UDim2.new(0, CONFIG.Size.X.Offset * scale, 0, CONFIG.Size.Y.Offset * scale)
				end),
				BackgroundColor3 = CONFIG.BackgroundColor,
				BackgroundTransparency = Computed(function()
					return 1 - (visibilitySpring:get() * 0.9)
				end),
				
				[Children] = {
					-- Corner rounding
					New "UICorner" {
						CornerRadius = CONFIG.CornerRadius,
					},
					
					-- Glowing border stroke
					New "UIStroke" {
						Color = smoothColor,
						Thickness = CONFIG.StrokeThickness,
						Transparency = Computed(function()
							return 1 - visibilitySpring:get()
						end),
					},
					
					-- Inner glow frame
					New "Frame" {
						Name = "InnerGlow",
						Size = UDim2.new(1, -8, 1, -8),
						Position = UDim2.new(0, 4, 0, 4),
						BackgroundColor3 = smoothColor,
						BackgroundTransparency = Computed(function()
							local pulse = pulseValue:get()
							local glowIntensity = 0.92 + math.sin(pulse * math.pi * 2) * 0.03
							return glowIntensity
						end),
						
						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0, 12),
							},
						},
					},
					
					-- Status label (top)
					New "TextLabel" {
						Name = "StatusLabel",
						Size = UDim2.new(1, 0, 0, 18),
						Position = UDim2.new(0, 0, 0, 6),
						BackgroundTransparency = 1,
						Text = Computed(function()
							return isRunning:get() and "RACE TIME" or "FINISHED"
						end),
						TextColor3 = smoothColor,
						TextTransparency = Computed(function()
							return 1 - (visibilitySpring:get() * 0.7)
						end),
						TextSize = 11,
						Font = Enum.Font.GothamBold,
					},
					
					-- Time display (simple format: M:SS.ms)
					New "TextLabel" {
						Name = "TimeLabel",
						Size = UDim2.new(1, 0, 0, 45),
						Position = UDim2.new(0, 0, 0, 24),
						BackgroundTransparency = 1,
						Text = timeString,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						TextTransparency = Computed(function()
							return 1 - visibilitySpring:get()
						end),
						TextSize = 36,
						Font = Enum.Font.GothamBlack,
					},
					
					-- Bottom accent bar
					New "Frame" {
						Name = "AccentBar",
						Size = Computed(function()
							-- Bar width pulses when running
							local baseWidth = isRunning:get() and 0.6 or 0.8
							local pulse = pulseValue:get()
							local width = baseWidth + math.sin(pulse * math.pi * 4) * 0.1
							return UDim2.new(width, 0, 0, 3)
						end),
						Position = UDim2.new(0.5, 0, 1, -10),
						AnchorPoint = Vector2.new(0.5, 0),
						BackgroundColor3 = smoothColor,
						BackgroundTransparency = Computed(function()
							return 1 - visibilitySpring:get()
						end),
						
						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(1, 0),
							},
							
							-- Glow effect
							New "UIGradient" {
								Color = ColorSequence.new({
									ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
									ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
									ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
								}),
								Transparency = NumberSequence.new({
									NumberSequenceKeypoint.new(0, 0.5),
									NumberSequenceKeypoint.new(0.5, 0),
									NumberSequenceKeypoint.new(1, 0.5),
								}),
							},
						},
					},
				},
			},
		},
	}
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function RaceTimerController:KnitInit()
	-- Initialize Fusion values
	self._displayTime = Value(0)
	self._serverTime = Value(0)
	self._isRunning = Value(false)
	self._isVisible = Value(false)
	self._pulseValue = Value(0)
	self._startLocalTime = 0
	
	-- Request replica data from server
	ReplicaController.RequestData()
	
	print("[RaceTimerController] Initialized")
end

function RaceTimerController:KnitStart()
	-- Create the UI
	self._screenGui = createTimerUI(self._displayTime, self._isRunning, self._isVisible, self._pulseValue)
	
	-- Smooth client-side time update (60fps)
	self._connection = RunService.RenderStepped:Connect(function(deltaTime)
		-- Update pulse animation
		local currentPulse = self._pulseValue:get()
		self._pulseValue:set((currentPulse + deltaTime * CONFIG.PulseSpeed) % 1)
		
		-- Smooth time interpolation when running
		if self._isRunning:get() then
			local serverTime = self._serverTime:get()
			local localElapsed = tick() - self._startLocalTime
			
			-- Use local time but sync to server periodically
			-- This gives smooth 60fps updates while staying accurate
			local displayTime = self._startLocalTime > 0 and localElapsed or serverTime
			self._displayTime:set(displayTime)
		end
	end)
	
	-- Listen for the RaceTimerReplica
	ReplicaController.ReplicaOfClassCreated("RaceTimerReplica", function(replica)
		print("[RaceTimerController] Received RaceTimerReplica - GO!")
		
		-- Show the timer
		self._isVisible:set(true)
		self._isRunning:set(replica.Data.IsRunning)
		
		-- Set initial time and start local tracking
		self._serverTime:set(replica.Data.ElapsedTime)
		self._displayTime:set(replica.Data.ElapsedTime)
		self._startLocalTime = tick() - replica.Data.ElapsedTime
		
		-- Listen for server time updates (sync correction)
		replica:ListenToChange({"ElapsedTime"}, function(newValue)
			self._serverTime:set(newValue)
			-- Soft sync: only correct if we're off by more than 0.5s
			local localTime = tick() - self._startLocalTime
			if math.abs(localTime - newValue) > 0.5 then
				self._startLocalTime = tick() - newValue
			end
		end)
		
		-- Listen for running state changes
		replica:ListenToChange({"IsRunning"}, function(newValue)
			self._isRunning:set(newValue)
			if not newValue then
				-- Race finished! Freeze display at final time
				self._displayTime:set(self._serverTime:get())
				print(string.format("[RaceTimerController] 🏁 FINISHED! Final time: %.2f seconds", self._serverTime:get()))
			end
		end)
		
		-- Handle replica destruction
		replica:ListenToRaw(function(actionName)
			if actionName == "Destroy" then
				print("[RaceTimerController] Timer hidden")
				self._isVisible:set(false)
				self._displayTime:set(0)
				self._serverTime:set(0)
				self._isRunning:set(false)
				self._startLocalTime = 0
			end
		end)
	end)
	
	print("[RaceTimerController] Started - ready for race!")
end

function RaceTimerController:KnitStop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

return RaceTimerController
