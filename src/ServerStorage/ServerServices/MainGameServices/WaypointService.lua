-- Services/WaypointService.lua
-- Generates and indexes waypoint voxels from producer parts (e.g., bridge-top plates).
-- 1) Generation: For each BasePart tagged with <producerTag>, build a voxel grid on its top face.
-- 2) Indexing:   All produced voxels are tagged <outputTag> and queryable (random / nearest / etc).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Packages            = ReplicatedStorage:WaitForChild("Packages")
local Knit                = require(Packages.Knit)
local CollectionService   = game:GetService("CollectionService")
local RunService          = game:GetService("RunService")

local WaypointService = Knit.CreateService {
    Name = "WaypointService",
    Client = {},
}

-- =================== TYPES / STATE ===================

-- How to build voxels on top of producer parts
type ProducerConfig = {
    -- voxel layout
    partSize: Vector3?,       -- size of each waypoint voxel (default: 1x1x1)
    gap: number?,             -- spacing between voxels (default: 5)
    inset: number?,           -- inner margin to keep away from edges (default: partSize.X/2, partSize.Z/2)
    yOnTopOffset: number?,    -- extra Y offset above the producer top (default: 0)
    alignToTopFace: boolean?, -- always put the grid on the top interior layer (default: true)

    -- voxel visuals
    color: Color3?,           -- default: Color3.fromRGB(255,170,0)
    material: Enum.Material?, -- default: Plastic
    transparency: number?,    -- default: 0.5
    anchored: boolean?,       -- default: true
    canCollide: boolean?,     -- default: false

    -- output & parenting
    outputTag: string?,       -- tag added to every voxel (default: "waypointPart")
    groupFolderName: string?, -- child folder created alongside producer.Parent to hold voxels (default: "WaypointGrids")
    parentStrategy: "siblingFolder" | "underProducer" | "underContainer"?,
        -- siblingFolder: create/find <groupFolderName> under producer.Parent
        -- underProducer: parent voxels directly under the producer instance
        -- underContainer: parent voxels under a service-managed top-level folder in Workspace
}

type Waypoint = { part: BasePart, pos: Vector3, cf: CFrame }

-- Internal structures
type ProducerState = {
    cfg: ProducerConfig,
    conns: { RBXScriptConnection },
    producedBySource: { [BasePart]: { Instance } }, -- sourcePart -> array of voxels
}

type TagIndex = {
    conns: { RBXScriptConnection },
    list: { Waypoint },
    byPart: { [BasePart]: Waypoint },
    filterAncestor: Instance?,   -- optional restriction (container)
    requireAnchored: boolean?,   -- optional filter
}

-- Maps for production + indexing
local _producers: { [string]: ProducerState } = {} -- producerTag -> ProducerState
local _indices:   { [string]: TagIndex }     = {} -- outputTag   -> TagIndex

-- Service-level folder for "underContainer" parenting
local _serviceContainer: Folder? = nil

-- =================== DEFAULTS ===================

local DEFAULT_PRODUCER: ProducerConfig = {
    partSize = Vector3.new(1, 1, 1),
    gap = 5,
    inset = nil,               -- computed from partSize at build
    yOnTopOffset = 0,
    alignToTopFace = true,

    color = Color3.fromRGB(255, 170, 0),
    material = Enum.Material.Plastic,
    transparency = 0.5,
    anchored = true,
    canCollide = false,

    outputTag = "waypointPart",
    groupFolderName = "WaypointGrids",
    parentStrategy = "siblingFolder",
}

-- =================== UTIL ===================

local function deepCopyCfg(cfg: ProducerConfig?): ProducerConfig
    local c: ProducerConfig = {}
    for k, v in pairs(DEFAULT_PRODUCER) do c[k] = v end
    if type(cfg) == "table" then
        for k, v in pairs(cfg) do c[k] = v end
    end
    return c
end

local function ensureServiceContainer(): Folder
    if _serviceContainer and _serviceContainer.Parent then return _serviceContainer end
    local f = Instance.new("Folder")
    f.Name = "WaypointService_Container"
    f.Parent = workspace
    _serviceContainer = f
    return f
end

local function getVoxelParentFor(source: Instance, cfg: ProducerConfig): Instance
    if cfg.parentStrategy == "underProducer" then
        return source
    elseif cfg.parentStrategy == "underContainer" then
        return ensureServiceContainer()
    else
        -- siblingFolder (default): create/find GroupFolder under the producer’s parent
        local parent = source.Parent or workspace
        local folder = parent:FindFirstChild(cfg.groupFolderName or DEFAULT_PRODUCER.groupFolderName)
        if not (folder and folder:IsA("Folder")) then
            folder = Instance.new("Folder")
            folder.Name = cfg.groupFolderName or DEFAULT_PRODUCER.groupFolderName
            folder.Parent = parent
        end
        return folder
    end
end

-- =================== GENERATION (PRODUCER) ===================

local function clearProducedFor(producerTag: string, sourcePart: BasePart)
    local st = _producers[producerTag]; if not st then return end
    local list = st.producedBySource[sourcePart]; if not list then return end
    for i = #list, 1, -1 do
        local inst = list[i]
        if inst and inst.Parent then inst:Destroy() end
        table.remove(list, i)
    end
    st.producedBySource[sourcePart] = nil
end

local function buildVoxelsOnSource(producerTag: string, sourcePart: BasePart)
    local st = _producers[producerTag]; if not st then return end
    local cfg = st.cfg
    clearProducedFor(producerTag, sourcePart)

    local partSize = cfg.partSize or DEFAULT_PRODUCER.partSize
    local gap = cfg.gap or DEFAULT_PRODUCER.gap
    local insetX = cfg.inset or (partSize.X * 0.5)
    local insetZ = cfg.inset or (partSize.Z * 0.5)
    local yOffsetExtra = cfg.yOnTopOffset or 0

    local parentForVoxels = getVoxelParentFor(sourcePart, cfg)

    -- compute the top interior layer relative to sourcePart
    local cf = sourcePart.CFrame
    local size = sourcePart.Size
    local half = size * 0.5

    -- y offset to sit on top face internally
    local yLocal = (cfg.alignToTopFace ~= false)
        and (half.Y - (partSize.Y * 0.5))  -- top interior layer
        or 0

    -- additional "above" offset if requested
    local worldYOffsetCf = CFrame.new(0, yOffsetExtra, 0)

    -- bounds with insets
    local minX, maxX = -half.X + insetX, half.X - insetX
    local minZ, maxZ = -half.Z + insetZ, half.Z - insetZ

    local stepX = partSize.X + gap
    local stepZ = partSize.Z + gap

    local produced = {}
    for lx = minX, maxX, stepX do
        for lz = minZ, maxZ, stepZ do
            local p = Instance.new("Part")
            p.Anchored = (cfg.anchored ~= false)
            p.CanCollide = (cfg.canCollide == true)
            p.Color = cfg.color or DEFAULT_PRODUCER.color
            p.Transparency = (cfg.transparency ~= nil) and cfg.transparency or DEFAULT_PRODUCER.transparency
            p.Material = cfg.material or DEFAULT_PRODUCER.material
            p.Size = partSize
            p.Name = "WaypointVoxel"

            -- world CFrame: source CF * local offset * extra Y offset
            local worldCFrame = cf * CFrame.new(lx, yLocal, lz) * worldYOffsetCf
            p.CFrame = worldCFrame
            p.Parent = parentForVoxels

            -- tag as waypoint voxel (outputTag)
            CollectionService:AddTag(p, cfg.outputTag or DEFAULT_PRODUCER.outputTag)

            table.insert(produced, p)
        end
    end

    st.producedBySource[sourcePart] = produced
end

local function rebuildForProducerPart(producerTag: string, inst: Instance)
    if not inst:IsA("BasePart") then return end
    buildVoxelsOnSource(producerTag, inst)
end

local function registerProducerListeners(producerTag: string)
    local st = _producers[producerTag]; if not st then return end
    -- disconnect previous
    for _, c in ipairs(st.conns) do pcall(function() c:Disconnect() end) end
    table.clear(st.conns)

    -- added
    table.insert(st.conns, CollectionService:GetInstanceAddedSignal(producerTag):Connect(function(inst)
        if inst:IsA("BasePart") then
            rebuildForProducerPart(producerTag, inst)
        end
    end))
    -- removed
    table.insert(st.conns, CollectionService:GetInstanceRemovedSignal(producerTag):Connect(function(inst)
        if inst:IsA("BasePart") then
            clearProducedFor(producerTag, inst)
        end
    end))
end

-- Public: register any tag as a voxel producer
function WaypointService:RegisterProducerTag(producerTag: string, cfg: ProducerConfig?)
    assert(typeof(producerTag) == "string" and #producerTag > 0, "RegisterProducerTag: non-empty tag required")
    local state = _producers[producerTag]
    if not state then
        state = { cfg = deepCopyCfg(cfg), conns = {}, producedBySource = {} }
        _producers[producerTag] = state
    else
        -- update config
        state.cfg = deepCopyCfg(cfg)
    end

    -- build for existing instances
    for _, inst in ipairs(CollectionService:GetTagged(producerTag)) do
        if inst:IsA("BasePart") then
            rebuildForProducerPart(producerTag, inst)
        end
    end

    registerProducerListeners(producerTag)
end

-- Rebuild voxels for all sources with this producer tag
function WaypointService:RefreshProducer(producerTag: string)
    local st = _producers[producerTag]; if not st then return end
    for sourcePart, _ in pairs(st.producedBySource) do
        rebuildForProducerPart(producerTag, sourcePart)
    end
end

-- =================== INDEXING (OUTPUT TAG QUERIES) ===================

local function ensureIndex(tag: string): TagIndex
    local idx = _indices[tag]
    if idx then return idx end
    idx = { conns = {}, list = {}, byPart = {}, filterAncestor = nil, requireAnchored = false }
    _indices[tag] = idx
    return idx
end

local function disconnectIndex(idx: TagIndex)
    for _, c in ipairs(idx.conns) do pcall(function() c:Disconnect() end) end
    table.clear(idx.conns)
end

local function acceptWaypointPart(p: Instance, idx: TagIndex): BasePart?
    if not p:IsA("BasePart") then return nil end
    if idx.filterAncestor and not p:IsDescendantOf(idx.filterAncestor) then return nil end
    if idx.requireAnchored and not p.Anchored then return nil end
    return p
end

local function rebuildIndex(tag: string)
    local idx = _indices[tag]; if not idx then return end
    table.clear(idx.list); table.clear(idx.byPart)
    for _, inst in ipairs(CollectionService:GetTagged(tag)) do
        local bp = acceptWaypointPart(inst, idx)
        if bp then
            local wp = { part = bp, pos = bp.Position, cf = bp.CFrame }
            table.insert(idx.list, wp)
            idx.byPart[bp] = wp
        end
    end
end

local function onWaypointAdded(tag: string, inst: Instance)
    local idx = _indices[tag]; if not idx then return end
    local bp = acceptWaypointPart(inst, idx); if not bp or idx.byPart[bp] then return end
    local wp = { part = bp, pos = bp.Position, cf = bp.CFrame }
    table.insert(idx.list, wp)
    idx.byPart[bp] = wp
end

local function onWaypointRemoved(tag: string, inst: Instance)
    local idx = _indices[tag]; if not idx or not inst:IsA("BasePart") then return end
    local wp = idx.byPart[inst]; if not wp then return end
    idx.byPart[inst] = nil
    for i = #idx.list, 1, -1 do
        if idx.list[i].part == inst then table.remove(idx.list, i); break end
    end
end

-- Public: set up an index (query surface) for a tag (usually the producer's outputTag)
function WaypointService:RegisterIndex(outputTag: string, opts: { filterAncestor: Instance?, requireAnchored: boolean? }?)
    assert(typeof(outputTag) == "string" and #outputTag > 0, "RegisterIndex: non-empty tag required")
    local idx = ensureIndex(outputTag)
    opts = opts or {}
    idx.filterAncestor = opts.filterAncestor
    idx.requireAnchored = (opts.requireAnchored == true)

    rebuildIndex(outputTag)
    disconnectIndex(idx)
    table.insert(idx.conns, CollectionService:GetInstanceAddedSignal(outputTag):Connect(function(inst) onWaypointAdded(outputTag, inst) end))
    table.insert(idx.conns, CollectionService:GetInstanceRemovedSignal(outputTag):Connect(function(inst) onWaypointRemoved(outputTag, inst) end))

    -- keep positions fresh if parts move (cheap)
    table.insert(idx.conns, RunService.Heartbeat:Connect(function()
        for _, wp in ipairs(idx.list) do
            local p = wp.part
            if p and p.Parent then
                wp.pos = p.Position
                wp.cf  = p.CFrame
            end
        end
    end))
end

function WaypointService:RefreshIndex(outputTag: string)
    if _indices[outputTag] then rebuildIndex(outputTag) end
end

function WaypointService:GetAll(outputTag: string): { Waypoint }
    local idx = _indices[outputTag]; if not idx then return {} end
    return idx.list
end

function WaypointService:GetRandom(outputTag: string): Waypoint?
    local idx = _indices[outputTag]; if not idx or #idx.list == 0 then return nil end
    return idx.list[math.random(1, #idx.list)]
end

function WaypointService:GetRandomCFrame(outputTag: string): CFrame?
    local wp = self:GetRandom(outputTag)
    return wp and wp.cf or nil
end

function WaypointService:GetNearest(outputTag: string, origin: Vector3): Waypoint?
    local idx = _indices[outputTag]; if not idx or #idx.list == 0 then return nil end
    local best: Waypoint? = nil
    local bestDist = math.huge
    for _, wp in ipairs(idx.list) do
        local d = (wp.pos - origin).Magnitude
        if d < bestDist then best, bestDist = wp, d end
    end
    return best
end

function WaypointService:GetNearestCFrame(outputTag: string, origin: Vector3): CFrame?
    local wp = self:GetNearest(outputTag, origin)
    return wp and wp.cf or nil
end

function WaypointService:KnitInit() end
function WaypointService:KnitStart() end

return WaypointService
