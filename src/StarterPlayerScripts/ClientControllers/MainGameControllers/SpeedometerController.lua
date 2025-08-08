local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Fusion
local FusionRoot = CustomPackages:WaitForChild("FusionRoot")
local Fusion = require(FusionRoot:WaitForChild("Fusion"))

local New = Fusion.New
local Value = Fusion.Value
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

local function lerp(a, b, t)
	return a + (b - a) * t
end

function SpeedometerController:KnitStart()
	local player = Players.LocalPlayer
	local gui = player:WaitForChild("PlayerGui")

	local function createSpeedometer(rootPart)
		local targetSpeed = 0
		local displayedSpeed = Value(0)

		-- Interpolate speed manually
		RunService.RenderStepped:Connect(function(dt)
			local velocity = rootPart.Velocity
			targetSpeed = velocity.Magnitude * 1.40625

			local current = displayedSpeed:get()
			local smoothed = lerp(current, targetSpeed, math.clamp(dt * 6, 0, 1))
			displayedSpeed:set(smoothed)
		end)

		-- GUI setup
		local screenGui = New "ScreenGui" {
			Name = "Speedometer",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			Parent = gui
		}

		local frameSize = UDim2.fromOffset(200, 200)

		-- Background Image
		local image = New "ImageLabel" {
			Name = "SpeedometerImage",
			Parent = screenGui,
			Size = frameSize,
			Position = UDim2.new(1, -220, 1, -220),
			AnchorPoint = Vector2.new(0, 0),
			BackgroundTransparency = 1,
			Image = "rbxassetid://94399498242995"
		}

		-- Text on top
        New "TextLabel" {
            Name = "SpeedLabel",
            Parent = image,
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundTransparency = 1,
            TextColor3 = Color3.new(0, 0, 0), -- black text
            TextScaled = false,
            TextSize = 24, -- smaller font
            Font = Enum.Font.GothamBold,
            Text = Computed(function()
                return string.format("%.1f", displayedSpeed:get()) -- no "MPH"
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
