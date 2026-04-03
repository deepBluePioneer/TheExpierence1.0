local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local Signal = require(Packages.Signal)

local LocalPlayer = Players.LocalPlayer

local GRAVITY_FORCE = 40

local GraviBowGravityController = Knit.CreateController({
	Name = "GraviBowGravityController",

	GravityDirection = Vector3.new(0, -1, 0),
	GravityChanged = Signal.new(),

	_trove = nil,
	_characterTrove = nil,
	_sphereCenter = Vector3.zero,
	_cachedMass = 0,
})

function GraviBowGravityController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowGravityController:KnitStart()
	local sphere = Workspace:WaitForChild("sphere", 30)
	if not sphere then
		warn("[GraviBowGravityController] Could not find Workspace.sphere")
		return
	end

	self._sphere = sphere
	self:_updateSphereCenter()

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(character)
	end), "Disconnect")

	if LocalPlayer.Character then
		self:_onCharacterAdded(LocalPlayer.Character)
	end

	print("[GraviBowGravityController] Started -- targeting sphere at " .. tostring(self._sphereCenter))
end

function GraviBowGravityController:GetSphereCenter()
	return self._sphereCenter
end

function GraviBowGravityController:_updateSphereCenter()
	local sphere = self._sphere
	if not sphere then return end

	if sphere:IsA("Model") and sphere.PrimaryPart then
		self._sphereCenter = sphere.PrimaryPart.Position
	elseif sphere:IsA("BasePart") then
		self._sphereCenter = sphere.Position
	else
		local rootPart = sphere:FindFirstChildWhichIsA("BasePart")
		if rootPart then
			self._sphereCenter = rootPart.Position
		end
	end
end

function GraviBowGravityController:GetSphereRadius()
	local sphere = self._sphere
	if not sphere then return 100 end

	local part = nil
	if sphere:IsA("Model") and sphere.PrimaryPart then
		part = sphere.PrimaryPart
	elseif sphere:IsA("BasePart") then
		part = sphere
	else
		part = sphere:FindFirstChildWhichIsA("BasePart")
	end
	if part then
		return math.max(part.Size.X, part.Size.Y, part.Size.Z) / 2
	end
	return 100
end

function GraviBowGravityController:_onCharacterAdded(character)
	if self._characterTrove then
		self._characterTrove:Clean()
	end
	self._characterTrove = self._trove:Extend()

	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	local vectorForce = hrp:WaitForChild("GravityForce", 10)
	if not vectorForce then
		warn("[GraviBowGravityController] Missing GravityForce on HumanoidRootPart")
		return
	end

	self._cachedMass = 0
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			self._cachedMass += part:GetMass()
		end
	end

	self:_teleportToSurface(hrp)

	self._characterTrove:Add(RunService.Heartbeat:Connect(function(_dt)
		self:_updateGravity(hrp, vectorForce)
	end), "Disconnect")

	print("[GraviBowGravityController] Character connected to gravity loop")
end

function GraviBowGravityController:_teleportToSurface(hrp)
	self:_updateSphereCenter()
	local center = self._sphereCenter
	local radius = self:GetSphereRadius()

	local upDir = Vector3.new(0, 1, 0)
	local surfacePos = center + upDir * (radius + 5)
	local lookDir = upDir:Cross(Vector3.new(0, 0, 1))
	if lookDir.Magnitude < 0.01 then
		lookDir = upDir:Cross(Vector3.new(1, 0, 0))
	end
	lookDir = lookDir.Unit

	local spawnCF = CFrame.lookAt(surfacePos, surfacePos + lookDir, upDir)
	hrp.CFrame = spawnCF
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
end

function GraviBowGravityController:_updateGravity(hrp, vectorForce)
	self:_updateSphereCenter()

	local playerPos = hrp.Position
	local toCenter = self._sphereCenter - playerPos
	if toCenter.Magnitude < 0.001 then return end

	local gravityDir = toCenter.Unit
	self.GravityDirection = gravityDir
	self.GravityChanged:Fire(gravityDir)

	vectorForce.Force = gravityDir * GRAVITY_FORCE * self._cachedMass
end

return GraviBowGravityController
