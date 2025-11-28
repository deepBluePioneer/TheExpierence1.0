local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage.CustomPackages
local Knit = require(Packages.Knit)

-- Zone+ module
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

-- Replica module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaService = require(Replica.ReplicaService)

local TeleporterService = Knit.CreateService {
	Name = "TeleporterService",
	Client = {},
}

-- Store active zones
TeleporterService.Zones = {}
TeleporterService.PlayerReplicas = {} -- Store replica per player

function TeleporterService:CreatePlayerReplica(player)
	local replica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken("TeleporterReplica_" .. player.UserId),
		Tags = { Player = player },
		Data = {
			CurrentZone = "", -- Empty string means not in any zone
			TeleporterName = "",
			ZoneColor = { R = 255, G = 255, B = 255 },
		},
		Replication = player, -- Only replicate to this specific player
	})
	
	self.PlayerReplicas[player] = replica
	print("TeleporterService: Created replica for " .. player.Name)
	return replica
end

function TeleporterService:UpdatePlayerZone(player, zoneName, teleporterName, zoneColor)
	local replica = self.PlayerReplicas[player]
	if not replica then return end
	
	replica:SetValue({ "CurrentZone" }, zoneName or "")
	replica:SetValue({ "TeleporterName" }, teleporterName or "")
	
	if zoneColor then
		replica:SetValue({ "ZoneColor" }, {
			R = math.floor(zoneColor.R * 255),
			G = math.floor(zoneColor.G * 255),
			B = math.floor(zoneColor.B * 255),
		})
	end
end

function TeleporterService:SetupZone(zonePart)
	local zoneName = zonePart.Name
	local linkedTeleporter = zonePart:FindFirstChild("LinkedTeleporter")
	local teleporterRef = linkedTeleporter and linkedTeleporter.Value
	local teleporterName = teleporterRef and teleporterRef.Name or "Unknown"
	local zoneColor = teleporterRef and teleporterRef.Color or Color3.new(1, 1, 1)
	
	-- Create Zone+ zone from the zone part
	local zone = Zone.new(zonePart)
	zone:setAccuracy("High")
	
	self.Zones[zoneName] = {
		zone = zone,
		zonePart = zonePart,
		teleporterName = teleporterName,
		zoneColor = zoneColor,
	}
	
	-- Player entered zone
	zone.playerEntered:Connect(function(player)
		print(player.Name .. " entered " .. zoneName)
		self:UpdatePlayerZone(player, zoneName, teleporterName, zoneColor)
	end)
	
	-- Player exited zone
	zone.playerExited:Connect(function(player)
		print(player.Name .. " exited " .. zoneName)
		
		-- Only clear if still in this zone (prevent race conditions)
		local replica = self.PlayerReplicas[player]
		if replica and replica.Data.CurrentZone == zoneName then
			self:UpdatePlayerZone(player, "", "", nil)
		end
	end)
	
	print("TeleporterService: Setup zone for " .. zoneName .. " (linked to " .. teleporterName .. ")")
end

function TeleporterService:SetupAllZones()
	local zonesFolder = workspace:FindFirstChild("TeleporterZones")
	if not zonesFolder then
		warn("TeleporterService: TeleporterZones folder not found in workspace!")
		return
	end
	
	for _, zonePart in ipairs(zonesFolder:GetChildren()) do
		if zonePart:IsA("BasePart") and CollectionService:HasTag(zonePart, "TeleporterZone") then
			self:SetupZone(zonePart)
		end
	end
end

-- Clean up when player leaves
function TeleporterService:OnPlayerRemoving(player)
	local replica = self.PlayerReplicas[player]
	if replica then
		replica:Destroy()
		self.PlayerReplicas[player] = nil
	end
end

function TeleporterService:OnPlayerAdded(player)
	self:CreatePlayerReplica(player)
end

function TeleporterService:KnitInit()
	print("TeleporterService: Initializing...")
	
	-- Setup player connections
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)
	
	-- Handle players already in game
	for _, player in ipairs(Players:GetPlayers()) do
		self:OnPlayerAdded(player)
	end
end

function TeleporterService:KnitStart()
	print("TeleporterService: Starting...")
	self:SetupAllZones()
end

return TeleporterService
