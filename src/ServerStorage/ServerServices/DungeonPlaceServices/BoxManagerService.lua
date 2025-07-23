local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local CollectionService = game:GetService("CollectionService")

local BoxManagerService = Knit.CreateService {
    Name = "BoxManagerService",
    Client = {},
}

-- Generate a random walk crack on a given face of the box
function BoxManagerService:CreateCrackOnFace(box, faceNormal, faceSize)
	local stepCount = 20 -- More steps = longer cracks
	local stepSize = faceSize * 1.5 / stepCount -- Increase step range

	local origin = box.Position + (box.CFrame:VectorToWorldSpace(faceNormal) * (box.Size / 2))
	local basis = box.CFrame:VectorToWorldSpace(Vector3.new(1, 0, 0)) -- right
	local up = box.CFrame:VectorToWorldSpace(Vector3.new(0, 1, 0))   -- up

	local lastPosition = origin
	for i = 1, stepCount do
		local offset = (basis * math.random(-2, 2) + up * math.random(-2, 2)) * math.min(stepSize.X, stepSize.Y, stepSize.Z)
		local nextPosition = lastPosition + offset

		local crackPart = Instance.new("Part")
		crackPart.Anchored = true
		crackPart.CanCollide = false
		crackPart.Size = Vector3.new(0.6, 0.6, (nextPosition - lastPosition).Magnitude + 1.0) -- Wider + longer segments
		crackPart.CFrame = CFrame.lookAt(lastPosition, nextPosition) * CFrame.new(0, 0, -crackPart.Size.Z / 2)
		crackPart.Color = Color3.new(0, 0, 0)
		crackPart.Material = Enum.Material.Neon
		crackPart.Parent = box

		lastPosition = nextPosition
	end
end



-- Create a physics-enabled box and handle machine collisions
function BoxManagerService:CreateBox(position)
	local box = Instance.new("Part")
	box.Name = "TriggerBox"
	box.Size = Vector3.new(20, 20, 20)
	box.Anchored = false
	box.CanCollide = true
	box.Transparency = 0
	box.Color = Color3.fromRGB(59, 59, 184)
	box.Position = position or Vector3.new(0, 5, 0)
	box.Parent = Workspace

	local alreadyTriggered = false

	box.Touched:Connect(function(hit)
		if alreadyTriggered then return end

		if hit.Name == "RootPart" then
			local model = hit:FindFirstAncestorOfClass("Model")
			if model and CollectionService:HasTag(model, "machine") then
				alreadyTriggered = true
				print(model.Name, "touched the box!")

				-- Define normals for all 6 faces of the box
				local faceNormals = {
					Vector3.new(0, 1, 0),   -- Top
					Vector3.new(0, -1, 0),  -- Bottom
					Vector3.new(1, 0, 0),   -- Right
					Vector3.new(-1, 0, 0),  -- Left
					Vector3.new(0, 0, 1),   -- Front
					Vector3.new(0, 0, -1),  -- Back
				}

				local faceSize = Vector3.new(4, 4, 4)

				for _, normal in ipairs(faceNormals) do
					self:CreateCrackOnFace(box, normal, faceSize)
				end
			end
		end
	end)

	return box
end

function BoxManagerService:KnitStart()
	self:CreateBox(Vector3.new(0, 10, 0))
end

function BoxManagerService:KnitInit()
end

return BoxManagerService
