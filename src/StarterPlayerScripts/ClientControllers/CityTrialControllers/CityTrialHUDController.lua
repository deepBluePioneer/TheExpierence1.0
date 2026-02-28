local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)
local ReplicaController = require(CustomPackages.Replica.ReplicaController)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local LocalPlayer = Players.LocalPlayer

local CityTrialHUDController = Knit.CreateController {
	Name = "CityTrialHUDController",
}

local _trove = Trove.new()

local phase = Value("LOBBY")
local matchTimeRemaining = Value(0)
local countdownRemaining = Value(0)
local resultsTimeRemaining = Value(0)
local playerCount = Value(0)
local readyCount = Value(0)

local earnedCurrency = Value(0)
local earnedXP = Value(0)
local totalPatches = Value(0)
local deaths = Value(0)

local function formatTime(seconds)
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function createLobbyOverlay()
	local visible = Computed(function()
		return phase:get() == "LOBBY"
	end)

	local statusText = Computed(function()
		local p = playerCount:get()
		local r = readyCount:get()
		return "Players: " .. p .. "  |  Ready: " .. r
	end)

	return New "Frame" {
		Name = "LobbyOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(15, 15, 25),
		BackgroundTransparency = 0.4,
		Visible = visible,
		ZIndex = 50,

		[Children] = {
			New "TextLabel" {
				Name = "Title",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.4),
				Size = UDim2.fromScale(0.5, 0.08),
				BackgroundTransparency = 1,
				Text = "City Trial",
				TextColor3 = Color3.fromRGB(80, 220, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
			},

			New "TextLabel" {
				Name = "Status",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.4, 0.05),
				BackgroundTransparency = 1,
				Text = statusText,
				TextColor3 = Color3.fromRGB(200, 200, 220),
				Font = Enum.Font.Gotham,
				TextScaled = true,
			},

			New "TextLabel" {
				Name = "WaitingLabel",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.58),
				Size = UDim2.fromScale(0.4, 0.04),
				BackgroundTransparency = 1,
				Text = "Waiting for all players...",
				TextColor3 = Color3.fromRGB(150, 150, 170),
				Font = Enum.Font.Gotham,
				TextScaled = true,
			},
		},
	}
end

local function createCountdownOverlay()
	local visible = Computed(function()
		return phase:get() == "COUNTDOWN"
	end)

	local countText = Computed(function()
		return tostring(countdownRemaining:get())
	end)

	local countColor = Computed(function()
		local r = countdownRemaining:get()
		if r <= 3 then return Color3.fromRGB(255, 80, 80) end
		if r <= 5 then return Color3.fromRGB(255, 220, 50) end
		return Color3.fromRGB(80, 220, 255)
	end)

	return New "Frame" {
		Name = "CountdownOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(15, 15, 25),
		BackgroundTransparency = 0.5,
		Visible = visible,
		ZIndex = 50,

		[Children] = {
			New "TextLabel" {
				Name = "GetReady",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.35),
				Size = UDim2.fromScale(0.4, 0.06),
				BackgroundTransparency = 1,
				Text = "Get Ready!",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
			},

			New "TextLabel" {
				Name = "CountdownNumber",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.2, 0.15),
				BackgroundTransparency = 1,
				Text = countText,
				TextColor3 = countColor,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
			},
		},
	}
end

local function createMatchHUD()
	local visible = Computed(function()
		return phase:get() == "IN_PROGRESS"
	end)

	local timerText = Computed(function()
		return formatTime(matchTimeRemaining:get())
	end)

	local timerColor = Computed(function()
		local t = matchTimeRemaining:get()
		if t <= 10 then return Color3.fromRGB(255, 80, 80) end
		if t <= 30 then return Color3.fromRGB(255, 220, 50) end
		return Color3.fromRGB(255, 255, 255)
	end)

	return New "Frame" {
		Name = "MatchHUD",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = visible,
		ZIndex = 10,

		[Children] = {
			-- Top center: match timer
			New "Frame" {
				Name = "TimerBar",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.02),
				Size = UDim2.fromScale(0.18, 0.06),
				BackgroundColor3 = Color3.fromRGB(20, 20, 35),
				BackgroundTransparency = 0.3,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.3, 0) },
					New "TextLabel" {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.9, 0.8),
						BackgroundTransparency = 1,
						Text = timerText,
						TextColor3 = timerColor,
						Font = Enum.Font.GothamBold,
						TextScaled = true,
					},
				},
			},

			-- Bottom left: patch count
			New "Frame" {
				Name = "PatchCounter",
				Position = UDim2.fromScale(0.01, 0.88),
				Size = UDim2.fromScale(0.15, 0.05),
				BackgroundColor3 = Color3.fromRGB(20, 20, 35),
				BackgroundTransparency = 0.3,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.3, 0) },
					New "TextLabel" {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.9, 0.8),
						BackgroundTransparency = 1,
						Text = Computed(function()
							return "Patches: " .. totalPatches:get()
						end),
						TextColor3 = Color3.fromRGB(255, 220, 50),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
				},
			},

			-- Player count
			New "Frame" {
				Name = "PlayerCount",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(0.99, 0.02),
				Size = UDim2.fromScale(0.12, 0.04),
				BackgroundColor3 = Color3.fromRGB(20, 20, 35),
				BackgroundTransparency = 0.3,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.3, 0) },
					New "TextLabel" {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.9, 0.8),
						BackgroundTransparency = 1,
						Text = Computed(function()
							return "Players: " .. playerCount:get()
						end),
						TextColor3 = Color3.fromRGB(200, 200, 220),
						Font = Enum.Font.Gotham,
						TextScaled = true,
					},
				},
			},
		},
	}
end

-- Animated bar targets: held at 0 while match is running, snap to real value on ENDED
local barCurrency = Value(0)
local barXP = Value(0)
local barPatches = Value(0)
local barDeaths = Value(0)

-- Reasonable visual maxes for bar fill (bars still show values beyond these, just capped at 100% fill)
local BAR_MAX_CURRENCY = 200
local BAR_MAX_XP = 500
local BAR_MAX_PATCHES = 60
local BAR_MAX_DEATHS = 10

local function createStatBar(label, valueState, maxVal, barColor, accentColor, layoutOrder, staggerDelay)
	local animTarget = Value(0)

	-- Stagger: each bar animates in sequence
	local _phaseConn
	_phaseConn = Computed(function()
		local p = phase:get()
		if p == "ENDED" or p == "RESULTS" then
			task.delay(staggerDelay, function()
				animTarget:set(1)
			end)
		else
			animTarget:set(0)
		end
		return p
	end)

	local fillFraction = Computed(function()
		local raw = valueState:get()
		return math.clamp(raw / math.max(maxVal, 1), 0, 1)
	end)

	local animatedFill = Spring(Computed(function()
		return fillFraction:get() * animTarget:get()
	end), 12, 0.7)

	local displayValue = Computed(function()
		local raw = valueState:get()
		local anim = animTarget:get()
		return math.floor(raw * math.clamp(anim, 0, 1))
	end)

	local animatedDisplayValue = Spring(Computed(function()
		return displayValue:get()
	end), 8, 0.9)

	local barTransparency = Spring(Computed(function()
		return animTarget:get() > 0 and 0 or 1
	end), 15)

	return New "Frame" {
		Name = label .. "Row",
		Size = UDim2.fromScale(0.92, 0.18),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,

		[Children] = {
			-- Label
			New "TextLabel" {
				Name = "Label",
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromScale(1, 0.38),
				BackgroundTransparency = 1,
				Text = label,
				TextColor3 = Color3.fromRGB(200, 200, 220),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTransparency = barTransparency,
			},

			-- Bar background
			New "Frame" {
				Name = "BarBG",
				Position = UDim2.fromScale(0, 0.42),
				Size = UDim2.fromScale(1, 0.36),
				BackgroundColor3 = Color3.fromRGB(25, 25, 40),
				BackgroundTransparency = Spring(Computed(function()
					return animTarget:get() > 0 and 0.3 or 1
				end), 15),
				ClipsDescendants = true,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.4, 0) },

					-- Fill bar
					New "Frame" {
						Name = "Fill",
						Size = Spring(Computed(function()
							return UDim2.fromScale(math.max(0.005, animatedFill:get()), 1)
						end), 12, 0.7),
						BackgroundColor3 = barColor,
						BackgroundTransparency = barTransparency,

						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(0.4, 0) },
							New "UIGradient" {
								Color = ColorSequence.new(barColor, accentColor),
								Rotation = 0,
							},
						},
					},
				},
			},

			-- Value label (right-aligned)
			New "TextLabel" {
				Name = "Value",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromScale(0.3, 0.38),
				BackgroundTransparency = 1,
				Text = Computed(function()
					local v = math.floor(animatedDisplayValue:get())
					if label == "Currency" then
						return "+" .. v
					elseif label == "XP" then
						return "+" .. v
					end
					return tostring(v)
				end),
				TextColor3 = accentColor,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextTransparency = barTransparency,
			},
		},
	}
end

local function createResultsOverlay()
	local visible = Computed(function()
		local p = phase:get()
		return p == "ENDED" or p == "RESULTS"
	end)

	local resultsTimerText = Computed(function()
		return "Returning to hub in " .. resultsTimeRemaining:get() .. "s"
	end)

	return New "Frame" {
		Name = "ResultsOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 10, 20),
		BackgroundTransparency = 0.3,
		Visible = visible,
		ZIndex = 60,

		[Children] = {
			New "TextLabel" {
				Name = "Title",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.12),
				Size = UDim2.fromScale(0.4, 0.08),
				BackgroundTransparency = 1,
				Text = "Match Complete!",
				TextColor3 = Color3.fromRGB(255, 220, 50),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
			},

			-- Results panel with animated bars
			New "Frame" {
				Name = "ResultsPanel",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.48),
				Size = UDim2.fromScale(0.4, 0.5),
				BackgroundColor3 = Color3.fromRGB(20, 20, 35),
				BackgroundTransparency = 0.15,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.03, 0) },
					New "UIPadding" {
						PaddingTop = UDim.new(0.04, 0),
						PaddingBottom = UDim.new(0.04, 0),
						PaddingLeft = UDim.new(0.05, 0),
						PaddingRight = UDim.new(0.05, 0),
					},

					New "UIListLayout" {
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0.03, 0),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					},

					createStatBar(
						"Currency",
						earnedCurrency,
						BAR_MAX_CURRENCY,
						Color3.fromRGB(200, 170, 0),
						Color3.fromRGB(255, 215, 0),
						1, 0.3
					),

					createStatBar(
						"XP",
						earnedXP,
						BAR_MAX_XP,
						Color3.fromRGB(40, 130, 220),
						Color3.fromRGB(80, 200, 255),
						2, 0.6
					),

					createStatBar(
						"Patches",
						totalPatches,
						BAR_MAX_PATCHES,
						Color3.fromRGB(50, 170, 80),
						Color3.fromRGB(100, 255, 130),
						3, 0.9
					),

					createStatBar(
						"Deaths",
						deaths,
						BAR_MAX_DEATHS,
						Color3.fromRGB(180, 50, 50),
						Color3.fromRGB(255, 80, 80),
						4, 1.2
					),
				},
			},

			-- Return timer
			New "TextLabel" {
				Name = "ReturnTimer",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.88),
				Size = UDim2.fromScale(0.35, 0.05),
				BackgroundTransparency = 1,
				Text = resultsTimerText,
				TextColor3 = Color3.fromRGB(150, 150, 170),
				Font = Enum.Font.Gotham,
				TextScaled = true,
				Visible = Computed(function()
					return phase:get() == "RESULTS"
				end),
			},
		},
	}
end

local function createHUD()
	local screenGui = New "ScreenGui" {
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		Name = "CityTrialHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

		[Children] = {
			createLobbyOverlay(),
			createCountdownOverlay(),
			createMatchHUD(),
			createResultsOverlay(),
		},
	}

	_trove:Add(screenGui)
end

local function bindMatchReplica(replica)
	local function sync(data)
		phase:set(data.phase or "LOBBY")
		matchTimeRemaining:set(data.matchTimeRemaining or 0)
		countdownRemaining:set(data.countdownRemaining or 0)
		resultsTimeRemaining:set(data.resultsTimeRemaining or 0)
		playerCount:set(data.playerCount or 0)
		readyCount:set(data.readyCount or 0)
	end

	sync(replica.Data)

	local fields = { "phase", "matchTimeRemaining", "countdownRemaining", "resultsTimeRemaining", "playerCount", "readyCount" }
	for _, field in ipairs(fields) do
		replica:ListenToChange({ field }, function(newVal)
			if field == "phase" then phase:set(newVal)
			elseif field == "matchTimeRemaining" then matchTimeRemaining:set(newVal)
			elseif field == "countdownRemaining" then countdownRemaining:set(newVal)
			elseif field == "resultsTimeRemaining" then resultsTimeRemaining:set(newVal)
			elseif field == "playerCount" then playerCount:set(newVal)
			elseif field == "readyCount" then readyCount:set(newVal)
			end
		end)
	end
end

local function bindPlayerReplica(replica)
	local function syncPlayer(data)
		totalPatches:set(data.totalPatches or 0)
		deaths:set(data.deaths or 0)
		earnedCurrency:set(data.earnedCurrency or 0)
		earnedXP:set(data.earnedXP or 0)
	end

	syncPlayer(replica.Data)

	for _, field in ipairs({ "totalPatches", "deaths", "earnedCurrency", "earnedXP" }) do
		replica:ListenToChange({ field }, function(newVal)
			if field == "totalPatches" then totalPatches:set(newVal)
			elseif field == "deaths" then deaths:set(newVal)
			elseif field == "earnedCurrency" then earnedCurrency:set(newVal)
			elseif field == "earnedXP" then earnedXP:set(newVal)
			end
		end)
	end
end

function CityTrialHUDController:KnitInit()
end

function CityTrialHUDController:KnitStart()
	ReplicaController.RequestData()

	createHUD()

	ReplicaController.ReplicaOfClassCreated("MatchState", function(replica)
		bindMatchReplica(replica)
	end)

	ReplicaController.ReplicaOfClassCreated("CTPlayerProfile", function(replica)
		if replica.Tags.Player == LocalPlayer then
			bindPlayerReplica(replica)
		end
	end)

	-- Auto-report ready once loaded
	task.spawn(function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end

		local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
		task.wait(1)

		local matchService = Knit.GetService("CityTrialMatchService")
		local playerService = Knit.GetService("CityTrialPlayerService")
		playerService.ReportReady:Fire()

		print("[CityTrialHUDController] Sent ready signal")
	end)
end

function CityTrialHUDController:Destroy()
	_trove:Destroy()
end

return CityTrialHUDController
