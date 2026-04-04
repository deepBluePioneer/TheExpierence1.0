local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local PLANET_TAG = "planet"
local RING_TILT = 25
local EMITTERS_PER_BAND = 36

local RING_BANDS = {
	{
		name = "Inner",
		radiusMul = 1.25,
		spinSpeed = 60,
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 180, 120)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 150, 80)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 120, 50)),
		}),
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.3, 0.6),
			NumberSequenceKeypoint.new(1, 0.15),
		}),
		rate = 12,
		lightEmission = 0.5,
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.2, 0.1),
			NumberSequenceKeypoint.new(0.7, 0.15),
			NumberSequenceKeypoint.new(1, 0.7),
		}),
	},
	{
		name = "Mid",
		radiusMul = 1.55,
		spinSpeed = 42,
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 210, 110)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(245, 180, 70)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 140, 45)),
		}),
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.3, 1.0),
			NumberSequenceKeypoint.new(1, 0.25),
		}),
		rate = 14,
		lightEmission = 0.65,
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.2, 0.08),
			NumberSequenceKeypoint.new(0.7, 0.12),
			NumberSequenceKeypoint.new(1, 0.75),
		}),
	},
	{
		name = "Outer",
		radiusMul = 1.85,
		spinSpeed = 28,
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 160, 140)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 130, 100)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 110, 80)),
		}),
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.3, 0.7),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		rate = 8,
		lightEmission = 0.4,
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.2, 0.2),
			NumberSequenceKeypoint.new(0.7, 0.25),
			NumberSequenceKeypoint.new(1, 0.8),
		}),
	},
}

local GraviBowRingController = Knit.CreateController({
	Name = "GraviBowRingController",
	_trove = nil,
	_ringData = nil,
})

function GraviBowRingController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowRingController:KnitStart()
	local tagged = CollectionService:GetTagged(PLANET_TAG)
	if #tagged > 0 then
		self:_setupRings(tagged[1])
	else
		local conn
		conn = CollectionService:GetInstanceAddedSignal(PLANET_TAG):Connect(function(instance)
			conn:Disconnect()
			self:_setupRings(instance)
		end)
		self._trove:Add(conn, "Disconnect")
	end

	self._trove:Add(RunService.RenderStepped:Connect(function(dt)
		self:_spinRings(dt)
	end), "Disconnect")
end

function GraviBowRingController:_getPlanetPart(model)
	if model:IsA("BasePart") then
		return model
	end
	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

function GraviBowRingController:_setupRings(model)
	if self._ringData then return end

	local part = self:_getPlanetPart(model)
	if not part then
		task.spawn(function()
			while model.Parent and not self:_getPlanetPart(model) do
				local desc = model.DescendantAdded:Wait()
				if desc:IsA("BasePart") then break end
			end
			if model.Parent and not self._ringData then
				self:_setupRings(model)
			end
		end)
		return
	end

	local center = part.Position
	local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2

	local bands = {}

	for _, band in ipairs(RING_BANDS) do
		local ringRadius = radius * band.radiusMul

		local host = Instance.new("Part")
		host.Name = model.Name .. "_Ring_" .. band.name
		host.Anchored = true
		host.CanCollide = false
		host.CanQuery = false
		host.CanTouch = false
		host.CastShadow = false
		host.Transparency = 1
		host.Size = Vector3.new(1, 1, 1)
		host.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(RING_TILT))
		host.Parent = Workspace

		for i = 0, EMITTERS_PER_BAND - 1 do
			local angle = (i / EMITTERS_PER_BAND) * math.pi * 2
			local x = math.cos(angle) * ringRadius
			local z = math.sin(angle) * ringRadius

			local att = Instance.new("Attachment")
			att.Name = "RingAtt_" .. i
			att.Position = Vector3.new(x, 0, z)
			att.Parent = host

			local emitter = Instance.new("ParticleEmitter")
			emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			emitter.Color = band.color
			emitter.Size = band.size
			emitter.Transparency = band.transparency
			emitter.Lifetime = NumberRange.new(2, 4)
			emitter.Speed = NumberRange.new(0.3, 1.2)
			emitter.Rate = band.rate
			emitter.SpreadAngle = Vector2.new(10, 10)
			emitter.RotSpeed = NumberRange.new(-30, 30)
			emitter.Rotation = NumberRange.new(0, 360)
			emitter.LightEmission = band.lightEmission
			emitter.LightInfluence = 0.3
			emitter.Drag = 1
			emitter.Parent = att
		end

		table.insert(bands, {
			host = host,
			spinSpeed = band.spinSpeed,
		})
	end

	self._ringData = {
		planetPart = part,
		bands = bands,
	}
end

function GraviBowRingController:_spinRings(dt)
	if not self._ringData then return end

	local center = self._ringData.planetPart.Position
	for _, band in ipairs(self._ringData.bands) do
		local host = band.host
		if host and host.Parent then
			local rot = CFrame.Angles(0, math.rad(band.spinSpeed * dt), 0)
			host.CFrame = CFrame.new(center) * (CFrame.new(-center) * host.CFrame) * rot
		end
	end
end

return GraviBowRingController
