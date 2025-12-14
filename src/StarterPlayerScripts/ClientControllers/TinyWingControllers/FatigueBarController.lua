--[[
	FatigueBarController
	
	Displays a fatigue bar GUI that shows player stamina.
	Depletes based on the number of packages being carried.
	Uses Replica for server sync and Fusion for reactive UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local FatigueBarController = Knit.CreateController {
	Name = "FatigueBarController",
	_screenGui = nil,
	_fatigueValue = nil,       -- Current fatigue (0-100)
	_maxFatigueValue = nil,    -- Max fatigue
	_stackCountValue = nil,    -- Current stack count
	_isVisible = nil,
	_replica = nil,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIG                                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Master enable/disable
	Enabled = true,
	
	-- Position & Size
	Position = UDim2.new(0, 20, 1, -120),  -- Bottom left
	Size = UDim2.new(0, 250, 0, 60),
	BarHeight = 20,
	
	-- Colors based on fatigue level
	HighFatigueColor = Color3.fromRGB(80, 200, 120),    -- Green - plenty of energy
	MidFatigueColor = Color3.fromRGB(255, 200, 80),     -- Yellow - getting tired
	LowFatigueColor = Color3.fromRGB(255, 80, 80),      -- Red - exhausted
	
	-- Background
	BackgroundColor = Color3.fromRGB(20, 25, 35),
	BarBackgroundColor = Color3.fromRGB(40, 45, 55),
	
	-- Styling
	CornerRadius = UDim.new(0, 8),
	BarCornerRadius = UDim.new(0, 6),
	
	-- Animation
	BarSpring = { speed = 15, damping = 0.8 },
	
	-- Thresholds
	LowThreshold = 30,   -- Below this = red
	MidThreshold = 60,   -- Below this = yellow
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         HELPER FUNCTIONS                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function getFatigueColor(percent)
	if percent <= CONFIG.LowThreshold then
		return CONFIG.LowFatigueColor
	elseif percent <= CONFIG.MidThreshold then
		-- Interpolate between red and yellow
		local t = (percent - CONFIG.LowThreshold) / (CONFIG.MidThreshold - CONFIG.LowThreshold)
		return CONFIG.LowFatigueColor:Lerp(CONFIG.MidFatigueColor, t)
	else
		-- Interpolate between yellow and green
		local t = (percent - CONFIG.MidThreshold) / (100 - CONFIG.MidThreshold)
		return CONFIG.MidFatigueColor:Lerp(CONFIG.HighFatigueColor, t)
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         UI CREATION                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function FatigueBarController:CreateUI()
	-- Reactive values
	self._fatigueValue = Value(100)
	self._maxFatigueValue = Value(100)
	self._stackCountValue = Value(0)
	self._isVisible = Value(true)
	
	-- Computed values
	local fatiguePercent = Computed(function()
		local fatigue = self._fatigueValue:get()
		local max = self._maxFatigueValue:get()
		return max > 0 and (fatigue / max * 100) or 100
	end)
	
	-- Spring for smooth bar animation
	local smoothPercent = Spring(fatiguePercent, CONFIG.BarSpring.speed, CONFIG.BarSpring.damping)
	
	-- Computed bar width
	local barWidth = Computed(function()
		return UDim2.new(smoothPercent:get() / 100, 0, 1, 0)
	end)
	
	-- Computed bar color
	local barColor = Computed(function()
		return getFatigueColor(smoothPercent:get())
	end)
	
	-- Computed visibility
	local visible = Computed(function()
		return CONFIG.Enabled and self._isVisible:get()
	end)
	
	-- Fatigue text
	local fatigueText = Computed(function()
		return string.format("%.0f%%", smoothPercent:get())
	end)
	
	-- Stack count text
	local stackText = Computed(function()
		local count = self._stackCountValue:get()
		if count > 0 then
			return "📦 " .. count
		end
		return ""
	end)
	
	-- Label text
	local labelText = Computed(function()
		local count = self._stackCountValue:get()
		if count > 0 then
			return "⚡ Stamina"
		end
		return "⚡ Rested"
	end)
	
	-- Create ScreenGui
	self._screenGui = New "ScreenGui" {
		Name = "FatigueBarGui",
		Parent = PlayerGui,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		
		[Children] = {
			-- Main container
			New "Frame" {
				Name = "Container",
				AnchorPoint = Vector2.new(0, 1),
				Position = CONFIG.Position,
				Size = CONFIG.Size,
				BackgroundColor3 = CONFIG.BackgroundColor,
				BackgroundTransparency = 0.1,
				Visible = visible,
				
				[Children] = {
					-- Corner radius
					New "UICorner" {
						CornerRadius = CONFIG.CornerRadius,
					},
					
					-- Border
					New "UIStroke" {
						Color = Computed(function()
							return barColor:get()
						end),
						Thickness = 2,
						Transparency = 0.5,
					},
					
					-- Padding
					New "UIPadding" {
						PaddingTop = UDim.new(0, 8),
						PaddingBottom = UDim.new(0, 8),
						PaddingLeft = UDim.new(0, 12),
						PaddingRight = UDim.new(0, 12),
					},
					
					-- Top row: Label and stack count
					New "Frame" {
						Name = "TopRow",
						Size = UDim2.new(1, 0, 0, 18),
						BackgroundTransparency = 1,
						
						[Children] = {
							-- Stamina label
							New "TextLabel" {
								Name = "Label",
								Size = UDim2.new(0.6, 0, 1, 0),
								BackgroundTransparency = 1,
								Text = labelText,
								TextColor3 = Color3.fromRGB(200, 200, 210),
								TextSize = 16,
								TextXAlignment = Enum.TextXAlignment.Left,
								Font = Enum.Font.GothamBold,
							},
							
							-- Stack count
							New "TextLabel" {
								Name = "StackCount",
								Position = UDim2.new(0.6, 0, 0, 0),
								Size = UDim2.new(0.4, 0, 1, 0),
								BackgroundTransparency = 1,
								Text = stackText,
								TextColor3 = Color3.fromRGB(255, 200, 100),
								TextSize = 14,
								TextXAlignment = Enum.TextXAlignment.Right,
								Font = Enum.Font.GothamBold,
							},
						},
					},
					
					-- Bar container
					New "Frame" {
						Name = "BarContainer",
						Position = UDim2.new(0, 0, 0, 24),
						Size = UDim2.new(1, 0, 0, CONFIG.BarHeight),
						BackgroundColor3 = CONFIG.BarBackgroundColor,
						
						[Children] = {
							New "UICorner" {
								CornerRadius = CONFIG.BarCornerRadius,
							},
							
							-- Fill bar
							New "Frame" {
								Name = "Fill",
								Size = barWidth,
								BackgroundColor3 = barColor,
								
								[Children] = {
									New "UICorner" {
										CornerRadius = CONFIG.BarCornerRadius,
									},
									
									-- Gradient for polish
									New "UIGradient" {
										Color = ColorSequence.new({
											ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
											ColorSequenceKeypoint.new(0.5, Color3.new(0.9, 0.9, 0.9)),
											ColorSequenceKeypoint.new(1, Color3.new(0.7, 0.7, 0.7)),
										}),
										Rotation = 90,
									},
								},
							},
							
							-- Percentage text overlay
							New "TextLabel" {
								Name = "PercentText",
								Size = UDim2.new(1, 0, 1, 0),
								BackgroundTransparency = 1,
								Text = fatigueText,
								TextColor3 = Color3.fromRGB(255, 255, 255),
								TextSize = 14,
								Font = Enum.Font.GothamBold,
								
								[Children] = {
									New "UIStroke" {
										Color = Color3.fromRGB(0, 0, 0),
										Thickness = 1,
									},
								},
							},
						},
					},
				},
			},
		},
	}
	
	print("[FatigueBarController] UI created")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         REPLICA HANDLING                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function FatigueBarController:SetupReplicaListener()
	-- Listen for PlayerFatigue replicas
	ReplicaController.ReplicaOfClassCreated("PlayerFatigue", function(replica)
		print("[FatigueBarController] Fatigue replica received!")
		self._replica = replica
		
		-- Initial data
		local data = replica.Data
		if data then
			self._fatigueValue:set(data.Fatigue or 100)
			self._maxFatigueValue:set(data.MaxFatigue or 100)
			self._stackCountValue:set(data.StackCount or 0)
		end
		
		-- Listen for changes
		replica:ListenToChange({"Fatigue"}, function(newValue)
			self._fatigueValue:set(newValue)
		end)
		
		replica:ListenToChange({"MaxFatigue"}, function(newValue)
			self._maxFatigueValue:set(newValue)
		end)
		
		replica:ListenToChange({"StackCount"}, function(newValue)
			self._stackCountValue:set(newValue)
		end)
		
		-- Handle replica destruction
		replica:ListenToDestruction(function()
			print("[FatigueBarController] Fatigue replica destroyed")
			self._replica = nil
			-- Reset to full fatigue
			self._fatigueValue:set(100)
			self._stackCountValue:set(0)
		end)
	end)
	
	print("[FatigueBarController] Replica listener setup complete")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function FatigueBarController:KnitInit()
	print("[FatigueBarController] Initializing...")
end

function FatigueBarController:KnitStart()
	print("[FatigueBarController] Starting...")
	
	if not CONFIG.Enabled then
		print("[FatigueBarController] Disabled via config")
		return
	end
	
	-- Request initial data from ReplicaController
	ReplicaController.RequestData()
	
	-- Setup replica listener
	self:SetupReplicaListener()
	
	-- Create UI
	self:CreateUI()
	
	print("[FatigueBarController] Started!")
end

return FatigueBarController

