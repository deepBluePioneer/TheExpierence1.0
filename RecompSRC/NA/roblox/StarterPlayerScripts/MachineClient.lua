--!strict
--[[
	Client input → UnreliableRemoteEvent.
	Place as LocalScript under StarterPlayerScripts.
	Charge = ButtonA / Space / Left Mouse (hold).
	Dismount = ButtonB / F / ButtonX.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild("MachineRemotes")
local MachineTypes = require(ReplicatedStorage:WaitForChild("MachineSystem"):WaitForChild("MachineTypes"))

local inputRemote = remotesFolder:WaitForChild(MachineTypes.RemoteNames.Input) :: UnreliableRemoteEvent
local dismountRemote = remotesFolder:WaitForChild(MachineTypes.RemoteNames.Dismount) :: RemoteEvent

local chargeHeld = false
local riding = false
local gamepadSteer = 0
local gamepadForward = 0

-- Camera client sets this attribute on player for sync
player:GetAttributeChangedSignal("MachineRiding"):Connect(function()
	riding = player:GetAttribute("MachineRiding") == true
end)

local function readStick(): (number, number)
	local steer, forward = gamepadSteer, gamepadForward

	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		steer -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		steer += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		forward += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		forward -= 1
	end

	return math.clamp(steer, -1, 1), math.clamp(forward, -1, 1)
end

UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		gamepadSteer = input.Position.X
		gamepadForward = input.Position.Y
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if
		input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.ButtonA
		or input.UserInputType == Enum.UserInputType.MouseButton1
	then
		chargeHeld = true
	end
	if
		input.KeyCode == Enum.KeyCode.F
		or input.KeyCode == Enum.KeyCode.ButtonB
		or input.KeyCode == Enum.KeyCode.ButtonX
	then
		if riding then
			dismountRemote:FireServer()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if
		input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.ButtonA
		or input.UserInputType == Enum.UserInputType.MouseButton1
	then
		chargeHeld = false
	end
end)

RunService.RenderStepped:Connect(function()
	riding = player:GetAttribute("MachineRiding") == true
	if not riding then
		return
	end
	local steer, forward = readStick()
	inputRemote:FireServer({
		Steer = steer,
		Forward = forward,
		ChargeHeld = chargeHeld,
	})
end)
