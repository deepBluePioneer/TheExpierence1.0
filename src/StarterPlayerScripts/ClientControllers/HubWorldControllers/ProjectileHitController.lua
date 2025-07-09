local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local ProjectileHitController = Knit.CreateController { Name = "ProjectileHitController" }

local signal = require(Packages.Signal)

function ProjectileHitController:KnitStart()

    local WeaponController = Knit.GetController("WeaponController")

    WeaponController.OnHitSignal:Connect(function(enemy)
        -- Handle the rayData
       warn(enemy.Name)
    end)
    -- Add controller startup logic here
end

function ProjectileHitController:KnitInit()
    -- Add controller initialization logic here
end

return ProjectileHitController