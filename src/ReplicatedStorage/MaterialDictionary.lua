-- Module script: MaterialTextureDictionary.lua

local MaterialTextureDictionary = {}

MaterialTextureDictionary.materials = {
    ["banner_pole.mat"] = {
        _BumpMap = "banner_pole_normal",
        _MainTex = "banner_pole_basecolor",        
        _MetallicGlossMap = "banner_pole_metallic"
    },
    ["bark.mat"] = {
        _BumpMap = "bark_normal",
        _MainTex = "bark_basecolor",
        _Metallic = "noMetal",
        _NormalMap = "bark_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["barrels.mat"] = {
        _BumpMap = "barrels_normal",
        _MainTex = "barrels_basecolor",
        _Metallic = "barrels_metallic",
        _MetallicGlossMap = "barrels_metallic",    
        _NormalMap = "barrels_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["bed_a.mat"] = {
        _BumpMap = "bed_a_normal",
        _MainTex = "bed_a_basecolor"
    },
    ["booth_cloth.mat"] = {
        _BumpMap = "booth_cloth_normal",
        _DetailAlbedoMap = "booth_cloth_basecolor_overlay",
        _DetailNormalMap = "booth_cloth_normal_overlay",
        _MainTex = "booth_cloth_basecolor",
        _Metallic = "noMetal",
        _NormalMap = "booth_cloth_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["candleholder.mat"] = {
        _BumpMap = "candleholder_normal",
        _MainTex = "candleholder_basecolor",
        _MetallicGlossMap = "candleholder_metallic"
    },
    ["candles.mat"] = {
        _BumpMap = "candles_normal",
        _MainTex = "candles_basecolor"
    },
    ["cart_a.mat"] = {
        _BumpMap = "cart_a_normal",
        _MainTex = "cart_a_basecolor",
        _Metallic = "cart_a_metallic",
        _MetallicGlossMap = "cart_a_metallic",
        _NormalMap = "cart_a_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["chairs.mat"] = {
        _BumpMap = "chairs_normal",
        _MainTex = "chairs_basecolor"
    },
    ["chest_a.mat"] = {
        _BumpMap = "chest_a_normal",
        _MainTex = "chest_a_basecolor",
        _MetallicGlossMap = "chest_a_metallic"
    },
    ["chest_b.mat"] = {
        _BumpMap = "chest_b_normal",
        _MainTex = "chest_b_basecolor",
        _MetallicGlossMap = "chest_b_metallic"
    },
    ["chimney_kitchen.mat"] = {
        _BumpMap = "wall_d_normal",
        _MainTex = "chimney_kitchen_basecolor"
    },
    ["cloth_a.mat"] = {
        _BumpMap = "cloth_a_normal",
        _MainTex = "cloth_a_basecolor"
    },
    ["cloth_b.mat"] = {
        _BumpMap = "cloth_b_normal",
        _MainTex = "cloth_b_basecolor"
    },
    ["column.mat"] = {
        _BumpMap = "column_normal",
        _MainTex = "column_basecolor",
        _MetallicGlossMap = "Unknown Texture"
    },
    ["decal_crack_a.mat"] = {
        _BumpMap = "decal_crack_a_normal",
        _MainTex = "decal_crack_a_basecolor"
    },
    ["decal_crack_b.mat"] = {
        _BumpMap = "decal_crack_b_normal",
        _MainTex = "decal_crack_b_basecolor"
    },
    ["decal_crack_c.mat"] = {
        _BumpMap = "decal_crack_c_normal",
        _MainTex = "decal_crack_c_basecolor"
    },
    ["decal_dirt_a.mat"] = {
        _BumpMap = "decal_dirt_a_normal",
        _MainTex = "decal_dirt_a_basecolor"
    },
    ["decal_dirt_a1.mat"] = {
        _BumpMap = "decal_dirt_a_normal",
        _MainTex = "decal_dirt_a_basecolor"
    },
    ["decal_dirt_b.mat"] = {
        _BumpMap = "decal_dirt_b_normal",
        _MainTex = "decal_dirt_b_basecolor"
    },
    ["decal_dirt_b1.mat"] = {
        _BumpMap = "decal_dirt_b_normal",
        _MainTex = "decal_dirt_b_basecolor"
    },
    ["decal_wall_a.mat"] = {
        _BumpMap = "decal_wall_a_normal",
        _MainTex = "decal_wall_a_basecolor"
    },
    ["decal_wall_b.mat"] = {
        _BumpMap = "decal_wall_b_normal",
        _MainTex = "decal_wall_b_basecolor"
    },
    ["decal_wall_c.mat"] = {
        _BumpMap = "decal_wall_c_normal",
        _MainTex = "decal_wall_c_basecolor"
    },
    ["decal_wall_d.mat"] = {
        _BumpMap = "decal_wall_d_normal",
        _MainTex = "decal_wall_d_basecolor",
        _MetallicGlossMap = "Unknown Texture"
    },
    ["door_a.mat"] = {
        _BumpMap = "door_a_normal",
        _MainTex = "door_a_basecolor",
        _Metallic = "door_a_metallic",
        _MetallicGlossMap = "door_a_metallic",
        _NormalMap = "door_a_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["door_a_variant.mat"] = {
        _BumpMap = "door_a_normal",
        _MainTex = "door_a_basecolor_clean",
        _Metallic = "door_a_metallic",
        _MetallicGlossMap = "door_a_metallic",
        _NormalMap = "door_a_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["door_b.mat"] = {
        _BumpMap = "door_b_normal",
        _MainTex = "door_b_basecolor",
        _Metallic = "door_b_metallic",
        _MetallicGlossMap = "door_b_metallic",
        _NormalMap = "door_b_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["door_b_dirty.mat"] = {
        _BumpMap = "door_b_dirty_normal",
        _MainTex = "door_b_dirty_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "door_b_dirty_metallic",
        _NormalMap = "door_b_dirty_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["door_c.mat"] = {
        _BumpMap = "door_c_normal",
        _MainTex = "door_c_basecolor",
        _MetallicGlossMap = "door_c_metallic"
    },
    ["door_d.mat"] = {
        _BumpMap = "door_d_normal",
        _MainTex = "door_d_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "door_d_metallic",
        _NormalMap = "door_d_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["door_e_iron.mat"] = {
        _BumpMap = "door_e_iron_normal",
        _MainTex = "door_e_iron_basecolor",
        _Metallic = "door_e_iron_metallic",
        _MetallicGlossMap = "door_e_iron_metallic",
        _NormalMap = "door_e_iron_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["door_e_wood.mat"] = {
        _BumpMap = "door_e_wood_normal",
        _MainTex = "door_e_wood_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "door_e_wood_metallic",
        _NormalMap = "door_e_wood_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["floor_a.mat"] = {
        _BumpMap = "floor_a_normal",
        _MainTex = "floor_a_basecolor",
        _ParallaxMap = "Unknown Texture"
    },
    ["furniture_a.mat"] = {
        _BumpMap = "furniture_a_normal",
        _MainTex = "furniture_a_basecolor"
    },
    ["furniture_b.mat"] = {
        _BumpMap = "funiture_b_normal",
        _MainTex = "funiture_b_basecolor",
        _MetallicGlossMap = "funiture_b_metallic"
    },
    ["furniture_b_1.mat"] = {
        _BumpMap = "funiture_b_normal",
        _MainTex = "funiture_b_basecolor",
        _MetallicGlossMap = "funiture_b_metallic"
    },
    ["gate_a.mat"] = {
        _BumpMap = "gate_a_normal",
        _MainTex = "gate_a_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "Unknown Texture",
        _NormalMap = "gate_a_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["gate_a_wing.mat"] = {
        _BumpMap = "gate_a_wing_normal",
        _MainTex = "gate_a_wing_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "gate_a_wing_metallic",
        _NormalMap = "gate_a_wing_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["glass_a_inside.mat"] = {
        _BumpMap = "glass_a_normal",
        _EmissionMap = "glass_a_emission",
        _MainTex = "glass_a_basecolor",
        _MetallicGlossMap = "glass_a_metallic"
    },
    ["glass_a_outside.mat"] = {
        _BumpMap = "glass_a_normal",
        _MainTex = "glass_a_basecolor",
        _MetallicGlossMap = "glass_a_metallic"
    },
    ["glass_b_inside.mat"] = {
        _BumpMap = "glass_b_normal",
        _EmissionMap = "glass_b_emission",
        _MainTex = "glass_b_basecolor",
        _MetallicGlossMap = "glass_b_metallic"
    },
    ["glass_b_outside.mat"] = {
        _BumpMap = "glass_b_normal",
        _MainTex = "glass_b_basecolor",
        _MetallicGlossMap = "glass_b_metallic"
    },
    ["grass.mat"] = {
        _BumpMap = "Unknown Texture",
        _Diffuse = "grass_basecolor",
        _MainTex = "grass_basecolor",
        _Normal = "Unknown Texture"
    },
    ["halberd.mat"] = {
        _BumpMap = "halberd_normal",
        _MainTex = "halberd_basecolor",
        _MetallicGlossMap = "halberd_metallic"
    },
    ["kitchen_props.mat"] = {
        _BumpMap = "kitchen_props_normal",
        _MainTex = "kitchen_props_basecolor",
        _MetallicGlossMap = "kitchen_props_metallic"
    },
    ["leafes_plane.mat"] = {
        _BumpMap = "leafes_plane_normal",
        _Diffuse = "leafes_plane_basecolor",
        _MainTex = "leafes_plane_basecolor",
        _MetallicGlossMap = "Unknown Texture",
        _Normal = "leafes_plane_normal"
    },
    ["morningstar.mat"] = {
        _BumpMap = "morningstar_normal",
        _MainTex = "morningstar_basecolor",
        _MetallicGlossMap = "morningstar_metallic"
    },
    ["mountain_a.mat"] = {
        _BumpMap = "mountain_a_normal",
        _MainTex = "mountain_a_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "Unknown Texture",
        _NormalMap = "mountain_b_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["mountain_b.mat"] = {
        _BumpMap = "mountain_b_normal",
        _MainTex = "mountain_b_basecolor",
        _Metallic = "noMetal",
        _NormalMap = "Unknown Texture",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["mountain_c.mat"] = {
        _BumpMap = "mountain_c_normal",
        _MainTex = "mountain_c_basecolor",
        _Metallic = "noMetal",
        _NormalMap = "Unknown Texture",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["package_a.mat"] = {
        _BumpMap = "package_a_normal",
        _MainTex = "package_a_basecolor",
        _Metallic = "noMetal",
        _NormalMap = "package_a_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["package_b.mat"] = {
        _BumpMap = "package_b_normal",
        _MainTex = "package_b_basecolor",
        _Metallic = "noMetal",
        _NormalMap = "package_b_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["pottery.mat"] = {
        _BumpMap = "pottery_normal",
        _MainTex = "pottery_basecolor",
        _MetallicGlossMap = "Unknown Texture"
    },
    ["rock_a.mat"] = {
        _BumpMap = "rock_a_normal",
        _MainTex = "rock_a_basecolor",
        _Metallic = "noMetal",
        _NormalMap = "rock_a_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["rock_b.mat"] = {
        _BumpMap = "rock_b_normal",
        _MainTex = "rock_b_basecolor",
        _Metallic = "noMetal",
        _NormalMap = "rock_b_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["rock_c.mat"] = {
        _BumpMap = "rock_c_normal",
        _MainTex = "rock_c_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "Unknown Texture",
        _NormalMap = "rock_c_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["roofBeams_large.mat"] = {
        _BumpMap = "wood_a_normal",
        _DetailAlbedoMap = "roofBeams_basecolor",
        _DetailNormalMap = "roofBeams_normal",
        _MainTex = "wood_a_basecolor",
        _MetallicGlossMap = "Unknown Texture"
    },
    ["roofBeams_small.mat"] = {
        _BumpMap = "wood_a_normal",
        _DetailAlbedoMap = "roofBeams_basecolor",
        _DetailNormalMap = "roofBeams_normal",
        _MainTex = "wood_a_basecolor",
        _MetallicGlossMap = "Unknown Texture"
    },
    ["roofTiles.mat"] = {
        _BumpMap = "roofTiles_normal",
        _HeightMap = "Unknown Texture",
        _MainTex = "roofTiles_basecolor",
        _Metallic = "Unknown Texture",
        _MetallicGlossMap = "Unknown Texture",
        _NormalMap = "Unknown Texture",
        _ParallaxMap = "roofTiles_height",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["roof_deco.mat"] = {
        _BumpMap = "roof_deco_normal",
        _MainTex = "roof_deco_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "roof_deco_metallic",
        _NormalMap = "roof_deco_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["sandstone_base.mat"] = {
        _BumpMap = "sandstone_base_normal",
        _MainTex = "sandstone_base_basecolor",
        _MetallicGlossMap = "Unknown Texture"
    },
    ["shields.mat"] = {
        _BumpMap = "shields_normal",
        _MainTex = "shields_basecolor",
        _MetallicGlossMap = "shields_metallic"
    },
    ["showcase_plane.mat"] = {
        -- No textures found or error parsing the file
    },
    ["squareBricks.mat"] = {
        _BumpMap = "stone_bricks_a_normal",
        _MainTex = "stone_bricks_a_basecolor",
        _MetallicGlossMap = "Unknown Texture"
    },
    ["stonesWallDeco.mat"] = {
        _BumpMap = "StonesWallDeco_normal",
        _MainTex = "StonesWallDeco_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "StonesWallDeco_metallic",
        _NormalMap = "StonesWallDeco_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["swords.mat"] = {
        _BumpMap = "swords_normal",
        _MainTex = "swords_basecolor",
        _MetallicGlossMap = "swords_metallic"
    },
    ["table_round.mat"] = {
        _BumpMap = "table_round_normal",
        _MainTex = "table_round_basecolor"
    },
    ["Terrain Material.mat"] = {
        -- No textures found or error parsing the file
    },
    ["throne.mat"] = {
        _BumpMap = "throne_normal",
        _MainTex = "throne_basecolor"
    },
    ["torture_gear.mat"] = {
        _BumpMap = "torture_gear_normal",
        _MainTex = "torture_gear_basecolor",
        _MetallicGlossMap = "torture_gear_metallic"
    },
    ["tower_a.mat"] = {
        _BumpMap = "tower_a_normal",
        _MainTex = "tower_a_basecolor",
        _Metallic = "tower_a_metallic",
        _MetallicGlossMap = "tower_a_metallic",
        _NormalMap = "tower_a_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["tower_b_deco.mat"] = {
        _BumpMap = "tower_b_deco_normal",
        _MainTex = "tower_b_deco_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "tower_b_deco_metallic",
        _NormalMap = "tower_b_deco_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["tower_b_stairs.mat"] = {
        _BumpMap = "tower_b_stairs_normal",
        _MainTex = "tower_b_stairs_basecolor",
        _MetallicGlossMap = "tower_b_stairs_metallic"
    },
    ["tree_b_branch.mat"] = {
        _BumpMap = "tree_b_branch_normal",
        _MainTex = "tree_b_branch_basecolor"
    },
    ["wall_a.mat"] = {
        _BumpMap = "wall_a_normal",
        _HeightMap = "wall_a_height",
        _MainTex = "wall_a_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "Unknown Texture",
        _NormalMap = "wall_a_normal",
        _ParallaxMap = "wall_a_height",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal",
        _basecolor = "wall_a_basecolor",
        _normalmap = "wall_a_normal"
    },
    ["wall_a_x2.mat"] = {
        _BumpMap = "wall_a_normal",
        _MainTex = "wall_a_basecolor",
        _Metallic = "noMetal",
        _NormalMap = "wall_a_normal",
        _ParallaxMap = "wall_a_height",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["wall_b.mat"] = {
        _BumpMap = "wall_b_normal",
        _MainTex = "wall_b_basecolor",
        _MetallicGlossMap = "Unknown Texture",
        _ParallaxMap = "wall_b_height"
    },
    ["wall_b_x2.mat"] = {
        first = "wall_b_height"
    },
    ["wall_c.mat"] = {
        _BumpMap = "wall_c_normal",
        _MainTex = "wall_c_basecolor"
    },
    ["wall_d.mat"] = {
        _BumpMap = "wall_d_normal",
        _MainTex = "wall_d_basecolor"
    },
    ["wall_outer_deco.mat"] = {
        _BumpMap = "wall_outer_normal",
        _MainTex = "wall_outer_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "wall_outer_metallic",
        _NormalMap = "wall_outer_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["wheel_barrow.mat"] = {
        _BumpMap = "wheel_barrow_normal",
        _MainTex = "wheel_barrow_basecolor",
        _MetallicGlossMap = "wheel_barrow_metallic"
    },
    ["window_a.mat"] = {
        _BumpMap = "window_a_normal",
        _MainTex = "window_a_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "Unknown Texture",
        _NormalMap = "window_a_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["window_b.mat"] = {
        _BumpMap = "window_b_normal",
        _MainTex = "window_b_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "window_b_metallic",
        _NormalMap = "window_b_normal",
        _SnowBasecolor = "Snow_basecolor",
        _SnowNormalMap = "Snow_normal"
    },
    ["window_c_d.mat"] = {
        _BumpMap = "window_c_normal",
        _MainTex = "window_c_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "Unknown Texture",
        _NormalMap = "window_c_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["wood_a_beams.mat"] = {
        _BumpMap = "wood_a_with_nails_normal",
        _DetailAlbedoMap = "wood_a_beams_basecolor_overlay",
        _DetailNormalMap = "wood_a_beams_normal_overlay",
        _MainTex = "wood_a_with_nails_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "wood_a_with_nails_metallic",
        _NormalMap = "wood_a_beams_normal_overlay",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["wood_a_deco.mat"] = {
        _BumpMap = "wood_a_deco_normal",
        _MainTex = "wood_a_deco_basecolor",
        _Metallic = "noMetal",
        _MetallicGlossMap = "wood_a_deco_metallic",
        _NormalMap = "wood_a_deco_normal",
        _SnowBasecolor = "Snow_basecolor"
    },
    ["wood_a_planks.mat"] = {
        _BumpMap = "wood_a_planks_normal",
        _MainTex = "wood_a_planks_basecolor",
        _MetallicGlossMap = "wood_a_planks_metallic"
    },
    ["wood_b_beams.mat"] = {
        _BumpMap = "wood_b_normal",
        _DetailAlbedoMap = "wood_a_beams_basecolor_overlay",
        _DetailNormalMap = "wood_a_beams_normal_overlay",
        _MainTex = "wood_b_basecolor",
        _MetallicGlossMap = "Unknown Texture"
    },
    ["wood_b_planks.mat"] = {
        _BumpMap = "wood_b_planks_normal",
        _MainTex = "wood_b_planks_basecolor",
        _MetallicGlossMap = "wood_b_planks_metallic",
        _ParallaxMap = "wood_b_planks_height"
    },
    ["wood_logs.mat"] = {
        _BumpMap = "wood_logs_normal",
        _MainTex = "wood_logs_basecolor"
    }
}

return MaterialTextureDictionary
