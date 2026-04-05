local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local LocalPlayer = Players.LocalPlayer

local JETPACK_THRUST = 60
local PARTICLE_RATE = 80
local PARTICLE_LIFETIME_MIN = 0.3
local PARTICLE_LIFETIME_MAX = 0.6
local PARTICLE_SPEED_MIN = 8
local PARTICLE_SPEED_MAX = 15

local GraviBowJetpackController = Knit.CreateController({
	Name = "GraviBowJetpackController",

	_active = false,
	_thrusting = false,
	_trove = nil,
	_characterTrove = nil,
	_thrustForce = nil,
	_cachedMass = 0,
	_emitter = nil,
	_backVisual = nil,
})

function GraviBowJetpackController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowJetpackController:KnitStart()
	self._gravityController = Knit.GetController("GraviBowGravityController")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end
end

function GraviBowJetpackController:Activate()
	self._active = true
	self:_attachVisual()
end

function GraviBowJetpackController:Deactivate()
	self._active = false
	self._thrusting = false
	if self._thrustForce then
		self._thrustForce.Force = Vector3.zero
	end
	if self._emitter then
		self._emitter.Rate = 0
	end
	self:_detachVisual()
end

function GraviBowJetpackController:IsActive()
	return self._active
end

function GraviBowJetpackController:IsThrusting()
	return self._active and self._thrusting
end

function GraviBowJetpackController:_attachVisual()
	self:_detachVisual()

	local character = LocalPlayer.Character
	if not character then return end

	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if not backpack then return end

	local jetpackTool
	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") and child.Name:lower() == "jetpack" then
			jetpackTool = child
			break
		end
	end
	if not jetpackTool then return end

	local accessory = jetpackTool:FindFirstChildWhichIsA("Accessory")
	if not accessory then return end

	local accHandle = accessory:FindFirstChild("Handle")
	if not accHandle then return end

	local accAttachment = accHandle:FindFirstChild("BodyBackAttachment")
	if not accAttachment then return end

	local upperTorso = character:FindFirstChild("UpperTorso")
	if not upperTorso then
		upperTorso = character:FindFirstChild("Torso")
	end
	if not upperTorso then return end

	local charAttachment = upperTorso:FindFirstChild("BodyBackAttachment")
	if not charAttachment then
		charAttachment = upperTorso:FindFirstChild("BodyFrontAttachment")
	end
	if not charAttachment then return end

	local visual = accHandle:Clone()
	visual.Name = "JetpackBackVisual"
	visual.Anchored = false
	visual.CanCollide = false
	visual.Parent = character

	local weld = Instance.new("Weld")
	weld.Name = "JetpackWeld"
	weld.Part0 = upperTorso
	weld.Part1 = visual
	weld.C0 = charAttachment.CFrame
	weld.C1 = accAttachment.CFrame * CFrame.Angles(0, math.rad(180), 0)
	weld.Parent = visual

	self._backVisual = visual
end

function GraviBowJetpackController:_detachVisual()
	if self._backVisual then
		self._backVisual:Destroy()
		self._backVisual = nil
	end
end

function GraviBowJetpackController:_onCharacterAdded(character)
	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	local centerAttachment = hrp:WaitForChild("CenterAttachment", 10)
	if not centerAttachment then
		warn("[GraviBowJetpackController] Missing CenterAttachment on HumanoidRootPart")
		return
	end

	self._cachedMass = 0
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			self._cachedMass += part:GetMass()
		end
	end

	local thrustForce = Instance.new("VectorForce")
	thrustForce.Name = "JetpackThrust"
	thrustForce.Attachment0 = centerAttachment
	thrustForce.ApplyAtCenterOfMass = true
	thrustForce.Force = Vector3.zero
	thrustForce.RelativeTo = Enum.ActuatorRelativeTo.World
	thrustForce.Parent = character
	self._thrustForce = thrustForce

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "JetpackExhaust"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(PARTICLE_LIFETIME_MIN, PARTICLE_LIFETIME_MAX)
	emitter.Speed = NumberRange.new(PARTICLE_SPEED_MIN, PARTICLE_SPEED_MAX)
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 85, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 100, 100)),
	})
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0.2
	emitter.Parent = hrp
	self._emitter = emitter

	self._characterTrove:Add(RunService.Stepped:Connect(function()
		self:_update()
	end), "Disconnect")

	self._characterTrove:Add(function()
		self._thrustForce = nil
		self._emitter = nil
		self._thrusting = false
		self:_detachVisual()
	end)
end

function GraviBowJetpackController:_update()
	if not self._thrustForce then return end

	if not self._active then
		self._thrustForce.Force = Vector3.zero
		self._thrusting = false
		if self._emitter then
			self._emitter.Rate = 0
		end
		return
	end

	local spaceHeld = UserInputService:IsKeyDown(Enum.KeyCode.Space)
	self._thrusting = spaceHeld

	if spaceHeld then
		local gravityDir = self._gravityController.GravityDirection
		local upDir = -gravityDir
		self._thrustForce.Force = upDir * JETPACK_THRUST * self._cachedMass

		if self._emitter then
			self._emitter.Rate = PARTICLE_RATE
		end
	else
		self._thrustForce.Force = Vector3.zero
		if self._emitter then
			self._emitter.Rate = 0
		end
	end
end

return GraviBowJetpackController
