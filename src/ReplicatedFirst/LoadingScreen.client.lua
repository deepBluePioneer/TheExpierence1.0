local ContentProvider = game:GetService("ContentProvider")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------------
-- Colors / style
---------------------------------------------------------------------------
local BG_COLOR       = Color3.fromRGB(6, 8, 18)
local ACCENT_CYAN    = Color3.fromRGB(0, 220, 255)
local ACCENT_PINK    = Color3.fromRGB(255, 30, 100)
local TEXT_WHITE     = Color3.fromRGB(255, 255, 255)
local TEXT_DIM       = Color3.fromRGB(120, 135, 170)
local BAR_TRACK      = Color3.fromRGB(20, 24, 40)
local BAR_FILL       = ACCENT_CYAN

---------------------------------------------------------------------------
-- Tips
---------------------------------------------------------------------------
local TIPS = {
	"Switch lanes to dodge hazards",
	"Collect blue cubes for points",
	"Hit purple portals to enter overdrive",
	"Pick up green cubes for bombs",
	"Hold SPACE to deploy bombs",
	"Chain combos for bonus score",
}
local TIP_CYCLE_TIME = 4

---------------------------------------------------------------------------
-- Build GUI
---------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreen"
screenGui.DisplayOrder = 999
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local bg = Instance.new("Frame")
bg.Name = "Background"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = BG_COLOR
bg.BorderSizePixel = 0
bg.Parent = screenGui

-- Subtle gradient overlay
local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 14, 30)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(6, 8, 18)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 10, 24)),
})
gradient.Rotation = 135
gradient.Parent = bg

---------------------------------------------------------------------------
-- Title: "PULSE RIDER"
---------------------------------------------------------------------------
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.Position = UDim2.new(0.5, 0, 0.38, 0)
titleLabel.Size = UDim2.new(0.8, 0, 0, 80)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "PULSE  RIDER"
titleLabel.TextColor3 = TEXT_WHITE
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextScaled = true
titleLabel.Parent = bg

local titleConstraint = Instance.new("UITextSizeConstraint")
titleConstraint.MaxTextSize = 72
titleConstraint.Parent = titleLabel

local titleStroke = Instance.new("UIStroke")
titleStroke.Color = ACCENT_CYAN
titleStroke.Thickness = 2
titleStroke.Transparency = 0.3
titleStroke.Parent = titleLabel

---------------------------------------------------------------------------
-- Tagline
---------------------------------------------------------------------------
local tagline = Instance.new("TextLabel")
tagline.Name = "Tagline"
tagline.AnchorPoint = Vector2.new(0.5, 0)
tagline.Position = UDim2.new(0.5, 0, 0.38, 50)
tagline.Size = UDim2.new(0.6, 0, 0, 24)
tagline.BackgroundTransparency = 1
tagline.Text = "RIDE THE BEAT. DODGE THE DROP."
tagline.TextColor3 = ACCENT_PINK
tagline.Font = Enum.Font.GothamBold
tagline.TextScaled = true
tagline.Parent = bg

local tagConstraint = Instance.new("UITextSizeConstraint")
tagConstraint.MaxTextSize = 18
tagConstraint.Parent = tagline

---------------------------------------------------------------------------
-- Tip text (rotates)
---------------------------------------------------------------------------
local tipLabel = Instance.new("TextLabel")
tipLabel.Name = "Tip"
tipLabel.AnchorPoint = Vector2.new(0.5, 0.5)
tipLabel.Position = UDim2.new(0.5, 0, 0.68, 0)
tipLabel.Size = UDim2.new(0.7, 0, 0, 22)
tipLabel.BackgroundTransparency = 1
tipLabel.Text = TIPS[1]
tipLabel.TextColor3 = TEXT_DIM
tipLabel.Font = Enum.Font.GothamBold
tipLabel.TextScaled = true
tipLabel.TextTransparency = 0
tipLabel.Parent = bg

local tipConstraint = Instance.new("UITextSizeConstraint")
tipConstraint.MaxTextSize = 16
tipConstraint.Parent = tipLabel

---------------------------------------------------------------------------
-- Progress bar
---------------------------------------------------------------------------
local barTrack = Instance.new("Frame")
barTrack.Name = "BarTrack"
barTrack.AnchorPoint = Vector2.new(0.5, 0.5)
barTrack.Position = UDim2.new(0.5, 0, 0.76, 0)
barTrack.Size = UDim2.new(0.4, 0, 0, 6)
barTrack.BackgroundColor3 = BAR_TRACK
barTrack.BorderSizePixel = 0
barTrack.Parent = bg

local barTrackCorner = Instance.new("UICorner")
barTrackCorner.CornerRadius = UDim.new(0.5, 0)
barTrackCorner.Parent = barTrack

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BackgroundColor3 = BAR_FILL
barFill.BorderSizePixel = 0
barFill.Parent = barTrack

local barFillCorner = Instance.new("UICorner")
barFillCorner.CornerRadius = UDim.new(0.5, 0)
barFillCorner.Parent = barFill

local barGlow = Instance.new("UIStroke")
barGlow.Color = BAR_FILL
barGlow.Thickness = 1
barGlow.Transparency = 0.5
barGlow.Parent = barTrack

---------------------------------------------------------------------------
-- Percentage label
---------------------------------------------------------------------------
local pctLabel = Instance.new("TextLabel")
pctLabel.Name = "Percent"
pctLabel.AnchorPoint = Vector2.new(0.5, 0)
pctLabel.Position = UDim2.new(0.5, 0, 0.76, 10)
pctLabel.Size = UDim2.new(0.3, 0, 0, 18)
pctLabel.BackgroundTransparency = 1
pctLabel.Text = "Loading... 0%"
pctLabel.TextColor3 = TEXT_DIM
pctLabel.Font = Enum.Font.GothamBold
pctLabel.TextScaled = true
pctLabel.Parent = bg

local pctConstraint = Instance.new("UITextSizeConstraint")
pctConstraint.MaxTextSize = 14
pctConstraint.Parent = pctLabel

---------------------------------------------------------------------------
-- Tip cycling coroutine
---------------------------------------------------------------------------
local tipIndex = 1
local tipRunning = true

task.spawn(function()
	while tipRunning do
		task.wait(TIP_CYCLE_TIME)
		if not tipRunning then break end

		local fadeOut = TweenService:Create(tipLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
		})
		fadeOut:Play()
		fadeOut.Completed:Wait()

		tipIndex = (tipIndex % #TIPS) + 1
		tipLabel.Text = TIPS[tipIndex]

		local fadeIn = TweenService:Create(tipLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 0,
		})
		fadeIn:Play()
		fadeIn.Completed:Wait()
	end
end)

---------------------------------------------------------------------------
-- Title glow pulse
---------------------------------------------------------------------------
task.spawn(function()
	while tipRunning do
		local t = (os.clock() * 0.8) % 1
		local alpha = 0.3 + math.sin(t * math.pi * 2) * 0.15
		titleStroke.Transparency = math.clamp(alpha, 0, 1)
		task.wait()
	end
end)

---------------------------------------------------------------------------
-- Asset preloading + progress
---------------------------------------------------------------------------
local loadingDone = false

task.spawn(function()
	local reps = game:GetService("ReplicatedStorage")
	reps:WaitForChild("Packages", 30)
	reps:WaitForChild("CustomPackages", 30)

	local assetsToLoad = {}
	local function collectAssets(parent, depth)
		if depth > 4 then return end
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("Sound") or child:IsA("Decal") or child:IsA("Texture") or child:IsA("ImageLabel") or child:IsA("ImageButton") then
				table.insert(assetsToLoad, child)
			end
			collectAssets(child, depth + 1)
		end
	end
	collectAssets(reps, 0)

	local workspace = game:GetService("Workspace")
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") or child:IsA("Sound") then
			table.insert(assetsToLoad, child)
		end
	end

	local total = math.max(#assetsToLoad, 1)
	local loaded = 0

	if total > 1 then
		ContentProvider:PreloadAsync(assetsToLoad, function()
			loaded = loaded + 1
			local frac = loaded / total
			barFill.Size = UDim2.new(math.clamp(frac, 0, 1), 0, 1, 0)
			pctLabel.Text = string.format("Loading... %d%%", math.floor(frac * 100))
		end)
	end

	barFill.Size = UDim2.new(1, 0, 1, 0)
	pctLabel.Text = "Loading... 100%"
	loadingDone = true
end)

---------------------------------------------------------------------------
-- Wait for Knit + preload, then fade out
---------------------------------------------------------------------------
while not (loadingDone and _G.__KNIT_READY) do
	task.wait(0.1)
end

task.wait(0.5)

tipRunning = false

local fadeOut = TweenService:Create(bg, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	BackgroundTransparency = 1,
})
fadeOut:Play()

for _, child in ipairs(bg:GetDescendants()) do
	if child:IsA("TextLabel") then
		TweenService:Create(child, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
		}):Play()
	elseif child:IsA("Frame") then
		TweenService:Create(child, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	elseif child:IsA("UIStroke") then
		TweenService:Create(child, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		}):Play()
	end
end

fadeOut.Completed:Wait()
screenGui:Destroy()
