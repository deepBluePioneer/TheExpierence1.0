-- Services/IslandWalkerService.lua
-- Wander NPCs tagged "islanderWalker" by moving to random parts tagged "waypointPart".
-- Server drives animation: loads Animate.walk.WalkAnim once and plays it while moving.
-- Disables climbing and jumping so NPCs stay grounded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

local WALKER_TAG = "islanderWalker"
local WAYPOINT_PART_TAG = "waypointPart"

local IslandWalkerService = Knit.CreateService({
    Name = "IslandWalkerService",
    Client = {},
})

-- ===== CONFIG =====
local REACH_THRESHOLD       = 3.0
local RETARGET_COOLDOWN     = 0.25
local STUCK_TIMEOUT         = 5.0
local MIN_RETARGET_DIST     = 10.0
local DEFAULT_WALKSPEED     = 12
local MOVE_REFRESH_INTERVAL = 1.0

-- ===== STATE =====
type Walker = {
    model: Model,
    hum: Humanoid,
    hrp: BasePart,

    target: BasePart?,
    lastPos: Vector3,
    lastMoveTime: number,
    lastMoveTo: number,
    nextTryAt: number,

    moveConn: RBXScriptConnection?,

    -- animation refs
    animator: Animator?,
    walkTrack: AnimationTrack?,
    runningConn: RBXScriptConnection?,
}

local walkers: { [Model]: Walker } = {}
local hb: RBXScriptConnection?
local waypointParts: { BasePart } = {}

-- ===== HELPERS =====
local function humOf(model: Model): Humanoid?
    return model:FindFirstChildWhichIsA("Humanoid")
end

local function hrpOf(model: Model): BasePart?
    return model:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function ensureAnimator(hum: Humanoid): Animator
    local a = hum:FindFirstChildOfClass("Animator")
    if not a then
        a = Instance.new("Animator")
        a.Parent = hum
    end
    return a
end

-- Keep Animate for storing the Animation object, but it won't run (LocalScript).
-- This fetches the WalkAnim Animation if present.
local function getWalkAnimationFromAnimate(model: Model): Animation?
    local animate = model:FindFirstChild("Animate")
    if not animate then
        local src = StarterPlayer:FindFirstChild("StarterCharacterScripts")
            and StarterPlayer.StarterCharacterScripts:FindFirstChild("Animate")
        if src then
            animate = src:Clone()
            animate.Parent = model
        end
    end
    if not animate then return nil end

    local walkFolder = animate:FindFirstChild("walk")
    if not walkFolder then return nil end

    local walkAnimObj = walkFolder:FindFirstChild("WalkAnim")
    if walkAnimObj and walkAnimObj:IsA("Animation") and walkAnimObj.AnimationId ~= "" then
        return walkAnimObj
    end
    return nil
end

-- MoveTo wrapper (one-shot callback)
local function moveTo(w: Walker, targetPoint: Vector3, andThen: ((reached: boolean) -> ())?)
    if w.moveConn then
        w.moveConn:Disconnect()
        w.moveConn = nil
    end
    w.hum:MoveTo(targetPoint)
    w.lastMoveTo = tick()
    if andThen then
        w.moveConn = w.hum.MoveToFinished:Once(function(reached: boolean)
            w.moveConn = nil
            andThen(reached)
        end)
    end
end

local function pruneWaypoints()
    local i = 1
    while i <= #waypointParts do
        local p = waypointParts[i]
        if not p or not p.Parent or not p:IsDescendantOf(workspace) or not p:IsA("BasePart") then
            table.remove(waypointParts, i)
        else
            i += 1
        end
    end
end

local function pickRandomWaypoint(origin: Vector3?): BasePart?
    pruneWaypoints()
    local n = #waypointParts
    if n == 0 then return nil end

    if origin then
        for _ = 1, math.min(6, n) do
            local cand = waypointParts[math.random(1, n)]
            if (cand.Position - origin).Magnitude >= MIN_RETARGET_DIST then
                return cand
            end
        end
    end
    return waypointParts[math.random(1, n)]
end

local function retarget(w: Walker)
    if tick() < (w.nextTryAt or 0) then return end
    local target = pickRandomWaypoint(w.hrp and w.hrp.Position or nil)
    if not target then
        w.target = nil
        w.nextTryAt = tick() + RETARGET_COOLDOWN
        return
    end

    w.target = target
    w.lastPos = w.hrp.Position
    w.lastMoveTime = tick()
    w.lastMoveTo = 0
    w.nextTryAt = tick() + RETARGET_COOLDOWN

    moveTo(w, target.Position, function(_reached)
        if w.target == target then
            w.target = nil
            retarget(w)
        end
    end)
end

local function startWalker(model: Model)
    if walkers[model] then return end
    local hum = humOf(model)
    local hrp = hrpOf(model)
    if not hum or not hrp then return end

    hum.AutoRotate = true
    hum.PlatformStand = false
    if hum.WalkSpeed <= 0 then hum.WalkSpeed = DEFAULT_WALKSPEED end

    -- 🚫 Disable climbing & jumping
    hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    hum.AutoJumpEnabled = false
    hum.JumpPower = 0

    -- Redirect unwanted states
    hum.StateChanged:Connect(function(_, new)
        if new == Enum.HumanoidStateType.Climbing then
            hum:ChangeState(Enum.HumanoidStateType.Freefall)
        elseif new == Enum.HumanoidStateType.Freefall then
            if hum.FloorMaterial ~= Enum.Material.Air then
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end
    end)

    -- Build walker
    local w: Walker = {
        model = model,
        hum = hum,
        hrp = hrp,
        target = nil,
        lastPos = hrp.Position,
        lastMoveTime = tick(),
        lastMoveTo = 0,
        nextTryAt = 0,
        moveConn = nil,

        animator = ensureAnimator(hum),
        walkTrack = nil,
        runningConn = nil,
    }

    -- Load WalkAnim from Animate if available
    local walkAnimObj = getWalkAnimationFromAnimate(model)
    if walkAnimObj then
        local ok, track = pcall(function()
            return w.animator:LoadAnimation(walkAnimObj)
        end)
        if ok and track then
            w.walkTrack = track
            w.walkTrack.Looped = true
            w.walkTrack.Priority = Enum.AnimationPriority.Movement
        else
            warn(("Failed to load WalkAnim for %s"):format(model.Name))
        end
    else
        warn(("No valid Animate.walk.WalkAnim found on %s; NPC will move without custom walk anim."):format(model.Name))
    end

    -- Start/stop walk based on Running
    w.runningConn = hum.Running:Connect(function(speed)
        local track = w.walkTrack
        if not track then return end
        if speed > 0.1 then
            if not track.IsPlaying then track:Play(0.15) end
        else
            if track.IsPlaying then track:Stop(0.2) end
        end
    end)

    walkers[model] = w

    hum.Died:Once(function()
        if w.moveConn then w.moveConn:Disconnect() end
        if w.runningConn then w.runningConn:Disconnect() end
        if w.walkTrack and w.walkTrack.IsPlaying then w.walkTrack:Stop(0.2) end
        walkers[model] = nil
    end)
end

local function stopWalker(model: Model)
    local w = walkers[model]
    if not w then return end
    if w.moveConn then w.moveConn:Disconnect() end
    if w.runningConn then w.runningConn:Disconnect() end
    if w.walkTrack and w.walkTrack.IsPlaying then w.walkTrack:Stop(0.2) end
    walkers[model] = nil
end

-- ===== HEARTBEAT =====
local function ensureHeartbeat()
    if hb then return end
    hb = RunService.Heartbeat:Connect(function()
        pruneWaypoints()

        for _, w in pairs(walkers) do
            if not w.model.Parent or not w.hrp.Parent then
                stopWalker(w.model)
            else
                local t = w.target
                if not t or not t.Parent then
                    retarget(w)
                else
                    local dist = (w.hrp.Position - t.Position).Magnitude
                    if dist <= REACH_THRESHOLD then
                        w.target = nil
                        retarget(w)
                    else
                        local moved = (w.hrp.Position - w.lastPos).Magnitude
                        if moved > 0.5 then
                            w.lastPos = w.hrp.Position
                            w.lastMoveTime = tick()
                        elseif (tick() - w.lastMoveTime) >= STUCK_TIMEOUT then
                            w.target = nil
                            retarget(w)
                        end

                        if (tick() - (w.lastMoveTo or 0)) >= MOVE_REFRESH_INTERVAL then
                            moveTo(w, t.Position, function(_reached)
                                if w.target == t then
                                    w.target = nil
                                    retarget(w)
                                end
                            end)
                        end
                    end
                end
            end
        end

        if next(walkers) == nil then
            hb:Disconnect()
            hb = nil
        end
    end)
end

-- ===== WAYPOINT PART LISTENERS =====
local function addWaypointPart(inst: Instance)
    if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
        table.insert(waypointParts, inst)
    end
end

local function removeWaypointPart(inst: Instance)
    local i = 1
    while i <= #waypointParts do
        if waypointParts[i] == inst then
            table.remove(waypointParts, i)
        else
            i += 1
        end
    end
end

-- ===== KNIT =====
function IslandWalkerService:KnitStart()
    math.randomseed(os.time())

    -- Seed waypoint list
    for _, inst in ipairs(CollectionService:GetTagged(WAYPOINT_PART_TAG)) do
        addWaypointPart(inst)
    end
    CollectionService:GetInstanceAddedSignal(WAYPOINT_PART_TAG):Connect(addWaypointPart)
    CollectionService:GetInstanceRemovedSignal(WAYPOINT_PART_TAG):Connect(removeWaypointPart)

    -- Start existing walkers
    for _, inst in ipairs(CollectionService:GetTagged(WALKER_TAG)) do
        local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
        if model then startWalker(model) end
    end
    if next(walkers) ~= nil then ensureHeartbeat() end

    -- Future walkers
    CollectionService:GetInstanceAddedSignal(WALKER_TAG):Connect(function(inst)
        local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
        if model then
            startWalker(model)
            ensureHeartbeat()
        end
    end)

    CollectionService:GetInstanceRemovedSignal(WALKER_TAG):Connect(function(inst)
        local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
        if model then stopWalker(model) end
    end)
end

function IslandWalkerService:KnitInit() end

return IslandWalkerService
