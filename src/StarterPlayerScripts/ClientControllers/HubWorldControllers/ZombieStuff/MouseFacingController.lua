-- Client/Controllers/MouseFacingController.lua

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local MouseFacingController = Knit.CreateController {
	Name = "MouseFacingController"
}

-- Config
local ROTATION_SEND_INTERVAL = 0.05
local lastSent = 0

-- Local state
local hrp = nil
local facingService = nil

-- Helpers
local function getDirectionToMouse()
	if not hrp then return nil end

	local rayOrigin = Mouse.UnitRay.Origin
	local rayDir = Mouse.UnitRay.Direction

	-- Prevent divide by zero when ray is flat
	if math.abs(rayDir.Y) < 1e-4 then
		return nil
	end

	-- Get intersection with horizontal plane at HumanoidRootPart Y
	local planeY = hrp.Position.Y
	local t = (planeY - rayOrigin.Y) / rayDir.Y
	local targetPos = rayOrigin + rayDir * t
	if not targetPos then return nil end

	-- Direction from HRP to target point (flattened to XZ)
	local dir = Vector3.new(targetPos.X - hrp.Position.X, 0, targetPos.Z - hrp.Position.Z)
	if dir.Magnitude > 0.01 then
		return dir.Unit
	end

	return nil
end

local function rotateCharacterLocally(dir: Vector3)
	if not hrp then return end
	local angle = math.atan2(-dir.X, -dir.Z)
	local rotCFrame = CFrame.Angles(0, angle, 0)
	hrp.CFrame = CFrame.new(hrp.Position) * rotCFrame
end

local function onCharacterAdded(character)
	hrp = character:WaitForChild("HumanoidRootPart", 2)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
	end
end

-- Knit lifecycle
function MouseFacingController:KnitStart()
	facingService = Knit.GetService("FacingService")

	-- Setup for existing character
	if LocalPlayer.Character then
		onCharacterAdded(LocalPlayer.Character)
	end

	-- Hook into character spawn
	LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

	-- Each frame, rotate + optionally sync to server
	RunService.RenderStepped:Connect(function(dt)
		if not hrp then return end

		local dir = getDirectionToMouse()
		if dir then
			-- Instant visual feedback
			rotateCharacterLocally(dir)

			-- Send to server at fixed interval
			local now = tick()
			if now - lastSent >= ROTATION_SEND_INTERVAL then
				lastSent = now
				facingService:UpdateDirection(dir)
			end
		end
	end)
end

return MouseFacingController
