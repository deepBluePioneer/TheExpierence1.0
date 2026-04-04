local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Fusion = require(CustomPackages.FusionRoot.Fusion)
local ReplicaController = require(CustomPackages.Replica.ReplicaController)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local LocalPlayer = Players.LocalPlayer

local ACCENT = Color3.fromRGB(60, 180, 255)
local BG_DARK = Color3.fromRGB(12, 14, 20)
local BG_CARD = Color3.fromRGB(20, 22, 30)
local TEXT_DIM = Color3.fromRGB(140, 140, 160)
local TEXT_BRIGHT = Color3.fromRGB(240, 240, 255)
local GOLD = Color3.fromRGB(255, 200, 60)
local RED = Color3.fromRGB(255, 80, 80)
local GREEN = Color3.fromRGB(80, 255, 120)

local GraviBowMatchController = Knit.CreateController({
	Name = "GraviBowMatchController",
	_trove = nil,

	Phase = "HUB_WAITING",
})

function GraviBowMatchController:KnitInit()
	self._trove = Trove.new()
	self._phase = Value("HUB_WAITING")
	self._timeRemaining = Value(0)
	self._scoreListFrame = nil
	self._lastScores = {}
end

function GraviBowMatchController:KnitStart()
	ReplicaController.RequestData()

	ReplicaController.ReplicaOfClassCreated("GraviBowMatchState", function(replica)
		self._replica = replica

		local data = replica.Data
		self._phase:set(data.phase or "HUB_WAITING")
		self._timeRemaining:set(data.timeRemaining or 0)
		self.Phase = data.phase or "HUB_WAITING"

		replica:ListenToChange({"phase"}, function(newVal)
			self._phase:set(newVal)
			self.Phase = newVal
			if newVal == "RESULTS" or newVal == "GAME_OVER" then
				self:_refreshScoreList(replica.Data.scores or {})
			end
		end)

		replica:ListenToChange({"timeRemaining"}, function(newVal)
			self._timeRemaining:set(newVal)
		end)

		replica:ListenToRaw(function()
			local p = self.Phase
			if p == "RESULTS" or p == "GAME_OVER" or p == "GAME_ACTIVE" then
				self:_refreshScoreList(replica.Data.scores or {})
			end
		end)
	end)

	self:_createUI()
end

function GraviBowMatchController:_refreshScoreList(scores)
	if not self._scoreListFrame then return end

	local list = {}
	for userId, data in pairs(scores) do
		if type(data) == "table" then
			table.insert(list, {
				userId = userId,
				name = data.name or "???",
				kills = data.kills or 0,
				deaths = data.deaths or 0,
				hits = data.hits or 0,
			})
		end
	end
	table.sort(list, function(a, b)
		if a.kills ~= b.kills then return a.kills > b.kills end
		return a.deaths < b.deaths
	end)

	for _, child in ipairs(self._scoreListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for rank, entry in ipairs(list) do
		local isLocal = entry.userId == tostring(LocalPlayer.UserId)
		local rowBg = isLocal and Color3.fromRGB(30, 40, 60) or BG_CARD

		local row = Instance.new("Frame")
		row.Name = "Row_" .. rank
		row.Size = UDim2.new(1, 0, 0, 36)
		row.BackgroundColor3 = rowBg
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.LayoutOrder = rank

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = row

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = row

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Name = "Rank"
		rankLabel.Size = UDim2.new(0, 30, 1, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Text = "#" .. rank
		rankLabel.TextColor3 = rank == 1 and GOLD or TEXT_DIM
		rankLabel.TextSize = 16
		rankLabel.Font = Enum.Font.GothamBold
		rankLabel.TextXAlignment = Enum.TextXAlignment.Left
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.Size = UDim2.new(0.4, -40, 1, 0)
		nameLabel.Position = UDim2.new(0, 36, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = entry.name
		nameLabel.TextColor3 = isLocal and ACCENT or TEXT_BRIGHT
		nameLabel.TextSize = 16
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = row

		local killsLabel = Instance.new("TextLabel")
		killsLabel.Name = "Kills"
		killsLabel.AnchorPoint = Vector2.new(1, 0)
		killsLabel.Size = UDim2.new(0, 60, 1, 0)
		killsLabel.Position = UDim2.new(0.7, 0, 0, 0)
		killsLabel.BackgroundTransparency = 1
		killsLabel.Text = tostring(entry.kills)
		killsLabel.TextColor3 = GREEN
		killsLabel.TextSize = 16
		killsLabel.Font = Enum.Font.GothamBold
		killsLabel.TextXAlignment = Enum.TextXAlignment.Center
		killsLabel.Parent = row

		local deathsLabel = Instance.new("TextLabel")
		deathsLabel.Name = "Deaths"
		deathsLabel.AnchorPoint = Vector2.new(1, 0)
		deathsLabel.Size = UDim2.new(0, 60, 1, 0)
		deathsLabel.Position = UDim2.new(0.85, 0, 0, 0)
		deathsLabel.BackgroundTransparency = 1
		deathsLabel.Text = tostring(entry.deaths)
		deathsLabel.TextColor3 = RED
		deathsLabel.TextSize = 16
		deathsLabel.Font = Enum.Font.GothamBold
		deathsLabel.TextXAlignment = Enum.TextXAlignment.Center
		deathsLabel.Parent = row

		local hitsLabel = Instance.new("TextLabel")
		hitsLabel.Name = "Hits"
		hitsLabel.AnchorPoint = Vector2.new(1, 0)
		hitsLabel.Size = UDim2.new(0, 60, 1, 0)
		hitsLabel.Position = UDim2.new(1, 0, 0, 0)
		hitsLabel.BackgroundTransparency = 1
		hitsLabel.Text = tostring(entry.hits)
		hitsLabel.TextColor3 = ACCENT
		hitsLabel.TextSize = 16
		hitsLabel.Font = Enum.Font.GothamBold
		hitsLabel.TextXAlignment = Enum.TextXAlignment.Center
		hitsLabel.Parent = row

		row.Parent = self._scoreListFrame
	end
end

function GraviBowMatchController:_createUI()
	local phase = self._phase
	local timeRemaining = self._timeRemaining

	local showTimer = Computed(function()
		local p = phase:get()
		return p == "HUB_COUNTDOWN" or p == "GAME_ACTIVE" or p == "RESULTS"
	end)

	local timerText = Computed(function()
		local t = math.max(0, math.ceil(timeRemaining:get()))
		return tostring(t)
	end)

	local timerColor = Spring(Computed(function()
		local p = phase:get()
		if p == "HUB_COUNTDOWN" then return GOLD end
		if p == "GAME_ACTIVE" then
			local t = timeRemaining:get()
			if t <= 5 then return RED end
			return TEXT_BRIGHT
		end
		return ACCENT
	end), 12)

	local phaseLabel = Computed(function()
		local p = phase:get()
		if p == "HUB_WAITING" then return "Waiting for players..." end
		if p == "HUB_COUNTDOWN" then return "Get Ready!" end
		if p == "TELEPORTING" then return "Teleporting..." end
		if p == "GAME_ACTIVE" then return "FIGHT!" end
		if p == "GAME_OVER" then return "Game Over" end
		if p == "RESULTS" then return "Results" end
		return ""
	end)

	local showPhaseLabel = Computed(function()
		local p = phase:get()
		return p ~= "GAME_ACTIVE" or timeRemaining:get() > 27
	end)

	local phaseLabelAlpha = Spring(Computed(function()
		return showPhaseLabel:get() and 0 or 1
	end), 10)

	local timerAlpha = Spring(Computed(function()
		return showTimer:get() and 0 or 1
	end), 10)

	local showResults = Computed(function()
		return phase:get() == "RESULTS"
	end)

	local resultsAlpha = Spring(Computed(function()
		return showResults:get() and 0 or 1
	end), 8)

	local scoreList = New "ScrollingFrame" {
		Name = "ScoreList",
		Size = UDim2.new(1, 0, 1, -72),
		Position = UDim2.new(0, 0, 0, 68),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = ACCENT,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,

		[Children] = {
			New "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			},
		},
	}
	self._scoreListFrame = scoreList

	local gui = New "ScreenGui" {
		Name = "MatchGui",
		DisplayOrder = 150,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		Parent = LocalPlayer.PlayerGui,

		[Children] = {
			New "TextLabel" {
				Name = "PhaseLabel",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 60),
				Size = UDim2.fromOffset(500, 50),
				BackgroundTransparency = 1,
				Text = phaseLabel,
				TextColor3 = ACCENT,
				TextTransparency = phaseLabelAlpha,
				TextSize = 28,
				Font = Enum.Font.GothamBold,
				TextStrokeTransparency = Computed(function()
					return showPhaseLabel:get() and 0.4 or 1
				end),
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			},

			New "TextLabel" {
				Name = "Timer",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 110),
				Size = UDim2.fromOffset(200, 60),
				BackgroundTransparency = 1,
				Text = timerText,
				TextColor3 = timerColor,
				TextTransparency = timerAlpha,
				TextSize = 52,
				Font = Enum.Font.GothamBlack,
				TextStrokeTransparency = Computed(function()
					return showTimer:get() and 0.3 or 1
				end),
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			},

			New "Frame" {
				Name = "ResultsOverlay",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(520, 420),
				BackgroundColor3 = BG_DARK,
				BackgroundTransparency = Computed(function()
					return showResults:get() and 0.15 or 1
				end),
				BorderSizePixel = 0,
				Visible = Computed(function()
					return phase:get() == "RESULTS" or phase:get() == "GAME_OVER"
				end),

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0, 16),
					},
					New "UIStroke" {
						Color = ACCENT,
						Thickness = 2,
						Transparency = resultsAlpha,
					},
					New "UIPadding" {
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
					},

					New "TextLabel" {
						Name = "Title",
						Size = UDim2.new(1, 0, 0, 36),
						BackgroundTransparency = 1,
						Text = "Match Results",
						TextColor3 = GOLD,
						TextTransparency = resultsAlpha,
						TextSize = 24,
						Font = Enum.Font.GothamBlack,
					},

					New "Frame" {
						Name = "Header",
						Size = UDim2.new(1, 0, 0, 24),
						Position = UDim2.new(0, 0, 0, 40),
						BackgroundTransparency = 1,

						[Children] = {
							New "UIPadding" {
								PaddingLeft = UDim.new(0, 12),
								PaddingRight = UDim.new(0, 12),
							},
							New "TextLabel" {
								Name = "NameH",
								Size = UDim2.new(0.4, -4, 1, 0),
								Position = UDim2.new(0, 36, 0, 0),
								BackgroundTransparency = 1,
								Text = "Player",
								TextColor3 = TEXT_DIM,
								TextTransparency = resultsAlpha,
								TextSize = 13,
								Font = Enum.Font.GothamMedium,
								TextXAlignment = Enum.TextXAlignment.Left,
							},
							New "TextLabel" {
								Name = "KillsH",
								AnchorPoint = Vector2.new(1, 0),
								Size = UDim2.new(0, 60, 1, 0),
								Position = UDim2.new(0.7, 0, 0, 0),
								BackgroundTransparency = 1,
								Text = "Kills",
								TextColor3 = TEXT_DIM,
								TextTransparency = resultsAlpha,
								TextSize = 13,
								Font = Enum.Font.GothamMedium,
								TextXAlignment = Enum.TextXAlignment.Center,
							},
							New "TextLabel" {
								Name = "DeathsH",
								AnchorPoint = Vector2.new(1, 0),
								Size = UDim2.new(0, 60, 1, 0),
								Position = UDim2.new(0.85, 0, 0, 0),
								BackgroundTransparency = 1,
								Text = "Deaths",
								TextColor3 = TEXT_DIM,
								TextTransparency = resultsAlpha,
								TextSize = 13,
								Font = Enum.Font.GothamMedium,
								TextXAlignment = Enum.TextXAlignment.Center,
							},
							New "TextLabel" {
								Name = "HitsH",
								AnchorPoint = Vector2.new(1, 0),
								Size = UDim2.new(0, 60, 1, 0),
								Position = UDim2.new(1, 0, 0, 0),
								BackgroundTransparency = 1,
								Text = "Hits",
								TextColor3 = TEXT_DIM,
								TextTransparency = resultsAlpha,
								TextSize = 13,
								Font = Enum.Font.GothamMedium,
								TextXAlignment = Enum.TextXAlignment.Center,
							},
						},
					},

					scoreList,
				},
			},
		},
	}

	self._trove:Add(gui)
end

return GraviBowMatchController
