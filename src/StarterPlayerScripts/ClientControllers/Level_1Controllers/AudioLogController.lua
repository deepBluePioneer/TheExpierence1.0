local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Fusion = require(CustomPackages:WaitForChild("FusionRoot"):WaitForChild("Fusion"))

-- Fusion imports
local New = Fusion.New
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring

local AudioLogController = Knit.CreateController {
	Name = "AudioLogController",
}

-- === CONFIG ===
local UI_CONFIG = {
	-- Dialog positioning (bottom of screen)
	DialogWidth = 1200,
	DialogHeight = 250,
	BottomPadding = 50,
	
	-- Colors
	BackgroundColor = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.25,
	TextColor = Color3.fromRGB(255, 255, 255),
	TitleColor = Color3.fromRGB(255, 220, 150),
	BorderColor = Color3.fromRGB(150, 130, 90),
	
	-- Typography
	TitleFont = Enum.Font.GothamBold,
	BodyFont = Enum.Font.Gotham,
	TitleSize = 28,
	BodySize = 36,
	
	-- Animation
	TypewriterSpeed = 0.025,  -- Seconds per character
	FadeInTime = 0.3,
}

-- === AUDIO LOG ENTRIES (Diary/Transcript content) ===
local AUDIO_LOG_ENTRIES = {
	{
		title = "AUDIO LOG #1 - Dr. Sarah Chen",
		content = "If anyone finds this... my name is Dr. Sarah Chen. The facility went dark three days ago. I can hear them in the corridors. Moving. Searching. Whatever we created down in Sub-Level 4... it's loose now.",
	},
	{
		title = "AUDIO LOG #2 - Dr. Sarah Chen",
		content = "Food is running low. They're not human anymore. I saw Jenkins yesterday through the observation window. His eyes were completely black. The emergency beacon should have brought help by now.",
	},
	{
		title = "AUDIO LOG #3 - Dr. Sarah Chen",
		content = "I found a way out. There's an old maintenance tunnel that leads to the surface. If you're listening, get to Sub-Level 4. The main terminal can send an external distress signal. The code is 7-4-1-9.",
	},
	{
		title = "AUDIO LOG #4 - Unknown Speaker",
		content = "*static* ...can't remember how long... The walls are breathing now. Or maybe that's just me. They found Lab C. Had to move. Keep moving... I think I'm becoming one of them...",
	},
	{
		title = "AUDIO LOG #5 - Final Entry",
		content = "Don't make the same mistakes we did. Some doors should stay closed. Destroy the samples in Sub-Level 4. Burn this place to the ground if you have to. Tell my daughter Emma that mommy tried to come home. I'm sorry.",
	},
}

-- === STATE ===
local isPlaying = false
local AudioLogService = nil

-- === UI COMPONENTS ===

local function createDialogUI(self)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- State values
	self.isVisible = Value(false)
	self.currentTitle = Value("")
	self.displayedText = Value("")
	self.dialogTransparency = Value(1)
	
	-- Animated transparency
	local animatedTransparency = Spring(self.dialogTransparency, 20, 1)
	
	-- Create the UI
	local screenGui = New "ScreenGui" {
		Name = "AudioLogUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Parent = playerGui,
		
		[Children] = {
			-- Bottom dialog container
			New "Frame" {
				Name = "DialogContainer",
				Size = UDim2.new(0, UI_CONFIG.DialogWidth, 0, UI_CONFIG.DialogHeight),
				Position = UDim2.new(0.5, 0, 1, -UI_CONFIG.BottomPadding),
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = UI_CONFIG.BackgroundColor,
				BackgroundTransparency = Computed(function()
					return UI_CONFIG.BackgroundTransparency + animatedTransparency:get() * (1 - UI_CONFIG.BackgroundTransparency)
				end),
				Visible = Computed(function()
					return self.isVisible:get()
				end),
				
				[Children] = {
					-- Corner rounding
					New "UICorner" {
						CornerRadius = UDim.new(0, 12),
					},
					
					-- Border stroke
					New "UIStroke" {
						Color = UI_CONFIG.BorderColor,
						Thickness = 2,
						Transparency = animatedTransparency,
					},
					
					-- Padding
					New "UIPadding" {
						PaddingLeft = UDim.new(0, 40),
						PaddingRight = UDim.new(0, 40),
						PaddingTop = UDim.new(0, 25),
						PaddingBottom = UDim.new(0, 25),
					},
					
					-- Title label
					New "TextLabel" {
						Name = "Title",
						Size = UDim2.new(1, 0, 0, 35),
						Position = UDim2.new(0, 0, 0, 0),
						BackgroundTransparency = 1,
						Font = UI_CONFIG.TitleFont,
						TextSize = UI_CONFIG.TitleSize,
						TextColor3 = UI_CONFIG.TitleColor,
						TextTransparency = animatedTransparency,
						TextXAlignment = Enum.TextXAlignment.Left,
						Text = Computed(function()
							return self.currentTitle:get()
						end),
					},
					
					-- Content text
					New "TextLabel" {
						Name = "ContentText",
						Size = UDim2.new(1, 0, 1, -45),
						Position = UDim2.new(0, 0, 0, 40),
						BackgroundTransparency = 1,
						Font = UI_CONFIG.BodyFont,
						TextSize = UI_CONFIG.BodySize,
						TextColor3 = UI_CONFIG.TextColor,
						TextTransparency = animatedTransparency,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						TextWrapped = true,
						Text = Computed(function()
							return self.displayedText:get()
						end),
					},
					
				},
			},
		},
	}
	
	self.screenGui = screenGui
	return screenGui
end

-- === TYPEWRITER EFFECT ===

local function typewriterEffect(self, fullText, onComplete)
	self.isTyping = true
	self.displayedText:set("")
	
	local charIndex = 0
	local totalChars = #fullText
	
	while charIndex < totalChars and self.isTyping and isPlaying do
		charIndex = charIndex + 1
		local currentText = string.sub(fullText, 1, charIndex)
		self.displayedText:set(currentText)
		
		-- Variable speed for punctuation
		local char = string.sub(fullText, charIndex, charIndex)
		if char == "." or char == "!" or char == "?" then
			task.wait(UI_CONFIG.TypewriterSpeed * 5)
		elseif char == "," or char == ";" or char == ":" then
			task.wait(UI_CONFIG.TypewriterSpeed * 2)
		elseif char == "\n" then
			task.wait(UI_CONFIG.TypewriterSpeed * 3)
		else
			task.wait(UI_CONFIG.TypewriterSpeed)
		end
	end
	
	-- Ensure full text is shown
	self.displayedText:set(fullText)
	self.isTyping = false
	
	-- Wait a moment then close
	if isPlaying then
		task.wait(2)
		if onComplete then
			onComplete()
		end
	end
end

-- === PUBLIC METHODS ===

function AudioLogController:ShowDialog(logIndex)
	-- Don't show if already playing
	if isPlaying then
		return
	end
	
	isPlaying = true
	
	-- Use the provided index, default to 1 if not provided or out of range
	logIndex = logIndex or 1
	
	-- Clamp to valid range
	if logIndex < 1 or logIndex > #AUDIO_LOG_ENTRIES then
		logIndex = ((logIndex - 1) % #AUDIO_LOG_ENTRIES) + 1
	end
	
	local entry = AUDIO_LOG_ENTRIES[logIndex]
	if not entry then
		warn("[AudioLogController] No entry found for index:", logIndex)
		isPlaying = false
		return
	end
	
	-- Update content
	self.currentTitle:set(entry.title)
	self.currentContent = entry.content
	self.displayedText:set("")
	
	-- Show dialog
	self.isVisible:set(true)
	self.dialogTransparency:set(0)
	
	print("[AudioLogController] Showing entry #" .. logIndex .. ": " .. entry.title)
	
	-- Start typewriter effect
	task.spawn(function()
		task.wait(UI_CONFIG.FadeInTime)
		typewriterEffect(self, entry.content, function()
			self:HideDialog()
		end)
	end)
end

function AudioLogController:HideDialog()
	if not isPlaying then return end
	
	self.isTyping = false
	isPlaying = false
	self.dialogTransparency:set(1)
	
	-- Notify server that we're done
	if AudioLogService then
		AudioLogService:NotifyDialogClosed()
	end
	
	task.delay(0.3, function()
		self.isVisible:set(false)
	end)
end

function AudioLogController:IsPlaying()
	return isPlaying
end

-- === KNIT LIFECYCLE ===

function AudioLogController:KnitInit()
	self.isTyping = false
	self.screenGui = nil
	self.currentContent = ""
end

function AudioLogController:KnitStart()
	-- Create UI
	createDialogUI(self)
	
	-- Connect to server audio log events
	AudioLogService = Knit.GetService("AudioLogService")
	
	-- Only this player receives the signal (server fires to specific player with entry index)
	AudioLogService.AudioLogTriggered:Connect(function(entryIndex)
		print("[AudioLogController] Received trigger for entry:", entryIndex)
		self:ShowDialog(entryIndex)
	end)
	
	print("[AudioLogController] Initialized")
end

return AudioLogController
