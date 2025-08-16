-- Services/SpawnZoneService.lua
-- Centralized management for spawn "zones" built from BaseParts tagged via CollectionService.
-- Depends on: ReplicatedStorage.CustomPackages.ZoneRoot.Zone

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local CollectionService   = game:GetService("CollectionService")
local RunService          = game:GetService("RunService")

local Packages            = ReplicatedStorage:WaitForChild("Packages")
local Knit                = require(Packages.Knit)

local CustomPackages      = ReplicatedStorage:WaitForChild("CustomPackages")
local ZoneRoot            = CustomPackages:WaitForChild("ZoneRoot")
local Zone                = require(ZoneRoot:WaitForChild("Zone"))

local NPC_SpawnZoneService = Knit.CreateService {
    Name = "NPC_SpawnZoneService",
    Client = {},
}

-- ================= Types / State =================
type TagConfig = {
    autoUpdate: boolean?,    -- rebuild zones on tag add/remove (default: true)
    randomYaw: boolean?,     -- when asking for a CFrame, apply random yaw (default: false)
    usePartSize: boolean?,   -- build Zone.fromRegion using exact part size (default: true)
}

type TagState = {
    cfg: TagConfig,
    zones: { any },          -- array of Zone objects
    rrIndex: number,         -- round-robin cursor
    conns: { RBXScriptConnection }, -- added/removed listeners
}

local Tags: { [string]: TagState } = {}

-- ================= Helpers =================
local function buildZonesForTag(tag: string, cfg: TagConfig): { any }
    local zones = {}

    for _, inst in ipairs(CollectionService:GetTagged(tag)) do
        if inst:IsA("BasePart") then
            local ok, z = pcall(function()
                local cf, size = inst.CFrame, inst.Size
                local zone = Zone.fromRegion(cf, size) -- axis-aligned bounds; inside test uses point-in-region
                zone.autoUpdate = false
                return zone
            end)
            if ok and z then
                table.insert(zones, z)
            end
        end
    end

    return zones
end

local function ensureTagState(tag: string): TagState
    local t = Tags[tag]
    if t then return t end
    t = {
        cfg = {},
        zones = {},
        rrIndex = 1,
        conns = {},
    }
    Tags[tag] = t
    return t
end

local function disconnectConns(t: TagState)
    for _, c in ipairs(t.conns) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(t.conns)
end

local function refreshTag(tag: string)
    local t = Tags[tag]
    if not t then return end

    -- rebuild
    t.zones = buildZonesForTag(tag, t.cfg)
    if #t.zones == 0 then
        t.rrIndex = 1
    else
        t.rrIndex = ((t.rrIndex - 1) % math.max(1, #t.zones)) + 1
    end
end

-- ================= Public API =================

-- Register a tag whose BaseParts define spawn zones. Safe to call multiple times.
function NPC_SpawnZoneService:RegisterTag(tag: string, cfg: TagConfig?)
    assert(typeof(tag) == "string" and #tag > 0, "RegisterTag: tag must be a non-empty string")
    cfg = cfg or {}

    local t = ensureTagState(tag)
    -- merge defaults
    t.cfg.autoUpdate  = (cfg.autoUpdate  == nil) and true  or cfg.autoUpdate
    t.cfg.randomYaw   = (cfg.randomYaw   == nil) and false or cfg.randomYaw
    t.cfg.usePartSize = (cfg.usePartSize == nil) and true  or cfg.usePartSize

    -- initial build
    refreshTag(tag)

    -- (re)wire listeners if autoUpdate
    disconnectConns(t)
    if t.cfg.autoUpdate then
        table.insert(t.conns, CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
            if inst:IsA("BasePart") then
                refreshTag(tag)
            end
        end))
        table.insert(t.conns, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
            if inst:IsA("BasePart") then
                refreshTag(tag)
            end
        end))
    end
end

-- Manually rebuild zones for a tag.
function NPC_SpawnZoneService:Refresh(tag: string)
    if not Tags[tag] then return end
    refreshTag(tag)
end

-- Return the raw Zone objects (read-only).
function NPC_SpawnZoneService:GetZones(tag: string): { any }
    local t = Tags[tag]
    if not t then return {} end
    return t.zones
end

-- Get a random point (Vector3) inside ANY zone for this tag.
function NPC_SpawnZoneService:GetRandomPoint(tag: string): Vector3?
    local t = Tags[tag]
    if not t or #t.zones == 0 then return nil end

    -- pick a random zone, then ask it for a point
    local z = t.zones[math.random(1, #t.zones)]
    local point = select(1, z:getRandomPoint())
    if typeof(point) ~= "Vector3" then return nil end
    return point
end

-- Get a random CFrame (optionally random yaw) from ANY zone for this tag.
function NPC_SpawnZoneService:GetRandomCFrame(tag: string): CFrame?
    local t = Tags[tag]
    if not t then return nil end
    local p = self:GetRandomPoint(tag)
    if not p then return nil end
    if t.cfg.randomYaw then
        local yaw = math.random() * math.pi * 2
        return CFrame.new(p) * CFrame.Angles(0, yaw, 0)
    else
        return CFrame.new(p)
    end
end

-- Round-robin: iterate zones to distribute spawns uniformly across volumes.
function NPC_SpawnZoneService:NextZoneCFrame(tag: string): CFrame?
    local t = Tags[tag]
    if not t or #t.zones == 0 then return nil end
    local z = t.zones[t.rrIndex]
    t.rrIndex = (t.rrIndex % #t.zones) + 1

    local p = select(1, z:getRandomPoint())
    if typeof(p) ~= "Vector3" then return nil end

    if t.cfg.randomYaw then
        local yaw = math.random() * math.pi * 2
        return CFrame.new(p) * CFrame.Angles(0, yaw, 0)
    else
        return CFrame.new(p)
    end
end

-- Optional: override config at runtime (e.g., enable random yaw for a tag).
function NPC_SpawnZoneService:SetTagConfig(tag: string, cfg: TagConfig)
    local t = Tags[tag]
    if not t then return end
    for k, v in pairs(cfg) do
        t.cfg[k] = v
    end
end

-- Cleanup (optional if you hot-reload)
function NPC_SpawnZoneService:UnregisterTag(tag: string)
    local t = Tags[tag]
    if not t then return end
    disconnectConns(t)
    Tags[tag] = nil
end

-- ================= Knit lifecycle =================
function NPC_SpawnZoneService:KnitInit() end
function NPC_SpawnZoneService:KnitStart()
end

return NPC_SpawnZoneService
