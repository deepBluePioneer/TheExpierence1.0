--[[
	BridgeSplineService
	
	Handles generation of spline-based bridge/track paths.
	Extracted from HubService for modularity and reusability.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local BridgeSplineService = Knit.CreateService {
	Name = "BridgeSplineService",
	Client = {},
	
	-- Generated data
	_bridgeFolder = nil,
	_path = nil,
	_controlPoints = nil,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Track/Deck dimensions
	TrackWidth = 30,
	TrackThickness = 2,
	TrackMaterial = Enum.Material.SmoothPlastic,
	TrackColor = Color3.fromRGB(255, 180, 50),
	
	-- Track path settings
	TrackTotalLength = 800,
	TrackNumControlPoints = 20,
	TrackMinHeight = 10,
	TrackStartHeight = 50,
	
	-- Rail settings (old style)
	RailEnabled = false,
	RailHeight = 3,
	RailThickness = 0.8,
	RailMaterial = Enum.Material.Metal,
	RailColor = Color3.fromRGB(80, 85, 90),
	RailSegmentLength = 8,
	
	-- Smooth path generation
	SubdivisionsPerSegment = 25,
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- SUSPENSION BRIDGE SETTINGS
	-- ═══════════════════════════════════════════════════════════════════════
	
	SuspensionEnabled = true,
	
	-- Towers (Pylons) - tall vertical structures supporting cables
	TowerCount = 4,                              -- More towers for longer bridge
	TowerHeight = 100,                           -- Taller towers for longer spans
	TowerWidth = 10,                             -- Wider tower base
	TowerDepth = 6,                              -- Deeper tower
	TowerColor = Color3.fromRGB(70, 75, 80),     -- Dark steel gray
	TowerMaterial = Enum.Material.Metal,
	TowerTopWidth = 6,                           -- Narrower at top
	
	-- Main Cables - primary load-bearing cables over towers
	MainCableThickness = 2,                      -- Thicker cables for longer bridge
	MainCableColor = Color3.fromRGB(50, 55, 60), -- Dark cable color
	MainCableMaterial = Enum.Material.Metal,
	MainCableSag = 40,                           -- More sag for longer spans
	MainCableSegments = 60,                      -- More segments for smoothness
	MainCableInset = 1,                          -- How far inside deck edge the cable sits
	
	-- Anchorages - massive structures at each end holding cables
	AnchorageSize = Vector3.new(20, 15, 15),
	AnchorageColor = Color3.fromRGB(100, 100, 105),
	AnchorageMaterial = Enum.Material.Concrete,
	
	-- Suspender Cables (Vertical Hangers) - connect main cable to deck
	HangerThickness = 0.5,
	HangerColor = Color3.fromRGB(60, 65, 70),
	HangerMaterial = Enum.Material.Metal,
	HangerSpacing = 20,                          -- Distance between hangers
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CATMULL-ROM INTERPOLATION                           ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function catmullRomInterpolate(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	
	return 0.5 * (
		(2 * p1) +
		(-p0 + p2) * t +
		(2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
		(-p0 + 3 * p1 - 3 * p2 + p3) * t3
	)
end

-- Generate smooth path from control points using Catmull-Rom interpolation
local function generateSmoothPath(controlPoints, subdivisions)
	local path = {}
	
	if #controlPoints < 4 then
		return controlPoints
	end
	
	-- Create phantom points for full interpolation
	local phantomStart = controlPoints[1] - (controlPoints[2] - controlPoints[1])
	local phantomEnd = controlPoints[#controlPoints] + (controlPoints[#controlPoints] - controlPoints[#controlPoints - 1])
	
	local extendedPoints = {phantomStart}
	for _, p in ipairs(controlPoints) do
		table.insert(extendedPoints, p)
	end
	table.insert(extendedPoints, phantomEnd)
	
	for i = 2, #extendedPoints - 2 do
		local p0 = extendedPoints[i - 1]
		local p1 = extendedPoints[i]
		local p2 = extendedPoints[i + 1]
		local p3 = extendedPoints[i + 2]
		
		for j = 0, subdivisions - 1 do
			local t = j / subdivisions
			local pos = catmullRomInterpolate(p0, p1, p2, p3, t)
			table.insert(path, pos)
		end
	end
	
	table.insert(path, controlPoints[#controlPoints])
	
	return path
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONTROL POINT GENERATION                            ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BridgeSplineService:GenerateControlPoints(startPos, endPos, options)
	options = options or {}
	
	local numPoints = options.numPoints or CONFIG.TrackNumControlPoints
	local points = {}
	
	-- Generate evenly spaced points along straight line
	for i = 0, numPoints - 1 do
		local t = i / (numPoints - 1)
		local point = startPos:Lerp(endPos, t)
		table.insert(points, point)
	end
	
	print(string.format("[BridgeSplineService] Generated %d control points", #points))
	return points
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         TRACK SEGMENT CREATION                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BridgeSplineService:CreateTrackSegment(startPos, endPos, options)
	options = options or {}
	local width = options.width or CONFIG.TrackWidth
	local color = options.color or CONFIG.TrackColor
	local bankAngle = options.bankAngle or 0
	local parent = options.parent
	
	local direction = endPos - startPos
	local length = direction.Magnitude
	if length < 0.1 then return nil end
	
	local midPoint = (startPos + endPos) / 2
	local overlapLength = length * 1.15
	
	local forward = direction.Unit
	local worldUp = Vector3.new(0, 1, 0)
	local right = forward:Cross(worldUp)
	if right.Magnitude < 0.1 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	
	local numLanes = 3
	local laneWidth = width / numLanes
	local segments = {}
	
	local baseCF = CFrame.lookAt(midPoint, midPoint + forward, worldUp)
	
	if bankAngle ~= 0 then
		baseCF = baseCF * CFrame.Angles(0, 0, math.rad(bankAngle))
	end
	
	for lane = 0, numLanes - 1 do
		local laneOffset = (lane - (numLanes - 1) / 2) * laneWidth
		local laneCenter = baseCF.Position + baseCF.RightVector * laneOffset
		
		local segment = Instance.new("Part")
		segment.Name = "BridgeSegment"
		segment.Size = Vector3.new(laneWidth * 1.02, CONFIG.TrackThickness, overlapLength)
		segment.Color = color
		segment.Material = CONFIG.TrackMaterial
		segment.Anchored = true
		segment.CanCollide = true
		segment.CFrame = CFrame.new(laneCenter) * baseCF.Rotation
		
		if parent then
			segment.Parent = parent
		end
		table.insert(segments, segment)
	end
	
	return segments
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         RAIL CREATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BridgeSplineService:CreateRails(path, options)
	options = options or {}
	local width = options.width or CONFIG.TrackWidth
	local color = options.color or CONFIG.RailColor
	local parent = options.parent
	
	if not CONFIG.RailEnabled then return end
	
	local numSpikes = math.ceil(#path / 10)
	numSpikes = math.max(numSpikes, 2)
	
	for i = 1, #path, math.floor(#path / numSpikes) do
		local pos = path[i]
		local nextPos = path[math.min(i + 1, #path)]
		local tangent = (nextPos - pos)
		
		if tangent.Magnitude > 0.1 then
			local forward = tangent.Unit
			local right = forward:Cross(Vector3.new(0, 1, 0))
			if right.Magnitude < 0.1 then
				right = Vector3.new(1, 0, 0)
			end
			right = right.Unit
			
			local spikeOffset = width / 2 - CONFIG.RailThickness / 4
			local baseY = pos.Y + CONFIG.TrackThickness / 2
			
			local leftBasePos = Vector3.new(pos.X, baseY, pos.Z) - right * spikeOffset
			local rightBasePos = Vector3.new(pos.X, baseY, pos.Z) + right * spikeOffset
			
			-- Left spike
			local leftSpike = Instance.new("WedgePart")
			leftSpike.Name = "LeftRail_" .. i
			leftSpike.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.RailThickness * 1.5)
			leftSpike.Color = color
			leftSpike.Material = CONFIG.RailMaterial
			leftSpike.Anchored = true
			leftSpike.CanCollide = true
			local leftCF = CFrame.lookAt(leftBasePos, leftBasePos + forward)
			leftSpike.CFrame = leftCF * CFrame.new(0, CONFIG.RailHeight / 2, 0) * CFrame.Angles(0, math.pi, 0)
			if parent then leftSpike.Parent = parent end
			
			-- Right spike
			local rightSpike = Instance.new("WedgePart")
			rightSpike.Name = "RightRail_" .. i
			rightSpike.Size = Vector3.new(CONFIG.RailThickness, CONFIG.RailHeight, CONFIG.RailThickness * 1.5)
			rightSpike.Color = color
			rightSpike.Material = CONFIG.RailMaterial
			rightSpike.Anchored = true
			rightSpike.CanCollide = true
			local rightCF = CFrame.lookAt(rightBasePos, rightBasePos + forward)
			rightSpike.CFrame = rightCF * CFrame.new(0, CONFIG.RailHeight / 2, 0)
			if parent then rightSpike.Parent = parent end
		end
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SUSPENSION BRIDGE - TOWERS                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BridgeSplineService:CreateTower(position, deckHeight, options)
	options = options or {}
	local parent = options.parent
	local width = options.width or CONFIG.TrackWidth
	
	local towerFolder = Instance.new("Model")
	towerFolder.Name = "Tower"
	
	local towerHeight = CONFIG.TowerHeight
	local towerWidth = CONFIG.TowerWidth
	local towerDepth = CONFIG.TowerDepth
	
	-- Cable position: directly above deck edge
	local cableOffset = (width / 2) - CONFIG.MainCableInset
	-- Tower leg position: outside the deck
	local legOffset = (width / 2) + (towerWidth / 2) + 2
	
	-- Tower legs extend from ground (Y=0) up through the deck to tower top
	local groundLevel = 0
	local towerTopY = deckHeight + towerHeight
	local totalLegHeight = towerTopY - groundLevel  -- Full height from ground to tower top
	
	-- Create two tower legs (left and right of deck)
	for side = -1, 1, 2 do
		-- Main tower leg - extends from ground to tower top
		local leg = Instance.new("Part")
		leg.Name = "TowerLeg_" .. (side == -1 and "L" or "R")
		leg.Size = Vector3.new(towerWidth, totalLegHeight, towerDepth)
		leg.Position = position + Vector3.new(side * legOffset, groundLevel + totalLegHeight / 2, 0)
		leg.Color = CONFIG.TowerColor
		leg.Material = CONFIG.TowerMaterial
		leg.Anchored = true
		leg.CanCollide = true
		leg.Parent = towerFolder
		
		-- Tower top cap
		local cap = Instance.new("Part")
		cap.Name = "TowerCap_" .. (side == -1 and "L" or "R")
		cap.Size = Vector3.new(towerWidth + 2, 3, towerDepth + 2)
		cap.Position = position + Vector3.new(side * legOffset, towerTopY + 1.5, 0)
		cap.Color = CONFIG.TowerColor
		cap.Material = CONFIG.TowerMaterial
		cap.Anchored = true
		cap.CanCollide = false
		cap.Parent = towerFolder
		
		-- Cable saddle at top (positioned above deck edge where cable runs)
		local saddle = Instance.new("Part")
		saddle.Name = "CableSaddle_" .. (side == -1 and "L" or "R")
		saddle.Size = Vector3.new(CONFIG.MainCableThickness * 3, 2, CONFIG.MainCableThickness * 3)
		saddle.Position = position + Vector3.new(side * cableOffset, towerTopY + 3, 0)
		saddle.Color = Color3.fromRGB(40, 45, 50)
		saddle.Material = Enum.Material.Metal
		saddle.Anchored = true
		saddle.CanCollide = false
		saddle.Shape = Enum.PartType.Cylinder
		saddle.CFrame = CFrame.new(saddle.Position) * CFrame.Angles(0, 0, math.rad(90))
		saddle.Parent = towerFolder
		
		-- Horizontal arm connecting leg to cable saddle
		local armLength = legOffset - cableOffset
		local arm = Instance.new("Part")
		arm.Name = "TowerArm_" .. (side == -1 and "L" or "R")
		arm.Size = Vector3.new(armLength, 3, towerDepth)
		arm.Position = position + Vector3.new(side * (cableOffset + armLength / 2), towerTopY + 1.5, 0)
		arm.Color = CONFIG.TowerColor
		arm.Material = CONFIG.TowerMaterial
		arm.Anchored = true
		arm.CanCollide = false
		arm.Parent = towerFolder
	end
	
	-- Cross beam connecting tower tops
	local crossBeam = Instance.new("Part")
	crossBeam.Name = "CrossBeam"
	local beamWidth = legOffset * 2
	crossBeam.Size = Vector3.new(beamWidth, 4, towerDepth)
	crossBeam.Position = position + Vector3.new(0, towerTopY - 5, 0)
	crossBeam.Color = CONFIG.TowerColor
	crossBeam.Material = CONFIG.TowerMaterial
	crossBeam.Anchored = true
	crossBeam.CanCollide = false
	crossBeam.Parent = towerFolder
	
	if parent then
		towerFolder.Parent = parent
	end
	
	return towerFolder
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SUSPENSION BRIDGE - ANCHORAGES                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BridgeSplineService:CreateAnchorage(position, facingDirection, options)
	options = options or {}
	local parent = options.parent
	local width = options.width or CONFIG.TrackWidth
	
	local anchorFolder = Instance.new("Model")
	anchorFolder.Name = "Anchorage"
	
	-- Cable position: directly above deck edge
	local cableOffset = (width / 2) - CONFIG.MainCableInset
	
	-- Anchor post height - small posts at deck edge to hold cable ends
	local postHeight = 5
	local postWidth = 4
	
	-- Create two anchor posts (left and right of deck)
	for side = -1, 1, 2 do
		-- Anchor post at deck edge
		local anchor = Instance.new("Part")
		anchor.Name = "AnchorPost_" .. (side == -1 and "L" or "R")
		anchor.Size = Vector3.new(postWidth, postHeight, postWidth)
		anchor.Position = position + Vector3.new(side * cableOffset, CONFIG.TrackThickness + postHeight / 2, 0)
		anchor.Color = CONFIG.AnchorageColor
		anchor.Material = CONFIG.AnchorageMaterial
		anchor.Anchored = true
		anchor.CanCollide = true
		anchor.Parent = anchorFolder
		
		-- Cable clamp on top of post
		local clamp = Instance.new("Part")
		clamp.Name = "CableClamp_" .. (side == -1 and "L" or "R")
		clamp.Size = Vector3.new(postWidth + 1, 2, postWidth + 1)
		clamp.Position = position + Vector3.new(side * cableOffset, CONFIG.TrackThickness + postHeight + 1, 0)
		clamp.Color = Color3.fromRGB(50, 55, 60)
		clamp.Material = Enum.Material.Metal
		clamp.Anchored = true
		clamp.CanCollide = false
		clamp.Parent = anchorFolder
	end
	
	if parent then
		anchorFolder.Parent = parent
	end
	
	return anchorFolder
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SUSPENSION BRIDGE - MAIN CABLES                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BridgeSplineService:CreateMainCable(startPos, endPos, towerPositions, deckHeight, options)
	options = options or {}
	local parent = options.parent
	local width = options.width or CONFIG.TrackWidth
	local side = options.side or 1  -- 1 = right, -1 = left
	
	local cableFolder = Instance.new("Folder")
	cableFolder.Name = "MainCable_" .. (side == -1 and "L" or "R")
	
	-- Cable runs directly above deck edge
	local cableOffset = (width / 2) - CONFIG.MainCableInset
	local towerTopHeight = deckHeight + CONFIG.TowerHeight
	
	-- Anchor cable attachment is at deck level (cables drape down from towers to deck ends)
	local startAnchorHeight = startPos.Y + CONFIG.TrackThickness
	local endAnchorHeight = endPos.Y + CONFIG.TrackThickness
	
	-- Build list of key points for cable: anchor -> towers -> anchor
	local keyPoints = {}
	
	-- Start anchor point (at deck level)
	table.insert(keyPoints, {
		pos = Vector3.new(startPos.X + side * cableOffset, startAnchorHeight, startPos.Z),
		isTower = false
	})
	
	-- Tower top points
	for _, towerPos in ipairs(towerPositions) do
		table.insert(keyPoints, {
			pos = Vector3.new(towerPos.X + side * cableOffset, towerTopHeight + 3, towerPos.Z),
			isTower = true
		})
	end
	
	-- End anchor point (at deck level)
	table.insert(keyPoints, {
		pos = Vector3.new(endPos.X + side * cableOffset, endAnchorHeight, endPos.Z),
		isTower = false
	})
	
	-- Create cable segments between each pair of key points with catenary sag
	for i = 1, #keyPoints - 1 do
		local p1 = keyPoints[i]
		local p2 = keyPoints[i + 1]
		
		local segmentCount = CONFIG.MainCableSegments
		local sag = CONFIG.MainCableSag
		
		-- If between two towers or tower to anchor, apply sag
		local applySag = true
		
		for j = 0, segmentCount - 1 do
			local t1 = j / segmentCount
			local t2 = (j + 1) / segmentCount
			
			local pos1 = p1.pos:Lerp(p2.pos, t1)
			local pos2 = p1.pos:Lerp(p2.pos, t2)
			
			-- Apply catenary sag (parabolic approximation)
			if applySag then
				local sagAmount1 = sag * (4 * t1 * (1 - t1))  -- Parabola: max at middle
				local sagAmount2 = sag * (4 * t2 * (1 - t2))
				pos1 = pos1 - Vector3.new(0, sagAmount1, 0)
				pos2 = pos2 - Vector3.new(0, sagAmount2, 0)
			end
			
			-- Create cable segment
			local direction = pos2 - pos1
			local length = direction.Magnitude
			local midPoint = (pos1 + pos2) / 2
			
			local cable = Instance.new("Part")
			cable.Name = "CableSegment_" .. i .. "_" .. j
			cable.Size = Vector3.new(CONFIG.MainCableThickness, CONFIG.MainCableThickness, length)
			cable.CFrame = CFrame.lookAt(midPoint, pos2)
			cable.Color = CONFIG.MainCableColor
			cable.Material = CONFIG.MainCableMaterial
			cable.Anchored = true
			cable.CanCollide = false
			cable.CastShadow = false
			cable.Parent = cableFolder
		end
	end
	
	if parent then
		cableFolder.Parent = parent
	end
	
	return cableFolder
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SUSPENSION BRIDGE - HANGERS                         ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BridgeSplineService:CreateHangers(path, startPos, endPos, towerPositions, deckHeight, options)
	options = options or {}
	local parent = options.parent
	local width = options.width or CONFIG.TrackWidth
	
	local hangerFolder = Instance.new("Folder")
	hangerFolder.Name = "Hangers"
	
	-- Cable runs directly above deck edge
	local cableOffset = (width / 2) - CONFIG.MainCableInset
	
	-- Use consistent deck surface height (top of deck)
	local deckSurfaceY = deckHeight + CONFIG.TrackThickness / 2
	
	-- Tower cable height (must match CreateMainCable exactly)
	local towerCableHeight = deckHeight + CONFIG.TowerHeight + 3
	
	-- Anchor cable heights (at deck surface, matching CreateMainCable)
	local startAnchorHeight = startPos.Y + CONFIG.TrackThickness
	local endAnchorHeight = endPos.Y + CONFIG.TrackThickness
	
	local spacing = CONFIG.HangerSpacing
	local sag = CONFIG.MainCableSag
	
	-- Build key points list (same as CreateMainCable) for height calculation
	-- Key points: start anchor -> towers -> end anchor
	local keyPoints = {}
	table.insert(keyPoints, { z = startPos.Z, y = startAnchorHeight })
	for _, towerPos in ipairs(towerPositions) do
		table.insert(keyPoints, { z = towerPos.Z, y = towerCableHeight })
	end
	table.insert(keyPoints, { z = endPos.Z, y = endAnchorHeight })
	
	-- Sort by Z position
	table.sort(keyPoints, function(a, b) return a.z < b.z end)
	
	-- Function to calculate cable height at a given Z position
	local function getCableHeightAtZ(z)
		-- Find which segment this Z falls into
		for i = 1, #keyPoints - 1 do
			local p1 = keyPoints[i]
			local p2 = keyPoints[i + 1]
			
			if z >= p1.z and z <= p2.z then
				-- Calculate t (0-1) within this segment
				local segmentLength = p2.z - p1.z
				if segmentLength <= 0 then
					return p1.y
				end
				
				local t = (z - p1.z) / segmentLength
				
				-- Linear interpolation between heights
				local baseHeight = p1.y + (p2.y - p1.y) * t
				
				-- Apply catenary sag (parabola: max sag at middle of segment)
				local sagAmount = sag * (4 * t * (1 - t))
				
				return baseHeight - sagAmount
			end
		end
		
		-- If outside range, return nearest endpoint height
		if z < keyPoints[1].z then
			return keyPoints[1].y
		else
			return keyPoints[#keyPoints].y
		end
	end
	
	-- Create hangers along the path at regular intervals
	local totalLength = math.abs(endPos.Z - startPos.Z)
	local numHangers = math.floor(totalLength / spacing)
	
	for i = 1, numHangers do
		-- Calculate Z position for this hanger
		local t = i / (numHangers + 1)
		local hangerZ = startPos.Z + t * (endPos.Z - startPos.Z)
		
		-- Get cable height at this Z position
		local cableHeightAtPoint = getCableHeightAtZ(hangerZ)
		
		-- Hanger bottom is at deck surface (consistent height for flat bridge)
		local hangerBottomY = deckSurfaceY
		
		-- Only create hangers where cable is significantly above deck
		local hangerLength = cableHeightAtPoint - hangerBottomY
		
		if hangerLength > 3 then  -- Only if cable is at least 3 studs above deck
			-- Create hangers on both sides
			for side = -1, 1, 2 do
				local hangerTopPos = Vector3.new(
					startPos.X + side * cableOffset,
					cableHeightAtPoint,
					hangerZ
				)
				local hangerBottomPos = Vector3.new(
					startPos.X + side * cableOffset,
					hangerBottomY,
					hangerZ
				)
				
				local hangerMid = (hangerTopPos + hangerBottomPos) / 2
				
				local hanger = Instance.new("Part")
				hanger.Name = "Hanger_" .. i .. "_" .. (side == -1 and "L" or "R")
				hanger.Size = Vector3.new(CONFIG.HangerThickness, hangerLength, CONFIG.HangerThickness)
				hanger.Position = hangerMid
				hanger.Color = CONFIG.HangerColor
				hanger.Material = CONFIG.HangerMaterial
				hanger.Anchored = true
				hanger.CanCollide = false
				hanger.CastShadow = false
				hanger.Parent = hangerFolder
				
				-- Create spire at top of hanger
				local spireHeight = 4
				local spire = Instance.new("Part")
				spire.Name = "Spire_" .. i .. "_" .. (side == -1 and "L" or "R")
				spire.Size = Vector3.new(0.8, spireHeight, 0.8)
				spire.Position = hangerTopPos + Vector3.new(0, spireHeight / 2, 0)
				spire.Color = Color3.fromRGB(40, 45, 50)
				spire.Material = Enum.Material.Metal
				spire.Anchored = true
				spire.CanCollide = false
				spire.CastShadow = false
				spire.Parent = hangerFolder
				
				-- Create light bulb at top of spire
				local lightBulb = Instance.new("Part")
				lightBulb.Name = "LightBulb_" .. i .. "_" .. (side == -1 and "L" or "R")
				lightBulb.Size = Vector3.new(1.2, 1.2, 1.2)
				lightBulb.Position = hangerTopPos + Vector3.new(0, spireHeight + 0.6, 0)
				lightBulb.Color = Color3.fromRGB(255, 200, 0)  -- Yellow
				lightBulb.Material = Enum.Material.Neon
				lightBulb.Shape = Enum.PartType.Ball
				lightBulb.Anchored = true
				lightBulb.CanCollide = false
				lightBulb.CastShadow = false
				lightBulb.Parent = hangerFolder
				
				-- Add point light for glow effect
				local pointLight = Instance.new("PointLight")
				pointLight.Name = "SpireLight"
				pointLight.Color = Color3.fromRGB(255, 200, 0)  -- Yellow
				pointLight.Brightness = 2
				pointLight.Range = 20
				pointLight.Enabled = true
				pointLight.Parent = lightBulb
				
				-- Create blinking effect using a NumberValue to track state
				local blinkValue = Instance.new("NumberValue")
				blinkValue.Name = "BlinkOffset"
				blinkValue.Value = (i + (side == -1 and 0 or 0.5)) * 0.3  -- Stagger the blinks
				blinkValue.Parent = lightBulb
			end
		end
	end
	
	-- Start blinking coroutine for all lights
	task.spawn(function()
		while hangerFolder and hangerFolder.Parent do
			local currentTime = tick()
			for _, child in ipairs(hangerFolder:GetDescendants()) do
				if child:IsA("Part") and child.Name:find("LightBulb") then
					local blinkOffset = child:FindFirstChild("BlinkOffset")
					local offset = blinkOffset and blinkOffset.Value or 0
					local blinkPhase = (currentTime + offset) % 2  -- 2 second cycle
					local isOn = blinkPhase < 1  -- On for 1 second, off for 1 second
					
					child.Material = isOn and Enum.Material.Neon or Enum.Material.SmoothPlastic
					child.Color = isOn and Color3.fromRGB(255, 200, 0) or Color3.fromRGB(100, 80, 0)
					
					local light = child:FindFirstChild("SpireLight")
					if light then
						light.Enabled = isOn
					end
				end
			end
			task.wait(0.5)  -- Update every half second for smooth blinking
		end
	end)
	
	if parent then
		hangerFolder.Parent = parent
	end
	
	return hangerFolder
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MAIN BRIDGE GENERATION                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BridgeSplineService:GenerateBridge(startPos, endPos, options)
	options = options or {}
	local parent = options.parent or Workspace
	local width = options.width or CONFIG.TrackWidth
	local color = options.color or CONFIG.TrackColor
	
	print("[BridgeSplineService] Generating suspension bridge...")
	print(string.format("[BridgeSplineService] Start: (%.1f, %.1f, %.1f)", startPos.X, startPos.Y, startPos.Z))
	print(string.format("[BridgeSplineService] End: (%.1f, %.1f, %.1f)", endPos.X, endPos.Y, endPos.Z))
	
	-- Create folder
	local bridgeFolder = Instance.new("Folder")
	bridgeFolder.Name = "SuspensionBridge"
	bridgeFolder.Parent = parent
	self._bridgeFolder = bridgeFolder
	
	-- Generate control points
	local controlPoints = self:GenerateControlPoints(startPos, endPos, options)
	self._controlPoints = controlPoints
	
	if #controlPoints < 4 then
		warn("[BridgeSplineService] Not enough control points!")
		return nil
	end
	
	-- Generate smooth path
	local smoothPath = generateSmoothPath(controlPoints, CONFIG.SubdivisionsPerSegment)
	self._path = smoothPath
	print(string.format("[BridgeSplineService] Generated smooth path with %d points", #smoothPath))
	
	-- Calculate average deck height
	local deckHeight = (startPos.Y + endPos.Y) / 2
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- CREATE DECK (TRACK SEGMENTS)
	-- ═══════════════════════════════════════════════════════════════════════
	local deckFolder = Instance.new("Folder")
	deckFolder.Name = "Deck"
	deckFolder.Parent = bridgeFolder
	
	local segmentCount = 0
	for i = 1, #smoothPath - 1 do
		local segStart = smoothPath[i]
		local segEnd = smoothPath[i + 1]
		
		self:CreateTrackSegment(segStart, segEnd, {
			width = width,
			color = color,
			parent = deckFolder,
		})
		segmentCount = segmentCount + 1
	end
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- CREATE SUSPENSION BRIDGE ELEMENTS
	-- ═══════════════════════════════════════════════════════════════════════
	if CONFIG.SuspensionEnabled then
		local totalLength = (endPos - startPos).Magnitude
		local towerPositions = {}
		
		-- Calculate tower positions (evenly spaced along bridge)
		local towerCount = CONFIG.TowerCount
		for i = 1, towerCount do
			local t = i / (towerCount + 1)  -- Distribute towers evenly
			local towerPos = startPos:Lerp(endPos, t)
			table.insert(towerPositions, towerPos)
			
			-- Create tower
			print(string.format("[BridgeSplineService] Creating tower %d at t=%.2f", i, t))
			self:CreateTower(towerPos, deckHeight, {
				parent = bridgeFolder,
				width = width,
			})
		end
		
		-- Create anchorages at both ends
		print("[BridgeSplineService] Creating anchorages...")
		self:CreateAnchorage(startPos, Vector3.new(0, 0, 1), {
			parent = bridgeFolder,
			width = width,
		})
		self:CreateAnchorage(endPos, Vector3.new(0, 0, -1), {
			parent = bridgeFolder,
			width = width,
		})
		
		-- Create main cables (both sides)
		print("[BridgeSplineService] Creating main cables...")
		self:CreateMainCable(startPos, endPos, towerPositions, deckHeight, {
			parent = bridgeFolder,
			width = width,
			side = 1,  -- Right
		})
		self:CreateMainCable(startPos, endPos, towerPositions, deckHeight, {
			parent = bridgeFolder,
			width = width,
			side = -1,  -- Left
		})
		
		-- Create vertical hangers
		print("[BridgeSplineService] Creating vertical hangers...")
		self:CreateHangers(smoothPath, startPos, endPos, towerPositions, deckHeight, {
			parent = bridgeFolder,
			width = width,
		})
	end
	
	-- Create old-style rails if enabled
	self:CreateRails(smoothPath, {
		width = width,
		parent = bridgeFolder,
	})
	
	local totalLength = (endPos - startPos).Magnitude
	print(string.format("[BridgeSplineService] Suspension bridge complete! %d deck segments, %.0f studs", segmentCount, totalLength))
	
	return {
		folder = bridgeFolder,
		path = smoothPath,
		controlPoints = controlPoints,
		startPos = startPos,
		endPos = endPos,
		totalLength = totalLength,
		endTangent = (#smoothPath >= 2) and (smoothPath[#smoothPath] - smoothPath[#smoothPath - 1]).Unit or Vector3.new(0, 0, 1),
	}
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BridgeSplineService:GetPath()
	return self._path
end

function BridgeSplineService:GetControlPoints()
	return self._controlPoints
end

function BridgeSplineService:GetConfig()
	return CONFIG
end

function BridgeSplineService:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
	end
end

function BridgeSplineService:Cleanup()
	if self._bridgeFolder then
		self._bridgeFolder:Destroy()
		self._bridgeFolder = nil
	end
	self._path = nil
	self._controlPoints = nil
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function BridgeSplineService:KnitInit()
	print("[BridgeSplineService] Initializing...")
end

function BridgeSplineService:KnitStart()
	print("[BridgeSplineService] Started")
end

return BridgeSplineService

