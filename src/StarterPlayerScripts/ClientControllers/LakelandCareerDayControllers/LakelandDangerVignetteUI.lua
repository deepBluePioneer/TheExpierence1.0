local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local HEALTH_PER_HEART = 25
local DISPLAY_ORDER = 90

local LakelandDangerVignetteUI = {}

function LakelandDangerVignetteUI.new(playerGui, gameState, beatIntensity)
	local trove = Trove.new()
	local destroyed = false
	local active = false
	local tweens = {}
	local renderConn = nil

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LakelandDangerVignette"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = DISPLAY_ORDER
	screenGui.Enabled = false
	screenGui.Parent = playerGui
	trove:Add(screenGui)

	-- Four edge gradients forming a vignette frame
	local edges = {}
	local edgeConfigs = {
		{ name = "Top",    pos = UDim2.new(0.5,0,0,0),   size = UDim2.new(1,0,0.25,0), anchor = Vector2.new(0.5,0), rot = 0 },
		{ name = "Bottom", pos = UDim2.new(0.5,0,1,0),   size = UDim2.new(1,0,0.25,0), anchor = Vector2.new(0.5,1), rot = 180 },
		{ name = "Left",   pos = UDim2.new(0,0,0.5,0),   size = UDim2.new(0.18,0,1,0), anchor = Vector2.new(0,0.5), rot = 270 },
		{ name = "Right",  pos = UDim2.new(1,0,0.5,0),   size = UDim2.new(0.18,0,1,0), anchor = Vector2.new(1,0.5), rot = 90 },
	}

	for _, cfg in ipairs(edgeConfigs) do
		local frame = Instance.new("Frame")
		frame.Name = "Edge_" .. cfg.name
		frame.AnchorPoint = cfg.anchor
		frame.Position = cfg.pos
		frame.Size = cfg.size
		frame.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = screenGui

		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 20, 20)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(200, 0, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 0, 0)),
		})
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.5, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Rotation = cfg.rot
		gradient.Parent = frame

		table.insert(edges, frame)
	end

	-- Thin inner border glow
	local innerBorder = Instance.new("Frame")
	innerBorder.Name = "InnerBorder"
	innerBorder.AnchorPoint = Vector2.new(0.5, 0.5)
	innerBorder.Position = UDim2.new(0.5, 0, 0.5, 0)
	innerBorder.Size = UDim2.new(1, -8, 1, -8)
	innerBorder.BackgroundTransparency = 1
	innerBorder.BorderSizePixel = 0
	innerBorder.Parent = screenGui

	local borderStroke = Instance.new("UIStroke")
	borderStroke.Color = Color3.fromRGB(255, 30, 30)
	borderStroke.Thickness = 2
	borderStroke.Transparency = 1
	borderStroke.Parent = innerBorder

	local borderCorner = Instance.new("UICorner")
	borderCorner.CornerRadius = UDim.new(0, 6)
	borderCorner.Parent = innerBorder

	-- Scanline overlay for sci-fi feel
	local scanlines = Instance.new("Frame")
	scanlines.Name = "Scanlines"
	scanlines.AnchorPoint = Vector2.new(0.5, 0.5)
	scanlines.Position = UDim2.new(0.5, 0, 0.5, 0)
	scanlines.Size = UDim2.new(1, 0, 1, 0)
	scanlines.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	scanlines.BackgroundTransparency = 1
	scanlines.BorderSizePixel = 0
	scanlines.Parent = screenGui

	-- "WARNING" corner indicators
	local warningLabels = {}
	local cornerPositions = {
		{ pos = UDim2.new(0.5, 0, 0.95, 0), anchor = Vector2.new(0.5, 1) },
	}
	for _, cp in ipairs(cornerPositions) do
		local lbl = Instance.new("TextLabel")
		lbl.Name = "WarningLabel"
		lbl.AnchorPoint = cp.anchor
		lbl.Position = cp.pos
		lbl.Size = UDim2.new(0, 100, 0, 20)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.Text = "⚠ CRITICAL"
		lbl.TextColor3 = Color3.fromRGB(255, 60, 60)
		lbl.TextScaled = true
		lbl.TextTransparency = 1
		lbl.Parent = screenGui

		local lblStroke = Instance.new("UIStroke")
		lblStroke.Color = Color3.fromRGB(100, 0, 0)
		lblStroke.Thickness = 1
		lblStroke.Transparency = 1
		lblStroke.Parent = lbl

		table.insert(warningLabels, { label = lbl, stroke = lblStroke })
	end

	local function stopTweens()
		for _, tw in ipairs(tweens) do
			tw:Cancel()
		end
		table.clear(tweens)
	end

	local function stopRender()
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
	end

	local function activate()
		if destroyed or active then return end
		active = true
		stopTweens()
		screenGui.Enabled = true

		for _, edge in ipairs(edges) do
			edge.BackgroundTransparency = 1
		end
		borderStroke.Transparency = 1
		scanlines.BackgroundTransparency = 1
		for _, w in ipairs(warningLabels) do
			w.label.TextTransparency = 1
			w.stroke.Transparency = 1
		end

		-- Fade in edges
		for _, edge in ipairs(edges) do
			local tw = TweenService:Create(edge, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0.35,
			})
			tw:Play()
			table.insert(tweens, tw)
		end

		-- Fade in border stroke
		local bTw = TweenService:Create(borderStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 0.4,
		})
		bTw:Play()
		table.insert(tweens, bTw)

		-- Fade in warning labels
		for _, w in ipairs(warningLabels) do
			local tw = TweenService:Create(w.label, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				TextTransparency = 0.1,
			})
			tw:Play()
			table.insert(tweens, tw)

			local stw = TweenService:Create(w.stroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 0.3,
			})
			stw:Play()
			table.insert(tweens, stw)
		end

		-- Beat-reactive render loop for pulsing intensity
		stopRender()
		renderConn = RunService.Heartbeat:Connect(function()
			if destroyed or not active then return end
			local beat = beatIntensity and beatIntensity:get() or 0
			local pulse = 0.5 + math.sin(time() * 4) * 0.15
			local intensity = pulse + beat * 0.3

			for _, edge in ipairs(edges) do
				edge.BackgroundTransparency = math.clamp(1 - intensity, 0.2, 0.85)
			end

			borderStroke.Transparency = math.clamp(0.6 - beat * 0.4 - math.sin(time() * 6) * 0.15, 0.05, 0.8)
			borderStroke.Thickness = 2 + beat * 3

			scanlines.BackgroundTransparency = math.clamp(0.97 - beat * 0.04, 0.92, 1)

			local warnAlpha = 0.5 + math.sin(time() * 3.5) * 0.4
			for _, w in ipairs(warningLabels) do
				w.label.TextTransparency = math.clamp(1 - warnAlpha, 0, 0.8)
				w.stroke.Transparency = math.clamp(1 - warnAlpha * 0.5, 0.3, 1)
			end
		end)
	end

	local function deactivate()
		if destroyed or not active then return end
		active = false
		stopTweens()
		stopRender()

		for _, edge in ipairs(edges) do
			local tw = TweenService:Create(edge, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			})
			tw:Play()
			table.insert(tweens, tw)
		end

		local bTw = TweenService:Create(borderStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Transparency = 1,
		})
		bTw:Play()
		table.insert(tweens, bTw)

		for _, w in ipairs(warningLabels) do
			local tw = TweenService:Create(w.label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
			})
			tw:Play()
			table.insert(tweens, tw)
		end

		local slTw = TweenService:Create(scanlines, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})
		slTw:Play()
		table.insert(tweens, slTw)

		slTw.Completed:Once(function()
			if not active then
				screenGui.Enabled = false
			end
		end)
	end

	-- Connect to race controller health changes
	local raceController = nil
	local connections = {}

	local function onHealthChanged(health)
		local state = gameState:get()
		if state ~= "PLAYING" then
			deactivate()
			return
		end
		if health > 0 and health <= HEALTH_PER_HEART then
			activate()
		else
			deactivate()
		end
	end

	local function bind()
		raceController = Knit.GetController("LakelandRaceController")
		table.insert(connections, raceController.HealthChanged:Connect(onHealthChanged))
	end

	task.spawn(bind)

	local function reset()
		deactivate()
	end

	local function destroy()
		destroyed = true
		stopTweens()
		stopRender()
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		connections = {}
		trove:Destroy()
	end

	return {
		reset = reset,
		destroy = destroy,
	}
end

return LakelandDangerVignetteUI
