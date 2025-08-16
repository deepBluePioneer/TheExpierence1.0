-- Services/NpcRagdollService.lua
-- Knit service to manage NPC ragdoll behavior.
-- Server API:
--   local S = Knit.GetService("NpcRagdollService")
--   S:Register(npcModel: Model, opts?: {})
--   S:Ragdoll(npcModel: Model, ownerPlayer: Player?)
--   S:Unragdoll(npcModel: Model)
--   S:Destroy(npcModel: Model)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Knit = require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Knit"))

-- ===== Joint limits (by Motor6D name) =====
type JointCfg = { swing: number, twistLower: number, twistUpper: number }
local JOINT_LIMITS: { [string]: JointCfg } = {
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
    ["Left Shoulder"]  = { swing = 70, twistLower = -60, twistUpper = 60 },
    ["Right Shoulder"] = { swing = 70, twistLower = -60, twistUpper = 60 },
    ["Left Hip"]       = { swing = 45, twistLower = -30, twistUpper = 30 },
    ["Right Hip"]      = { swing = 45, twistLower = -30, twistUpper = 30 },
    ["Neck"]           = { swing = 40, twistLower = -40, twistUpper = 40 },
}

-- Default ragdoll config
local DEFAULTS = {
    makeMasslessWhileCarried = false, -- keep physics mass
    giveNetworkOwnership = false,     -- server keeps ownership
}

-- ===== Helpers =====
local function getHumanoid(model: Model): Humanoid?
    return model and model:FindFirstChildWhichIsA("Humanoid") or nil
end

local function getHRP(model: Model): BasePart?
    return model and (model:FindFirstChild("HumanoidRootPart") :: BasePart) or nil
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

local function setNpcMassless(npc: Model, massless: boolean)
    for _, d in ipairs(npc:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Massless = massless
        end
    end
end

local function setNpcAllCollide(npc: Model, canCollide: boolean)
    for _, d in ipairs(npc:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = canCollide
        end
    end
end

local function isMotorJoint(inst: Instance): boolean
    return inst:IsA("Motor6D") and inst.Part0 ~= nil and inst.Part1 ~= nil
end

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

local function ensureBallSocketForMotor(m: Motor6D, cfg: JointCfg)
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

local function setNetworkOwnerForAssembly(npc: Model, player: Player?)
    local hrp = getHRP(npc)
    if hrp then pcall(function() hrp:SetNetworkOwner(player) end) end
    for _, d in ipairs(npc:GetDescendants()) do
        if d:IsA("BasePart") then
            pcall(function() d:SetNetworkOwner(player) end)
        end
    end
end

-- ===== Controller (private to service) =====
type Controller = {
    model: Model,
    hum: Humanoid,
    hrp: BasePart,
    deathConn: RBXScriptConnection?,
    isRagdolled: boolean,
    options: {
        makeMasslessWhileCarried: boolean,
        giveNetworkOwnership: boolean,
    },
}

local function NewController(npcModel: Model, opts: {}?): Controller
    assert(npcModel and npcModel:IsA("Model"), "NpcRagdollService:Register: npcModel must be a Model")
    local hum = getHumanoid(npcModel)
    local hrp = getHRP(npcModel)
    assert(hum and hrp, "NpcRagdollService:Register: NPC must have Humanoid and HumanoidRootPart")

    local ctrl: Controller = {
        model = npcModel,
        hum = hum,
        hrp = hrp,
        deathConn = nil,
        isRagdolled = false,
        options = table.clone(DEFAULTS),
    }

    if typeof(opts) == "table" then
        for k, v in pairs(opts) do
            if ctrl.options[k] ~= nil then ctrl.options[k] = v end
        end
    end

    -- Clean up on NPC death
    ctrl.deathConn = hum.Died:Once(function()
        setNetworkOwnerForAssembly(ctrl.model, nil)
        setNpcAllCollide(ctrl.model, false)
        ctrl.isRagdolled = false
    end)

    return ctrl
end

-- ===== Service =====
local NpcRagdollService = Knit.CreateService({
    Name = "NpcRagdollService",
    Client = {},
})

-- Model -> Controller map
local _controllers: { [Model]: Controller } = {}

-- ===== Service API =====
function NpcRagdollService:Register(npcModel: Model, opts: {}?)
    if _controllers[npcModel] then return end
    _controllers[npcModel] = NewController(npcModel, opts)
end

-- Put NPC into ragdoll (disable motors, add BallSockets, etc.)
function NpcRagdollService:Ragdoll(npcModel: Model, ownerPlayer: Player?)
    local ctrl = _controllers[npcModel]
    if not ctrl or ctrl.isRagdolled then return end

    -- Stop movement/animations
    ctrl.hum.WalkSpeed = 0
    ctrl.hum.JumpPower = 0
    ctrl.hum.AutoRotate = false
    ctrl.hum.AutoJumpEnabled = false
    stopAndDestroyAnimator(ctrl.hum)

    -- Non-collide & optionally massless
    setNpcAllCollide(ctrl.model, false)
    if ctrl.options.makeMasslessWhileCarried then
        setNpcMassless(ctrl.model, true)
    end

    -- Switch humanoid to Physics state
    ctrl.hum:ChangeState(Enum.HumanoidStateType.Physics)

    -- Set network ownership (server or player)
    if ctrl.options.giveNetworkOwnership then
        setNetworkOwnerForAssembly(ctrl.model, ownerPlayer)
    else
        setNetworkOwnerForAssembly(ctrl.model, nil)
    end

    -- Replace Motor6Ds with physics constraints
    for _, inst in ipairs(ctrl.model:GetDescendants()) do
        if isMotorJoint(inst) then
            local m = inst :: Motor6D
            local cfg = JOINT_LIMITS[m.Name] or { swing = 35, twistLower = -25, twistUpper = 25 }
            ensureBallSocketForMotor(m, cfg)
            m.Enabled = false
        end
    end

    ctrl.isRagdolled = true
end

-- Restore motors and exit ragdoll
function NpcRagdollService:Unragdoll(npcModel: Model)
    local ctrl = _controllers[npcModel]
    if not ctrl or not ctrl.isRagdolled then return end

    for _, inst in ipairs(ctrl.model:GetDescendants()) do
        if inst:IsA("Motor6D") then
            inst.Enabled = true
        elseif inst:IsA("BallSocketConstraint") and inst.Name:match("^RGD_BSC_") then
            inst:Destroy()
        elseif inst:IsA("Attachment") and inst.Name:match("^RGD_Att_") then
            inst:Destroy()
        end
    end
    setNpcAllCollide(ctrl.model, true)
    setNpcMassless(ctrl.model, false)
    ctrl.hum.AutoRotate = true
    ctrl.isRagdolled = false
end

-- Cleanup controller
function NpcRagdollService:Destroy(npcModel: Model)
    local ctrl = _controllers[npcModel]
    if not ctrl then return end

    if ctrl.deathConn then
        ctrl.deathConn:Disconnect()
        ctrl.deathConn = nil
    end
    _controllers[npcModel] = nil
end

-- ===== Knit lifecycle =====
function NpcRagdollService:KnitInit() end
function NpcRagdollService:KnitStart()
    -- auto-clean dead NPCs
    for model, ctrl in pairs(_controllers) do
        if not model.Parent then
            self:Destroy(model)
        end
    end
end

return NpcRagdollService
