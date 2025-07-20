local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
-- Fusion
local FusionRoot = CustomPackages:WaitForChild("FusionRoot")
local Fusion = require(FusionRoot:WaitForChild("Fusion"))
local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed

-- Replica
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica:WaitForChild("ReplicaController"))
local PatchUIController = Knit.CreateController { Name = "PatchUIController" }

function PatchUIController:KnitStart()
    -- Add controller startup logic here
end


function PatchUIController:createScreenGUI()


	local screenGui = New "ScreenGui" {
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		Name = "PlayerPatch"
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

		
	end)
end

function PatchUIController:KnitInit()
	ReplicaController.RequestData()
	--self:createScreenGUI()
end



return PatchUIController