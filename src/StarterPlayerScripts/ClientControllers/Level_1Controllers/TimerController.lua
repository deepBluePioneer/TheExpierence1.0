local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Replica Module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica.ReplicaController)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local TimerController = Knit.CreateController {
	Name = "TimerController",
}

-- === GUI CREATION ===

local function createTimerGui()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TimerGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = PlayerGui
	
	-- Main frame
	local frame = Instance.new("Frame")
	frame.Name = "TimerFrame"
	frame.Size = UDim2.new(0, 200, 0, 80)
	frame.Position = UDim2.new(0.5, -100, 0, 20)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	
	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	
	-- Stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 100, 120)
	stroke.Thickness = 2
	stroke.Parent = frame
	
	-- Title label
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0, 25)
	titleLabel.Position = UDim2.new(0, 0, 0, 5)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "TIME REMAINING"
	titleLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	titleLabel.TextSize = 14
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = frame
	
	-- Timer label
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, 0, 0, 45)
	timerLabel.Position = UDim2.new(0, 0, 0, 30)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "0:00"
	timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	timerLabel.TextSize = 36
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.Parent = frame
	
	return timerLabel
end

local function formatTime(seconds)
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", mins, secs)
end

-- === KNIT LIFECYCLE ===

function TimerController:KnitInit()
	-- Request replica data from server
	ReplicaController.RequestData()
end

function TimerController:KnitStart()
	local timerLabel = createTimerGui()
	
	-- Listen for the GridTimerReplica
	ReplicaController.ReplicaOfClassCreated("GridTimerReplica", function(replica)
		print("[TimerController] Received GridTimerReplica")
		
		-- Set initial value
		timerLabel.Text = formatTime(replica.Data.TimeRemaining)
		
		-- Listen for time changes
		replica:ListenToChange({"TimeRemaining"}, function(newValue)
			timerLabel.Text = formatTime(newValue)
			
			-- Change color when low on time
			if newValue <= 10 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 80, 80)  -- Red
			elseif newValue <= 30 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 200, 80)  -- Yellow
			else
				timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)  -- White
			end
		end)
		
		-- Listen for running state changes
		replica:ListenToChange({"IsRunning"}, function(isRunning)
			if isRunning then
				timerLabel.Parent.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
			else
				timerLabel.Parent.BackgroundColor3 = Color3.fromRGB(50, 30, 30)
			end
		end)
	end)
end

return TimerController

