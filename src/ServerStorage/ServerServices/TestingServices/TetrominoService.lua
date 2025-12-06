local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- Shared modules
local Source = ReplicatedStorage:WaitForChild("Source")
local SharedModules = Source:WaitForChild("SharedModules")
local TetrominoShapes = require(SharedModules:WaitForChild("TetrominoShapes"))

local TetrominoService = Knit.CreateService {
	Name = "TetrominoService",
	Client = {},
}

-- === CONFIG ===
local PHOTO_TARGET_TAG = "PhotoTarget"
local TETROMINO_ATTRIBUTE_NAME = "TetrominoShape"

-- === HELPERS ===

-- Get a random tetromino shape (using shared module)
local function getRandomTetrominoShape()
	return TetrominoShapes.GetRandomShape()
end

-- Assign a random tetromino shape to a photo target
local function assignTetrominoToTarget(target)
	if not target or not target:IsA("Model") then
		return
	end
	
	local shape = getRandomTetrominoShape()
	target:SetAttribute(TETROMINO_ATTRIBUTE_NAME, shape)
	
	--[[print(string.format("[TetrominoService] Assigned tetromino shape '%s' to %s", shape, target.Name))]]
end

-- === KNIT LIFECYCLE ===

function TetrominoService:KnitInit()
	-- Nothing to init
end

function TetrominoService:KnitStart()
	-- Assign tetromino shapes to existing photo targets
	local existingTargets = CollectionService:GetTagged(PHOTO_TARGET_TAG)
	for _, target in ipairs(existingTargets) do
		-- Only assign if it doesn't already have a shape
		if not target:GetAttribute(TETROMINO_ATTRIBUTE_NAME) then
			assignTetrominoToTarget(target)
		end
	end
	
	-- Listen for new photo targets being added
	CollectionService:GetInstanceAddedSignal(PHOTO_TARGET_TAG):Connect(function(target)
		-- Small delay to ensure the target is fully initialized
		task.wait(0.1)
		assignTetrominoToTarget(target)
	end)
	
	--("[TetrominoService] Started - listening for photo targets")
	
	-- Mark step complete for LoadingService
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	if LoadingService then
		LoadingService:MarkStepComplete("TetrominoService")
	end
end

-- === PUBLIC METHODS ===

-- Get the tetromino shape for a specific photo target
function TetrominoService:GetTetrominoShape(target)
	if not target or not target:IsA("Model") then
		return nil
	end
	return target:GetAttribute(TETROMINO_ATTRIBUTE_NAME)
end

-- Assign a specific tetromino shape to a target
function TetrominoService:AssignTetrominoShape(target, shape)
	if not target or not target:IsA("Model") then
		warn("[TetrominoService] Invalid target provided")
		return false
	end
	
	if not TetrominoShapes.IsValidShape(shape) then
		warn(string.format("[TetrominoService] Invalid tetromino shape: %s", tostring(shape)))
		return false
	end
	
	target:SetAttribute(TETROMINO_ATTRIBUTE_NAME, shape)
	return true
end

-- Get all available tetromino shapes
function TetrominoService:GetAllTetrominoShapes()
	return TetrominoShapes.SHAPE_NAMES
end

-- Reassign random tetromino shapes to all photo targets
function TetrominoService:ReassignAllTetrominoShapes()
	local targets = CollectionService:GetTagged(PHOTO_TARGET_TAG)
	for _, target in ipairs(targets) do
		assignTetrominoToTarget(target)
	end
	--[[print(string.format("[TetrominoService] Reassigned tetromino shapes to %d photo targets", #targets))]]
end

return TetrominoService

