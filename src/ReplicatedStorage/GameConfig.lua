local GameConfig = {
	-- CityTrial match timing
	matchDurationSeconds = 60,
	resultsDurationSeconds = 15,
	startCountdownSeconds = 10,
	respawnSeconds = 4,
	invulnerabilitySeconds = 3,

	-- Player counts
	minPlayers = 2,
	maxPlayers = 8,

	-- Grace timers for CityTrial join/ready handshake
	joinGraceSeconds = 30,
	readyGraceSeconds = 15,

	-- Physics mode: "ClientPredicted" or "ServerAuthoritative"
	physicsMode = "ClientPredicted",

	-- HUD density default: "Minimal", "Moderate", or "Full"
	defaultHudDensity = "Full",

	-- Reward formulas (all tunable without code changes)
	rewards = {
		baseCurrency = 50,
		baseXP = 100,

		patchCurrencyMultiplier = 2,
		patchXPMultiplier = 5,

		survivalCurrencyMax = 30,
		survivalXPMax = 80,

		eventCurrency = 10,
		eventXP = 25,

		deathPenaltyPercent = 0.15,
	},
}

return GameConfig
