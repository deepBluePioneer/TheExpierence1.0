-- Services/NpcAttachmentService.lua
-- Adds a ProximityPrompt to NPCs tagged "islanderWalker".
-- On interact: ragdoll NPC, stop animating, make parts non-collidable & massless,
-- and attach above player's head using Align* so it won't push the player.
-- Also maintains network ownership on the carrier and builds NoCollisionConstraints
-- between the NPC and the carrier character.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit     = require(Packages.Knit)

local WALKER_TAG          = "islanderWalker"

-- Prompt tuning
local PROMPT_ACTION_TEXT  = "Pick Up"
local PROMPT_OBJECT_TEXT  = "Islander"
local PROMPT_HOLD_SEC     = 0.3
local PROMPT_MAX_DIST     = 10

-- Attach tuning
local OFFSET_ABOVE_HEAD      = 8      -- studs above player's Head (applied via aligner)
local GIVE_NETWORK_OWNERSHIP = true   -- keep network ownership on the carrier
local MAKE_NPC_MASSLESS      = true   -- massless while carried

local NpcAttachmentService = Knit.CreateService {
    Name = "NpcAttachmentService",
    Client = {},
}

-- ========= Helpers =========

local function getHumanoid(model: Model): Humanoid?
    return model and model:FindFirstChildWhichIsA("Humanoid") or nil
end

local function getHRP(model: Model): BasePart?
    return model and model:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function getHead(model: Model): BasePart?
    return model and model:FindFirstChild("Head") :: BasePart
end

-- Massless for ALL BaseParts (incl. accessories)
local function setNpcMassless(npc: Model, massless: boolean)
    for _, d in ipairs(npc:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Massless = massless
        end
    end
end

-- Force collisions state on ALL BaseParts (HRP too)
local function setNpcAllCollide(npc: Model, canCollide: boolean)
    for _, d in ipairs(npc:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = canCollide
        end
    end
end

local function stopAndDestroyAnimator(hum: Humanoid)
    local animator = hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
            pcall(function() tr:Stop(0.1) end)
        end
        animator:Destroy()
    end
end

-- ========= Ragdoll constraints (BallSocket at Motor6D joints) =========

local function ensureAttachment(part: BasePart, name: string, cf: CFrame): Attachment
    local att = part:FindFirstChild(name) :: Attachment
    if not att then
        att = Instance.new("Attachment")
        att.Name = name
        att.Parent = part
    end
    att.CFrame = cf
    return att
end

local JOINT_LIMITS: { [string]: { swing: number, twistLower: number, twistUpper: number } } = {
    Neck  = { swing = 40, twistLower = -40, twistUpper = 40 },
    Waist = { swing = 25, twistLower = -20, twistUpper = 20 },
    LeftShoulder  = { swing = 70, twistLower = -60, twistUpper = 60 },
    RightShoulder = { swing = 70, twistLower = -60, twistUpper = 60 },
    LeftElbow     = { swing = 5,  twistLower = 0,   twistUpper = 140 },
    RightElbow    = { swing = 5,  twistLower = 0,   twistUpper = 140 },
    LeftWrist     = { swing = 20, twistLower = -45, twistUpper = 45 },
    RightWrist    = { swing = 20, twistLower = -45, twistUpper = 45 },
    LeftHip   = { swing = 45, twistLower = -30, twistUpper = 30 },
    RightHip  = { swing = 45, twistLower = -30, twistUpper = 30 },
    LeftKnee  = { swing = 5,  twistLower = 0,  twistUpper = 130 },
    RightKnee = { swing = 5,  twistLower = 0,  twistUpper = 130 },
    LeftAnkle = { swing = 20, twistLower = -30, twistUpper = 30 },
    RightAnkle= { swing = 20, twistLower = -30, twistUpper = 30 },
    -- R6 aliases
    ["Left Shoulder"]  = { swing = 70, twistLower = -60, twistUpper = 60 },
    ["Right Shoulder"] = { swing = 70, twistLower = -60, twistUpper = 60 },
    ["Left Hip"]       = { swing = 45, twistLower = -30, twistUpper = 30 },
    ["Right Hip"]      = { swing = 45, twistLower = -30, twistUpper = 30 },
    ["Neck"]           = { swing = 40, twistLower = -40, twistUpper = 40 },
}

local function isMotorJoint(inst: Instance): boolean
    return inst:IsA("Motor6D") and inst.Part0 and inst.Part1
end

local function ensureBallSocketForMotor(m: Motor6D, cfg: { swing: number, twistLower: number, twistUpper: number })
    if not (m.Part0 and m.Part1) then return end
    local a0 = ensureAttachment(m.Part0, "RGD_Att_" .. m.Name .. "_0", m.C0)
    local a1 = ensureAttachment(m.Part1, "RGD_Att_" .. m.Name .. "_1", m.C1)

    local existing = (m.Parent and m.Parent:FindFirstChild("RGD_BSC_" .. m.Name)) :: BallSocketConstraint
    if existing then
        existing.Attachment0, existing.Attachment1 = a0, a1
        return
    end

    local bsc = Instance.new("BallSocketConstraint")
    bsc.Name = "RGD_BSC_" .. m.Name
    bsc.Attachment0 = a0
    bsc.Attachment1 = a1
    bsc.LimitsEnabled = true
    bsc.UpperAngle = cfg.swing or 45
    bsc.TwistLimitsEnabled = true
    bsc.TwistLowerAngle = cfg.twistLower or -30
    bsc.TwistUpperAngle = cfg.twistUpper or 30
    bsc.Parent = m.Parent
end

-- ========= Network ownership =========

local function setNetworkOwnerForAssembly(npc: Model, player: Player?)
    local hrp = getHRP(npc)
    if hrp then pcall(function() hrp:SetNetworkOwner(player) end) end
    for _, d in ipairs(npc:GetDescendants()) do
        if d:IsA("BasePart") then
            pcall(function() d:SetNetworkOwner(player) end)
        end
    end
end

local ownerMaintainers: { [Model]: RBXScriptConnection } = {}

local function startOwnershipMaintainer(npc: Model, player: Player)
    if ownerMaintainers[npc] then
        ownerMaintainers[npc]:Disconnect()
        ownerMaintainers[npc] = nil
    end
    local accum = 0
    ownerMaintainers[npc] = RunService.Heartbeat:Connect(function(dt)
        if not npc.Parent or not npc:GetAttribute("AttachedToPlayer") then
            local conn = ownerMaintainers[npc]
            if conn then conn:Disconnect() end
            ownerMaintainers[npc] = nil
            local hrp = getHRP(npc)
            if hrp then pcall(function() hrp:SetNetworkOwner(nil) end) end
            return
        end
        accum += dt
        if accum >= 0.5 then
            accum = 0
            setNetworkOwnerForAssembly(npc, player)
        end
    end)
end

-- ========= No-collision pairs (NPC ↔ player character) =========

local function createNoCollisionPairs(npc: Model, character: Model)
    local folder = npc:FindFirstChild("Carry_NoCollision") :: Folder
    if folder then folder:Destroy() end
    folder = Instance.new("Folder")
    folder.Name = "Carry_NoCollision"
    folder.Parent = npc

    local npcParts, charParts = {}, {}
    for _, d in ipairs(npc:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(npcParts, d) end
    end
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(charParts, d) end
    end
    for _, np in ipairs(npcParts) do
        for _, cp in ipairs(charParts) do
            local ncc = Instance.new("NoCollisionConstraint")
            ncc.Part0 = np
            ncc.Part1 = cp
            ncc.Parent = folder
        end
    end
end

local function destroyNoCollisionPairs(npc: Model)
    local folder = npc:FindFirstChild("Carry_NoCollision")
    if folder then folder:Destroy() end
end

-- ========= Carry attachments (one-way follower, no reaction force) =========

local function createCarryAligners(npcHRP: BasePart, playerHead: BasePart, offsetY: number)
    -- Attachments
    local attNpc = Instance.new("Attachment")
    attNpc.Name = "Carry_Att_NPC"
    attNpc.Parent = npcHRP
    attNpc.Position = Vector3.new(0, 0, 0) -- NPC-side offset (keep 0; we offset on player side)

    local attPlayer = Instance.new("Attachment")
    attPlayer.Name = "Carry_Att_Player"
    attPlayer.Parent = playerHead
    attPlayer.Position = Vector3.new(0, offsetY, 0) -- vertical offset above head (local to head)

    -- Position follower
    local ap = Instance.new("AlignPosition")
    ap.Name = "Carry_AlignPosition"
    ap.Attachment0 = attNpc
    ap.Attachment1 = attPlayer
    ap.ApplyAtCenterOfMass = true
    ap.MaxForce = math.huge
    ap.MaxVelocity = math.huge
    ap.Responsiveness = 160   -- slightly softer to reduce impulses
    ap.RigidityEnabled = true
    pcall(function() ap.ReactionForceEnabled = false end) -- avoid pushing target
    ap.Parent = npcHRP

    -- Orientation follower
    local ao = Instance.new("AlignOrientation")
    ao.Name = "Carry_AlignOrientation"
    ao.Attachment0 = attNpc
    ao.Attachment1 = attPlayer
    ao.MaxTorque = math.huge
    ao.Responsiveness = 160
    ao.RigidityEnabled = true
    pcall(function() ao.ReactionTorqueEnabled = false end) -- avoid torque into target
    ao.Parent = npcHRP

    return attNpc, attPlayer, ap, ao
end

local function destroyCarryAligners(npc: Model)
    for _, inst in ipairs(npc:GetDescendants()) do
        if inst:IsA("AlignPosition") and inst.Name == "Carry_AlignPosition" then inst:Destroy() end
        if inst:IsA("AlignOrientation") and inst.Name == "Carry_AlignOrientation" then inst:Destroy() end
        if inst:IsA("Attachment") and (inst.Name == "Carry_Att_NPC" or inst.Name == "Carry_Att_Player") then inst:Destroy() end
    end
end

-- ========= Ragdoll & attach =========

local function ragdollNow(npc: Model, ownerPlayer: Player?)
    if npc:GetAttribute("IsRagdolled") then return end
    local hum = getHumanoid(npc)
    local hrp = getHRP(npc)
    if not (hum and hrp) then return end

    -- Stop locomotion/animations
    hum.WalkSpeed = 0
    hum.JumpPower = 0
    hum.AutoRotate = false
    hum.AutoJumpEnabled = false
    stopAndDestroyAnimator(hum)

    -- Non-collide + massless (if desired)
    setNpcAllCollide(npc, false)
    if MAKE_NPC_MASSLESS then
        setNpcMassless(npc, true)
    end

    -- Physics-only so Humanoid doesn't fight constraints
    hum:ChangeState(Enum.HumanoidStateType.Physics)

    -- Give/lock ownership to carrier (or server if none)
    if GIVE_NETWORK_OWNERSHIP then
        setNetworkOwnerForAssembly(npc, ownerPlayer)
    else
        setNetworkOwnerForAssembly(npc, nil)
    end

    -- Build constraints and disable motors
    for _, inst in ipairs(npc:GetDescendants()) do
        if isMotorJoint(inst) then
            local m = inst :: Motor6D
            local cfg = JOINT_LIMITS[m.Name] or { swing = 35, twistLower = -25, twistUpper = 25 }
            ensureBallSocketForMotor(m, cfg)
            m.Enabled = false
        end
    end

    npc:SetAttribute("IsRagdolled", true)
end

local function freezeNpcForAttach(npc: Model)
    local hum = getHumanoid(npc)
    if not hum then return end
    hum:ChangeState(Enum.HumanoidStateType.Physics)
end

local function attachNpcToPlayer(npc: Model, player: Player)
    if not npc or not player.Character then return end
    local npcHRP = getHRP(npc)
    if not npcHRP then return end
    local playerHead = player.Character:FindFirstChild("Head") :: BasePart
    if not (playerHead and playerHead:IsA("BasePart")) then return end

    -- Prevent double-attach
    if npc:GetAttribute("AttachedToPlayer") then return end
    npc:SetAttribute("AttachedToPlayer", true)

    -- Ragdoll immediately (and stop animating)
    ragdollNow(npc, player)

    -- Keep non-collide & massless while carried
    setNpcAllCollide(npc, false)
    setNpcMassless(npc, true)
    freezeNpcForAttach(npc)

    -- Build NoCollisionConstraints vs the carrier character (extra safety)
    createNoCollisionPairs(npc, player.Character)

    -- Ensure both parts are unanchored
    npcHRP.Anchored = false
    playerHead.Anchored = false

    -- Warm-start near head (no offset here; offset applied by aligners)
    npc:PivotTo(CFrame.new(playerHead.Position, playerHead.Position + playerHead.CFrame.LookVector))

    -- One-way follower w/ vertical offset applied via attPlayer.Position
    createCarryAligners(npcHRP, playerHead, OFFSET_ABOVE_HEAD)

    -- Maintain ownership on the carrier while attached
    if GIVE_NETWORK_OWNERSHIP then
        startOwnershipMaintainer(npc, player)
    end

    -- Cleanup if the player dies / respawns
    local playerHum = player.Character:FindFirstChildOfClass("Humanoid")
    if playerHum then
        playerHum.Died:Once(function()
            if npc and npc.Parent then
                npc:SetAttribute("AttachedToPlayer", nil)
                local conn = ownerMaintainers[npc]
                if conn then conn:Disconnect() ownerMaintainers[npc] = nil end
                destroyCarryAligners(npc)
                destroyNoCollisionPairs(npc)
                setNpcAllCollide(npc, false)  -- keep non-collide after drop (change to true if you want)
                setNpcMassless(npc, false)    -- restore mass after drop
                setNetworkOwnerForAssembly(npc, nil)
            end
        end)
    end
end

-- ========= Proximity prompt & setup =========

local function ensureProximityPrompt(npc: Model)
    local parentPart = getHead(npc) or getHRP(npc)
    if not parentPart then return end

    local prompt = parentPart:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        prompt = Instance.new("ProximityPrompt")
        prompt.Name = "AttachPrompt"
        prompt.ActionText = PROMPT_ACTION_TEXT
        prompt.ObjectText = PROMPT_OBJECT_TEXT
        prompt.HoldDuration = PROMPT_HOLD_SEC
        prompt.RequiresLineOfSight = false
        prompt.MaxActivationDistance = PROMPT_MAX_DIST
        prompt.KeyboardKeyCode = Enum.KeyCode.E
        prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
        prompt.Style = Enum.ProximityPromptStyle.Default
        prompt.Parent = parentPart
    end

    if prompt:GetAttribute("Bound") then return end
    prompt:SetAttribute("Bound", true)

    prompt.Triggered:Connect(function(player: Player)
        attachNpcToPlayer(npc, player)
    end)
end

local function setupNpc(npcInstance: Instance)
    local model = npcInstance:IsA("Model") and npcInstance or npcInstance:FindFirstAncestorOfClass("Model")
    if not model then return end
    ensureProximityPrompt(model)

    local hum = getHumanoid(model)
    if hum then
        hum.Died:Once(function()
            if model then
                model:SetAttribute("AttachedToPlayer", nil)
                model:SetAttribute("IsRagdolled", nil)
                local conn = ownerMaintainers[model]
                if conn then conn:Disconnect() ownerMaintainers[model] = nil end
                destroyCarryAligners(model)
                destroyNoCollisionPairs(model)
                setNetworkOwnerForAssembly(model, nil)
                setNpcAllCollide(model, false)
            end
        end)
    end
end

-- ========= Knit lifecycle =========

function NpcAttachmentService:KnitStart()
    math.randomseed(os.time())

    -- Existing NPCs
    for _, inst in ipairs(CollectionService:GetTagged(WALKER_TAG)) do
        if inst:IsA("Model") then
            setupNpc(inst)
        end
    end

    -- Future NPCs
    CollectionService:GetInstanceAddedSignal(WALKER_TAG):Connect(function(inst)
        if inst:IsA("Model") then
            setupNpc(inst)
        end
    end)
end

function NpcAttachmentService:KnitInit() end

return NpcAttachmentService
