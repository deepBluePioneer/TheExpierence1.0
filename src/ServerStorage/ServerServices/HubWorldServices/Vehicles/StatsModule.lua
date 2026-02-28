local StatModule = {}

-- Define the Machine abilities with their descriptions
StatModule.Abilities = {
    HP = {
        Description = "HP represents the amount of damage a Machine can sustain. Upon reaching zero HP, a Machine is destroyed. Having any non-zero HP lower than the maximum does not impact a Machine's performance.",
        Default = 100
    },
    TopSpeed = {
        Description = "Top Speed is the highest speed a machine can attain. It is essential to have this on relatively straight courses.",
        Default = 100
    },
    Boost = {
        Description = "Boost determines a machine's automatic acceleration and the speed boost when releasing the charge from the Boost Meter. The higher the machine's boost rating, the sooner it can reach its top speed and the faster it goes when releasing a boost charge.",
        Default = 50
    },
    Charge = {
        Description = "Charge determines the amount of time it takes to fill up the Boost Gauge when Button A is held down. The higher the charge rating, the faster the Gauge fills.",
        Default = 50
    },
    Turn = {
        Description = "Turn determines the maximum angular rotation a Machine can perform. The higher the turn rating, the faster and tighter it can turn.",
        Default = 50
    },
    Offense = {
        Description = "Offense determines the amount of HP damage inflicted on other players upon contact. High offense gives more damage.",
        Default = 20
    },
    Defense = {
        Description = "Defense determines the reduction of HP damage received when enemies collide into the player's Air Ride Machine. High defense means less damage received.",
        Default = 20
    },
    Weight = {
        Description = "Weight determines the amount of time needed for a Machine to come to a stop and reduces the amount of skidding a Machine has while turning and stopping. Increases the mass of the Machine so it is less prone to being knocked around when damaged. Mass (affected by Weight) is taken into account when collision damage between two machines occur or when ramming into objects. Weight slightly affects top speed.",
        Default = 50
    },
    Glide = {
        Description = "Glide determines the length of time a flying Machine can remain airborne. The higher the gliding rating, the longer it can stay in the air, the higher the arc a Machine makes when taking off, and the easier it becomes to start gliding.",
        Default = 50
    }
}

-- Compute effective stats from base stats + collected patch counts using PatchesConfig.
-- baseStats: table from MachinesConfig (e.g. { topSpeed = 85, acceleration = 6, ... })
-- patchCounts: table { [patchType] = count } (e.g. { speed = 3, handling = 2 })
-- patchesConfig: the PatchesConfig module table
function StatModule.RecalculateStats(baseStats, patchCounts, patchesConfig)
    local result = {}
    for key, value in pairs(baseStats) do
        result[key] = value
    end

    for patchType, count in pairs(patchCounts) do
        local patchDef = patchesConfig.patches[patchType]
        if not patchDef then continue end

        if patchDef.statKeys then
            for i, statKey in ipairs(patchDef.statKeys) do
                local delta = patchDef.deltas[i] * count
                local cap = patchDef.softCaps[i]
                if cap > 0 then
                    delta = math.min(delta, cap)
                else
                    delta = math.max(delta, cap)
                end
                result[statKey] = (result[statKey] or 0) + delta
            end
        elseif patchDef.statKey then
            local delta = patchDef.delta * count
            local cap = patchDef.softCap
            if patchDef.floor ~= nil then
                delta = math.max(delta, cap)
                result[patchDef.statKey] = math.max(
                    (result[patchDef.statKey] or 0) + delta,
                    patchDef.floor
                )
            elseif cap >= 0 then
                delta = math.min(delta, cap)
                result[patchDef.statKey] = (result[patchDef.statKey] or 0) + delta
            else
                delta = math.max(delta, cap)
                result[patchDef.statKey] = (result[patchDef.statKey] or 0) + delta
            end
        end
    end

    return result
end

return StatModule
