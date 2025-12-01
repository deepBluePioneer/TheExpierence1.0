local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Fusion = require(CustomPackages:WaitForChild("FusionRoot"):WaitForChild("Fusion"))

local New = Fusion.New
local Children = Fusion.Children
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring
local OnEvent = Fusion.OnEvent

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local LoadingController = Knit.CreateController {
	Name = "LoadingController",
	_loadingService = nil,
	_screenGui = nil,
	_isLoading = true,
}

-- === CONFIG ===
local LOADING_CONFIG = {
	-- Colors
	BackgroundColor = Color3.fromRGB(10, 10, 15),
	AccentColor = Color3.fromRGB(0, 180, 255),
	TextColor = Color3.fromRGB(255, 255, 255),
	SecondaryTextColor = Color3.fromRGB(150, 150, 160),
	
	-- Timing
	FadeOutTime = 1.5,
	
	-- Game info
	GameTitle = "THE EXPERIENCE",
	GameSubtitle = "LEVEL 1",
}

-- === UI COMPONENTS ===

local function createLoadingScreen(progressValue, statusText, tipsText, isVisible)
	-- Animated progress for smooth bar movement
	local smoothProgress = Spring(progressValue, 20, 0.8)
	
	return New "ScreenGui" {
		Name = "LoadingScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Parent = PlayerGui,
		
		[Children] = {
			-- Background
			New "Frame" {
				Name = "Background",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundColor3 = LOADING_CONFIG.BackgroundColor,
				BorderSizePixel = 0,
				
				Visible = Computed(function()
					return isVisible:get()
				end),
				
				BackgroundTransparency = Computed(function()
					return isVisible:get() and 0 or 1
				end),
				
				[Children] = {
					-- Subtle gradient overlay
					New "UIGradient" {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 30)),
							ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 10, 15)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 5, 10)),
						}),
						Rotation = 45,
					},
					
					-- Center container
					New "Frame" {
						Name = "CenterContainer",
						Size = UDim2.new(0.4, 0, 0.3, 0),
						Position = UDim2.new(0.5, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						
						[Children] = {
							-- Game title
							New "TextLabel" {
								Name = "Title",
								Size = UDim2.new(1, 0, 0, 60),
								Position = UDim2.new(0.5, 0, 0, 0),
								AnchorPoint = Vector2.new(0.5, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.GothamBold,
								Text = LOADING_CONFIG.GameTitle,
								TextColor3 = LOADING_CONFIG.TextColor,
								TextScaled = true,
								TextTransparency = Computed(function()
									return isVisible:get() and 0 or 1
								end),
							},
							
							-- Subtitle
							New "TextLabel" {
								Name = "Subtitle",
								Size = UDim2.new(1, 0, 0, 25),
								Position = UDim2.new(0.5, 0, 0, 65),
								AnchorPoint = Vector2.new(0.5, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.Gotham,
								Text = LOADING_CONFIG.GameSubtitle,
								TextColor3 = LOADING_CONFIG.AccentColor,
								TextScaled = true,
								TextTransparency = Computed(function()
									return isVisible:get() and 0.2 or 1
								end),
							},
							
							-- Progress bar container
							New "Frame" {
								Name = "ProgressContainer",
								Size = UDim2.new(0.8, 0, 0, 8),
								Position = UDim2.new(0.5, 0, 0.6, 0),
								AnchorPoint = Vector2.new(0.5, 0.5),
								BackgroundColor3 = Color3.fromRGB(30, 30, 40),
								BorderSizePixel = 0,
								
								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(1, 0),
									},
									
									-- Progress fill
									New "Frame" {
										Name = "ProgressFill",
										Size = Computed(function()
											local progress = smoothProgress:get()
											return UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)
										end),
										BackgroundColor3 = LOADING_CONFIG.AccentColor,
										BorderSizePixel = 0,
										
										[Children] = {
											New "UICorner" {
												CornerRadius = UDim.new(1, 0),
											},
											
											-- Glow effect
											New "UIGradient" {
												Color = ColorSequence.new({
													ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
													ColorSequenceKeypoint.new(0.5, LOADING_CONFIG.AccentColor),
													ColorSequenceKeypoint.new(1, LOADING_CONFIG.AccentColor),
												}),
												Transparency = NumberSequence.new({
													NumberSequenceKeypoint.new(0, 0.5),
													NumberSequenceKeypoint.new(0.3, 0),
													NumberSequenceKeypoint.new(1, 0),
												}),
											},
										},
									},
								},
							},
							
							-- Status text
							New "TextLabel" {
								Name = "StatusText",
								Size = UDim2.new(1, 0, 0, 20),
								Position = UDim2.new(0.5, 0, 0.6, 20),
								AnchorPoint = Vector2.new(0.5, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.Gotham,
								Text = Computed(function()
									return statusText:get()
								end),
								TextColor3 = LOADING_CONFIG.SecondaryTextColor,
								TextScaled = true,
								TextTransparency = Computed(function()
									return isVisible:get() and 0 or 1
								end),
							},
							
							-- Percentage
							New "TextLabel" {
								Name = "Percentage",
								Size = UDim2.new(1, 0, 0, 30),
								Position = UDim2.new(0.5, 0, 0.6, 45),
								AnchorPoint = Vector2.new(0.5, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.GothamBold,
								Text = Computed(function()
									local progress = progressValue:get()
									-- Clamp progress to 0-1 range to prevent values over 100%
									local clampedProgress = math.clamp(progress, 0, 1)
									return string.format("%.0f%%", clampedProgress * 100)
								end),
								TextColor3 = LOADING_CONFIG.TextColor,
								TextScaled = true,
								TextTransparency = Computed(function()
									return isVisible:get() and 0 or 1
								end),
							},
						},
					},
					
					-- Tips at bottom
					New "TextLabel" {
						Name = "Tips",
						Size = UDim2.new(0.6, 0, 0, 20),
						Position = UDim2.new(0.5, 0, 0.9, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamMedium,
						Text = Computed(function()
							return tipsText:get()
						end),
						TextColor3 = LOADING_CONFIG.SecondaryTextColor,
						TextScaled = true,
						TextTransparency = Computed(function()
							return isVisible:get() and 0.3 or 1
						end),
					},
					
					-- Animated dots
					New "TextLabel" {
						Name = "LoadingDots",
						Size = UDim2.new(0, 50, 0, 20),
						Position = UDim2.new(0.5, 0, 0.75, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamBold,
						Text = "...",
						TextColor3 = LOADING_CONFIG.AccentColor,
						TextSize = 24,
						TextTransparency = Computed(function()
							return isVisible:get() and 0 or 1
						end),
					},
				},
			},
		},
	}
end

-- === TIPS ===

local LOADING_TIPS = {
	"TIP: Stay alert in the dark...",
	"TIP: Use cover to stay safe",
	"TIP: Watch your surroundings",
	"TIP: Explore every corner",
	"TIP: The night brings danger",
}

local function getRandomTip()
	return LOADING_TIPS[math.random(1, #LOADING_TIPS)]
end

-- === LOADING LOGIC ===

local function preloadAssets(self, progressValue, statusText)
	statusText:set("Preloading assets...")
	
	-- Get assets to preload
	local assetsToPreload = {}
	
	-- Add workspace descendants
	for _, desc in ipairs(game.Workspace:GetDescendants()) do
		if desc:IsA("Decal") or desc:IsA("Texture") or desc:IsA("Sound") then
			table.insert(assetsToPreload, desc)
		end
	end
	
	-- Preload in batches
	if #assetsToPreload > 0 then
		local batchSize = 10
		for i = 1, #assetsToPreload, batchSize do
			local batch = {}
			for j = i, math.min(i + batchSize - 1, #assetsToPreload) do
				table.insert(batch, assetsToPreload[j])
			end
			
			ContentProvider:PreloadAsync(batch)
			
			-- Update progress (assets are 20% of loading)
			local assetProgress = (i / #assetsToPreload) * 0.2
			progressValue:set(math.max(progressValue:get(), assetProgress))
			
			task.wait()
		end
	end
end

local function hideLoadingScreen(self, screenGui, isVisible)
	print("[LoadingController] Hiding loading screen...")
	
	-- Fade out
	isVisible:set(false)
	
	-- Wait for fade then destroy
	task.delay(LOADING_CONFIG.FadeOutTime, function()
		if screenGui then
			screenGui:Destroy()
		end
		self._isLoading = false
		print("[LoadingController] Loading screen removed")
	end)
end

-- === KNIT LIFECYCLE ===

function LoadingController:KnitInit()
	print("[LoadingController] Initializing...")
end

function LoadingController:KnitStart()
	print("[LoadingController] Starting loading screen...")
	
	-- Create reactive values
	local progressValue = Value(0)
	local statusText = Value("Connecting to server...")
	local tipsText = Value(getRandomTip())
	local isVisible = Value(true)
	
	-- Create loading screen
	self._screenGui = createLoadingScreen(progressValue, statusText, tipsText, isVisible)
	
	-- Rotate tips
	task.spawn(function()
		while self._isLoading do
			task.wait(5)
			tipsText:set(getRandomTip())
		end
	end)
	
	-- Animate loading dots
	task.spawn(function()
		local dots = {".", "..", "...", ""}
		local dotIndex = 1
		
		-- Wait for UI to render
		task.wait(0.1)
		
		-- Find the dots label with retry
		local dotsLabel = nil
		local background = self._screenGui and self._screenGui:FindFirstChild("Background")
		if background then
			dotsLabel = background:FindFirstChild("LoadingDots")
		end
		
		while self._isLoading do
			if dotsLabel and dotsLabel.Parent then
				dotsLabel.Text = dots[dotIndex]
				dotIndex = (dotIndex % #dots) + 1
			end
			task.wait(0.4)
		end
	end)
	
	-- Preload assets
	task.spawn(function()
		preloadAssets(self, progressValue, statusText)
	end)
	
	-- Get LoadingService
	print("[LoadingController] Connecting to LoadingService...")
	self._loadingService = Knit.GetService("LoadingService")
	
	-- Track if server is ready to prevent progress from going backwards
	local serverReady = false
	
	-- Listen for server ready
	self._loadingService.ServerReady:Connect(function()
		print("[LoadingController] Server ready signal received!")
		serverReady = true
		progressValue:set(1)
		statusText:set("Ready!")
		
		-- Brief delay to show 100%
		task.wait(0.5)
		
		-- Hide loading screen
		hideLoadingScreen(self, self._screenGui, isVisible)
	end)
	
	-- Listen for progress updates (set up early to catch all updates)
	self._loadingService.LoadingProgress:Connect(function(progress, description)
		if not serverReady then
			-- Clamp progress to 0-1 range to prevent invalid values
			local clampedProgress = math.clamp(progress or 0, 0, 1)
			-- Only update if progress is higher than current (monotonic - never go backwards)
			local currentProgress = progressValue:get()
			if clampedProgress > currentProgress then
				print(string.format("[LoadingController] Progress update: %.0f%% - %s", clampedProgress * 100, description))
				progressValue:set(clampedProgress)
				statusText:set(description)
			end
		end
	end)
	
	-- Check if already ready FIRST (before getting progress)
	self._loadingService:IsServerReady():andThen(function(isReady)
		if isReady then
			print("[LoadingController] Server already ready!")
			serverReady = true
			progressValue:set(1)
			statusText:set("Ready!")
			task.wait(0.5)
			hideLoadingScreen(self, self._screenGui, isVisible)
		else
			-- Only get initial progress if server is not ready yet
			self._loadingService:GetLoadingProgress():andThen(function(initialProgress, initialStatus)
				if not serverReady then
					-- Clamp initial progress to 0-1 range
					local clampedInitial = initialProgress and math.clamp(initialProgress, 0, 1) or 0
					-- Only update if progress is higher than current (monotonic - never go backwards)
					local currentProgress = progressValue:get()
					if clampedInitial > currentProgress then
						print(string.format("[LoadingController] Initial progress: %.0f%% - %s", clampedInitial * 100, initialStatus or "Loading..."))
						progressValue:set(clampedInitial)
						if initialStatus then
							statusText:set(initialStatus)
						end
					end
				end
			end):catch(function(err)
				warn("[LoadingController] Failed to get initial progress:", err)
			end)
		end
	end):catch(function(err)
		warn("[LoadingController] Failed to check server ready:", err)
	end)
end

-- === PUBLIC METHODS ===

function LoadingController:IsLoading()
	return self._isLoading
end

function LoadingController:ForceHide()
	if self._screenGui then
		self._screenGui:Destroy()
		self._screenGui = nil
	end
	self._isLoading = false
end

return LoadingController

