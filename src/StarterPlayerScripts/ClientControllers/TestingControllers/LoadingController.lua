--[[
	LoadingController
	Sci-Fi Computer Boot Sequence Loading Screen
	Matches the Helmet HUD visual theme
]]

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

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local LoadingController = Knit.CreateController {
	Name = "LoadingController",
	_loadingService = nil,
	_screenGui = nil,
	_isLoading = true,
}

-- === CONFIG ===
local BOOT_CONFIG = {
	-- Colors - Same as Helmet HUD
	BackgroundColor = Color3.fromRGB(5, 12, 18),
	PrimaryColor = Color3.fromRGB(0, 235, 235),
	SecondaryColor = Color3.fromRGB(0, 190, 210),
	AccentColor = Color3.fromRGB(120, 255, 255),
	DimColor = Color3.fromRGB(0, 100, 120),
	WarningColor = Color3.fromRGB(255, 190, 0),
	TextColor = Color3.fromRGB(0, 220, 220),
	DimTextColor = Color3.fromRGB(0, 130, 150),
	
	-- Timing
	FadeOutTime = 1.2,
	
	-- System info
	SystemName = "NEXUS-7  EXOSUIT",
	SystemVersion = "v4.7.2",
	MissionName = "KEPLER-442b SURVEY",
}

-- === BOOT SEQUENCE MESSAGES ===
local BOOT_SEQUENCE = {
	{text = "NEXUS-7 EXOSUIT SYSTEMS", delay = 0.3, color = "accent"},
	{text = "═══════════════════════════════════════", delay = 0.1, color = "dim"},
	{text = "", delay = 0.2},
	{text = "INITIALIZING BOOT SEQUENCE...", delay = 0.4, color = "primary"},
	{text = "", delay = 0.1},
	{text = "[BIOS] Power-on self-test.............. OK", delay = 0.2},
	{text = "[BIOS] Memory check: 128TB quantum RAM.. OK", delay = 0.15},
	{text = "[BIOS] Neural interface calibration..... OK", delay = 0.2},
	{text = "", delay = 0.1},
	{text = "Loading NEXUS-OS v4.7.2", delay = 0.3, color = "primary"},
	{text = "Copyright 2187 Nexus Aerospace Corp.", delay = 0.1, color = "dim"},
	{text = "", delay = 0.2},
	{text = "[CORE] Initializing reactor core........ ", delay = 0.3, progress = 0.1},
	{text = "[LIFE] Life support systems online...... ", delay = 0.25, progress = 0.2},
	{text = "[ATMO] Atmospheric processors active.... ", delay = 0.2, progress = 0.25},
	{text = "[SENS] Environmental sensors ready...... ", delay = 0.2, progress = 0.3},
	{text = "[COMM] Establishing uplink.............. ", delay = 0.35, progress = 0.35},
	{text = "[NAV]  Navigation systems online........ ", delay = 0.2, progress = 0.4},
	{text = "[WEAP] Defense systems armed............ ", delay = 0.25, progress = 0.45},
	{text = "[HUD]  Visor HUD initializing........... ", delay = 0.3, progress = 0.5},
	{text = "", delay = 0.1},
	{text = "LOADING MISSION PARAMETERS...", delay = 0.4, color = "warning"},
	{text = "Mission: KEPLER-442b PLANETARY SURVEY", delay = 0.2, color = "primary"},
	{text = "Threat Level: UNKNOWN", delay = 0.15, color = "warning"},
	{text = "Atmosphere: HOSTILE - SEALED SUIT REQUIRED", delay = 0.2, color = "warning"},
	{text = "", delay = 0.2},
}

local STATUS_MESSAGES = {
	["Connecting to server..."] = "[NET]  Establishing server connection... ",
	["Initializing world..."] = "[WORLD] Generating terrain matrix....... ",
	["Loading terrain..."] = "[TERR] Loading geological data.......... ",
	["Spawning entities..."] = "[BIO]  Cataloging lifeforms............. ",
	["Loading assets..."] = "[DATA] Downloading mission assets....... ",
	["Finalizing..."] = "[SYS]  Finalizing system checks......... ",
	["Ready!"] = "[BOOT] ALL SYSTEMS OPERATIONAL",
}

-- === STATE ===
local bootLines = Value({})
local currentProgress = Value(0)
local isVisible = Value(true)
local cursorBlink = Value(true)

-- === UI COMPONENTS ===

local function createScanLines(parent)
	local lines = {}
	for i = 1, 100 do
		table.insert(lines, New "Frame" {
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.new(0, 0, i / 100, 0),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.92,
			BorderSizePixel = 0,
		})
	end
	
	return New "Frame" {
		Name = "ScanLines",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		[Children] = lines,
	}
end

local function createBootTerminal(parent, animatedProgress)
	return New "Frame" {
		Name = "BootTerminal",
		Size = UDim2.new(0.7, 0, 0.75, 0),
		Position = UDim2.new(0.5, 0, 0.48, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(3, 8, 12),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = parent,
		
		[Children] = {
			New "UIStroke" {
				Color = BOOT_CONFIG.DimColor,
				Thickness = 2,
				Transparency = 0.5,
			},
			New "UICorner" {
				CornerRadius = UDim.new(0, 4),
			},
			
			New "Frame" {
				Name = "Header",
				Size = UDim2.new(1, 0, 0, 35),
				BackgroundColor3 = BOOT_CONFIG.DimColor,
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0, 4),
					},
					New "TextLabel" {
						Size = UDim2.new(1, -20, 1, 0),
						Position = UDim2.new(0, 10, 0, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.RobotoMono,
						Text = "◈ NEXUS-7 BOOT TERMINAL ◈",
						TextColor3 = BOOT_CONFIG.PrimaryColor,
						TextSize = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					New "Frame" {
						Size = UDim2.new(0, 12, 0, 12),
						Position = UDim2.new(1, -50, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = BOOT_CONFIG.WarningColor,
						BorderSizePixel = 0,
						[Children] = { New "UICorner" { CornerRadius = UDim.new(1, 0) } },
					},
					New "Frame" {
						Size = UDim2.new(0, 12, 0, 12),
						Position = UDim2.new(1, -30, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = BOOT_CONFIG.PrimaryColor,
						BorderSizePixel = 0,
						[Children] = { New "UICorner" { CornerRadius = UDim.new(1, 0) } },
					},
				},
			},
			
			New "ScrollingFrame" {
				Name = "Content",
				Size = UDim2.new(1, -20, 1, -100),
				Position = UDim2.new(0, 10, 0, 40),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				ScrollBarImageColor3 = BOOT_CONFIG.DimColor,
				CanvasSize = UDim2.new(0, 0, 0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				
				[Children] = {
					New "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 2),
					},
				},
			},
			
			New "Frame" {
				Name = "StatusBar",
				Size = UDim2.new(1, 0, 0, 50),
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = BOOT_CONFIG.DimColor,
				BackgroundTransparency = 0.85,
				BorderSizePixel = 0,
				
				[Children] = {
					New "Frame" {
						Name = "ProgressBG",
						Size = UDim2.new(0.6, 0, 0, 8),
						Position = UDim2.new(0.02, 0, 0.35, 0),
						BackgroundColor3 = Color3.fromRGB(10, 20, 25),
						BorderSizePixel = 0,
						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(1, 0) },
							New "UIStroke" {
								Color = BOOT_CONFIG.DimColor,
								Thickness = 1,
								Transparency = 0.6,
							},
							New "Frame" {
								Name = "Fill",
								Size = Computed(function()
									return UDim2.new(math.clamp(animatedProgress:get(), 0, 1), 0, 1, 0)
								end),
								BackgroundColor3 = BOOT_CONFIG.PrimaryColor,
								BorderSizePixel = 0,
								[Children] = {
									New "UICorner" { CornerRadius = UDim.new(1, 0) },
									New "UIGradient" {
										Color = ColorSequence.new({
											ColorSequenceKeypoint.new(0, BOOT_CONFIG.AccentColor),
											ColorSequenceKeypoint.new(1, BOOT_CONFIG.PrimaryColor),
										}),
									},
								},
							},
						},
					},
					
					New "TextLabel" {
						Size = UDim2.new(0.15, 0, 0.4, 0),
						Position = UDim2.new(0.64, 0, 0.3, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.RobotoMono,
						Text = Computed(function()
							return string.format("%.0f%%", math.clamp(animatedProgress:get(), 0, 1) * 100)
						end),
						TextColor3 = BOOT_CONFIG.AccentColor,
						TextSize = 16,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					
					New "TextLabel" {
						Size = UDim2.new(0.35, 0, 0.35, 0),
						Position = UDim2.new(0.02, 0, 0.6, 0),
						BackgroundTransparency = 1,
						Font = Enum.Font.RobotoMono,
						Text = Computed(function()
							local prog = animatedProgress:get()
							if prog >= 1 then return "STATUS: BOOT COMPLETE"
							elseif prog >= 0.8 then return "STATUS: FINALIZING..."
							elseif prog >= 0.5 then return "STATUS: LOADING SUBSYSTEMS..."
							else return "STATUS: INITIALIZING..." end
						end),
						TextColor3 = Computed(function()
							return animatedProgress:get() >= 1 and BOOT_CONFIG.AccentColor or BOOT_CONFIG.DimTextColor
						end),
						TextSize = 11,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					
					New "TextLabel" {
						Size = UDim2.new(0.2, 0, 0.4, 0),
						Position = UDim2.new(0.98, 0, 0.5, 0),
						AnchorPoint = Vector2.new(1, 0.5),
						BackgroundTransparency = 1,
						Font = Enum.Font.RobotoMono,
						Text = Computed(function()
							return cursorBlink:get() and "▌" or " "
						end),
						TextColor3 = BOOT_CONFIG.PrimaryColor,
						TextSize = 18,
						TextXAlignment = Enum.TextXAlignment.Right,
					},
				},
			},
		},
	}
end

local function createTopBar(parent)
	return New "Frame" {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = BOOT_CONFIG.DimColor,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = parent,
		
		[Children] = {
			New "TextLabel" {
				Size = UDim2.new(0.3, 0, 1, 0),
				Position = UDim2.new(0, 15, 0, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.SciFi,
				Text = "◈ " .. BOOT_CONFIG.SystemName,
				TextColor3 = BOOT_CONFIG.PrimaryColor,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
			New "TextLabel" {
				Size = UDim2.new(0.4, 0, 1, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				Text = "MISSION: " .. BOOT_CONFIG.MissionName,
				TextColor3 = BOOT_CONFIG.SecondaryColor,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Center,
			},
			New "TextLabel" {
				Size = UDim2.new(0.2, 0, 1, 0),
				Position = UDim2.new(1, -15, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.RobotoMono,
				Text = BOOT_CONFIG.SystemVersion,
				TextColor3 = BOOT_CONFIG.DimTextColor,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Right,
			},
		},
	}
end

local function createCornerDecorations(parent)
	local decorations = {}
	local cornerSize = 30
	local margin = 15
	
	local corners = {
		{pos = UDim2.new(0, margin, 0, margin + 40), anchor = Vector2.new(0, 0)},
		{pos = UDim2.new(1, -margin, 0, margin + 40), anchor = Vector2.new(1, 0)},
		{pos = UDim2.new(0, margin, 1, -margin), anchor = Vector2.new(0, 1)},
		{pos = UDim2.new(1, -margin, 1, -margin), anchor = Vector2.new(1, 1)},
	}
	
	for _, c in ipairs(corners) do
		table.insert(decorations, New "Frame" {
			Size = UDim2.new(0, cornerSize, 0, 2),
			Position = c.pos,
			AnchorPoint = c.anchor,
			BackgroundColor3 = BOOT_CONFIG.DimColor,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		})
		table.insert(decorations, New "Frame" {
			Size = UDim2.new(0, 2, 0, cornerSize),
			Position = c.pos,
			AnchorPoint = c.anchor,
			BackgroundColor3 = BOOT_CONFIG.DimColor,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		})
	end
	
	return New "Frame" {
		Name = "CornerDecorations",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = parent,
		[Children] = decorations,
	}
end

local function createLoadingScreen()
	local smoothProgress = Spring(currentProgress, 15, 0.9)
	
	return New "ScreenGui" {
		Name = "BootScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Parent = PlayerGui,
		
		[Children] = {
			New "Frame" {
				Name = "Background",
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundColor3 = BOOT_CONFIG.BackgroundColor,
				BorderSizePixel = 0,
				
				Visible = Computed(function()
					return isVisible:get()
				end),
				
				[Children] = {
					New "UIGradient" {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 15, 22)),
							ColorSequenceKeypoint.new(0.5, BOOT_CONFIG.BackgroundColor),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(3, 8, 12)),
						}),
						Rotation = 135,
					},
					createScanLines(nil),
					createTopBar(nil),
					createCornerDecorations(nil),
					createBootTerminal(nil, smoothProgress),
				},
			},
		},
	}
end

-- === BOOT TEXT ===

local function addBootLine(text, colorType)
	local lines = bootLines:get()
	local newLines = {}
	for _, line in ipairs(lines) do
		table.insert(newLines, line)
	end
	
	local color = BOOT_CONFIG.TextColor
	if colorType == "accent" then
		color = BOOT_CONFIG.AccentColor
	elseif colorType == "primary" then
		color = BOOT_CONFIG.PrimaryColor
	elseif colorType == "dim" then
		color = BOOT_CONFIG.DimTextColor
	elseif colorType == "warning" then
		color = BOOT_CONFIG.WarningColor
	end
	
	table.insert(newLines, {text = text, color = color})
	bootLines:set(newLines)
	
	local screenGui = PlayerGui:FindFirstChild("BootScreen")
	if screenGui then
		local content = screenGui:FindFirstChild("Background")
		if content then
			content = content:FindFirstChild("BootTerminal")
			if content then
				content = content:FindFirstChild("Content")
				if content then
					local label = Instance.new("TextLabel")
					label.Name = "Line" .. #newLines
					label.Size = UDim2.new(1, 0, 0, 16)
					label.BackgroundTransparency = 1
					label.Font = Enum.Font.RobotoMono
					label.Text = text
					label.TextColor3 = color
					label.TextSize = 13
					label.TextXAlignment = Enum.TextXAlignment.Left
					label.LayoutOrder = #newLines
					label.Parent = content
					
					content.CanvasPosition = Vector2.new(0, content.AbsoluteCanvasSize.Y)
				end
			end
		end
	end
end

local function runBootSequence()
	task.spawn(function()
		task.wait(0.5)
		
		for i, entry in ipairs(BOOT_SEQUENCE) do
			if not isVisible:get() then break end
			
			addBootLine(entry.text, entry.color)
			
			if entry.progress then
				local newProgress = math.max(currentProgress:get(), entry.progress)
				currentProgress:set(newProgress)
			end
			
			task.wait(entry.delay or 0.15)
		end
	end)
end

local function startCursorBlink()
	task.spawn(function()
		while isVisible:get() do
			cursorBlink:set(not cursorBlink:get())
			task.wait(0.5)
		end
	end)
end

-- === LOADING LOGIC ===

local function preloadAssets(progressCallback)
	local assetsToPreload = {}
	
	for _, desc in ipairs(game.Workspace:GetDescendants()) do
		if desc:IsA("Decal") or desc:IsA("Texture") or desc:IsA("Sound") then
			table.insert(assetsToPreload, desc)
		end
	end
	
	if #assetsToPreload > 0 then
		local batchSize = 10
		for i = 1, #assetsToPreload, batchSize do
			local batch = {}
			for j = i, math.min(i + batchSize - 1, #assetsToPreload) do
				table.insert(batch, assetsToPreload[j])
			end
			
			ContentProvider:PreloadAsync(batch)
			
			local assetProgress = (i / #assetsToPreload) * 0.15
			progressCallback(assetProgress)
			
			task.wait()
		end
	end
end

local function hideLoadingScreen(self, screenGui)
	print("[BootSequence] Shutdown initiated...")
	
	addBootLine("", nil)
	addBootLine("═══════════════════════════════════════", "dim")
	addBootLine("[BOOT] ALL SYSTEMS OPERATIONAL", "accent")
	addBootLine("[BOOT] INITIALIZING VISOR HUD...", "primary")
	addBootLine("[BOOT] WELCOME, OPERATOR", "primary")
	addBootLine("═══════════════════════════════════════", "dim")
	
	task.wait(1.2)
	
	isVisible:set(false)
	
	if screenGui then
		local bg = screenGui:FindFirstChild("Background")
		if bg then
			local tween = TweenService:Create(bg, TweenInfo.new(BOOT_CONFIG.FadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1
			})
			tween:Play()
			
			for _, child in ipairs(bg:GetDescendants()) do
				if child:IsA("Frame") then
					TweenService:Create(child, TweenInfo.new(BOOT_CONFIG.FadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
				elseif child:IsA("TextLabel") then
					TweenService:Create(child, TweenInfo.new(BOOT_CONFIG.FadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1}):Play()
				elseif child:IsA("UIStroke") then
					TweenService:Create(child, TweenInfo.new(BOOT_CONFIG.FadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
				elseif child:IsA("ScrollingFrame") then
					TweenService:Create(child, TweenInfo.new(BOOT_CONFIG.FadeOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {ScrollBarImageTransparency = 1}):Play()
				end
			end
		end
	end
	
	task.delay(BOOT_CONFIG.FadeOutTime * 0.4, function()
		local success, err = pcall(function()
			local CameraUIController = Knit.GetController("CameraUIController")
			if CameraUIController and CameraUIController.FadeIn then
				print("[BootSequence] Handing off to Helmet HUD...")
				CameraUIController:FadeIn(1.8)
			end
		end)
		
		if not success then
			warn("[BootSequence] Failed to fade in HUD:", err)
		end
	end)
	
	task.delay(BOOT_CONFIG.FadeOutTime + 0.3, function()
		if screenGui then
			screenGui:Destroy()
		end
		self._isLoading = false
		print("[BootSequence] Boot sequence complete - Terminal closed")
	end)
end

local function updateStatusMessage(message)
	local mappedMessage = STATUS_MESSAGES[message]
	if mappedMessage then
		addBootLine(mappedMessage .. "OK", nil)
	else
		addBootLine("[SYS]  " .. message, nil)
	end
end

-- === KNIT LIFECYCLE ===

function LoadingController:KnitInit()
	print("[BootSequence] Pre-boot check...")
end

function LoadingController:KnitStart()
	print("[BootSequence] Initiating boot sequence...")
	
	self._screenGui = createLoadingScreen()
	
	startCursorBlink()
	runBootSequence()
	
	task.spawn(function()
		preloadAssets(function(progress)
			currentProgress:set(math.max(currentProgress:get(), progress))
		end)
	end)
	
	self._loadingService = Knit.GetService("LoadingService")
	
	local serverReady = false
	local lastStatus = ""
	
	self._loadingService.ServerReady:Connect(function()
		print("[BootSequence] Server handshake complete")
		serverReady = true
		currentProgress:set(1)
		
		task.wait(0.8)
		hideLoadingScreen(self, self._screenGui)
	end)
	
	self._loadingService.LoadingProgress:Connect(function(progress, description)
		if not serverReady then
			local clampedProgress = math.clamp(progress or 0, 0, 1)
			local mappedProgress = 0.5 + (clampedProgress * 0.5)
			
			if mappedProgress > currentProgress:get() then
				currentProgress:set(mappedProgress)
				
				if description and description ~= lastStatus then
					lastStatus = description
					updateStatusMessage(description)
				end
			end
		end
	end)
	
	self._loadingService:IsServerReady():andThen(function(isReady)
		if isReady then
			print("[BootSequence] Server already operational")
			serverReady = true
			currentProgress:set(1)
			task.wait(0.8)
			hideLoadingScreen(self, self._screenGui)
		else
			self._loadingService:GetLoadingProgress():andThen(function(initialProgress, initialStatus)
				if not serverReady then
					local clampedInitial = initialProgress and math.clamp(initialProgress, 0, 1) or 0
					local mappedProgress = 0.5 + (clampedInitial * 0.5)
					
					if mappedProgress > currentProgress:get() then
						currentProgress:set(mappedProgress)
						if initialStatus then
							updateStatusMessage(initialStatus)
						end
					end
				end
			end):catch(function(err)
				warn("[BootSequence] Failed to get initial progress:", err)
			end)
		end
	end):catch(function(err)
		warn("[BootSequence] Failed server check:", err)
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
