-- ReplicatedStorage/Modules/VO/VOConfig.lua
-- Maps friendly VO keys -> uploaded asset IDs

local VOConfig = {
    -- === Intro ===
    Intro_Welcome     = "rbxassetid://0000000001",
    Intro_Compliance  = "rbxassetid://0000000002",

    -- === Clause 1 ===
    Clause1_Read      = "rbxassetid://0000000101",
    Clause1_Signed    = "rbxassetid://0000000102",
    Clause1_Rejected  = "rbxassetid://0000000103",

    -- === Clause 2 ===
    Clause2_Read      = "rbxassetid://0000000201",
    Clause2_Signed    = "rbxassetid://0000000202",
    Clause2_Rejected  = "rbxassetid://0000000203",

    -- === Clause 3 ===
    Clause3_Read      = "rbxassetid://0000000301",
    Clause3_Signed    = "rbxassetid://0000000302",
    Clause3_Rejected  = "rbxassetid://0000000303",

    -- === Clause 4 ===
    Clause4_Read      = "rbxassetid://0000000401",
    Clause4_Signed    = "rbxassetid://0000000402",
    Clause4_Rejected  = "rbxassetid://0000000403",

    -- === Clause 5 ===
    Clause5_Read      = "rbxassetid://0000000501",
    Clause5_Signed    = "rbxassetid://0000000502",
    Clause5_Rejected  = "rbxassetid://0000000503",

    -- === Escalation ===
    Escalation1       = "rbxassetid://0000000601",
    Escalation2       = "rbxassetid://0000000602",
    Escalation3_Glitch= "rbxassetid://0000000603",

    -- === Final Clause & Endings ===
    Final_Read        = "rbxassetid://0000000701",
    Ending_Obedient   = "rbxassetid://0000000801",
    Ending_Defiant    = "rbxassetid://0000000802",
    Ending_Mixed      = "rbxassetid://0000000803",
}

return VOConfig
