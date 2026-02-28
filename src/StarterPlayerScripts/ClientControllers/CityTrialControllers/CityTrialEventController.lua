local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Shake = require(Packages.Shake)

local CustomPackages = ReplicatedStorage.CustomPackages
local Fusion = require(CustomPackages.FusionRoot.Fusion)
local ReplicaController = require(CustomPackages.Replica.ReplicaController)

local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed
local Children = Fusion.Children
local Spring = Fusion.Spring

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local CityTrialEventController = Knit.CreateController {
	Name = "CityTrialEventController",
}

local _trove = Trove.new()
local _eventService = nil

local activeWarning = Value(nil)
local activeEvents = Value({})

----------------------------------------------------------------
-- Warning banner (center screen, brief flash)
----------------------------------------------------------------

local function createWarningBanner()
	local warningText = Computed(function()
		local w = activeWarning:get()
		return w and ("⚠ " .. w.name .. " INCOMING! ⚠") or ""
	end)

	local warningVisible = Computed(function()
		return activeWarning:get() ~= nil
	end)

	return New "ScreenGui" {
		Name = "EventWarningGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),

		[Children] = {
			New "Frame" {
				Name = "WarningBanner",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.12),
				Size = UDim2.fromScale(0.5, 0.08),
				BackgroundColor3 = Color3.fromRGB(180, 40, 40),
				BackgroundTransparency = Spring(Computed(function()
					return warningVisible:get() and 0.15 or 1
				end), 25),

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0, 12) },
					New "UIStroke" {
						Color = Color3.fromRGB(255, 80, 80),
						Thickness = 2,
						Transparency = Spring(Computed(function()
							return warningVisible:get() and 0 or 1
						end), 25),
					},
					New "TextLabel" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = warningText,
						TextColor3 = Color3.new(1, 1, 1),
						TextScaled = true,
						Font = Enum.Font.GothamBold,
						TextTransparency = Spring(Computed(function()
							return warningVisible:get() and 0 or 1
						end), 25),
					},
				},
			},
		},
	}
end

----------------------------------------------------------------
-- Active events sidebar (shows ongoing events with timers)
----------------------------------------------------------------

local function createActiveEventsPanel()
	local eventEntries = Computed(function()
		local events = activeEvents:get()
		local children = {}

		children["Layout"] = New "UIListLayout" {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}

		local order = 0
		for eventId, info in pairs(events) do
			order = order + 1
			children["Event_" .. eventId] = New "Frame" {
				Name = eventId,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Color3.fromRGB(30, 30, 40),
				BackgroundTransparency = 0.3,
				LayoutOrder = order,

				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0, 8) },
					New "UIPadding" {
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
					},
					New "TextLabel" {
						Size = UDim2.new(1, 0, 0, 18),
						BackgroundTransparency = 1,
						Text = info.displayName or eventId,
						TextColor3 = Color3.fromRGB(255, 200, 80),
						TextScaled = true,
						Font = Enum.Font.GothamBold,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					New "TextLabel" {
						Size = UDim2.new(1, 0, 0, 14),
						Position = UDim2.new(0, 0, 0, 18),
						BackgroundTransparency = 1,
						Text = string.format("%.0fs remaining", math.max(0, info.remaining or 0)),
						TextColor3 = Color3.fromRGB(200, 200, 200),
						TextScaled = true,
						Font = Enum.Font.Gotham,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
				},
			}
		end

		return children
	end)

	return New "ScreenGui" {
		Name = "EventActiveGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 15,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),

		[Children] = {
			New "Frame" {
				Name = "ActiveEventsList",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(0.98, 0.25),
				Size = UDim2.fromScale(0.18, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,

				[Children] = eventEntries,
			},
		},
	}
end

----------------------------------------------------------------
-- Camera shake helper
----------------------------------------------------------------

local _shakeInstance = nil

local function triggerCameraShake(intensity, duration)
	if not _shakeInstance then
		_shakeInstance = Shake.new()
	end

	_shakeInstance.FadeInTime = 0
	_shakeInstance.FadeOutTime = duration * 0.6
	_shakeInstance.Frequency = 0.1
	_shakeInstance.Amplitude = intensity
	_shakeInstance.RotationInfluence = Vector3.new(0.2, 0.2, 0.2)

	_shakeInstance:Start()
	_shakeInstance:BindToRenderStep(Shake.NextRenderName(), Enum.RenderPriority.Last.Value, function(pos, rot)
		Camera.CFrame = Camera.CFrame * CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z)
	end)

	task.delay(duration, function()
		if _shakeInstance then
			_shakeInstance:Stop()
		end
	end)
end

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

function CityTrialEventController:KnitInit()
	print("[CityTrialEventController] KnitInit")
end

function CityTrialEventController:KnitStart()
	_eventService = Knit.GetService("CityTrialEventService")

	-- Warning signal
	_trove:Add(_eventService.EventWarning:Connect(function(eventId, displayName, warningSeconds)
		activeWarning:set({ id = eventId, name = displayName })
		task.delay(warningSeconds + 0.5, function()
			local current = activeWarning:get()
			if current and current.id == eventId then
				activeWarning:set(nil)
			end
		end)
	end), "Disconnect")

	-- Event started
	_trove:Add(_eventService.EventStarted:Connect(function(eventId, displayName, duration)
		local current = table.clone(activeEvents:get())
		current[eventId] = {
			displayName = displayName,
			remaining = duration,
			startedAt = os.clock(),
			duration = duration,
		}
		activeEvents:set(current)

		-- Shake for impact events
		if eventId == "meteor_shower" then
			triggerCameraShake(0.5, 1.0)
		elseif eventId == "shockwave" then
			triggerCameraShake(1.5, 0.8)
		end
	end), "Disconnect")

	-- Event ended
	_trove:Add(_eventService.EventEnded:Connect(function(eventId)
		local current = table.clone(activeEvents:get())
		current[eventId] = nil
		activeEvents:set(current)
	end), "Disconnect")

	-- Periodic refresh of remaining timers
	task.spawn(function()
		while true do
			task.wait(1)
			local current = activeEvents:get()
			local hasAny = false
			local updated = {}
			for eventId, info in pairs(current) do
				hasAny = true
				local elapsed = os.clock() - info.startedAt
				updated[eventId] = {
					displayName = info.displayName,
					remaining = math.max(0, info.duration - elapsed),
					startedAt = info.startedAt,
					duration = info.duration,
				}
			end
			if hasAny then
				activeEvents:set(updated)
			end
		end
	end)

	-- Build UI
	_trove:Add(createWarningBanner())
	_trove:Add(createActiveEventsPanel())

	print("[CityTrialEventController] KnitStart -- Event UI ready")
end

return CityTrialEventController
