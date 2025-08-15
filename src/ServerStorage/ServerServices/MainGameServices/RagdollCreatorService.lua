-- Services/RagdollCreatorService.lua
-- After 20s, convert each "islanderWalker" NPC into a constraint-based ragdoll and stop movement.
-- Supports R15 (full chain) and falls back sensibly for R6.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit     = require(Packages.Knit)

local WALKER_TAG    = "islanderWalker"
local RAGDOLL_DELAY = 5 -- seconds

local RagdollCreatorService = Knit.CreateService {
    Name = "RagdollCreatorService",
    Client = {},
}

-- =================== Utilities ===================

local function getHumanoid(model: Model): Humanoid?
    return model:FindFirstChildWhichIsA("Humanoid")
end

local function getHRP(model: Model): BasePart?
    return model:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function stopAnimations(hum: Humanoid)
    local animator = hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
            pcall(function() tr:Stop(0.1) end)
        end
        animator:Destroy()
    end
end

local function enableLimbCollision(model: Model)
    for _, p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") then
            if p.Name == "HumanoidRootPart" then
                p.CanCollide = false
            else
                p.CanCollide = true
            end
        end
    end
end

-- Create an Attachment; parent is a BasePart; name is prefixed
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

-- Build a BallSocket between Motor6D.Part0/Part1 at their C0/C1 frames.
-- cfg = { swing=number, twistLower=number, twistUpper=number }
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
    -- Optional “feel” tweaks:
    -- bsc.Restitution = 0
    -- bsc.MaxFrictionTorque = math.huge

    bsc.Parent = m.Parent -- usually the connecting part (e.g., UpperArm, UpperLeg, Torso)
end

-- Recommended joint limits by Motor6D name (R15 names)
local JOINT_LIMITS: { [string]: { swing: number, twistLower: number, twistUpper: number } } = {
    -- torso/neck
    Neck  = { swing = 40, twistLower = -40, twistUpper = 40 },
    Waist = { swing = 25, twistLower = -20, twistUpper = 20 },

    -- shoulders/elbows/wrists
    LeftShoulder  = { swing = 70, twistLower = -60, twistUpper = 60 },
    RightShoulder = { swing = 70, twistLower = -60, twistUpper = 60 },
    LeftElbow     = { swing = 5,  twistLower = 0,    twistUpper = 140 }, -- hinge-ish
    RightElbow    = { swing = 5,  twistLower = 0,    twistUpper = 140 },
    LeftWrist     = { swing = 20, twistLower = -45,  twistUpper = 45 },
    RightWrist    = { swing = 20, twistLower = -45,  twistUpper = 45 },

    -- hips/knees/ankles
    LeftHip   = { swing = 45, twistLower = -30, twistUpper = 30 },
    RightHip  = { swing = 45, twistLower = -30, twistUpper = 30 },
    LeftKnee  = { swing = 5,  twistLower = 0,   twistUpper = 130 }, -- hinge-ish
    RightKnee = { swing = 5,  twistLower = 0,   twistUpper = 130 },
    LeftAnkle = { swing = 20, twistLower = -30, twistUpper = 30 },
    RightAnkle= { swing = 20, twistLower = -30, twistUpper = 30 },

    -- R6 compatibility
    ["Left Shoulder"]  = { swing = 70, twistLower = -60, twistUpper = 60 },
    ["Right Shoulder"] = { swing = 70, twistLower = -60, twistUpper = 60 },
    ["Left Hip"]       = { swing = 45, twistLower = -30, twistUpper = 30 },
    ["Right Hip"]      = { swing = 45, twistLower = -30, twistUpper = 30 },
    ["Neck"]           = { swing = 40, twistLower = -40, twistUpper = 40 },
}

local function isMotorJoint(m: Instance): boolean
    return m:IsA("Motor6D") and m.Part0 and m.Part1
end

-- Build constraints for every Motor6D we recognize, and disable motors
local function buildConstraintRagdoll(model: Model)
    -- Step 1: stop control/animations
    local hum = getHumanoid(model)
    local hrp = getHRP(model)
    if not (hum and hrp) then return end

    hum.WalkSpeed = 0
    hum.JumpPower = 0
    hum.AutoRotate = false
    hum.AutoJumpEnabled = false
    hum:ChangeState(Enum.HumanoidStateType.Physics)
    pcall(function() hrp:SetNetworkOwner(nil) end) -- server authority

    stopAnimations(hum)
    enableLimbCollision(model)

    -- Step 2: constraints for every Motor6D
    for _, inst in ipairs(model:GetDescendants()) do
        if isMotorJoint(inst) then
            local m = inst :: Motor6D
            local cfg = JOINT_LIMITS[m.Name]
            -- Default if unknown joint name
            cfg = cfg or { swing = 35, twistLower = -25, twistUpper = 25 }
            ensureBallSocketForMotor(m, cfg)
            m.Enabled = false -- keep the object for restoration; physics takes over
        end
    end

    model:SetAttribute("IsRagdolled", true)
end

-- Optional: restore the character (remove constraints & attachments and re-enable motors)
local function removeConstraintRagdoll(model: Model)
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("BallSocketConstraint") and inst.Name:sub(1,8) == "RGD_BSC_" then
            inst:Destroy()
        elseif inst:IsA("Attachment") and inst.Name:sub(1,8) == "RGD_Att_" then
            inst:Destroy()
        elseif inst:IsA("Motor6D") and inst.Enabled == false then
            inst.Enabled = true
        end
    end
    model:SetAttribute("IsRagdolled", false)

    local hum = getHumanoid(model)
    if hum then
        hum.AutoRotate = true
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
end

-- =================== Scheduling ===================

local scheduled: { [Model]: boolean } = {}

local function scheduleRagdoll(modelLike: Instance)
    local model = modelLike:IsA("Model") and modelLike or modelLike:FindFirstAncestorOfClass("Model")
    if not model or scheduled[model] then return end
    scheduled[model] = true

    task.delay(RAGDOLL_DELAY, function()
        if model.Parent and not model:GetAttribute("IsRagdolled") then
            buildConstraintRagdoll(model)
        end
        scheduled[model] = nil
    end)
end

-- =================== Knit Lifecycle ===================

function RagdollCreatorService:KnitStart()
    -- Existing NPCs
    for _, inst in ipairs(CollectionService:GetTagged(WALKER_TAG)) do
        scheduleRagdoll(inst)
    end

    -- Future NPCs
    CollectionService:GetInstanceAddedSignal(WALKER_TAG):Connect(function(inst)
        scheduleRagdoll(inst)
    end)

    -- Optional: expose restore via attribute toggle (for debugging)
    -- e.g., set model:SetAttribute("IsRagdolled", false) to pop back up.
    CollectionService:GetInstanceRemovedSignal(WALKER_TAG):Connect(function(inst)
        local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
        if model and model:GetAttribute("IsRagdolled") then
            -- removeConstraintRagdoll(model) -- enable if you want auto-restore on tag removal
        end
        scheduled[model] = nil
    end)
end

function RagdollCreatorService:KnitInit() end

return RagdollCreatorService
