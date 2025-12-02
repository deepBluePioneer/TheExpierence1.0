--[[
    WormController (PATH-BASED, SURFACE-AWARE FX + HIGHLIGHT)
    Giant worm that follows a parametric path using Heartbeat dt.
    Uses TweenService only for dirt / rock FX on the terrain surface.
    Adds a Highlight on the worm model so it’s easy to see.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local WormController = Knit.CreateController {
    Name = "WormController",
    _worms = {},
}

-- === CONFIGURATION ===
local WORM_CONFIG = {
    -- Worm body
    SegmentCount = 25,
    SegmentLength = 6,
    SegmentRadius = 4,
    HeadRadius = 6,
    TailTaper = 0.3,

    -- Colors
    BodyColor = Color3.fromRGB(120, 80, 60),
    HeadColor = Color3.fromRGB(90, 60, 40),

    -- Movement
    MoveSpeed = 60,              -- Studs per second
    PathExtendThreshold = 120,   -- When remaining path length < this, extend path

    -- Path generation
    TargetRadius = 200,
    MinTargetDistance = 80,
    MaxTargetDistance = 180,
    ArcHeight = 60,
    ArcHeightVariation = 15,
    GroundDepth = -50,           -- How far underground the tunnels go

    -- Spawning
    SpawnRadius = 150,

    -- FX placement (for dirt / rock formations)
    SurfaceSpawnOffset = 25,     -- how far in front of the head to spawn mounds/rocks
    SurfaceRaycastHeight = 200,
    SurfaceRaycastDepth = 1000,

    -- Dirt mound / rock effect
    DirtMound = {
        Enabled = true,
        RingRadius = 10,
        ChunkCount = 12,
        ChunkSizeMin = 2,
        ChunkSizeMax = 4,
        ChunkHeightMin = 1,
        ChunkHeightMax = 3,
        SprayVelocity = 15,
        LifeTime = 4,
        FadeTime = 1.5,
        Color = Color3.fromRGB(90, 70, 50),
        ColorVariation = 0.15,
    },

    -- Highlight overlay on the worm
    Highlight = {
        Enabled = true,
        FillColor = Color3.fromRGB(255, 255, 255),
        FillTransparency = 0.7,
        OutlineColor = Color3.fromRGB(255, 255, 0),
        OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    },
}

-- Cache raycast params
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.FilterDescendantsInstances = {}

-- === HELPER: RAYCAST FILTER SETUP ===

local function updateRaycastFilter()
    local excludeList = {}

    local wormsFolder = Workspace:FindFirstChild("Worms")
    if wormsFolder then
        table.insert(excludeList, wormsFolder)
    end

    local debugFolder = Workspace:FindFirstChild("ExclusionZoneDebug")
    if debugFolder then
        table.insert(excludeList, debugFolder)
    end

    local dirtFolder = Workspace:FindFirstChild("WormDirt")
    if dirtFolder then
        table.insert(excludeList, dirtFolder)
    end

    raycastParams.FilterDescendantsInstances = excludeList
end

-- === HELPER: GROUND SAMPLING ===

local function getGroundHeight(x, z)
    updateRaycastFilter()

    local result = Workspace:Raycast(
        Vector3.new(x, 500, z),
        Vector3.new(0, -1000, 0),
        raycastParams
    )

    return result and result.Position.Y or 0
end

local function getRandomTerrainSpot(fromX, fromZ)
    local baseplate = Workspace:FindFirstChild("Baseplate")
    local maxRadius = baseplate and math.min(WORM_CONFIG.TargetRadius, baseplate.Size.X / 2 - 20)
        or WORM_CONFIG.TargetRadius

    local angle = math.random() * math.pi * 2
    local distance = WORM_CONFIG.MinTargetDistance
        + math.random() * (WORM_CONFIG.MaxTargetDistance - WORM_CONFIG.MinTargetDistance)

    local targetX = math.clamp(fromX + math.cos(angle) * distance, -maxRadius, maxRadius)
    local targetZ = math.clamp(fromZ + math.sin(angle) * distance, -maxRadius, maxRadius)

    return Vector3.new(targetX, getGroundHeight(targetX, targetZ) + WORM_CONFIG.GroundDepth, targetZ)
end

-- Get the surface point *ahead* of the head along its forward direction
local function getSurfaceAhead(headPos, forwardDir)
    updateRaycastFilter()

    -- Flatten to horizontal plane so we don't shoot up/down
    local horiz = Vector3.new(forwardDir.X, 0, forwardDir.Z)
    if horiz.Magnitude < 0.001 then
        horiz = Vector3.new(0, 0, -1) -- fallback direction
    end
    horiz = horiz.Unit

    local offsetPos = headPos + horiz * WORM_CONFIG.SurfaceSpawnOffset

    -- Ray from above that point down to find actual surface
    local origin = offsetPos + Vector3.new(0, WORM_CONFIG.SurfaceRaycastHeight, 0)
    local direction = Vector3.new(0, -WORM_CONFIG.SurfaceRaycastDepth, 0)

    local result = Workspace:Raycast(origin, direction, raycastParams)
    if result then
        return result.Position
    else
        -- Fallback to vertical ground sample if nothing hit
        local gy = getGroundHeight(offsetPos.X, offsetPos.Z)
        return Vector3.new(offsetPos.X, gy, offsetPos.Z)
    end
end

-- === DIRT / ROCK MOUND EFFECTS ===

local dirtMoundsFolder = nil

local function getDirtFolder()
    if not dirtMoundsFolder or not dirtMoundsFolder.Parent then
        dirtMoundsFolder = Workspace:FindFirstChild("WormDirt") or Instance.new("Folder", Workspace)
        dirtMoundsFolder.Name = "WormDirt"
    end
    return dirtMoundsFolder
end

local function createDirtMound(position)
    if not WORM_CONFIG.DirtMound.Enabled then return end

    local config = WORM_CONFIG.DirtMound
    local folder = getDirtFolder()

    local groundY = getGroundHeight(position.X, position.Z)
    local groundPos = Vector3.new(position.X, groundY, position.Z)

    local chunks = {}

    for i = 1, config.ChunkCount do
        local angle = (i / config.ChunkCount) * math.pi * 2
        angle = angle + (math.random() - 0.5) * 0.5

        local ringRadius = config.RingRadius + (math.random() - 0.5) * 3
        local offsetX = math.cos(angle) * ringRadius
        local offsetZ = math.sin(angle) * ringRadius

        local chunk = Instance.new("Part")
        chunk.Name = "DirtChunk"

        local size = config.ChunkSizeMin + math.random() * (config.ChunkSizeMax - config.ChunkSizeMin)
        chunk.Size = Vector3.new(
            size * (0.8 + math.random() * 0.4),
            size * (0.5 + math.random() * 0.5),
            size * (0.8 + math.random() * 0.4)
        )

        local variation = config.ColorVariation
        local r = math.clamp(config.Color.R + (math.random() - 0.5) * variation, 0, 1)
        local g = math.clamp(config.Color.G + (math.random() - 0.5) * variation, 0, 1)
        local b = math.clamp(config.Color.B + (math.random() - 0.5) * variation, 0, 1)
        chunk.Color = Color3.new(r, g, b)

        chunk.Material = Enum.Material.Sand
        chunk.Anchored = true
        chunk.CanCollide = false
        chunk.CastShadow = false

        local startHeight = config.ChunkHeightMin
            + math.random() * (config.ChunkHeightMax - config.ChunkHeightMin)
        local chunkPos = groundPos + Vector3.new(offsetX, startHeight, offsetZ)

        chunk.CFrame = CFrame.new(chunkPos) * CFrame.Angles(
            math.random() * math.pi,
            math.random() * math.pi,
            math.random() * math.pi
        )

        chunk.Parent = folder
        table.insert(chunks, chunk)
    end

    task.spawn(function()
        local sprayTime = 0.3
        local settleTime = 0.5

        -- Spray outward
        for _, chunk in ipairs(chunks) do
            local startPos = chunk.Position
            local outwardDir = (Vector3.new(startPos.X, groundY, startPos.Z) - groundPos).Unit
            local targetPos = startPos
                + outwardDir * config.SprayVelocity * 0.3
                + Vector3.new(0, math.random() * 2, 0)

            local sprayTween = TweenService:Create(
                chunk,
                TweenInfo.new(sprayTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Position = targetPos }
            )
            sprayTween:Play()
        end

        task.wait(sprayTime)

        -- Settle onto ground
        for _, chunk in ipairs(chunks) do
            local settlePos = Vector3.new(chunk.Position.X, groundY + chunk.Size.Y / 2, chunk.Position.Z)
            local settleTween = TweenService:Create(
                chunk,
                TweenInfo.new(settleTime, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
                { Position = settlePos }
            )
            settleTween:Play()
        end

        task.wait(config.LifeTime - config.FadeTime)

        -- Fade out
        for _, chunk in ipairs(chunks) do
            local fadeTween = TweenService:Create(
                chunk,
                TweenInfo.new(config.FadeTime, Enum.EasingStyle.Linear),
                { Transparency = 1 }
            )
            fadeTween:Play()
        end

        task.wait(config.FadeTime + 0.1)

        for _, chunk in ipairs(chunks) do
            chunk:Destroy()
        end
    end)
end

-- === PATH UTILS ===

-- Replace your existing buildArcPath with this:

local function buildArcPath(fromPos, toPos)
    -- Smooth sinusoidal arch:
    --  - baseline = underground tunnel (groundY + GroundDepth)
    --  - peak = groundY + ArcHeight (above surface)
    -- The worm smoothly goes: underground -> peak -> underground.

    -- Randomize arc height slightly per segment
    local arcHeight = WORM_CONFIG.ArcHeight
        + (math.random() - 0.5) * WORM_CONFIG.ArcHeightVariation * 2

    -- More steps = smoother curve
    local steps = 16  -- you can push this to 20 if you want ultra smooth

    local points = {}

    for i = 0, steps do
        local t = i / steps

        -- Interpolate XZ linearly between start and end
        local px = fromPos.X + (toPos.X - fromPos.X) * t
        local pz = fromPos.Z + (toPos.Z - fromPos.Z) * t

        local groundY = getGroundHeight(px, pz)

        -- Underground baseline (GroundDepth is negative in your config)
        local baseY = groundY + WORM_CONFIG.GroundDepth

        -- Desired peak height above ground
        local peakY = groundY + arcHeight

        -- Amplitude of the hump from baseline to peak
        local amplitude = peakY - baseY

        -- Smooth hump: 0 -> 1 -> 0 with continuous slope
        local hump = math.sin(t * math.pi) -- 0 at ends, 1 at center

        local y = baseY + hump * amplitude

        points[#points + 1] = Vector3.new(px, y, pz)
    end

    return points
end



local function computePathLengths(points, existingPoints, existingLengths)
    local pathPoints = existingPoints or {}
    local lengths = existingLengths or {}

    local startIndex = 1
    if #pathPoints > 0 and (pathPoints[#pathPoints] - points[1]).Magnitude < 0.001 then
        startIndex = 2 -- skip duplicate connection point
    end

    for i = startIndex, #points do
        table.insert(pathPoints, points[i])
        local idx = #pathPoints
        if idx > 1 then
            local segLen = (pathPoints[idx] - pathPoints[idx - 1]).Magnitude
            table.insert(lengths, segLen)
        end
    end

    local total = 0
    for _, segLen in ipairs(lengths) do
        total += segLen
    end

    return pathPoints, lengths, total
end

local function getPositionAtDistance(pathPoints, segLengths, distance)
    if distance <= 0 then
        return pathPoints[1]
    end

    local remaining = distance
    for i, segLen in ipairs(segLengths) do
        if remaining <= segLen then
            local t = remaining / segLen
            local a = pathPoints[i]
            local b = pathPoints[i + 1]
            return a:Lerp(b, t)
        else
            remaining -= segLen
        end
    end

    return pathPoints[#pathPoints]
end

-- === WORM CREATION ===

local function createHighlightForWorm(wormModel)
    local cfg = WORM_CONFIG.Highlight
    if not cfg.Enabled then
        return nil
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "WormHighlight"
    highlight.Adornee = wormModel
    highlight.Parent = wormModel

    highlight.FillColor = cfg.FillColor
    highlight.FillTransparency = cfg.FillTransparency
    highlight.OutlineColor = cfg.OutlineColor
    highlight.OutlineTransparency = cfg.OutlineTransparency
    highlight.DepthMode = cfg.DepthMode

    return highlight
end

local function createWorm(name)
    local folder = Workspace:FindFirstChild("Worms") or Instance.new("Folder", Workspace)
    folder.Name = "Worms"

    local wormModel = Instance.new("Model")
    wormModel.Name = name or "SandWorm"
    wormModel.Parent = folder

    local segments = {}

    for i = 1, WORM_CONFIG.SegmentCount do
        local segment = Instance.new("Part")
        segment.Name = "Segment_" .. i
        segment.Shape = Enum.PartType.Cylinder

        local taperFactor = 1
        if i == 1 then
            taperFactor = WORM_CONFIG.HeadRadius / WORM_CONFIG.SegmentRadius
        elseif i > WORM_CONFIG.SegmentCount * 0.6 then
            local tailProgress = (i - WORM_CONFIG.SegmentCount * 0.6) / (WORM_CONFIG.SegmentCount * 0.4)
            taperFactor = 1 - (1 - WORM_CONFIG.TailTaper) * tailProgress
        end

        local radius = WORM_CONFIG.SegmentRadius * taperFactor
        segment.Size = Vector3.new(WORM_CONFIG.SegmentLength, radius * 2, radius * 2)
        segment.Color = i == 1 and WORM_CONFIG.HeadColor or WORM_CONFIG.BodyColor
        segment.Material = Enum.Material.Sand
        segment.Anchored = true
        segment.CanCollide = false
        segment.CastShadow = false
        segment.Parent = wormModel

        segments[i] = segment
    end

    wormModel.PrimaryPart = segments[1]

    local highlight = createHighlightForWorm(wormModel)

    return {
        model = wormModel,
        segments = segments,
        highlight = highlight,

        -- Path data
        pathPoints = {},
        segLengths = {},
        totalLength = 0,

        -- Head
        headDistance = 0,

        -- Ground crossing detection
        lastHeadY = nil,
        lastGroundY = nil,
        wasUnderground = true,

        -- Cached segment distances/positions
        segmentDistances = {},
        segmentPositions = {},

        active = true,
    }
end

-- === UPDATE LOOP ===

local function extendPathIfNeeded(wormData)
    local remaining = wormData.totalLength - wormData.headDistance
    if remaining > WORM_CONFIG.PathExtendThreshold then
        return
    end

    local lastPos = wormData.pathPoints[#wormData.pathPoints]
    local endPos = getRandomTerrainSpot(lastPos.X, lastPos.Z)
    local arcPoints = buildArcPath(lastPos, endPos)

    wormData.pathPoints, wormData.segLengths, wormData.totalLength =
        computePathLengths(arcPoints, wormData.pathPoints, wormData.segLengths)
end

local function updateWorm(wormData, dt)
    if not wormData.active then return end
    if #wormData.pathPoints < 2 then return end

    -- Move head along path
    wormData.headDistance += WORM_CONFIG.MoveSpeed * dt
    if wormData.headDistance > wormData.totalLength then
        wormData.headDistance = wormData.totalLength
    end

    extendPathIfNeeded(wormData)

    local headPos = getPositionAtDistance(
        wormData.pathPoints,
        wormData.segLengths,
        wormData.headDistance
    )

    -- Forward direction from path (for orientation & FX placement)
    local spacing = WORM_CONFIG.SegmentLength * 0.85
    local aheadDist = wormData.headDistance + spacing * 0.4
    local aheadPos = getPositionAtDistance(
        wormData.pathPoints,
        wormData.segLengths,
        aheadDist
    )
    local pathDir = (aheadPos - headPos)
    local forwardDir = pathDir.Magnitude > 0.001 and pathDir.Unit or Vector3.new(0, 0, -1)

    -- Ground crossing & FX
    local groundY = getGroundHeight(headPos.X, headPos.Z)
    local isUnderground = headPos.Y < groundY

    if wormData.lastHeadY ~= nil then
        local wasUnder = wormData.wasUnderground

        if wasUnder ~= isUnderground then
            -- Crossing surface -> spawn dirt/rock FX on the terrain *ahead* of the head
            local surfacePos = getSurfaceAhead(headPos, forwardDir)
            createDirtMound(surfacePos)
        end
    end

    wormData.lastHeadY = headPos.Y
    wormData.lastGroundY = groundY
    wormData.wasUnderground = isUnderground

    -- Segment distances (fixed spacing behind head)
    for i = 1, #wormData.segments do
        local d = wormData.headDistance - (i - 1) * spacing
        if d < 0 then
            d = 0
        end
        wormData.segmentDistances[i] = d
        wormData.segmentPositions[i] = getPositionAtDistance(
            wormData.pathPoints,
            wormData.segLengths,
            d
        )
    end

    -- Apply positions & orientation
    for i, segment in ipairs(wormData.segments) do
        local pos = wormData.segmentPositions[i]
        if pos then
            local lookTarget
            if i == 1 then
                -- Head looks forward along path
                lookTarget = pos + forwardDir
            else
                lookTarget = wormData.segmentPositions[i - 1]
            end

            if lookTarget and (lookTarget - pos).Magnitude > 0.01 then
                local dir = (lookTarget - pos).Unit
                local cf = CFrame.lookAt(pos, pos + dir)
                -- Cylinders are aligned along X axis, rotate to align with path
                segment.CFrame = cf * CFrame.Angles(0, math.rad(90), 0)
            else
                segment.Position = pos
            end
        end
    end
end

-- === PUBLIC API ===

function WormController:SpawnWorm(x, z, name)
    x = x or math.random(-WORM_CONFIG.SpawnRadius, WORM_CONFIG.SpawnRadius)
    z = z or math.random(-WORM_CONFIG.SpawnRadius, WORM_CONFIG.SpawnRadius)

    local groundY = getGroundHeight(x, z)
    local startPos = Vector3.new(x, groundY + WORM_CONFIG.GroundDepth, z)

    local wormData = createWorm(name)
    table.insert(self._worms, wormData)

    -- Initial path: from underground start to first random target
    local endPos = getRandomTerrainSpot(startPos.X, startPos.Z)
    local initialPoints = buildArcPath(startPos, endPos)
    wormData.pathPoints, wormData.segLengths, wormData.totalLength =
        computePathLengths(initialPoints)

    -- Start head at beginning of path
    wormData.headDistance = 0
    local headPos = getPositionAtDistance(
        wormData.pathPoints,
        wormData.segLengths,
        wormData.headDistance
    )

    -- Initialize segment positions
    wormData.segmentDistances = {}
    wormData.segmentPositions = {}
    local spacing = WORM_CONFIG.SegmentLength * 0.85

    for i = 1, #wormData.segments do
        local d = wormData.headDistance - (i - 1) * spacing
        if d < 0 then
            d = 0
        end
        wormData.segmentDistances[i] = d
        wormData.segmentPositions[i] = getPositionAtDistance(
            wormData.pathPoints,
            wormData.segLengths,
            d
        )
        wormData.segments[i].Position = wormData.segmentPositions[i]
    end

    print(string.format(
        "[WormController] Spawned '%s' at (%.0f, %.0f)",
        name or "SandWorm",
        x, z
    ))

    return wormData
end

function WormController:RemoveWorm(wormData)
    for i, w in ipairs(self._worms) do
        if w == wormData then
            w.active = false
            if w.model then
                w.model:Destroy()
            end
            table.remove(self._worms, i)
            break
        end
    end
end

function WormController:SetSpeed(speed)
    WORM_CONFIG.MoveSpeed = speed
end

function WormController:SetHighlightEnabled(enabled)
    WORM_CONFIG.Highlight.Enabled = enabled and true or false
    for _, wormData in ipairs(self._worms) do
        if wormData.highlight then
            wormData.highlight.Enabled = WORM_CONFIG.Highlight.Enabled
        end
    end
end

-- === KNIT LIFECYCLE ===

function WormController:KnitInit()
    print("[WormController] Initializing (path-based, surface-aware FX + highlight)...")
end

function WormController:KnitStart()
    local lastTime = os.clock()

    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        local dt = now - lastTime
        lastTime = now

        for _, wormData in ipairs(self._worms) do
            updateWorm(wormData, dt)
        end
    end)

    print("[WormController] Started")

    -- Test spawn
    task.delay(5, function()
        local baseplate = Workspace:FindFirstChild("Baseplate")
        local cx = baseplate and baseplate.Position.X or 0
        local cz = baseplate and baseplate.Position.Z or 0
        self:SpawnWorm(
            cx + (math.random() - 0.5) * 100,
            cz + (math.random() - 0.5) * 100,
            "SandWorm_1"
        )
    end)
end

return WormController
