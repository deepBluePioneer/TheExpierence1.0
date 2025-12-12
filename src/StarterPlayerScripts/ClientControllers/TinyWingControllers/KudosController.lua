--[[
	KudosController.lua
	Client-side controller for displaying and animating the Kudos currency UI.
	Uses Replica to sync with server and Fusion for reactive UI.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))

-- Replica Module
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica.ReplicaController)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- UI Position & Size (upper left)
	Position = UDim2.new(0, 20, 0, 20),
	AnchorPoint = Vector2.new(0, 0),
	Size = UDim2.new(0, 160, 0, 50),
	
	-- Colors
	BackgroundColor = Color3.fromRGB(30, 30, 40),
	BorderColor = Color3.fromRGB(255, 200, 50),
	TextColor = Color3.fromRGB(255, 230, 100),
	IconColor = Color3.fromRGB(255, 215, 0),
	
	-- Reward popup
	PopupDuration = 1.5,
	PopupColor = Color3.fromRGB(255, 255, 100),
	
	-- Animation
	CountUpSpeed = 50,  -- Kudos per second when counting up
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONTROLLER                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local KudosController = Knit.CreateController({
	Name = "KudosController",
})

local player = Players.LocalPlayer
local kudosGui = nil
local kudosLabel = nil
local currentKudos = 0
local displayedKudos = 0
local lastAwardTime = 0
local replicaConnection = nil

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         UI CREATION                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function createKudosUI()
	local playerGui = player:WaitForChild("PlayerGui")
	
	-- Main ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "KudosGui"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	
	-- Container frame
	local container = Instance.new("Frame")
	container.Name = "KudosContainer"
	container.Size = CONFIG.Size
	container.Position = CONFIG.Position
	container.AnchorPoint = CONFIG.AnchorPoint
	container.BackgroundColor3 = CONFIG.BackgroundColor
	container.BorderSizePixel = 0
	container.Parent = gui
	
	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = container
	
	-- Border stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = CONFIG.BorderColor
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = container
	
	-- Inner glow
	local innerGlow = Instance.new("Frame")
	innerGlow.Name = "InnerGlow"
	innerGlow.Size = UDim2.new(1, -4, 1, -4)
	innerGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
	innerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	innerGlow.BackgroundColor3 = CONFIG.BorderColor
	innerGlow.BackgroundTransparency = 0.9
	innerGlow.BorderSizePixel = 0
	innerGlow.Parent = container
	
	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0, 10)
	innerCorner.Parent = innerGlow
	
	-- Star icon
	local starIcon = Instance.new("TextLabel")
	starIcon.Name = "StarIcon"
	starIcon.Size = UDim2.new(0, 35, 0, 35)
	starIcon.Position = UDim2.new(0, 10, 0.5, 0)
	starIcon.AnchorPoint = Vector2.new(0, 0.5)
	starIcon.BackgroundTransparency = 1
	starIcon.Text = "⭐"
	starIcon.TextColor3 = CONFIG.IconColor
	starIcon.Font = Enum.Font.GothamBold
	starIcon.TextSize = 28
	starIcon.TextXAlignment = Enum.TextXAlignment.Center
	starIcon.Parent = container
	
	-- Kudos amount label
	local label = Instance.new("TextLabel")
	label.Name = "KudosLabel"
	label.Size = UDim2.new(1, -55, 1, 0)
	label.Position = UDim2.new(0, 50, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = "0"
	label.TextColor3 = CONFIG.TextColor
	label.Font = Enum.Font.GothamBold
	label.TextSize = 24
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = container
	
	-- "KUDOS" subtitle
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(0, 50, 0, 12)
	subtitle.Position = UDim2.new(1, -8, 1, -14)
	subtitle.AnchorPoint = Vector2.new(1, 1)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "KUDOS"
	subtitle.TextColor3 = CONFIG.TextColor
	subtitle.TextTransparency = 0.4
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextSize = 10
	subtitle.TextXAlignment = Enum.TextXAlignment.Right
	subtitle.Parent = container
	
	kudosGui = gui
	kudosLabel = label
	
	return gui
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         REWARD POPUP                                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function showRewardPopup(amount)
	if not kudosGui then return end
	
	local container = kudosGui:FindFirstChild("KudosContainer")
	if not container then return end
	
	-- Create popup label
	local popup = Instance.new("TextLabel")
	popup.Name = "RewardPopup"
	popup.Size = UDim2.new(0, 80, 0, 30)
	popup.Position = UDim2.new(0.5, 0, 0, -5)
	popup.AnchorPoint = Vector2.new(0.5, 1)
	popup.BackgroundTransparency = 1
	popup.Text = string.format("+%d", amount)
	popup.TextColor3 = CONFIG.PopupColor
	popup.TextStrokeColor3 = Color3.new(0, 0, 0)
	popup.TextStrokeTransparency = 0.3
	popup.Font = Enum.Font.GothamBold
	popup.TextSize = 20
	popup.TextScaled = false
	popup.Parent = container
	
	-- Animate popup
	local startPos = popup.Position
	local endPos = UDim2.new(0.5, 0, 0, -50)
	
	-- Float up and fade out
	local moveTween = TweenService:Create(popup, TweenInfo.new(CONFIG.PopupDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = endPos,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	
	-- Scale up initially
	popup.TextSize = 16
	TweenService:Create(popup, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = 24
	}):Play()
	
	moveTween:Play()
	moveTween.Completed:Connect(function()
		popup:Destroy()
	end)
	
	-- Pulse the container
	local stroke = container:FindFirstChild("UIStroke")
	if stroke then
		local originalColor = stroke.Color
		stroke.Color = Color3.new(1, 1, 1)
		TweenService:Create(stroke, TweenInfo.new(0.3), {
			Color = originalColor
		}):Play()
	end
	
	-- Bounce the star
	local star = container:FindFirstChild("StarIcon")
	if star then
		local originalSize = star.TextSize
		star.TextSize = originalSize + 8
		TweenService:Create(star, TweenInfo.new(0.2, Enum.EasingStyle.Elastic), {
			TextSize = originalSize
		}):Play()
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KUDOS DISPLAY UPDATE                                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function updateKudosDisplay(dt)
	if not kudosLabel then return end
	
	-- Smoothly count up to target
	if displayedKudos < currentKudos then
		local diff = currentKudos - displayedKudos
		local increment = math.max(1, math.ceil(CONFIG.CountUpSpeed * dt))
		displayedKudos = math.min(displayedKudos + increment, currentKudos)
	elseif displayedKudos > currentKudos then
		displayedKudos = currentKudos
	end
	
	kudosLabel.Text = tostring(math.floor(displayedKudos))
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         REPLICA HANDLING                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function setupReplicaListener()
	-- Wait for the kudos replica (ReplicaController already required at top of file)
	ReplicaController.ReplicaOfClassCreated("PlayerKudos_" .. player.UserId, function(replica)
		print("[KudosController] Kudos replica received!")
		
		-- Initial sync
		currentKudos = replica.Data.Kudos or 0
		displayedKudos = currentKudos
		lastAwardTime = replica.Data.LastAwardTime or 0
		
		if kudosLabel then
			kudosLabel.Text = tostring(currentKudos)
		end
		
		-- Listen for changes
		replica:ListenToChange({"Kudos"}, function(newValue)
			local oldKudos = currentKudos
			currentKudos = newValue
			
			-- Show popup for the difference
			if newValue > oldKudos then
				local awarded = newValue - oldKudos
				showRewardPopup(awarded)
			end
		end)
		
		replica:ListenToChange({"LastAward"}, function(newValue)
			-- Could trigger additional effects here
		end)
		
		print(string.format("[KudosController] Initial kudos: %d", currentKudos))
	end)
	
	-- Request replicas
	ReplicaController.RequestData()
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         GATE COLLECTION EFFECTS                             ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function createGateCollectionEffect(gate, kudosReward)
	if not gate or not gate.Parent then return end
	
	-- Get the center glow part
	local centerGlow = gate:FindFirstChild("CenterGlow")
	local ringParts = {}
	local orbParts = {}
	
	for _, part in ipairs(gate:GetDescendants()) do
		if part:IsA("BasePart") then
			if part.Name:match("^Ring_") then
				table.insert(ringParts, part)
			elseif part.Name:match("Orb$") then
				table.insert(orbParts, part)
			end
		end
	end
	
	-- ═══════════════════════════════════════════════════════════════
	-- EFFECT 1: Expand and fade the ring
	-- ═══════════════════════════════════════════════════════════════
	task.spawn(function()
		for _, ringPart in ipairs(ringParts) do
			local originalSize = ringPart.Size
			local originalTransparency = ringPart.Transparency
			
			-- Quick scale up and fade
			local scaleTween = TweenService:Create(ringPart, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = originalSize * 1.5,
				Transparency = 1,
			})
			scaleTween:Play()
		end
	end)
	
	-- ═══════════════════════════════════════════════════════════════
	-- EFFECT 2: Flash center glow bright then fade
	-- ═══════════════════════════════════════════════════════════════
	if centerGlow then
		task.spawn(function()
			local originalColor = centerGlow.Color
			local originalTransparency = centerGlow.Transparency
			
			-- Flash bright
			centerGlow.Color = Color3.new(1, 1, 1)
			centerGlow.Transparency = 0.3
			
			-- Scale up
			local originalSize = centerGlow.Size
			TweenService:Create(centerGlow, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = originalSize * Vector3.new(1, 1.3, 1.3),
			}):Play()
			
			task.wait(0.15)
			
			-- Fade to transparent
			TweenService:Create(centerGlow, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
				Color = originalColor,
				Size = originalSize * Vector3.new(1, 0.5, 0.5),
			}):Play()
		end)
	end
	
	-- ═══════════════════════════════════════════════════════════════
	-- EFFECT 3: Pulse the orbs
	-- ═══════════════════════════════════════════════════════════════
	for _, orb in ipairs(orbParts) do
		task.spawn(function()
			local originalSize = orb.Size
			
			-- Quick pulse
			TweenService:Create(orb, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = originalSize * 1.8,
			}):Play()
			
			task.wait(0.15)
			
			TweenService:Create(orb, TweenInfo.new(0.3, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
				Size = originalSize,
			}):Play()
		end)
	end
	
	-- ═══════════════════════════════════════════════════════════════
	-- EFFECT 4: Create particle burst from center
	-- ═══════════════════════════════════════════════════════════════
	if centerGlow then
		task.spawn(function()
			-- Create sparkle particles
			local attachment = Instance.new("Attachment")
			attachment.Parent = centerGlow
			
			local particles = Instance.new("ParticleEmitter")
			particles.Color = ColorSequence.new(CONFIG.BorderColor)
			particles.LightEmission = 1
			particles.LightInfluence = 0
			particles.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 3),
				NumberSequenceKeypoint.new(0.5, 2),
				NumberSequenceKeypoint.new(1, 0),
			})
			particles.Texture = "rbxassetid://6490035152"  -- Sparkle texture
			particles.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.8, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			particles.Lifetime = NumberRange.new(0.5, 1)
			particles.Rate = 0
			particles.Speed = NumberRange.new(30, 60)
			particles.SpreadAngle = Vector2.new(180, 180)
			particles.Parent = attachment
			
			-- Emit burst
			particles:Emit(30)
			
			-- Cleanup after particles fade
			task.delay(1.5, function()
				attachment:Destroy()
			end)
		end)
	end
	
	-- ═══════════════════════════════════════════════════════════════
	-- EFFECT 5: Fade out the billboard indicator
	-- ═══════════════════════════════════════════════════════════════
	local billboard = gate:FindFirstChild("KudosIndicator")
	if billboard then
		local kudosFrame = billboard:FindFirstChild("KudosFrame")
		if kudosFrame then
			task.spawn(function()
				-- Scale up and fade
				TweenService:Create(billboard, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = UDim2.new(0, 180, 0, 75),
					StudsOffset = billboard.StudsOffset + Vector3.new(0, 5, 0),
				}):Play()
				
				task.wait(0.3)
				
				-- Fade out
				local label = kudosFrame:FindFirstChild("KudosLabel")
				if label then
					TweenService:Create(label, TweenInfo.new(0.3), {
						TextTransparency = 1,
						TextStrokeTransparency = 1,
					}):Play()
				end
				
				TweenService:Create(kudosFrame, TweenInfo.new(0.3), {
					BackgroundTransparency = 1,
				}):Play()
				
				local stroke = kudosFrame:FindFirstChild("UIStroke")
				if stroke then
					TweenService:Create(stroke, TweenInfo.new(0.3), {
						Transparency = 1,
					}):Play()
				end
			end)
		end
	end
	
	print(string.format("[KudosController] Gate collection effect played for +%d kudos!", kudosReward))
end

local function setupGateCollectionListener()
	local gateCollectedEvent = ReplicatedStorage:WaitForChild("GateCollectedEvent", 10)
	if not gateCollectedEvent then
		warn("[KudosController] GateCollectedEvent not found!")
		return
	end
	
	gateCollectedEvent.OnClientEvent:Connect(function(gate, kudosReward)
		createGateCollectionEffect(gate, kudosReward)
	end)
	
	print("[KudosController] Gate collection listener setup!")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function KudosController:KnitInit()
	print("[KudosController] Initializing...")
end

function KudosController:KnitStart()
	print("[KudosController] Started")
	
	-- Create UI
	createKudosUI()
	
	-- Setup replica listener
	task.spawn(function()
		setupReplicaListener()
	end)
	
	-- Setup gate collection effects
	task.spawn(function()
		setupGateCollectionListener()
	end)
	
	-- Update loop for smooth counting
	RunService.RenderStepped:Connect(function(dt)
		updateKudosDisplay(dt)
	end)
	
	print("[KudosController] Kudos UI ready!")
end

return KudosController

