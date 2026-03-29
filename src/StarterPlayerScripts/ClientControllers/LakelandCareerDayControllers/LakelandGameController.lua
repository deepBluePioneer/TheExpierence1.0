local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local StarterPlayer = game:GetService("StarterPlayer")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Signal = require(Packages.Signal)

local Workspace = game:GetService("Workspace")

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)
local Value = Fusion.Value
local TableUtil = require(Packages.TableUtil)

local ControllersFolder = StarterPlayer.StarterPlayerScripts.Source.ClientControllers.LakelandCareerDayControllers
local LakelandHealthBarUI = require(ControllersFolder.LakelandHealthBarUI)
local LakelandDistanceUI = require(ControllersFolder.LakelandDistanceUI)
local LakelandEndGameUI = require(ControllersFolder.LakelandEndGameUI)
local LakelandBombUI = require(ControllersFolder.LakelandBombUI)
local LakelandWipeTransition = require(ControllersFolder.LakelandWipeTransition)
local LakelandDangerVignetteUI = require(ControllersFolder.LakelandDangerVignetteUI)

local END_SCREEN_DURATION = 5

local LocalPlayer = Players.LocalPlayer

local STATES = {
	LOBBY = "LOBBY",
	PLAYING = "PLAYING",
	GAME_OVER = "GAME_OVER",
}

-- Match LakelandDataService: center Y=50, thickness=4 → top surface Y=52
local LOBBY_CENTER = Vector3.new(0, 50, -200)
local LOBBY_PLATFORM_SIZE = Vector3.new(200, 4, 200)
local LOBBY_PLATFORM_THICKNESS = 4
local LOBBY_SURFACE_Y = LOBBY_CENTER.Y + LOBBY_PLATFORM_THICKNESS / 2
local LOBBY_SPAWN_POS = Vector3.new(LOBBY_CENTER.X, LOBBY_SURFACE_Y + 3, LOBBY_CENTER.Z + 15)

---------------------------------------------------------------------------
-- Background Music
---------------------------------------------------------------------------
local BGM_FADE_TIME = 1.5
local BGM_VOLUME = 0.25

local MENU_TRACK_ID = "rbxassetid://130353120493764"

local MUSIC_GROUP = SoundService:FindFirstChild("music")
local GAME_TRACK_IDS = {}

if MUSIC_GROUP then
	for _, child in ipairs(MUSIC_GROUP:GetChildren()) do
		if child:IsA("Sound") and child.SoundId ~= "" then
			table.insert(GAME_TRACK_IDS, child.SoundId)
		end
	end
end
if #GAME_TRACK_IDS == 0 then
	table.insert(GAME_TRACK_IDS, "rbxassetid://5409360995")
end

local LakelandGameController = Knit.CreateController({
	Name = "LakelandGameController",

	GameStateChanged = Signal.new(),

	_trove = nil,
	_gameState = nil,
	_topScores = nil,
	_previousNames = nil,
	_currentPlayerName = nil,
	_wipe = nil,
	_healthConn = nil,
	_gameEnding = false,

	_bgmCurrent = nil,
	_bgmFadeTween = nil,
	_gameTrackOrder = {},
	_gameTrackIndex = 0,
	_bgmEndedConn = nil,
	_beatIntensity = nil,
	_beatConn = nil,

	_seatedConn = nil,
	_unseatConn = nil,
	_lobbyReady = false,
	_chosenTemplate = nil,
	_lobbyHyperjumpGui = nil,
})

local MAX_LEADERBOARD_ENTRIES = 10

function LakelandGameController:KnitInit()
	self._trove = Trove.new()
	self._gameState = Value(STATES.LOBBY)
	self._topScores = Value({})
	self._previousNames = Value({})
	self._currentPlayerName = ""
	self._playerNameValue = Value("")
	self._beatIntensity = Value(0)
end

local MIN_LOAD_DURATION = 3.5

function LakelandGameController:KnitStart()
	self._dataService = Knit.GetService("LakelandDataService")
	self._raceController = Knit.GetController("LakelandRaceController")

	local loadScreen = self:_createLoadingScreen()
	local loadStart = tick()

	loadScreen.setStatus("Connecting...")
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	loadScreen.setProgress(0.25)

	loadScreen.setStatus("Loading player data...")
	self:_loadFromServer()
	loadScreen.setProgress(0.55)

	loadScreen.setStatus("Building world...")
	self:_createUI()
	loadScreen.setProgress(0.80)

	self._beatConn = RunService.Heartbeat:Connect(function(dt)
		local raw = (self._bgmCurrent and self._bgmCurrent.PlaybackLoudness or 0) / 400
		raw = math.clamp(raw, 0, 1)
		local current = self._beatIntensity:get()
		local smoothed = current + (raw - current) * math.min(dt * 12, 1)
		self._beatIntensity:set(smoothed)
	end)
	self._trove:Add(self._beatConn)

	loadScreen.setStatus("Preparing lobby...")
	self:_enterLobby()
	loadScreen.setProgress(1)

	local elapsed = tick() - loadStart
	if elapsed < MIN_LOAD_DURATION then
		loadScreen.setStatus("Ready")
		task.wait(MIN_LOAD_DURATION - elapsed)
	end

	loadScreen.fadeOut()
	self:_playMenuMusic()

	print("[LakelandGameController] Ready - entering lobby")
end

function LakelandGameController:_createLoadingScreen()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")

	local sg = Instance.new("ScreenGui")
	sg.Name = "LoadingScreen"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 999
	sg.Parent = playerGui

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(6, 10, 22)
	bg.BorderSizePixel = 0
	bg.Parent = sg

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 14, 30)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(6, 10, 22)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 6, 16)),
	})
	grad.Rotation = 135
	grad.Parent = bg

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	titleLabel.Position = UDim2.fromScale(0.5, 0.40)
	titleLabel.Size = UDim2.fromScale(0.6, 0.08)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.Text = "LAKELAND"
	titleLabel.TextColor3 = Color3.fromRGB(0, 200, 255)
	titleLabel.TextScaled = true
	titleLabel.TextTransparency = 0
	titleLabel.Parent = sg

	local titleSizeConstraint = Instance.new("UITextSizeConstraint")
	titleSizeConstraint.MaxTextSize = 72
	titleSizeConstraint.Parent = titleLabel

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(0, 120, 180)
	titleStroke.Thickness = 2
	titleStroke.Transparency = 0.3
	titleStroke.Parent = titleLabel

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.AnchorPoint = Vector2.new(0.5, 0)
	subtitleLabel.Position = UDim2.fromScale(0.5, 0.46)
	subtitleLabel.Size = UDim2.fromScale(0.35, 0.035)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = Enum.Font.GothamBold
	subtitleLabel.Text = "CAREER DAY"
	subtitleLabel.TextColor3 = Color3.fromRGB(140, 180, 220)
	subtitleLabel.TextScaled = true
	subtitleLabel.Parent = sg

	local subtitleConstraint = Instance.new("UITextSizeConstraint")
	subtitleConstraint.MaxTextSize = 28
	subtitleConstraint.Parent = subtitleLabel

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.AnchorPoint = Vector2.new(0.5, 0.5)
	barBg.Position = UDim2.fromScale(0.5, 0.56)
	barBg.Size = UDim2.fromScale(0.3, 0.008)
	barBg.BackgroundColor3 = Color3.fromRGB(20, 30, 50)
	barBg.BorderSizePixel = 0
	barBg.Parent = sg

	local barBgCorner = Instance.new("UICorner")
	barBgCorner.CornerRadius = UDim.new(0.5, 0)
	barBgCorner.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(0.5, 0)
	barFillCorner.Parent = barFill

	local barGlow = Instance.new("UIStroke")
	barGlow.Color = Color3.fromRGB(0, 160, 220)
	barGlow.Thickness = 1
	barGlow.Transparency = 0.5
	barGlow.Parent = barBg

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.AnchorPoint = Vector2.new(0.5, 0)
	statusLabel.Position = UDim2.fromScale(0.5, 0.585)
	statusLabel.Size = UDim2.fromScale(0.3, 0.025)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Text = ""
	statusLabel.TextColor3 = Color3.fromRGB(100, 130, 170)
	statusLabel.TextScaled = true
	statusLabel.Parent = sg

	local statusConstraint = Instance.new("UITextSizeConstraint")
	statusConstraint.MaxTextSize = 16
	statusConstraint.Parent = statusLabel

	TweenService:Create(titleLabel, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()

	local function setProgress(frac)
		frac = math.clamp(frac, 0, 1)
		TweenService:Create(barFill, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(frac, 1),
		}):Play()
	end

	local function setStatus(text)
		statusLabel.Text = text
	end

	local function fadeOut()
		local fadeDuration = 0.8
		local fadeElements = {
			TweenService:Create(bg, TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			}),
			TweenService:Create(titleLabel, TweenInfo.new(fadeDuration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
			}),
			TweenService:Create(titleStroke, TweenInfo.new(fadeDuration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			}),
			TweenService:Create(subtitleLabel, TweenInfo.new(fadeDuration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
			}),
			TweenService:Create(barBg, TweenInfo.new(fadeDuration * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			}),
			TweenService:Create(barFill, TweenInfo.new(fadeDuration * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			}),
			TweenService:Create(barGlow, TweenInfo.new(fadeDuration * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			}),
			TweenService:Create(statusLabel, TweenInfo.new(fadeDuration * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
			}),
		}
		for _, t in ipairs(fadeElements) do
			t:Play()
		end
		task.delay(fadeDuration + 0.1, function()
			sg:Destroy()
		end)
	end

	return {
		setProgress = setProgress,
		setStatus = setStatus,
		fadeOut = fadeOut,
	}
end

function LakelandGameController:_ensureCharacter(freeze)
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")

	if not (character and character.Parent and humanoid and hrp) then
		self._dataService:LoadCharacter():expect()
		character = LocalPlayer.Character
		if not character then
			character = LocalPlayer.CharacterAdded:Wait()
		end
		humanoid = character:WaitForChild("Humanoid")
		humanoid:WaitForChild("Animator")
		character:WaitForChild("HumanoidRootPart", 10)
	end

	if freeze then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	else
		humanoid.WalkSpeed = 16
		humanoid.JumpHeight = 7.2
		humanoid.JumpPower = 50
	end

	return character, humanoid
end

function LakelandGameController:_loadCharacter(freeze)
	self._dataService:LoadCharacter():expect()

	local character = LocalPlayer.Character
	if not character then
		character = LocalPlayer.CharacterAdded:Wait()
	end
	local humanoid = character:WaitForChild("Humanoid")
	humanoid:WaitForChild("Animator")
	character:WaitForChild("HumanoidRootPart", 10)

	if freeze then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	else
		humanoid.WalkSpeed = 16
		humanoid.JumpHeight = 7.2
		humanoid.JumpPower = 50
	end

	return character, humanoid
end

function LakelandGameController:_createUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")

	self._healthBar = LakelandHealthBarUI.new(playerGui, self._gameState, self._beatIntensity)
	self._trove:Add(function()
		self._healthBar.destroy()
	end)

	self._distanceUI = LakelandDistanceUI.new(playerGui, self._gameState, self._playerNameValue, self._beatIntensity)
	self._trove:Add(function()
		self._distanceUI.destroy()
	end)

	self._endGameUI = LakelandEndGameUI.new(playerGui, self._gameState)
	self._trove:Add(function()
		self._endGameUI.destroy()
	end)

	self._bombUI = LakelandBombUI.new(playerGui, self._gameState, self._beatIntensity)
	self._trove:Add(function()
		self._bombUI.destroy()
	end)

	self._wipe = LakelandWipeTransition.new(playerGui)
	self._trove:Add(function()
		self._wipe.destroy()
	end)

	self._dangerVignette = LakelandDangerVignetteUI.new(playerGui, self._gameState, self._beatIntensity)
	self._trove:Add(function()
		self._dangerVignette.destroy()
	end)

	self._trove:Add(function()
		self:_stopBGM()
	end)
end

---------------------------------------------------------------------------
-- Lobby flow
---------------------------------------------------------------------------
function LakelandGameController:_applyLobbyLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.35
	Lighting.Ambient = Color3.fromRGB(188, 198, 218)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 168, 198)
	Lighting.FogColor = Color3.fromRGB(178, 206, 238)
	Lighting.FogStart = 800
	Lighting.FogEnd = 12000
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.42

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.22
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(190, 215, 255)
	atmosphere.Decay = Color3.fromRGB(125, 160, 210)
	atmosphere.Glare = 0.22
	atmosphere.Haze = 0.45

	local bloom = Lighting:FindFirstChild("RaceBloom")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "RaceBloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.1
	bloom.Size = 12
	bloom.Threshold = 1.15

	local cc = Lighting:FindFirstChild("RaceCC")
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "RaceCC"
		cc.Parent = Lighting
	end
	cc.Brightness = 0.12
	cc.Contrast = 0.06
	cc.Saturation = 0.08
	cc.TintColor = Color3.fromRGB(255, 252, 245)
end

function LakelandGameController:_enterLobby()
	self:_setState(STATES.LOBBY)

	Workspace.Terrain:FillBlock(
		CFrame.new(LOBBY_CENTER),
		LOBBY_PLATFORM_SIZE,
		Enum.Material.Grass
	)

	self._dataService:CreateLobbyPlatform()
	self._dataService:SpawnLobbyMachines()

	local character, humanoid = self:_ensureCharacter(false)

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(LOBBY_SPAWN_POS) * CFrame.Angles(0, math.rad(180), 0)
	end

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid

	self:_applyLobbyLighting()

	self._lobbyReady = true
	self:_startSeatWatch()
	print("[LakelandGameController] Entered lobby")
end

function LakelandGameController:_startSeatWatch()
	self:_stopSeatWatch()

	self._seatedConn = RunService.Heartbeat:Connect(function()
		if self._gameState:get() ~= STATES.LOBBY then return end

		local character = LocalPlayer.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end

		if not humanoid.Sit then return end

		local seatPart = humanoid.SeatPart
		if not seatPart then return end

		local machine = seatPart:FindFirstAncestorWhichIsA("Model")
		if not machine then return end

		local templateName = machine:GetAttribute("TemplateName")
		if not templateName then return end

		self:_stopSeatWatch()
		self:_onLobbyMachineChosen(templateName)
	end)
end

function LakelandGameController:_stopSeatWatch()
	if self._seatedConn then
		self._seatedConn:Disconnect()
		self._seatedConn = nil
	end
end

function LakelandGameController:_onLobbyMachineChosen(templateName)
	print("[LakelandGameController] Player chose machine: " .. templateName)
	self._chosenTemplate = templateName

	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seatPart = humanoid and humanoid.SeatPart
	if seatPart then
		local machine = seatPart:FindFirstAncestorWhichIsA("Model")
		if machine then
			local cf = machine:GetPivot()
			local behind = cf * CFrame.new(0, 8, 14)
			local lookAt = cf.Position + cf.LookVector * 60
			local camera = Workspace.CurrentCamera
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.lookAt(behind.Position, lookAt)
		end
	end

	self:_showLobbyHyperjumpButton()
	self:_startUnseatWatch()
end

function LakelandGameController:_startUnseatWatch()
	self:_stopUnseatWatch()
	self._unseatConn = RunService.Heartbeat:Connect(function()
		local character = LocalPlayer.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		if humanoid.Sit then return end

		self:_stopUnseatWatch()
		self:_hideLobbyHyperjumpButton()
		self._chosenTemplate = nil

		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then camera.CameraSubject = hum end

		self:_startSeatWatch()
	end)
end

function LakelandGameController:_stopUnseatWatch()
	if self._unseatConn then
		self._unseatConn:Disconnect()
		self._unseatConn = nil
	end
end

function LakelandGameController:_showLobbyHyperjumpButton()
	self:_hideLobbyHyperjumpButton()

	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local sg = Instance.new("ScreenGui")
	sg.Name = "LobbyHyperjumpButton"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 65
	sg.Parent = playerGui
	self._lobbyHyperjumpGui = sg

	local btn = Instance.new("TextButton")
	btn.Name = "JumpBtn"
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.fromScale(0.5, 1.1)
	btn.Size = UDim2.fromScale(0.22, 0.055)
	btn.BackgroundColor3 = Color3.fromRGB(8, 14, 28)
	btn.BackgroundTransparency = 0.1
	btn.Text = "JUMP TO HYPERSPACE"
	btn.TextColor3 = Color3.fromRGB(0, 200, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ZIndex = 2
	btn.Parent = sg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.35, 0)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 200, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = btn

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = btn

	TweenService:Create(btn, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.92),
	}):Play()

	btn.MouseEnter:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.12), { Thickness = 3, Transparency = 0 }):Play()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.12), { Thickness = 2, Transparency = 0.15 }):Play()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 0.1 }):Play()
	end)

	btn.MouseButton1Click:Connect(function()
		if not self._chosenTemplate then return end
		self:_launchFromLobby()
	end)
end

function LakelandGameController:_hideLobbyHyperjumpButton()
	if self._lobbyHyperjumpGui then
		self._lobbyHyperjumpGui:Destroy()
		self._lobbyHyperjumpGui = nil
	end
end

function LakelandGameController:_launchFromLobby()
	local templateName = self._chosenTemplate
	if not templateName then return end
	self._chosenTemplate = nil

	self:_stopUnseatWatch()
	self:_hideLobbyHyperjumpButton()

	self._currentPlayerName = LocalPlayer.Name
	self._playerNameValue:set(LocalPlayer.Name)

	task.spawn(function()
		self:_stopBGM()
		self._dataService:DestroyLobbyMachines()

		self._dataService:SpawnSpecificMachine(templateName):expect()
		self:_freezeCharacter()
		self:_seatPlayer()

		self._healthBar.reset()
		self._bombUI.reset()
		self._dangerVignette.reset()
		self:_shuffleGameTracks()

		self._raceController:_setupDarkEnvironment()
		self:_flashTransition()
		self:_setState(STATES.PLAYING)
		self:_bindHealthWatch()
	end)
end

function LakelandGameController:_flashTransition()
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local sg = Instance.new("ScreenGui")
	sg.Name = "HyperEntryFlash"
	sg.DisplayOrder = 100
	sg.IgnoreGuiInset = true
	sg.Parent = playerGui

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 0
	flash.BorderSizePixel = 0
	flash.Parent = sg

	local tw = TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})
	tw:Play()
	tw.Completed:Once(function()
		sg:Destroy()
	end)
end

function LakelandGameController:_setState(newState)
	local old = self._gameState:get()
	if old == newState then return end

	self._gameState:set(newState)
	self.GameStateChanged:Fire(newState, old)
	print("[LakelandGameController] State: " .. old .. " -> " .. newState)
end


function LakelandGameController:_bindHealthWatch()
	if self._healthConn then
		self._healthConn:Disconnect()
		self._healthConn = nil
	end

	self._healthConn = self._raceController.HealthChanged:Connect(function(health)
		if health <= 0 and self._gameState:get() == STATES.PLAYING then
			self:_onGameEnd("DESTROYED")
		end
	end)
end

function LakelandGameController:_onGameEnd(endReason)
	if self._gameEnding or self._gameState:get() == STATES.GAME_OVER then return end
	self._gameEnding = true

	if self._healthConn then
		self._healthConn:Disconnect()
		self._healthConn = nil
	end
	if self._raceTimer and self._raceTimer.stop then
		self._raceTimer.stop()
	end

	local finalScore = self._distanceUI.getScore()
	local finalDistance = self._raceController:GetDistance()

	self._raceController:StopRace()
	self._dangerVignette.reset()

	if self._bgmCurrent then
		if self._bgmFadeTween then
			self._bgmFadeTween:Cancel()
			self._bgmFadeTween = nil
		end
		if self._bgmEndedConn then
			self._bgmEndedConn:Disconnect()
			self._bgmEndedConn = nil
		end
		local snd = self._bgmCurrent
		local fadeOut = TweenService:Create(snd, TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 })
		fadeOut:Play()
		fadeOut.Completed:Once(function()
			snd:Stop()
			snd:Destroy()
		end)
		self._bgmCurrent = nil
	end

	local function computeRank(sc)
		local entries = self._topScores:get()
		for i, entry in ipairs(entries) do
			if sc >= (entry.score or 0) then
				return i
			end
		end
		if #entries < MAX_LEADERBOARD_ENTRIES then
			return #entries + 1
		end
		return nil
	end

	task.spawn(function()
		if endReason == "DESTROYED" then
			local cam = self._raceController._cameraController
			local impactsFolder = SoundService:FindFirstChild("Impacts")
			local finalSound = impactsFolder and impactsFolder:FindFirstChild("OnImpactHazardFinal")
			local soundLen = (finalSound and finalSound:IsA("Sound")) and finalSound.TimeLength or 1.5
			local waitDuration = math.max(soundLen - 2.0, 0.3)

			local cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "DeathDesaturate"
			cc.Saturation = 0
			cc.Brightness = 0
			cc.Contrast = 0
			cc.Parent = Lighting
			self._deathCC = cc
			TweenService:Create(cc, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Saturation = -1,
				Brightness = -0.1,
				Contrast = 0.15,
			}):Play()

			if cam then
				cam:DeathZoom(waitDuration)
			end
			task.wait(waitDuration)
			if cam then
				cam:ResetZoom()
			end
		end

		self._wipe.wipe(function()
			if self._deathCC then
				self._deathCC:Destroy()
				self._deathCC = nil
			end
			self:_setState(STATES.GAME_OVER)

			self._endGameUI.show({
				score = finalScore,
				distance = finalDistance,
				name = self._currentPlayerName,
				reason = endReason,
				rank = computeRank(finalScore),
			})
		end)

		if finalScore > 0 and self._currentPlayerName and #self._currentPlayerName > 0 then
			local ok, err = pcall(function()
				self:SubmitScore(finalScore)
			end)
			if ok then
				local rank = computeRank(finalScore)
				self._endGameUI.setRank(rank)
				self._endGameUI.setStatus("SCORE SAVED!")
				print("[LakelandGameController] Submitted score: " .. finalScore)
			else
				self._endGameUI.setStatus("SAVE FAILED - RETRYING...")
				warn("[LakelandGameController] Score save failed: " .. tostring(err))
				task.wait(2)
				local retryOk = pcall(function()
					self:SubmitScore(finalScore)
				end)
				if retryOk then
					local rank = computeRank(finalScore)
					self._endGameUI.setRank(rank)
					self._endGameUI.setStatus("SCORE SAVED!")
				else
					self._endGameUI.setStatus("COULD NOT SAVE")
					warn("[LakelandGameController] Score retry also failed")
				end
			end
		else
			self._endGameUI.setStatus("NO SCORE")
		end

		task.wait(END_SCREEN_DURATION - 1)
		self._endGameUI.setStatus("RETURNING TO LOBBY...")
		task.wait(1)

		self._wipe.wipe(function()
			pcall(function()
				self:_cleanup()
			end)
			self._gameEnding = false
			self:_playMenuMusic()
			self:_enterLobby()
		end)
		print("[LakelandGameController] " .. endReason .. " — returning to lobby.")
	end)
end

function LakelandGameController:_cleanup()
	self:_stopSeatWatch()
	self:_stopUnseatWatch()
	self:_hideLobbyHyperjumpButton()
	self._chosenTemplate = nil

	local camCtrl = self._raceController and self._raceController._cameraController
	if camCtrl then
		camCtrl:_deactivate()
	end

	self:_unseatPlayer()
	self:_destroyMachine()
end

function LakelandGameController:_freezeCharacter()
	local character = LocalPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0
end

function LakelandGameController:_unfreezeCharacter()
	local character = LocalPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.WalkSpeed = 16
	humanoid.JumpHeight = 7.2
	humanoid.JumpPower = 50
end

----------------------------------------------------------------
-- Machine spawning (via server)
----------------------------------------------------------------

function LakelandGameController:_spawnMachine()
	local machineName = self._dataService:SpawnMachine():expect()
	print("[LakelandGameController] Server spawned machine: " .. tostring(machineName))
end

function LakelandGameController:_destroyMachine()
	self._dataService:DestroyMachine():expect()
end

function LakelandGameController:_seatPlayer()
	self._dataService:SeatPlayerInMachine():expect()
	print("[LakelandGameController] Requested server to seat player")
end

function LakelandGameController:_unseatPlayer()
	self._dataService:UnseatPlayer():expect()
end

----------------------------------------------------------------
-- Server data
----------------------------------------------------------------

function LakelandGameController:_loadFromServer()
	local profiles = self._dataService:GetProfiles():expect()

	if type(profiles) == "table" then
		local names = {}
		for _, profile in ipairs(profiles) do
			if type(profile) == "table" and profile.name then
				table.insert(names, profile.name)
			end
		end
		self._previousNames:set(names)
		print("[LakelandGameController] Loaded " .. #names .. " profiles from server")
	end

	self:_refreshLeaderboard()
end

function LakelandGameController:_refreshLeaderboard()
	local leaderboard = self._dataService:GetLeaderboard():expect()

	local entries = {}
	if type(leaderboard) == "table" then
		for i, entry in ipairs(leaderboard) do
			if i > MAX_LEADERBOARD_ENTRIES then break end
			if type(entry) == "table" then
				table.insert(entries, { rank = i, name = entry.name or "---", score = entry.score or 0 })
			end
		end
		print("[LakelandGameController] Loaded " .. #entries .. " leaderboard entries from server")
	end

	while #entries < MAX_LEADERBOARD_ENTRIES do
		table.insert(entries, { rank = #entries + 1, name = "---", score = 0 })
	end
	self._topScores:set(entries)

	self:_rebuildNameList(entries)
end

function LakelandGameController:_rebuildNameList(entries)
	local scoreMap = {}
	for _, entry in ipairs(entries) do
		if entry.name and entry.name ~= "---" then
			scoreMap[entry.name] = entry.score or 0
		end
	end

	local nameSet = {}
	local allNames = {}

	for _, entry in ipairs(entries) do
		local name = entry.name
		if name and name ~= "---" and not nameSet[name] then
			nameSet[name] = true
			table.insert(allNames, name)
		end
	end

	local profiles = self._previousNames:get()
	for _, name in ipairs(profiles) do
		if not nameSet[name] then
			nameSet[name] = true
			table.insert(allNames, name)
		end
	end

	table.sort(allNames, function(a, b)
		local aIsLast = (a == self._currentPlayerName)
		local bIsLast = (b == self._currentPlayerName)
		if aIsLast ~= bIsLast then
			return aIsLast
		end
		local aScore = scoreMap[a] or 0
		local bScore = scoreMap[b] or 0
		if aScore ~= bScore then
			return aScore > bScore
		end
		return a < b
	end)

	self._previousNames:set(allNames)
end

----------------------------------------------------------------
-- Names
----------------------------------------------------------------

function LakelandGameController:_addPreviousName(name)
	local names = TableUtil.Copy(self._previousNames:get())
	for _, existing in names do
		if existing == name then
			return
		end
	end
	table.insert(names, name)
	self._previousNames:set(names)
end

function LakelandGameController:GetCurrentPlayerName()
	return self._currentPlayerName
end

----------------------------------------------------------------
-- Scores
----------------------------------------------------------------

function LakelandGameController:SubmitScore(score)
	self._dataService:SubmitScore(self._currentPlayerName, score):expect()
	self:_refreshLeaderboard()
end

----------------------------------------------------------------
-- Background Music
----------------------------------------------------------------

function LakelandGameController:_shuffleGameTracks()
	self._gameTrackOrder = {}
	for i, id in ipairs(GAME_TRACK_IDS) do
		self._gameTrackOrder[i] = id
	end
	for i = #self._gameTrackOrder, 2, -1 do
		local j = math.random(1, i)
		self._gameTrackOrder[i], self._gameTrackOrder[j] = self._gameTrackOrder[j], self._gameTrackOrder[i]
	end
	self._gameTrackIndex = 0
end

function LakelandGameController:_nextGameTrack()
	if #self._gameTrackOrder == 0 then
		self:_shuffleGameTracks()
	end
	self._gameTrackIndex = self._gameTrackIndex + 1
	if self._gameTrackIndex > #self._gameTrackOrder then
		self:_shuffleGameTracks()
		self._gameTrackIndex = 1
	end
	return self._gameTrackOrder[self._gameTrackIndex]
end

function LakelandGameController:_playBGM(soundId, looping)
	if self._bgmEndedConn then
		self._bgmEndedConn:Disconnect()
		self._bgmEndedConn = nil
	end
	if self._bgmFadeTween then
		self._bgmFadeTween:Cancel()
		self._bgmFadeTween = nil
	end

	local old = self._bgmCurrent
	if old then
		local fadeOut = TweenService:Create(old, TweenInfo.new(BGM_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 })
		fadeOut:Play()
		fadeOut.Completed:Once(function()
			old:Stop()
			old:Destroy()
		end)
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0
	sound.Looped = looping or false
	sound.Parent = SoundService
	self._bgmCurrent = sound
	sound:Play()

	local fadeIn = TweenService:Create(sound, TweenInfo.new(BGM_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = BGM_VOLUME })
	fadeIn:Play()
	self._bgmFadeTween = fadeIn

	if not looping then
		self._bgmEndedConn = sound.Ended:Once(function()
			if self._bgmCurrent == sound then
				self:_playNextGameTrack()
			end
		end)
	end
end

function LakelandGameController:_playMenuMusic()
	self:_playBGM(MENU_TRACK_ID, true)
end

function LakelandGameController:_playNextGameTrack()
	local id = self:_nextGameTrack()
	self:_playBGM(id, false)
end

function LakelandGameController:_stopBGM()
	if self._bgmEndedConn then
		self._bgmEndedConn:Disconnect()
		self._bgmEndedConn = nil
	end
	if self._bgmFadeTween then
		self._bgmFadeTween:Cancel()
		self._bgmFadeTween = nil
	end
	if self._bgmCurrent then
		local snd = self._bgmCurrent
		local fadeOut = TweenService:Create(snd, TweenInfo.new(BGM_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 })
		fadeOut:Play()
		fadeOut.Completed:Once(function()
			snd:Stop()
			snd:Destroy()
		end)
		self._bgmCurrent = nil
	end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------

function LakelandGameController:GetState()
	return self._gameState:get()
end

function LakelandGameController:GetStateValue()
	return self._gameState
end

function LakelandGameController:GetBeatIntensity()
	return self._beatIntensity
end

return LakelandGameController
