-- Services/NpcLifespanService.lua
-- Countdown + accelerating white-flash warning -> RAGDOLL (no destroy).
-- Integrated with Knit NpcRagdollService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit     = require(Packages.Knit)

local NpcLifespanService = Knit.CreateService {
    Name = "NpcLifespanService",
    Client = {},
}

-- ========= Types =========
export type Options = {
    min: number?,
    max: number?,
    destroyOnDeath: boolean?,
    onDestroy: ((Model, string) -> ())?, -- "ragdoll_timeout" | "ragdoll_death" | "removed" | "manual"
}

type PartSnapshot = { part: BasePart, color: Color3 }
type TaskEntry = {
    model: Model,
    remaining: number,
    destroyOnDeath: boolean,
    onDestroy: ((Model, string) -> ())?,

    conns: { RBXScriptConnection },
    paused: boolean,

    -- flashing state
    warnActive: boolean?,
    parts: { PartSnapshot }?,
    flashOn: boolean?,
    nextFlashAt: number?,
}

-- ========= Defaults / State =========
local DEFAULTS = {
    min = 20,
    max = 60,
    destroyOnDeath = true, -- if humanoid Died fires, ragdoll immediately
}

-- Flashing config
local WARN_DURATION          = 3.0
local FLASH_INTERVAL_START   = 0.6
local FLASH_INTERVAL_END     = 0.08
local FLASH_COLOR            = Color3.new(1, 1, 1)

-- Options passed to NpcRagdollService:Register(model, opts)
local RAGDOLL_OPTIONS = {
    makeMasslessWhileCarried = false, -- keep mass (pure flop)
    giveNetworkOwnership     = false, -- don't force owner
    alignResponsiveness      = 160,   -- irrelevant unless attaching later
}

local Active: { [Model]: TaskEntry } = {}
local HeartbeatConn: RBXScriptConnection? = nil
local PausedGlobal = false

-- Knit service handle (filled in KnitStart)
local RagdollSvc: any = nil

-- ========= Internal helpers =========

local function randRange(minV: number, maxV: number): number
    local mn = math.max(0, minV)
    local mx = math.max(mn, maxV)
    return mn + math.random() * (mx - mn)
end

local function stopHeartbeatIfIdle()
    if HeartbeatConn and next(Active) == nil then
        HeartbeatConn:Disconnect()
        HeartbeatConn = nil
    end
end

local function snapshotParts(model: Model): { PartSnapshot }
    local list = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            table.insert(list, { part = d, color = d.Color })
        end
    end
    return list
end

local function setFlashState(entry: TaskEntry, on: boolean)
    if not entry.parts then return end
    entry.flashOn = on
    for i = #entry.parts, 1, -1 do
        local snap = entry.parts[i]
        local p = snap.part
        if p and p.Parent then
            p.Color = on and FLASH_COLOR or snap.color
        else
            table.remove(entry.parts, i)
        end
    end
end

local function stopWarning(entry: TaskEntry)
    if entry.warnActive then
        setFlashState(entry, false)
        entry.warnActive = false
        entry.parts = nil
        entry.nextFlashAt = nil
        entry.flashOn = nil
    end
end

local function startWarning(entry: TaskEntry)
    if entry.warnActive then return end
    entry.warnActive = true
    entry.parts = snapshotParts(entry.model)
    entry.flashOn = false
    entry.nextFlashAt = 0
end

local function currentFlashInterval(remaining: number): number
    local progress = 1 - math.clamp(remaining / WARN_DURATION, 0, 1)
    return FLASH_INTERVAL_START + (FLASH_INTERVAL_END - FLASH_INTERVAL_START) * progress
end

local function ensureNpcRegistered(model: Model)
    -- Safe to call repeatedly; our NpcRagdollService:Register is idempotent.
    if RagdollSvc then
        local ok = pcall(function()
            RagdollSvc:Register(model, RAGDOLL_OPTIONS)
        end)
        if not ok then
            warn("[NpcLifespanService] Failed to register NPC with NpcRagdollService")
        end
    end
end

local function ragdollAndCleanup(model: Model, reason: string)
    local entry = Active[model]
    if entry then
        stopWarning(entry)
        for _, c in ipairs(entry.conns) do pcall(function() c:Disconnect() end) end
        table.clear(entry.conns)
        Active[model] = nil
    end

    if model and model.Parent and RagdollSvc then
        ensureNpcRegistered(model)
        pcall(function() RagdollSvc:Ragdoll(model, nil) end) -- no owner; just flop
    end

    if entry and entry.onDestroy then
        pcall(entry.onDestroy, model, reason)
    end

    stopHeartbeatIfIdle()
end

local function cleanupEntry(model: Model, reason: string)
    local entry = Active[model]
    if not entry then return end
    stopWarning(entry)
    Active[model] = nil
    for _, c in ipairs(entry.conns) do pcall(function() c:Disconnect() end) end
    table.clear(entry.conns)
    if entry.onDestroy then
        pcall(entry.onDestroy, model, reason)
    end
    stopHeartbeatIfIdle()
end

local function ensureHeartbeat()
    if HeartbeatConn then return end
    HeartbeatConn = RunService.Heartbeat:Connect(function(dt)
        if PausedGlobal then return end

        for model, entry in pairs(Active) do
            if not entry.paused then
                entry.remaining -= dt

                if not entry.warnActive and entry.remaining <= WARN_DURATION then
                    startWarning(entry)
                end

                if entry.warnActive then
                    local now = tick()
                    if not entry.nextFlashAt or now >= entry.nextFlashAt then
                        setFlashState(entry, not entry.flashOn)
                        entry.nextFlashAt = now + currentFlashInterval(math.max(0, entry.remaining))
                    end
                end

                if entry.remaining <= 0 then
                    -- Time's up -> ragdoll (do NOT destroy)
                    ragdollAndCleanup(model, "ragdoll_timeout")
                end
            end
        end

        stopHeartbeatIfIdle()
    end)
end

-- ========= Public API =========

function NpcLifespanService:SetDefaults(opts: Options)
    if typeof(opts) ~= "table" then return end
    if typeof(opts.min) == "number" then DEFAULTS.min = math.max(0, opts.min) end
    if typeof(opts.max) == "number" then DEFAULTS.max = math.max(DEFAULTS.min, opts.max) end
    if typeof(opts.destroyOnDeath) == "boolean" then DEFAULTS.destroyOnDeath = opts.destroyOnDeath end
end

function NpcLifespanService:PauseAll()  PausedGlobal = true  end
function NpcLifespanService:ResumeAll() PausedGlobal = false end

function NpcLifespanService:Add(model: Model, opts: Options?)
    if not (model and model:IsA("Model")) then
        warn("[NpcLifespanService] Add: expected a Model")
        return
    end
    opts = opts or {}

    local minLife = typeof(opts.min) == "number" and math.max(0, opts.min) or DEFAULTS.min
    local maxLife = typeof(opts.max) == "number" and math.max(minLife, opts.max) or DEFAULTS.max
    local destroyOnDeath = (typeof(opts.destroyOnDeath) == "boolean") and opts.destroyOnDeath or DEFAULTS.destroyOnDeath
    local onDestroyCb = opts.onDestroy

    if Active[model] then
        self:Remove(model)
    end

    -- Ensure the NPC is known to the ragdoll service up-front
    ensureNpcRegistered(model)

    local life = randRange(minLife, maxLife)
    local entry: TaskEntry = {
        model = model,
        remaining = life,
        destroyOnDeath = destroyOnDeath,
        onDestroy = onDestroyCb,
        conns = {},
        paused = false,

        warnActive = false,
        parts = nil,
        flashOn = false,
        nextFlashAt = nil,
    }

    -- External removal
    table.insert(entry.conns, model.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            cleanupEntry(model, "removed")
        end
    end))

    -- Humanoid death -> ragdoll (if enabled)
    if destroyOnDeath then
        local hum = model:FindFirstChildWhichIsA("Humanoid")
        if hum then
            table.insert(entry.conns, hum.Died:Connect(function()
                ragdollAndCleanup(model, "ragdoll_death")
            end))
        end
    end

    Active[model] = entry
    ensureHeartbeat()
end

function NpcLifespanService:Remove(model: Model)
    if not Active[model] then return end
    cleanupEntry(model, "manual")
end

function NpcLifespanService:Pause(model: Model)
    local entry = Active[model]
    if entry then entry.paused = true end
end

function NpcLifespanService:Resume(model: Model)
    local entry = Active[model]
    if entry then entry.paused = false end
end

-- Force ragdoll now and stop tracking.
function NpcLifespanService:RagdollNow(model: Model, reason: string?)
    if not model then return end
    ragdollAndCleanup(model, reason or "manual")
end

function NpcLifespanService:KnitInit() end

function NpcLifespanService:KnitStart()
    math.randomseed(os.time())
    -- Acquire the ragdoll service
    RagdollSvc = Knit.GetService("NpcRagdollService")
end

return NpcLifespanService
