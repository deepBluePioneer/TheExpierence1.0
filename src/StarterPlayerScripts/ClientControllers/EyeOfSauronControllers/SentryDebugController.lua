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

local SPOTLIGHT_ANGLE = 35
local SPOTLIGHT_RANGE = 60
local CONE_SUBDIVISIONS = 16
local CONE_COLOR = Color3.fromRGB(255, 120, 40)
local DETECTION_RAY_COLOR = Color3.fromRGB(255, 40, 40)

local SentryDebugController = Knit.CreateController({
	Name = "SentryDebugController",
})

function SentryDebugController:KnitInit()
	self._sentryFolder = nil
end

function SentryDebugController:KnitStart()
	if not Gizmo then return end

	self._sentryFolder = Workspace:WaitForChild("Sentries", 15)
	if not self._sentryFolder then
		warn("[SentryDebugController] No Sentries folder found")
		return
	end

	local coneRadius = math.tan(math.rad(SPOTLIGHT_ANGLE / 2)) * SPOTLIGHT_RANGE

	RunService.RenderStepped:Connect(function()
		for _, sentry in ipairs(self._sentryFolder:GetChildren()) do
			if not sentry:IsA("BasePart") then continue end

			local pos = sentry.Position
			local midpoint = pos - Vector3.new(0, SPOTLIGHT_RANGE / 2, 0)
			local coneCF = CFrame.new(midpoint) * CFrame.Angles(math.rad(90), 0, 0)

			Gizmo.PushProperty("AlwaysOnTop", false)
			Gizmo.PushProperty("Color3", CONE_COLOR)
			Gizmo.Cone:Draw(coneCF, coneRadius, SPOTLIGHT_RANGE, CONE_SUBDIVISIONS)

			Gizmo.PushProperty("Color3", DETECTION_RAY_COLOR)
			Gizmo.Ray:Draw(pos, pos - Vector3.new(0, SPOTLIGHT_RANGE, 0))
		end
	end)

	print("[SentryDebugController] Sentry cone debug visuals active")
end

return SentryDebugController
