-- Client/Controllers/TerminalGUITestController.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Packages = ReplicatedStorage.Packages

local Signal = require(Packages.Signal)

local TerminalGUITestController = Knit.CreateController { Name = "TerminalGUITestController" }

-- Exported signals
TerminalGUITestController.Signals = {
	RightHandTargetChanged = Signal.new(),
	RightHandPoleChanged   = Signal.new(),
	LeftHandTargetChanged  = Signal.new(),
	LeftHandPoleChanged    = Signal.new(),
}

local function init()
	local Iris = Knit.GetController("irisInitController"):GetIris()

	-- Snap to 0.1 helper
	local function snap01(v: number): number
		return math.round(v * 10) / 10
	end

	local function newVec3State(x, y, z)
		return {
			X = Iris.State(snap01(x)),
			Y = Iris.State(snap01(y)),
			Z = Iris.State(snap01(z)),
		}
	end

	-- === Default Values ===
	local rightTarget = newVec3State(1.048, 0.712, -1.196)
	local leftTarget  = newVec3State(-0.916, 0.437, -1.776)
	local rightPole   = newVec3State(0, 0, 0)
	local leftPole    = newVec3State(0, 0, 0)

	local function connectAxisSignal(state, signal, axis)
		state:onChange(function(newVal)
			local snapped = snap01(newVal)
			if snapped ~= newVal then
				state:set(snapped) -- force display to match
			end
			signal:Fire(axis, snapped)
		end)

		-- Force emit once at init (so IK controller gets the values)
		signal:Fire(axis, snap01(state:get()))
	end

	local function connectVec3Signals(vecState, signal)
		connectAxisSignal(vecState.X, signal, "X")
		connectAxisSignal(vecState.Y, signal, "Y")
		connectAxisSignal(vecState.Z, signal, "Z")
	end

	-- Connect all signal bindings
	connectVec3Signals(rightTarget, TerminalGUITestController.Signals.RightHandTargetChanged)
	connectVec3Signals(rightPole,   TerminalGUITestController.Signals.RightHandPoleChanged)
	connectVec3Signals(leftTarget,  TerminalGUITestController.Signals.LeftHandTargetChanged)
	connectVec3Signals(leftPole,    TerminalGUITestController.Signals.LeftHandPoleChanged)

	-- Iris UI Rendering
	Iris:Connect(function()
		local windowSize = Iris.State(Vector2.new(420, 460))
		local isOpen = Iris.State(true)

		if Iris.Window({ "Transform & IK Controls" }, { size = windowSize, isOpened = isOpen }) then
			local function drawVec3Tree(label, vec)
                if Iris.Tree({ label }) then
                    Iris.SliderNum({ "X" }, vec.X, 0.001, -1000, 1000)
                    Iris.SliderNum({ "Y" }, vec.Y, 0.001, -1000, 1000)
                    Iris.SliderNum({ "Z" }, vec.Z, 0.001, -1000, 1000)
                    Iris.End()
                end
            end




			drawVec3Tree("Right Hand Target", rightTarget)
			drawVec3Tree("Right Hand Pole",   rightPole)
			Iris.Separator()
			drawVec3Tree("Left Hand Target",  leftTarget)
			drawVec3Tree("Left Hand Pole",    leftPole)

			Iris.End()
		end
	end)
end

function TerminalGUITestController:KnitInit() end

function TerminalGUITestController:KnitStart()
	init()
end

return TerminalGUITestController
