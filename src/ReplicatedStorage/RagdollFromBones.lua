-- RagdollFromBones.lua
-- Build a pure-physics ragdoll (Parts + BallSockets) from a Mixamo-skinned MeshPart (no bone driving).

local RagdollFromBones = {}

-- ===== defaults =====
local DEFAULTS = {
    UseSegments = false,                         -- false = tiny block per bone; true = cylinders between key bones
    HideOriginal = false,                         -- hide original mesh parts after spawning ragdoll
    PartSize = Vector3.new(0.22, 0.22, 0.22),    -- size for block-per-bone
    CylinderRadius = 0.12,                       -- radius for segment cylinders
    CollideTokens = { "Hips","Spine","Head","LeftFoot","RightFoot" }, -- which pieces should collide
    -- Mixamo link map
    Links = {
        {"mixamorig:Hips","mixamorig:Spine"},
        {"mixamorig:Spine","mixamorig:Spine1"},
        {"mixamorig:Spine1","mixamorig:Spine2"},
        {"mixamorig:Spine2","mixamorig:Neck"},
        {"mixamorig:Neck","mixamorig:Head"},

        {"mixamorig:Spine2","mixamorig:LeftShoulder"},
        {"mixamorig:LeftShoulder","mixamorig:LeftArm"},
        {"mixamorig:LeftArm","mixamorig:LeftForeArm"},
        {"mixamorig:LeftForeArm","mixamorig:LeftHand"},

        {"mixamorig:Spine2","mixamorig:RightShoulder"},
        {"mixamorig:RightShoulder","mixamorig:RightArm"},
        {"mixamorig:RightArm","mixamorig:RightForeArm"},
        {"mixamorig:RightForeArm","mixamorig:RightHand"},

        {"mixamorig:Hips","mixamorig:LeftUpLeg"},
        {"mixamorig:LeftUpLeg","mixamorig:LeftLeg"},
        {"mixamorig:LeftLeg","mixamorig:LeftFoot"},
        {"mixamorig:LeftFoot","mixamorig:LeftToeBase"},

        {"mixamorig:Hips","mixamorig:RightUpLeg"},
        {"mixamorig:RightUpLeg","mixamorig:RightLeg"},
        {"mixamorig:RightLeg","mixamorig:RightFoot"},
        {"mixamorig:RightFoot","mixamorig:RightToeBase"},
    },
    -- Segment definitions if UseSegments = true
    Segments = {
        {"Torso","mixamorig:Spine","mixamorig:Spine2"},
        {"Neck","mixamorig:Neck","mixamorig:Head"},
        {"L_UpperArm","mixamorig:LeftShoulder","mixamorig:LeftArm"},
        {"L_ForeArm","mixamorig:LeftArm","mixamorig:LeftForeArm"},
        {"L_Hand","mixamorig:LeftForeArm","mixamorig:LeftHand"},
        {"R_UpperArm","mixamorig:RightShoulder","mixamorig:RightArm"},
        {"R_ForeArm","mixamorig:RightArm","mixamorig:RightForeArm"},
        {"R_Hand","mixamorig:RightForeArm","mixamorig:RightHand"},
        {"L_Thigh","mixamorig:Hips","mixamorig:LeftUpLeg"},
        {"L_Calf","mixamorig:LeftUpLeg","mixamorig:LeftLeg"},
        {"L_Foot","mixamorig:LeftLeg","mixamorig:LeftFoot"},
        {"R_Thigh","mixamorig:Hips","mixamorig:RightUpLeg"},
        {"R_Calf","mixamorig:RightUpLeg","mixamorig:RightLeg"},
        {"R_Foot","mixamorig:RightLeg","mixamorig:RightFoot"},
    }
}

-- ===== helpers =====
local function applyDefaults(opts)
    opts = opts or {}
    local out = {}
    for k,v in pairs(DEFAULTS) do
        out[k] = (opts[k] ~= nil) and opts[k] or v
    end
    return out
end

local function containsToken(name, tokens)
    local lower = string.lower(name)
    for _, t in ipairs(tokens) do
        if string.find(lower, string.lower(t), 1, true) then
            return true
        end
    end
    return false
end

local function boneWorldCF(mesh: MeshPart, bone: Instance)
    -- world = mesh * bone.CFrame * bone.Transform
    return mesh.CFrame * bone.CFrame * (bone.Transform or CFrame.identity)
end

local function makeBlock(name, cf, size: Vector3)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.Massless = false
    p.CanCollide = false
    p.CFrame = cf
    p.Material = Enum.Material.Plastic
    p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
    return p
end

local function makeCylinderBetween(name, aCF: CFrame, bCF: CFrame, radius)
    local origin, target = aCF.Position, bCF.Position
    local dir = target - origin
    local len = dir.Magnitude
    if len < 1e-4 then
        return makeBlock(name, aCF, Vector3.new(radius*2, radius*2, radius*2))
    end
    local mid = CFrame.lookAt(origin:Lerp(target, 0.5), target)
    local part = Instance.new("Part")
    part.Name = name
    part.Shape = Enum.PartType.Cylinder
    part.Size = Vector3.new(radius*2, len, radius*2) -- cylinder height is Y
    part.CFrame = mid * CFrame.Angles(0, 0, math.rad(90)) -- rotate so Y aligns with the link
    part.Massless = false
    part.CanCollide = false
    part.Material = Enum.Material.Plastic
    return part
end

local function ballSocket(a: Attachment, b: Attachment)
    local s = Instance.new("BallSocketConstraint")
    s.Attachment0 = a
    s.Attachment1 = b
    s.LimitsEnabled = true
    s.UpperAngle = 55
    s.TwistLimitsEnabled = true
    s.TwistLowerAngle = -35
    s.TwistUpperAngle = 35
    return s
end

-- ===== core builders =====
local function buildBlocksRagdoll(mesh: MeshPart, modelName: string, opts): Model
    local rag = Instance.new("Model")
    rag.Name = modelName .. "_Ragdoll"
    rag.Parent = workspace

    local bonePart = {} -- boneName -> Part

    for _, d in ipairs(mesh:GetDescendants()) do
        if d:IsA("Bone") then
            local wcf = boneWorldCF(mesh, d)
            local p = makeBlock(d.Name.."_RB", wcf, opts.PartSize)
            p.Parent = rag
            bonePart[d.Name] = p
        end
    end

    for _, link in ipairs(opts.Links) do
        local aName, bName = link[1], link[2]
        local p0, p1 = bonePart[aName], bonePart[bName]
        if p0 and p1 then
            local att0 = Instance.new("Attachment"); att0.Name = aName.."_A"; att0.Parent = p0
            local att1 = Instance.new("Attachment"); att1.Name = bName.."_A"; att1.Parent = p1
            local s = ballSocket(att0, att1); s.Parent = p0
        end
    end

    for name, p in pairs(bonePart) do
        p.CanCollide = containsToken(name, opts.CollideTokens)
        p.Anchored = false
    end

    -- set PrimaryPart if hips exists
    local hips = rag:FindFirstChild("mixamorig:Hips_RB", true)
    if hips and hips:IsA("BasePart") then
        rag.PrimaryPart = hips
    end

    return rag
end

local function buildSegmentRagdoll(mesh: MeshPart, modelName: string, opts): Model
    local rag = Instance.new("Model")
    rag.Name = modelName .. "_Ragdoll"
    rag.Parent = workspace

    local boneCF = {}
    for _, d in ipairs(mesh:GetDescendants()) do
        if d:IsA("Bone") then
            boneCF[d.Name] = boneWorldCF(mesh, d)
        end
    end

    local segPart = {} -- name -> Part
    local segEnds = {} -- name -> {aBone, bBone}
    for _, seg in ipairs(opts.Segments) do
        local segName, aName, bName = seg[1], seg[2], seg[3]
        local aCF, bCF = boneCF[aName], boneCF[bName]
        if aCF and bCF then
            local p = makeCylinderBetween(segName, aCF, bCF, opts.CylinderRadius)
            p.Parent = rag
            segPart[segName] = p
            segEnds[segName] = {aName, bName}
        end
    end

    local function partForBone(boneName)
        for sName, ends in pairs(segEnds) do
            if ends[1] == boneName or ends[2] == boneName then
                return segPart[sName]
            end
        end
        return nil
    end

    for _, link in ipairs(opts.Links) do
        local aName, bName = link[1], link[2]
        local pa, pb = partForBone(aName), partForBone(bName)
        if pa and pb then
            local att0 = Instance.new("Attachment"); att0.Parent = pa
            local att1 = Instance.new("Attachment"); att1.Parent = pb
            local aCFw, bCFw = boneCF[aName], boneCF[bName]
            if aCFw then att0.CFrame = pa.CFrame:ToObjectSpace(aCFw) end
            if bCFw then att1.CFrame = pb.CFrame:ToObjectSpace(bCFw) end
            local s = ballSocket(att0, att1); s.Parent = pa
        end
    end

    for _, p in pairs(segPart) do
        p.CanCollide = containsToken(p.Name, opts.CollideTokens)
        p.Anchored = false
    end

    -- try to pick a torso piece as PrimaryPart
    if segPart["Torso"] then rag.PrimaryPart = segPart["Torso"] end
    return rag
end

-- ===== public API =====

-- Create a ragdoll Model from a skinned MeshPart (no animation/bone driving)
-- opts: see DEFAULTS keys
function RagdollFromBones.CreateFromMesh(meshPart: MeshPart, opts)
    opts = applyDefaults(opts)
    local modelName = meshPart.Parent and meshPart.Parent.Name or meshPart.Name
    if opts.UseSegments then
        return buildSegmentRagdoll(meshPart, modelName, opts)
    else
        return buildBlocksRagdoll(meshPart, modelName, opts)
    end
end

-- Convenience: given a character/model that contains the skinned MeshPart, build ragdoll and (optionally) hide original.
function RagdollFromBones.CreateFromModel(model: Model, opts)
    opts = applyDefaults(opts)
    local mesh = model:FindFirstChildWhichIsA("MeshPart", true)
    if not mesh then
        warn("[RagdollFromBones] No MeshPart with bones found in", model:GetFullName())
        return nil
    end
    local rag = RagdollFromBones.CreateFromMesh(mesh, opts)

    if opts.HideOriginal then
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Transparency = 1
                d.CanCollide = false
            end
        end
    end

    -- position convenience: try to pivot rag to hips pose if present
    local hips = mesh:FindFirstChild("mixamorig:Hips", true)
    if hips and rag and rag.PrimaryPart then
        local pivot = mesh.CFrame * hips.CFrame
        rag:PivotTo(pivot)
    elseif rag and rag.PrimaryPart == nil then
        -- still place roughly at model pivot
        rag:PivotTo(model:GetPivot())
    end

    return rag
end

return RagdollFromBones
