local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local AMBER       = Color3.fromRGB(255, 150, 40)
local SAND        = Color3.fromRGB(237, 201, 140)
local BONE        = Color3.fromRGB(240, 225, 195)
local DUST        = Color3.fromRGB(160, 130, 90)
local BG_DARK     = Color3.fromRGB(25, 18, 12)
local BG_CARD     = Color3.fromRGB(45, 32, 20)
local RUNNER_BLUE = Color3.fromRGB(50, 140, 220)
local SNAKE_RED   = Color3.fromRGB(180, 45, 30)
local CRIMSON     = Color3.fromRGB(210, 55, 40)
local GOLD        = Color3.fromRGB(255, 195, 55)

local FONT_TITLE = Enum.Font.Fondamento
local FONT_BODY  = Enum.Font.TitilliumWeb
local FONT_TIMER = Enum.Font.Oswald

local GraviBowMatchController = Knit.CreateController({
	Name = "GraviBowMatchController",
	_trove = nil,

	Phase = "WAITING",
})

function GraviBowMatchController:KnitInit()
	self._trove = Trove.new()
	self._phase = Value("WAITING")
	self._timeRemaining = Value(0)
	self._isSnake = Value(false)
	self._firstSnakeId = Value(0)
	self._scoreListFrame = nil
	self._aliveListFrame = nil
	self._aliveCountLabel = nil
	self._lastScores = {}
end

function GraviBowMatchController:KnitStart()
	ReplicaController.RequestData()

	ReplicaController.ReplicaOfClassCreated("GraviBowMatchState", function(replica)
		self._replica = replica

		local data = replica.Data
		self._phase:set(data.phase or "WAITING")
		self._timeRemaining:set(data.timeRemaining or 0)
		self._firstSnakeId:set(data.firstSnakeId or 0)
		self.Phase = data.phase or "WAITING"

		local myKey = tostring(LocalPlayer.UserId)
		local snakePlayers = data.snakePlayers or {}
		self._isSnake:set(snakePlayers[myKey] == true)

		replica:ListenToChange({"phase"}, function(newVal)
			self._phase:set(newVal)
			self.Phase = newVal
			if newVal == "RESULTS" or newVal == "ROUND_OVER" then
				self:_refreshScoreList(replica.Data.scores or {}, replica.Data.snakePlayers or {})
			end
			if newVal == "COUNTDOWN" or newVal == "SNAKE_SPAWNING" or newVal == "ROUND_ACTIVE" then
				self:_refreshAliveList(replica.Data.scores or {}, replica.Data.snakePlayers or {})
			end
		end)

		replica:ListenToChange({"timeRemaining"}, function(newVal)
			self._timeRemaining:set(newVal)
		end)

		replica:ListenToChange({"firstSnakeId"}, function(newVal)
			self._firstSnakeId:set(newVal or 0)
		end)

		replica:ListenToRaw(function()
			local sp = replica.Data.snakePlayers or {}
			self._isSnake:set(sp[myKey] == true)

			local p = self.Phase
			if p == "RESULTS" or p == "ROUND_OVER" or p == "ROUND_ACTIVE" then
				self:_refreshScoreList(replica.Data.scores or {}, sp)
			end
			if p == "COUNTDOWN" or p == "SNAKE_SPAWNING" or p == "ROUND_ACTIVE" then
				self:_refreshAliveList(replica.Data.scores or {}, sp)
			end
		end)
	end)

	self:_createUI()
end

function GraviBowMatchController:_addTextSizeConstraint(parent, minSize, maxSize)
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = minSize or 8
	c.MaxTextSize = maxSize or 36
	c.Parent = parent
	return c
end

function GraviBowMatchController:_refreshScoreList(scores, snakePlayers)
	if not self._scoreListFrame then return end

	local list = {}
	for userId, data in pairs(scores) do
		if type(data) == "table" then
			table.insert(list, {
				userId = userId,
				name = data.name or "???",
				deaths = data.deaths or 0,
				survived = data.survived or false,
				isSnake = snakePlayers[userId] == true,
			})
		end
	end
	table.sort(list, function(a, b)
		if a.survived ~= b.survived then return a.survived end
		return a.deaths < b.deaths
	end)

	for _, child in ipairs(self._scoreListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for rank, entry in ipairs(list) do
		local isLocal = entry.userId == tostring(LocalPlayer.UserId)
		local rowBg = isLocal and Color3.fromRGB(65, 45, 25) or BG_CARD

		local row = Instance.new("Frame")
		row.Name = "Row_" .. rank
		row.Size = UDim2.new(1, 0, 0.09, 0)
		row.BackgroundColor3 = rowBg
		row.BackgroundTransparency = 0.2
		row.BorderSizePixel = 0
		row.LayoutOrder = rank

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.15, 0)
		corner.Parent = row

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.03, 0)
		pad.PaddingRight = UDim.new(0.03, 0)
		pad.Parent = row

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Name = "Rank"
		rankLabel.Size = UDim2.new(0.08, 0, 1, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Text = "#" .. rank
		rankLabel.TextScaled = true
		rankLabel.TextColor3 = rank == 1 and GOLD or DUST
		rankLabel.Font = FONT_BODY
		rankLabel.TextXAlignment = Enum.TextXAlignment.Left
		rankLabel.Parent = row
		self:_addTextSizeConstraint(rankLabel, 10, 24)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "Name"
		nameLabel.Size = UDim2.new(0.38, 0, 1, 0)
		nameLabel.Position = UDim2.new(0.1, 0, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = entry.name
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = isLocal and AMBER or BONE
		nameLabel.Font = FONT_BODY
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = row
		self:_addTextSizeConstraint(nameLabel, 10, 24)

		local roleLabel = Instance.new("TextLabel")
		roleLabel.Name = "Role"
		roleLabel.AnchorPoint = Vector2.new(1, 0)
		roleLabel.Size = UDim2.new(0.2, 0, 1, 0)
		roleLabel.Position = UDim2.new(0.73, 0, 0, 0)
		roleLabel.BackgroundTransparency = 1
		roleLabel.Text = entry.isSnake and "SNAKE" or "RUNNER"
		roleLabel.TextScaled = true
		roleLabel.TextColor3 = entry.isSnake and SNAKE_RED or RUNNER_BLUE
		roleLabel.Font = FONT_TITLE
		roleLabel.TextXAlignment = Enum.TextXAlignment.Center
		roleLabel.Parent = row
		self:_addTextSizeConstraint(roleLabel, 10, 22)

		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "Status"
		statusLabel.AnchorPoint = Vector2.new(1, 0)
		statusLabel.Size = UDim2.new(0.25, 0, 1, 0)
		statusLabel.Position = UDim2.new(1, 0, 0, 0)
		statusLabel.BackgroundTransparency = 1
		statusLabel.Text = entry.survived and "SURVIVED" or (entry.isSnake and string.format("%d caught", entry.deaths) or "CAUGHT")
		statusLabel.TextScaled = true
		statusLabel.TextColor3 = entry.survived and GOLD or DUST
		statusLabel.Font = FONT_BODY
		statusLabel.TextXAlignment = Enum.TextXAlignment.Center
		statusLabel.Parent = row
		self:_addTextSizeConstraint(statusLabel, 10, 22)

		row.Parent = self._scoreListFrame
	end
end

function GraviBowMatchController:_createAliveRow(entry, order, dotColor, nameColor)
	local row = Instance.new("Frame")
	row.Name = (entry.isSnake and "S_" or "R_") .. entry.userId
	row.Size = UDim2.new(1, 0, 0.08, 0)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.BorderSizePixel = 0

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromScale(0.045, 0.35)
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 0, 0.5, 0)
	dot.BackgroundColor3 = dotColor
	dot.BorderSizePixel = 0
	dot.Parent = row

	local dotAR = Instance.new("UIAspectRatioConstraint")
	dotAR.AspectRatio = 1
	dotAR.Parent = dot

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(0.88, 0, 1, 0)
	nameLabel.Position = UDim2.new(0.12, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = entry.name
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = nameColor
	nameLabel.Font = FONT_BODY
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = row
	self:_addTextSizeConstraint(nameLabel, 8, 18)

	return row
end

function GraviBowMatchController:_refreshAliveList(scores, snakePlayers)
	if not self._aliveListFrame then return end

	for _, child in ipairs(self._aliveListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local runners = {}
	local snakes = {}
	for userId, data in pairs(scores) do
		if type(data) ~= "table" then continue end
		local entry = { userId = userId, name = data.name or "???", isSnake = snakePlayers[userId] == true }
		if entry.isSnake then
			table.insert(snakes, entry)
		else
			table.insert(runners, entry)
		end
	end
	table.sort(runners, function(a, b) return a.name < b.name end)
	table.sort(snakes, function(a, b) return a.name < b.name end)

	if self._aliveCountLabel then
		self._aliveCountLabel.Text = tostring(#runners) .. " alive"
	end

	local order = 0
	for _, entry in ipairs(runners) do
		order += 1
		local isLocal = entry.userId == tostring(LocalPlayer.UserId)
		local row = self:_createAliveRow(entry, order, RUNNER_BLUE, isLocal and AMBER or BONE)
		row.Parent = self._aliveListFrame
	end

	for _, entry in ipairs(snakes) do
		order += 1
		local isLocal = entry.userId == tostring(LocalPlayer.UserId)
		local row = self:_createAliveRow(entry, order, SNAKE_RED, isLocal and AMBER or DUST)
		row.Parent = self._aliveListFrame
	end
end

function GraviBowMatchController:IsLocalPlayerSnake()
	return self._isSnake:get()
end

function GraviBowMatchController:_createUI()
	local phase = self._phase
	local timeRemaining = self._timeRemaining
	local isSnake = self._isSnake

	local showTimer = Computed(function()
		local p = phase:get()
		return p == "COUNTDOWN" or p == "ROUND_ACTIVE"
	end)

	local timerText = Computed(function()
		local t = math.max(0, math.ceil(timeRemaining:get()))
		local p = phase:get()
		if p == "COUNTDOWN" then
			return tostring(t)
		elseif p == "ROUND_ACTIVE" then
			local mins = math.floor(t / 60)
			local secs = t % 60
			return string.format("%d:%02d", mins, secs)
		end
		return tostring(t)
	end)

	local timerColor = Spring(Computed(function()
		local p = phase:get()
		if p == "COUNTDOWN" then return AMBER end
		if p == "ROUND_ACTIVE" then
			local t = timeRemaining:get()
			if t <= 10 then return CRIMSON end
			return SAND
		end
		return AMBER
	end), 12)

	local phaseLabel = Computed(function()
		local p = phase:get()
		if p == "WAITING" then return "Waiting for players..." end
		if p == "COUNTDOWN" then
			if isSnake:get() then
				return "YOU ARE THE SNAKE"
			else
				return "THE SNAKE IS COMING"
			end
		end
		if p == "SNAKE_SPAWNING" then
			if isSnake:get() then
				return "Your snake is emerging..."
			else
				return "The ground shakes..."
			end
		end
		if p == "ROUND_ACTIVE" then
			if isSnake:get() then
				return "HUNT THEM DOWN"
			else
				return "RUN FOR YOUR LIFE"
			end
		end
		if p == "ROUND_OVER" then return "Round Over" end
		if p == "RESULTS" then return "Scoreboard" end
		return ""
	end)

	local phaseLabelColor = Computed(function()
		local p = phase:get()
		if p == "COUNTDOWN" or p == "SNAKE_SPAWNING" or p == "ROUND_ACTIVE" then
			if isSnake:get() then
				return SNAKE_RED
			end
			return RUNNER_BLUE
		end
		if p == "ROUND_OVER" then return GOLD end
		return SAND
	end)

	local showPhaseLabel = Computed(function()
		local p = phase:get()
		return p ~= "WAITING" or false
	end)

	local phaseLabelAlpha = Spring(Computed(function()
		return showPhaseLabel:get() and 0 or 1
	end), 10)

	local timerAlpha = Spring(Computed(function()
		return showTimer:get() and 0 or 1
	end), 10)

	local showAliveList = Computed(function()
		local p = phase:get()
		return p == "COUNTDOWN" or p == "SNAKE_SPAWNING" or p == "ROUND_ACTIVE"
	end)

	local aliveListAlpha = Spring(Computed(function()
		return showAliveList:get() and 0 or 1
	end), 10)

	local showResults = Computed(function()
		local p = phase:get()
		return p == "RESULTS" or p == "ROUND_OVER"
	end)

	local resultsAlpha = Spring(Computed(function()
		return showResults:get() and 0 or 1
	end), 8)

	local scoreList = New "ScrollingFrame" {
		Name = "ScoreList",
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.fromScale(0, 0.17),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = AMBER,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,

		[Children] = {
			New "UIListLayout" {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0.01, 0),
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
				Position = UDim2.fromScale(0.5, 0.035),
				Size = UDim2.fromScale(0.5, 0.07),
				BackgroundTransparency = 1,
				Text = phaseLabel,
				TextScaled = true,
				TextColor3 = phaseLabelColor,
				TextTransparency = phaseLabelAlpha,
				Font = FONT_TITLE,
				TextStrokeTransparency = Computed(function()
					return showPhaseLabel:get() and 0.3 or 1
				end),
				TextStrokeColor3 = Color3.fromRGB(15, 10, 5),

				[Children] = {
					New "UITextSizeConstraint" {
						MinTextSize = 14,
						MaxTextSize = 52,
					},
				},
			},

			New "TextLabel" {
				Name = "Timer",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.11),
				Size = UDim2.fromScale(0.22, 0.1),
				BackgroundTransparency = 1,
				Text = timerText,
				TextScaled = true,
				TextColor3 = timerColor,
				TextTransparency = timerAlpha,
				Font = FONT_TIMER,
				TextStrokeTransparency = Computed(function()
					return showTimer:get() and 0.2 or 1
				end),
				TextStrokeColor3 = Color3.fromRGB(15, 10, 5),

				[Children] = {
					New "UITextSizeConstraint" {
						MinTextSize = 20,
						MaxTextSize = 96,
					},
				},
			},

			New "Frame" {
				Name = "ResultsOverlay",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.45, 0.6),
				BackgroundColor3 = BG_DARK,
				BackgroundTransparency = Computed(function()
					return showResults:get() and 0.08 or 1
				end),
				BorderSizePixel = 0,
				Visible = Computed(function()
					return phase:get() == "RESULTS" or phase:get() == "ROUND_OVER"
				end),

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.02, 0),
					},
					New "UIStroke" {
						Color = AMBER,
						Thickness = 2,
						Transparency = resultsAlpha,
					},
					New "UIPadding" {
						PaddingTop = UDim.new(0.035, 0),
						PaddingBottom = UDim.new(0.035, 0),
						PaddingLeft = UDim.new(0.03, 0),
						PaddingRight = UDim.new(0.03, 0),
					},

					New "TextLabel" {
						Name = "Title",
						Size = UDim2.new(1, 0, 0.1, 0),
						BackgroundTransparency = 1,
						Text = Computed(function()
							if isSnake:get() then
								return "The Snake Got Everyone"
							else
								return "You Survived!"
							end
						end),
						TextScaled = true,
						TextColor3 = GOLD,
						TextTransparency = resultsAlpha,
						Font = FONT_TITLE,

						[Children] = {
							New "UITextSizeConstraint" {
								MinTextSize = 14,
								MaxTextSize = 38,
							},
						},
					},

					New "Frame" {
						Name = "Header",
						Size = UDim2.new(1, 0, 0.055, 0),
						Position = UDim2.fromScale(0, 0.11),
						BackgroundTransparency = 1,

						[Children] = {
							New "UIPadding" {
								PaddingLeft = UDim.new(0.03, 0),
								PaddingRight = UDim.new(0.03, 0),
							},
							New "TextLabel" {
								Name = "NameH",
								Size = UDim2.new(0.38, 0, 1, 0),
								Position = UDim2.fromScale(0.1, 0),
								BackgroundTransparency = 1,
								Text = "Name",
								TextScaled = true,
								TextColor3 = DUST,
								TextTransparency = resultsAlpha,
								Font = FONT_BODY,
								TextXAlignment = Enum.TextXAlignment.Left,

								[Children] = {
									New "UITextSizeConstraint" {
										MinTextSize = 8,
										MaxTextSize = 18,
									},
								},
							},
							New "TextLabel" {
								Name = "RoleH",
								AnchorPoint = Vector2.new(1, 0),
								Size = UDim2.new(0.2, 0, 1, 0),
								Position = UDim2.fromScale(0.73, 0),
								BackgroundTransparency = 1,
								Text = "Role",
								TextScaled = true,
								TextColor3 = DUST,
								TextTransparency = resultsAlpha,
								Font = FONT_BODY,
								TextXAlignment = Enum.TextXAlignment.Center,

								[Children] = {
									New "UITextSizeConstraint" {
										MinTextSize = 8,
										MaxTextSize = 18,
									},
								},
							},
							New "TextLabel" {
								Name = "StatusH",
								AnchorPoint = Vector2.new(1, 0),
								Size = UDim2.new(0.25, 0, 1, 0),
								Position = UDim2.fromScale(1, 0),
								BackgroundTransparency = 1,
								Text = "Status",
								TextScaled = true,
								TextColor3 = DUST,
								TextTransparency = resultsAlpha,
								Font = FONT_BODY,
								TextXAlignment = Enum.TextXAlignment.Center,

								[Children] = {
									New "UITextSizeConstraint" {
										MinTextSize = 8,
										MaxTextSize = 18,
									},
								},
							},
						},
					},

					scoreList,
				},
			},

			New "Frame" {
				Name = "AlivePanel",
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.fromScale(0.01, 0.046),
				Size = UDim2.fromScale(0.13, 0.4),
				BackgroundColor3 = BG_DARK,
				BackgroundTransparency = Computed(function()
					return showAliveList:get() and 0.25 or 1
				end),
				BorderSizePixel = 0,
				Visible = showAliveList,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.025, 0),
					},
					New "UIStroke" {
						Color = AMBER,
						Thickness = 1,
						Transparency = aliveListAlpha,
					},
					New "UIPadding" {
						PaddingTop = UDim.new(0.03, 0),
						PaddingBottom = UDim.new(0.03, 0),
						PaddingLeft = UDim.new(0.06, 0),
						PaddingRight = UDim.new(0.06, 0),
					},

					New "TextLabel" {
						Name = "Title",
						Size = UDim2.fromScale(0.5, 0.07),
						BackgroundTransparency = 1,
						Text = "PLAYERS",
						TextScaled = true,
						TextColor3 = AMBER,
						TextTransparency = aliveListAlpha,
						Font = FONT_TITLE,
						TextXAlignment = Enum.TextXAlignment.Left,

						[Children] = {
							New "UITextSizeConstraint" {
								MinTextSize = 10,
								MaxTextSize = 22,
							},
						},
					},

					(function()
						local lbl = New "TextLabel" {
							Name = "AliveCount",
							AnchorPoint = Vector2.new(1, 0),
							Position = UDim2.fromScale(1, 0),
							Size = UDim2.fromScale(0.5, 0.07),
							BackgroundTransparency = 1,
							Text = "0 alive",
							TextScaled = true,
							TextColor3 = SAND,
							TextTransparency = aliveListAlpha,
							Font = FONT_BODY,
							TextXAlignment = Enum.TextXAlignment.Right,

							[Children] = {
								New "UITextSizeConstraint" {
									MinTextSize = 8,
									MaxTextSize = 16,
								},
							},
						}
						self._aliveCountLabel = lbl
						return lbl
					end)(),

					New "Frame" {
						Name = "Divider",
						Size = UDim2.new(1, 0, 0, 1),
						Position = UDim2.fromScale(0, 0.08),
						BackgroundColor3 = DUST,
						BackgroundTransparency = 0.5,
						BorderSizePixel = 0,
					},

					(function()
						local scrollFrame = New "ScrollingFrame" {
							Name = "AliveList",
							Size = UDim2.fromScale(1, 0.88),
							Position = UDim2.fromScale(0, 0.1),
							BackgroundTransparency = 1,
							ScrollBarThickness = 4,
							ScrollBarImageColor3 = DUST,
							CanvasSize = UDim2.new(0, 0, 0, 0),
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							BorderSizePixel = 0,

							[Children] = {
								New "UIListLayout" {
									SortOrder = Enum.SortOrder.LayoutOrder,
									Padding = UDim.new(0.01, 0),
								},
							},
						}
						self._aliveListFrame = scrollFrame
						return scrollFrame
					end)(),
				},
			},
		},
	}

	self._trove:Add(gui)
end

return GraviBowMatchController
