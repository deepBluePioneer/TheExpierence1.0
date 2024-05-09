local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Shake = require(Packages.Shake)

local CameraController = Knit.CreateController { Name = "CameraController" }

function CameraController:KnitStart()
    -- Automatically start the shake when the controller starts
    self:StartShake()
end

function CameraController:KnitInit()
    -- Initialize the camera shake with enhanced horizontal and vertical translation
    self.shake = Shake.new()
    self.shake.Amplitude = 0.2  -- Small amplitude to keep the shake subtle
    self.shake.Frequency = 0.8  -- Slower frequency for smoother effects
    self.shake.Sustain = true  -- Continuous shake
    self.shake.FadeInTime = 2  -- Smooth and slow fade-in
    self.shake.FadeOutTime = 2  -- Smooth and slow fade-out
    self.shake.PositionInfluence = Vector3.new(0.3, 0.3, 0.05)  -- Increased X and Y for more horizontal and vertical movement
    self.shake.RotationInfluence = Vector3.new(0.02, 0.02, 0.02)  -- Minimal rotation influence to keep focus on translation
end

function CameraController:StartShake()
    local camera = workspace.CurrentCamera

    -- Keep the default camera type, do not set to scriptable
    self.shake:Start()

    -- Bind the shake effect directly to the camera's current CFrame
    local lastUpdateTime = tick()
    self.connection = RunService.RenderStepped:Connect(function()
        local deltaTime = tick() - lastUpdateTime
        lastUpdateTime = tick()

        local pos, rot, isDone = self.shake:Update()
        pos = pos * math.exp(-0.5 * deltaTime)  -- Applying damping for extra smoothness
        rot = rot * math.exp(-0.5 * deltaTime)
        camera.CFrame = camera.CFrame * CFrame.new(pos) * CFrame.Angles(rot.X, rot.Y, rot.Z)
    end)
end

function CameraController:StopShake()
    if self.connection then
        self.connection:Disconnect()
    end
    self.shake:Stop()
end

return CameraController
