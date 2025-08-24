local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local DisasterEventService = Knit.CreateService {
	Name = "DisasterEventService",
	Client = {},
}

-- Reference to Atmosphere
local Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

-- Store default values
local defaultAtmosphere = {
	Density = Atmosphere and Atmosphere.Density or 0,
	Color = Atmosphere and Atmosphere.Color or Color3.new(1, 1, 1),
	Haze = Atmosphere and Atmosphere.Haze or 0,
}

-- Lerp helper functions
local function lerpNumber(a, b, alpha)
	return a + (b - a) * alpha
end

local function lerpColor(a, b, alpha)
	return Color3.new(
		lerpNumber(a.R, b.R, alpha),
		lerpNumber(a.G, b.G, alpha),
		lerpNumber(a.B, b.B, alpha)
	)
end

-- Tween atmosphere settings
local function tweenAtmosphere(target, duration)
	if not Atmosphere then return end

	local start = {
		Density = Atmosphere.Density,
		Haze = Atmosphere.Haze,
		Color = Atmosphere.Color,
	}

	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local alpha = math.clamp(elapsed / duration, 0, 1)

		Atmosphere.Density = lerpNumber(start.Density, target.Density, alpha)
		Atmosphere.Haze = lerpNumber(start.Haze, target.Haze, alpha)
		Atmosphere.Color = lerpColor(start.Color, target.Color, alpha)

		if alpha >= 1 then
			connection:Disconnect()
		end
	end)
end

-- Trigger fog event
function DisasterEventService:TriggerAtmosphereFog(duration)
	if not Atmosphere then
		warn("No Atmosphere found in Lighting.")
		return
	end

	local target = {
		Density = 0.55,
		Haze = 10,
		Color = Color3.new(1, 1, 1),
	}

	tweenAtmosphere(target, 1.25)

	task.delay(duration, function()
		tweenAtmosphere(defaultAtmosphere, 1.25)
	end)
end

-- Add bounce logic to patches
-- Shared bounce utility
local function ensureAttachment(part)
	local attachment = part:FindFirstChild("BounceAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "BounceAttachment"
		attachment.Parent = part
	end
	return attachment
end

-- Vertical-only bouncing (simple up bounce every time it slows down)
function DisasterEventService:VerticalBouncyPatches()
	local bounced = {}

	RunService.Heartbeat:Connect(function()
		for _, part in ipairs(CollectionService:GetTagged("powerupPatch")) do
			if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
				if not part:GetAttribute("VerticalBounceReady") then
					part:SetAttribute("VerticalBounceReady", true)
					ensureAttachment(part)
				end

				if part.AssemblyLinearVelocity.Magnitude < 0.05 then
					local now = tick()
					if not bounced[part] or now - bounced[part] > 0.3 then
						bounced[part] = now

						local bounce = Instance.new("VectorForce")
						bounce.Name = "VerticalBounceForce"
						bounce.Attachment0 = ensureAttachment(part)
						bounce.RelativeTo = Enum.ActuatorRelativeTo.World
						bounce.ApplyAtCenterOfMass = true

						local mass = part:GetMass()
						bounce.Force = Vector3.new(0, mass * 2000, 0)
						bounce.Parent = part

						task.delay(0.1, function()
							if bounce and bounce.Parent then
								bounce:Destroy()
							end
						end)
					end
				end
			end
		end
	end)
end

-- Directional bounce (after random delay, adds lateral force too)
function DisasterEventService:DirectionalBouncyPatches()
	local bounced = {}

	RunService.Heartbeat:Connect(function()
		for _, part in ipairs(CollectionService:GetTagged("powerupPatch")) do
			if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
				if not part:GetAttribute("DirectionalBounceReady") then
					part:SetAttribute("DirectionalBounceReady", true)
					ensureAttachment(part)
				end

				if part.AssemblyLinearVelocity.Magnitude < 0.05 then
					local now = tick()
					if not bounced[part] or now - bounced[part] > 0.3 then
						bounced[part] = now

						task.delay(math.random(2, 10) / 10, function()
							if not part or not part.Parent then return end

							local bounce = Instance.new("VectorForce")
							bounce.Name = "DirectionalBounceForce"
							bounce.Attachment0 = ensureAttachment(part)
							bounce.RelativeTo = Enum.ActuatorRelativeTo.World
							bounce.ApplyAtCenterOfMass = true

							local mass = part:GetMass()
							local upward = Vector3.new(0, 1, 0)
							local lateral = Vector3.new(
								math.random(-100, 100) / 100,
								0,
								math.random(-100, 100) / 100
							).Unit

							local forceDir = (upward + lateral).Unit
							bounce.Force = forceDir * mass * 2000
							bounce.Parent = part

							task.delay(0.1, function()
								if bounce and bounce.Parent then
									bounce:Destroy()
								end
							end)
						end)
					end
				end
			end
		end
	end)
end


function init()
		task.delay(10, function()
		self:TriggerAtmosphereFog(10)
		--self:VerticalBouncyPatches()       -- Up-only bouncing
		--self:DirectionalBouncyPatches()    -- Lateral impulse bouncing
	end)
end

-- Start event after delay
function DisasterEventService:KnitStart()

end


function DisasterEventService:KnitInit() end

return DisasterEventService
