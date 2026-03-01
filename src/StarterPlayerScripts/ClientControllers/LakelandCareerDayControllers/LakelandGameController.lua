local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Signal = require(Packages.Signal)

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)
local Value = Fusion.Value
local TableUtil = require(Packages.TableUtil)

local ControllersFolder = StarterPlayer.StarterPlayerScripts.Source.ClientControllers.LakelandCareerDayControllers
local LakelandMenuUI = require(ControllersFolder.LakelandMenuUI)
local LakelandNameEntryUI = require(ControllersFolder.LakelandNameEntryUI)
local LakelandCountdownUI = require(ControllersFolder.LakelandCountdownUI)
local LakelandRaceTimerUI = require(ControllersFolder.LakelandRaceTimerUI)
local LakelandHealthBarUI = require(ControllersFolder.LakelandHealthBarUI)
local LakelandDistanceUI = require(ControllersFolder.LakelandDistanceUI)
local LakelandSpeedUI = require(ControllersFolder.LakelandSpeedUI)
local LakelandEndGameUI = require(ControllersFolder.LakelandEndGameUI)

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
	_healthConn = nil,
})

local MAX_LEADERBOARD_ENTRIES = 10

function LakelandGameController:KnitInit()
	self._trove = Trove.new()
	self._gameState = Value(STATES.MENU)
	self._topScores = Value({})
	self._previousNames = Value({})
	self._currentPlayerName = ""
end

function LakelandGameController:KnitStart()
	self._dataService = Knit.GetService("LakelandDataService")
	self._raceController = Knit.GetController("LakelandRaceController")

	self:_loadFromServer()
	self:_createUI()

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

	self._distanceUI = LakelandDistanceUI.new(playerGui, self._gameState)
	self._trove:Add(function()
		self._distanceUI.destroy()
	end)

	self._speedUI = LakelandSpeedUI.new(playerGui, self._gameState)
	self._trove:Add(function()
		self._speedUI.destroy()
	end)

	self._endGameUI = LakelandEndGameUI.new(playerGui, self._gameState)
	self._trove:Add(function()
		self._endGameUI.destroy()
	end)
end

function LakelandGameController:_setState(newState)
	local old = self._gameState:get()
	if old == newState then return end

	self._gameState:set(newState)
	self.GameStateChanged:Fire(newState, old)
	print("[LakelandGameController] State: " .. old .. " -> " .. newState)
end

function LakelandGameController:_onPlayPressed()
	self._nameEntry.reset()
	self:_setState(STATES.NAME_ENTRY)
end

function LakelandGameController:_onNameConfirmed(name)
	self._currentPlayerName = name

	self._dataService:RegisterProfile(name):expect()

	self:_addPreviousName(name)
	print("[LakelandGameController] Player name: " .. name)

	self:_spawnMachine()
	self:_loadCharacter()
	self:_seatPlayer()

	self._healthBar.reset()
	self:_setState(STATES.COUNTDOWN)
	self._countdown.start()
end

function LakelandGameController:_onCountdownDone()
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
	if self._gameState:get() == STATES.GAME_OVER then return end

	if self._healthConn then
		self._healthConn:Disconnect()
		self._healthConn = nil
	end

	local finalScore = self._distanceUI.getScore()
	local finalDistance = self._raceController:GetDistance()

	self:_setState(STATES.GAME_OVER)

	self._endGameUI.show({
		score = finalScore,
		distance = finalDistance,
		name = self._currentPlayerName,
		reason = endReason,
	})

	task.spawn(function()
		if finalScore > 0 and self._currentPlayerName and #self._currentPlayerName > 0 then
			local ok, err = pcall(function()
				self:SubmitScore(finalScore)
			end)
			if ok then
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

		pcall(function()
			self:_cleanup()
		end)
		self:_setState(STATES.MENU)
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
-- Public API
----------------------------------------------------------------

function LakelandGameController:GetState()
	return self._gameState:get()
end

function LakelandGameController:GetStateValue()
	return self._gameState
end

return LakelandGameController
