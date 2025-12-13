--[[
	MachineController
	
	Main coordinator - handles seat detection and sets up physics.
	Currently just hover physics (no input).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local MachineController = Knit.CreateController {
	Name = "MachineController",
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STATE                                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local player = Players.LocalPlayer
local currentMachine = nil
local seat = nil

-- Controller references
local physicsController = nil
local cameraController = nil

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SEAT DETECTION                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function findMachineFromSeat(seatPart)
	local folder = seatPart.Parent
	if folder and folder:IsA("Folder") then
		local machine = folder.Parent
		if machine and machine:IsA("Model") then
			return machine
		end
	end
	return nil
end

local function enterMachine(machine)
	if not physicsController then
		warn("[MachineController] Physics controller not ready!")
		return
	end
	
	currentMachine = machine
	
	-- Setup physics
	if physicsController:SetupPhysics(machine) then
		print("[MachineController] Now in:", machine.Name)
		
		-- Enable camera
		if cameraController then
			cameraController:Enable()
		end
	end
end

local function exitMachine()
	if not currentMachine then return end
	
	-- Disable camera
	if cameraController then
		cameraController:Disable()
	end
	
	physicsController:ClearPhysics()
	
	currentMachine = nil
	seat = nil
	
	print("[MachineController] Exited machine")
end

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")
	
	humanoid.Seated:Connect(function(isSeated, seatPart)
		if isSeated and seatPart then
			local machine = findMachineFromSeat(seatPart)
			if machine and machine:FindFirstChild("ControllerManager") then
				seat = seatPart
				enterMachine(machine)
			end
		else
			if currentMachine then
				exitMachine()
			end
		end
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function MachineController:GetCurrentMachine()
	return currentMachine
end

function MachineController:IsInMachine()
	return currentMachine ~= nil
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function MachineController:KnitInit()
	print("[MachineController] Initializing...")
end

function MachineController:KnitStart()
	print("[MachineController] Started")
	
	-- Get controllers
	physicsController = Knit.GetController("MachinePhysicsController")
	cameraController = Knit.GetController("MachineCameraController")
	
	-- Character setup
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	
	print("[MachineController] Ready - Sit in a machine to hover!")
end

return MachineController
