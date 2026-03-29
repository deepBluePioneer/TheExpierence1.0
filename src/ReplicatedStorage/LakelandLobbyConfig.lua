-- Shared lobby placement. Must sit outside the Lakeland race Terrain footprint
-- (500×500 studs centered at FIXED_MACHINE_POS XZ ≈ 0,0). Lobby floor is a Part
-- (not Terrain voxels) so only biomes use smooth Terrain; see LakelandDataService.
local LakelandLobbyConfig = {}

LakelandLobbyConfig.ORIGIN = Vector3.new(0, 50, -400)
LakelandLobbyConfig.PLATFORM_SIZE = Vector3.new(200, 4, 200)
LakelandLobbyConfig.MACHINE_SPACING = 20
LakelandLobbyConfig.MACHINE_CLEARANCE = 0.15

function LakelandLobbyConfig.getSurfaceY()
	return LakelandLobbyConfig.ORIGIN.Y + LakelandLobbyConfig.PLATFORM_SIZE.Y / 2
end

return LakelandLobbyConfig
