return {
	name = "Volcanic",
	description = "Rivers of molten rock carve through jagged basalt peaks. Extreme elevation and thick smoke test your reflexes.",
	accentColor = Color3.fromRGB(255, 130, 50),
	planetColor = Color3.fromRGB(220, 70, 20),
	tagline = "Rivers of molten rock",
	material = Enum.Material.Basalt,
	amp = 18,
	noiseScale = 0.0095,
	seed = 404,
	terrain = {
		octaves = 6, lacunarity = 2, gain = 0.48, ridgeWeight = 0.45, warpAmp = 20,
		verticalStuds = 140, caveEnabled = true, caveThreshold = 0.36, caveScale = 0.04,
		caveSkinVoxels = 2, heightScale = 1.05,
	},
	atmosphere = {
		fogColor = Color3.fromRGB(80, 35, 15), decay = Color3.fromRGB(130, 55, 20),
		density = 0.25, haze = 4, glare = 0.2,
	},
	bloom = { intensity = 0.06, size = 18, threshold = 0.8 },
	cc = { tint = Color3.fromRGB(255, 195, 160), brightness = 0.02, contrast = 0.12, saturation = 0.1 },
	lighting = {
		clockTime = 17.5, brightness = 1.5, ambient = Color3.fromRGB(100, 55, 30),
		outdoorAmbient = Color3.fromRGB(90, 45, 25), fogColor = Color3.fromRGB(80, 35, 15),
		fogStart = 60, fogEnd = 500, envDiffuse = 0.3, envSpecular = 0.3, globalShadows = true,
	},
	orbit = { radius = 0.30, angle = math.rad(306) },
	elements = {
		{
			type = "simple", name = "LavaPool", density = 0.02, cell = 10,
			sizeMin = Vector3.new(3, 0.6, 3), sizeMax = Vector3.new(8, 1.2, 8),
			material = Enum.Material.Neon, color = Color3.fromRGB(255, 80, 20),
		},
		{
			type = "lsystem", density = 0.015, cell = 12, minScale = 2.0, maxScale = 3.5,
			rule = {
				name = "ObsidianSpire", axiom = "F",
				rules = { F = "F[+F]F[-F]FF" },
				iterations = 4, angle = 30,
				segmentLength = 5, segmentThickness = 2.0,
				lengthDecay = 0.68, thicknessDecay = 0.62,
				material = Enum.Material.Glass, color = Color3.fromRGB(40, 20, 55),
				leafEnabled = false,
			},
		},
		{
			type = "simple", name = "BasaltPillar", density = 0.018, cell = 10,
			sizeMin = Vector3.new(2, 8, 2), sizeMax = Vector3.new(5, 22, 5),
			material = Enum.Material.Slate, color = Color3.fromRGB(30, 25, 35),
		},
		{
			type = "simple", name = "MagmaRock", density = 0.015, cell = 10,
			shape = "Ball",
			sizeMin = Vector3.new(4, 3, 4), sizeMax = Vector3.new(10, 7, 10),
			material = Enum.Material.Basalt, color = Color3.fromRGB(50, 35, 30),
		},
	},
}
