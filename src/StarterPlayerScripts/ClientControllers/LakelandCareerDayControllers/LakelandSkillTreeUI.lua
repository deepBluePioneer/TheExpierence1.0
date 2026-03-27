local TweenService = game:GetService("TweenService")

local BG_PANEL       = Color3.fromRGB(8, 14, 28)
local BORDER_CYAN    = Color3.fromRGB(0, 140, 200)
local BORDER_LOCKED  = Color3.fromRGB(40, 50, 70)
local TEXT_BRIGHT    = Color3.fromRGB(220, 235, 255)
local TEXT_DIM       = Color3.fromRGB(70, 100, 140)
local LINE_UNLOCKED  = Color3.fromRGB(0, 180, 255)
local LINE_LOCKED    = Color3.fromRGB(50, 60, 80)
local NODE_BG_UNLOCK = Color3.fromRGB(12, 22, 42)
local NODE_BG_LOCK   = Color3.fromRGB(16, 18, 26)
local SELECTED_WHITE = Color3.fromRGB(255, 255, 255)
local LOCKED_RED     = Color3.fromRGB(255, 60, 60)
local BUTTON_GLOW    = Color3.fromRGB(0, 200, 255)

local NODE_W = 0.1
local NODE_H = 0.055
local TIER_Y = { [0] = 0.15, [1] = 0.45, [2] = 0.75 }

local SKILL_NODES = {
	{ id = "core",       name = "CORE",           tier = 0, x = 0.5,  unlocked = true,  children = {"speed","shield","magnet"} },
	{ id = "speed",      name = "SPEED+",         tier = 1, x = 0.2,  unlocked = false, children = {"boost","handling"} },
	{ id = "shield",     name = "SHIELD+",        tier = 1, x = 0.5,  unlocked = false, children = {"armor","regen"} },
	{ id = "magnet",     name = "COIN MAGNET",    tier = 1, x = 0.8,  unlocked = false, children = {"multiplier","combo"} },
	{ id = "boost",      name = "BOOST DURATION", tier = 2, x = 0.1,  unlocked = false, children = {} },
	{ id = "handling",   name = "HANDLING",        tier = 2, x = 0.3,  unlocked = false, children = {} },
	{ id = "armor",      name = "ARMOR",           tier = 2, x = 0.4,  unlocked = false, children = {} },
	{ id = "regen",      name = "REGEN",           tier = 2, x = 0.6,  unlocked = false, children = {} },
	{ id = "multiplier", name = "SCORE x2",        tier = 2, x = 0.7,  unlocked = false, children = {} },
	{ id = "combo",      name = "COMBO EXTEND",    tier = 2, x = 0.9,  unlocked = false, children = {} },
}

local function buildLookup()
	local map = {}
	for _, node in ipairs(SKILL_NODES) do
		map[node.id] = node
	end
	return map
end

local function makeSegment(parent, color, transparency, zIndex)
	local f = Instance.new("Frame")
	f.Name = "ConnSeg"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.ZIndex = zIndex
	f.Parent = parent
	return f
end

local function layoutSegH(frame, pw, ph, x1, x2, y, thick)
	local left = math.min(x1, x2) * pw
	local right = math.max(x1, x2) * pw
	local cy = y * ph
	frame.Position = UDim2.fromOffset((left + right) / 2, cy)
	frame.Size = UDim2.fromOffset(right - left + thick, thick)
end

local function layoutSegV(frame, pw, ph, x, y1, y2, thick)
	local top = math.min(y1, y2) * ph
	local bot = math.max(y1, y2) * ph
	local cx = x * pw
	frame.Position = UDim2.fromOffset(cx, (top + bot) / 2)
	frame.Size = UDim2.fromOffset(thick, bot - top + thick)
end

local LakelandSkillTreeUI = {}

function LakelandSkillTreeUI.new(playerGui)
	local lookup = buildLookup()
	local selectedId = nil
	local nodeFrames = {}
	local lineFrames = {}

	-- Button ScreenGui
	local buttonGui = Instance.new("ScreenGui")
	buttonGui.Name = "LakelandSkillTreeButton"
	buttonGui.ResetOnSpawn = false
	buttonGui.IgnoreGuiInset = true
	buttonGui.DisplayOrder = 60
	buttonGui.Enabled = false
	buttonGui.Parent = playerGui

	local btn = Instance.new("TextButton")
	btn.Name = "SkillsBtn"
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.fromScale(0.5, 1.1)
	btn.Size = UDim2.fromScale(0.12, 0.045)
	btn.BackgroundColor3 = BG_PANEL
	btn.BackgroundTransparency = 0.1
	btn.Text = "SKILLS"
	btn.TextColor3 = BUTTON_GLOW
	btn.Font = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.ZIndex = 2
	btn.Parent = buttonGui

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0.35, 0)
	btnCorner.Parent = btn

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = BUTTON_GLOW
	btnStroke.Thickness = 2
	btnStroke.Transparency = 0.2
	btnStroke.Parent = btn

	local btnPad = Instance.new("UIPadding")
	btnPad.PaddingTop = UDim.new(0.1, 0)
	btnPad.PaddingBottom = UDim.new(0.1, 0)
	btnPad.Parent = btn

	-- Window ScreenGui
	local windowGui = Instance.new("ScreenGui")
	windowGui.Name = "LakelandSkillTreeWindow"
	windowGui.ResetOnSpawn = false
	windowGui.IgnoreGuiInset = true
	windowGui.DisplayOrder = 70
	windowGui.Enabled = false
	windowGui.Parent = playerGui

	-- Backdrop (click to close)
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.ZIndex = 1
	backdrop.Parent = windowGui

	-- Main panel
	local panel = Instance.new("Frame")
	panel.Name = "TreePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.7, 0.7)
	panel.BackgroundColor3 = BG_PANEL
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.ZIndex = 2
	panel.Parent = windowGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0.02, 0)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = BORDER_CYAN
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.15
	panelStroke.Parent = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.02)
	title.Size = UDim2.fromScale(0.4, 0.06)
	title.BackgroundTransparency = 1
	title.Text = "SKILL TREE"
	title.TextColor3 = TEXT_BRIGHT
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.ZIndex = 3
	title.Parent = panel

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.fromScale(0.98, 0.015)
	closeBtn.Size = UDim2.fromScale(0.05, 0.06)
	closeBtn.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
	closeBtn.BackgroundTransparency = 0.4
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextScaled = true
	closeBtn.BorderSizePixel = 0
	closeBtn.AutoButtonColor = false
	closeBtn.ZIndex = 4
	closeBtn.Parent = panel

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0.25, 0)
	closeBtnCorner.Parent = closeBtn

	local closeBtnStroke = Instance.new("UIStroke")
	closeBtnStroke.Color = Color3.fromRGB(255, 80, 80)
	closeBtnStroke.Thickness = 1
	closeBtnStroke.Transparency = 0.5
	closeBtnStroke.Parent = closeBtn

	-- Node area (offset below title)
	local nodeArea = Instance.new("Frame")
	nodeArea.Name = "NodeArea"
	nodeArea.AnchorPoint = Vector2.new(0.5, 0.5)
	nodeArea.Position = UDim2.fromScale(0.5, 0.55)
	nodeArea.Size = UDim2.fromScale(0.92, 0.82)
	nodeArea.BackgroundTransparency = 1
	nodeArea.BorderSizePixel = 0
	nodeArea.ZIndex = 3
	nodeArea.Parent = panel

	-- Create grid-style connection segments (vertical-horizontal-vertical)
	for _, node in ipairs(SKILL_NODES) do
		local fromX = node.x
		local fromY = TIER_Y[node.tier] + NODE_H / 2
		for _, childId in ipairs(node.children) do
			local child = lookup[childId]
			if child then
				local toX = child.x
				local toY = TIER_Y[child.tier] - NODE_H / 2
				local midY = (fromY + toY) / 2
				local isUnlocked = node.unlocked and child.unlocked
				local color = isUnlocked and LINE_UNLOCKED or LINE_LOCKED
				local thick = isUnlocked and 3 or 2
				local trans = isUnlocked and 0.05 or 0.4
				local glowTrans = 0.82

				local segV1 = makeSegment(nodeArea, color, trans, 2)
				local segH  = makeSegment(nodeArea, color, trans, 2)
				local segV2 = makeSegment(nodeArea, color, trans, 2)

				local glowV1, glowH, glowV2
				if isUnlocked then
					glowV1 = makeSegment(nodeArea, color, glowTrans, 1)
					glowH  = makeSegment(nodeArea, color, glowTrans, 1)
					glowV2 = makeSegment(nodeArea, color, glowTrans, 1)
				end

				table.insert(lineFrames, {
					segV1 = segV1, segH = segH, segV2 = segV2,
					glowV1 = glowV1, glowH = glowH, glowV2 = glowV2,
					fromX = fromX, fromY = fromY, toX = toX, toY = toY, midY = midY,
					thick = thick, glowThick = 10,
				})
			end
		end
	end

	local function layoutAllLines()
		local absSize = nodeArea.AbsoluteSize
		if absSize.X < 1 or absSize.Y < 1 then return end
		local pw, ph = absSize.X, absSize.Y
		for _, info in ipairs(lineFrames) do
			local t = info.thick
			local gt = info.glowThick
			layoutSegV(info.segV1, pw, ph, info.fromX, info.fromY, info.midY, t)
			layoutSegH(info.segH, pw, ph, info.fromX, info.toX, info.midY, t)
			layoutSegV(info.segV2, pw, ph, info.toX, info.midY, info.toY, t)
			if info.glowV1 then
				layoutSegV(info.glowV1, pw, ph, info.fromX, info.fromY, info.midY, gt)
				layoutSegH(info.glowH, pw, ph, info.fromX, info.toX, info.midY, gt)
				layoutSegV(info.glowV2, pw, ph, info.toX, info.midY, info.toY, gt)
			end
		end
	end

	nodeArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutAllLines)
	task.defer(layoutAllLines)

	-- Locked tooltip
	local tooltip = Instance.new("TextLabel")
	tooltip.Name = "LockedTooltip"
	tooltip.AnchorPoint = Vector2.new(0.5, 1)
	tooltip.Size = UDim2.fromScale(0.12, 0.045)
	tooltip.BackgroundColor3 = Color3.fromRGB(30, 10, 10)
	tooltip.BackgroundTransparency = 0.2
	tooltip.Text = "LOCKED"
	tooltip.TextColor3 = LOCKED_RED
	tooltip.Font = Enum.Font.GothamBold
	tooltip.TextScaled = true
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 10
	tooltip.Parent = nodeArea

	local tooltipCorner = Instance.new("UICorner")
	tooltipCorner.CornerRadius = UDim.new(0.3, 0)
	tooltipCorner.Parent = tooltip

	local tooltipStroke = Instance.new("UIStroke")
	tooltipStroke.Color = LOCKED_RED
	tooltipStroke.Thickness = 1
	tooltipStroke.Transparency = 0.5
	tooltipStroke.Parent = tooltip

	-- Build node frames
	for _, node in ipairs(SKILL_NODES) do
		local isUnlocked = node.unlocked
		local cx = node.x
		local cy = TIER_Y[node.tier]

		local frame = Instance.new("TextButton")
		frame.Name = "Node_" .. node.id
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(cx, cy)
		frame.Size = UDim2.fromScale(NODE_W, NODE_H)
		frame.BackgroundColor3 = isUnlocked and NODE_BG_UNLOCK or NODE_BG_LOCK
		frame.BackgroundTransparency = 0.1
		frame.Text = ""
		frame.BorderSizePixel = 0
		frame.AutoButtonColor = false
		frame.ZIndex = 5
		frame.Parent = nodeArea

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = frame

		local stroke = Instance.new("UIStroke")
		stroke.Color = isUnlocked and BORDER_CYAN or BORDER_LOCKED
		stroke.Thickness = isUnlocked and 2 or 1
		stroke.Transparency = 0.15
		stroke.Parent = frame

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.9, 0.7)
		label.BackgroundTransparency = 1
		label.Text = node.name
		label.TextColor3 = isUnlocked and TEXT_BRIGHT or TEXT_DIM
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.ZIndex = 6
		label.Parent = frame

		local labelConstraint = Instance.new("UITextSizeConstraint")
		labelConstraint.MaxTextSize = 14
		labelConstraint.Parent = label

		if isUnlocked then
			local glow = Instance.new("Frame")
			glow.Name = "Glow"
			glow.AnchorPoint = Vector2.new(0.5, 0.5)
			glow.Position = UDim2.fromScale(0.5, 0.5)
			glow.Size = UDim2.fromScale(1.15, 1.4)
			glow.BackgroundColor3 = BORDER_CYAN
			glow.BackgroundTransparency = 0.92
			glow.BorderSizePixel = 0
			glow.ZIndex = 4
			glow.Parent = frame

			local glowCorner = Instance.new("UICorner")
			glowCorner.CornerRadius = UDim.new(0.25, 0)
			glowCorner.Parent = glow
		end

		frame.MouseButton1Click:Connect(function()
			if isUnlocked then
				if selectedId == node.id then
					selectedId = nil
					stroke.Color = BORDER_CYAN
					stroke.Thickness = 2
				else
					if selectedId and nodeFrames[selectedId] then
						local prev = nodeFrames[selectedId]
						local prevNode = lookup[selectedId]
						local prevStroke = prev:FindFirstChildOfClass("UIStroke")
						if prevStroke then
							prevStroke.Color = prevNode.unlocked and BORDER_CYAN or BORDER_LOCKED
							prevStroke.Thickness = prevNode.unlocked and 2 or 1
						end
					end
					selectedId = node.id
					stroke.Color = SELECTED_WHITE
					stroke.Thickness = 3
					TweenService:Create(stroke, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Thickness = 2.5 }):Play()
				end
			else
				tooltip.Position = UDim2.fromScale(cx, cy - NODE_H / 2 - 0.01)
				tooltip.Visible = true
				tooltip.TextTransparency = 0
				tooltip.BackgroundTransparency = 0.2
				task.delay(0.8, function()
					if tooltip.Visible then
						local tw = TweenService:Create(tooltip, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							TextTransparency = 1,
							BackgroundTransparency = 1,
						})
						tw:Play()
						tw.Completed:Once(function()
							tooltip.Visible = false
						end)
					end
				end)
			end
		end)

		nodeFrames[node.id] = frame
	end

	-- Close window
	local function closeWindow()
		local tw = TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.fromScale(0.65, 0.65),
			BackgroundTransparency = 0.5,
		})
		tw:Play()
		TweenService:Create(backdrop, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
		tw.Completed:Once(function()
			windowGui.Enabled = false
			panel.Size = UDim2.fromScale(0.7, 0.7)
			panel.BackgroundTransparency = 0.05
			backdrop.BackgroundTransparency = 0.5
		end)
	end

	local function openWindow()
		windowGui.Enabled = true
		panel.Size = UDim2.fromScale(0.6, 0.6)
		panel.BackgroundTransparency = 0.3
		TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(0.7, 0.7),
			BackgroundTransparency = 0.05,
		}):Play()
		TweenService:Create(backdrop, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.5,
		}):Play()
	end

	closeBtn.MouseButton1Click:Connect(closeWindow)
	backdrop.MouseButton1Click:Connect(closeWindow)

	btn.MouseButton1Click:Connect(function()
		if windowGui.Enabled then
			closeWindow()
		else
			openWindow()
		end
	end)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btnStroke, TweenInfo.new(0.15), { Thickness = 3, Transparency = 0 }):Play()
		TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = 0 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btnStroke, TweenInfo.new(0.15), { Thickness = 2, Transparency = 0.2 }):Play()
		TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = 0.1 }):Play()
	end)

	closeBtn.MouseEnter:Connect(function()
		TweenService:Create(closeBtn, TweenInfo.new(0.12), { BackgroundTransparency = 0.1 }):Play()
	end)
	closeBtn.MouseLeave:Connect(function()
		TweenService:Create(closeBtn, TweenInfo.new(0.12), { BackgroundTransparency = 0.4 }):Play()
	end)

	-- Public API
	local api = {}

	function api.show()
		buttonGui.Enabled = true
		btn.Position = UDim2.fromScale(0.5, 1.1)
		TweenService:Create(btn, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.96),
		}):Play()
	end

	function api.hide()
		if windowGui.Enabled then
			windowGui.Enabled = false
		end
		if buttonGui.Enabled then
			TweenService:Create(btn, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromScale(0.5, 1.1),
			}):Play()
			task.delay(0.3, function()
				buttonGui.Enabled = false
			end)
		end
		panel.Size = UDim2.fromScale(0.7, 0.7)
		panel.BackgroundTransparency = 0.05
		backdrop.BackgroundTransparency = 0.5
	end

	function api.destroy()
		windowGui:Destroy()
		buttonGui:Destroy()
	end

	return api
end

return LakelandSkillTreeUI
