-- Client/Controllers/IKPoseController.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local IKPoseController = Knit.CreateController { Name = "IKPoseController" }

local RightTarget = Vector3.zero
local RightPole = Vector3.zero
local LeftTarget = Vector3.zero
local LeftPole = Vector3.zero

function IKPoseController:KnitStart()

   
	local TerminalGUI = Knit.GetController("TerminalGUITestController")

	local function updateVec3(ref, axis, value)
		if axis == "X" then return Vector3.new(value, ref.Y, ref.Z)
		elseif axis == "Y" then return Vector3.new(ref.X, value, ref.Z)
		elseif axis == "Z" then return Vector3.new(ref.X, ref.Y, value)
		end
		return ref
	end

	TerminalGUI.Signals.RightHandTargetChanged:Connect(function(axis, value)
		RightTarget = updateVec3(RightTarget, axis, value)
		print(("[IKPose] Right Target %s → %.2f | Current: %s"):format(axis, value, tostring(RightTarget)))
	end)

	TerminalGUI.Signals.RightHandPoleChanged:Connect(function(axis, value)
		RightPole = updateVec3(RightPole, axis, value)
		print(("[IKPose] Right Pole %s → %.2f | Current: %s"):format(axis, value, tostring(RightPole)))
	end)

	TerminalGUI.Signals.LeftHandTargetChanged:Connect(function(axis, value)
		LeftTarget = updateVec3(LeftTarget, axis, value)
		print(("[IKPose] Left Target %s → %.2f | Current: %s"):format(axis, value, tostring(LeftTarget)))
	end)

	TerminalGUI.Signals.LeftHandPoleChanged:Connect(function(axis, value)
		LeftPole = updateVec3(LeftPole, axis, value)
		print(("[IKPose] Left Pole %s → %.2f | Current: %s"):format(axis, value, tostring(LeftPole)))
	end)
end

function IKPoseController:KnitInit() end

return IKPoseController
