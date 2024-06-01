--- PatchesModule
-- This module contains definitions for various patches that modify machine stats.
-- @module PatchesModuls

--- Table holding all patch definitions.
-- @field TurnPatch Patch that modifies the Turn stat.
-- @field ChargePatch Patch that modifies the Charge stat.
-- @field GlidePatch Patch that modifies the Glide stat.
-- @field WeightPatch Patch that modifies the Weight stat.
-- @field OffensePatch Patch that modifies the Offense stat.
-- @field DefensePatch Patch that modifies the Defense stat.
-- @field HPPatch Patch that modifies the HP stat.
-- @field AllPatch Patch that modifies all stats.
PatchesModule = {}

--- Patch definition.
-- @table Patch
-- @field Stat The name of the stat modified by the patch.
-- @field Description A description of what the patch does.
-- @field Value The value by which the stat is modified.
-- @field Color The color representing the patch.
-- @field SpriteID The ID of the sprite representing the patch.

PatchesModule.Patches = {
    TurnPatch = {
        Stat = "Turn",
        Description = "Turn aids a machine's handling. Turning is important for going past sharp corners and turns, as well as avoiding damage from the environment.",
        Value = 10,
        Color = Color3.fromRGB(255, 0, 0), -- Red
        SpriteID = 11600511955 -- Sigma
    },
    ChargePatch = {
        Stat = "Charge",
        Description = "Charge raises a machine's charging speed, making it charge faster. Charging is good for accelerating quicker and winning races.",
        Value = 10,
        Color = Color3.fromRGB(0, 255, 0), -- Green
        SpriteID = 10729455663 -- Sad Spongebob meme
    },
    GlidePatch = {
        Stat = "Glide",
        Description = "Glide raises a machine's ability to glide. Gliding is good for getting to higher places easier.",
        Value = 10,
        Color = Color3.fromRGB(0, 0, 255), -- Blue
        SpriteID = 10180628714 -- Megamind Meme
    },
    WeightPatch = {
        Stat = "Weight",
        Description = "Weight influences several factors of a machine; it balances Glide, increases top speed and defense, increases knockback given, and decreases the amount of time needed to come to a full stop.",
        Value = 10,
        Color = Color3.fromRGB(255, 255, 0), -- Yellow
        SpriteID = 9895184382 -- Bing Chilling
    },
    OffensePatch = {
        Stat = "Offense",
        Description = "Offense increases a machine's attack power, the amount damage that a player deals with the machine.",
        Value = 10,
        Color = Color3.fromRGB(255, 165, 0), -- Orange
        SpriteID = 11759293347 -- Gengar Crosshair
    },
    DefensePatch = {
        Stat = "Defense",
        Description = "Defense increases a machine's damage resistance, the amount damage that a machine avoids taking.",
        Value = 10,
        Color = Color3.fromRGB(128, 0, 128), -- Purple
        SpriteID = 11759193017 -- Dragon Ball Crosshair
    },
    HPPatch = {
        Stat = "HP",
        Description = "HP raises a machine's stamina. If the machine's stamina is depleted, it will explode, and the player will have to find a new one.",
        Value = 18.75, -- This value will be used as a percentage increase
        Color = Color3.fromRGB(255, 192, 203), -- Pink
        SpriteID = 7220505725 -- Cat that fell into its milk
    },
    AllPatch = {
        Stat = "All",
        Description = "The All Patch raises every stat on a machine by one. It is the ultimate power up, and is the rarest of them all.",
        Value = 1,
        Color = Color3.fromRGB(255, 255, 255), -- White
        SpriteID = 4632517063 -- Peter Griffin Voice Call
    }
}

return PatchesModule
