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

-- State
TeleporterController.ScreenGui = nil
TeleporterController.ZoneFrame = nil
TeleporterController.CurrentZone = nil
TeleporterController.QueueReplica = nil -- For popup UI (complex data)
TeleporterController.QueueCountReplica = nil -- For billboard counts (simple data)
TeleporterController.Billboards = {} -- References to server-created billboard labels

--=============================================
-- BILLBOARD UPDATES (Client updates server-created billboards)
--=============================================

function TeleporterController:FindBillboards()
	local zonesFolder = workspace:WaitForChild("TeleporterZones", 10)
	if not zonesFolder then
		warn("[TeleporterController] TeleporterZones folder not found!")
		return
	end

	-- Handle already-present children
	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
		self:TryRegisterZonePart(zonePart)
	end

	-- Handle children that stream in later
	zonesFolder.ChildAdded:Connect(function(child)
		print("[TeleporterController] ChildAdded in TeleporterZones:", child.Name)
		self:TryRegisterZonePart(child)
	end)

	print("[TeleporterController] Billboard discovery hooked. Current count:", self:CountBillboards())
	-- Apply any pending updates that came in before billboards were found
	self:ApplyPendingBillboardUpdates()
end


function TeleporterController:CountBillboards()
	local count = 0
	for _ in pairs(self.Billboards) do
		count = count + 1
	end
	return count
end

function TeleporterController:UpdateBillboard(zoneName, playerCount, maxPlayers)
	local countLabel = self.Billboards[zoneName]
	if not countLabel then 
		-- Store pending update for when billboard is found
		self.PendingBillboardUpdates = self.PendingBillboardUpdates or {}
		self.PendingBillboardUpdates[zoneName] = { Count = playerCount, Max = maxPlayers }
		warn("[TeleporterController] No billboard for", zoneName, "- stored pending update:", playerCount, "/", maxPlayers)
		return 
	end
	
	local newText = string.format("%d/%d", playerCount, maxPlayers)
	print("[TeleporterController] >>> UPDATING BILLBOARD", zoneName, "to", newText)
	countLabel.Text = newText
	
	if playerCount >= maxPlayers then
		countLabel.TextColor3 = Color3.fromRGB(255, 100, 100) -- Full
	elseif playerCount > 0 then
		countLabel.TextColor3 = Color3.fromRGB(100, 255, 100) -- Has players
	else
		countLabel.TextColor3 = Color3.fromRGB(200, 200, 200) -- Empty
	end
end
function TeleporterController:TryRegisterZonePart(zonePart)
	if not zonePart:IsA("BasePart") then return end

	local zoneName = zonePart.Name
	local billboard = zonePart:FindFirstChild("QueueBillboard")

	if not billboard then
		-- In case QueueBillboard gets added later
		zonePart.ChildAdded:Connect(function(child)
			if child.Name == "QueueBillboard" then
				self:TryRegisterZonePart(zonePart)
			end
		end)
		return
	end

	local bg = billboard:FindFirstChild("Background")
	if not bg then return end

	local countLabel = bg:FindFirstChild("QueueCount")
	if not countLabel then return end

	self.Billboards[zoneName] = countLabel
	print("[TeleporterController] Registered billboard for", zoneName, "->", countLabel:GetFullName())

	-- If we already have replica data, apply it immediately
	if self.QueueCountReplica and self.QueueCountReplica.Data.Counts[zoneName] then
		local data = self.QueueCountReplica.Data.Counts[zoneName]
		self:UpdateBillboard(zoneName, data.Count or 0, data.Max or 8)
	end

	-- Also apply any pending updates that were cached
	if self.PendingBillboardUpdates and self.PendingBillboardUpdates[zoneName] then
		local data = self.PendingBillboardUpdates[zoneName]
		print("[TeleporterController] Applying pending update for", zoneName, "from TryRegisterZonePart")
		self:UpdateBillboard(zoneName, data.Count, data.Max)
		self.PendingBillboardUpdates[zoneName] = nil
	end
end

function TeleporterController:ApplyPendingBillboardUpdates()
	if not self.PendingBillboardUpdates then return end
	
	for zoneName, data in pairs(self.PendingBillboardUpdates) do
		if self.Billboards[zoneName] then
			print("[TeleporterController] Applying pending update for", zoneName)
			self:UpdateBillboard(zoneName, data.Count, data.Max)
			self.PendingBillboardUpdates[zoneName] = nil
		end
	end
end

function TeleporterController:UpdateAllBillboards()
	if not self.QueueCountReplica then 
		return -- Silent fail, will be called again when replica arrives
	end
	
	local counts = self.QueueCountReplica.Data.Counts
	if not counts then
		return
	end
	
	for zoneName, countData in pairs(counts) do
		if countData then
			self:UpdateBillboard(zoneName, countData.Count or 0, countData.Max or 8)
		end
	end
end

function TeleporterController:SetupQueueCountReplicaListeners(replica)
	self.QueueCountReplica = replica
	print("[TeleporterController] QueueCountReplica received!")
	
	-- Listen for any count changes
	replica:ListenToRaw(function(actionName, pathArray)
		print("[TeleporterController] QueueCountReplica change:", actionName, table.concat(pathArray, "."))
		
		if pathArray[1] == "Counts" and pathArray[2] then
			local zoneName = pathArray[2]
			local countData = replica.Data.Counts[zoneName]
			
			if countData then
				print("[TeleporterController] Billboard update for", zoneName, ":", countData.Count, "/", countData.Max)
				self:UpdateBillboard(zoneName, countData.Count or 0, countData.Max or 8)
			end
		end
	end)
	
	-- Initial update of all billboards if we have them
	if self:CountBillboards() > 0 then
		print("[TeleporterController] Have billboards, updating from QueueCountReplica")
		self:UpdateAllBillboards()
	end
end

--=============================================
-- POPUP UI (When player enters zone)
--=============================================

function TeleporterController:CreatePopupUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TeleporterUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = PlayerGui
	self.ScreenGui = screenGui
	
	-- Zone frame (hidden by default)
	local zoneFrame = Instance.new("Frame")
	zoneFrame.Name = "ZoneFrame"
	zoneFrame.Size = UDim2.new(0.35, 0, 0.25, 0)
	zoneFrame.Position = UDim2.new(0.325, 0, 0.7, 0)
	zoneFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	zoneFrame.BackgroundTransparency = 0.1
	zoneFrame.BorderSizePixel = 0
	zoneFrame.Visible = false
	zoneFrame.Parent = screenGui
	self.ZoneFrame = zoneFrame
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.05, 0)
	corner.Parent = zoneFrame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = zoneFrame
	self.ZoneStroke = stroke
	
	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0.2, 0)
	titleLabel.Position = UDim2.new(0, 0, 0.02, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "TELEPORTER ZONE"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = zoneFrame
	self.TitleLabel = titleLabel
	
	-- Queue count
	local queueLabel = Instance.new("TextLabel")
	queueLabel.Name = "QueueLabel"
	queueLabel.Size = UDim2.new(1, 0, 0.18, 0)
	queueLabel.Position = UDim2.new(0, 0, 0.22, 0)
	queueLabel.BackgroundTransparency = 1
	queueLabel.Text = "Players: 0/8"
	queueLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	queueLabel.TextScaled = true
	queueLabel.Font = Enum.Font.GothamMedium
	queueLabel.Parent = zoneFrame
	self.QueueLabel = queueLabel
	
	-- Countdown
	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "CountdownLabel"
	countdownLabel.Size = UDim2.new(1, 0, 0.25, 0)
	countdownLabel.Position = UDim2.new(0, 0, 0.4, 0)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Text = "Waiting for players..."
	countdownLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
	countdownLabel.TextScaled = true
	countdownLabel.Font = Enum.Font.GothamBold
	countdownLabel.Parent = zoneFrame
	self.CountdownLabel = countdownLabel
	
	-- Player list
	local playerListFrame = Instance.new("Frame")
	playerListFrame.Name = "PlayerListFrame"
	playerListFrame.Size = UDim2.new(0.9, 0, 0.28, 0)
	playerListFrame.Position = UDim2.new(0.05, 0, 0.66, 0)
	playerListFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
	playerListFrame.BackgroundTransparency = 0.5
	playerListFrame.BorderSizePixel = 0
	playerListFrame.Parent = zoneFrame
	self.PlayerListFrame = playerListFrame
	
	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0.1, 0)
	listCorner.Parent = playerListFrame
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0.02, 0)
	listLayout.Parent = playerListFrame
	
	-- Status
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0.1, 0)
	statusLabel.Position = UDim2.new(0, 0, 0.9, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Step on pad to join queue"
	statusLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Parent = zoneFrame
	self.StatusLabel = statusLabel
end

function TeleporterController:UpdatePlayerList(playerNames)
	for _, child in ipairs(self.PlayerListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	for i, playerName in ipairs(playerNames) do
		if i > 8 then break end
		
		local icon = Instance.new("Frame")
		icon.Size = UDim2.new(0.1, 0, 0.8, 0)
		icon.BackgroundColor3 = playerName == LocalPlayer.Name 
			and Color3.fromRGB(80, 120, 80) 
			or Color3.fromRGB(60, 60, 80)
		icon.BorderSizePixel = 0
		icon.Parent = self.PlayerListFrame
		
		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(0.2, 0)
		iconCorner.Parent = icon
		
		local initial = Instance.new("TextLabel")
		initial.Size = UDim2.new(1, 0, 1, 0)
		initial.BackgroundTransparency = 1
		initial.Text = string.sub(playerName, 1, 1):upper()
		initial.TextColor3 = Color3.fromRGB(255, 255, 255)
		initial.TextScaled = true
		initial.Font = Enum.Font.GothamBold
		initial.Parent = icon
	end
end

function TeleporterController:UpdatePopupUI(zoneName)
	if not self.QueueReplica then 
		print("[TeleporterController] UpdatePopupUI: No replica yet")
		return 
	end
	if not zoneName or zoneName == "" then return end
	
	local queueData = self.QueueReplica.Data.Queues[zoneName]
	if not queueData then 
		print("[TeleporterController] UpdatePopupUI: No queue data for", zoneName)
		-- Show default values
		self.QueueLabel.Text = "Players: 0/8"
		self.CountdownLabel.Text = "Loading..."
		self.CountdownLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		return 
	end
	
	local playerCount = queueData.PlayerCount or 0
	local maxPlayers = queueData.MaxPlayers or 8
	local isCountingDown = queueData.IsCountingDown or false
	local countdown = queueData.Countdown or 0
	local playerNames = queueData.Players or {}
	local isSinglePlayer = queueData.IsSinglePlayer or (maxPlayers == 1)
	
	print("[TeleporterController] UpdatePopupUI:", zoneName, "Players:", playerCount, "/", maxPlayers)
	
	-- Show different label for single-player mode
	if isSinglePlayer then
		self.QueueLabel.Text = "Solo Teleporter"
	else
		self.QueueLabel.Text = string.format("Players: %d/%d", playerCount, maxPlayers)
	end
	
	if isCountingDown then
		self.CountdownLabel.Text = string.format("Teleporting in %d...", countdown)
		self.CountdownLabel.TextColor3 = countdown <= 5 
			and Color3.fromRGB(255, 100, 100) 
			or Color3.fromRGB(255, 200, 100)
	else
		if isSinglePlayer then
			self.CountdownLabel.Text = playerCount > 0 and "Preparing teleport..." or "Step in to teleport!"
		else
			self.CountdownLabel.Text = playerCount > 0 and "Waiting for more players..." or "Be the first to join!"
		end
		self.CountdownLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	end
	
	self:UpdatePlayerList(playerNames)
	
	local isInQueue = table.find(playerNames, LocalPlayer.Name) ~= nil
	if isSinglePlayer then
		self.StatusLabel.Text = isInQueue and "Ready to teleport!" or "Step on pad to teleport"
	else
		self.StatusLabel.Text = isInQueue and "You are in the queue!" or "Step on pad to join queue"
	end
	self.StatusLabel.TextColor3 = isInQueue and Color3.fromRGB(100, 200, 100) or Color3.fromRGB(120, 120, 120)
end

function TeleporterController:ShowPopup(zoneName, teleporterName, zoneColor)
	if not self.ZoneFrame then return end
	
	local color = zoneColor or Color3.fromRGB(255, 255, 255)
	
	self.TitleLabel.Text = (teleporterName or zoneName):gsub("Teleporter", "Zone "):upper()
	self.TitleLabel.TextColor3 = color
	self.ZoneStroke.Color = color
	
	self.ZoneFrame.Visible = true
	self.ZoneFrame.Position = UDim2.new(0.325, 0, 0.85, 0)
	self.ZoneFrame.BackgroundTransparency = 1
	
	TweenService:Create(self.ZoneFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.325, 0, 0.7, 0),
		BackgroundTransparency = 0.1,
	}):Play()
	
	self.CurrentZone = zoneName
	
	-- Update UI immediately
	self:UpdatePopupUI(zoneName)
	
	-- Also update after a short delay (in case queue data arrives after PlayerZones)
	task.delay(0.1, function()
		if self.CurrentZone == zoneName then
			self:UpdatePopupUI(zoneName)
		end
	end)
end

function TeleporterController:HidePopup()
	if not self.ZoneFrame then return end
	
	self.CurrentZone = nil
	
	local tween = TweenService:Create(self.ZoneFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.325, 0, 0.85, 0),
		BackgroundTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		if self.CurrentZone == nil then
			self.ZoneFrame.Visible = false
		end
	end)
end

--=============================================
-- REPLICA LISTENERS
--=============================================

function TeleporterController:SetupReplicaListeners(replica)
	self.QueueReplica = replica
	local userId = tostring(LocalPlayer.UserId)
	
	-- Listen for player entering/exiting zones (for popup)
	replica:ListenToChange({ "PlayerZones", userId }, function(newData)
		if newData and newData.ZoneName and newData.ZoneName ~= "" then
			local zoneColor = newData.ZoneColor and 
				Color3.fromRGB(newData.ZoneColor.R, newData.ZoneColor.G, newData.ZoneColor.B) or nil
			self:ShowPopup(newData.ZoneName, newData.TeleporterName, zoneColor)
		else
			self:HidePopup()
		end
	end)
	
	-- Listen to queue changes (for popup UI only - billboards use QueueCountReplica)
	replica:ListenToRaw(function(actionName, pathArray)
		if pathArray[1] == "Queues" and pathArray[2] then
			local zoneName = pathArray[2]
			
			-- Update popup if viewing this zone
			if self.CurrentZone == zoneName then
				print("[TeleporterController] Popup update for", zoneName)
				self:UpdatePopupUI(zoneName)
			end
		end
	end)
	
	-- Check if player is already in a zone
	local initialData = replica.Data.PlayerZones[userId]
	if initialData and initialData.ZoneName and initialData.ZoneName ~= "" then
		local zoneColor = initialData.ZoneColor and 
			Color3.fromRGB(initialData.ZoneColor.R, initialData.ZoneColor.G, initialData.ZoneColor.B) or nil
		self:ShowPopup(initialData.ZoneName, initialData.TeleporterName, zoneColor)
	end
end

--=============================================
-- KNIT LIFECYCLE
--=============================================

function TeleporterController:KnitInit()
	print("[TeleporterController] Initializing...")
	self:CreatePopupUI()
	ReplicaController.RequestData()
end

function TeleporterController:KnitStart()
	print("[TeleporterController] Starting...")

	-- Replica listeners
	ReplicaController.ReplicaOfClassCreated("TeleporterQueueReplica", function(replica)
		print("[TeleporterController] TeleporterQueueReplica received!")
		self:SetupReplicaListeners(replica)
	end)

	ReplicaController.ReplicaOfClassCreated("QueueCountReplica", function(replica)
		print("[TeleporterController] QueueCountReplica received!")
		self:SetupQueueCountReplicaListeners(replica)
	end)

	-- Start billboard discovery
	task.spawn(function()
		self:FindBillboards()
	end)
end


return TeleporterController
