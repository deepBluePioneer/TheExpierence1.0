local ShopConfig = {
	items = {
		-- Trails
		{ id = "trail_fire", category = "trail", displayName = "Fire Trail", price = 500, levelRequired = 5, icon = "rbxassetid://0" },
		{ id = "trail_electric", category = "trail", displayName = "Electric Trail", price = 700, levelRequired = 8, icon = "rbxassetid://0" },
		{ id = "trail_ice", category = "trail", displayName = "Ice Trail", price = 600, levelRequired = 6, icon = "rbxassetid://0" },

		-- Machine skins
		{ id = "skin_starter_chrome", category = "skin", machineId = "starter", displayName = "Chrome Starter", price = 400, levelRequired = 3, icon = "rbxassetid://0" },
		{ id = "skin_falcon_gold", category = "skin", machineId = "falcon", displayName = "Gold Falcon", price = 1000, levelRequired = 10, icon = "rbxassetid://0" },
		{ id = "skin_titan_obsidian", category = "skin", machineId = "titan", displayName = "Obsidian Titan", price = 1200, levelRequired = 12, icon = "rbxassetid://0" },
		{ id = "skin_nimble_neon", category = "skin", machineId = "nimble", displayName = "Neon Nimble", price = 900, levelRequired = 8, icon = "rbxassetid://0" },

		-- Titles
		{ id = "title_speedDemon", category = "title", displayName = "Speed Demon", price = 300, levelRequired = 0, icon = "rbxassetid://0" },
		{ id = "title_patchCollector", category = "title", displayName = "Patch Collector", price = 300, levelRequired = 5, icon = "rbxassetid://0" },
		{ id = "title_survivor", category = "title", displayName = "Survivor", price = 500, levelRequired = 10, icon = "rbxassetid://0" },

		-- Boost effects
		{ id = "boost_flame", category = "boostEffect", displayName = "Flame Boost", price = 600, levelRequired = 7, icon = "rbxassetid://0" },
		{ id = "boost_sparkle", category = "boostEffect", displayName = "Sparkle Boost", price = 600, levelRequired = 7, icon = "rbxassetid://0" },
	},

	categories = { "trail", "skin", "title", "boostEffect" },

	categoryDisplayNames = {
		trail = "Trails",
		skin = "Machine Skins",
		title = "Titles",
		boostEffect = "Boost Effects",
	},
}

return ShopConfig
