--[[
	RandomShapesController
	Creates a dozen random geometric shapes in the world
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Packages = game:GetService("ReplicatedStorage"):WaitForChild("Packages")
local Knit = require(Packages.Knit)

local RandomShapesController = Knit.CreateController {
	Name = "RandomShapesController",
	
	-- State
	_shapesFolder = nil,
	_shapes = {},
}

-- Shape types to randomly pick from
local SHAPE_TYPES = {
	Enum.PartType.Block,
	Enum.PartType.Ball,
	Enum.PartType.Cylinder,
	Enum.PartType.Wedge,
	Enum.PartType.CornerWedge,
}

-- Neon colors for variety
local COLORS = {
	Color3.fromRGB(255, 0, 100),    -- Hot pink
	Color3.fromRGB(0, 255, 200),    -- Cyan
	Color3.fromRGB(255, 100, 0),    -- Orange
	Color3.fromRGB(100, 0, 255),    -- Purple
	Color3.fromRGB(0, 255, 100),    -- Green
	Color3.fromRGB(255, 255, 0),    -- Yellow
	Color3.fromRGB(0, 150, 255),    -- Blue
	Color3.fromRGB(255, 50, 50),    -- Red
}

-- Materials for variety
local MATERIALS = {
	Enum.Material.Neon,
	Enum.Material.Glass,
	Enum.Material.SmoothPlastic,
	Enum.Material.Metal,
	Enum.Material.Foil,
}

-- === SHAPE CREATION ===

function RandomShapesController:CreateRandomShape(index)
	local part = Instance.new("Part")
	part.Name = "RandomShape_" .. index
	
	-- Random shape type
	local shapeType = SHAPE_TYPES[math.random(1, #SHAPE_TYPES)]
	if shapeType == Enum.PartType.Block then
		-- Block stays as default
	else
		part.Shape = shapeType
	end
	
	-- Random size (between 2 and 8 studs)
	local sizeX = math.random(20, 80) / 10
	local sizeY = math.random(20, 80) / 10
	local sizeZ = math.random(20, 80) / 10
	part.Size = Vector3.new(sizeX, sizeY, sizeZ)
	
	-- Random color
	part.Color = COLORS[math.random(1, #COLORS)]
	
	-- Random material
	part.Material = MATERIALS[math.random(1, #MATERIALS)]
	
	-- Random position (spread out in a 50x50 area, elevated)
	local posX = math.random(-25, 25)
	local posY = math.random(5, 30)
	local posZ = math.random(-25, 25)
	part.Position = Vector3.new(posX, posY, posZ)
	
	-- Random rotation
	local rotX = math.random(0, 360)
	local rotY = math.random(0, 360)
	local rotZ = math.random(0, 360)
	part.Orientation = Vector3.new(rotX, rotY, rotZ)
	
	-- Physics properties
	part.Anchored = false
	part.CanCollide = true
	part.CastShadow = true
	
	-- Add "shape" tag
	CollectionService:AddTag(part, "shape")
	
	-- Add point light to neon shapes
	if part.Material == Enum.Material.Neon then
		local light = Instance.new("PointLight")
		light.Color = part.Color
		light.Brightness = 1
		light.Range = 8
		light.Parent = part
	end
	
	return part
end

function RandomShapesController:CreateShapes(count)
	count = count or 12
	
	-- Clear existing shapes
	self:ClearShapes()
	
	-- Create folder to hold shapes
	self._shapesFolder = Instance.new("Folder")
	self._shapesFolder.Name = "RandomShapes"
	self._shapesFolder.Parent = Workspace
	
	-- Create the shapes
	for i = 1, count do
		local shape = self:CreateRandomShape(i)
		shape.Parent = self._shapesFolder
		table.insert(self._shapes, shape)
	end
	
	print("[RandomShapes] Created", count, "shapes")
end

function RandomShapesController:ClearShapes()
	-- Destroy all shapes
	for _, shape in ipairs(self._shapes) do
		if shape and shape.Parent then
			shape:Destroy()
		end
	end
	self._shapes = {}
	
	-- Destroy folder
	if self._shapesFolder then
		self._shapesFolder:Destroy()
		self._shapesFolder = nil
	end
end

function RandomShapesController:RandomizeShapes()
	-- Re-randomize existing shapes
	for i, shape in ipairs(self._shapes) do
		if shape and shape.Parent then
			-- Random position
			shape.Position = Vector3.new(
				math.random(-25, 25),
				math.random(5, 30),
				math.random(-25, 25)
			)
			
			-- Random rotation
			shape.Orientation = Vector3.new(
				math.random(0, 360),
				math.random(0, 360),
				math.random(0, 360)
			)
			
			-- Random color
			shape.Color = COLORS[math.random(1, #COLORS)]
			
			-- Update light color if present
			local light = shape:FindFirstChildOfClass("PointLight")
			if light then
				light.Color = shape.Color
			end
		end
	end
end

-- === PUBLIC API ===

function RandomShapesController:GetShapes()
	return self._shapes
end

function RandomShapesController:GetShapeCount()
	return #self._shapes
end

function RandomShapesController:SetShapeAnchored(anchored)
	for _, shape in ipairs(self._shapes) do
		if shape and shape.Parent then
			shape.Anchored = anchored
		end
	end
end

function RandomShapesController:SetShapeCollision(canCollide)
	for _, shape in ipairs(self._shapes) do
		if shape and shape.Parent then
			shape.CanCollide = canCollide
		end
	end
end

-- === KNIT LIFECYCLE ===

function RandomShapesController:KnitInit()
end

function RandomShapesController:KnitStart()
	-- Create 12 random shapes on start
	self:CreateShapes(12)
end

return RandomShapesController

