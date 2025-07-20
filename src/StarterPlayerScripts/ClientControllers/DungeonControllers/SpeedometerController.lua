local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Fusion (function-based modules)
local FusionRoot = CustomPackages:WaitForChild("FusionRoot")
local Fusion = require(FusionRoot:WaitForChild("Fusion"))

local New = Fusion.New
local OnEvent = Fusion.OnEvent
local Value = Fusion.Value -- This is how you use Fusion's state management
local Computed = Fusion.Computed

local SpeedometerController = Knit.CreateController { Name = "SpeedometerController" }

-- Utility to find the top-level machine from any seat
local function findMachineModelFromSeat(seat)
	local model = seat:FindFirstAncestorWhichIsA("Model")
	if model and CollectionService:HasTag(model, "machine") then
		return model
	end
	return nil
end

function SpeedometerController:KnitStart()
	local player = Players.LocalPlayer
	local gui = player:WaitForChild("PlayerGui")

	local function createSpeedometer(rootPart)
		local speedValue = Value(0)

		-- Update MPH based on velocity
		RunService.RenderStepped:Connect(function()
			local velocity = rootPart.Velocity
			local speedMPH = velocity.Magnitude * 1.40625
			speedValue:set(math.floor(speedMPH))
		end)

		-- Create GUI
		local screenGui = New "ScreenGui" {
			Name = "Speedometer",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			Parent = gui
		}

		New "TextLabel" {
			Name = "SpeedLabel",
			Parent = screenGui,
			Size = UDim2.fromOffset(200, 50),
			Position = UDim2.new(1, -210, 1, -60),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 0.3,
			BackgroundColor3 = Color3.fromRGB(20, 20, 20),
			TextColor3 = Color3.new(1, 1, 1),
			TextScaled = true,
			Font = Enum.Font.GothamBold,

			Text = Computed(function()
				return tostring(speedValue:get())
			end)
		}
	end

	local function onSeated(humanoid, isSeated, seat)
		if isSeated and seat then
			local machine = findMachineModelFromSeat(seat)
			if machine then
				local rootPart = machine:FindFirstChild("RootPart")
				if rootPart then
					createSpeedometer(rootPart)
				end
			end
		end
	end

	local function connectSeated()
		local char = player.Character or player.CharacterAdded:Wait()
		local humanoid = char:WaitForChild("Humanoid")
		humanoid.Seated:Connect(function(isSeated, seat)
			onSeated(humanoid, isSeated, seat)
		end)
	end

	if player.Character then
		connectSeated()
	end
	player.CharacterAdded:Connect(connectSeated)
end

function SpeedometerController:KnitInit() end

return SpeedometerController
