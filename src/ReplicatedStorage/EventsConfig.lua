local EventsConfig = {
	maxConcurrentEvents = 2,
	minCooldownSeconds = 15,
	scheduleIntervalMin = 20,
	scheduleIntervalMax = 45,

	events = {
		meteor_shower = {
			displayName = "Meteor Shower",
			duration = 12,
			warningSeconds = 2.0,
			damage = 30,
			meteorCount = { min = 5, max = 10 },
			weight = 10,
		},

		rain = {
			displayName = "Heavy Rain",
			duration = 25,
			warningSeconds = 3.0,
			visibilityMultiplier = 0.5,
			weight = 8,
		},

		fog = {
			displayName = "Thick Fog",
			duration = 20,
			warningSeconds = 2.0,
			visibilityMultiplier = 0.3,
			weight = 6,
		},

		shockwave = {
			displayName = "Shockwave",
			duration = 3,
			warningSeconds = 1.5,
			damage = 20,
			knockbackForce = 50,
			radius = 60,
			weight = 5,
		},

		area_hazard = {
			displayName = "Danger Zone",
			duration = 15,
			warningSeconds = 2.0,
			tickDamage = 5,
			tickInterval = 1,
			radius = 40,
			weight = 7,
		},

		patch_rain = {
			displayName = "Patch Rain",
			duration = 10,
			warningSeconds = 1.0,
			bonusPatches = 18,
			weight = 6,
		},

		wind = {
			displayName = "Strong Wind",
			duration = 20,
			warningSeconds = 2.0,
			windForce = 15,
			weight = 4,
		},
	},
}

return EventsConfig
