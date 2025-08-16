local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local Players = game:GetService("Players")

-- Fusion
local FusionRoot = CustomPackages:WaitForChild("FusionRoot")
local Fusion = require(FusionRoot:WaitForChild("Fusion"))
local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed

-- Replica
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica:WaitForChild("ReplicaController"))

local GameManagerController = Knit.CreateController { Name = "GameManagerController" }

-- Helper to format seconds into MM:SS.mmm
local function formatTime(seconds)
	local minutes = math.floor(seconds / 60)
	local sec = math.floor(seconds % 60)
	local milliseconds = math.floor((seconds - math.floor(seconds)) * 1000)
	return string.format("%02d:%02d.%03d", minutes, sec, milliseconds)
end

function GameManagerController:createScreenGUI()
	local timeRemaining = Value("0")
	local timerType = Value("Lobby")

	local textValue = Computed(function()
		return timeRemaining:get()
	end)

	local screenGui = New "ScreenGui" {
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		Name = "TeleporterScreenGui"
	}

	New "TextLabel" {
		Parent = screenGui,
		Size = UDim2.new(0.5, 0, 0.1, 0),
		Position = UDim2.new(0.25, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = textValue,
		TextColor3 = Color3.fromRGB(248, 246, 128),
		TextScaled = true,
		Font = Enum.Font.DenkOne
	}

	ReplicaController.ReplicaOfClassCreated("TimerReplica", function(timer_replica)

		-- Raw seconds for Lobby
		timer_replica:ListenToChange({ "TimeRemaining" }, function(new_value)
			timerType:set("Lobby")
			timeRemaining:set(tostring(math.floor(new_value)))
		--	print("[LOBBY]", new_value)
		end)

		-- Formatted MM:SS.mmm for Game
		timer_replica:ListenToChange({ "GameTimeRemaining" }, function(new_value)
			timerType:set("Game")
			timeRemaining:set(formatTime(new_value))
			--print("[GAME]", formatTime(new_value))
		end)

		-- Formatted MM:SS.mmm for Return
		timer_replica:ListenToChange({ "ReturnTimeRemaining" }, function(new_value)
			timerType:set("Return")
			timeRemaining:set(formatTime(new_value))
			--print("[RETURN]", formatTime(new_value))
		end)
	end)
end

function init()
	ReplicaController.RequestData()
	self:createScreenGUI()
end

function GameManagerController:KnitInit()
	
end

function GameManagerController:KnitStart()
	-- Optional: Add startup logic here
end

return GameManagerController
