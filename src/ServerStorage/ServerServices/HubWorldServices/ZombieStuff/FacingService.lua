-- Services/FacingService.lua

local Players = game:GetService("Players")
local Knit = require(game:GetService("ReplicatedStorage").Packages.Knit)

local FacingService = Knit.CreateService {
	Name = "FacingService",
	Client = {}
}

local RATE_LIMIT = 0.05
local lastUpdate = {}

function FacingService:UpdateDirection(player, dir: Vector3)
	if dir.Magnitude == 0 then return end

	local now = tick()
	if lastUpdate[player] and now - lastUpdate[player] < RATE_LIMIT then return end
	lastUpdate[player] = now

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	--hum.AutoRotate = false

	local angle = math.atan2(-dir.X, -dir.Z)
	--hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, angle, 0)
end

function FacingService.Client:UpdateDirection(player, dir)
	self.Server:UpdateDirection(player, dir)
end

return FacingService
