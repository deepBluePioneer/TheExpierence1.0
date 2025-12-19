--[[
	ArrowTimerController
	
	Displays a countdown timer UI centered at the top of the screen
	using Fusion. Receives timer updates from ReplicaController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local ReplicaController = require(CustomPackages.Replica.ReplicaController)
local Fusion = require(CustomPackages.FusionRoot.Fusion)

-- Fusion imports
local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Cleanup = Fusion.Cleanup

local ArrowTimerController = Knit.CreateController({
	Name = "ArrowTimerController",
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- UI Positioning
	PositionY = 0.05,  -- 5% from top of screen
	
	-- Timer Display
	FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
	TextSize = 72,
	
	-- Colors
	NormalColor = Color3.fromRGB(255, 255, 255),
	WarningColor = Color3.fromRGB(255, 200, 80),   -- Yellow when < 5 seconds
	CriticalColor = Color3.fromRGB(255, 80, 80),   -- Red when < 3 seconds
	
	-- Background
	BackgroundColor = Color3.fromRGB(20, 20, 30),
	BackgroundTransparency = 0.3,
	CornerRadius = UDim.new(0, 16),
	
	-- Animation
	SpringSpeed = 25,
	SpringDamping = 0.8,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local player = Players.LocalPlayer
local ArrowTimerService = nil
local timerReplica = nil

-- Fusion State
local timeRemaining = Value(10)
local totalDuration = Value(10)
local isRunning = Value(false)
local isVisible = Value(false)

-- UI References
local screenGui = nil
local timerUI = nil

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         UI CREATION                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTimerController:CreateTimerUI()
	-- Computed values for dynamic styling
	local timerColor = Computed(function()
		local time = timeRemaining:get()
		if time <= 3 then
			return CONFIG.CriticalColor
		elseif time <= 5 then
			return CONFIG.WarningColor
		else
			return CONFIG.NormalColor
		end
	end)
	
	local timerText = Computed(function()
		local time = timeRemaining:get()
		if time >= 10 then
			return string.format("%.1f", time)
		else
			return string.format("%.1f", time)
		end
	end)
	
	local progressFraction = Computed(function()
		local remaining = timeRemaining:get()
		local total = totalDuration:get()
		if total <= 0 then return 1 end
		return remaining / total
	end)
	
	local uiScale = Computed(function()
		local time = timeRemaining:get()
		-- Pulse effect when time is critical
		if time <= 3 and time > 0 then
			local pulse = 1 + (math.sin(tick() * 8) * 0.05)
			return pulse
		end
		return 1
	end)
	
	local visibility = Computed(function()
		return if isVisible:get() then 1 else 0
	end)
	
	local springVisibility = Spring(visibility, CONFIG.SpringSpeed, CONFIG.SpringDamping)
	local springColor = Spring(timerColor, CONFIG.SpringSpeed, CONFIG.SpringDamping)
	
	-- Create the ScreenGui
	screenGui = New "ScreenGui" {
		Name = "ArrowTimerGui",
		Parent = player:WaitForChild("PlayerGui"),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		
		[Children] = {
			-- Main Timer Container
			New "Frame" {
				Name = "TimerContainer",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, CONFIG.PositionY, 0),
				Size = UDim2.new(0, 200, 0, 100),
				BackgroundColor3 = CONFIG.BackgroundColor,
				BackgroundTransparency = Computed(function()
					return CONFIG.BackgroundTransparency + (1 - springVisibility:get()) * 0.7
				end),
				
				[Children] = {
					-- Corner radius
					New "UICorner" {
						CornerRadius = CONFIG.CornerRadius,
					},
					
					-- Stroke
					New "UIStroke" {
						Color = springColor,
						Thickness = 3,
						Transparency = Computed(function()
							return 0.3 + (1 - springVisibility:get()) * 0.7
						end),
					},
					
					-- Gradient overlay
					New "UIGradient" {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 180, 180)),
						}),
						Rotation = 90,
						Transparency = NumberSequence.new(0.95),
					},
					
					-- Progress bar background
					New "Frame" {
						Name = "ProgressBarBG",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 0, 1, -8),
						Size = UDim2.new(0.85, 0, 0, 6),
						BackgroundColor3 = Color3.fromRGB(40, 40, 50),
						BackgroundTransparency = Computed(function()
							return 0.3 + (1 - springVisibility:get()) * 0.7
						end),
						
						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(1, 0),
							},
							
							-- Progress bar fill
							New "Frame" {
								Name = "ProgressFill",
								Size = Computed(function()
									return UDim2.new(progressFraction:get(), 0, 1, 0)
								end),
								BackgroundColor3 = springColor,
								BackgroundTransparency = Computed(function()
									return 0.1 + (1 - springVisibility:get()) * 0.9
								end),
								
								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(1, 0),
									},
								},
							},
						},
					},
					
					-- Timer text
					New "TextLabel" {
						Name = "TimerText",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0.5, 0, 0.4, 0),
						Size = UDim2.new(1, 0, 0.7, 0),
						BackgroundTransparency = 1,
						Text = timerText,
						TextColor3 = springColor,
						TextTransparency = Computed(function()
							return 1 - springVisibility:get()
						end),
						FontFace = CONFIG.FontFace,
						TextSize = CONFIG.TextSize,
						TextScaled = false,
						
						[Children] = {
							-- Text shadow/glow
							New "UIStroke" {
								Color = Computed(function()
									local c = springColor:get()
									return Color3.new(c.R * 0.3, c.G * 0.3, c.B * 0.3)
								end),
								Thickness = 2,
								Transparency = Computed(function()
									return 0.5 + (1 - springVisibility:get()) * 0.5
								end),
							},
						},
					},
					
					-- "TIME" label
					New "TextLabel" {
						Name = "TimeLabel",
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0.02, 0),
						Size = UDim2.new(1, 0, 0, 16),
						BackgroundTransparency = 1,
						Text = "TIME",
						TextColor3 = Color3.fromRGB(150, 150, 160),
						TextTransparency = Computed(function()
							return 0.3 + (1 - springVisibility:get()) * 0.7
						end),
						FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
						TextSize = 14,
						TextScaled = false,
					},
				},
			},
		},
	}
	
	print("[ArrowTimerController] ✓ Timer UI created")
	return screenGui
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         REPLICA HANDLING                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTimerController:SetupReplicaListeners()
	ReplicaController.ReplicaOfClassCreated("ArrowTimer", function(replica)
		print("[ArrowTimerController] ✓ ArrowTimer replica received")
		timerReplica = replica
		
		-- Initialize with current values
		timeRemaining:set(replica.Data.TimeRemaining)
		totalDuration:set(replica.Data.TotalDuration)
		isRunning:set(replica.Data.IsRunning)
		isVisible:set(replica.Data.IsRunning)
		
		-- Listen for time remaining changes
		replica:ListenToChange({"TimeRemaining"}, function(newValue)
			timeRemaining:set(newValue)
		end)
		
		-- Listen for total duration changes
		replica:ListenToChange({"TotalDuration"}, function(newValue)
			totalDuration:set(newValue)
		end)
		
		-- Listen for running state changes
		replica:ListenToChange({"IsRunning"}, function(newValue)
			isRunning:set(newValue)
			isVisible:set(newValue)
		end)
		
		-- Handle replica destruction
		replica:AddCleanupTask(function()
			timerReplica = nil
			isVisible:set(false)
		end)
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTimerController:Show()
	isVisible:set(true)
end

function ArrowTimerController:Hide()
	isVisible:set(false)
end

function ArrowTimerController:GetTimeRemaining()
	return timeRemaining:get()
end

function ArrowTimerController:IsRunning()
	return isRunning:get()
end

function ArrowTimerController:RequestStartTimer(duration: number?)
	if ArrowTimerService then
		return ArrowTimerService:RequestStartTimer(duration)
	end
	return false
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function ArrowTimerController:KnitInit()
	print("[ArrowTimerController] Initializing...")
	
	-- Setup replica listeners early
	self:SetupReplicaListeners()
end

function ArrowTimerController:KnitStart()
	print("[ArrowTimerController] Starting...")
	
	-- Get service reference
	ArrowTimerService = Knit.GetService("ArrowTimerService")
	
	-- Request replica data
	ReplicaController.RequestData()
	
	-- Create the UI
	self:CreateTimerUI()
	
	-- Connect to service signals
	ArrowTimerService.TimerStarted:Connect(function(duration)
		print("[ArrowTimerController] Timer started:", duration)
		isVisible:set(true)
	end)
	
	ArrowTimerService.TimerEnded:Connect(function()
		print("[ArrowTimerController] Timer ended!")
		-- Keep visible briefly to show 0.0
		task.delay(2, function()
			isVisible:set(false)
		end)
	end)
	
	print("[ArrowTimerController] Ready")
end

return ArrowTimerController

