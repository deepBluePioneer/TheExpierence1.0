--[[
	EntityController
	Handles entity cloning from ReplicatedStorage.Prefab
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local EntityController = Knit.CreateController {
	Name = "EntityController",
}

-- === CONFIG ===
local ENTITY_TAG = "entity"
local PREFAB_FOLDER_NAME = "Prefab"

-- === HELPERS ===

-- Find and clone an entity model from Prefab folder
local function cloneEntity()
	local prefabFolder = ReplicatedStorage:FindFirstChild(PREFAB_FOLDER_NAME)
	if not prefabFolder then
		warn(string.format("[EntityController] Prefab folder not found in ReplicatedStorage"))
		return nil
	end
	
	-- Get all models with the "entity" tag
	local taggedEntities = CollectionService:GetTagged(ENTITY_TAG)
	
	-- Filter to only models that are in the Prefab folder
	local prefabEntity = nil
	for _, entity in ipairs(taggedEntities) do
		if entity:IsA("Model") and entity.Parent == prefabFolder then
			prefabEntity = entity
			break
		end
	end
	
	-- If no tagged entity found, search the Prefab folder directly
	if not prefabEntity then
		for _, child in ipairs(prefabFolder:GetChildren()) do
			if child:IsA("Model") and CollectionService:HasTag(child, ENTITY_TAG) then
				prefabEntity = child
				break
			end
		end
	end
	
	if not prefabEntity then
		warn(string.format("[EntityController] No model with '%s' tag found in Prefab folder", ENTITY_TAG))
		return nil
	end
	
	-- Clone the entity
	local clonedEntity = prefabEntity:Clone()
	print(string.format("[EntityController] Cloned entity: %s", clonedEntity.Name))
	
	return clonedEntity
end

-- === KNIT LIFECYCLE ===

function EntityController:KnitInit()
	print("[EntityController] Initializing...")
end

function EntityController:KnitStart()
	-- Clone an entity when the controller starts
	local entity = cloneEntity()
	if entity then
		-- Parent the cloned entity to workspace (or wherever you want it)
		entity.Parent = Workspace
		print("[EntityController] Entity cloned and added to workspace")
	end
end

return EntityController

