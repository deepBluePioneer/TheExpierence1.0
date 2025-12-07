--[[
	SplinePathController
	Creates a spline path that runs through the environment
	Visualizes the path using debug gizmos
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Gizmo = require(Packages.imgizmo)
local CatmullRomSpline = require(CustomPackages:WaitForChild("Splines"):WaitForChild("CatmullRomSpline"))

local SplinePathController = Knit.CreateController {
	Name = "SplinePathController",
	_paths = {},        -- Store created paths
	_gizmoInit = false,
}

-- === CONFIGURATION ===
local PATH_CONFIG = {
	-- DISABLED: Spline path system disabled
	Enabled = false,
	
	-- Path generation
	DefaultTension = 0.5,         -- Spline tension (0 = sharp, 1 = loose)
	PathSegments = 100,           -- Number of segments to draw the path
	
	-- Visualization
	DebugEnabled = false,         -- DISABLED: No debug visualization
	PathColor = Color3.fromRGB(255, 150, 0),    -- Orange path
	PointColor = Color3.fromRGB(255, 255, 0),   -- Yellow control points
	PointRadius = 1,
	
	-- Auto-generation
	AutoPathPointCount = 8,       -- Number of points for auto-generated path
	AutoPathRadius = 100,         -- Radius of auto-generated path
	AutoPathHeight = 10,          -- Height above ground
	AutoPathHeightVariation = 5,  -- Random height variation
}

-- === GIZMO HELPERS ===

local function initGizmo()
	if not SplinePathController._gizmoInit then
		Gizmo.Init()
		SplinePathController._gizmoInit = true
	end
end

local function drawPathLine(startPos, endPos, color)
	if not PATH_CONFIG.DebugEnabled then return end
	initGizmo()
	Gizmo.SetStyle(color, 0, true)
	Gizmo.Ray:Draw(startPos, endPos)
end

local function drawControlPoint(position, color, radius)
	if not PATH_CONFIG.DebugEnabled then return end
	initGizmo()
	Gizmo.SetStyle(color, 0, true)
	Gizmo.Sphere:Draw(CFrame.new(position), radius, 8, 360)
end

-- === PATH CREATION ===

local function createPathFromPoints(points, tension)
	if #points < 4 then
		warn("[SplinePathController] Need at least 4 points for a spline")
		return nil
	end
	
	local spline = CatmullRomSpline.new(points, tension or PATH_CONFIG.DefaultTension)
	return spline
end

local function generateCircularPath(center, radius, pointCount, baseHeight)
	local points = {}
	
	for i = 0, pointCount - 1 do
		local angle = (i / pointCount) * math.pi * 2
		local x = center.X + math.cos(angle) * radius
		local z = center.Z + math.sin(angle) * radius
		local heightVariation = (math.random() - 0.5) * PATH_CONFIG.AutoPathHeightVariation * 2
		local y = baseHeight + heightVariation
		
		table.insert(points, Vector3.new(x, y, z))
	end
	
	-- Add first few points again to close the loop smoothly
	table.insert(points, points[1])
	table.insert(points, points[2])
	table.insert(points, points[3])
	
	return points
end

local function generateWanderingPath(startPos, pointCount, spread)
	local points = {}
	local currentPos = startPos
	
	for i = 1, pointCount do
		-- Random direction
		local angle = math.random() * math.pi * 2
		local distance = spread * (0.5 + math.random() * 0.5)
		
		local offsetX = math.cos(angle) * distance
		local offsetZ = math.sin(angle) * distance
		local offsetY = (math.random() - 0.5) * PATH_CONFIG.AutoPathHeightVariation * 2
		
		currentPos = currentPos + Vector3.new(offsetX, offsetY, offsetZ)
		
		-- Keep height reasonable
		currentPos = Vector3.new(currentPos.X, math.max(5, currentPos.Y), currentPos.Z)
		
		table.insert(points, currentPos)
	end
	
	return points
end

-- === PATH DATA STRUCTURE ===

local function createPathData(spline, points, name)
	return {
		name = name or "Path_" .. tostring(#SplinePathController._paths + 1),
		spline = spline,
		controlPoints = points,
		createdAt = tick(),
	}
end

-- === VISUALIZATION ===

local function visualizePath(pathData)
	if not PATH_CONFIG.DebugEnabled then return end
	if not pathData or not pathData.spline then return end
	
	local spline = pathData.spline
	local segments = PATH_CONFIG.PathSegments
	
	-- Draw the spline path
	for i = 0, segments - 1 do
		local t0 = i / segments
		local t1 = (i + 1) / segments
		
		local pos0 = spline:CalculatePositionAt(t0)
		local pos1 = spline:CalculatePositionAt(t1)
		
		drawPathLine(pos0, pos1, PATH_CONFIG.PathColor)
	end
	
	-- Draw control points
	for _, point in ipairs(pathData.controlPoints) do
		drawControlPoint(point, PATH_CONFIG.PointColor, PATH_CONFIG.PointRadius)
	end
end

local function visualizeAllPaths()
	for _, pathData in ipairs(SplinePathController._paths) do
		visualizePath(pathData)
	end
end

-- === PUBLIC API ===

function SplinePathController:CreatePath(points, tension, name)
	local spline = createPathFromPoints(points, tension)
	if not spline then return nil end
	
	local pathData = createPathData(spline, points, name)
	table.insert(self._paths, pathData)
	
	print(string.format("[SplinePathController] Created path '%s' with %d control points", pathData.name, #points))
	return pathData
end

function SplinePathController:CreateCircularPath(center, radius, pointCount, name)
	center = center or Vector3.new(0, 0, 0)
	radius = radius or PATH_CONFIG.AutoPathRadius
	pointCount = pointCount or PATH_CONFIG.AutoPathPointCount
	
	local points = generateCircularPath(center, radius, pointCount, PATH_CONFIG.AutoPathHeight)
	return self:CreatePath(points, nil, name or "CircularPath")
end

function SplinePathController:CreateWanderingPath(startPos, pointCount, spread, name)
	startPos = startPos or Vector3.new(0, PATH_CONFIG.AutoPathHeight, 0)
	pointCount = pointCount or PATH_CONFIG.AutoPathPointCount
	spread = spread or 30
	
	local points = generateWanderingPath(startPos, pointCount, spread)
	return self:CreatePath(points, nil, name or "WanderingPath")
end

function SplinePathController:GetPositionAt(pathData, t)
	if not pathData or not pathData.spline then return nil end
	return pathData.spline:CalculatePositionAt(t)
end

function SplinePathController:GetDirectionAt(pathData, t)
	if not pathData or not pathData.spline then return nil end
	local derivative = pathData.spline:CalculateDerivativeAt(t)
	return derivative.Unit
end

function SplinePathController:GetPath(nameOrIndex)
	if type(nameOrIndex) == "number" then
		return self._paths[nameOrIndex]
	else
		for _, pathData in ipairs(self._paths) do
			if pathData.name == nameOrIndex then
				return pathData
			end
		end
	end
	return nil
end

function SplinePathController:GetAllPaths()
	return self._paths
end

function SplinePathController:RemovePath(nameOrIndex)
	if type(nameOrIndex) == "number" then
		table.remove(self._paths, nameOrIndex)
	else
		for i, pathData in ipairs(self._paths) do
			if pathData.name == nameOrIndex then
				table.remove(self._paths, i)
				break
			end
		end
	end
end

function SplinePathController:ClearAllPaths()
	self._paths = {}
	print("[SplinePathController] Cleared all paths")
end

function SplinePathController:EnableDebug()
	PATH_CONFIG.DebugEnabled = true
end

function SplinePathController:DisableDebug()
	PATH_CONFIG.DebugEnabled = false
end

function SplinePathController:SetPathColor(color)
	PATH_CONFIG.PathColor = color
end

-- === KNIT LIFECYCLE ===

function SplinePathController:KnitInit()
	-- Early exit if disabled
	if not PATH_CONFIG.Enabled then
		return
	end
	initGizmo()
end

function SplinePathController:KnitStart()
	-- Early exit if disabled
	if not PATH_CONFIG.Enabled then
		return
	end
end

-- Expose config for external access (DebugVisualsController)
SplinePathController.PATH_CONFIG = PATH_CONFIG

return SplinePathController
