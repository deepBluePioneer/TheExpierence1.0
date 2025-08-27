-- Server/Services/IKHammerPoseService.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local IKHammerPoseService = Knit.CreateService {
	Name = "IKHammerPoseService",
	Client = {},
}

-- ==== Helpers ====

local function isR15(character: Model): boolean
	return character:FindFirstChild("RightHand") ~= nil
end

local function getArmParts(character: Model, side: "Left" | "Right")
	if isR15(character) then
		return character:FindFirstChild(side .. "UpperArm"), character:FindFirstChild(side .. "Hand")
	else
		return character:FindFirstChild("Torso"), character:FindFirstChild(side .. " Arm")
	end
end

local function ensureAttachment(parent: Instance, name: string, cframe: CFrame): Attachment
	local a = parent:FindFirstChild(name)
	if not a then
		a = Instance.new("Attachment")
		a.Name = name
		a.Parent = parent
	end
	a.CFrame = cframe
	return a
end

local function applyArmIK(character: Model, side: "Left" | "Right", target: Attachment, pole: Attachment?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local chainRoot, endEffector = getArmParts(character, side)
	if not (humanoid and chainRoot and endEffector) then return end

	local ikName = "IK_" .. side .. "Hand"
	local ik = humanoid:FindFirstChild(ikName)
	if not ik then
		ik = Instance.new("IKControl")
		ik.Name = ikName
		ik.Type = Enum.IKControlType.Position
		ik.ChainRoot = chainRoot
		ik.EndEffector = endEffector
		ik.Parent = humanoid
	end

	ik.Target = target
	ik.Pole = pole or nil
	ik.SmoothTime = 0.06
	ik.Weight = 1
	ik.Priority = 1
	ik.Enabled = true
end

-- ==== Apply batting stance ====

function IKHammerPoseService:ApplyBattingPose(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Updated hand positions based on visual reference
	local rightTarget = ensureAttachment(
		hrp,
		"RightHandTarget",
		CFrame.new(0.45, 1.2, -0.5) * CFrame.Angles(0, 0, math.rad(-15))
	)

	local leftTarget = ensureAttachment(
		hrp,
		"LeftHandTarget",
		CFrame.new(0.25, 1.0, -1.0) * CFrame.Angles(0, 0, math.rad(10))
	)

	-- Elbow poles – right elbow is pulled farther back and out, left elbow gently out
	local rightPole = ensureAttachment(hrp, "RightPole", CFrame.new(1.3, 1.1, -0.3))
	local leftPole  = ensureAttachment(hrp, "LeftPole",  CFrame.new(-0.7, 1.05, -0.7))

	-- Apply IK
	applyArmIK(character, "Right", rightTarget, rightPole)
	applyArmIK(character, "Left",  leftTarget, leftPole)
end


function IKHammerPoseService:ClearBattingPose(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	for _, side in { "Left", "Right" } do
		local ik = humanoid:FindFirstChild("IK_" .. side .. "Hand")
		if ik then ik:Destroy() end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local t = hrp:FindFirstChild(side .. "HandTarget")
			local p = hrp:FindFirstChild(side .. "Pole")
			if t then t:Destroy() end
			if p then p:Destroy() end
		end
	end
end

-- ==== Knit Lifecycle ====

function IKHammerPoseService:KnitStart()
	local Players = game:GetService("Players")

	-- 🧪 Auto-apply batting pose for testing
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			--task.wait(1)
			--self:ApplyBattingPose(character)
		end)
	end)
end

function IKHammerPoseService:KnitInit() end

return IKHammerPoseService
