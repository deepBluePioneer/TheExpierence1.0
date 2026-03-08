local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local CutsceneService = require(CustomPackages.CutsceneService.CutsceneService)

local ControllersFolder = StarterPlayer.StarterPlayerScripts.Source.ClientControllers.LakelandCareerDayControllers
local LakelandMenuUI = require(ControllersFolder.LakelandMenuUI)
local LakelandNameEntryUI = require(ControllersFolder.LakelandNameEntryUI)
local LakelandCountdownUI = require(ControllersFolder.LakelandCountdownUI)
local LakelandRaceTimerUI = require(ControllersFolder.LakelandRaceTimerUI)
local LakelandHealthBarUI = require(ControllersFolder.LakelandHealthBarUI)
local LakelandDistanceUI = require(ControllersFolder.LakelandDistanceUI)
local LakelandEndGameUI = require(ControllersFolder.LakelandEndGameUI)
local LakelandScoreBarUI = require(ControllersFolder.LakelandScoreBarUI)
local LakelandBombUI = require(ControllersFolder.LakelandBombUI)
local LakelandWipeTransition = require(ControllersFolder.LakelandWipeTransition)

local RACE_DURATION = 120
local END_SCREEN_DURATION = 5

local LocalPlayer = Players.LocalPlayer

local STATES = {
	MENU = "MENU",
	NAME_ENTRY = "NAME_ENTRY",
	COUNTDOWN = "COUNTDOWN",
	PLAYING = "PLAYING",
	GAME_OVER = "GAME_OVER",
}

---------------------------------------------------------------------------
-- Background Music
---------------------------------------------------------------------------
local BGM_FADE_TIME = 1.5
local BGM_VOLUME = 0.35

local MENU_TRACK_ID = "rbxassetid://7028518546"  -- Protostar - New Horizons

local GAME_TRACK_IDS = {
	"rbxassetid://7023887630",  -- Hyper Potions & Nokae - Expedition
	"rbxassetid://5409360995",  -- Dion Timmer - Shiawase
	"rbxassetid://5410082879",  -- Noisestorm - Escape
	"rbxassetid://5410084802",  -- Pixel Terror - Chroma
	"rbxassetid://5410085763",  -- Tokyo Machine - PLAY
}

local LakelandGameController = Knit.CreateController({
	Name = "LakelandGameController",

	GameStateChanged = Signal.new(),

	_trove = nil,
	_gameState = nil,
	_topScores = nil,
	_previousNames = nil,
	_currentPlayerName = nil,
	_menuCleanup = nil,
	_nameEntry = nil,
	_countdown = nil,
	_raceTimer = nil,
	_wipe = nil,
	_healthConn = nil,
	_introCutscene = nil,
	_gameEnding = false,

	_bgmCurrent = nil,
	_bgmFadeTween = nil,
	_gameTrackOrder = {},
	_gameTrackIndex = 0,
	_bgmEndedConn = nil,
})

local MAX_LEADERBOARD_ENTRIES = 10

function LakelandGameController:KnitInit()
	self._trove = Trove.new()
	self._gameState = Value(STATES.MENU)
	self._topScores = Value({})
	self._previousNames = Value({})
	self._currentPlayerName = ""
	self._playerNameValue = Value("")
end

function LakelandGameController:KnitStart()
	self._dataService = Knit.GetService("LakelandDataService")
	self._raceController = Knit.GetController("LakelandRaceController")

	self:_loadFromServer()
	self:_createUI()

	local character = LocalPlayer.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = CFrame.new(0, -500, 0)
		end
	end

	self:_startIntroCutscene()
	self:_playMenuMusic()

	print("[LakelandGameController] Ready - showing menu")
end

function LakelandGameController:_loadCharacter()
	self._dataService:LoadCharacter():expect()

	local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	humanoid:WaitForChild("Animator")

	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0

	return character, humanoid
end

function LakelandGameController:_createUI()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")

	self._menuCleanup = LakelandMenuUI.new(playerGui, self._gameState, self._topScores, function()
		self:_onPlayPressed()
	end)
	self._trove:Add(self._menuCleanup)

	self._nameEntry = LakelandNameEntryUI.new(playerGui, self._gameState, self._previousNames, function(name)
		self:_onNameConfirmed(name)
	end)
	self._trove:Add(function()
		self._nameEntry.destroy()
	end)

	self._countdown = LakelandCountdownUI.new(playerGui, self._gameState, function()
		self:_onCountdownDone()
	end)
	self._trove:Add(function()
		self._countdown.destroy()
	end)

	self._raceTimer = LakelandRaceTimerUI.new(playerGui, self._gameState, RACE_DURATION, function()
		self:_onGameEnd("TIME UP")
	end)
	self._trove:Add(function()
		self._raceTimer.destroy()
	end)

	self._healthBar = LakelandHealthBarUI.new(playerGui, self._gameState)
	self._trove:Add(function()
		self._healthBar.destroy()
	end)

	self._distanceUI = LakelandDistanceUI.new(playerGui, self._gameState, self._playerNameValue)
	self._trove:Add(function()
		self._distanceUI.destroy()
	end)

	self._endGameUI = LakelandEndGameUI.new(playerGui, self._gameState)
	self._trove:Add(function()
		self._endGameUI.destroy()
	end)

	self._scoreBar = LakelandScoreBarUI.new(playerGui, self._gameState, self._topScores, self._playerNameValue)
	self._trove:Add(function()
		self._scoreBar.destroy()
	end)

	self._bombUI = LakelandBombUI.new(playerGui, self._gameState)
	self._trove:Add(function()
		self._bombUI.destroy()
	end)

	self._wipe = LakelandWipeTransition.new(playerGui)
	self._trove:Add(function()
		self._wipe.destroy()
	end)

	self._trove:Add(function()
		self:_stopIntroCutscene()
	end)

	self._trove:Add(function()
		self:_stopBGM()
	end)
end

function LakelandGameController:_startIntroCutscene()
	local folder = Workspace:FindFirstChild("IntroCutscene")
	if not folder then
		warn("[LakelandGameController] IntroCutscene folder not found in Workspace")
		return
	end

	if self._introCutscene then
		pcall(function() self._introCutscene:Cancel() end)
		pcall(function() self._introCutscene:Destroy() end)
		self._introCutscene = nil
	end

	local cutscene = CutsceneService:Create(folder, 12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	self._introCutscene = cutscene

	cutscene.Next = cutscene
	cutscene:Play()
end

function LakelandGameController:_stopIntroCutscene()
	if not self._introCutscene then return end

	pcall(function() self._introCutscene:Cancel() end)
	pcall(function() self._introCutscene:Destroy() end)
	self._introCutscene = nil
end

function LakelandGameController:_setState(newState)
	local old = self._gameState:get()
	if old == newState then return end

	self._gameState:set(newState)
	self.GameStateChanged:Fire(newState, old)
	print("[LakelandGameController] State: " .. old .. " -> " .. newState)
end

function LakelandGameController:_onPlayPressed()
	if self._wipe.isWiping() then return end
	task.spawn(function()
		self._wipe.wipe(function()
			self._nameEntry.reset()
			self:_setState(STATES.NAME_ENTRY)
		end)
	end)
end

function LakelandGameController:_onNameConfirmed(name)
	if self._wipe.isWiping() then return end
	self._currentPlayerName = name
	self._playerNameValue:set(name)

	self._dataService:RegisterProfile(name):expect()
	self:_addPreviousName(name)
	print("[LakelandGameController] Player name: " .. name)

	task.spawn(function()
		self._wipe.wipe(function()
			self:_stopIntroCutscene()

			self:_spawnMachine()
			self:_loadCharacter()
			self:_seatPlayer()

			self._healthBar.reset()
			self._scoreBar.reset()
			self._bombUI.reset()
			self:_shuffleGameTracks()
			self:_playNextGameTrack()
			self:_setState(STATES.COUNTDOWN)
			self._countdown.start()
		end)
	end)
end

function LakelandGameController:_onCountdownDone()
	-- Edge case: countdown callback must only run once; avoid double-start if already PLAYING
	if self._gameState:get() == STATES.PLAYING then
		return
	end
	self:_setState(STATES.PLAYING)
	self._raceTimer.start()

	self:_bindHealthWatch()

	print("[LakelandGameController] Player has control! Race timer started.")
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
			if cam then
				cam:DeathZoom(waitDuration)
			end
			task.wait(waitDuration)
			if cam then
				cam:ResetZoom()
			end
		end

		self._wipe.wipe(function()
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
		self._endGameUI.setStatus("RETURNING TO MENU...")
		task.wait(1)

		self._wipe.wipe(function()
			pcall(function()
				self:_cleanup()
			end)
			self._gameEnding = false
			self:_playMenuMusic()
			self:_setState(STATES.MENU)
			self:_startIntroCutscene()
		end)
		print("[LakelandGameController] " .. endReason .. " — returning to menu.")
	end)
end

function LakelandGameController:_cleanup()
	self:_unseatPlayer()
	self:_destroyMachine()
	self._dataService:DestroyCharacter():expect()
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

return LakelandGameController
