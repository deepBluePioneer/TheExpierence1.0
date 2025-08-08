local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")

local DestructionService = Knit.CreateService {
	Name = "DestructionService",
	Client = {},
}

function DestructionService:GetDestructableRootParts()
	local destructableParts = {}

	for _, obj in ipairs(CollectionService:GetTagged("destructable")) do
		local cube = obj:FindFirstChild("Cube")
		if cube then
			local entry = {
				Cube = cube,
				Children = cube:GetChildren(),
			}
			table.insert(destructableParts, entry)
		end
	end

	return destructableParts
end

function DestructionService:GetMachineRootParts()
	local machineParts = {}

	for _, obj in ipairs(CollectionService:GetTagged("machine")) do
		local root = obj:FindFirstChild("RootPart")
		if root then
			table.insert(machineParts, root)
		end
	end

	return machineParts
end

function init()
	local destructables = self:GetDestructableRootParts()
	local machines = self:GetMachineRootParts()

	for _, destructable in ipairs(destructables) do
		local cube = destructable.Cube

		cube.Touched:Connect(function(hit)
			for _, root in ipairs(machines) do
				if hit == root then
					print("Machine RootPart touched destructable Cube!")

					-- Hide the cube
					cube.Transparency = 1
					cube.CanCollide = false

					-- Show and activate children
					for _, child in ipairs(destructable.Children) do
						if child:IsA("BasePart") then
							child.Transparency = 0
							child.CanCollide = true
							child.Anchored = false

							-- Create an attachment
							local attachment = Instance.new("Attachment")
							attachment.Parent = child

							local force = Instance.new("VectorForce")
                            force.Attachment0 = attachment
                            force.RelativeTo = Enum.ActuatorRelativeTo.World
                            force.ApplyAtCenterOfMass = true


							-- Calculate force vector based on root velocity
							local velocity = root.AssemblyLinearVelocity
							local strength = 50 -- you can tweak this
							force.Force = velocity.Unit * strength * child:GetMass()
							force.Parent = child

							-- Remove after short duration
							task.delay(0.2, function()
								force:Destroy()
								attachment:Destroy()
							end)
						end
					end

					break
				end
			end
		end)
	end
end

function DestructionService:KnitStart()
	
end



function DestructionService:KnitInit()
	-- Optional init logic
end

return DestructionService
