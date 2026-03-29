local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local BiomeConfig = require(ReplicatedStorage.Source.BiomeConfig)

local BG_DEEP      = Color3.fromRGB(4, 6, 16)
local BG_PANEL     = Color3.fromRGB(8, 14, 28)
local BORDER_CYAN  = Color3.fromRGB(0, 180, 255)
local TEXT_BRIGHT  = Color3.fromRGB(220, 235, 255)
local TEXT_DIM     = Color3.fromRGB(90, 120, 160)
local RING_DIM     = Color3.fromRGB(20, 35, 60)
local SELECTED_GLOW = Color3.fromRGB(0, 220, 255)

local PLANET_DATA = {}
for i, biome in ipairs(BiomeConfig.Biomes) do
	table.insert(PLANET_DATA, {
		id = i,
		name = string.upper(biome.name),
		tagline = biome.tagline or biome.description or "",
		color = biome.planetColor or biome.accentColor,
		accent = biome.accentColor,
		orbitRadius = biome.orbit and biome.orbit.radius or (0.18 + i * 0.03),
		orbitAngle = biome.orbit and biome.orbit.angle or (math.rad(72 * i)),
	})
end

local STAR_COUNT     = 120
local ORBIT_SPEED    = 0.08
local PLANET_SIZE    = UDim2.fromScale(0.065, 0.065)
local SUN_SIZE       = UDim2.fromScale(0.06, 0.06)

local LakelandGalacticMapUI = {}

local function createStar(parent)
	local star = Instance.new("Frame")
	star.Name = "Star"
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	local sz = 1 + math.random() * 2
	star.Size = UDim2.fromOffset(sz, sz)
	star.Position = UDim2.fromScale(math.random(), math.random())
	star.BackgroundColor3 = Color3.new(1, 1, 1)
	star.BackgroundTransparency = 0.3 + math.random() * 0.5
	star.BorderSizePixel = 0
	star.ZIndex = 1
	star.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = star
	return star
end

local function createOrbitRing(parent, radiusFrac)
	local ring = Instance.new("Frame")
	ring.Name = "Orbit"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(radiusFrac * 2, radiusFrac * 2)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.ZIndex = 2
	ring.Parent = parent
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = RING_DIM
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = ring
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	return ring
end

function LakelandGalacticMapUI.new(playerGui)
	local selectedIndex = nil
	local planetFrames = {}
	local planetGlows = {}
	local starFrames = {}
	local onConfirm = nil
	local renderConn = nil
	local orbitTime = 0
	local visible = false
	local infoLabels = {}

	local sg = Instance.new("ScreenGui")
	sg.Name = "LakelandGalacticMap"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 70
	sg.Enabled = false
	sg.Parent = playerGui

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = BG_DEEP
	bg.BackgroundTransparency = 0.15
	bg.BorderSizePixel = 0
	bg.ZIndex = 0
	bg.Parent = sg

	for _ = 1, STAR_COUNT do
		table.insert(starFrames, createStar(bg))
	end

	local mapFrame = Instance.new("Frame")
	mapFrame.Name = "MapFrame"
	mapFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mapFrame.Position = UDim2.fromScale(0.5, 0.48)
	mapFrame.Size = UDim2.fromScale(0.75, 0.85)
	mapFrame.BackgroundTransparency = 1
	mapFrame.BorderSizePixel = 0
	mapFrame.ZIndex = 3
	mapFrame.Parent = sg

	local mapAspect = Instance.new("UIAspectRatioConstraint")
	mapAspect.AspectRatio = 1
	mapAspect.DominantAxis = Enum.DominantAxis.Height
	mapAspect.Parent = mapFrame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.fromScale(0.5, 0.01)
	titleLabel.Size = UDim2.fromScale(0.6, 0.06)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "G A L A C T I C   M A P"
	titleLabel.TextColor3 = BORDER_CYAN
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.ZIndex = 10
	titleLabel.Parent = mapFrame

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.AnchorPoint = Vector2.new(0.5, 0)
	subtitleLabel.Position = UDim2.fromScale(0.5, 0.07)
	subtitleLabel.Size = UDim2.fromScale(0.5, 0.035)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Text = "SELECT YOUR DESTINATION"
	subtitleLabel.TextColor3 = TEXT_DIM
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextScaled = true
	subtitleLabel.ZIndex = 10
	subtitleLabel.Parent = mapFrame

	local uniqueRadii = {}
	for _, pd in ipairs(PLANET_DATA) do
		local found = false
		for _, r in ipairs(uniqueRadii) do
			if math.abs(r - pd.orbitRadius) < 0.001 then found = true; break end
		end
		if not found then table.insert(uniqueRadii, pd.orbitRadius) end
	end
	for _, r in ipairs(uniqueRadii) do
		createOrbitRing(mapFrame, r)
	end

	local sun = Instance.new("Frame")
	sun.Name = "Sun"
	sun.AnchorPoint = Vector2.new(0.5, 0.5)
	sun.Position = UDim2.fromScale(0.5, 0.5)
	sun.Size = SUN_SIZE
	sun.BackgroundColor3 = Color3.fromRGB(255, 220, 100)
	sun.BackgroundTransparency = 0
	sun.BorderSizePixel = 0
	sun.ZIndex = 5
	sun.Parent = mapFrame
	local sunCorner = Instance.new("UICorner")
	sunCorner.CornerRadius = UDim.new(1, 0)
	sunCorner.Parent = sun
	local sunAspect = Instance.new("UIAspectRatioConstraint")
	sunAspect.AspectRatio = 1
	sunAspect.Parent = sun
	local sunGlow = Instance.new("UIStroke")
	sunGlow.Color = Color3.fromRGB(255, 200, 50)
	sunGlow.Thickness = 3
	sunGlow.Transparency = 0.3
	sunGlow.Parent = sun

	local sunLabel = Instance.new("TextLabel")
	sunLabel.Name = "SunLabel"
	sunLabel.AnchorPoint = Vector2.new(0.5, 0)
	sunLabel.Position = UDim2.fromScale(0.5, 1.15)
	sunLabel.Size = UDim2.fromScale(2, 0.4)
	sunLabel.BackgroundTransparency = 1
	sunLabel.Text = "SOL"
	sunLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
	sunLabel.Font = Enum.Font.GothamBold
	sunLabel.TextScaled = true
	sunLabel.ZIndex = 6
	sunLabel.Parent = sun

	for i, pd in ipairs(PLANET_DATA) do
		local planetBtn = Instance.new("TextButton")
		planetBtn.Name = "Planet_" .. pd.name
		planetBtn.AnchorPoint = Vector2.new(0.5, 0.5)
		planetBtn.Position = UDim2.fromScale(0.5, 0.5)
		planetBtn.Size = PLANET_SIZE
		planetBtn.BackgroundColor3 = pd.color
		planetBtn.BackgroundTransparency = 0
		planetBtn.BorderSizePixel = 0
		planetBtn.Text = ""
		planetBtn.AutoButtonColor = false
		planetBtn.ZIndex = 8
		planetBtn.Parent = mapFrame

		local pCorner = Instance.new("UICorner")
		pCorner.CornerRadius = UDim.new(1, 0)
		pCorner.Parent = planetBtn

		local pAspect = Instance.new("UIAspectRatioConstraint")
		pAspect.AspectRatio = 1
		pAspect.Parent = planetBtn

		local pStroke = Instance.new("UIStroke")
		pStroke.Color = pd.accent
		pStroke.Thickness = 2
		pStroke.Transparency = 0.4
		pStroke.Parent = planetBtn

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PlanetName"
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.Position = UDim2.fromScale(0.5, 1.2)
		nameLabel.Size = UDim2.fromScale(3, 0.35)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = pd.name
		nameLabel.TextColor3 = TEXT_BRIGHT
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.ZIndex = 9
		nameLabel.Parent = planetBtn

		planetBtn.MouseEnter:Connect(function()
			if selectedIndex == i then return end
			TweenService:Create(pStroke, TweenInfo.new(0.15), { Thickness = 3, Transparency = 0.1 }):Play()
			TweenService:Create(planetBtn, TweenInfo.new(0.15), {
				Size = UDim2.fromScale(PLANET_SIZE.X.Scale * 1.2, PLANET_SIZE.Y.Scale * 1.2),
			}):Play()
		end)

		planetBtn.MouseLeave:Connect(function()
			if selectedIndex == i then return end
			TweenService:Create(pStroke, TweenInfo.new(0.15), { Thickness = 2, Transparency = 0.4 }):Play()
			TweenService:Create(planetBtn, TweenInfo.new(0.15), { Size = PLANET_SIZE }):Play()
		end)

		planetBtn.MouseButton1Click:Connect(function()
			local prev = selectedIndex
			selectedIndex = i

			if prev and prev ~= i and planetGlows[prev] then
				local oldBtn = planetFrames[prev]
				local oldStroke = oldBtn:FindFirstChildOfClass("UIStroke")
				local oldPd = PLANET_DATA[prev]
				TweenService:Create(oldStroke, TweenInfo.new(0.2), {
					Thickness = 2, Transparency = 0.4, Color = oldPd.accent,
				}):Play()
				TweenService:Create(oldBtn, TweenInfo.new(0.2), { Size = PLANET_SIZE }):Play()
			end

			TweenService:Create(pStroke, TweenInfo.new(0.2), {
				Thickness = 4, Transparency = 0, Color = SELECTED_GLOW,
			}):Play()
			TweenService:Create(planetBtn, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(PLANET_SIZE.X.Scale * 1.3, PLANET_SIZE.Y.Scale * 1.3),
			}):Play()

			infoLabels.name.Text = pd.name
			infoLabels.tagline.Text = pd.tagline
			infoLabels.name.TextColor3 = pd.accent
			infoLabels.panel.Visible = true

			local confirmBtn = infoLabels.confirmBtn
			if confirmBtn then
				confirmBtn.Visible = true
				TweenService:Create(confirmBtn, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(0.5, 0.93),
				}):Play()
			end
		end)

		planetFrames[i] = planetBtn
		planetGlows[i] = pStroke
	end

	local infoPanel = Instance.new("Frame")
	infoPanel.Name = "InfoPanel"
	infoPanel.AnchorPoint = Vector2.new(0.5, 1)
	infoPanel.Position = UDim2.fromScale(0.5, 0.87)
	infoPanel.Size = UDim2.fromScale(0.35, 0.08)
	infoPanel.BackgroundColor3 = BG_PANEL
	infoPanel.BackgroundTransparency = 0.15
	infoPanel.BorderSizePixel = 0
	infoPanel.ZIndex = 10
	infoPanel.Visible = false
	infoPanel.Parent = mapFrame

	local infoPanelCorner = Instance.new("UICorner")
	infoPanelCorner.CornerRadius = UDim.new(0.2, 0)
	infoPanelCorner.Parent = infoPanel

	local infoPanelStroke = Instance.new("UIStroke")
	infoPanelStroke.Color = BORDER_CYAN
	infoPanelStroke.Thickness = 1
	infoPanelStroke.Transparency = 0.3
	infoPanelStroke.Parent = infoPanel

	local infoName = Instance.new("TextLabel")
	infoName.Name = "InfoName"
	infoName.AnchorPoint = Vector2.new(0.5, 0)
	infoName.Position = UDim2.fromScale(0.5, 0.1)
	infoName.Size = UDim2.fromScale(0.9, 0.45)
	infoName.BackgroundTransparency = 1
	infoName.Text = ""
	infoName.TextColor3 = TEXT_BRIGHT
	infoName.Font = Enum.Font.GothamBold
	infoName.TextScaled = true
	infoName.ZIndex = 11
	infoName.Parent = infoPanel

	local infoTag = Instance.new("TextLabel")
	infoTag.Name = "InfoTagline"
	infoTag.AnchorPoint = Vector2.new(0.5, 0)
	infoTag.Position = UDim2.fromScale(0.5, 0.55)
	infoTag.Size = UDim2.fromScale(0.9, 0.35)
	infoTag.BackgroundTransparency = 1
	infoTag.Text = ""
	infoTag.TextColor3 = TEXT_DIM
	infoTag.Font = Enum.Font.Gotham
	infoTag.TextScaled = true
	infoTag.ZIndex = 11
	infoTag.Parent = infoPanel

	infoLabels.name = infoName
	infoLabels.tagline = infoTag
	infoLabels.panel = infoPanel

	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Name = "ConfirmBtn"
	confirmBtn.AnchorPoint = Vector2.new(0.5, 1)
	confirmBtn.Position = UDim2.fromScale(0.5, 1.1)
	confirmBtn.Size = UDim2.fromScale(0.24, 0.055)
	confirmBtn.BackgroundColor3 = BG_PANEL
	confirmBtn.BackgroundTransparency = 0.1
	confirmBtn.Text = "ENGAGE HYPERDRIVE"
	confirmBtn.TextColor3 = BORDER_CYAN
	confirmBtn.Font = Enum.Font.GothamBold
	confirmBtn.TextScaled = true
	confirmBtn.BorderSizePixel = 0
	confirmBtn.AutoButtonColor = false
	confirmBtn.ZIndex = 12
	confirmBtn.Visible = false
	confirmBtn.Parent = mapFrame
	infoLabels.confirmBtn = confirmBtn

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0.35, 0)
	confirmCorner.Parent = confirmBtn

	local confirmStroke = Instance.new("UIStroke")
	confirmStroke.Color = BORDER_CYAN
	confirmStroke.Thickness = 2
	confirmStroke.Transparency = 0.15
	confirmStroke.Parent = confirmBtn

	local confirmPad = Instance.new("UIPadding")
	confirmPad.PaddingTop = UDim.new(0.1, 0)
	confirmPad.PaddingBottom = UDim.new(0.1, 0)
	confirmPad.Parent = confirmBtn

	confirmBtn.MouseEnter:Connect(function()
		TweenService:Create(confirmStroke, TweenInfo.new(0.12), { Thickness = 3, Transparency = 0 }):Play()
		TweenService:Create(confirmBtn, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
	end)
	confirmBtn.MouseLeave:Connect(function()
		TweenService:Create(confirmStroke, TweenInfo.new(0.12), { Thickness = 2, Transparency = 0.15 }):Play()
		TweenService:Create(confirmBtn, TweenInfo.new(0.12), { BackgroundTransparency = 0.1 }):Play()
	end)

	confirmBtn.MouseButton1Click:Connect(function()
		if not selectedIndex then return end
		if onConfirm then
			onConfirm(selectedIndex)
		end
	end)

	local function positionPlanets()
		local absSize = mapFrame.AbsoluteSize
		if absSize.X == 0 or absSize.Y == 0 then return end
		local halfMin = math.min(absSize.X, absSize.Y) / 2

		for i, pd in ipairs(PLANET_DATA) do
			local angle = pd.orbitAngle + orbitTime * ORBIT_SPEED
			local r = pd.orbitRadius
			local px = 0.5 + math.cos(angle) * r
			local py = 0.5 + math.sin(angle) * r
			local btn = planetFrames[i]
			if btn then
				btn.Position = UDim2.fromScale(px, py)
			end
		end
	end

	local function startRender()
		if renderConn then return end
		renderConn = RunService.RenderStepped:Connect(function(dt)
			orbitTime = orbitTime + dt
			positionPlanets()

			for _, star in ipairs(starFrames) do
				local base = star.BackgroundTransparency
				star.BackgroundTransparency = base + math.sin(orbitTime * (2 + math.random() * 0.01)) * 0.005
			end
		end)
	end

	local function stopRender()
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
	end

	local api = {}

	function api.show(callback)
		onConfirm = callback
		selectedIndex = nil
		infoLabels.panel.Visible = false
		confirmBtn.Visible = false
		confirmBtn.Position = UDim2.fromScale(0.5, 1.1)

		for i, btn in ipairs(planetFrames) do
			local pd = PLANET_DATA[i]
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Thickness = 2
				stroke.Transparency = 0.4
				stroke.Color = pd.accent
			end
			btn.Size = PLANET_SIZE
		end

		positionPlanets()
		sg.Enabled = true
		visible = true
		startRender()

		bg.BackgroundTransparency = 1
		TweenService:Create(bg, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.15,
		}):Play()

		for _, btn in ipairs(planetFrames) do
			btn.BackgroundTransparency = 1
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Transparency = 1 end
		end

		task.delay(0.2, function()
			for i, btn in ipairs(planetFrames) do
				task.delay(i * 0.1, function()
					TweenService:Create(btn, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
						BackgroundTransparency = 0,
					}):Play()
					local stroke = btn:FindFirstChildOfClass("UIStroke")
					if stroke then
						TweenService:Create(stroke, TweenInfo.new(0.4), {
							Transparency = 0.4,
						}):Play()
					end
				end)
			end
		end)
	end

	function api.hide()
		visible = false
		TweenService:Create(bg, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()

		for _, btn in ipairs(planetFrames) do
			TweenService:Create(btn, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play() end
		end

		infoLabels.panel.Visible = false
		confirmBtn.Visible = false

		task.delay(0.5, function()
			if not visible then
				sg.Enabled = false
				stopRender()
			end
		end)
	end

	function api.isVisible()
		return visible
	end

	function api.getSelectedIndex()
		return selectedIndex
	end

	function api.destroy()
		stopRender()
		sg:Destroy()
	end

	return api
end

return LakelandGalacticMapUI
