local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local BiomeConfig = require(ReplicatedStorage.Source.BiomeConfig)

local BG_DEEP        = Color3.fromRGB(3, 5, 14)
local BG_PANEL       = Color3.fromRGB(10, 16, 32)
local BORDER_CYAN    = Color3.fromRGB(0, 180, 255)
local TEXT_BRIGHT    = Color3.fromRGB(225, 238, 255)
local TEXT_DIM       = Color3.fromRGB(100, 130, 170)
local RING_DIM       = Color3.fromRGB(18, 32, 55)
local SELECTED_GLOW  = Color3.fromRGB(0, 220, 255)
local ACCENT_SOFT    = Color3.fromRGB(60, 100, 160)
local CURRENT_COLOR  = Color3.fromRGB(255, 200, 60)
local DISABLED_DIM   = Color3.fromRGB(50, 55, 70)

local PLANET_DATA = {}
for i, biome in ipairs(BiomeConfig.Biomes) do
	table.insert(PLANET_DATA, {
		id = i,
		name = string.upper(biome.name),
		tagline = biome.tagline or biome.description or "",
		description = biome.description or "",
		color = biome.planetColor or biome.accentColor,
		accent = biome.accentColor,
		orbitRadius = biome.orbit and biome.orbit.radius or (0.18 + i * 0.03),
		orbitAngle = biome.orbit and biome.orbit.angle or (math.rad(72 * i)),
	})
end

local LOBBY_COLOR   = Color3.fromRGB(120, 200, 255)
local LOBBY_ACCENT  = Color3.fromRGB(80, 170, 240)

local STAR_COUNT  = 160
local PLANET_SIZE = UDim2.fromScale(0.07, 0.07)
local LOBBY_SIZE  = UDim2.fromScale(0.055, 0.055)
local SUN_SIZE    = UDim2.fromScale(0.055, 0.055)

local LakelandGalacticMapUI = {}
LakelandGalacticMapUI.LOBBY_INDEX = 0

local function createStar(parent)
	local star = Instance.new("Frame")
	star.Name = "Star"
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	local sz = 1 + math.random() * 2.5
	star.Size = UDim2.fromOffset(sz, sz)
	star.Position = UDim2.fromScale(math.random(), math.random())
	local brightness = math.random()
	local r = 200 + math.floor(brightness * 55)
	local g = 210 + math.floor(brightness * 45)
	star.BackgroundColor3 = Color3.fromRGB(r, g, 255)
	star.BackgroundTransparency = 0.25 + math.random() * 0.5
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
	stroke.Transparency = 0.6
	stroke.Parent = ring
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	return ring
end

function LakelandGalacticMapUI.new(playerGui)
	local selectedIndex = nil
	local currentBiome = nil
	local planetFrames = {}
	local planetGlows = {}
	local planetHereLabels = {}
	local starFrames = {}
	local onConfirm = nil
	local visible = false
	local infoLabels = {}
	local pulseConn = nil
	local pulseTime = 0

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
	bg.BackgroundTransparency = 0.05
	bg.BorderSizePixel = 0
	bg.ZIndex = 0
	bg.Parent = sg

	local vignette = Instance.new("ImageLabel")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundTransparency = 1
	vignette.Image = "rbxassetid://1526406839"
	vignette.ImageColor3 = Color3.new(0, 0, 0)
	vignette.ImageTransparency = 0.3
	vignette.ZIndex = 1
	vignette.Parent = bg

	for _ = 1, STAR_COUNT do
		table.insert(starFrames, createStar(bg))
	end

	local mapFrame = Instance.new("Frame")
	mapFrame.Name = "MapFrame"
	mapFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mapFrame.Position = UDim2.fromScale(0.5, 0.47)
	mapFrame.Size = UDim2.fromScale(0.75, 0.85)
	mapFrame.BackgroundTransparency = 1
	mapFrame.BorderSizePixel = 0
	mapFrame.ZIndex = 3
	mapFrame.Parent = sg

	local mapAspect = Instance.new("UIAspectRatioConstraint")
	mapAspect.AspectRatio = 1
	mapAspect.DominantAxis = Enum.DominantAxis.Height
	mapAspect.Parent = mapFrame

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.fromScale(0.5, 0.005)
	titleLabel.Size = UDim2.fromScale(0.6, 0.055)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "G A L A C T I C   M A P"
	titleLabel.TextColor3 = BORDER_CYAN
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.ZIndex = 10
	titleLabel.Parent = mapFrame

	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = BORDER_CYAN
	titleStroke.Thickness = 0
	titleStroke.Transparency = 0.6
	titleStroke.Parent = titleLabel

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.AnchorPoint = Vector2.new(0.5, 0)
	subtitleLabel.Position = UDim2.fromScale(0.5, 0.065)
	subtitleLabel.Size = UDim2.fromScale(0.4, 0.03)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Text = "SELECT YOUR DESTINATION"
	subtitleLabel.TextColor3 = TEXT_DIM
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextScaled = true
	subtitleLabel.ZIndex = 10
	subtitleLabel.Parent = mapFrame

	-- Decorative line under title
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.Position = UDim2.fromScale(0.5, 0.058)
	divider.Size = UDim2.fromScale(0.25, 0)
	divider.BackgroundTransparency = 1
	divider.BorderSizePixel = 0
	divider.ZIndex = 10
	divider.Parent = mapFrame
	local divStroke = Instance.new("UIStroke")
	divStroke.Color = ACCENT_SOFT
	divStroke.Thickness = 1
	divStroke.Transparency = 0.5
	divStroke.Parent = divider

	-- Orbit rings
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

	-- Sun
	local sun = Instance.new("Frame")
	sun.Name = "Sun"
	sun.AnchorPoint = Vector2.new(0.5, 0.5)
	sun.Position = UDim2.fromScale(0.5, 0.5)
	sun.Size = SUN_SIZE
	sun.BackgroundColor3 = Color3.fromRGB(255, 225, 110)
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
	sunGlow.Color = Color3.fromRGB(255, 200, 60)
	sunGlow.Thickness = 4
	sunGlow.Transparency = 0.25
	sunGlow.Parent = sun

	local sunLabel = Instance.new("TextLabel")
	sunLabel.Name = "SunLabel"
	sunLabel.AnchorPoint = Vector2.new(0.5, 0)
	sunLabel.Position = UDim2.fromScale(0.5, 1.2)
	sunLabel.Size = UDim2.fromScale(2, 0.35)
	sunLabel.BackgroundTransparency = 1
	sunLabel.Text = "SOL"
	sunLabel.TextColor3 = Color3.fromRGB(255, 220, 110)
	sunLabel.Font = Enum.Font.GothamBold
	sunLabel.TextScaled = true
	sunLabel.ZIndex = 6
	sunLabel.Parent = sun

	-- Lobby station (bottom-center, small diamond-shaped marker)
	local lobbyBtn = Instance.new("TextButton")
	lobbyBtn.Name = "LobbyStation"
	lobbyBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	lobbyBtn.Position = UDim2.fromScale(0.5, 0.88)
	lobbyBtn.Size = LOBBY_SIZE
	lobbyBtn.BackgroundColor3 = LOBBY_COLOR
	lobbyBtn.BackgroundTransparency = 0
	lobbyBtn.BorderSizePixel = 0
	lobbyBtn.Text = ""
	lobbyBtn.AutoButtonColor = false
	lobbyBtn.Rotation = 45
	lobbyBtn.ZIndex = 8
	lobbyBtn.Visible = false
	lobbyBtn.Parent = mapFrame
	local lobbyCorner = Instance.new("UICorner")
	lobbyCorner.CornerRadius = UDim.new(0.2, 0)
	lobbyCorner.Parent = lobbyBtn
	local lobbyAspect = Instance.new("UIAspectRatioConstraint")
	lobbyAspect.AspectRatio = 1
	lobbyAspect.Parent = lobbyBtn
	local lobbyStroke = Instance.new("UIStroke")
	lobbyStroke.Color = LOBBY_ACCENT
	lobbyStroke.Thickness = 2
	lobbyStroke.Transparency = 0.3
	lobbyStroke.Parent = lobbyBtn

	local lobbyNameLabel = Instance.new("TextLabel")
	lobbyNameLabel.Name = "LobbyName"
	lobbyNameLabel.AnchorPoint = Vector2.new(0.5, 0)
	lobbyNameLabel.Position = UDim2.fromScale(0.5, 1.4)
	lobbyNameLabel.Size = UDim2.fromScale(3, 0.35)
	lobbyNameLabel.BackgroundTransparency = 1
	lobbyNameLabel.Text = "LOBBY"
	lobbyNameLabel.TextColor3 = TEXT_BRIGHT
	lobbyNameLabel.Font = Enum.Font.GothamBold
	lobbyNameLabel.TextScaled = true
	lobbyNameLabel.ZIndex = 9
	lobbyNameLabel.Rotation = -45
	lobbyNameLabel.Parent = lobbyBtn
	local lobbyNameStroke = Instance.new("UIStroke")
	lobbyNameStroke.Color = Color3.new(0, 0, 0)
	lobbyNameStroke.Thickness = 1
	lobbyNameStroke.Transparency = 0.5
	lobbyNameStroke.Parent = lobbyNameLabel

	local showLobby = false

	local function deselectPrevious()
		if not selectedIndex or selectedIndex == 0 then return end
		if selectedIndex == currentBiome then return end
		local oldBtn = planetFrames[selectedIndex]
		if not oldBtn then return end
		local oldStroke = oldBtn:FindFirstChildOfClass("UIStroke")
		local oldPd = PLANET_DATA[selectedIndex]
		if oldStroke and oldPd then
			TweenService:Create(oldStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
				Thickness = 2, Transparency = 0.35, Color = oldPd.accent,
			}):Play()
		end
		TweenService:Create(oldBtn, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
			Size = PLANET_SIZE,
		}):Play()
	end

	local function deselectLobby()
		TweenService:Create(lobbyStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			Thickness = 2, Transparency = 0.3, Color = LOBBY_ACCENT,
		}):Play()
		TweenService:Create(lobbyBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			Size = LOBBY_SIZE,
		}):Play()
	end

	local function selectLobby()
		if selectedIndex and selectedIndex > 0 then
			deselectPrevious()
		end
		selectedIndex = 0

		TweenService:Create(lobbyStroke, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Thickness = 4, Transparency = 0, Color = SELECTED_GLOW,
		}):Play()
		TweenService:Create(lobbyBtn, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(LOBBY_SIZE.X.Scale * 1.25, LOBBY_SIZE.Y.Scale * 1.25),
		}):Play()

		infoLabels.name.Text = "LOBBY"
		infoLabels.tagline.Text = "Return to the launch platform"
		infoLabels.desc.Text = "Warp back to the lobby to pick a new machine or change your profile."
		infoLabels.name.TextColor3 = LOBBY_COLOR
		infoLabels.panel.Visible = true

		TweenService:Create(infoLabels.panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5, 0.86),
		}):Play()

		local cBtn = infoLabels.confirmBtn
		if cBtn then
			cBtn.Visible = true
			cBtn.Text = "RETURN TO LOBBY"
			TweenService:Create(cBtn, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(0.5, 0.945),
			}):Play()
		end
	end

	lobbyBtn.MouseEnter:Connect(function()
		if selectedIndex == 0 then return end
		TweenService:Create(lobbyStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Thickness = 3, Transparency = 0.05,
		}):Play()
		TweenService:Create(lobbyBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(LOBBY_SIZE.X.Scale * 1.15, LOBBY_SIZE.Y.Scale * 1.15),
		}):Play()
	end)

	lobbyBtn.MouseLeave:Connect(function()
		if selectedIndex == 0 then return end
		TweenService:Create(lobbyStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Thickness = 2, Transparency = 0.3,
		}):Play()
		TweenService:Create(lobbyBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = LOBBY_SIZE,
		}):Play()
	end)

	lobbyBtn.MouseButton1Click:Connect(function()
		selectLobby()
	end)

	-- Planets (static positions)
	for i, pd in ipairs(PLANET_DATA) do
		local px = 0.5 + math.cos(pd.orbitAngle) * pd.orbitRadius
		local py = 0.5 + math.sin(pd.orbitAngle) * pd.orbitRadius

		local planetBtn = Instance.new("TextButton")
		planetBtn.Name = "Planet_" .. pd.name
		planetBtn.AnchorPoint = Vector2.new(0.5, 0.5)
		planetBtn.Position = UDim2.fromScale(px, py)
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
		pStroke.Transparency = 0.35
		pStroke.Parent = planetBtn

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PlanetName"
		nameLabel.AnchorPoint = Vector2.new(0.5, 0)
		nameLabel.Position = UDim2.fromScale(0.5, 1.25)
		nameLabel.Size = UDim2.fromScale(3, 0.3)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = pd.name
		nameLabel.TextColor3 = TEXT_BRIGHT
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextScaled = true
		nameLabel.ZIndex = 9
		nameLabel.Parent = planetBtn

		local nameStroke = Instance.new("UIStroke")
		nameStroke.Color = Color3.new(0, 0, 0)
		nameStroke.Thickness = 1
		nameStroke.Transparency = 0.5
		nameStroke.Parent = nameLabel

		local hereLabel = Instance.new("TextLabel")
		hereLabel.Name = "HereLabel"
		hereLabel.AnchorPoint = Vector2.new(0.5, 1)
		hereLabel.Position = UDim2.fromScale(0.5, -0.25)
		hereLabel.Size = UDim2.fromScale(3, 0.25)
		hereLabel.BackgroundTransparency = 1
		hereLabel.Text = "YOU ARE HERE"
		hereLabel.TextColor3 = CURRENT_COLOR
		hereLabel.Font = Enum.Font.GothamBold
		hereLabel.TextScaled = true
		hereLabel.ZIndex = 10
		hereLabel.Visible = false
		hereLabel.Parent = planetBtn
		planetHereLabels[i] = hereLabel

		planetBtn.MouseEnter:Connect(function()
			if currentBiome == i or selectedIndex == i then return end
			TweenService:Create(pStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Thickness = 3, Transparency = 0.05,
			}):Play()
			TweenService:Create(planetBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(PLANET_SIZE.X.Scale * 1.15, PLANET_SIZE.Y.Scale * 1.15),
			}):Play()
		end)

		planetBtn.MouseLeave:Connect(function()
			if currentBiome == i or selectedIndex == i then return end
			TweenService:Create(pStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Thickness = 2, Transparency = 0.35,
			}):Play()
			TweenService:Create(planetBtn, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = PLANET_SIZE,
			}):Play()
		end)

		planetBtn.MouseButton1Click:Connect(function()
			if currentBiome == i then return end

			local prev = selectedIndex
			if prev == 0 then
				deselectLobby()
			elseif prev and prev ~= i then
				deselectPrevious()
			end
			selectedIndex = i

			TweenService:Create(pStroke, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Thickness = 4, Transparency = 0, Color = SELECTED_GLOW,
			}):Play()
			TweenService:Create(planetBtn, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(PLANET_SIZE.X.Scale * 1.25, PLANET_SIZE.Y.Scale * 1.25),
			}):Play()

			infoLabels.name.Text = pd.name
			infoLabels.tagline.Text = pd.tagline
			infoLabels.desc.Text = pd.description
			infoLabels.name.TextColor3 = pd.accent
			infoLabels.panel.Visible = true

			TweenService:Create(infoLabels.panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(0.5, 0.86),
			}):Play()

			local cBtn = infoLabels.confirmBtn
			if cBtn then
				cBtn.Text = "ENGAGE HYPERDRIVE"
				cBtn.Visible = true
				TweenService:Create(cBtn, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(0.5, 0.945),
				}):Play()
			end
		end)

		planetFrames[i] = planetBtn
		planetGlows[i] = pStroke
	end

	-- Info panel
	local infoPanel = Instance.new("Frame")
	infoPanel.Name = "InfoPanel"
	infoPanel.AnchorPoint = Vector2.new(0.5, 1)
	infoPanel.Position = UDim2.fromScale(0.5, 0.90)
	infoPanel.Size = UDim2.fromScale(0.38, 0.11)
	infoPanel.BackgroundColor3 = BG_PANEL
	infoPanel.BackgroundTransparency = 0.08
	infoPanel.BorderSizePixel = 0
	infoPanel.ZIndex = 10
	infoPanel.Visible = false
	infoPanel.Parent = mapFrame

	local infoPanelCorner = Instance.new("UICorner")
	infoPanelCorner.CornerRadius = UDim.new(0.12, 0)
	infoPanelCorner.Parent = infoPanel

	local infoPanelStroke = Instance.new("UIStroke")
	infoPanelStroke.Color = BORDER_CYAN
	infoPanelStroke.Thickness = 1
	infoPanelStroke.Transparency = 0.3
	infoPanelStroke.Parent = infoPanel

	local infoName = Instance.new("TextLabel")
	infoName.Name = "InfoName"
	infoName.AnchorPoint = Vector2.new(0.5, 0)
	infoName.Position = UDim2.fromScale(0.5, 0.06)
	infoName.Size = UDim2.fromScale(0.9, 0.3)
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
	infoTag.Position = UDim2.fromScale(0.5, 0.36)
	infoTag.Size = UDim2.fromScale(0.9, 0.22)
	infoTag.BackgroundTransparency = 1
	infoTag.Text = ""
	infoTag.TextColor3 = ACCENT_SOFT
	infoTag.Font = Enum.Font.GothamMedium
	infoTag.TextScaled = true
	infoTag.ZIndex = 11
	infoTag.Parent = infoPanel

	local infoDesc = Instance.new("TextLabel")
	infoDesc.Name = "InfoDesc"
	infoDesc.AnchorPoint = Vector2.new(0.5, 0)
	infoDesc.Position = UDim2.fromScale(0.5, 0.60)
	infoDesc.Size = UDim2.fromScale(0.9, 0.32)
	infoDesc.BackgroundTransparency = 1
	infoDesc.Text = ""
	infoDesc.TextColor3 = TEXT_DIM
	infoDesc.Font = Enum.Font.Gotham
	infoDesc.TextScaled = true
	infoDesc.TextWrapped = true
	infoDesc.ZIndex = 11
	infoDesc.Parent = infoPanel

	infoLabels.name = infoName
	infoLabels.tagline = infoTag
	infoLabels.desc = infoDesc
	infoLabels.panel = infoPanel

	-- Confirm button
	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Name = "ConfirmBtn"
	confirmBtn.AnchorPoint = Vector2.new(0.5, 1)
	confirmBtn.Position = UDim2.fromScale(0.5, 1.1)
	confirmBtn.Size = UDim2.fromScale(0.22, 0.052)
	confirmBtn.BackgroundColor3 = BG_PANEL
	confirmBtn.BackgroundTransparency = 0.05
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
	confirmStroke.Transparency = 0.1
	confirmStroke.Parent = confirmBtn

	local confirmPad = Instance.new("UIPadding")
	confirmPad.PaddingTop = UDim.new(0.1, 0)
	confirmPad.PaddingBottom = UDim.new(0.1, 0)
	confirmPad.PaddingLeft = UDim.new(0.05, 0)
	confirmPad.PaddingRight = UDim.new(0.05, 0)
	confirmPad.Parent = confirmBtn

	confirmBtn.MouseEnter:Connect(function()
		TweenService:Create(confirmStroke, TweenInfo.new(0.15), {
			Thickness = 3, Transparency = 0, Color = SELECTED_GLOW,
		}):Play()
		TweenService:Create(confirmBtn, TweenInfo.new(0.15), {
			BackgroundTransparency = 0, TextColor3 = Color3.new(1, 1, 1),
		}):Play()
	end)
	confirmBtn.MouseLeave:Connect(function()
		TweenService:Create(confirmStroke, TweenInfo.new(0.15), {
			Thickness = 2, Transparency = 0.1, Color = BORDER_CYAN,
		}):Play()
		TweenService:Create(confirmBtn, TweenInfo.new(0.15), {
			BackgroundTransparency = 0.05, TextColor3 = BORDER_CYAN,
		}):Play()
	end)

	confirmBtn.MouseButton1Click:Connect(function()
		if not selectedIndex then return end
		if onConfirm then
			onConfirm(selectedIndex)
		end
	end)

	-- Subtle pulse on the selected planet
	local function startPulse()
		if pulseConn then return end
		pulseTime = 0
		pulseConn = RunService.RenderStepped:Connect(function(dt)
			pulseTime = pulseTime + dt
			if not selectedIndex then return end
			local btn = planetFrames[selectedIndex]
			if not btn then return end
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0.05 + math.sin(pulseTime * 2.5) * 0.08
			end
		end)
	end

	local function stopPulse()
		if pulseConn then
			pulseConn:Disconnect()
			pulseConn = nil
		end
	end

	local api = {}

	function api.show(callback, currentBiomeIndex, showLobbyOption)
		onConfirm = callback
		selectedIndex = nil
		currentBiome = currentBiomeIndex
		showLobby = showLobbyOption or false
		infoLabels.panel.Visible = false
		infoLabels.panel.Position = UDim2.fromScale(0.5, 0.94)
		confirmBtn.Visible = false
		confirmBtn.Position = UDim2.fromScale(0.5, 1.1)
		confirmBtn.Text = "ENGAGE HYPERDRIVE"

		lobbyBtn.Visible = false
		lobbyBtn.Size = UDim2.fromScale(0.01, 0.01)
		lobbyBtn.BackgroundTransparency = 1
		lobbyStroke.Transparency = 1
		lobbyStroke.Thickness = 2
		lobbyStroke.Color = LOBBY_ACCENT

		for i, btn in ipairs(planetFrames) do
			local pd = PLANET_DATA[i]
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			local isCurrent = (currentBiome == i)
			local nameL = btn:FindFirstChild("PlanetName")
			local hereL = planetHereLabels[i]

			if isCurrent then
				if stroke then
					stroke.Thickness = 3
					stroke.Transparency = 0.1
					stroke.Color = CURRENT_COLOR
				end
				btn.BackgroundTransparency = 0.4
				if nameL then nameL.TextColor3 = DISABLED_DIM end
				if hereL then hereL.Visible = true end
			else
				if stroke then
					stroke.Thickness = 2
					stroke.Transparency = 0.35
					stroke.Color = pd.accent
				end
				btn.BackgroundTransparency = 1
				if nameL then nameL.TextColor3 = TEXT_BRIGHT end
				if hereL then hereL.Visible = false end
			end
			btn.Size = PLANET_SIZE
		end

		sg.Enabled = true
		visible = true

		bg.BackgroundTransparency = 1
		TweenService:Create(bg, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.05,
		}):Play()

		for i, btn in ipairs(planetFrames) do
			local isCurrent = (currentBiome == i)
			local targetTransparency = isCurrent and 0.4 or 0
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Transparency = 1 end
			btn.Size = UDim2.fromScale(0.01, 0.01)
			btn.BackgroundTransparency = 1

			task.delay(0.15 + i * 0.08, function()
				TweenService:Create(btn, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					BackgroundTransparency = targetTransparency,
					Size = PLANET_SIZE,
				}):Play()
				if stroke then
					local targetStrokeTrans = isCurrent and 0.1 or 0.35
					TweenService:Create(stroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Transparency = targetStrokeTrans,
					}):Play()
				end
			end)
		end

		if showLobby then
			lobbyBtn.Visible = true
			local lobbyDelay = 0.15 + (#PLANET_DATA + 1) * 0.08
			task.delay(lobbyDelay, function()
				TweenService:Create(lobbyBtn, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					BackgroundTransparency = 0,
					Size = LOBBY_SIZE,
				}):Play()
				TweenService:Create(lobbyStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 0.3,
				}):Play()
			end)
		end

		startPulse()
	end

	function api.hide()
		visible = false

		TweenService:Create(bg, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()

		for _, btn in ipairs(planetFrames) do
			TweenService:Create(btn, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0.01, 0.01),
			}):Play()
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			end
		end

		if lobbyBtn.Visible then
			TweenService:Create(lobbyBtn, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(0.01, 0.01),
			}):Play()
			TweenService:Create(lobbyStroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		end

		infoLabels.panel.Visible = false
		confirmBtn.Visible = false

		task.delay(0.5, function()
			if not visible then
				sg.Enabled = false
				stopPulse()
				lobbyBtn.Visible = false
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
		stopPulse()
		sg:Destroy()
	end

	return api
end

return LakelandGalacticMapUI
