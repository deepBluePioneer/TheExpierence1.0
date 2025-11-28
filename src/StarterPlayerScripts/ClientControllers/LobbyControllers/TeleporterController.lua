local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage.CustomPackages
local Knit = require(Packages.Knit)

-- Replica module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica.ReplicaController)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local TeleporterController = Knit.CreateController {
	Name = "TeleporterController",
}

-- UI References
TeleporterController.ScreenGui = nil
TeleporterController.ZoneFrame = nil
TeleporterController.ZoneLabel = nil
TeleporterController.CurrentZone = nil
TeleporterController.TeleporterReplica = nil

function TeleporterController:CreateUI()
	-- Main ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TeleporterUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = PlayerGui
	self.ScreenGui = screenGui
	
	-- Zone notification frame (hidden by default)
	local zoneFrame = Instance.new("Frame")
	zoneFrame.Name = "ZoneFrame"
	zoneFrame.Size = UDim2.new(0.3, 0, 0.15, 0)
	zoneFrame.Position = UDim2.new(0.35, 0, 0.75, 0)
	zoneFrame.AnchorPoint = Vector2.new(0, 0)
	zoneFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	zoneFrame.BackgroundTransparency = 0.2
	zoneFrame.BorderSizePixel = 0
	zoneFrame.Visible = false
	zoneFrame.Parent = screenGui
	self.ZoneFrame = zoneFrame
	
	-- Corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.1, 0)
	corner.Parent = zoneFrame
	
	-- Stroke/border
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.5
	stroke.Parent = zoneFrame
	self.ZoneStroke = stroke
	
	-- Gradient background
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 40, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 30)),
	})
	gradient.Rotation = 90
	gradient.Parent = zoneFrame
	
	-- Zone title label
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0.4, 0)
	titleLabel.Position = UDim2.new(0, 0, 0.05, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "TELEPORTER ZONE"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = zoneFrame
	self.ZoneLabel = titleLabel
	
	-- Zone name label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.35, 0)
	nameLabel.Position = UDim2.new(0, 0, 0.4, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "Zone 1"
	nameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.Parent = zoneFrame
	self.NameLabel = nameLabel
	
	-- Instruction label
	local instructionLabel = Instance.new("TextLabel")
	instructionLabel.Name = "InstructionLabel"
	instructionLabel.Size = UDim2.new(1, 0, 0.2, 0)
	instructionLabel.Position = UDim2.new(0, 0, 0.75, 0)
	instructionLabel.BackgroundTransparency = 1
	instructionLabel.Text = "Press E to teleport"
	instructionLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	instructionLabel.TextScaled = true
	instructionLabel.Font = Enum.Font.GothamMedium
	instructionLabel.Parent = zoneFrame
	self.InstructionLabel = instructionLabel
end

function TeleporterController:ShowZoneUI(zoneName, teleporterName, zoneColor)
	if not self.ZoneFrame then return end
	
	local color = zoneColor or Color3.fromRGB(255, 255, 255)
	local displayName = zoneName:gsub("Zone", " "):gsub("Teleporter", "Zone ")
	
	-- Update colors
	self.ZoneLabel.TextColor3 = color
	self.ZoneStroke.Color = color
	self.NameLabel.Text = displayName
	
	-- Show with tween
	self.ZoneFrame.Visible = true
	self.ZoneFrame.Position = UDim2.new(0.35, 0, 0.85, 0)
	self.ZoneFrame.BackgroundTransparency = 1
	
	local showTween = TweenService:Create(self.ZoneFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.35, 0, 0.75, 0),
		BackgroundTransparency = 0.2,
	})
	showTween:Play()
	
	self.CurrentZone = zoneName
end

function TeleporterController:HideZoneUI()
	if not self.ZoneFrame then return end
	
	local hideTween = TweenService:Create(self.ZoneFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.35, 0, 0.85, 0),
		BackgroundTransparency = 1,
	})
	hideTween:Play()
	hideTween.Completed:Connect(function()
		if self.CurrentZone == nil then
			self.ZoneFrame.Visible = false
		end
	end)
	
	self.CurrentZone = nil
end

function TeleporterController:SetupReplicaListeners(replica)
	self.TeleporterReplica = replica
	
	-- Listen to CurrentZone changes
	replica:ListenToChange({ "CurrentZone" }, function(newZone, oldZone)
		print("Zone changed from", oldZone, "to", newZone)
		
		if newZone and newZone ~= "" then
			-- Player entered a zone
			local teleporterName = replica.Data.TeleporterName
			local colorData = replica.Data.ZoneColor
			local zoneColor = Color3.fromRGB(colorData.R, colorData.G, colorData.B)
			self:ShowZoneUI(newZone, teleporterName, zoneColor)
		else
			-- Player exited zone
			self:HideZoneUI()
		end
	end)
	
	-- Listen to color changes (in case it updates while in zone)
	replica:ListenToChange({ "ZoneColor" }, function(newColor)
		if self.CurrentZone then
			local zoneColor = Color3.fromRGB(newColor.R, newColor.G, newColor.B)
			self.ZoneLabel.TextColor3 = zoneColor
			self.ZoneStroke.Color = zoneColor
		end
	end)
	
	-- Check initial state (in case player spawns in a zone)
	local initialZone = replica.Data.CurrentZone
	if initialZone and initialZone ~= "" then
		local teleporterName = replica.Data.TeleporterName
		local colorData = replica.Data.ZoneColor
		local zoneColor = Color3.fromRGB(colorData.R, colorData.G, colorData.B)
		self:ShowZoneUI(initialZone, teleporterName, zoneColor)
	end
end

function TeleporterController:KnitInit()
	print("TeleporterController: Initializing...")
	self:CreateUI()
	
	-- Request replica data
	ReplicaController.RequestData()
end

function TeleporterController:KnitStart()
	print("TeleporterController: Starting...")
	
	-- Listen for our player's TeleporterReplica
	local replicaClassName = "TeleporterReplica_" .. LocalPlayer.UserId
	
	ReplicaController.ReplicaOfClassCreated(replicaClassName, function(replica)
		print("TeleporterController: Replica received -", replica.Class)
		self:SetupReplicaListeners(replica)
	end)
end

return TeleporterController
