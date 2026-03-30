local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local Gizmo
local ok, mod = pcall(require, Packages.imgizmo)
if ok then
	Gizmo = mod
	Gizmo.Init()
end

local RAY_LENGTH = 40

local DIR_COLORS = {
	Forward  = Color3.fromRGB(0, 255, 0),
	Backward = Color3.fromRGB(255, 0, 0),
	Left     = Color3.fromRGB(0, 120, 255),
	Right    = Color3.fromRGB(255, 255, 0),
}

local THRESHOLD = 0.5

local PacManDebugController = Knit.CreateController({
	Name = "PacManDebugController",

	_lastOrigin = nil,
})

function PacManDebugController:KnitInit() end

function PacManDebugController:_getDirectionColor(lookVector)
	local x = lookVector.X
	local z = lookVector.Z

	if math.abs(z) > math.abs(x) then
		if z < 0 then
			return DIR_COLORS.Forward
		else
			return DIR_COLORS.Backward
		end
	else
		if x > 0 then
			return DIR_COLORS.Right
		else
			return DIR_COLORS.Left
		end
	end
end

function PacManDebugController:KnitStart()
	if not Gizmo then return end

	RunService.RenderStepped:Connect(function()
		local pacman = Workspace:FindFirstChild("PacMan")
		if not pacman then return end

		local anchor = nil
		if pacman:IsA("Model") and pacman.PrimaryPart then
			anchor = pacman.PrimaryPart
		else
			anchor = pacman:FindFirstChildWhichIsA("BasePart", true)
		end
		if not anchor then return end

		local origin = anchor.Position
		local forward = anchor.CFrame.LookVector
		local color = self:_getDirectionColor(forward)

		Gizmo.PushProperty("AlwaysOnTop", true)
		Gizmo.PushProperty("Color3", color)
		Gizmo.Ray:Draw(origin, origin + forward * RAY_LENGTH)
	end)

	print("[PacManDebugController] Direction ray active")
end

return PacManDebugController
