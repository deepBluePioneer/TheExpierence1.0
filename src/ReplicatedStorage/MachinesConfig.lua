local MachinesConfig = {
	machines = {
		starter = {
			displayName = "Starter",
			unlock = { type = "default" },
			bodySize = Vector3.new(6, 2, 10),
			bodyColor = Color3.fromRGB(80, 140, 220),
			baseStats = {
				topSpeed = 85,
				acceleration = 6,
				handling = 6,
				weight = 5,
				boostPower = 30,
				boostChargeRate = 1.0,
				maxHealth = 80,
				offroadPenalty = 0.3,
			},
		},

		falcon = {
			displayName = "Falcon",
			unlock = { type = "level", requiredLevel = 5 },
			bodySize = Vector3.new(5, 1.5, 11),
			bodyColor = Color3.fromRGB(220, 60, 60),
			baseStats = {
				topSpeed = 120,
				acceleration = 8,
				handling = 5,
				weight = 3,
				boostPower = 40,
				boostChargeRate = 1.5,
				maxHealth = 60,
				offroadPenalty = 0.4,
			},
		},

		titan = {
			displayName = "Titan",
			unlock = { type = "level", requiredLevel = 10 },
			bodySize = Vector3.new(7, 2.5, 10),
			bodyColor = Color3.fromRGB(100, 100, 110),
			baseStats = {
				topSpeed = 70,
				acceleration = 4,
				handling = 3,
				weight = 10,
				boostPower = 25,
				boostChargeRate = 0.8,
				maxHealth = 120,
				offroadPenalty = 0.1,
			},
		},

		nimble = {
			displayName = "Nimble",
			unlock = { type = "shop", price = 800 },
			bodySize = Vector3.new(5, 1.5, 8),
			bodyColor = Color3.fromRGB(60, 200, 120),
			baseStats = {
				topSpeed = 90,
				acceleration = 6,
				handling = 9,
				weight = 5,
				boostPower = 30,
				boostChargeRate = 1.2,
				maxHealth = 80,
				offroadPenalty = 0.3,
			},
		},
	},

	defaultMachineId = "starter",
}

return MachinesConfig
