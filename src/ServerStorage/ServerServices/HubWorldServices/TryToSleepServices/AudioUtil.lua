local AudioUtil = {}

function AudioUtil.Connect(source: Instance, target: Instance)
    local wire = Instance.new("Wire")
    wire.Parent = source
    wire.SourceInstance = source
    wire.TargetInstance = target
    return wire
end

-- Make/ensure a listener->output chain on the current camera (client)
function AudioUtil.EnsureCameraOutput()
    local cam = workspace.CurrentCamera
    local listener = cam:FindFirstChildOfClass("AudioListener")
    if not listener then
        listener = Instance.new("AudioListener")
        listener.Name = "Global_Listener"
        listener.Parent = cam
        local out = Instance.new("AudioDeviceOutput")
        out.Name = "Global_Output"
        out.Parent = listener
        AudioUtil.Connect(listener, out)
    end
    return listener
end

return AudioUtil
