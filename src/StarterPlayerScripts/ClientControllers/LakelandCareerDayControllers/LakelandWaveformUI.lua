local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local BAR_COUNT = 150
local BAR_GAP = 1
local PANEL_HEIGHT = 44
local BAR_MIN_H = 0.08
local BAR_MAX_H = 0.9
local PLAYHEAD_WIDTH = 2
local DISPLAY_ORDER = 50
local SCAN_SPEED = 16

local PLAYED_COLOR = Color3.fromRGB(50, 160, 255)
local UNPLAYED_COLOR = Color3.fromRGB(40, 40, 50)
local UNSAMPLED_COLOR = Color3.fromRGB(25, 25, 30)
local PLAYHEAD_COLOR = Color3.fromRGB(255, 255, 255)
local BG_COLOR = Color3.fromRGB(8, 8, 14)

local waveformCache = {}

local LakelandWaveformUI = {}

local function formatTime(seconds)
	if not seconds or seconds ~= seconds then return "0:00" end
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

function LakelandWaveformUI.new(playerGui)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LakelandWaveform"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = DISPLAY_ORDER
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "WaveformPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -8)
	panel.Size = UDim2.new(0.75, 0, 0, PANEL_HEIGHT)
	panel.BackgroundColor3 = BG_COLOR
	panel.BackgroundTransparency = 0.3
	panel.BorderSizePixel = 0
	panel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 6)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(40, 50, 70)
	panelStroke.Thickness = 1
	panelStroke.Transparency = 0.5
	panelStroke.Parent = panel

	local trackLabel = Instance.new("TextLabel")
	trackLabel.Name = "TrackName"
	trackLabel.AnchorPoint = Vector2.new(0, 0.5)
	trackLabel.Position = UDim2.new(0, 8, 0.5, 0)
	trackLabel.Size = UDim2.new(0.2, -8, 1, -4)
	trackLabel.BackgroundTransparency = 1
	trackLabel.Font = Enum.Font.GothamBold
	trackLabel.TextColor3 = Color3.fromRGB(200, 210, 230)
	trackLabel.TextTransparency = 0.15
	trackLabel.TextScaled = true
	trackLabel.TextXAlignment = Enum.TextXAlignment.Left
	trackLabel.TextTruncate = Enum.TextTruncate.AtEnd
	trackLabel.Text = ""
	trackLabel.Parent = panel
	local trackTSC = Instance.new("UITextSizeConstraint")
	trackTSC.MaxTextSize = 13
	trackTSC.MinTextSize = 8
	trackTSC.Parent = trackLabel

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "TimeLabel"
	timeLabel.AnchorPoint = Vector2.new(1, 0.5)
	timeLabel.Position = UDim2.new(1, -8, 0.5, 0)
	timeLabel.Size = UDim2.new(0.12, -8, 1, -4)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Font = Enum.Font.GothamMedium
	timeLabel.TextColor3 = Color3.fromRGB(160, 170, 190)
	timeLabel.TextTransparency = 0.2
	timeLabel.TextScaled = true
	timeLabel.TextXAlignment = Enum.TextXAlignment.Right
	timeLabel.Text = "0:00 / 0:00"
	timeLabel.Parent = panel
	local timeTSC = Instance.new("UITextSizeConstraint")
	timeTSC.MaxTextSize = 12
	timeTSC.MinTextSize = 7
	timeTSC.Parent = timeLabel

	local barContainer = Instance.new("Frame")
	barContainer.Name = "BarContainer"
	barContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	barContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
	barContainer.Size = UDim2.new(0.64, 0, 0.85, 0)
	barContainer.BackgroundTransparency = 1
	barContainer.ClipsDescendants = true
	barContainer.Parent = panel

	local barsTop = {}
	local barsBot = {}
	local barWidth = 1 / BAR_COUNT
	for i = 1, BAR_COUNT do
		local top = Instance.new("Frame")
		top.Name = "BarTop" .. i
		top.AnchorPoint = Vector2.new(0, 1)
		top.Position = UDim2.new((i - 1) * barWidth, 0, 0.5, 0)
		top.Size = UDim2.new(barWidth, -BAR_GAP, BAR_MIN_H * 0.5, 0)
		top.BackgroundColor3 = UNSAMPLED_COLOR
		top.BorderSizePixel = 0
		top.Parent = barContainer
		local cTop = Instance.new("UICorner")
		cTop.CornerRadius = UDim.new(0, 1)
		cTop.Parent = top
		barsTop[i] = top

		local bot = Instance.new("Frame")
		bot.Name = "BarBot" .. i
		bot.AnchorPoint = Vector2.new(0, 0)
		bot.Position = UDim2.new((i - 1) * barWidth, 0, 0.5, 0)
		bot.Size = UDim2.new(barWidth, -BAR_GAP, BAR_MIN_H * 0.5, 0)
		bot.BackgroundColor3 = UNSAMPLED_COLOR
		bot.BorderSizePixel = 0
		bot.Parent = barContainer
		local cBot = Instance.new("UICorner")
		cBot.CornerRadius = UDim.new(0, 1)
		cBot.Parent = bot
		barsBot[i] = bot
	end

	local playhead = Instance.new("Frame")
	playhead.Name = "Playhead"
	playhead.AnchorPoint = Vector2.new(0.5, 0.5)
	playhead.Position = UDim2.new(0, 0, 0.5, 0)
	playhead.Size = UDim2.new(0, PLAYHEAD_WIDTH, 1.1, 0)
	playhead.BackgroundColor3 = PLAYHEAD_COLOR
	playhead.BackgroundTransparency = 0.15
	playhead.BorderSizePixel = 0
	playhead.ZIndex = 2
	playhead.Parent = barContainer
	local phCorner = Instance.new("UICorner")
	phCorner.CornerRadius = UDim.new(0, 1)
	phCorner.Parent = playhead

	local bins = {}
	for i = 1, BAR_COUNT do
		bins[i] = 0
	end
	local sampled = {}
	local currentSound = nil
	local currentSoundId = nil
	local heartbeatConn = nil
	local peakMax = 0.01
	local scanQueue = {}
	local scanning = false

	local function applyBins()
		for i = 1, BAR_COUNT do
			local val = bins[i]
			local norm = math.clamp(val / peakMax, 0, 1)
			local halfH = (BAR_MIN_H + norm * (BAR_MAX_H - BAR_MIN_H)) * 0.5
			barsTop[i].Size = UDim2.new(barWidth, -BAR_GAP, halfH, 0)
			barsBot[i].Size = UDim2.new(barWidth, -BAR_GAP, halfH, 0)
			local col = sampled[i] and UNPLAYED_COLOR or UNSAMPLED_COLOR
			barsTop[i].BackgroundColor3 = col
			barsBot[i].BackgroundColor3 = col
		end
	end

	local function loadFromCache(soundId)
		local cached = waveformCache[soundId]
		if not cached then return false end
		for i = 1, BAR_COUNT do
			bins[i] = cached.bins[i] or 0
			sampled[i] = true
		end
		peakMax = cached.peakMax or 0.01
		applyBins()
		return true
	end

	local function scanNextTrack()
		if #scanQueue == 0 then
			scanning = false
			return
		end
		scanning = true
		local soundId = table.remove(scanQueue, 1)

		if waveformCache[soundId] then
			task.defer(scanNextTrack)
			return
		end

		local probe = Instance.new("Sound")
		probe.SoundId = soundId
		probe.Volume = 0
		probe.PlaybackSpeed = SCAN_SPEED
		probe.Looped = false
		probe.Parent = SoundService
		probe:Play()

		local scanBins = {}
		local scanPeak = 0.01
		for i = 1, BAR_COUNT do scanBins[i] = 0 end

		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not probe or not probe.Parent or not probe.IsPlaying then
				if conn then conn:Disconnect(); conn = nil end
				if probe and probe.Parent then
					probe:Stop()
					probe:Destroy()
				end
				waveformCache[soundId] = { bins = scanBins, peakMax = scanPeak }
				print("[Waveform] Preloaded: " .. soundId)
				task.defer(scanNextTrack)
				return
			end

			local len = probe.TimeLength
			if len <= 0 then return end
			local pos = probe.TimePosition
			local frac = math.clamp(pos / len, 0, 1)
			local idx = math.clamp(math.floor(frac * BAR_COUNT) + 1, 1, BAR_COUNT)

			local loud = probe.PlaybackLoudness / 500
			loud = math.clamp(loud, 0, 1)

			if loud > scanBins[idx] then
				scanBins[idx] = loud
			end
			if loud > scanPeak then scanPeak = loud end
		end)

		probe.Ended:Once(function()
			if conn then conn:Disconnect(); conn = nil end
			if probe and probe.Parent then
				probe:Destroy()
			end
			waveformCache[soundId] = { bins = scanBins, peakMax = scanPeak }
			print("[Waveform] Preloaded: " .. soundId)
			task.defer(scanNextTrack)
		end)
	end

	local api = {}

	function api.preloadTracks(soundIds)
		for _, id in ipairs(soundIds) do
			if not waveformCache[id] then
				table.insert(scanQueue, id)
			end
		end
		if not scanning then
			task.defer(scanNextTrack)
		end
	end

	function api.startTrack(sound, trackName)
		api.stopTrack()
		currentSound = sound
		currentSoundId = sound.SoundId

		local hadCache = loadFromCache(currentSoundId)
		if not hadCache then
			for i = 1, BAR_COUNT do
				bins[i] = 0
				sampled[i] = false
			end
			peakMax = 0.01
			applyBins()
		end

		playhead.Position = UDim2.new(0, 0, 0.5, 0)
		trackLabel.Text = trackName or ""
		timeLabel.Text = "0:00 / 0:00"
		screenGui.Enabled = true

		heartbeatConn = RunService.Heartbeat:Connect(function()
			if not currentSound or not currentSound.Parent then return end
			local len = currentSound.TimeLength
			if len <= 0 then return end
			local pos = currentSound.TimePosition
			local frac = math.clamp(pos / len, 0, 1)
			local binIdx = math.clamp(math.floor(frac * BAR_COUNT) + 1, 1, BAR_COUNT)

			local loud = currentSound.PlaybackLoudness / 500
			loud = math.clamp(loud, 0, 1)

			if loud > bins[binIdx] then
				bins[binIdx] = loud
			end
			sampled[binIdx] = true
			if loud > peakMax then peakMax = loud end

			playhead.Position = UDim2.new(frac, 0, 0.5, 0)
			timeLabel.Text = formatTime(pos) .. " / " .. formatTime(len)

			for i = 1, BAR_COUNT do
				local val = bins[i]
				local norm = math.clamp(val / peakMax, 0, 1)
				local halfH = (BAR_MIN_H + norm * (BAR_MAX_H - BAR_MIN_H)) * 0.5
				barsTop[i].Size = UDim2.new(barWidth, -BAR_GAP, halfH, 0)
				barsBot[i].Size = UDim2.new(barWidth, -BAR_GAP, halfH, 0)

				local col
				if i <= binIdx then
					col = PLAYED_COLOR
				elseif sampled[i] then
					col = UNPLAYED_COLOR
				else
					col = UNSAMPLED_COLOR
				end
				barsTop[i].BackgroundColor3 = col
				barsBot[i].BackgroundColor3 = col
			end
		end)
	end

	function api.stopTrack()
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
		if currentSound and currentSoundId then
			local cacheEntry = waveformCache[currentSoundId]
			if not cacheEntry then
				waveformCache[currentSoundId] = { bins = {}, peakMax = peakMax }
				for i = 1, BAR_COUNT do
					waveformCache[currentSoundId].bins[i] = bins[i]
				end
			end
		end
		currentSound = nil
		currentSoundId = nil
	end

	function api.show()
		screenGui.Enabled = true
		panel.BackgroundTransparency = 0.3
		for i = 1, BAR_COUNT do
			barsTop[i].BackgroundTransparency = 0
			barsBot[i].BackgroundTransparency = 0
		end
		playhead.BackgroundTransparency = 0.15
		trackLabel.TextTransparency = 0.15
		timeLabel.TextTransparency = 0.2
	end

	function api.hide()
		api.stopTrack()
		screenGui.Enabled = false
	end

	function api.destroy()
		api.stopTrack()
		scanQueue = {}
		screenGui:Destroy()
	end

	return api
end

return LakelandWaveformUI
