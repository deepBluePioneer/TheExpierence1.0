local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local machineTag = "machine"

local MachineVisualController = Knit.CreateController { Name = "MachineVisualController" }

local machines = {}

function MachineVisualController:SetupMachine(machine)
	if not machine:IsA("Model") then return end

	local root = machine:FindFirstChild("RootPart")
	if not root or not root:IsA("BasePart") then return end

	-- Make sure it's anchored and not duplicated
	if machines[machine] then return end
	root.Anchored = true

	machines[machine] = {
		RootPart = root,
		BaseY = root.Position.Y,
		TimeOffset = math.random() * 2 * math.pi -- offset for desync
	}
end

function MachineVisualController:KnitStart()
	task.wait(1)

	for _, machine in ipairs(CollectionService:GetTagged(machineTag)) do
		self:SetupMachine(machine)
	end

	CollectionService:GetInstanceAddedSignal(machineTag):Connect(function(machine)
		self:SetupMachine(machine)
	end)

	-- Update loop
	RunService.RenderStepped:Connect(function(dt)
		local t = tick()
		for _, data in pairs(machines) do
			local root = data.RootPart
			local baseY = data.BaseY
			local offset = math.sin(t * 2 + data.TimeOffset) * 0.25 -- 0.5 = amplitude
			local pos = root.Position
			root.Position = Vector3.new(pos.X, baseY + offset, pos.Z)
		end
	end)
end

function MachineVisualController:KnitInit()
	-- Optional init logic
end

return MachineVisualController
