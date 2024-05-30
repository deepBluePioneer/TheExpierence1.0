local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Mouse = require(Packages.Input).Mouse
local Player = Players.LocalPlayer
local partcache = require(Packages.partcache)

local FastCast = require(CustomPackages.FastCastFolder.FastCastRedux)
local WeaponsService
local bulletCache
local signal = require(Packages.Signal)


local bulletFireEvent
local WeaponController = Knit.CreateController {
     Name = "WeaponController",
     FireRaySignal = signal.new(),
     OnHitSignal = signal.new() -- Create the signal within the table



}
function  WeaponController:initBullet()

    WeaponsService = Knit.GetService("WeaponsService")

    local bulletTemplate = Instance.new("Part")
    bulletTemplate.Shape = Enum.PartType.Ball
    bulletTemplate.Size = Vector3.new(5, 5, 5)
    bulletTemplate.Material = Enum.Material.Neon
    bulletTemplate.BrickColor = BrickColor.new("Bright red")
    bulletTemplate.Anchored = true
    bulletTemplate.CanCollide = false

    bulletCache = partcache.new(bulletTemplate, 200)

    WeaponsService.RayHit:Connect(function(player, hit, hitPosition, hitNormal)
        -- Handle visual and other effects on hit
        --print("Ray hit:", hit, hitPosition, hitNormal)
    end)
    
end
function  WeaponController:initWeapon()
    task.wait(3)
    bulletFireEvent = ReplicatedStorage:WaitForChild("BulletFireEvent")
    FastCast.VisualizeCasts = false

    local VehicleService = Knit.GetService("VehicleService")

    VehicleService:GetPlayerVehicle():andThen(function(vehicleModel)
        if vehicleModel then
            self.VehicleModel = vehicleModel
            self.PrimaryPart = vehicleModel.PrimaryPart      
        else
            warn("No vehicle model found for the player")
        end
    end):catch(function(err)
        warn("Failed to get vehicle model:", err)
    end)

    local mouse = Mouse.new()

    mouse.LeftDown:Connect(function()
        self:StartAutomaticFiring()
    end)

    mouse.LeftUp:Connect(function()
        self:StopAutomaticFiring()
    end)
end



function WeaponController:StartAutomaticFiring()
    self.isFiring = true
    self.lastFireTime = 0
    self.fireRate = 0.15  -- Increase this value to slow down the rate of fire (e.g., 0.5 for slower rate)

    self.fireConnection = RunService.RenderStepped:Connect(function()
        local currentTime = tick()
        if self.isFiring and (currentTime - self.lastFireTime) >= self.fireRate then
            self:FireRay(self.PrimaryPart)
            self.lastFireTime = currentTime
        end
    end)
end

function WeaponController:StopAutomaticFiring()
    self.isFiring = false
    if self.fireConnection then
        self.fireConnection:Disconnect()
        self.fireConnection = nil
    end
end


function WeaponController:FireRay()
    if self.PrimaryPart then
        -- Get the firing point part
        local firingPoint = self.PrimaryPart:FindFirstChild("FiringPoint")
        if not firingPoint then
            warn("Firing point not found")
            return
        end
        local firingPointPosition = firingPoint.Position
        local firingPointForward = firingPoint.CFrame.LookVector

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {self.VehicleModel, Player.Character}
        params.IgnoreWater = true

        local result = workspace:Raycast(firingPointPosition, firingPointForward * 1000, params)

        local targetPoint
        if result then
            targetPoint = result.Position
        else
            targetPoint = firingPointPosition + firingPointForward * 1000
        end

        local direction = (targetPoint - firingPointPosition).Unit

        local rayData = {
            origin = firingPointPosition,
            direction = direction,
            timestamp = tick()  -- Add timestamp here
        }

        -- Emit the signal with the rayData
        self.FireRaySignal:Fire(rayData)
        -- WeaponsService:SendRay(rayData, self.PrimaryPart)
        -- bulletFireEvent:FireServer(rayData, self.PrimaryPart)

        -- Use FastCast to create and manage the bullet on the client
        local bullet = bulletCache:GetPart()
        bullet.CFrame = CFrame.new(firingPointPosition)
        bullet.Parent = workspace

        local castBehavior = FastCast.newBehavior()
        castBehavior.RaycastParams = params
        castBehavior.CosmeticBullet = bullet
        castBehavior.AutoIgnoreContainer = false

        local caster = FastCast.new()
        caster.LengthChanged:Connect(function(cast, lastPoint, rayDir, displacement, segmentVelocity)
            local newPoint = lastPoint + (rayDir * displacement)
            bullet.CFrame = CFrame.new(newPoint, newPoint + rayDir)
        end)
        caster.RayHit:Connect(function(cast, result, velocity)
            if result and CollectionService:HasTag(result.Instance, "enemy") then
                self.OnHitSignal:Fire(result.Instance)
            end
            bulletCache:ReturnPart(bullet)
        end)
        caster:Fire(firingPointPosition, direction, 500, castBehavior)  -- Adjust the velocity as needed
    end
end


function WeaponController:KnitInit()
 
end

function WeaponController:KnitStart()

end




return WeaponController
