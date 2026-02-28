local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local ForValues = Fusion.ForValues

local LocalPlayer = Players.LocalPlayer

local HubLeaderboardController = Knit.CreateController {
	Name = "HubLeaderboardController",
}

local _trove = Trove.new()
local _screenGui = nil
local _leaderboardService = nil

local isOpen = Value(false)
local entries = Value({})
local isLoading = Value(false)

local isMobile = UserInputService.TouchEnabled

local function createEntryRow(entry)
	local isLocal = entry.userId == LocalPlayer.UserId

	local bgColor = isLocal and Color3.fromRGB(40, 60, 100) or Color3.fromRGB(35, 35, 55)
	local nameColor = isLocal and Color3.fromRGB(80, 220, 255) or Color3.fromRGB(220, 220, 230)

	local displayName = Value("Loading...")

	task.spawn(function()
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(entry.userId)
		end)
		displayName:set(ok and name or ("User" .. entry.userId))
	end)

	return New "Frame" {
		Name = "Entry_" .. entry.rank,
		Size = UDim2.fromScale(1, 0.08),
		BackgroundColor3 = bgColor,
		BackgroundTransparency = 0.3,

		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0.2, 0) },

			New "TextLabel" {
				Name = "Rank",
				Position = UDim2.fromScale(0.02, 0),
				Size = UDim2.fromScale(0.1, 1),
				BackgroundTransparency = 1,
				Text = "#" .. entry.rank,
				TextColor3 = Color3.fromRGB(255, 215, 0),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
			},

			New "TextLabel" {
				Name = "PlayerName",
				Position = UDim2.fromScale(0.14, 0),
				Size = UDim2.fromScale(0.55, 1),
				BackgroundTransparency = 1,
				Text = displayName,
				TextColor3 = nameColor,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},

			New "TextLabel" {
				Name = "Score",
				Position = UDim2.fromScale(0.72, 0),
				Size = UDim2.fromScale(0.25, 1),
				BackgroundTransparency = 1,
				Text = tostring(entry.value) .. " XP",
				TextColor3 = Color3.fromRGB(180, 220, 255),
				Font = Enum.Font.Gotham,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Right,
			},
		},
	}
end

local function createLeaderboardUI()
	local entryRows = Computed(function()
		local data = entries:get()
		local rows = {}
		for _, entry in ipairs(data) do
			table.insert(rows, createEntryRow(entry))
		end
		return rows
	end)

	local panelSize = isMobile and UDim2.fromScale(1, 1) or UDim2.fromScale(0.45, 0.7)

	local loadingText = Computed(function()
		if isLoading:get() then return "Loading..." end
		local data = entries:get()
		if #data == 0 then return "No entries yet" end
		return ""
	end)

	local showLoadingText = Computed(function()
		return isLoading:get() or #entries:get() == 0
	end)

	_screenGui = New "ScreenGui" {
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		Name = "HubLeaderboardUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = isOpen,

		[Children] = {
			New "TextButton" {
				Name = "Backdrop",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.5,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 1,

				[OnEvent "Activated"] = function()
					HubLeaderboardController:Close()
				end,
			},

			New "Frame" {
				Name = "LeaderboardPanel",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = panelSize,
				BackgroundColor3 = Color3.fromRGB(25, 25, 40),
				BackgroundTransparency = 0.1,
				ZIndex = 2,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.02, 0) },

					New "TextLabel" {
						Position = UDim2.fromScale(0.03, 0.01),
						Size = UDim2.fromScale(0.5, 0.07),
						BackgroundTransparency = 1,
						Text = "Leaderboard",
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 3,
					},

					New "TextButton" {
						Name = "CloseButton",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(0.98, 0.01),
						Size = UDim2.fromScale(0.06, 0.06),
						SizeConstraint = Enum.SizeConstraint.RelativeYY,
						BackgroundColor3 = Color3.fromRGB(200, 60, 60),
						Text = "X",
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						ZIndex = 3,

						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
							New "UIAspectRatioConstraint" { AspectRatio = 1 },
						},

						[OnEvent "Activated"] = function()
							HubLeaderboardController:Close()
						end,
					},

					New "TextLabel" {
						Name = "LoadingText",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.5, 0.05),
						BackgroundTransparency = 1,
						Text = loadingText,
						TextColor3 = Color3.fromRGB(160, 160, 180),
						Font = Enum.Font.Gotham,
						TextScaled = true,
						Visible = showLoadingText,
						ZIndex = 3,
					},

					New "ScrollingFrame" {
						Name = "EntriesScroll",
						Position = UDim2.fromScale(0.02, 0.1),
						Size = UDim2.fromScale(0.96, 0.88),
						BackgroundTransparency = 1,
						ScrollBarThickness = 4,
						CanvasSize = UDim2.fromScale(0, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.Y,
						ScrollingDirection = Enum.ScrollingDirection.Y,
						ZIndex = 3,

						[Children] = {
							New "UIListLayout" {
								FillDirection = Enum.FillDirection.Vertical,
								Padding = UDim.new(0.005, 0),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							entryRows,
						},
					},

					-- Refresh button
					New "TextButton" {
						Name = "RefreshButton",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(0.85, 0.01),
						Size = UDim2.fromScale(0.1, 0.06),
						BackgroundColor3 = Color3.fromRGB(60, 120, 180),
						Text = "Refresh",
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						ZIndex = 3,

						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(0.3, 0) },
						},

						[OnEvent "Activated"] = function()
							HubLeaderboardController:Refresh()
						end,
					},
				},
			},
		},
	}

	_trove:Add(_screenGui)
end

function HubLeaderboardController:KnitInit()
end

function HubLeaderboardController:KnitStart()
	_leaderboardService = Knit.GetService("HubLeaderboardService")
	createLeaderboardUI()
end

function HubLeaderboardController:Refresh()
	if isLoading:get() then return end

	isLoading:set(true)
	task.spawn(function()
		local ok, result = pcall(function()
			return _leaderboardService:GetTopPlayers(50)
		end)

		if ok and result then
			entries:set(result)
		else
			warn("[HubLeaderboardController] Failed to fetch leaderboard: " .. tostring(result))
		end
		isLoading:set(false)
	end)
end

function HubLeaderboardController:Open()
	local panelManager = Knit.GetController("HubPanelManager")
	if panelManager then
		panelManager:OpenPanel("leaderboard")
	else
		isOpen:set(true)
	end
	self:Refresh()
end

function HubLeaderboardController:Close()
	local panelManager = Knit.GetController("HubPanelManager")
	if panelManager then
		panelManager:ClosePanel()
	else
		isOpen:set(false)
	end
end

function HubLeaderboardController:SetOpen(open)
	isOpen:set(open)
	if open then
		self:Refresh()
	end
end

function HubLeaderboardController:IsOpen()
	return isOpen:get()
end

function HubLeaderboardController:Destroy()
	_trove:Destroy()
end

return HubLeaderboardController
