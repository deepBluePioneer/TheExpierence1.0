return {
	name = "Arctic",
	description = "A frozen glacial expanse wrapped in pale fog. Icy ridges and deep crevasses make navigation treacherous.",
	accentColor = Color3.fromRGB(200, 230, 255),
	planetColor = Color3.fromRGB(140, 200, 240),
	tagline = "Frozen glacial expanse",
	material = Enum.Material.Glacier,
	amp = 11,
	noiseScale = 0.0065,
	seed = 256,
	terrain = {
		octaves = 5, lacunarity = 2, gain = 0.5, ridgeWeight = 0.28, warpAmp = 16,
		verticalStuds = 130, caveEnabled = true, caveThreshold = 0.4, caveScale = 0.038,
		caveSkinVoxels = 2, heightScale = 1.1,
	},
	atmosphere = {
		fogColor = Color3.fromRGB(195, 210, 235), decay = Color3.fromRGB(175, 190, 220),
		density = 0.22, haze = 4, glare = 0.08,
	},
	bloom = { intensity = 0.04, size = 14, threshold = 1.0 },
	cc = { tint = Color3.fromRGB(215, 228, 250), brightness = 0.03, contrast = 0.05, saturation = -0.1 },
	lighting = {
		clockTime = 10, brightness = 1.8, ambient = Color3.fromRGB(100, 115, 140),
		outdoorAmbient = Color3.fromRGB(90, 105, 130), fogColor = Color3.fromRGB(195, 210, 235),
		fogStart = 80, fogEnd = 600, envDiffuse = 0.5, envSpecular = 0.6, globalShadows = true,
	},
	orbit = { radius = 0.24, angle = math.rad(234) },
	elements = {
		{
			type = "lsystem", density = 0.018, cell = 10, minScale = 2.0, maxScale = 3.5,
			rule = {
				name = "IceMonolith", axiom = "F",
				rules = { F = "F[+^F][-&F]FF" },
				iterations = 4, angle = 18,
				segmentLength = 6, segmentThickness = 2.5,
				lengthDecay = 0.76, thicknessDecay = 0.7,
				material = Enum.Material.Ice, color = Color3.fromRGB(200, 235, 255),
				leafEnabled = false,
			},
		},
		{
			type = "simple", name = "IcePillar", density = 0.015, cell = 12,
			sizeMin = Vector3.new(3, 12, 3), sizeMax = Vector3.new(8, 28, 8),
			material = Enum.Material.Glacier, color = Color3.fromRGB(180, 220, 245),
		},
		{
			type = "simple", name = "SnowMound", density = 0.012, cell = 12,
			shape = "Ball",
			sizeMin = Vector3.new(4, 2, 4), sizeMax = Vector3.new(10, 5, 10),
			material = Enum.Material.Snow, color = Color3.fromRGB(240, 248, 255),
		},
		{
			type = "simple", name = "FrozenBoulder", density = 0.015, cell = 10,
			shape = "Ball",
			sizeMin = Vector3.new(4, 4, 4), sizeMax = Vector3.new(10, 8, 10),
			material = Enum.Material.Glacier, color = Color3.fromRGB(160, 200, 230),
		},
	},
}
