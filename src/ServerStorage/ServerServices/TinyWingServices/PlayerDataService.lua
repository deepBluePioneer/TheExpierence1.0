--[[
	PlayerDataService
	
	Manages persistent player data using ProfileService.
	Saves: Kudos, Stack Capacity (upgrades), and other persistent stats.
	
	Based on ProfileService API: https://madstudioroblox.github.io/ProfileService/api/
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- ProfileService
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local ProfileService = require(CustomPackages.ProfileService.ProfileService)

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PROFILE TEMPLATE                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Default values for new players
local PROFILE_TEMPLATE = {
	-- Currency
	Kudos = 50,  -- Starting kudos
	
	-- Upgrades
	StackCapacity = 1,  -- Starting stack capacity (boxes player can carry)
	
	-- Skills (Skill Tree unlocks)
	UnlockedSkills = {},  -- Array of skill IDs that player has unlocked
	
	-- Stats
	TotalPackagesDelivered = 0,
	TotalKudosEarned = 0,
	PlayTime = 0,  -- In seconds
	
	-- Timestamps
	FirstJoinTime = 0,
	LastJoinTime = 0,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SERVICE DEFINITION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local PlayerDataService = Knit.CreateService {
	Name = "PlayerDataService",
	Client = {
		DataLoaded = Knit.CreateSignal(),  -- Fires when player data is ready
		DataChanged = Knit.CreateSignal(), -- Fires when specific data changes
	},
}

-- Profile Store
local GameProfileStore = ProfileService.GetProfileStore(
	"PlayerData_v1",  -- DataStore name (version suffix for easy migrations)
	PROFILE_TEMPLATE
)

-- Active profiles
local Profiles = {}  -- [Player] = Profile

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PROFILE MANAGEMENT                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PlayerDataService:GetProfile(player)
	return Profiles[player]
end

function PlayerDataService:GetData(player)
	local profile = Profiles[player]
	if profile then
		return profile.Data
	end
	return nil
end

-- Wait for a player's profile to load (useful for other services)
function PlayerDataService:WaitForProfile(player, timeout)
	timeout = timeout or 10
	local startTime = tick()
	
	while not Profiles[player] do
		if tick() - startTime > timeout then
			warn(string.format("[PlayerDataService] Timeout waiting for %s's profile", player.Name))
			return nil
		end
		task.wait(0.1)
	end
	
	return Profiles[player]
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KUDOS METHODS                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PlayerDataService:GetKudos(player)
	local profile = Profiles[player]
	if profile then
		return profile.Data.Kudos
	end
	return 0
end

function PlayerDataService:SetKudos(player, amount)
	local profile = Profiles[player]
	if profile then
		profile.Data.Kudos = math.max(0, amount)
		return true
	end
	return false
end

function PlayerDataService:AddKudos(player, amount)
	local profile = Profiles[player]
	if profile then
		profile.Data.Kudos = profile.Data.Kudos + amount
		profile.Data.TotalKudosEarned = profile.Data.TotalKudosEarned + amount
		return profile.Data.Kudos
	end
	return nil
end

function PlayerDataService:SpendKudos(player, amount)
	local profile = Profiles[player]
	if profile then
		if profile.Data.Kudos >= amount then
			profile.Data.Kudos = profile.Data.Kudos - amount
			return true, profile.Data.Kudos
		else
			return false, profile.Data.Kudos  -- Not enough kudos
		end
	end
	return false, 0
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STACK CAPACITY METHODS                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PlayerDataService:GetStackCapacity(player)
	local profile = Profiles[player]
	if profile then
		return profile.Data.StackCapacity
	end
	return 1  -- Default
end

function PlayerDataService:SetStackCapacity(player, capacity)
	local profile = Profiles[player]
	if profile then
		profile.Data.StackCapacity = math.max(1, capacity)
		return true
	end
	return false
end

function PlayerDataService:IncrementStackCapacity(player)
	local profile = Profiles[player]
	if profile then
		profile.Data.StackCapacity = profile.Data.StackCapacity + 1
		return profile.Data.StackCapacity
	end
	return nil
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SKILLS METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PlayerDataService:GetUnlockedSkills(player)
	local profile = Profiles[player]
	if profile then
		return profile.Data.UnlockedSkills or {}
	end
	return {}
end

function PlayerDataService:HasSkill(player, skillId)
	local profile = Profiles[player]
	if profile and profile.Data.UnlockedSkills then
		for _, id in ipairs(profile.Data.UnlockedSkills) do
			if id == skillId then
				return true
			end
		end
	end
	return false
end

function PlayerDataService:UnlockSkill(player, skillId)
	local profile = Profiles[player]
	if profile then
		-- Check if already unlocked
		if self:HasSkill(player, skillId) then
			return false, "Already unlocked"
		end
		
		-- Initialize skills array if needed
		if not profile.Data.UnlockedSkills then
			profile.Data.UnlockedSkills = {}
		end
		
		-- Add skill to unlocked list
		table.insert(profile.Data.UnlockedSkills, skillId)
		
		print(string.format("[PlayerDataService] %s unlocked skill: %s", player.Name, skillId))
		return true, nil
	end
	return false, "Profile not loaded"
end

function PlayerDataService:SetUnlockedSkills(player, skillsList)
	local profile = Profiles[player]
	if profile then
		profile.Data.UnlockedSkills = skillsList or {}
		return true
	end
	return false
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STATS METHODS                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PlayerDataService:IncrementPackagesDelivered(player, count)
	local profile = Profiles[player]
	if profile then
		count = count or 1
		profile.Data.TotalPackagesDelivered = profile.Data.TotalPackagesDelivered + count
		return profile.Data.TotalPackagesDelivered
	end
	return nil
end

function PlayerDataService:GetStats(player)
	local profile = Profiles[player]
	if profile then
		return {
			TotalPackagesDelivered = profile.Data.TotalPackagesDelivered,
			TotalKudosEarned = profile.Data.TotalKudosEarned,
			PlayTime = profile.Data.PlayTime,
			StackCapacity = profile.Data.StackCapacity,
		}
	end
	return nil
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PLAYER LIFECYCLE                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PlayerDataService:OnPlayerAdded(player)
	print(string.format("[PlayerDataService] Loading profile for %s...", player.Name))
	
	local profile = GameProfileStore:LoadProfileAsync("Player_" .. player.UserId)
	
	if profile ~= nil then
		-- GDPR compliance
		profile:AddUserId(player.UserId)
		
		-- Fill in any missing values from template (for existing players after updates)
		profile:Reconcile()
		
		-- Handle profile release (e.g., loaded on another server)
		profile:ListenToRelease(function()
			Profiles[player] = nil
			-- Force disconnect if profile was stolen
			player:Kick("Your data was loaded on another server. Please rejoin.")
		end)
		
		-- Check if player is still in game
		if player:IsDescendantOf(Players) then
			Profiles[player] = profile
			
			-- Update timestamps
			if profile.Data.FirstJoinTime == 0 then
				profile.Data.FirstJoinTime = os.time()
			end
			profile.Data.LastJoinTime = os.time()
			
			print(string.format("[PlayerDataService] Profile loaded for %s: %d kudos, %d stack capacity, %d skills", 
				player.Name, profile.Data.Kudos, profile.Data.StackCapacity, #(profile.Data.UnlockedSkills or {})))
			
			-- Notify client that data is ready
			self.Client.DataLoaded:Fire(player, {
				Kudos = profile.Data.Kudos,
				StackCapacity = profile.Data.StackCapacity,
				UnlockedSkills = profile.Data.UnlockedSkills or {},
			})
			
			-- Start play time tracking
			task.spawn(function()
				while Profiles[player] do
					task.wait(60)  -- Update every minute
					if Profiles[player] then
						profile.Data.PlayTime = profile.Data.PlayTime + 60
					end
				end
			end)
		else
			-- Player left before profile loaded
			profile:Release()
		end
	else
		-- Profile couldn't be loaded (session lock conflict)
		warn(string.format("[PlayerDataService] Failed to load profile for %s", player.Name))
		player:Kick("Failed to load your data. Please try again.")
	end
end

function PlayerDataService:OnPlayerRemoving(player)
	local profile = Profiles[player]
	if profile then
		print(string.format("[PlayerDataService] Releasing profile for %s (Kudos: %d, Stack: %d)", 
			player.Name, profile.Data.Kudos, profile.Data.StackCapacity))
		profile:Release()
		Profiles[player] = nil
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PlayerDataService.Client:GetMyData(player)
	local profile = Profiles[player]
	if profile then
		return {
			Kudos = profile.Data.Kudos,
			StackCapacity = profile.Data.StackCapacity,
			TotalPackagesDelivered = profile.Data.TotalPackagesDelivered,
			TotalKudosEarned = profile.Data.TotalKudosEarned,
			UnlockedSkills = profile.Data.UnlockedSkills or {},
		}
	end
	return nil
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PlayerDataService:KnitInit()
	print("[PlayerDataService] Initializing...")
end

function PlayerDataService:KnitStart()
	print("[PlayerDataService] Starting...")
	
	-- Handle players already in game
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:OnPlayerAdded(player)
		end)
	end
	
	-- Handle new players
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)
	
	-- Handle players leaving
	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)
	
	-- Handle server shutdown - release all profiles
	game:BindToClose(function()
		print("[PlayerDataService] Server shutting down, releasing all profiles...")
		for player, profile in pairs(Profiles) do
			profile:Release()
		end
	end)
	
	print("[PlayerDataService] Started!")
end

return PlayerDataService

