local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local machineSINController = Knit.CreateController { Name = "machineSINController" }

function machineSINController:KnitInit()
    -- Initialization logic
end

function machineSINController:KnitStart()
    task.wait(5) -- Allow time for workspace replication

    local machines = CollectionService:GetTagged("machine")
    print("Found", #machines, "machines")

    for _, machine in ipairs(machines) do
        if not machine:IsDescendantOf(workspace) then continue end

        print("Machine:", machine:GetFullName())

        local controllerManager = machine:FindFirstChildWhichIsA("ControllerManager", true)
        local groundController = machine:FindFirstChildWhichIsA("GroundController", true)
        local groundSensor = machine:FindFirstChildWhichIsA("ControllerPartSensor", true)
        local rootPart = machine:FindFirstChild("RootPart") or machine:FindFirstChildWhichIsA("BasePart", true)

        if not (controllerManager and groundController and groundSensor and rootPart) then
            warn("Missing controller components for machine:", machine.Name)
            continue
        end

        -- Assign essential controller references
        groundSensor.UpdateType = "OnRead"
        controllerManager.RootPart = rootPart
        controllerManager.GroundSensor = groundSensor
        controllerManager.ActiveController = groundController

        -- Movement settings
        controllerManager.BaseMoveSpeed = 50
        controllerManager.BaseTurnSpeed = 5
        groundController.MoveSpeedFactor = 1
        groundController.TurnSpeedFactor = 1
        groundController.AccelerationTime = 0
        groundController.DecelerationTime = 0
        groundController.Friction = 1

        -- Hover bobbing config
        local baseOffset = 0.75
        local amplitude = 0.15
        local frequency = 1.5
        local currentOffset = baseOffset

        -- Movement input tracking
        local inputVector = Vector3.zero

        local function getMoveDirection()
            local cam = workspace.CurrentCamera
            if not cam then return Vector3.zero end

            local forward = cam.CFrame.LookVector * inputVector.Z
            local right = cam.CFrame.RightVector * inputVector.X
            local move = forward + right
            return move.Magnitude > 0 and move.Unit or Vector3.zero
        end

        -- Input events
        UserInputService.InputBegan:Connect(function(input, processed)
            if processed then return end
            if input.KeyCode == Enum.KeyCode.W then inputVector += Vector3.new(0, 0, 1) end
            if input.KeyCode == Enum.KeyCode.S then inputVector -= Vector3.new(0, 0, 1) end
            if input.KeyCode == Enum.KeyCode.A then inputVector -= Vector3.new(1, 0, 0) end
            if input.KeyCode == Enum.KeyCode.D then inputVector += Vector3.new(1, 0, 0) end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.W then inputVector -= Vector3.new(0, 0, 1) end
            if input.KeyCode == Enum.KeyCode.S then inputVector += Vector3.new(0, 0, 1) end
            if input.KeyCode == Enum.KeyCode.A then inputVector += Vector3.new(1, 0, 0) end
            if input.KeyCode == Enum.KeyCode.D then inputVector -= Vector3.new(1, 0, 0) end
        end)

        -- Continuous update
        RunService.RenderStepped:Connect(function()
            -- Hover offset bobbing
            local t = tick()
            local targetOffset = baseOffset + math.sin(t * frequency) * amplitude
            currentOffset += (targetOffset - currentOffset) * 0.1
            groundController.GroundOffset = currentOffset

            -- Apply movement and facing
            local moveDir = getMoveDirection()
            controllerManager.MovingDirection = moveDir
            controllerManager.FacingDirection = -moveDir -- optional
        end)
    end
end

return machineSINController
