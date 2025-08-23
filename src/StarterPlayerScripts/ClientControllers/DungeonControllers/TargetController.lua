-- ClientControllers/TargetController.lua
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local CollectionService  = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local Knit               = require(ReplicatedStorage.Packages.Knit)

local LocalPlayer = Players.LocalPlayer

local TargetController = Knit.CreateController { Name = "TargetController" }

-- Runtime state
TargetController._candidates    = {}   -- array<BasePart>
TargetController._current       = nil  -- current targeted BasePart
TargetController._highlight     = nil  -- Highlight
TargetController._reticleGui    = nil  -- BillboardGui (corner brackets)
TargetController._reticleColor  = Color3.new(1,1,1)
TargetController._tagConns      = {}   -- [tag] = {addedConn=..., removedConn=...}

-- NEW: scanning bar gui for non-powerup cubes
TargetController._scanGui       = nil  -- BillboardGui ( --[--|--]-- )
TargetController._scanTrack     = nil  -- Frame (center track)
TargetController._scanPipe      = nil  -- Frame (moving |)
TargetController._scanTween     = nil  -- active tween
TargetController._scanConn      = nil  -- tween Completed connection
TargetController._scanDir       = 1    -- 1 -> right, -1 -> left
TargetController._scanWidthPx   = 140  -- total widget width (fixed pixels)
TargetController._scanHeightPx  = 18
TargetController._scanBracketPx = 10   -- width of [ and ] each
TargetController._scanPipePx    = 4    -- width of the moving "|"
TargetController._scanDuration  = 1.0  -- seconds to sweep end-to-end

-- Config (defaults; server can override via TargetService if you add properties)
TargetController._threshold     = 0.80
TargetController._maxDistance   = 300
TargetController._tagRandom     = "randomGridCube"
TargetController._tagPowerup    = "powerupPatch"

-- Reticle (corner brackets) sizing
TargetController._minReticlePx  = 64
TargetController._maxReticlePx  = 160
TargetController._baseReticlePx = 110
TargetController._reticleEdge   = 0.28

function TargetController:KnitStart()
    local TargetService = Knit.GetService("TargetService")

    if TargetService.Threshold then
        TargetService.Threshold:Observe(function(v) self._threshold = tonumber(v) or self._threshold end)
    end
    if TargetService.MaxDistance then
        TargetService.MaxDistance:Observe(function(v) self._maxDistance = tonumber(v) or self._maxDistance end)
    end
    if TargetService.TagRandom then
        TargetService.TagRandom:Observe(function(v)
            local newTag = tostring(v) or self._tagRandom
            if newTag ~= self._tagRandom then
                self:_connectTagSignals(newTag)
                self:_disconnectTagSignals(self._tagRandom)
                self._tagRandom = newTag
                self:_rebuildCandidates()
            end
        end)
    end
    if TargetService.TagPowerup then
        TargetService.TagPowerup:Observe(function(v)
            local newTag = tostring(v) or self._tagPowerup
            if newTag ~= self._tagPowerup then
                self:_connectTagSignals(newTag)
                self:_disconnectTagSignals(self._tagPowerup)
                self._tagPowerup = newTag
                self:_rebuildCandidates()
            end
        end)
    end

    self:_rebuildCandidates()
    self:_ensureHighlight()
    self:_ensureReticle()
    self:_ensureScanGui()

    self:_connectTagSignals(self._tagRandom)
    self:_connectTagSignals(self._tagPowerup)

    RunService.RenderStepped:Connect(function()
        self:_updateTargetFromCamera()
        self:_tickReticleSize()
    end)
end

-- Hook live add/remove for a given tag
function TargetController:_connectTagSignals(tag: string)
    if not tag or self._tagConns[tag] then return end

    local addedConn = CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
        if inst:IsA("BasePart") then
            table.insert(self._candidates, inst)
        end
    end)

    local removedConn = CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
        for i = #self._candidates, 1, -1 do
            if self._candidates[i] == inst then
                table.remove(self._candidates, i)
                break
            end
        end
        if self._current == inst then
            self:_setTarget(nil)
        end
    end)

    self._tagConns[tag] = { addedConn = addedConn, removedConn = removedConn }
end

function TargetController:_disconnectTagSignals(tag: string)
    local conns = self._tagConns[tag]
    if not conns then return end
    if conns.addedConn then conns.addedConn:Disconnect() end
    if conns.removedConn then conns.removedConn:Disconnect() end
    self._tagConns[tag] = nil
end

-- Build / refresh candidate list from BOTH tags, deduping
function TargetController:_rebuildCandidates()
    table.clear(self._candidates)
    local seen = {}

    local function addTagged(tag)
        if not tag then return end
        for _, inst in ipairs(CollectionService:GetTagged(tag)) do
            if inst:IsA("BasePart") and not seen[inst] then
                seen[inst] = true
                table.insert(self._candidates, inst)
            end
        end
    end

    addTagged(self._tagRandom)
    addTagged(self._tagPowerup)
end

-- Reusable highlight (local-only)
function TargetController:_ensureHighlight()
    if self._highlight and self._highlight.Parent then return end
    local guiParent = LocalPlayer:WaitForChild("PlayerGui")
    local h = Instance.new("Highlight")
    h.Name = "TargetHighlight"
    h.FillTransparency    = 0.5
    h.OutlineTransparency = 0
    h.DepthMode           = Enum.HighlightDepthMode.Occluded
    h.Enabled             = false
    h.Parent              = guiParent
    self._highlight = h
end

-- Reusable BillboardGui reticle (corner brackets)
function TargetController:_ensureReticle()
    if self._reticleGui and self._reticleGui.Parent then return end
    local guiParent = LocalPlayer:WaitForChild("PlayerGui")

    local bg = Instance.new("BillboardGui")
    bg.Name = "TargetReticle"
    bg.AlwaysOnTop = true
    bg.LightInfluence = 0
    bg.ResetOnSpawn = false
    bg.Size = UDim2.fromOffset(self._baseReticlePx, self._baseReticlePx)
    bg.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
    bg.Enabled = false
    bg.Parent = guiParent
    self._reticleGui = bg

    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.Size = UDim2.fromScale(1, 1)
    container.Parent = bg

    local function corner(parent, at: "TL"|"TR"|"BL"|"BR")
        local col = self._reticleColor
        local edge = self._reticleEdge

        local hbar = Instance.new("Frame")
        hbar.BackgroundColor3 = col
        hbar.BorderSizePixel = 0
        hbar.Size = UDim2.new(edge, 0, 0, 2)

        local vbar = Instance.new("Frame")
        vbar.BackgroundColor3 = col
        vbar.BorderSizePixel = 0
        vbar.Size = UDim2.new(0, 2, edge, 0)

        if at == "TL" then
            hbar.AnchorPoint, hbar.Position = Vector2.new(0, 0), UDim2.new(0, 0, 0, 0)
            vbar.AnchorPoint, vbar.Position = Vector2.new(0, 0), UDim2.new(0, 0, 0, 0)
        elseif at == "TR" then
            hbar.AnchorPoint, hbar.Position = Vector2.new(1, 0), UDim2.new(1, 0, 0, 0)
            vbar.AnchorPoint, vbar.Position = Vector2.new(1, 0), UDim2.new(1, 0, 0, 0)
        elseif at == "BL" then
            hbar.AnchorPoint, hbar.Position = Vector2.new(0, 1), UDim2.new(0, 0, 1, 0)
            vbar.AnchorPoint, vbar.Position = Vector2.new(0, 1), UDim2.new(0, 0, 1, 0)
        else
            hbar.AnchorPoint, hbar.Position = Vector2.new(1, 1), UDim2.new(1, 0, 1, 0)
            vbar.AnchorPoint, vbar.Position = Vector2.new(1, 1), UDim2.new(1, 0, 1, 0)
        end

        hbar.Parent = parent
        vbar.Parent = parent
        return hbar, vbar
    end

    self._retTL_h, self._retTL_v = corner(container, "TL")
    self._retTR_h, self._retTR_v = corner(container, "TR")
    self._retBL_h, self._retBL_v = corner(container, "BL")
    self._retBR_h, self._retBR_v = corner(container, "BR")
end

-- NEW: scanning billboard gui ( --[--|--]-- ), used ONLY for non-powerup random cubes
function TargetController:_ensureScanGui()
    if self._scanGui and self._scanGui.Parent then return end
    local guiParent = LocalPlayer:WaitForChild("PlayerGui")

    local bg = Instance.new("BillboardGui")
    bg.Name = "TargetScan"
    bg.AlwaysOnTop = true
    bg.LightInfluence = 0
    bg.ResetOnSpawn = false
    bg.Size = UDim2.fromOffset(self._scanWidthPx, self._scanHeightPx)
    bg.StudsOffsetWorldSpace = Vector3.new(0, 2.0, 0) -- sit above cube a bit
    bg.Enabled = false
    bg.Parent = guiParent
    self._scanGui = bg

    -- container row
    local container = Instance.new("Frame")
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.Size = UDim2.fromScale(1, 1)
    container.Parent = bg

    -- [
    local left = Instance.new("Frame")
    left.BackgroundColor3 = Color3.new(1,1,1)
    left.BackgroundTransparency = 0
    left.BorderSizePixel = 0
    left.AnchorPoint = Vector2.new(0, 0.5)
    left.Position = UDim2.new(0, 0, 0.5, 0)
    left.Size = UDim2.fromOffset(self._scanBracketPx, self._scanHeightPx)
    left.Parent = container

    -- ]
    local right = Instance.new("Frame")
    right.BackgroundColor3 = Color3.new(1,1,1)
    right.BackgroundTransparency = 0
    right.BorderSizePixel = 0
    right.AnchorPoint = Vector2.new(1, 0.5)
    right.Position = UDim2.new(1, 0, 0.5, 0)
    right.Size = UDim2.fromOffset(self._scanBracketPx, self._scanHeightPx)
    right.Parent = container

    -- center track ( --- )
    local track = Instance.new("Frame")
    track.Name = "Track"
    track.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
    track.BackgroundTransparency = 0.35
    track.BorderSizePixel = 0
    track.AnchorPoint = Vector2.new(0, 0.5)
    track.Position = UDim2.new(0, self._scanBracketPx, 0.5, 0)
    track.Size = UDim2.new(1, -(self._scanBracketPx * 2), 1, 0)
    track.Parent = container
    self._scanTrack = track

    -- moving pipe ( | ), starts near the left ( --| )
    local pipe = Instance.new("Frame")
    pipe.Name = "Pipe"
    pipe.BackgroundColor3 = Color3.new(1,1,1)
    pipe.BorderSizePixel = 0
    pipe.AnchorPoint = Vector2.new(0.5, 0.5)
    pipe.Position = UDim2.new(0, self._scanPipePx/2, 0.5, 0)
    pipe.Size = UDim2.fromOffset(self._scanPipePx, self._scanHeightPx)
    pipe.Parent = track
    self._scanPipe = pipe
end

-- Helpers
local function hasTag(inst: Instance, tag: string)
    return tag and CollectionService:HasTag(inst, tag)
end

-- Reticle tint
function TargetController:_tintReticle(color: Color3)
    self._reticleColor = color
    if not self._reticleGui then return end
    if self._retTL_h then self._retTL_h.BackgroundColor3 = color end
    if self._retTL_v then self._retTL_v.BackgroundColor3 = color end
    if self._retTR_h then self._retTR_h.BackgroundColor3 = color end
    if self._retTR_v then self._retTR_v.BackgroundColor3 = color end
    if self._retBL_h then self._retBL_h.BackgroundColor3 = color end
    if self._retBL_v then self._retBL_v.BackgroundColor3 = color end
    if self._retBR_h then self._retBR_h.BackgroundColor3 = color end
    if self._retBR_v then self._retBR_v.BackgroundColor3 = color end
end

-- NEW: scan GUI tint (match part color)
function TargetController:_tintScan(color: Color3)
    if not self._scanGui then return end
    if self._scanTrack then
        self._scanTrack.BackgroundColor3 = color:Lerp(Color3.new(1,1,1), 0.2)
    end
    if self._scanPipe then
        self._scanPipe.BackgroundColor3 = color
    end
end

-- NEW: start/stop scan tween
function TargetController:_stopScanAnim()
    if self._scanConn then self._scanConn:Disconnect() self._scanConn = nil end
    if self._scanTween then self._scanTween:Cancel() self._scanTween = nil end
end

function TargetController:_startScanAnim()
    if not (self._scanGui and self._scanTrack and self._scanPipe) then return end

    self:_stopScanAnim() -- ensure single animator

    -- compute pixel bounds inside track
    local total = self._scanTrack.AbsoluteSize.X
    if total <= 0 then
        -- wait one frame to get layout sizes
        RunService.RenderStepped:Wait()
        total = self._scanTrack.AbsoluteSize.X
    end
    if total <= 0 then return end

    local minX = self._scanPipePx/2
    local maxX = total - self._scanPipePx/2

    -- place pipe at the "end" so it goes --| then scans to |--
    local startX = (self._scanDir == 1) and minX or maxX
    self._scanPipe.Position = UDim2.new(0, startX, 0.5, 0)

    -- ping-pong tween loop
    local function tweenTo(targetX)
        local ti = TweenInfo.new(self._scanDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
        self._scanTween = TweenService:Create(self._scanPipe, ti, { Position = UDim2.new(0, targetX, 0.5, 0) })
        if self._scanConn then self._scanConn:Disconnect() end
        self._scanConn = self._scanTween.Completed:Connect(function()
            if not (self._scanGui and self._scanGui.Enabled and self._scanPipe.Parent) then return end
            -- flip direction
            self._scanDir = -self._scanDir
            local nextX = (self._scanDir == 1) and maxX or minX
            tweenTo(nextX)
        end)
        self._scanTween:Play()
    end

    local firstTarget = (self._scanDir == 1) and maxX or minX
    tweenTo(firstTarget)
end

-- Attach/detach current target visuals
function TargetController:_setTarget(part: BasePart?)
    if self._current == part then return end
    self._current = part

    -- Highlight
    if part then
        self._highlight.Adornee = part
        self._highlight.FillColor    = part.Color
        self._highlight.OutlineColor = part.Color
        self._highlight.Enabled = true
    else
        self._highlight.Adornee = nil
        self._highlight.Enabled = false
    end

    -- Reticle (shown for both)
    if part then
        self:_tintReticle(part.Color)
        self._reticleGui.Adornee = part
        if hasTag(part, self._tagPowerup) then
            self._reticleGui.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
        else
            self._reticleGui.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
        end
        self._reticleGui.Enabled = true
    else
        self._reticleGui.Adornee = nil
        self._reticleGui.Enabled = false
    end

    -- NEW: Scan bar only for NON-powerup random cubes
    if part and not hasTag(part, self._tagPowerup) then
        self._scanGui.Adornee = part
        self._scanGui.Enabled = true
        self:_tintScan(part.Color)
        self:_startScanAnim()
    else
        self._scanGui.Adornee = nil
        self._scanGui.Enabled = false
        self:_stopScanAnim()
    end
end

-- Camera-based targeting via dot product
function TargetController:_updateTargetFromCamera()
    local cam = workspace.CurrentCamera
    if not cam then return end

    local camPos  = cam.CFrame.Position
    local forward = cam.CFrame.LookVector

    local bestDot  = self._threshold
    local bestPart = nil
    local maxDist  = self._maxDistance

    for i = #self._candidates, 1, -1 do
        local p = self._candidates[i]
        if not (p and p.Parent) then
            table.remove(self._candidates, i)
        else
            local offset = p.Position - camPos
            local dist   = offset.Magnitude
            if dist > 0.01 and dist <= maxDist then
                local dir = offset / dist
                local dot = forward:Dot(dir)
                -- small bias to powerups if you like:
                if hasTag(p, self._tagPowerup) then dot += 0.03 end
                if dot > bestDot then
                    bestDot  = dot
                    bestPart = p
                end
            end
        end
    end

    self:_setTarget(bestPart)
end

-- Reticle scales with distance
function TargetController:_tickReticleSize()
    if not (self._reticleGui and self._reticleGui.Enabled and self._reticleGui.Adornee) then return end
    local cam = workspace.CurrentCamera
    if not cam then return end

    local part = self._reticleGui.Adornee :: BasePart
    if not (part and part.Parent) then return end

    local dist = (cam.CFrame.Position - part.Position).Magnitude
    local px = math.clamp(self._baseReticlePx * (70 / math.max(20, dist)), self._minReticlePx, self._maxReticlePx)
    self._reticleGui.Size = UDim2.fromOffset(px, px)
end

return TargetController
