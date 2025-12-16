--[[
	SkillTreeService
	
	Server-side service for managing player skill unlocks.
	Handles persistence via ProfileService and syncs to clients via Replica.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Replica for real-time sync
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaService = require(Replica.ReplicaService)

local SkillTreeService = Knit.CreateService {
	Name = "SkillTreeService",
	Client = {
		SkillUnlocked = Knit.CreateSignal(),  -- Fires when a skill is unlocked
	},
	
	-- Player data
	_playerReplicas = {},  -- userId -> replica
	_playerSkills = {},    -- userId -> { skillId = true }
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SKILL DEFINITIONS                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Skill categories and their trees (same structure as client for validation)
local SKILL_TREES = {
	traversal = {
		"sprint_start", "momentum_keeper", "straight_line", "edge_confidence",
		"flow_state", "perfect_line", "endurance_runner", "express_hauler"
	},
	carry = {
		"extra_slot_1", "extra_slot_2", "vertical_logistics", "stable_carry",
		"quick_grab", "instant_stack", "bulk_training", "overload_mode"
	},
	profit = {
		"flat_rate", "clean_run", "long_haul", "stack_multiplier",
		"combo_chain", "priority_cargo", "golden_route", "compound_returns"
	},
	time = {
		"instant_deposit", "quick_turnaround", "auto_pickup", "cooldown_reduction",
		"run_recall", "phantom_carry", "time_compression", "zero_downtime"
	},
	route = {
		"line_bonus", "checkpoint_memory", "perfect_delivery", "risk_route",
		"split_path", "speedrun_bonus", "master_route", "flawless_run"
	},
	social = {
		"nearby_boost", "shared_deposit", "assist_credit", "convoy_mode",
		"leader_aura", "relay_carry", "union_contract", "bridge_authority"
	},
	specialization = {
		"the_sprinter", "the_hauler", "the_tycoon", "the_operator"
	},
}

-- Skill costs
local SKILL_COSTS = {
	-- Traversal
	sprint_start = 50, momentum_keeper = 100, straight_line = 150, edge_confidence = 200,
	flow_state = 300, perfect_line = 400, endurance_runner = 500, express_hauler = 750,
	
	-- Carry
	extra_slot_1 = 75, extra_slot_2 = 150, vertical_logistics = 200, stable_carry = 300,
	quick_grab = 400, instant_stack = 500, bulk_training = 600, overload_mode = 800,
	
	-- Profit
	flat_rate = 100, clean_run = 175, long_haul = 250, stack_multiplier = 350,
	combo_chain = 450, priority_cargo = 550, golden_route = 700, compound_returns = 1000,
	
	-- Time
	instant_deposit = 100, quick_turnaround = 175, auto_pickup = 275, cooldown_reduction = 400,
	run_recall = 550, phantom_carry = 650, time_compression = 800, zero_downtime = 1200,
	
	-- Route
	line_bonus = 125, checkpoint_memory = 200, perfect_delivery = 300, risk_route = 425,
	split_path = 500, speedrun_bonus = 625, master_route = 850, flawless_run = 1100,
	
	-- Social
	nearby_boost = 100, shared_deposit = 200, assist_credit = 325, convoy_mode = 450,
	leader_aura = 575, relay_carry = 700, union_contract = 900, bridge_authority = 1500,
	
	-- Specializations
	the_sprinter = 2000, the_hauler = 2000, the_tycoon = 2000, the_operator = 2000,
}

-- Specialization IDs (can only pick one)
local SPECIALIZATIONS = {
	"the_sprinter", "the_hauler", "the_tycoon", "the_operator"
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SKILL VALIDATION                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeService:GetSkillCategory(skillId)
	for category, skills in pairs(SKILL_TREES) do
		for _, id in ipairs(skills) do
			if id == skillId then
				return category
			end
		end
	end
	return nil
end

function SkillTreeService:GetSkillIndex(skillId)
	for category, skills in pairs(SKILL_TREES) do
		for index, id in ipairs(skills) do
			if id == skillId then
				return category, index
			end
		end
	end
	return nil, nil
end

function SkillTreeService:IsSpecialization(skillId)
	for _, spec in ipairs(SPECIALIZATIONS) do
		if spec == skillId then
			return true
		end
	end
	return false
end

function SkillTreeService:HasSpecialization(player)
	local skills = self._playerSkills[player.UserId]
	if not skills then return false end
	
	for _, spec in ipairs(SPECIALIZATIONS) do
		if skills[spec] then
			return true
		end
	end
	return false
end

function SkillTreeService:CanUnlockSkill(player, skillId)
	local userId = player.UserId
	local skills = self._playerSkills[userId] or {}
	
	-- Already unlocked?
	if skills[skillId] then
		return false, "Already unlocked"
	end
	
	-- Valid skill?
	local category, index = self:GetSkillIndex(skillId)
	if not category then
		return false, "Invalid skill"
	end
	
	-- Specialization check
	if self:IsSpecialization(skillId) then
		if self:HasSpecialization(player) then
			return false, "Already have a specialization"
		end
	end
	
	-- First skill in category always available
	if index == 1 then
		return true, nil
	end
	
	-- Check if previous skill is unlocked
	local prevSkillId = SKILL_TREES[category][index - 1]
	if not skills[prevSkillId] then
		return false, "Unlock previous skill first"
	end
	
	return true, nil
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SKILL MANAGEMENT                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeService:UnlockSkillInternal(player, skillId)
	local userId = player.UserId
	
	-- Validate
	local canUnlock, reason = self:CanUnlockSkill(player, skillId)
	if not canUnlock then
		return false, reason
	end
	
	-- Check cost
	local cost = SKILL_COSTS[skillId]
	if not cost then
		return false, "Invalid skill cost"
	end
	
	-- Get services
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local HubService = Knit.GetService("HubService")
	
	if not PlayerDataService then
		return false, "PlayerDataService not available"
	end
	
	-- Check if player has enough kudos
	local playerKudos = PlayerDataService:GetKudos(player)
	if playerKudos < cost then
		return false, "Not enough Kudos"
	end
	
	-- Deduct kudos
	local success, _ = PlayerDataService:SpendKudos(player, cost)
	if not success then
		return false, "Failed to spend Kudos"
	end
	
	-- Grant skill in PlayerDataService (persistent)
	local unlockSuccess, unlockErr = PlayerDataService:UnlockSkill(player, skillId)
	if not unlockSuccess then
		-- Refund kudos on failure
		PlayerDataService:AddKudos(player, cost)
		return false, unlockErr or "Failed to unlock skill"
	end
	
	-- Update local cache
	if not self._playerSkills[userId] then
		self._playerSkills[userId] = {}
	end
	self._playerSkills[userId][skillId] = true
	
	-- Update replica for client sync
	self:UpdatePlayerReplica(player)
	
	-- Update kudos replica if HubService has one
	if HubService and HubService._kudosReplicas and HubService._kudosReplicas[player] then
		local kudosReplica = HubService._kudosReplicas[player]
		kudosReplica:SetValue({"Kudos"}, PlayerDataService:GetKudos(player))
	end
	
	-- Fire signal
	self.Client.SkillUnlocked:Fire(player, skillId)
	
	print(string.format("[SkillTreeService] %s unlocked skill: %s (cost: %d)", player.Name, skillId, cost))
	
	return true, nil
end

function SkillTreeService:GetPlayerSkills(player)
	return self._playerSkills[player.UserId] or {}
end

function SkillTreeService:GetPlayerSkillsList(player)
	local skills = self._playerSkills[player.UserId] or {}
	local list = {}
	for skillId, _ in pairs(skills) do
		table.insert(list, skillId)
	end
	return list
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         REPLICA MANAGEMENT                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeService:CreatePlayerReplica(player)
	local userId = player.UserId
	
	-- Create skills replica for this player
	local skillsList = self:GetPlayerSkillsList(player)
	
	local replica = ReplicaService.NewReplica({
		ClassToken = ReplicaService.NewClassToken("PlayerSkills_" .. userId),
		Data = {
			UnlockedSkills = skillsList,
		},
		Replication = player,  -- Only replicate to this player
	})
	
	self._playerReplicas[userId] = replica
	
	print(string.format("[SkillTreeService] Created skills replica for %s with %d skills", player.Name, #skillsList))
	
	return replica
end

function SkillTreeService:UpdatePlayerReplica(player)
	local userId = player.UserId
	local replica = self._playerReplicas[userId]
	
	if replica then
		local skillsList = self:GetPlayerSkillsList(player)
		replica:SetValue({"UnlockedSkills"}, skillsList)
	end
end

function SkillTreeService:DestroyPlayerReplica(player)
	local userId = player.UserId
	local replica = self._playerReplicas[userId]
	
	if replica then
		replica:Destroy()
		self._playerReplicas[userId] = nil
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PERSISTENCE                                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeService:LoadPlayerSkills(player)
	local userId = player.UserId
	
	-- Get from PlayerDataService
	local PlayerDataService = Knit.GetService("PlayerDataService")
	if PlayerDataService then
		-- Wait for profile to be ready
		local profile = PlayerDataService:WaitForProfile(player, 15)
		if profile then
			local unlockedSkills = PlayerDataService:GetUnlockedSkills(player)
			local skills = {}
			for _, skillId in ipairs(unlockedSkills) do
				skills[skillId] = true
			end
			self._playerSkills[userId] = skills
			print(string.format("[SkillTreeService] Loaded %d skills for %s from PlayerDataService", #unlockedSkills, player.Name))
			return
		end
	end
	
	-- Default to empty
	self._playerSkills[userId] = {}
	print(string.format("[SkillTreeService] Initialized empty skills for %s", player.Name))
end

function SkillTreeService:SavePlayerSkills(player)
	-- Skills are automatically saved via PlayerDataService when UnlockSkill is called
	-- This method exists for manual saves if needed
	local PlayerDataService = Knit.GetService("PlayerDataService")
	if PlayerDataService then
		local skillsList = self:GetPlayerSkillsList(player)
		PlayerDataService:SetUnlockedSkills(player, skillsList)
		print(string.format("[SkillTreeService] Saved %d skills for %s to PlayerDataService", #skillsList, player.Name))
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeService.Client:UnlockSkill(player, skillId)
	return SkillTreeService:UnlockSkillInternal(player, skillId)
end

function SkillTreeService.Client:GetUnlockedSkills(player)
	return SkillTreeService:GetPlayerSkillsList(player)
end

function SkillTreeService.Client:CanUnlockSkill(player, skillId)
	return SkillTreeService:CanUnlockSkill(player, skillId)
end

function SkillTreeService.Client:GetSkillCost(player, skillId)
	return SKILL_COSTS[skillId] or 0
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SKILL EFFECTS                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Check if player has a specific skill
function SkillTreeService:HasSkill(player, skillId)
	local skills = self._playerSkills[player.UserId]
	return skills and skills[skillId] == true
end

-- Get all skill bonuses for a player (for other services to query)
function SkillTreeService:GetSkillBonuses(player)
	local skills = self._playerSkills[player.UserId] or {}
	local bonuses = {
		-- Speed bonuses
		sprintStartBonus = skills["sprint_start"] and 0.25 or 0,
		momentumKeeper = skills["momentum_keeper"] and 0.40 or 0,
		straightLineBonus = skills["straight_line"] and 0.15 or 0,
		edgeConfidence = skills["edge_confidence"] or false,
		flowStateActive = skills["flow_state"] or false,
		perfectLineBonus = skills["perfect_line"] and 0.20 or 0,
		enduranceRunner = skills["endurance_runner"] and 0.50 or 0,
		expressHauler = skills["express_hauler"] and 0.10 or 0,
		
		-- Carry bonuses
		extraSlots = (skills["extra_slot_1"] and 1 or 0) + (skills["extra_slot_2"] and 2 or 0),
		verticalLogistics = skills["vertical_logistics"] and 0.30 or 0,
		stableCarry = skills["stable_carry"] or false,
		quickGrab = skills["quick_grab"] and 0.50 or 0,
		instantStack = skills["instant_stack"] or false,
		bulkTraining = skills["bulk_training"] or false,
		overloadMode = skills["overload_mode"] or false,
		
		-- Profit bonuses
		flatRateBonus = skills["flat_rate"] and 0.10 or 0,
		cleanRunBonus = skills["clean_run"] and 0.15 or 0,
		longHaulBonus = skills["long_haul"] and 0.20 or 0,
		stackMultiplier = skills["stack_multiplier"] and 0.05 or 0,
		comboChainBonus = skills["combo_chain"] and 0.03 or 0,
		priorityCargo = skills["priority_cargo"] or false,
		goldenRoute = skills["golden_route"] or false,
		compoundReturns = skills["compound_returns"] or false,
		
		-- Time bonuses
		instantDeposit = skills["instant_deposit"] or false,
		quickTurnaround = skills["quick_turnaround"] and 0.40 or 0,
		autoPickup = skills["auto_pickup"] or false,
		cooldownReduction = skills["cooldown_reduction"] and 0.20 or 0,
		runRecall = skills["run_recall"] or false,
		phantomCarry = skills["phantom_carry"] or false,
		timeCompression = skills["time_compression"] or false,
		zeroDowntime = skills["zero_downtime"] or false,
		
		-- Route bonuses
		lineBonus = skills["line_bonus"] and 0.10 or 0,
		checkpointMemory = skills["checkpoint_memory"] and 0.05 or 0,
		perfectDeliveryBonus = skills["perfect_delivery"] and 0.25 or 0,
		riskRoute = skills["risk_route"] and 0.40 or 0,
		splitPathAwareness = skills["split_path"] or false,
		speedrunBonus = skills["speedrun_bonus"] and 0.30 or 0,
		masterRoute = skills["master_route"] and 0.10 or 0,
		flawlessRunMultiplier = skills["flawless_run"] and 1.5 or 1,
		
		-- Social bonuses
		nearbyBoost = skills["nearby_boost"] and 0.10 or 0,
		sharedDeposit = skills["shared_deposit"] and 0.15 or 0,
		assistCredit = skills["assist_credit"] and 0.20 or 0,
		convoyMode = skills["convoy_mode"] and 0.25 or 0,
		leaderAura = skills["leader_aura"] and 0.10 or 0,
		relayCarry = skills["relay_carry"] or false,
		unionContract = skills["union_contract"] or false,
		bridgeAuthority = skills["bridge_authority"] or false,
		
		-- Specializations
		theSprinter = skills["the_sprinter"] or false,
		theHauler = skills["the_hauler"] or false,
		theTycoon = skills["the_tycoon"] or false,
		theOperator = skills["the_operator"] or false,
	}
	
	return bonuses
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PLAYER EVENTS                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeService:OnPlayerAdded(player)
	-- Load skills from profile
	self:LoadPlayerSkills(player)
	
	-- Create replica (with small delay to ensure other services are ready)
	task.delay(1, function()
		if player.Parent then
			self:CreatePlayerReplica(player)
		end
	end)
end

function SkillTreeService:OnPlayerRemoving(player)
	-- Save skills
	self:SavePlayerSkills(player)
	
	-- Cleanup
	self:DestroyPlayerReplica(player)
	self._playerSkills[player.UserId] = nil
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         LIFECYCLE                                           ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeService:KnitInit()
	print("[SkillTreeService] Initializing...")
end

function SkillTreeService:KnitStart()
	print("[SkillTreeService] Starting...")
	
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:OnPlayerAdded(player)
		end)
	end
	
	-- Handle new players
	Players.PlayerAdded:Connect(function(player)
		self:OnPlayerAdded(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:OnPlayerRemoving(player)
	end)
	
	print("[SkillTreeService] Started! Managing " .. #SPECIALIZATIONS .. " specializations across " .. 
		(function()
			local count = 0
			for _ in pairs(SKILL_TREES) do count = count + 1 end
			return count
		end)() .. " categories")
end

return SkillTreeService

