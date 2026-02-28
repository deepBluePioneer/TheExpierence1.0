local ProfileConfig = {}

ProfileConfig.CURRENT_VERSION = 1

ProfileConfig.DEFAULT_PROFILE = {
	schemaVersion = ProfileConfig.CURRENT_VERSION,

	-- Currency and progression
	currency = 0,
	xp = 0,
	level = 1,

	-- Machines
	ownedMachines = { "starter" },
	selectedMachineId = "starter",

	-- Cosmetics
	ownedTrails = {},
	equippedTrailId = nil,

	ownedSkins = {},
	equippedSkins = {},

	ownedTitles = {},
	equippedTitleId = nil,

	ownedBoostEffects = {},
	equippedBoostEffectId = nil,

	-- Stats and records
	totalMatchesPlayed = 0,
	totalPatchesCollected = 0,
	bestSingleMatchPatches = 0,
	bestSurvivalTime = 0,

	-- Settings
	hudDensity = "Full",
	sfxVolume = 1.0,
	musicVolume = 0.5,
}

function ProfileConfig.xpForLevel(n)
	return math.floor(100 * n ^ 1.5)
end

ProfileConfig.Migrations = {
	-- [1] = function(profile)
	--     profile.someNewField = profile.someNewField or "default"
	--     profile.schemaVersion = 2
	-- end,
}

return ProfileConfig
