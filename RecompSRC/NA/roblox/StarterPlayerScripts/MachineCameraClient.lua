--!strict
--[[
	Client camera chase for ride / on-foot.
	Place as LocalScript under StarterPlayerScripts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local MachineSystem = ReplicatedStorage:WaitForChild("MachineSystem")
local MachineTypes = require(MachineSystem:WaitForChild("MachineTypes"))
local CameraChase = require(MachineSystem:WaitForChild("CameraChase"))

local remotes = ReplicatedStorage:WaitForChild("MachineRemotes")
local cameraRemote = remotes:WaitForChild(MachineTypes.RemoteNames.CameraMode) :: RemoteEvent

local state = CameraChase.NewState()
local active = false

local function characterRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setOnFoot()
	player:SetAttribute("MachineRiding", false)
	active = true
	CameraChase.SetMode(state, "OnFoot", characterRoot())
end

local function setRiding(model: Model?)
	player:SetAttribute("MachineRiding", true)
	active = true
	local root = model and model.PrimaryPart
	CameraChase.SetMode(state, "Riding", root)
end

cameraRemote.OnClientEvent:Connect(function(mode: string, model: Model?)
	if mode == "Riding" and model then
		setRiding(model)
	else
		setOnFoot()
		-- Restore default cam after short delay if desired:
		-- camera.CameraType = Enum.CameraType.Custom
	end
end)

player.CharacterAdded:Connect(function()
	if player:GetAttribute("MachineRiding") ~= true then
		task.wait(0.1)
		-- Keep custom chase for consistency, or switch to Custom:
		camera.CameraType = Enum.CameraType.Custom
		active = false
		state.Subject = nil
	end
end)

UserInputService.InputChanged:Connect(function(input, gp)
	if gp or not active then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		CameraChase.AddOrbit(state, -input.Delta.X, -input.Delta.Y)
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		CameraChase.AddOrbit(state, -input.Position.X * 2, input.Position.Y * 2)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not active or not state.Subject then
		return
	end
	-- Refresh on-foot subject if character respawned
	if state.Mode == "OnFoot" then
		local root = characterRoot()
		if root ~= state.Subject then
			state.Subject = root
		end
	end
	if state.Subject then
		CameraChase.Step(state, camera, dt)
	end
end)
