local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BiomesFolder = ReplicatedStorage.Source.Biomes

local BiomeConfig = {}

BiomeConfig.Biomes = {
	require(BiomesFolder.Meadow),
	require(BiomesFolder.Desert),
	require(BiomesFolder.Arctic),
	require(BiomesFolder.Volcanic),
	require(BiomesFolder.Forest),
}

function BiomeConfig.GetCount()
	return #BiomeConfig.Biomes
end

function BiomeConfig.GetBiome(index)
	return BiomeConfig.Biomes[index]
end

function BiomeConfig.GetRandomIndex()
	return math.random(1, #BiomeConfig.Biomes)
end

return BiomeConfig
