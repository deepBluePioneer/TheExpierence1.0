local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local PLANET_TAG = "planet"

local SURFACE_EMITTER_COUNT = 24
local SURFACE_PARTICLE_RATE = 3
local SURFACE_PARTICLE_LIFETIME = NumberRange.new(3, 6)
local SURFACE_PARTICLE_SPEED = NumberRange.new(0.2, 1.0)
local SURFACE_PARTICLE_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.2, 1.5),
	NumberSequenceKeypoint.new(0.8, 1.2),
	NumberSequenceKeypoint.new(1, 0),
})
local SURFACE_PARTICLE_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.15, 0.5),
	NumberSequenceKeypoint.new(0.7, 0.6),
	NumberSequenceKeypoint.new(1, 1),
})
local SURFACE_PARTICLE_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 210, 230)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 180, 220)),
})

local SPACE_DUST_RATE = 8
local SPACE_DUST_LIFETIME = NumberRange.new(4, 8)
local SPACE_DUST_SPEED = NumberRange.new(0.1, 0.6)
local SPACE_DUST_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.3, 0.6),
	NumberSequenceKeypoint.new(0.7, 0.5),
	NumberSequenceKeypoint.new(1, 0),
})
local SPACE_DUST_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.6),
	NumberSequenceKeypoint.new(0.8, 0.65),
	NumberSequenceKeypoint.new(1, 1),
})
local SPACE_DUST_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 190, 220)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 200, 240)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 170, 200)),
})

local LANDING_PUFF_COUNT = 12
local LANDING_PUFF_SPEED = NumberRange.new(4, 10)
local LANDING_PUFF_LIFETIME = NumberRange.new(0.3, 0.7)
local LANDING_PUFF_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.3),
	NumberSequenceKeypoint.new(0.4, 0.8),
	NumberSequenceKeypoint.new(1, 0.1),
})
local LANDING_PUFF_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.3),
	NumberSequenceKeypoint.new(0.5, 0.6),
	NumberSequenceKeypoint.new(1, 1),
})

local FOOTSTEP_RATE = 6
local FOOTSTEP_LIFETIME = NumberRange.new(0.4, 0.8)
local FOOTSTEP_SPEED = NumberRange.new(1, 3)
local FOOTSTEP_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.5, 0.35),
	NumberSequenceKeypoint.new(1, 0),
})
local FOOTSTEP_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.4),
	NumberSequenceKeypoint.new(0.6, 0.7),
	NumberSequenceKeypoint.new(1, 1),
})

local GraviBowEnvironmentController = Knit.CreateController({
	Name = "GraviBowEnvironmentController",

	_trove = nil,
	_characterTrove = nil,
	_planetVisuals = {},
	_spaceDustPart = nil,
	_footstepEmitter = nil,
	_landingEmitter = nil,
	_wasGrounded = true,
	_wasRunning = false,
})

function GraviBowEnvironmentController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowEnvironmentController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")
	self._groundController = Knit.GetController("GraviBowGroundController")
	self._characterController = Knit.GetController("GraviBowCharacterController")

	for _, instance in ipairs(CollectionService:GetTagged(PLANET_TAG)) do
		self:_setupPlanetVisuals(instance)
	end

	self._trove:Add(CollectionService:GetInstanceAddedSignal(PLANET_TAG):Connect(function(instance)
		self:_setupPlanetVisuals(instance)
	end), "Disconnect")

	self._trove:Add(CollectionService:GetInstanceRemovedSignal(PLANET_TAG):Connect(function(instance)
		self:_removePlanetVisuals(instance)
	end), "Disconnect")

	self:_createSpaceDust()

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end

	self._trove:Add(RunService.RenderStepped:Connect(function(dt)
		self:_update(dt)
	end), "Disconnect")
end

function GraviBowEnvironmentController:_getPlanetPart(model)
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

function GraviBowEnvironmentController:_setupPlanetVisuals(model)
	if self._planetVisuals[model] then return end

	local part = self:_getPlanetPart(model)
	if not part then
		task.spawn(function()
			while model.Parent and not self:_getPlanetPart(model) do
				local desc = model.DescendantAdded:Wait()
				if desc:IsA("BasePart") then break end
			end
			if model.Parent and not self._planetVisuals[model] then
				self:_setupPlanetVisuals(model)
			end
		end)
		return
	end

	local center = part.Position
	local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2
	local visuals = { parts = {} }

	local surfaceHost = Instance.new("Part")
	surfaceHost.Name = model.Name .. "_SurfaceParticles"
	surfaceHost.Anchored = true
	surfaceHost.CanCollide = false
	surfaceHost.CanQuery = false
	surfaceHost.CanTouch = false
	surfaceHost.CastShadow = false
	surfaceHost.Transparency = 1
	surfaceHost.Size = Vector3.new(1, 1, 1)
	surfaceHost.Position = center
	surfaceHost.Parent = Workspace
	table.insert(visuals.parts, surfaceHost)

	for i = 0, SURFACE_EMITTER_COUNT - 1 do
		local phi = math.acos(1 - 2 * (i + 0.5) / SURFACE_EMITTER_COUNT)
		local theta = math.pi * (1 + math.sqrt(5)) * i

		local x = math.sin(phi) * math.cos(theta)
		local y = math.cos(phi)
		local z = math.sin(phi) * math.sin(theta)

		local att = Instance.new("Attachment")
		att.Name = "SurfaceAtt_" .. i
		att.Position = Vector3.new(x, y, z) * (radius + 2)
		att.Parent = surfaceHost

		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = SURFACE_PARTICLE_COLOR
		emitter.Size = SURFACE_PARTICLE_SIZE
		emitter.Transparency = SURFACE_PARTICLE_TRANSPARENCY
		emitter.Lifetime = SURFACE_PARTICLE_LIFETIME
		emitter.Speed = SURFACE_PARTICLE_SPEED
		emitter.Rate = SURFACE_PARTICLE_RATE
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.RotSpeed = NumberRange.new(-20, 20)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.LightEmission = 0.4
		emitter.LightInfluence = 0.5
		emitter.Drag = 2
		emitter.Parent = att
	end

	visuals.planetPart = part
	self._planetVisuals[model] = visuals
end

function GraviBowEnvironmentController:_removePlanetVisuals(model)
	local visuals = self._planetVisuals[model]
	if not visuals then return end

	for _, p in ipairs(visuals.parts) do
		if p and p.Parent then
			p:Destroy()
		end
	end

	self._planetVisuals[model] = nil
end

function GraviBowEnvironmentController:_createSpaceDust()
	local dustPart = Instance.new("Part")
	dustPart.Name = "SpaceDust"
	dustPart.Anchored = true
	dustPart.CanCollide = false
	dustPart.CanQuery = false
	dustPart.CanTouch = false
	dustPart.CastShadow = false
	dustPart.Transparency = 1
	dustPart.Size = Vector3.new(1, 1, 1)
	dustPart.Parent = Workspace
	self._trove:Add(dustPart)
	self._spaceDustPart = dustPart

	local att = Instance.new("Attachment")
	att.Parent = dustPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = SPACE_DUST_COLOR
	emitter.Size = SPACE_DUST_SIZE
	emitter.Transparency = SPACE_DUST_TRANSPARENCY
	emitter.Lifetime = SPACE_DUST_LIFETIME
	emitter.Speed = SPACE_DUST_SPEED
	emitter.Rate = SPACE_DUST_RATE
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.RotSpeed = NumberRange.new(-10, 10)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.LightEmission = 0.3
	emitter.LightInfluence = 0.2
	emitter.Drag = 0.5
	emitter.Parent = att
end

function GraviBowEnvironmentController:_onCharacterAdded(character)
	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()
	self._wasGrounded = true
	self._wasRunning = false

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	local footAtt = Instance.new("Attachment")
	footAtt.Name = "FootstepAtt"
	footAtt.Position = Vector3.new(0, -2.5, 0)
	footAtt.Parent = hrp
	self._characterTrove:Add(footAtt)

	local footEmitter = Instance.new("ParticleEmitter")
	footEmitter.Name = "FootstepDust"
	footEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	footEmitter.Color = ColorSequence.new(Color3.fromRGB(170, 160, 140))
	footEmitter.Size = FOOTSTEP_SIZE
	footEmitter.Transparency = FOOTSTEP_TRANSPARENCY
	footEmitter.Lifetime = FOOTSTEP_LIFETIME
	footEmitter.Speed = FOOTSTEP_SPEED
	footEmitter.Rate = 0
	footEmitter.SpreadAngle = Vector2.new(60, 60)
	footEmitter.RotSpeed = NumberRange.new(-30, 30)
	footEmitter.Rotation = NumberRange.new(0, 360)
	footEmitter.LightEmission = 0
	footEmitter.LightInfluence = 1
	footEmitter.Drag = 3
	footEmitter.Parent = footAtt
	self._characterTrove:Add(footEmitter)
	self._footstepEmitter = footEmitter

	local landAtt = Instance.new("Attachment")
	landAtt.Name = "LandingAtt"
	landAtt.Position = Vector3.new(0, -2.5, 0)
	landAtt.Parent = hrp
	self._characterTrove:Add(landAtt)

	local landEmitter = Instance.new("ParticleEmitter")
	landEmitter.Name = "LandingPuff"
	landEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	landEmitter.Color = ColorSequence.new(Color3.fromRGB(180, 170, 150))
	landEmitter.Size = LANDING_PUFF_SIZE
	landEmitter.Transparency = LANDING_PUFF_TRANSPARENCY
	landEmitter.Lifetime = LANDING_PUFF_LIFETIME
	landEmitter.Speed = LANDING_PUFF_SPEED
	landEmitter.Rate = 0
	landEmitter.SpreadAngle = Vector2.new(80, 80)
	landEmitter.RotSpeed = NumberRange.new(-40, 40)
	landEmitter.Rotation = NumberRange.new(0, 360)
	landEmitter.LightEmission = 0
	landEmitter.LightInfluence = 1
	landEmitter.Drag = 4
	landEmitter.Parent = landAtt
	self._characterTrove:Add(landEmitter)
	self._landingEmitter = landEmitter
end

function GraviBowEnvironmentController:_update(dt)
	self:_updateSpaceDust()
	self:_updateFootstepDust()
	self:_updateLandingPuff()
end

function GraviBowEnvironmentController:_updateSpaceDust()
	if not self._spaceDustPart then return end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	self._spaceDustPart.Position = camera.CFrame.Position + camera.CFrame.LookVector * 40
end

function GraviBowEnvironmentController:_updateFootstepDust()
	if not self._footstepEmitter then return end

	local isGrounded = self._groundController.IsGrounded
	local state = self._characterController.State
	local isRunning = isGrounded and (state == "Running")

	if isRunning then
		self._footstepEmitter.Rate = FOOTSTEP_RATE
	else
		self._footstepEmitter.Rate = 0
	end

	self._wasRunning = isRunning
end

function GraviBowEnvironmentController:_updateLandingPuff()
	if not self._landingEmitter then return end

	local isGrounded = self._groundController.IsGrounded

	if isGrounded and not self._wasGrounded then
		self._landingEmitter:Emit(LANDING_PUFF_COUNT)
	end

	self._wasGrounded = isGrounded
end

return GraviBowEnvironmentController
