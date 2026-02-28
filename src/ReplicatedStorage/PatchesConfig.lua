local PatchesConfig = {
	targetPatchCount = 40,

	patches = {
		speed = {
			displayName = "Speed",
			color = Color3.fromRGB(255, 200, 50),
			statKey = "topSpeed",
			delta = 5,
			softCap = 50,
			spawnWeight = 10,
			respawnDelay = 5,
		},

		acceleration = {
			displayName = "Acceleration",
			color = Color3.fromRGB(255, 130, 50),
			statKey = "acceleration",
			delta = 1,
			softCap = 8,
			spawnWeight = 8,
			respawnDelay = 5,
		},

		handling = {
			displayName = "Handling",
			color = Color3.fromRGB(50, 200, 255),
			statKey = "handling",
			delta = 1,
			softCap = 8,
			spawnWeight = 8,
			respawnDelay = 5,
		},

		boost = {
			displayName = "Boost",
			color = Color3.fromRGB(255, 80, 80),
			statKey = "boostPower",
			delta = 5,
			softCap = 40,
			spawnWeight = 5,
			respawnDelay = 7,
		},

		charge = {
			displayName = "Charge",
			color = Color3.fromRGB(200, 80, 255),
			statKey = "boostChargeRate",
			delta = 0.2,
			softCap = 2.0,
			spawnWeight = 5,
			respawnDelay = 7,
		},

		defense = {
			displayName = "Defense",
			color = Color3.fromRGB(100, 255, 100),
			statKeys = { "weight", "maxHealth" },
			deltas = { 1, 10 },
			softCaps = { 8, 80 },
			spawnWeight = 4,
			respawnDelay = 8,
		},

		glide = {
			displayName = "Glide",
			color = Color3.fromRGB(180, 220, 255),
			statKey = "offroadPenalty",
			delta = -0.05,
			softCap = -0.3,
			floor = 0.0,
			spawnWeight = 3,
			respawnDelay = 8,
		},
	},

	spawn = {
		altitudeOffset = 100,
		landingTimeout = 9,
		initialBatchStaggerSeconds = 2.5,
		maxRetries = 5,
	},
}

return PatchesConfig
