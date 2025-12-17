-- TerminalUIController
-- FNAF-style terminal with clickable button to open
-- Uses Fusion for reactive UI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Fusion
local Fusion = require(CustomPackages:WaitForChild("FusionRoot"):WaitForChild("Fusion"))
local New = Fusion.New
local Children = Fusion.Children
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring
local OnEvent = Fusion.OnEvent

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local TerminalUIController = Knit.CreateController {
	Name = "TerminalUIController",
	_screenGui = nil,
	_hudGui = nil,
	_isTerminalVisible = nil,
	_isSeated = nil,
	_terminalText = nil,
	_isButtonHovered = nil,
}

-- =========================================================
-- CONFIG
-- =========================================================

local CONFIG = {
	-- Animation
	FadeSpeed = 12,
	FadeDamping = 1,
	
	-- Colors
	BackgroundColor = Color3.fromRGB(5, 8, 12),
	TextColor = Color3.fromRGB(0, 255, 100),
	DimTextColor = Color3.fromRGB(0, 100, 50),
	HeaderColor = Color3.fromRGB(0, 220, 100),
	BorderColor = Color3.fromRGB(0, 80, 40),
	
	-- Button colors
	ButtonColor = Color3.fromRGB(20, 60, 40),
	ButtonHoverColor = Color3.fromRGB(30, 100, 60),
	ButtonBorderColor = Color3.fromRGB(0, 200, 80),
	
	-- Font
	FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),
	BoldFontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
	TextSize = 16,
	
	-- Effects
	VignetteOpacity = 0.7,
}

-- =========================================================
-- CONTROLLER REFERENCE
-- =========================================================

local ComputerCameraController = nil

-- =========================================================
-- HUD UI (Button + Edge indicators when seated)
-- =========================================================

function TerminalUIController:CreateHudUI()
	self._isSeated = Value(false)
	self._isTerminalVisible = Value(false)
	self._isButtonHovered = Value(false)
	
	-- Show HUD when seated but terminal not open
	local hudVisibility = Spring(Computed(function()
		return (self._isSeated:get() and not self._isTerminalVisible:get()) and 1 or 0
	end), CONFIG.FadeSpeed, CONFIG.FadeDamping)
	
	local hudEnabled = Computed(function()
		return hudVisibility:get() > 0.01
	end)
	
	-- Button color based on hover
	local buttonColor = Computed(function()
		return self._isButtonHovered:get() and CONFIG.ButtonHoverColor or CONFIG.ButtonColor
	end)
	
	local buttonColorSpring = Spring(buttonColor, 20, 1)
	
	self._hudGui = New "ScreenGui" {
		Name = "SecurityHUD",
		Parent = PlayerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 95,
		Enabled = hudEnabled,
		
		[Children] = {
			-- Terminal button at bottom center
			New "TextButton" {
				Name = "TerminalButton",
				Size = UDim2.fromOffset(280, 60),
				Position = UDim2.new(0.5, 0, 1, -50),
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = buttonColorSpring,
				BackgroundTransparency = Computed(function()
					return 0.1 + (0.9 * (1 - hudVisibility:get()))
				end),
				Text = "",
				AutoButtonColor = false,
				
				[OnEvent "MouseEnter"] = function()
					self._isButtonHovered:set(true)
				end,
				
				[OnEvent "MouseLeave"] = function()
					self._isButtonHovered:set(false)
				end,
				
				[OnEvent "MouseButton1Click"] = function()
					if ComputerCameraController then
						ComputerCameraController:OpenTerminal()
					end
				end,
				
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0, 12) },
					
					New "UIStroke" {
						Color = CONFIG.ButtonBorderColor,
						Thickness = 2,
						Transparency = Computed(function()
							return 1 - hudVisibility:get()
						end),
					},
					
					-- Icon
					New "TextLabel" {
						Size = UDim2.fromOffset(40, 60),
						Position = UDim2.fromOffset(15, 0),
						BackgroundTransparency = 1,
						Text = "🖥️",
						TextSize = 28,
						TextTransparency = Computed(function()
							return 1 - hudVisibility:get()
						end),
					},
					
					-- Text
					New "TextLabel" {
						Size = UDim2.new(1, -70, 1, 0),
						Position = UDim2.fromOffset(55, 0),
						BackgroundTransparency = 1,
						Text = "ACCESS TERMINAL",
						TextColor3 = CONFIG.TextColor,
						FontFace = CONFIG.BoldFontFace,
						TextSize = 20,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTransparency = Computed(function()
							return 1 - hudVisibility:get()
						end),
					},
					
					-- Subtext
					New "TextLabel" {
						Size = UDim2.new(1, -70, 0, 20),
						Position = UDim2.new(0, 55, 1, -22),
						BackgroundTransparency = 1,
						Text = "Click or press TAB",
						TextColor3 = CONFIG.DimTextColor,
						FontFace = CONFIG.FontFace,
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTransparency = Computed(function()
							return 1 - hudVisibility:get()
						end),
					},
				},
			},
			
			-- Exit hint at top
			New "TextLabel" {
				Size = UDim2.new(0, 200, 0, 30),
				Position = UDim2.new(0.5, 0, 0, 20),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = Color3.fromRGB(30, 30, 40),
				BackgroundTransparency = Computed(function()
					return 0.3 + (0.7 * (1 - hudVisibility:get()))
				end),
				Text = "[ SPACE - Stand Up ]",
				TextColor3 = Color3.fromRGB(180, 180, 180),
				FontFace = CONFIG.FontFace,
				TextSize = 14,
				TextTransparency = Computed(function()
					return 1 - hudVisibility:get()
				end),
				
				[Children] = {
					New "UICorner" { CornerRadius = UDim.new(0, 8) },
				},
			},
			
			-- Pan arrows on edges
			-- Left arrow
			New "TextLabel" {
				Size = UDim2.fromOffset(40, 40),
				Position = UDim2.new(0, 20, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Text = "◀",
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 30,
				TextTransparency = Computed(function()
					return 0.5 + (0.5 * (1 - hudVisibility:get()))
				end),
			},
			
			-- Right arrow
			New "TextLabel" {
				Size = UDim2.fromOffset(40, 40),
				Position = UDim2.new(1, -20, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundTransparency = 1,
				Text = "▶",
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 30,
				TextTransparency = Computed(function()
					return 0.5 + (0.5 * (1 - hudVisibility:get()))
				end),
			},
		},
	}
end

-- =========================================================
-- TERMINAL UI (Full screen when opened)
-- =========================================================

function TerminalUIController:CreateTerminalUI()
	self._terminalText = Value(self:GetWelcomeText())
	
	local terminalVisibility = Spring(Computed(function()
		return self._isTerminalVisible:get() and 1 or 0
	end), CONFIG.FadeSpeed, CONFIG.FadeDamping)
	
	local bgTransparency = Computed(function()
		return 1 - terminalVisibility:get()
	end)
	
	local textTransparency = Computed(function()
		return 1 - terminalVisibility:get()
	end)
	
	local terminalEnabled = Computed(function()
		return terminalVisibility:get() > 0.01
	end)
	
	self._screenGui = New "ScreenGui" {
		Name = "TerminalUI",
		Parent = PlayerGui,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Enabled = terminalEnabled,
		
		[Children] = {
			-- Monitor background
			New "Frame" {
				Name = "MonitorFrame",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = CONFIG.BackgroundColor,
				BackgroundTransparency = bgTransparency,
				BorderSizePixel = 0,
				
				[Children] = {
					-- CRT vignette
					New "ImageLabel" {
						Name = "Vignette",
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Image = "rbxassetid://2778177152",
						ImageColor3 = Color3.new(0, 0, 0),
						ImageTransparency = Computed(function()
							return 1 - (CONFIG.VignetteOpacity * terminalVisibility:get())
						end),
						ZIndex = 10,
					},
					
					-- Map Display (full screen)
					New "Frame" {
						Name = "MapContainer",
						Size = UDim2.fromScale(0.85, 0.85),
						Position = UDim2.fromScale(0.5, 0.48),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = Color3.fromRGB(8, 12, 18),
						BackgroundTransparency = Computed(function()
							return 0.1 + (0.9 * (1 - terminalVisibility:get()))
						end),
						ZIndex = 5,
						
						[Children] = {
							New "UICorner" { CornerRadius = UDim.new(0, 12) },
							
							New "UIStroke" {
								Color = CONFIG.BorderColor,
								Thickness = 2,
								Transparency = textTransparency,
							},
							
							-- Header
							New "Frame" {
								Size = UDim2.new(1, 0, 0, 50),
								BackgroundColor3 = Color3.fromRGB(12, 18, 25),
								BackgroundTransparency = Computed(function()
									return 0.2 + (0.8 * (1 - terminalVisibility:get()))
								end),
								
								[Children] = {
									New "UICorner" { CornerRadius = UDim.new(0, 12) },
									
									New "TextLabel" {
										Size = UDim2.fromScale(1, 1),
										BackgroundTransparency = 1,
										Text = "◈  FACILITY MAP  ◈",
										TextColor3 = CONFIG.HeaderColor,
										FontFace = CONFIG.BoldFontFace,
										TextSize = 24,
										TextTransparency = textTransparency,
									},
								},
							},
							
							-- Map Content
							New "Frame" {
								Name = "MapContent",
								Size = UDim2.new(1, -40, 1, -110),
								Position = UDim2.fromOffset(20, 60),
								BackgroundTransparency = 1,
								
								[Children] = {
									New "TextLabel" {
										Name = "MapText",
										Size = UDim2.fromScale(1, 1),
										BackgroundTransparency = 1,
										Text = [[<font color="#00FF66">                              ┌────────⊙────────┐</font>
<font color="#00FF66">                              │     BRIDGE      │</font>
<font color="#00FF66">                              └────────┬────────┘</font>
<font color="#00FF66">                                       │</font>
<font color="#00FF66">            ┌──────────┐       ┌───────┴───────┐       ┌──────────┐</font>
<font color="#00FF66">            │ ENGINEER │       │               │       │   A.I.   │</font>
<font color="#00FF66">      ╔═════│ DECK  01 ├───────┤   MESS HALL   ├───────┤   CORE   │</font>
<font color="#00FF66">      ║     │    ⚡    │       │               │       │    ◎     │</font>
<font color="#00FF66">      ║     └────┬─────┘       └───────┬───────┘       └────┬─────┘</font>
<font color="#00FF66">      ║          │                     │                    │</font>
<font color="#00FF66">      ║     ┌────┴─────┐       ┌───────┴───────┐       ┌────┴─────┐</font>
<font color="#00FF66">      ║     │  LOUNGE  │       │     CRYO      │       │   DUCT   │</font>
<font color="#00FF66">      ║     │    ☕    ├───────┤    BAY  ❄❄❄   ├═══════│  SYSTEM  │</font>
<font color="#00FF66">      ║     │          │       │               │       │    ≋     │</font>
<font color="#00FF66">      ║     └────┬─────┘       └───────┬───────┘       └────┬─────┘</font>
<font color="#00FF66">      ║          │                     │                    │</font>
<font color="#00FF66"> ┌────╨────┐┌────┴─────┐       ┌───────┴───────┐       ┌────┴─────┐</font>
<font color="#00FF66"> │ ARMORY  ││ MED BAY  │       │   ENGINEER    │       │ AIRLOCK  │</font>
<font color="#00FF66"> │   ⚔⚔    ││    ✚     │       │   DECK  02    │       │    ◈     │</font>
<font color="#00FF66"> │         ││          │       │      ⚡       │       │    X     │</font>
<font color="#00FF66"> └─────────┘└──────────┘       └───────────────┘       └──────────┘</font>

<font color="#FFCC00">══════════════════════════════════ LEGEND ══════════════════════════════════</font>
<font color="#00AA55">  ⊙</font> Access Terminal    <font color="#00AA55">⚡</font> Engineering Station    <font color="#00AA55">✚</font> Medical Bay    <font color="#00AA55">◎</font> Mainframe
<font color="#00AA55">  ❄</font> Cryosleep Pod      <font color="#00AA55">≋</font> Duct Access           <font color="#00AA55">◈</font> Airlock        <font color="#00AA55">☕</font> Crew Lounge
<font color="#00AA55">  ⚔</font> Weapons Storage    <font color="#FF6666">X</font> Emergency Exit         <font color="#00AA55">═</font> Vent Shaft
<font color="#FFCC00">════════════════════════════════════════════════════════════════════════════</font>

<font color="#FF6666">  █ YOUR LOCATION: SECURITY OFFICE</font>              <font color="#FFCC00">⚠ ALERT: DUCT SYSTEM</font>]],
										TextColor3 = CONFIG.TextColor,
										FontFace = CONFIG.FontFace,
										TextSize = 14,
										TextTransparency = textTransparency,
										TextXAlignment = Enum.TextXAlignment.Center,
										TextYAlignment = Enum.TextYAlignment.Center,
										RichText = true,
										TextWrapped = false,
										TextScaled = false,
									},
								},
							},
							
							-- Close button
							New "TextButton" {
								Name = "CloseButton",
								Size = UDim2.fromOffset(180, 40),
								Position = UDim2.new(0.5, 0, 1, -15),
								AnchorPoint = Vector2.new(0.5, 1),
								BackgroundColor3 = Color3.fromRGB(50, 20, 20),
								BackgroundTransparency = Computed(function()
									return 0.1 + (0.9 * (1 - terminalVisibility:get()))
								end),
								Text = "✕  CLOSE  [ ESC ]",
								TextColor3 = Color3.fromRGB(255, 100, 100),
								FontFace = CONFIG.BoldFontFace,
								TextSize = 16,
								TextTransparency = textTransparency,
								AutoButtonColor = true,
								
								[OnEvent "MouseButton1Click"] = function()
									if ComputerCameraController then
										ComputerCameraController:CloseTerminal()
									end
								end,
								
								[Children] = {
									New "UICorner" { CornerRadius = UDim.new(0, 8) },
									New "UIStroke" {
										Color = Color3.fromRGB(150, 50, 50),
										Thickness = 2,
										Transparency = textTransparency,
									},
								},
							},
						},
					},
				},
			},
		},
	}
end

-- =========================================================
-- TERMINAL LOGIC
-- =========================================================

function TerminalUIController:GetWelcomeText()
	return string.format([[<font color="#00AA55">[SYS]</font> Booting security interface...
<font color="#00AA55">[SYS]</font> All systems nominal.

<font color="#00FF66">══════════════════════════════════════</font>
<font color="#00FF66">  WELCOME, OPERATOR %s</font>
<font color="#00FF66">══════════════════════════════════════</font>

<font color="#666666">Session: %s</font>
<font color="#FFCC00">[!]</font> Movement detected in Sector C

Type <font color="#FFFF00">'help'</font> for available commands.

]], Player.Name:upper(), os.date("%Y-%m-%d %H:%M:%S"))
end

function TerminalUIController:GetFacilityMap()
	return [[
<font color="#FFCC00">╔═══════════════════ FACILITY MAP ═══════════════════╗</font>

<font color="#00FF66">                    ┌──⊙──┐</font>
<font color="#00FF66">                    │BRIDGE│</font>
<font color="#00FF66">                    └──┬───┘</font>
<font color="#00FF66">           ┌────────┐  │  ┌────┐</font>
<font color="#00FF66">    ┌──────┤ ENGIN. ├──┴──┤ AI │</font>
<font color="#00FF66">    │  ⚡  │ DECK 01│     │CORE│</font>
<font color="#00FF66">    │      └───┬────┘     └──┬─┘</font>
<font color="#00FF66">    │          │             │</font>
<font color="#00FF66"> ┌──┴──┐   ┌───┴───┐    ┌───┴───┐     ┌─────────┐</font>
<font color="#00FF66"> │ MED │   │ MESS  │    │ CRYO  │     │  DUCT   │</font>
<font color="#00FF66"> │ BAY ├───┤ HALL  ├────┤  BAY  │═════│ SYSTEM  │</font>
<font color="#00FF66"> │  ✚  │   │       │    │  ❄❄❄  │     │    ≋    │</font>
<font color="#00FF66"> └──┬──┘   └───┬───┘    └───┬───┘     └────┬────┘</font>
<font color="#00FF66">    │          │            │              │</font>
<font color="#00FF66"> ┌──┴──┐   ┌───┴───┐   ┌───┴────┐    ┌────┴────┐</font>
<font color="#00FF66"> │ARMRY│   │LOUNGE │   │ENGIN.  │    │AIRLOCK  │</font>
<font color="#00FF66"> │ ⚔⚔  │   │  ☕    │   │DECK 02 │    │   ◈     │</font>
<font color="#00FF66"> └─────┘   └───────┘   │   ⚡    │    └─────────┘</font>
<font color="#00FF66">                       └────────┘</font>

<font color="#FFCC00">╠═══════════════════ LEGEND ══════════════════════════╣</font>
<font color="#00AA55"> ⊙</font> Terminal   <font color="#00AA55">⚡</font> Engineering   <font color="#00AA55">✚</font> Medical
<font color="#00AA55"> ❄</font> Cryo Pod   <font color="#00AA55">≋</font> Duct Access   <font color="#00AA55">◈</font> Airlock
<font color="#00AA55"> ☕</font> Crew Area  <font color="#00AA55">⚔</font> Armory        <font color="#FF6666">█</font> You Are Here
<font color="#FFCC00">╚═════════════════════════════════════════════════════╝</font>

<font color="#666666">Current Location: SECURITY OFFICE</font>
<font color="#FF6666">[!] Anomaly detected: DUCT SYSTEM</font>
]]
end

function TerminalUIController:ProcessCommand()
	local inputBox = self._screenGui:FindFirstChild("InputBox", true)
	if not inputBox then return end
	
	local command = inputBox.Text:lower():gsub("^%s*(.-)%s*$", "%1")
	inputBox.Text = ""
	
	if command == "" then return end
	
	local currentText = self._terminalText:get()
	local response = ""
	
	if command == "help" then
		response = [[
<font color="#FFCC00">╔═══ COMMAND LIST ═══╗</font>
  <font color="#00FF66">help</font>     - Display commands
  <font color="#00FF66">map</font>      - Facility map
  <font color="#00FF66">status</font>   - System status
  <font color="#00FF66">cameras</font>  - Camera feeds
  <font color="#00FF66">scan</font>     - Scan for threats
  <font color="#00FF66">clear</font>    - Clear screen
<font color="#FFCC00">╚════════════════════╝</font>
]]
	elseif command == "clear" then
		self._terminalText:set(self:GetWelcomeText())
		return
	elseif command == "status" then
		response = [[
<font color="#00AA55">┌─── SYSTEM STATUS ───┐</font>
  Power:    <font color="#00FF00">■ ONLINE</font>
  Network:  <font color="#00FF00">■ CONNECTED</font>
  Cameras:  <font color="#00FF00">■ 6/6 ACTIVE</font>
  Doors:    <font color="#FFCC00">■ 2 UNLOCKED</font>
  Threats:  <font color="#FF6666">■ 1 DETECTED</font>
<font color="#00AA55">└─────────────────────┘</font>
]]
	elseif command == "cameras" then
		response = [[
<font color="#00AA55">┌─── CAMERA FEEDS ───┐</font>
  CAM-01  Main Lobby    <font color="#00FF00">[OK]</font>
  CAM-02  Hallway A     <font color="#00FF00">[OK]</font>
  CAM-03  Storage       <font color="#FFCC00">[STATIC]</font>
  CAM-04  Kitchen       <font color="#00FF00">[OK]</font>
  CAM-05  Backstage     <font color="#FF6666">[OFFLINE]</font>
  CAM-06  Office        <font color="#00FF00">[OK]</font>
<font color="#00AA55">└─────────────────────┘</font>
]]
	elseif command == "scan" then
		response = [[
<font color="#FFCC00">[SCANNING...]</font>
  ████████████████████ 100%

<font color="#00AA55">[RESULTS]</font>
  Anomalies: <font color="#FF6666">1</font>
  Location: <font color="#FFCC00">Sector C - Storage</font>
  Status: <font color="#FF6666">MONITORING</font>
]]
	elseif command == "map" then
		response = self:GetFacilityMap()
	else
		response = string.format("<font color='#FF6666'>[ERR]</font> Unknown command: '%s'\nType 'help' for commands.\n", command)
	end
	
	self._terminalText:set(currentText .. "<font color='#444444'>> " .. command .. "</font>\n" .. response .. "\n")
end

-- =========================================================
-- SHOW / HIDE
-- =========================================================

function TerminalUIController:ShowTerminal()
	self._isTerminalVisible:set(true)
	
	task.delay(0.25, function()
		local inputBox = self._screenGui and self._screenGui:FindFirstChild("InputBox", true)
		if inputBox and self._isTerminalVisible:get() then
			inputBox:CaptureFocus()
		end
	end)
end

function TerminalUIController:HideTerminal()
	self._isTerminalVisible:set(false)
	
	local inputBox = self._screenGui and self._screenGui:FindFirstChild("InputBox", true)
	if inputBox then
		inputBox:ReleaseFocus()
	end
end

function TerminalUIController:SetSeated(isSeated)
	self._isSeated:set(isSeated)
	
	if not isSeated then
		self._isTerminalVisible:set(false)
	end
end

-- =========================================================
-- KNIT LIFECYCLE
-- =========================================================

function TerminalUIController:KnitInit()
	print("[TerminalUIController] Initializing")
end

function TerminalUIController:KnitStart()
	print("[TerminalUIController] Starting")
	
	-- Get camera controller reference
	ComputerCameraController = Knit.GetController("ComputerCameraController")
	
	-- Create UIs
	self:CreateHudUI()
	self:CreateTerminalUI()
	
	-- Listen to camera controller events
	ComputerCameraController.SeatedAtComputer:Connect(function(isSeated)
		self:SetSeated(isSeated)
	end)
	
	ComputerCameraController.TerminalToggled:Connect(function(isOpen)
		if isOpen then
			self:ShowTerminal()
		else
			self:HideTerminal()
		end
	end)
	
	print("[TerminalUIController] Ready")
end

return TerminalUIController
