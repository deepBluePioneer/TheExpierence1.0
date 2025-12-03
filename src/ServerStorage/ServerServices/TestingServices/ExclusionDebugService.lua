--[[
	ExclusionDebugService
	Visualizes GridService exclusion zones with semi-transparent parts
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- Tag for exclusion from raycasts
local DEBUG_TAG = "gridCellDebugExclusion"

local ExclusionDebugService = Knit.CreateService {
	Name = "ExclusionDebugService",
	Client = {},
	_gridService = nil,
	_visualParts = {},
	_enabled = true,
	_zoneChangedConnection = nil,
}

-- === CONFIG ===
local DEBUG_CONFIG = {
	Enabled = true,                    -- Enable visualization
	
	-- Visual settings
	Color = Color3.fromRGB(255, 100, 100),  -- Red-ish color for exclusion zones
	Transparency = 0.7,                     -- Semi-transparent
	Material = Enum.Material.ForceField,    -- ForceField for visibility
	
	-- Cylinder settings (for circular zones)
	SegmentsPerCircle = 24,           -- How smooth the circle is
	
	-- Update settings (fallback polling if events not available)
	UpdateInterval = 2,               -- Seconds between updates (fallback only)
}

local DEBUG_FOLDER_NAME = "ExclusionZoneDebug"

-- === HELPERS ===

local function getDebugFolder()
	local folder = Workspace:FindFirstChild(DEBUG_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = DEBUG_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function clearVisuals(self)
	for _, part in ipairs(self._visualParts) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	self._visualParts = {}
end

-- Create a visual cylinder for a circular exclusion zone (upright)
local function createZoneVisual(zoneId, position, radius, height)
	local part = Instance.new("Part")
	part.Name = "ExclusionZone_" .. zoneId
	part.Shape = Enum.PartType.Cylinder
	-- Roblox Cylinder: X is the axis (length), Y and Z are diameter
	-- We want it upright, so we need to rotate it
	part.Size = Vector3.new(height, radius * 2, radius * 2)
	-- Rotate 90° around Z so the cylinder stands upright (X axis becomes Y axis)
	part.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Color = DEBUG_CONFIG.Color
	part.Transparency = DEBUG_CONFIG.Transparency
	part.Material = DEBUG_CONFIG.Material
	part.Parent = getDebugFolder()
	
	-- Tag for raycast exclusion
	CollectionService:AddTag(part, DEBUG_TAG)
	
	-- Add selection box for better visibility
	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Adornee = part
	selectionBox.Color3 = DEBUG_CONFIG.Color
	selectionBox.Transparency = 0.5
	selectionBox.LineThickness = 0.05
	selectionBox.Parent = part
	
	-- Add label
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, height / 2 + 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = string.format("%s\nR: %.0f", zoneId, radius)
	label.Parent = billboard
	
	return {part}  -- Return as array for consistency
end

-- === VISUALIZATION ===

local function updateVisuals(self)
	if not self._enabled or not DEBUG_CONFIG.Enabled then
		clearVisuals(self)
		return
	end
	
	if not self._gridService then
		return
	end
	
	-- Get exclusion zones from GridService
	local exclusionZones = self._gridService:GetExclusionZones()
	if not exclusionZones then
		return
	end
	
	-- Clear old visuals
	clearVisuals(self)
	
	-- Create new visuals for each zone
	for zoneId, zoneData in pairs(exclusionZones) do
		local visuals = createZoneVisual(
			zoneId,
			zoneData.position,
			zoneData.radius,
			zoneData.height or 50
		)
		-- visuals is now an array of parts
		for _, part in ipairs(visuals) do
			table.insert(self._visualParts, part)
		end
	end
	
	print(string.format("[ExclusionDebugService] Updated %d exclusion zone visuals", #self._visualParts))
end

-- === KNIT LIFECYCLE ===

function ExclusionDebugService:KnitInit()
	print("[ExclusionDebugService] Initializing...")
end

function ExclusionDebugService:KnitStart()
	-- Get GridService reference
	pcall(function()
		self._gridService = Knit.GetService("GridService")
	end)
	
	if not self._gridService then
		warn("[ExclusionDebugService] GridService not found!")
		return
	end
	
	-- Initial update after a delay to let other services register zones
	task.delay(3, function()
		updateVisuals(self)
	end)
	
	-- Listen for exclusion zone changes instead of polling
	if self._gridService.ExclusionZoneChanged then
		self._zoneChangedConnection = self._gridService.ExclusionZoneChanged:Connect(function()
			if self._enabled then
				updateVisuals(self)
			end
		end)
		print("[ExclusionDebugService] Listening to exclusion zone changes via signal")
	else
		warn("[ExclusionDebugService] GridService.ExclusionZoneChanged signal not available, falling back to polling")
		-- Fallback to polling if signal not available
		task.spawn(function()
			while true do
				task.wait(DEBUG_CONFIG.UpdateInterval)
				if self._enabled then
					updateVisuals(self)
				end
			end
		end)
	end
	
	print("[ExclusionDebugService] Started")
end

-- === PUBLIC API ===

function ExclusionDebugService:Enable()
	self._enabled = true
	updateVisuals(self)
	print("[ExclusionDebugService] Enabled")
end

function ExclusionDebugService:Disable()
	self._enabled = false
	clearVisuals(self)
	
	-- Disconnect from signal
	if self._zoneChangedConnection then
		self._zoneChangedConnection:Disconnect()
		self._zoneChangedConnection = nil
	end
	
	print("[ExclusionDebugService] Disabled")
end

function ExclusionDebugService:Toggle()
	if self._enabled then
		self:Disable()
	else
		self:Enable()
	end
end

function ExclusionDebugService:IsEnabled()
	return self._enabled
end

function ExclusionDebugService:Refresh()
	updateVisuals(self)
end

function ExclusionDebugService:SetColor(color)
	DEBUG_CONFIG.Color = color
	updateVisuals(self)
end

function ExclusionDebugService:SetTransparency(transparency)
	DEBUG_CONFIG.Transparency = transparency
	updateVisuals(self)
end

-- Get all debug parts for raycast exclusion
function ExclusionDebugService:GetDebugParts()
	return CollectionService:GetTagged(DEBUG_TAG)
end

-- Get the tag name for external use
function ExclusionDebugService:GetDebugTag()
	return DEBUG_TAG
end

-- Helper to add debug parts to a RaycastParams filter
function ExclusionDebugService:AddToRaycastFilter(raycastParams)
	local debugParts = self:GetDebugParts()
	local currentFilter = raycastParams.FilterDescendantsInstances or {}
	
	-- Add debug parts to filter
	for _, part in ipairs(debugParts) do
		table.insert(currentFilter, part)
	end
	
	-- Also add the debug folder
	local folder = Workspace:FindFirstChild(DEBUG_FOLDER_NAME)
	if folder then
		table.insert(currentFilter, folder)
	end
	
	raycastParams.FilterDescendantsInstances = currentFilter
	return raycastParams
end

return ExclusionDebugService

