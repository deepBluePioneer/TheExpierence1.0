local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local PhotoTargetService = Knit.CreateService {
	Name = "PhotoTargetService",
	Client = {
		PhotoTargetScanned = Knit.CreateSignal(),  -- Fires when a player scans a photo target
		TetrominoShapeCaptured = Knit.CreateSignal(),  -- Fires to client when a tetromino shape is captured
	},
	_scannedTargets = {},  -- Track which targets have been scanned (by model reference)
}

-- === CONFIG ===
local PHOTO_TARGET_TAG = "PhotoTarget"
local TARGETS_FOLDER_NAME = "PhotoTargets"

local TARGET_CONFIG = {
	Color = Color3.fromRGB(255, 255, 0),  -- Yellow
	Size = Vector3.new(2, 2, 2),
	Material = Enum.Material.SmoothPlastic,
	SpawnCount = 20,
	SpawnRadius = 60,
	SpawnHeight = 1,  -- Height above ground
}

-- === HELPERS ===

local function getTargetsFolder()
	local folder = Workspace:FindFirstChild(TARGETS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = TARGETS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function clearTargets()
	local folder = Workspace:FindFirstChild(TARGETS_FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

local function createTarget(position)
	local model = Instance.new("Model")
	model.Name = "PhotoTarget_" .. math.random(1000, 9999)
	
	local part = Instance.new("Part")
	part.Name = "TargetPart"
	part.Size = TARGET_CONFIG.Size
	part.Position = position
	part.Color = TARGET_CONFIG.Color
	part.Material = TARGET_CONFIG.Material
	part.Anchored = true
	part.CanCollide = true
	part.Parent = model
	
	model.PrimaryPart = part
	
	-- Add tag to the model
	CollectionService:AddTag(model, PHOTO_TARGET_TAG)
	
	return model
end

-- === KNIT LIFECYCLE ===

function PhotoTargetService:KnitInit()
	--("[PhotoTargetService] Initializing...")
end

function PhotoTargetService:KnitStart()
	-- Photo targets are now spawned by ReservedZoneService within photo target zones
	-- This service only provides the CreateTarget() method and manages photo target state
	-- We do NOT auto-generate photo targets here anymore
	--("[PhotoTargetService] Started - photo targets will be spawned by ReservedZoneService within zones")
	
	-- Listen for when players scan photo targets
	self.Client.PhotoTargetScanned:Connect(function(player, targetModel)
		-- Validate the target
		if not targetModel or not targetModel:IsA("Model") then
			warn(string.format("[PhotoTargetService] Invalid target model from player %s", player.Name))
			return
		end
		
		-- Check if target has the PhotoTarget tag
		if not CollectionService:HasTag(targetModel, PHOTO_TARGET_TAG) then
			warn(string.format("[PhotoTargetService] Target %s does not have PhotoTarget tag", targetModel.Name))
			return
		end
		
		-- Check if target has already been scanned
		if self._scannedTargets[targetModel] then
			--("[PhotoTargetService] Target %s already scanned, ignoring duplicate scan from %s", targetModel.Name, player.Name)
			return
		end
		
		-- Mark as scanned
		self._scannedTargets[targetModel] = true
		
		-- Get tetromino shape before destroying
		local tetrominoShape = targetModel:GetAttribute("TetrominoShape")
		
		-- Get target position and convert to grid coordinates
		local targetPosition = nil
		if targetModel.PrimaryPart then
			targetPosition = targetModel.PrimaryPart.Position
		elseif targetModel:FindFirstChild("TargetPart") then
			targetPosition = targetModel:FindFirstChild("TargetPart").Position
		end
		
		-- Destroy the target first
		targetModel:Destroy()
		
		-- Notify client to create tetromino shape in camera grid UI
		if targetPosition and tetrominoShape then
			local GridService = Knit.GetService("GridService")
			if GridService and GridService.WorldToGrid then
				local gridX, gridZ = GridService:WorldToGrid(targetPosition)
				if gridX and gridZ then
					-- Fire signal to client with grid coordinates and tetromino shape
					self.Client.TetrominoShapeCaptured:Fire(player, gridX, gridZ, tetrominoShape)
					--[[print(string.format("[PhotoTargetService] Notified client %s to create tetromino shape '%s' at grid cell (%d, %d)", 
						player.Name, tetrominoShape, gridX, gridZ))]]
				end
			end
		end
		
		--("[PhotoTargetService] Player %s scanned photo target %s (Tetromino: %s)", 
		--	player.Name, targetModel.Name, tetrominoShape or "Unknown")
		
		--("[PhotoTargetService] Photo target %s destroyed after being scanned", targetModel.Name)
	end)
	
	-- Mark step complete for LoadingService so it doesn't wait for us
	local LoadingService = nil
	pcall(function()
		LoadingService = Knit.GetService("LoadingService")
	end)
	
	if LoadingService then
		LoadingService:MarkStepComplete("PhotoTargetService")
		--("[PhotoTargetService] Marked step complete")
	end
end

-- === PUBLIC METHODS ===

function PhotoTargetService:CreateTarget(position)
	local folder = getTargetsFolder()
	local target = createTarget(position)
	target.Parent = folder
	return target
end

function PhotoTargetService:ClearTargets()
	clearTargets()
end

function PhotoTargetService:GetAllPhotoTargets()
	return CollectionService:GetTagged(PHOTO_TARGET_TAG)
end

function PhotoTargetService:GetSpawnCount()
	return TARGET_CONFIG.SpawnCount
end

function PhotoTargetService:RegenerateTargets(count)
	clearTargets()
	local folder = getTargetsFolder()
	
	for i = 1, (count or TARGET_CONFIG.SpawnCount) do
		local angle = math.random() * math.pi * 2
		local distance = math.random() * TARGET_CONFIG.SpawnRadius
		
		local position = Vector3.new(
			math.cos(angle) * distance,
			TARGET_CONFIG.SpawnHeight + TARGET_CONFIG.Size.Y / 2,
			math.sin(angle) * distance
		)
		
		local target = createTarget(position)
		target.Parent = folder
	end
end

return PhotoTargetService
