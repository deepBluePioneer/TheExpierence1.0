--[[
	RollerCoasterTrackService
	
	Generates roller coaster track geometry along spline paths.
	Creates rails, cross ties, spine, and support structures.
	
	Automatically generates tracks on startup for any folders named:
	- spline_# (e.g., spline_1, spline_2)
	- coaster_# (e.g., coaster_1)
	- track_# (e.g., track_1)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local CatmullRomSpline = require(CustomPackages.Splines.CatmullRomSpline)

local RollerCoasterTrackService = Knit.CreateService({
	Name = "RollerCoasterTrackService",
	Client = {
		TrackGenerated = Knit.CreateSignal(),
	},
})

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              CONFIGURATION                                  ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Rail Settings
	RailWidth = 0.4,
	RailHeight = 0.4,
	RailSeparation = 3,
	RailMaterial = Enum.Material.Metal,
	RailColor = Color3.fromRGB(180, 40, 40),
	
	-- Cross Tie Settings
	TieWidth = 0.3,
	TieHeight = 0.2,
	TieSpacing = 2,
	TieMaterial = Enum.Material.Metal,
	TieColor = Color3.fromRGB(60, 60, 65),
	
	-- Spine Settings
	SpineWidth = 0.6,
	SpineHeight = 0.6,
	SpineOffset = -0.5,
	SpineMaterial = Enum.Material.Metal,
	SpineColor = Color3.fromRGB(45, 45, 50),
	
	-- Support Settings
	SupportSpacing = 20,
	SupportWidth = 1.2,
	SupportMinHeight = 5,
	SupportMaterial = Enum.Material.Metal,
	SupportColor = Color3.fromRGB(80, 80, 85),
	SupportBaseSize = Vector3.new(4, 1, 4),
	SupportBaseMaterial = Enum.Material.Concrete,
	SupportBaseColor = Color3.fromRGB(140, 140, 140),
	
	-- Generation Settings
	SegmentLength = 1,
	SplineTension = 0.5,
	GroundLevel = 0,
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                              STATE                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local generatedTracks = {}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         TRACK GENERATION                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Main function to generate a complete track from a folder of control points
function RollerCoasterTrackService:GenerateTrack(folderName: string)
	print(string.format("[RollerCoasterTrack] Generating track from folder: %s", folderName))
	
	-- Find the folder
	local folder = Workspace:FindFirstChild(folderName)
	if not folder then
		warn("[RollerCoasterTrack] Folder not found:", folderName)
		return nil
	end
	
	-- Get and sort control points
	local pointData = {}
	for _, child in ipairs(folder:GetChildren()) do
		local pointNumber = child:GetAttribute("pointNumber")
		if pointNumber and child:IsA("BasePart") then
			table.insert(pointData, {
				part = child,
				number = pointNumber,
			})
		end
	end
	
	table.sort(pointData, function(a, b)
		return a.number < b.number
	end)
	
	if #pointData < 4 then
		warn("[RollerCoasterTrack] Need at least 4 control points, found:", #pointData)
		return nil
	end
	
	-- Extract parts for spline
	local controlParts = {}
	for _, data in ipairs(pointData) do
		table.insert(controlParts, data.part)
	end
	
	-- Create spline
	local spline = CatmullRomSpline.new(controlParts, CONFIG.SplineTension)
	local splineLength = spline.Length
	print(string.format("[RollerCoasterTrack] Spline created with %d points, length: %.2f studs", #controlParts, splineLength))
	
	-- Remove existing track if present
	if generatedTracks[folderName] then
		if generatedTracks[folderName].folder then
			generatedTracks[folderName].folder:Destroy()
		end
		generatedTracks[folderName] = nil
	end
	
	-- Create track folder structure
	local trackFolder = Instance.new("Folder")
	trackFolder.Name = "RollerCoasterTrack_" .. folderName
	
	local railsFolder = Instance.new("Folder")
	railsFolder.Name = "Rails"
	railsFolder.Parent = trackFolder
	
	local tiesFolder = Instance.new("Folder")
	tiesFolder.Name = "CrossTies"
	tiesFolder.Parent = trackFolder
	
	local spineFolder = Instance.new("Folder")
	spineFolder.Name = "Spine"
	spineFolder.Parent = trackFolder
	
	local supportsFolder = Instance.new("Folder")
	supportsFolder.Name = "Supports"
	supportsFolder.Parent = trackFolder
	
	-- Calculate number of segments
	local numSegments = math.ceil(splineLength / CONFIG.SegmentLength)
	local worldUp = Vector3.new(0, 1, 0)
	local railHalfSep = CONFIG.RailSeparation / 2
	
	-- Generate all track points first
	local trackPoints = {}
	
	for i = 0, numSegments do
		local t = i / numSegments
		local position = spline:CalculatePositionRelativeToLength(t)
		local derivative = spline:CalculateDerivativeRelativeToLength(t)
		local forward = derivative.Unit
		
		-- Calculate right vector
		local right = forward:Cross(worldUp)
		if right.Magnitude < 0.1 then
			right = Vector3.new(1, 0, 0)
		end
		right = right.Unit
		
		-- Calculate up vector
		local up = right:Cross(forward).Unit
		
		table.insert(trackPoints, {
			position = position,
			forward = forward,
			right = right,
			up = up,
		})
	end
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- CREATE RAILS AND SPINE
	-- ═══════════════════════════════════════════════════════════════════════
	
	for i = 1, #trackPoints - 1 do
		local current = trackPoints[i]
		local nextPoint = trackPoints[i + 1]
		local avgUp = (current.up + nextPoint.up).Unit
		
		-- LEFT RAIL
		local leftStart = current.position - current.right * railHalfSep
		local leftEnd = nextPoint.position - nextPoint.right * railHalfSep
		local leftDirection = leftEnd - leftStart
		local leftLength = leftDirection.Magnitude
		
		if leftLength > 0.01 then
			local leftRail = Instance.new("Part")
			leftRail.Name = "LeftRail_" .. i
			leftRail.Size = Vector3.new(CONFIG.RailWidth, CONFIG.RailHeight, leftLength * 1.02)
			leftRail.Material = CONFIG.RailMaterial
			leftRail.Color = CONFIG.RailColor
			leftRail.Anchored = true
			leftRail.CanCollide = true
			leftRail.CastShadow = true
			leftRail.CFrame = CFrame.lookAt(
				(leftStart + leftEnd) / 2,
				(leftStart + leftEnd) / 2 + leftDirection.Unit,
				avgUp
			)
			leftRail.Parent = railsFolder
		end
		
		-- RIGHT RAIL
		local rightStart = current.position + current.right * railHalfSep
		local rightEnd = nextPoint.position + nextPoint.right * railHalfSep
		local rightDirection = rightEnd - rightStart
		local rightLength = rightDirection.Magnitude
		
		if rightLength > 0.01 then
			local rightRail = Instance.new("Part")
			rightRail.Name = "RightRail_" .. i
			rightRail.Size = Vector3.new(CONFIG.RailWidth, CONFIG.RailHeight, rightLength * 1.02)
			rightRail.Material = CONFIG.RailMaterial
			rightRail.Color = CONFIG.RailColor
			rightRail.Anchored = true
			rightRail.CanCollide = true
			rightRail.CastShadow = true
			rightRail.CFrame = CFrame.lookAt(
				(rightStart + rightEnd) / 2,
				(rightStart + rightEnd) / 2 + rightDirection.Unit,
				avgUp
			)
			rightRail.Parent = railsFolder
		end
		
		-- SPINE (center beam)
		local spineStart = current.position + current.up * CONFIG.SpineOffset
		local spineEnd = nextPoint.position + nextPoint.up * CONFIG.SpineOffset
		local spineDirection = spineEnd - spineStart
		local spineLength = spineDirection.Magnitude
		
		if spineLength > 0.01 then
			local spinePart = Instance.new("Part")
			spinePart.Name = "Spine_" .. i
			spinePart.Size = Vector3.new(CONFIG.SpineWidth, CONFIG.SpineHeight, spineLength * 1.02)
			spinePart.Material = CONFIG.SpineMaterial
			spinePart.Color = CONFIG.SpineColor
			spinePart.Anchored = true
			spinePart.CanCollide = false
			spinePart.CastShadow = true
			spinePart.CFrame = CFrame.lookAt(
				(spineStart + spineEnd) / 2,
				(spineStart + spineEnd) / 2 + spineDirection.Unit,
				avgUp
			)
			spinePart.Parent = spineFolder
		end
	end
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- CREATE CROSS TIES
	-- ═══════════════════════════════════════════════════════════════════════
	
	local totalDistance = 0
	local nextTieDistance = 0
	local tieIndex = 0
	
	for i = 1, #trackPoints do
		local current = trackPoints[i]
		
		if totalDistance >= nextTieDistance then
			tieIndex = tieIndex + 1
			
			local tie = Instance.new("Part")
			tie.Name = "CrossTie_" .. tieIndex
			tie.Size = Vector3.new(CONFIG.RailSeparation + CONFIG.RailWidth, CONFIG.TieHeight, CONFIG.TieWidth)
			tie.Material = CONFIG.TieMaterial
			tie.Color = CONFIG.TieColor
			tie.Anchored = true
			tie.CanCollide = false
			tie.CastShadow = true
			
			local tiePosition = current.position - current.up * (CONFIG.RailHeight / 2 + CONFIG.TieHeight / 2)
			tie.CFrame = CFrame.fromMatrix(tiePosition, current.right, current.up, -current.forward)
			tie.Parent = tiesFolder
			
			nextTieDistance = nextTieDistance + CONFIG.TieSpacing
		end
		
		if i < #trackPoints then
			totalDistance = totalDistance + (trackPoints[i + 1].position - current.position).Magnitude
		end
	end
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- CREATE SUPPORTS
	-- ═══════════════════════════════════════════════════════════════════════
	
	local totalSupportDistance = 0
	local nextSupportDistance = 0
	local supportIndex = 0
	
	for i = 1, #trackPoints do
		local current = trackPoints[i]
		
		if totalSupportDistance >= nextSupportDistance then
			local trackHeight = current.position.Y
			local supportHeight = trackHeight - CONFIG.GroundLevel - CONFIG.SupportBaseSize.Y
			
			if supportHeight >= CONFIG.SupportMinHeight then
				supportIndex = supportIndex + 1
				
				local supportModel = Instance.new("Model")
				supportModel.Name = "Support_" .. supportIndex
				
				-- Base pad
				local basePart = Instance.new("Part")
				basePart.Name = "Base"
				basePart.Size = CONFIG.SupportBaseSize
				basePart.Material = CONFIG.SupportBaseMaterial
				basePart.Color = CONFIG.SupportBaseColor
				basePart.Anchored = true
				basePart.CanCollide = true
				basePart.Position = Vector3.new(
					current.position.X,
					CONFIG.GroundLevel + CONFIG.SupportBaseSize.Y / 2,
					current.position.Z
				)
				basePart.Parent = supportModel
				
				-- Column
				local columnPart = Instance.new("Part")
				columnPart.Name = "Column"
				columnPart.Size = Vector3.new(CONFIG.SupportWidth, supportHeight, CONFIG.SupportWidth)
				columnPart.Material = CONFIG.SupportMaterial
				columnPart.Color = CONFIG.SupportColor
				columnPart.Anchored = true
				columnPart.CanCollide = true
				columnPart.Position = Vector3.new(
					current.position.X,
					CONFIG.GroundLevel + CONFIG.SupportBaseSize.Y + supportHeight / 2,
					current.position.Z
				)
				columnPart.Parent = supportModel
				
				-- Top cap
				local topPart = Instance.new("Part")
				topPart.Name = "Top"
				topPart.Size = Vector3.new(CONFIG.SupportWidth * 2, 0.5, CONFIG.SupportWidth * 2)
				topPart.Material = CONFIG.SupportMaterial
				topPart.Color = CONFIG.SupportColor
				topPart.Anchored = true
				topPart.CanCollide = false
				topPart.Position = Vector3.new(
					current.position.X,
					current.position.Y - 1,
					current.position.Z
				)
				topPart.Parent = supportModel
				
				supportModel.Parent = supportsFolder
			end
			
			nextSupportDistance = nextSupportDistance + CONFIG.SupportSpacing
		end
		
		if i < #trackPoints then
			totalSupportDistance = totalSupportDistance + (trackPoints[i + 1].position - current.position).Magnitude
		end
	end
	
	-- Parent the track folder to workspace
	trackFolder.Parent = Workspace
	
	-- Store track data
	generatedTracks[folderName] = {
		folder = trackFolder,
		spline = spline,
		length = splineLength,
		pointCount = #trackPoints,
	}
	
	-- Print results
	local railCount = #railsFolder:GetChildren()
	local tieCount = #tiesFolder:GetChildren()
	local spineCount = #spineFolder:GetChildren()
	local supportCount = #supportsFolder:GetChildren()
	
	print("[RollerCoasterTrack] ✓ Track generated successfully!")
	print(string.format("  └─ Rails: %d", railCount))
	print(string.format("  └─ CrossTies: %d", tieCount))
	print(string.format("  └─ Spine: %d", spineCount))
	print(string.format("  └─ Supports: %d", supportCount))
	
	-- Fire client signal
	self.Client.TrackGenerated:FireAll(folderName, splineLength)
	
	return generatedTracks[folderName]
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function RollerCoasterTrackService:GetTrack(trackName: string)
	return generatedTracks[trackName]
end

function RollerCoasterTrackService:GetAllTrackNames()
	local names = {}
	for name in pairs(generatedTracks) do
		table.insert(names, name)
	end
	return names
end

function RollerCoasterTrackService:RemoveTrack(trackName: string)
	local trackData = generatedTracks[trackName]
	if trackData and trackData.folder then
		trackData.folder:Destroy()
		generatedTracks[trackName] = nil
		print("[RollerCoasterTrack] Removed track:", trackName)
		return true
	end
	return false
end

function RollerCoasterTrackService:ClearAllTracks()
	for trackName, trackData in pairs(generatedTracks) do
		if trackData.folder then
			trackData.folder:Destroy()
		end
	end
	generatedTracks = {}
	print("[RollerCoasterTrack] Cleared all tracks")
end

function RollerCoasterTrackService:GetSpline(trackName: string)
	local trackData = generatedTracks[trackName]
	if trackData then
		return trackData.spline
	end
	return nil
end

function RollerCoasterTrackService:GetTrackLength(trackName: string)
	local trackData = generatedTracks[trackName]
	if trackData then
		return trackData.length
	end
	return nil
end

function RollerCoasterTrackService:GetConfig()
	return CONFIG
end

function RollerCoasterTrackService:UpdateConfig(key: string, value: any)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
		return true
	end
	return false
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CLIENT METHODS                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function RollerCoasterTrackService.Client:GetTrackNames(player)
	return RollerCoasterTrackService:GetAllTrackNames()
end

function RollerCoasterTrackService.Client:GetTrackLength(player, trackName: string)
	return RollerCoasterTrackService:GetTrackLength(trackName)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function RollerCoasterTrackService:KnitInit()
	print("[RollerCoasterTrack] Initializing...")
end

function RollerCoasterTrackService:KnitStart()
	print("[RollerCoasterTrack] Starting...")
	
	-- Generate tracks on startup
	task.spawn(function()
		-- Wait for workspace to be ready
		task.wait(2)
		
		print("[RollerCoasterTrack] Scanning workspace for track folders...")
		
		local tracksGenerated = 0
		
		-- Find all valid folders
		for _, child in ipairs(Workspace:GetChildren()) do
			if child:IsA("Folder") then
				local name = child.Name
				
				-- Check for valid naming patterns
				if name:match("^spline_%d+$") or name:match("^coaster_%d+$") or name:match("^track_%d+$") then
					print("[RollerCoasterTrack] Found folder:", name)
					
					local success, result = pcall(function()
						return self:GenerateTrack(name)
					end)
					
					if success and result then
						tracksGenerated = tracksGenerated + 1
					else
						warn("[RollerCoasterTrack] Failed to generate track for:", name)
						if not success then
							warn("  Error:", tostring(result))
						end
					end
				end
			end
		end
		
		print(string.format("[RollerCoasterTrack] ✓ Startup complete! Generated %d track(s)", tracksGenerated))
	end)
	
	print("[RollerCoasterTrack] Ready")
end

return RollerCoasterTrackService
