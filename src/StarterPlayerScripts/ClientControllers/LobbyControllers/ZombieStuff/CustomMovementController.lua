-- Client/Controllers/CustomMovementController.lua

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local LocalPlayer = Players.LocalPlayer

local CustomMovementController = Knit.CreateController {
	Name = "CustomMovementController"
}

-- Constants
local ACTION_MOVE = "MoveInput"

-- Movement input state
local moveVector = Vector3.zero
local hrp = nil
local humanoid = nil

-- Key → movement vector mapping (local space)
local KEY_DIRECTIONS = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
	[Enum.KeyCode.Up] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.Down] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.Left] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.Right] = Vector3.new(1, 0, 0),
}

-- Handle WASD/Arrow input via ContextActionService
local function onMoveAction(actionName, inputState, inputObj)
	local key = inputObj.KeyCode
	local dir = KEY_DIRECTIONS[key]
	if not dir then return end

	if inputState == Enum.UserInputState.Begin then
		moveVector += dir
	elseif inputState == Enum.UserInputState.End then
		moveVector -= dir
	end
end

-- Apply movement every frame based on input state
local function updateMovement()
	if not hrp or not humanoid then return end

	if moveVector.Magnitude > 0 then
		-- Normalize and transform to world space based on character's current facing
		local moveDir = moveVector.Unit
		local worldDir = hrp.CFrame:VectorToWorldSpace(moveDir)
		humanoid:Move(worldDir, false)
	else
		humanoid:Move(Vector3.zero, false)
	end
end

-- Bind input for WASD/Arrow keys
local function bindMovementControls()
	ContextActionService:BindAction(ACTION_MOVE, onMoveAction, false,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right
	)
end

-- Character setup
local function onCharacterAdded(character)
	hrp = character:WaitForChild("HumanoidRootPart", 2)
	humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = false
	end
end

function init()
		if LocalPlayer.Character then
		onCharacterAdded(LocalPlayer.Character)
	end

	LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

	bindMovementControls()

	RunService.RenderStepped:Connect(updateMovement)
end

-- Knit lifecycle
function CustomMovementController:KnitStart()

end

return CustomMovementController
