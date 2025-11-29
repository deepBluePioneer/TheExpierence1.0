local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local EntityCoverService = Knit.CreateService {
	Name = "EntityCoverService",
	Client = {},
}

-- === CONFIG ===
local ENTITY_TAG = "entity"

-- === KNIT LIFECYCLE ===

function EntityCoverService:KnitInit()
	print("[EntityCoverService] Initializing...")
end

function EntityCoverService:KnitStart()
	-- Get all existing entities with the tag
	local taggedEntities = CollectionService:GetTagged(ENTITY_TAG)
	print(string.format("[EntityCoverService] Found %d entities with '%s' tag", #taggedEntities, ENTITY_TAG))
	
	for _, entity in ipairs(taggedEntities) do
		print(string.format("[EntityCoverService] Entity: %s", entity.Name))
	end
	
	-- Listen for new entities being tagged
	CollectionService:GetInstanceAddedSignal(ENTITY_TAG):Connect(function(entity)
		print(string.format("[EntityCoverService] New entity tagged: %s", entity.Name))
	end)
	
	-- Listen for entities being untagged
	CollectionService:GetInstanceRemovedSignal(ENTITY_TAG):Connect(function(entity)
		print(string.format("[EntityCoverService] Entity untagged: %s", entity.Name))
	end)
	
	print("[EntityCoverService] Started!")
end

-- === PUBLIC METHODS ===

function EntityCoverService:GetAllEntities()
	return CollectionService:GetTagged(ENTITY_TAG)
end

function EntityCoverService:GetEntityCount()
	return #CollectionService:GetTagged(ENTITY_TAG)
end

return EntityCoverService
