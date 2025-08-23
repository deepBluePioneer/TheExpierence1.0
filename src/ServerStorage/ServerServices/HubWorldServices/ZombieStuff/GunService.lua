-- Server/Services/GunService.lua

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Players            = game:GetService("Players")
local PhysicsService     = game:GetService("PhysicsService")
local CollectionService  = game:GetService("CollectionService")

local Packages        = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages  = ReplicatedStorage:WaitForChild("CustomPackages")

local Knit     = require(Packages.Knit)
local FastCast = require(CustomPackages.FastCastFolder:WaitForChild("FastCastRedux"))
FastCast.VisualizeCasts = true

local GunService = Knit.CreateService({
	Name = "GunService",
	Client = {
		RayHit = Knit.CreateSignal(),
		FireGunSignal = Knit.CreateSignal(),
	},
})

-- ======= CONFIG =======
local BULLET_SPEED                = 320          -- studs/sec
local BULLET_GRAVITY              = Vector3.new(0, -workspace.Gravity, 0)
local MAX_DISTANCE                = 1500
local HIGH_FIDELITY_SEGMENT_SIZE  = 0.5
local DAMAGE_PER_HIT              = 15
local ZOMBIE_TAG                  = "zombie"
-- =======================

local Caster = FastCast.new()

local function newBehavior(ignoreList)
	local behavior = FastCast.newBehavior()
	behavior.Acceleration            = BULLET_GRAVITY
	behavior.AutoIgnoreContainer     = false
	behavior.CosmeticBulletTemplate  = nil
	behavior.HighFidelitySegmentSize = HIGH_FIDELITY_SEGMENT_SIZE
	behavior.MaxDistance             = MAX_DISTANCE

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or {}
	params.IgnoreWater = false
	behavior.RaycastParams = params

	return behavior
end

local function buildIgnoreListForPlayer(player: Player)
	local ignore = {}
	local char = player.Character
	if char then table.insert(ignore, char) end
	local effectsFolder = workspace:FindFirstChild("BulletEffects")
	if effectsFolder then table.insert(ignore, effectsFolder) end
	return ignore
end

-- Walk up to see if any ancestor is tagged as zombie
local function getTaggedAncestor(inst: Instance, tag: string)
	local cur = inst
	while cur do
		if CollectionService:HasTag(cur, tag) then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

Caster.LengthChanged:Connect(function() end)

Caster.RayHit:Connect(function(cast, result: RaycastResult, velocity, bullet)
	local shooter: Player? = cast.UserData and cast.UserData.player or nil
	local hitPart = result.Instance
	local pos     = result.Position
	local normal  = result.Normal
	local mat     = result.Material

	-- 1) If it’s a zombie (tag), apply damage via Attribute, destroy at 0
	local zombieInst = getTaggedAncestor(hitPart, ZOMBIE_TAG)
	if zombieInst then
		local hp = zombieInst:GetAttribute("Health")
		if typeof(hp) ~= "number" then
			-- If no Health attribute, default to 0 (one-shot destroy)
			zombieInst:Destroy()
		else
			hp -= DAMAGE_PER_HIT
			zombieInst:SetAttribute("Health", hp)
			if hp <= 0 then
				zombieInst:Destroy()
			end
		end
	end

	-- 2) (Optional) Humanoid damage for other NPCs/players
	local hitHumanoid: Humanoid? = nil
	if hitPart and hitPart.Parent then
		hitHumanoid = hitPart.Parent:FindFirstChildWhichIsA("Humanoid")
	end
	if hitHumanoid and hitHumanoid.Health > 0 then
		hitHumanoid:TakeDamage(DAMAGE_PER_HIT)
	end

	-- Notify shooter (for hit markers, etc.)
	if shooter then
		GunService.Client.RayHit:Fire(shooter, hitPart, pos, normal, mat, hitHumanoid)
	end

	if bullet and bullet.Destroy then
		bullet:Destroy()
	end
end)

Caster.CastTerminating:Connect(function(cast)
	local bullet = cast.RayInfo and cast.RayInfo.CosmeticBulletObject
	if bullet and bullet.Destroy then
		bullet:Destroy()
	end
end)

function GunService:KnitStart()
	self.Client.FireGunSignal:Connect(function(player: Player, origin: Vector3, direction: Vector3)
		if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
		if direction.Magnitude < 0.001 then return end

		local ignore = buildIgnoreListForPlayer(player)
		local behavior = newBehavior(ignore)

		local userData = { player = player }
		Caster:Fire(origin, direction.Unit, BULLET_SPEED, behavior, userData)

		-- Quick muzzle flash (spawn & destroy)
		local flash = Instance.new("PointLight")
		flash.Brightness = 5
		flash.Range = 12
		flash.Shadows = false

		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = origin
		attachment.Parent = workspace.Terrain
		flash.Parent = attachment

		flash.Enabled = true
		task.delay(0.05, function()
			attachment:Destroy()
		end)
	end)
end

return GunService
