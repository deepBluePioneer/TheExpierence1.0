-- Client/Controllers/IKSetupController.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local IKSetupController = Knit.CreateController { Name = "IKSetupController" }

-- Exported target references
local targets = {
	RightTarget = nil,
	RightPole   = nil,
	LeftTarget  = nil,
	LeftPole    = nil,
}

local function createAttachment(name, parent, cframe)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = cframe or CFrame.new()
	attachment.Parent = parent
	return attachment
end

local function setupArmIK(humanoid: Humanoid, root: BasePart, arm: "Right" | "Left")
	local endEffector = humanoid.Parent:FindFirstChild(arm .. "Hand") -- ✅ Now targets the Hand!
	local chainRoot   = humanoid.Parent:FindFirstChild(arm .. "UpperArm")

	if not (endEffector and chainRoot) then
		warn("[IKSetup] Could not find required parts for", arm)
		return
	end

	local targetOffset = CFrame.new((arm == "Right" and 3 or -3), 2, -4)
	local poleOffset   = CFrame.new((arm == "Right" and 3 or -3), 3, -1)

	local targetAttachment = createAttachment(arm .. "HandTarget", root, targetOffset)
	local poleAttachment   = createAttachment(arm .. "HandPole", root, poleOffset)

	local ik = Instance.new("IKControl")
	ik.Name = arm .. "HandIK"
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = chainRoot
	ik.EndEffector = endEffector
	ik.Target = targetAttachment
	ik.Pole = poleAttachment
	ik.SmoothTime = 0.05
	ik.Weight = 1
	ik.Enabled = true
	ik.Parent = humanoid

	if arm == "Right" then
		targets.RightTarget = targetAttachment
		targets.RightPole   = poleAttachment
	else
		targets.LeftTarget = targetAttachment
		targets.LeftPole   = poleAttachment
	end
end

function IKSetupController:GetTargets()
	return targets
end

function IKSetupController:KnitStart()
	local player = Players.LocalPlayer

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid"):WaitForChild("Animator")

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:WaitForChild("HumanoidRootPart")

		setupArmIK(humanoid, rootPart, "Right")
		setupArmIK(humanoid, rootPart, "Left")

		warn("[IKSetup] IKControls initialized for character:", character.Name)
	end)
end

function IKSetupController:KnitInit() end

return IKSetupController
