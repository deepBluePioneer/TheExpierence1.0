-- CustomPackages/StatDecorators.lua

local StatDecorators = {}

function StatDecorators.ApplyHP(vehicle, value)
    vehicle.Stats.HP = (vehicle.Stats.HP or 0) + value
end

function StatDecorators.ApplyTopSpeed(vehicle, value)
    vehicle.Stats.TopSpeed = (vehicle.Stats.TopSpeed or 0) + value
end

function StatDecorators.ApplyBoost(vehicle, value)
    vehicle.Stats.Boost = (vehicle.Stats.Boost or 0) + value
end

function StatDecorators.ApplyCharge(vehicle, value)
    vehicle.Stats.Charge = (vehicle.Stats.Charge or 0) + value
end

function StatDecorators.ApplyTurn(vehicle, value)
    vehicle.Stats.Turn = (vehicle.Stats.Turn or 0) + value
end

function StatDecorators.ApplyOffense(vehicle, value)
    vehicle.Stats.Offense = (vehicle.Stats.Offense or 0) + value
end

function StatDecorators.ApplyDefense(vehicle, value)
    vehicle.Stats.Defense = (vehicle.Stats.Defense or 0) + value
end

function StatDecorators.ApplyWeight(vehicle, value)
    vehicle.Stats.Weight = (vehicle.Stats.Weight or 0) + value
end

function StatDecorators.ApplyGlide(vehicle, value)
    vehicle.Stats.Glide = (vehicle.Stats.Glide or 0) + value
end

return StatDecorators
