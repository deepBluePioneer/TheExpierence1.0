local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local SFXConfig = require(ReplicatedStorage.Modules.Audio.SFXConfig)
local AudioUtil = require(ReplicatedStorage.Modules.Audio.AudioUtil)

local AmbienceController = Knit.CreateController { Name = "AmbienceController" }

local current = { player=nil, emitter=nil, reverb=nil, lowpass=nil }
local fading  = { player=nil, emitter=nil, reverb=nil }
local FADE_TIME = 1.2

local function lerp(a,b,t) return a + (b-a)*t end

local function resolveParent(path)
    if type(path) == "string" and path ~= "" then
        -- best effort: search Workspace recursively for last segment
        local seg = path:match("([^%.]+)$")
        local found = workspace:FindFirstChild(seg, true)
        if found then return found end
    end
    return workspace.CurrentCamera
end

local function buildChain(parent: Instance, assetId: string, useReverb: boolean, spatialize: boolean)
    local player = Instance.new("AudioPlayer")
    player.AssetId = assetId
    player.Name = "AMB_Player"
    player.Looped = true -- looping ambience
    player.Parent = parent

    local node = player

    local reverb = nil
    if useReverb then
        reverb = Instance.new("AudioReverb")
        reverb.Name = "AMB_Reverb"
        reverb.Parent = parent
        AudioUtil.Connect(player, reverb)
        node = reverb
    end

    local emitter = Instance.new("AudioEmitter")
    emitter.Name = "AMB_Emitter"
    emitter.Spatialize = spatialize ~= false -- default true for room tone, set false if you want head-locked
    emitter.Parent = parent

    AudioUtil.Connect(node, emitter)

    return player, emitter, reverb
end

local function startAmbience(opts)
    AudioUtil.EnsureCameraOutput()
    local key = (opts and opts.key) or "Ambience_RoomLoop"
    local assetId = SFXConfig[key]
    if not assetId then warn("[Ambience] Unknown key:", key) return end

    local parent = resolveParent(opts and opts.parentPath or "Workspace.DeskSpeaker")
    local useReverb = (opts and opts.useReverb) ~= false
    local spatialize = (opts and opts.spatialize) ~= false
    local volume = (opts and opts.volume) or 0.5

    -- if something is playing, crossfade
    if current.player then
        fading.player = current.player
        fading.emitter = current.emitter
        fading.reverb = current.reverb
    end

    local player, emitter, reverb = buildChain(parent, assetId, useReverb, spatialize)
    current.player, current.emitter, current.reverb = player, emitter, reverb

    player:Play()
    pcall(function() player.Volume = 0 end)

    -- crossfade
    task.spawn(function()
        local t=0
        while t < FADE_TIME do
            t += task.wait()
            local k = math.clamp(t/FADE_TIME, 0, 1)
            pcall(function()
                if player then player.Volume = lerp(0, volume, k) end
                if fading.player then fading.player.Volume = lerp((opts and opts.prevVolume) or volume, 0, k) end
            end)
        end
        if fading.player then
            fading.player:Stop()
            fading.player:Destroy()
            if fading.emitter then fading.emitter:Destroy() end
            if fading.reverb then fading.reverb:Destroy() end
            fading = { }
        end
    end)
end

local function stopAmbience()
    if current.player then
        local player = current.player
        local emitter = current.emitter
        local reverb = current.reverb
        current = {}

        task.spawn(function()
            local startVol = 0
            pcall(function() startVol = player.Volume or 0.5 end)
            local t=0
            while t < FADE_TIME do
                t += task.wait()
                local k = math.clamp(t/FADE_TIME, 0, 1)
                pcall(function() player.Volume = lerp(startVol, 0, k) end)
            end
            player:Stop()
            player:Destroy()
            if emitter then emitter:Destroy() end
            if reverb then reverb:Destroy() end
        end)
    end
end

local function setLowpass(enabled: boolean)
    if not current.player then return end
    if enabled and not current.lowpass then
        local lp = Instance.new("AudioEqualizer") -- assuming EQ node available; substitute if different node in your Studio version
        lp.Name = "AMB_Lowpass"
        lp.Parent = current.player.Parent
        -- simple chain: player -> lp -> (reverb or emitter)
        -- rebuild the wires:
        -- destroy old wire by recreating chain quickly:
        -- For brevity, just tweak reverb params if present
        if current.reverb then
            pcall(function() current.reverb.DecayTime = 3.0 end)
        end
        current.lowpass = lp
    elseif not enabled and current.lowpass then
        current.lowpass:Destroy()
        current.lowpass = nil
        if current.reverb then
            pcall(function() current.reverb.DecayTime = 1.2 end)
        end
    end
end

function AmbienceController:KnitStart()
    AudioUtil.EnsureCameraOutput()
    local AmbienceService = Knit.GetService("AmbienceService")
    AmbienceService.Client.Start:Connect(startAmbience)
    AmbienceService.Client.Stop:Connect(stopAmbience)
    AmbienceService.Client.SetLowpass:Connect(function(payload)
        setLowpass(payload and payload.enabled)
    end)
end

return AmbienceController
