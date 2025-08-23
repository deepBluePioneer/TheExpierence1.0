local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local IKController = Knit.CreateController { Name = "IKController" }

local function setupDrivingIK(character: Model, seat: Seat)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Create attachments for the left and right hand targets
	local function createHandTarget(name: string, offset: Vector3)
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = offset
		attachment.Parent = seat
		return attachment
	end

	local leftTarget = createHandTarget("LeftHandTarget", Vector3.new(-0.5, 1, -1))
	local rightTarget = createHandTarget("RightHandTarget", Vector3.new(0.5, 1, -1))

	-- Create IKControl for a hand
	local function createIKControl(name: string, endEffectorName: string, chainRootName: string, target: Attachment)
		local ik = Instance.new("IKControl")
		ik.Name = name
		ik.Type = Enum.IKControlType.Transform
		ik.EndEffector = character:FindFirstChild(endEffectorName)
		ik.ChainRoot = character:FindFirstChild(chainRootName)
		ik.Target = target
		ik.Weight = 1
		ik.Priority = 1 -- optional
		ik.Parent = humanoid
	end

	createIKControl("LeftHandIK", "LeftHand", "LeftUpperArm", leftTarget)
	createIKControl("RightHandIK", "RightHand", "RightUpperArm", rightTarget)

	-- Setup torso twisting (R15: Waist is under UpperTorso)
	local upperTorso = character:FindFirstChild("UpperTorso")
	local waistMotor = upperTorso and upperTorso:FindFirstChild("Waist")

	if waistMotor and waistMotor:IsA("Motor6D") then
		local twistAngle = 0

		local originalC0 = waistMotor.C0

        RunService:BindToRenderStep("TorsoTwist", Enum.RenderPriority.Character.Value, function()
            local twistTarget = 0
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                twistTarget = math.rad(-45)
            elseif UserInputService:IsKeyDown(Enum.KeyCode.A) then
                twistTarget = math.rad(45)
            end

            twistAngle = twistAngle + (twistTarget - twistAngle) * 0.15

            -- Rotate torso by modifying C0 instead of Transform
            waistMotor.C0 = originalC0 * CFrame.Angles(0, twistAngle, 0)
        end)


		-- Cleanup on seat exit
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			if not seat.Occupant or seat.Occupant.Parent ~= character then
				RunService:UnbindFromRenderStep("TorsoTwist")
				waistMotor.Transform = CFrame.new()
			end
		end)
	end
end

local function setupMachine(machine: Model)
	local seat = machine:FindFirstChildWhichIsA("Seat", true)
	if not seat then return end

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		if humanoid and humanoid.Parent == LocalPlayer.Character then
			setupDrivingIK(LocalPlayer.Character, seat)
		end
	end)
end

function IKController:initIk()
	task.wait(5)
	local machines = CollectionService:GetTagged("machine")
	for _, machine in ipairs(machines) do
		if machine:IsDescendantOf(workspace) then
			setupMachine(machine)
		end
	end
end

function IKController:KnitStart()
	
end

function IKController:KnitInit()
	-- Nothing for now
end

return IKController
