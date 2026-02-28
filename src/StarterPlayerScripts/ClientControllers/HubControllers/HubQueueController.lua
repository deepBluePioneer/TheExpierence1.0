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
local Tween = Fusion.Tween
local OnEvent = Fusion.OnEvent

local TeleportConfig = require(ReplicatedStorage.Source.TeleportConfig)

local LocalPlayer = Players.LocalPlayer

local HubQueueController = Knit.CreateController {
	Name = "HubQueueController",
}

local _trove = Trove.new()
local _screenGui = nil
local _queueService = nil

local isInQueue = Value(false)
local queueState = Value("WAITING")
local queueSize = Value(0)
local countdownEndTime = Value(nil)
local lastError = Value(nil)
local secondsRemaining = Value(0)
local activeTeleporterId = Value(nil)

local isTeleporting = Computed(function()
	return queueState:get() == "TELEPORTING"
end)

local isCountdown = Computed(function()
	return queueState:get() == "COUNTDOWN"
end)

local function createQueueBar()
	local barVisible = Computed(function()
		return isInQueue:get()
	end)

	local statusText = Computed(function()
		local state = queueState:get()
		local size = queueSize:get()
		local err = lastError:get()

		if state == "TELEPORTING" then
			return "Teleporting..."
		elseif state == "COUNTDOWN" then
			local secs = secondsRemaining:get()
			return "Starting in " .. math.max(0, math.ceil(secs)) .. "s  (" .. size .. "/" .. TeleportConfig.maxPlayers .. ")"
		else
			local base = "Waiting... " .. size .. "/" .. TeleportConfig.minPlayers
			if err then
				return base .. "  |  " .. err
			end
			return base
		end
	end)

	local barColor = Computed(function()
		local state = queueState:get()
		if state == "TELEPORTING" then return Color3.fromRGB(60, 200, 60) end
		if state == "COUNTDOWN" then return Color3.fromRGB(255, 180, 40) end
		return Color3.fromRGB(60, 100, 180)
	end)

	return New "Frame" {
		Name = "QueueBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.96),
		Size = UDim2.fromScale(0.4, 0.06),
		BackgroundColor3 = Color3.fromRGB(25, 25, 40),
		BackgroundTransparency = 0.3,
		Visible = barVisible,
		ZIndex = 10,

		[Children] = {
			New "UICorner" { CornerRadius = UDim.new(0.3, 0) },
			New "UIStroke" {
				Color = barColor,
				Thickness = 2,
			},

			New "TextLabel" {
				Name = "StatusText",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.04, 0.5),
				Size = UDim2.fromScale(0.7, 0.7),
				BackgroundTransparency = 1,
				Text = statusText,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},

			New "TextButton" {
				Name = "LeaveButton",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(0.96, 0.5),
				Size = UDim2.fromScale(0.18, 0.65),
				BackgroundColor3 = Color3.fromRGB(180, 50, 50),
				Text = "Leave",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				Visible = Computed(function()
					return not isTeleporting:get()
				end),

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0.3, 0) },
				},

				[OnEvent "Activated"] = function()
					local tid = activeTeleporterId:get()
					if tid and _queueService then
						_queueService:LeaveQueue(tid)
					end
					isInQueue:set(false)
				end,
			},
		},
	}
end

local function createTeleportOverlay()
	return New "Frame" {
		Name = "TeleportOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 10, 20),
		BackgroundTransparency = 0.3,
		Visible = isTeleporting,
		ZIndex = 100,

		[Children] = {
			New "TextLabel" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.45),
				Size = UDim2.fromScale(0.5, 0.06),
				BackgroundTransparency = 1,
				Text = "Teleporting to City Trial...",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
			},

			New "TextLabel" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.55),
				Size = UDim2.fromScale(0.3, 0.03),
				BackgroundTransparency = 1,
				Text = "Prepare your machine!",
				TextColor3 = Color3.fromRGB(180, 180, 200),
				Font = Enum.Font.Gotham,
				TextScaled = true,
			},
		},
	}
end

local function createQueueUI()
	_screenGui = New "ScreenGui" {
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
		Name = "HubQueueUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

		[Children] = {
			createQueueBar(),
			createTeleportOverlay(),
		},
	}

	_trove:Add(_screenGui)
end

local _tickConnection = nil

local function startCountdownTick()
	if _tickConnection then return end

	local RunService = game:GetService("RunService")
	_tickConnection = RunService.Heartbeat:Connect(function()
		local endTime = countdownEndTime:get()
		if endTime then
			local remaining = endTime - os.clock()
			secondsRemaining:set(math.max(0, remaining))
		else
			secondsRemaining:set(0)
		end
	end)
	_trove:Add(_tickConnection)
end

function HubQueueController:KnitInit()
end

function HubQueueController:KnitStart()
	_queueService = Knit.GetService("HubQueueService")

	createQueueUI()
	startCountdownTick()

	_queueService.QueueStateChanged:Connect(function(teleporterId, stateData)
		activeTeleporterId:set(teleporterId)
		queueState:set(stateData.state or "WAITING")
		queueSize:set(stateData.queueSize or 0)
		countdownEndTime:set(stateData.countdownEndTime)
		lastError:set(stateData.lastError)

		if stateData.queueSize and stateData.queueSize > 0 then
			isInQueue:set(true)
		end
	end)

	ReplicaController.ReplicaOfClassCreated("QueueState", function(replica)
		local data = replica.Data
		queueState:set(data.state or "WAITING")
		queueSize:set(data.queueSize or 0)
		countdownEndTime:set(data.countdownEndTime)
		lastError:set(data.lastError)

		replica:ListenToChange({ "state" }, function(newVal)
			queueState:set(newVal)
		end)
		replica:ListenToChange({ "queueSize" }, function(newVal)
			queueSize:set(newVal)
			if newVal > 0 then
				isInQueue:set(true)
			end
		end)
		replica:ListenToChange({ "countdownEndTime" }, function(newVal)
			countdownEndTime:set(newVal)
		end)
		replica:ListenToChange({ "lastError" }, function(newVal)
			lastError:set(newVal)
		end)
	end)
end

function HubQueueController:JoinQueue(teleporterId)
	if _queueService then
		_queueService:JoinQueue(teleporterId)
		activeTeleporterId:set(teleporterId)
		isInQueue:set(true)
	end
end

function HubQueueController:LeaveQueue()
	local tid = activeTeleporterId:get()
	if tid and _queueService then
		_queueService:LeaveQueue(tid)
	end
	isInQueue:set(false)
end

function HubQueueController:Destroy()
	_trove:Destroy()
end

return HubQueueController
