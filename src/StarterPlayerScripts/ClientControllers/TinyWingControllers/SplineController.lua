--[[
	SplineController
	
	Client-side spline generation and queries.
	Creates a Catmull-Rom spline that follows the terrain.
	All calculations happen locally - no network calls.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- Import spline module
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Splines = CustomPackages:WaitForChild("Splines")
local CatmullRomSpline = require(Splines:WaitForChild("CatmullRomSpline"))

local SplineController = Knit.CreateController {
	Name = "SplineController",
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Spline parameters
	PointSpacing = 15,          -- Distance between control points
	HeightOffset = 3,           -- Height above terrain for spline
	SplineTension = 0.5,        -- Catmull-Rom tension (0 = smooth, 1 = linear)
	
	-- Visualization
	ShowSpline = true,          -- Show spline visualization
	SplineColor = Color3.fromRGB(255, 255, 0),  -- Yellow
	SplineThickness = 0.5,
	ShowControlPoints = true,
	ControlPointColor = Color3.fromRGB(255, 0, 0),  -- Red
	ControlPointSize = 1,
}

-- State
local spline = nil
local controlPoints = {}
local terrainController = nil
local visualFolder = nil
local startX = 0
local endX = 0

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SPLINE GENERATION                                   ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Generate control points from terrain with UNIFORM 3D spacing
local function generateControlPoints()
	if not terrainController then
		warn("[SplineController] TerrainController not available!")
		return {}
	end
	
	local bounds = terrainController:GetBounds()
	startX = bounds.StartX
	endX = bounds.EndX
	
	-- First, sample terrain at high resolution to get the path
	local sampleStep = 2  -- Fine sampling for accuracy
	local samples = {}
	
	for x = startX, endX, sampleStep do
		local height = terrainController:GetHeightAtX(x)
		local point = Vector3.new(x, height + CONFIG.HeightOffset, 0)
		table.insert(samples, point)
	end
	
	-- Add end point
	local endHeight = terrainController:GetHeightAtX(endX)
	table.insert(samples, Vector3.new(endX, endHeight + CONFIG.HeightOffset, 0))
	
	-- Now walk along samples and place control points at uniform arc-length distances
	local points = {}
	local targetSpacing = CONFIG.PointSpacing  -- Desired 3D distance between points
	
	-- Start with first point
	table.insert(points, samples[1])
	local accumulatedDistance = 0
	local lastPoint = samples[1]
	
	for i = 2, #samples do
		local currentPoint = samples[i]
		local segmentDistance = (currentPoint - lastPoint).Magnitude
		accumulatedDistance = accumulatedDistance + segmentDistance
		
		-- When we've traveled far enough, add a control point
		while accumulatedDistance >= targetSpacing do
			-- Interpolate to find exact position at targetSpacing
			local overshoot = accumulatedDistance - targetSpacing
			local t = 1 - (overshoot / segmentDistance)
			local newPoint = lastPoint:Lerp(currentPoint, math.clamp(t, 0, 1))
			
			table.insert(points, newPoint)
			accumulatedDistance = overshoot
		end
		
		lastPoint = currentPoint
	end
	
	-- Ensure we have the end point
	local lastAdded = points[#points]
	if (samples[#samples] - lastAdded).Magnitude > 1 then
		table.insert(points, samples[#samples])
	end
	
	controlPoints = points
	print(string.format("[SplineController] Generated %d uniformly-spaced control points", #points))
	
	return points
end

-- Create the spline from control points
local function createSpline()
	local points = controlPoints
	
	if #points < 4 then
		warn("[SplineController] Need at least 4 control points for spline!")
		return nil
	end
	
	-- Create spline with first 4 points
	local newSpline = CatmullRomSpline.new({points[1], points[2], points[3], points[4]}, CONFIG.SplineTension)
	
	-- Add remaining points
	for i = 5, #points do
		newSpline:AddPoint(points[i])
	end
	
	spline = newSpline
	print("[SplineController] Spline created successfully")
	
	return spline
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         VISUALIZATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function clearVisualization()
	if visualFolder then
		visualFolder:Destroy()
		visualFolder = nil
	end
end

local function visualizeSpline()
	if not spline or not CONFIG.ShowSpline then return end
	
	clearVisualization()
	
	visualFolder = Instance.new("Folder")
	visualFolder.Name = "ClientSplineVisualization"
	visualFolder.Parent = Workspace
	
	-- Colors for slope direction
	local upwardColor = Color3.fromRGB(0, 150, 255)    -- Blue for upward
	local downwardColor = Color3.fromRGB(255, 150, 0)  -- Orange for downward
	
	-- Draw spline segments
	local segments = 200
	local lastPos = nil
	
	for i = 0, segments do
		local t = i / segments
		local pos = spline:CalculatePositionAt(t)
		
		if lastPos then
			-- Create line segment
			local segment = Instance.new("Part")
			segment.Name = "SplineSegment_" .. i
			segment.Anchored = true
			segment.CanCollide = false
			segment.CastShadow = false
			segment.Material = Enum.Material.Neon
			
			-- Color based on slope: going UP = blue, going DOWN = orange
			local direction = pos - lastPos
			local slope = direction.Y
			
			if slope > 0.1 then
				segment.Color = upwardColor      -- Going UP = blue
			elseif slope < -0.1 then
				segment.Color = downwardColor    -- Going DOWN = orange
			else
				segment.Color = CONFIG.SplineColor  -- Flat = default yellow
			end
			
			local distance = direction.Magnitude
			
			segment.Size = Vector3.new(CONFIG.SplineThickness, CONFIG.SplineThickness, distance)
			segment.CFrame = CFrame.lookAt(lastPos + direction / 2, pos)
			segment.Parent = visualFolder
		end
		
		lastPos = pos
	end
	
	-- Draw control points
	if CONFIG.ShowControlPoints then
		for i, point in ipairs(controlPoints) do
			local marker = Instance.new("Part")
			marker.Name = "ControlPoint_" .. i
			marker.Shape = Enum.PartType.Ball
			marker.Size = Vector3.new(CONFIG.ControlPointSize, CONFIG.ControlPointSize, CONFIG.ControlPointSize)
			marker.Position = point
			marker.Anchored = true
			marker.CanCollide = false
			marker.CastShadow = false
			marker.Material = Enum.Material.Neon
			marker.Color = CONFIG.ControlPointColor
			marker.Parent = visualFolder
		end
	end
	
	print(string.format("[SplineController] Visualized spline with %d segments", segments))
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SplineController:KnitInit()
	print("[SplineController] Initializing...")
end

function SplineController:KnitStart()
	print("[SplineController] Started")
	
	-- Get terrain controller
	terrainController = Knit.GetController("TerrainController")
	
	if not terrainController then
		warn("[SplineController] TerrainController not found!")
		return
	end
	
	-- Generate spline
	generateControlPoints()
	createSpline()
	
	-- Visualize
	if CONFIG.ShowSpline then
		visualizeSpline()
	end
	
	print("[SplineController] Client-side spline ready")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Get position on spline at t (0-1)
function SplineController:GetPositionAt(t)
	if not spline then return nil end
	return spline:CalculatePositionAt(math.clamp(t, 0, 1))
end

-- Get position relative to spline length
function SplineController:GetPositionRelativeToLength(t)
	if not spline then return nil end
	return spline:CalculatePositionRelativeToLength(math.clamp(t, 0, 1))
end

-- Get tangent/derivative at t (0-1)
function SplineController:GetDerivativeAt(t)
	if not spline then return nil end
	return spline:CalculateDerivativeAt(math.clamp(t, 0, 1))
end

-- Get spline length
function SplineController:GetLength()
	if not spline then return 0 end
	return spline.Length
end

-- Convert world X position to spline t parameter (0-1)
function SplineController:WorldXToSplineT(worldX)
	if endX == startX then return 0 end
	local t = (worldX - startX) / (endX - startX)
	return math.clamp(t, 0, 1)
end

-- Get position at world X (convenience method)
function SplineController:GetPositionAtWorldX(worldX)
	local t = self:WorldXToSplineT(worldX)
	return self:GetPositionAt(t)
end

-- Get raw spline object
function SplineController:GetSpline()
	return spline
end

-- Get control points
function SplineController:GetControlPoints()
	return controlPoints
end

-- Get bounds
function SplineController:GetBounds()
	return {
		StartX = startX,
		EndX = endX,
	}
end

-- Toggle visualization
function SplineController:SetVisualization(enabled)
	CONFIG.ShowSpline = enabled
	if enabled then
		visualizeSpline()
	else
		clearVisualization()
	end
end

-- Regenerate spline (call if terrain config changes)
function SplineController:Regenerate()
	generateControlPoints()
	createSpline()
	if CONFIG.ShowSpline then
		visualizeSpline()
	end
end

-- Get/Set config
function SplineController:GetConfig()
	return CONFIG
end

function SplineController:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		return true
	end
	return false
end

return SplineController

