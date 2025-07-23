-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

-- Packages
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

-- ZonePlus
local ZoneRoot = CustomPackages:WaitForChild("ZoneRoot")
local Zone = require(ZoneRoot:WaitForChild("Zone"))

-- Service Definition
local MeteorService = Knit.CreateService {
    Name = "MeteorService",
    Client = {},
}

-- Track players in the zone
local activePlayersInZone = {}

-- Create a particle emitter with box-shaped texture (used for CreateMeteorZone visual effect)
local function createBoxParticleEmitter()
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "BoxParticle"
    emitter.Texture = "rbxassetid://124394366919392"
    emitter.Rate = 5
    emitter.Lifetime = NumberRange.new(10, 12)
    emitter.Speed = NumberRange.new(30, 35)
    emitter.EmissionDirection = Enum.NormalId.Top
    emitter.VelocitySpread = 15
    emitter.Size = NumberSequence.new(1)
    emitter.LightEmission = 0.4
    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1)
    })
    emitter.Color = ColorSequence.new(Color3.fromRGB(255, 150, 100))
    emitter.LockedToPart = false
    return emitter
end

-- Creates a grid of invisible particle emitters within the sphere volume
local function createVolumeEmitters(sphere, radius, spacing)
    local origin = sphere.Position
    local count = math.floor(radius / spacing)

    for x = -count, count do
        for y = -count, count do
            for z = -count, count do
                local pos = origin + Vector3.new(x, y, z) * spacing
                if (pos - origin).Magnitude <= radius * 0.5 then
                    local emitterPart = Instance.new("Part")
                    emitterPart.Name = "Emitter"
                    emitterPart.Size = Vector3.new(spacing - 1, spacing - 1, spacing - 1)
                    emitterPart.Anchored = true
                    emitterPart.CanCollide = false
                    emitterPart.Transparency = 1
                    emitterPart.Position = pos
                    emitterPart.Parent = sphere

                    local emitter = createBoxParticleEmitter()
                    emitter.Rate = 6
                    emitter.Parent = emitterPart
                end
            end
        end
    end
end

-- Create a meteor zone with visual effects
function MeteorService:CreateMeteorZone(position, radius)
    local sphere = Instance.new("Part")
    sphere.Name = "MeteorZone"
    sphere.Shape = Enum.PartType.Ball
    sphere.Size = Vector3.new(radius, radius, radius)
    sphere.Position = position
    sphere.Anchored = true
    sphere.CanCollide = false
    sphere.Transparency = 0.5
    sphere.Material = Enum.Material.ForceField
    sphere.Color = Color3.fromRGB(255, 100, 100)
    sphere.Parent = Workspace

    createVolumeEmitters(sphere, radius, 10)

    local zone = Zone.new(sphere)
    zone.playerEntered:Connect(function(player)
        print(player.Name .. " entered the meteor zone.")
        activePlayersInZone[player] = true
    end)
    zone.playerExited:Connect(function(player)
        print(player.Name .. " exited the meteor zone.")
        activePlayersInZone[player] = nil
    end)
end

-- Rain logic: spawn meteors near random players
function MeteorService:Rain()
	local Prefabs = ReplicatedStorage:WaitForChild("Prefabs")
	local meteorPrefab = Prefabs:WaitForChild("Meteor")
	local taggedZones = CollectionService:GetTagged("meteorZone")

	-- Cache Zone objects
	local zones = {}
	for _, container in ipairs(taggedZones) do
		table.insert(zones, Zone.new(container))
	end

	-- Repeatedly spawn meteors near random players
	task.spawn(function()
		while true do
			local players = Players:GetPlayers()
			if #players == 0 then
				task.wait(1)
				continue
			end

			local chosenPlayer = players[math.random(1, #players)]
			local char = chosenPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				task.wait(1)
				continue
			end

			local targetPos = hrp.Position

			-- Find best random point closest to this player
			local bestPoint = nil
			local bestDist = math.huge

			for _, zone in ipairs(zones) do
				for _ = 1, 5 do
					local point = zone:getRandomPoint()
					if point then
						local dist = (point - targetPos).Magnitude
						if dist < bestDist then
							bestDist = dist
							bestPoint = point
						end
					end
				end
			end

			if bestPoint then
				local spawnPos = bestPoint + Vector3.new(0, 50, 0)
				local meteor = meteorPrefab:Clone()
				meteor.Position = spawnPos
				meteor.Anchored = false
				meteor.CanCollide = true
				meteor.Parent = workspace

				-- Apply velocity toward the player
				local direction = (targetPos - spawnPos).Unit
				local speed = 1000 -- adjust to your liking
				meteor.AssemblyLinearVelocity = direction * speed
			end

			task.wait(math.random(1, 3))
		end
	end)
end


-- Knit lifecycle
function MeteorService:KnitInit() end

function MeteorService:KnitStart()
    --self:Rain()
end

return MeteorService
