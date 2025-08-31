local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local SFXConfig = require(ReplicatedStorage.Modules.Audio.SFXConfig)
local AudioUtil = require(ReplicatedStorage.Modules.Audio.AudioUtil)

local SFXController = Knit.CreateController { Name = "SFXController" }

local function resolveParent(path)
    if type(path) == "string" and path ~= "" then
        local seg = path:match("([^%.]+)$")
        local found = workspace:FindFirstChild(seg, true)
        if found then return found end
    end
    return workspace.CurrentCamera
end

local function playOneShot(payload)
    AudioUtil.EnsureCameraOutput()
    if not payload or not payload.key then return end
    local assetId = SFXConfig[payload.key]
    if not assetId then warn("[SFX] Unknown key:", payload.key) return end

    local parent = resolveParent(payload.parentPath or "Workspace.DeskSpeaker")
    local spatialize = (payload.spatialize ~= false)
    local volume = payload.volume

    -- Build minimal chain: Player -> (Emitter)
    local player = Instance.new("AudioPlayer")
    player.Name = "SFX_" .. payload.key
    player.AssetId = assetId
    player.Looped = false
    player.Parent = parent

    local emitter = Instance.new("AudioEmitter")
    emitter.Name = "SFX_Emitter"
    emitter.Spatialize = spatialize
    emitter.Parent = parent

    AudioUtil.Connect(player, emitter)
    if volume then pcall(function() player.Volume = volume end) end

    player:Play()

    task.spawn(function()
        task.wait(5)
        if player then player:Destroy() end
        if emitter then emitter:Destroy() end
    end)
end

function SFXController:KnitStart()
    AudioUtil.EnsureCameraOutput()
    local SFXService = Knit.GetService("SFXService")
    SFXService.Client.Play:Connect(playOneShot)
end

return SFXController
