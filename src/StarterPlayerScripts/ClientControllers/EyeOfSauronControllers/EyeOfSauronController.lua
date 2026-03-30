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

local SCAN_COLOR = Color3.fromRGB(255, 165, 0)
local LOCKED_COLOR = Color3.fromRGB(255, 0, 0)
local BEAM_HALF_ANGLE_RAD = math.rad(2)
local CONE_SUBDIVISIONS = 16
local ANGLE_STEP = (2 * math.pi) / CONE_SUBDIVISIONS
local MAX_BEAM_RANGE = 2000

local EyeOfSauronController = Knit.CreateController({
	Name = "EyeOfSauronController",
})

function EyeOfSauronController:KnitInit()
	self._eyeOrigin = nil
	self._lookTarget = nil
	self._isLockedOn = false
	self._raycastParams = nil
end

function EyeOfSauronController:KnitStart()
	local eyeModel = Workspace:WaitForChild("eye", 15)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = eyeModel and { eyeModel } or {}
	self._raycastParams = params

	local eyeService = Knit.GetService("EyeOfSauronService")
	eyeService.EyeUpdate:Connect(function(eyeOrigin, lookTarget, isLockedOn)
		self._eyeOrigin = eyeOrigin
		self._lookTarget = lookTarget
		self._isLockedOn = isLockedOn
	end)

	if Gizmo then
		local hitPoints = table.create(CONE_SUBDIVISIONS)
		local tanHalf = math.tan(BEAM_HALF_ANGLE_RAD)

		RunService.RenderStepped:Connect(function()
			if not self._lookTarget or not self._eyeOrigin then return end

			local color = self._isLockedOn and LOCKED_COLOR or SCAN_COLOR
			Gizmo.PushProperty("AlwaysOnTop", true)
			Gizmo.PushProperty("Color3", color)

			local beamCF = CFrame.lookAt(self._eyeOrigin, self._lookTarget)
			local beamDir = beamCF.LookVector
			local beamRight = beamCF.RightVector
			local beamUp = beamCF.UpVector

			local centerVec = beamDir * MAX_BEAM_RANGE
			local centerHit = Workspace:Raycast(self._eyeOrigin, centerVec, self._raycastParams)
			local edgeRange = centerHit and (centerHit.Position - self._eyeOrigin).Magnitude or MAX_BEAM_RANGE

			for i = 0, CONE_SUBDIVISIONS - 1 do
				local theta = i * ANGLE_STEP
				local perpOffset = beamRight * math.cos(theta) + beamUp * math.sin(theta)
				local rayDir = (beamDir + perpOffset * tanHalf).Unit
				local rayVec = rayDir * MAX_BEAM_RANGE

				local result = Workspace:Raycast(self._eyeOrigin, rayVec, self._raycastParams)
				hitPoints[i + 1] = result and result.Position or (self._eyeOrigin + rayDir * edgeRange)
			end

			for i = 1, CONE_SUBDIVISIONS do
				Gizmo.Ray:Draw(self._eyeOrigin, hitPoints[i])
				local next = (i % CONE_SUBDIVISIONS) + 1
				Gizmo.Ray:Draw(hitPoints[i], hitPoints[next])
			end
		end)
	end

	print("[EyeOfSauronController] Eye of Sauron visuals active")
end

return EyeOfSauronController
