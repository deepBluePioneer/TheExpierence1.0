local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PatchLookController = Knit.CreateController { Name = "PatchLookController" }

local patches = {}

-- Add only unique patch
local function addPatch(patch)
	if not patch:IsA("BasePart") then return end
	for _, p in ipairs(patches) do
		if p == patch then return end
	end
	table.insert(patches, patch)
end

-- Remove patch if it gets untagged
local function removePatch(patch)
	for i, p in ipairs(patches) do
		if p == patch then
			table.remove(patches, i)
			break
		end
	end
end

function test()

		local Camera = Workspace.CurrentCamera

	wait(5)
	-- Initial tag scan (may miss server-spawned parts if too early)
	for _, patch in ipairs(CollectionService:GetTagged("powerupPatch")) do
		print("ADDED TO COLLECTION")
		print(patch.Name)
		addPatch(patch)
	end



	-- Rotate toward camera
	RunService.RenderStepped:Connect(function()
		if not Camera then return end
		local camPos = Camera.CFrame.Position

		for _, patch in ipairs(patches) do
			if patch:IsDescendantOf(Workspace) and patch:IsA("BasePart") then
				local pos = patch.Position
				local flatCam = Vector3.new(camPos.X, pos.Y, camPos.Z)
				
				-- Calculate just the facing rotation
				local lookVector = (flatCam - pos).Unit
				local yAngle = math.atan2(-lookVector.X, -lookVector.Z) -- Y-axis rotation only

				-- Preserve current position and apply new Y-axis rotation
				patch.CFrame = CFrame.new(pos) * CFrame.Angles(0, yAngle, 0)
			end
		end
	end)
	
end

function PatchLookController:KnitStart()





end

function PatchLookController:KnitInit() end

return PatchLookController
