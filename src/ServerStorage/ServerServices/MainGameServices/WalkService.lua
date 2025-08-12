-- Services/WalkService.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local RagdollFromBones = require(ReplicatedStorage.Source.RagdollFromBones)

local WalkService = Knit.CreateService {
    Name = "WalkService",
    Client = {},
}

-- ====== Config ======
local MODEL_NAME = "mayor_walking_1"
local RAGDOLL_DELAY = 5 -- seconds
local RAGDOLL_OPTS = {
    UseSegments = false,                                -- true = cylinder limbs
    HideOriginal = true,                                -- hide skinned mesh after spawn
    PartSize = Vector3.new(0.22, 0.22, 0.22),           -- for block-per-bone
    CylinderRadius = 0.12,                              -- for segments
    CollideTokens = { "Hips","Spine","Head","LeftFoot","RightFoot" },
}

-- ====== Helpers ======
local function stopAllAnimations(model: Model)
    local ac = model:FindFirstChildOfClass("AnimationController")
    local animator = ac and ac:FindFirstChildOfClass("Animator")
    if animator then
        for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
            t:Stop(0.1)
        end
    end
end

local function scheduleRagdoll(model: Model, seconds: number)
    if model:GetAttribute("Ragdolled") then return end
    task.delay(seconds, function()
        if not model.Parent or model:GetAttribute("Ragdolled") then return end

        -- stop anims so they don't fight physics
        stopAllAnimations(model)

        -- build the physics ragdoll from the skinned MeshPart and hide the original
        local rag = RagdollFromBones.CreateFromModel(model, RAGDOLL_OPTS)
        if rag then
            model:SetAttribute("Ragdolled", true)
        else
            warn("[WalkService] Ragdoll creation failed for", model:GetFullName())
        end
    end)
end

-- Play the first Animation under the Animator, then schedule ragdoll
local function playMayorWalk(model: Model)
    local animCtrl = model:FindFirstChildOfClass("AnimationController")
    if not animCtrl then
        warn("[WalkService] No AnimationController on", model:GetFullName())
        return
    end

    local animator = animCtrl:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = animCtrl
    end

    -- Find an Animation either under Animator or the model
    local anim: Animation? = animator:FindFirstChildOfClass("Animation") or model:FindFirstChildOfClass("Animation")
    if not anim or not anim.AnimationId or anim.AnimationId == "" then
        warn("[WalkService] No Animation with valid AnimationId on", model:GetFullName())
        return
    end

    local track = animator:LoadAnimation(anim)
    track.Looped = true
    track.Priority = Enum.AnimationPriority.Movement
    track:Play(0.2) -- fade-in

    -- schedule ragdoll
  --  scheduleRagdoll(model, RAGDOLL_DELAY)
end

local function tryStartOnExisting()
    local mayor = workspace:FindFirstChild(MODEL_NAME)
    if mayor and mayor:IsA("Model") then
        playMayorWalk(mayor)
    end
end

-- ====== Knit lifecycle ======
function WalkService:KnitStart()
    tryStartOnExisting()

    workspace.ChildAdded:Connect(function(child)
        if child:IsA("Model") and child.Name == MODEL_NAME then
            task.defer(function()
                playMayorWalk(child)
            end)
        end
    end)
end

function WalkService:KnitInit()
    -- init if needed
end

return WalkService
