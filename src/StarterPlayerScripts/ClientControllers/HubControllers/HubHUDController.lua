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
local OnEvent = Fusion.OnEvent

local LocalPlayer = Players.LocalPlayer

local HubHUDController = Knit.CreateController {
	Name = "HubHUDController",
}

local currency = Value(0)
local xp = Value(0)
local level = Value(1)
local machineName = Value("--")
local isLoaded = Value(false)

local _trove = Trove.new()
local _screenGui = nil
local _replica = nil

local function formatNumber(n)
	if n >= 1000000 then
		return string.format("%.1fM", n / 1000000)
	elseif n >= 1000 then
		return string.format("%.1fK", n / 1000)
	end
	return tostring(n)
end

local function createHUD()
	local xpBarFill = Computed(function()
		local ProfileConfig = require(ReplicatedStorage.Source.ProfileConfig)
		local currentXP = xp:get()
		local currentLevel = level:get()
		local needed = ProfileConfig.xpForLevel(currentLevel + 1)
		local prevNeeded = ProfileConfig.xpForLevel(currentLevel)
		local progress = math.clamp((currentXP - prevNeeded) / math.max(needed - prevNeeded, 1), 0, 1)
		return UDim2.fromScale(progress, 1)
	end)

	local smoothFill = Spring(xpBarFill, 25, 1)

	local currencyText = Computed(function()
		return formatNumber(currency:get())
	end)

	local levelText = Computed(function()
		return "Lv." .. level:get()
	end)

	local machineText = Computed(function()
		return machineName:get()
	end)

	local loadingVisible = Computed(function()
		return not isLoaded:get()
	end)

	_screenGui = New "ScreenGui" {
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		Name = "HubHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

		[Children] = {
			-- Loading overlay
			New "Frame" {
				Name = "LoadingOverlay",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(20, 20, 30),
				BackgroundTransparency = 0.3,
				Visible = loadingVisible,
				ZIndex = 100,

				[Children] = {
					New "TextLabel" {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(0.4, 0.06),
						BackgroundTransparency = 1,
						Text = "Loading your data...",
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
					},
				},
			},

			-- Top-left HUD panel
			New "Frame" {
				Name = "HUDPanel",
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.fromScale(0.01, 0.04),
				Size = UDim2.fromScale(0.22, 0.12),
				BackgroundColor3 = Color3.fromRGB(30, 30, 50),
				BackgroundTransparency = 0.4,

				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0.15, 0),
					},

					-- Currency row
					New "TextLabel" {
						Name = "CurrencyIcon",
						Position = UDim2.fromScale(0.04, 0.05),
						Size = UDim2.fromScale(0.15, 0.35),
						BackgroundTransparency = 1,
						Text = "coin",
						TextColor3 = Color3.fromRGB(255, 215, 0),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
					},

					New "TextLabel" {
						Name = "CurrencyValue",
						Position = UDim2.fromScale(0.22, 0.05),
						Size = UDim2.fromScale(0.35, 0.35),
						BackgroundTransparency = 1,
						Text = currencyText,
						TextColor3 = Color3.fromRGB(255, 255, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
					},

					-- Level badge
					New "TextLabel" {
						Name = "LevelBadge",
						Position = UDim2.fromScale(0.65, 0.05),
						Size = UDim2.fromScale(0.3, 0.35),
						BackgroundTransparency = 1,
						Text = levelText,
						TextColor3 = Color3.fromRGB(150, 220, 255),
						Font = Enum.Font.GothamBold,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Right,
					},

					-- XP bar background
					New "Frame" {
						Name = "XPBarBg",
						Position = UDim2.fromScale(0.04, 0.48),
						Size = UDim2.fromScale(0.92, 0.15),
						BackgroundColor3 = Color3.fromRGB(50, 50, 70),

						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0.5, 0),
							},
							New "Frame" {
								Name = "XPBarFill",
								Size = smoothFill,
								BackgroundColor3 = Color3.fromRGB(80, 200, 255),

								[Children] = {
									New "UICorner" {
										CornerRadius = UDim.new(0.5, 0),
									},
								},
							},
						},
					},

					-- Machine name
					New "TextLabel" {
						Name = "MachineName",
						Position = UDim2.fromScale(0.04, 0.7),
						Size = UDim2.fromScale(0.92, 0.25),
						BackgroundTransparency = 1,
						Text = machineText,
						TextColor3 = Color3.fromRGB(200, 200, 220),
						Font = Enum.Font.Gotham,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
				},
			},
		},
	}

	_trove:Add(_screenGui)
end

local function bindReplica(replica)
	_replica = replica

	local data = replica.Data
	currency:set(data.currency or 0)
	xp:set(data.xp or 0)
	level:set(data.level or 1)

	local MachinesConfig = require(ReplicatedStorage.Source.MachinesConfig)
	local selId = data.selectedMachineId or MachinesConfig.defaultMachineId
	local machDef = MachinesConfig.machines[selId]
	machineName:set(machDef and machDef.displayName or selId)

	isLoaded:set(true)

	_trove:Add(replica:ListenToChange({ "currency" }, function(newVal)
		currency:set(newVal)
	end))

	_trove:Add(replica:ListenToChange({ "xp" }, function(newVal)
		xp:set(newVal)
	end))

	_trove:Add(replica:ListenToChange({ "level" }, function(newVal)
		level:set(newVal)
	end))

	_trove:Add(replica:ListenToChange({ "selectedMachineId" }, function(newVal)
		local def = MachinesConfig.machines[newVal]
		machineName:set(def and def.displayName or newVal)
	end))
end

function HubHUDController:KnitInit()
end

function HubHUDController:KnitStart()
	ReplicaController.RequestData()

	createHUD()

	ReplicaController.ReplicaOfClassCreated("PlayerProfile", function(replica)
		if replica.Tags.Player == LocalPlayer then
			bindReplica(replica)
		end
	end)
end

function HubHUDController:GetCurrency()
	return currency:get()
end

function HubHUDController:GetLevel()
	return level:get()
end

function HubHUDController:IsLoaded()
	return isLoaded:get()
end

function HubHUDController:Destroy()
	_trove:Destroy()
end

return HubHUDController
