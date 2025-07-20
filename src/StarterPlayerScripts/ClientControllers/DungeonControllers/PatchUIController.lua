-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Fusion
local FusionRoot = CustomPackages:WaitForChild("FusionRoot")
local Fusion = require(FusionRoot:WaitForChild("Fusion"))
local New = Fusion.New
local Value = Fusion.Value
local Computed = Fusion.Computed

-- Patch Types and IDs
local offenseID = 98406035373604
local speedBoostID = 123435038795023
local topSpeedID = 124394366919392

local patchIcons = {
	Offense = "rbxassetid://" .. offenseID,
	SpeedBoost = "rbxassetid://" .. speedBoostID,
	TopSpeed = "rbxassetid://" .. topSpeedID,
}

-- Replica
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica:WaitForChild("ReplicaController"))

local PatchUIController = Knit.CreateController { Name = "PatchUIController" }

-- Track all active ImageLabels above the head
local activeIcons = {}

function PatchUIController:CreateIconAboveHead(character, imageId)
	local head = character:FindFirstChild("Head")
	if not head then return end

	-- Billboard GUI setup
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "PatchIconUI"
	billboard.Adornee = head
	billboard.Size = UDim2.new(4, 0, 4, 0)
	billboard.StudsOffset = Vector3.new(0, 3 + math.random(), 0) -- vertical jitter
	billboard.AlwaysOnTop = true
	billboard.Parent = head

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(0.5, 0, 0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Image = imageId
	icon.ImageTransparency = 1
	icon.Parent = billboard

	-- Animate icon appearance
	TweenService:Create(icon, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		ImageTransparency = 0
	}):Play()
	TweenService:Create(icon, TweenInfo.new(0.25, Enum.EasingStyle.Back), {
		Size = UDim2.new(1, 0, 1, 0)
	}):Play()

	-- Shift existing icons left
	local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, otherIcon in ipairs(activeIcons) do
		if otherIcon and otherIcon ~= icon and otherIcon.Parent then
			local newPos = otherIcon.Position - UDim2.new(0.75, 0, 0, 0)
			TweenService:Create(otherIcon, tweenInfo, { Position = newPos }):Play()
		end
	end

	table.insert(activeIcons, icon)

	-- Hide and destroy after 3s
	task.delay(3, function()
		TweenService:Create(icon, TweenInfo.new(0.25), {
			ImageTransparency = 1
		}):Play()
		task.delay(0.3, function()
			if billboard and billboard.Parent then
				billboard:Destroy()
			end
		end)

		-- Remove from active icon list
		for i, obj in ipairs(activeIcons) do
			if obj == icon then
				table.remove(activeIcons, i)
				break
			end
		end
	end)
end

function PatchUIController:KnitStart()
	ReplicaController.ReplicaOfClassCreated("PatchNotifier", function(replica)
		replica:ListenToChange("PatchType", function(newType)
			if newType and patchIcons[newType] then
				local character = Players.LocalPlayer.Character
				if character then
					self:CreateIconAboveHead(character, patchIcons[newType])
				end
			end
		end)
	end)
end

function PatchUIController:KnitInit()
	ReplicaController.RequestData()
end

return PatchUIController
