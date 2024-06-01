--[[ --------------------------------------------------------------------

-- 4thAxis
-- 6/20/22

	MIT License

	Copyright (c) 2022 4thAxis

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
	
]] --------------------------------------------------------------------



local Module = {}
Module.Connections = {}

--------------------------------------------------------------------
---------------------------  Imports   -----------------------------
--------------------------------------------------------------------

local CameraModes = require(script.Parent:WaitForChild("CameraModes"))

--------------------------------------------------------------------
--------------------------  Services  ------------------------------
--------------------------------------------------------------------

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
--------------------------------------------------------------------
--------------------------  Privates  ------------------------------
--------------------------------------------------------------------

local function LockCenter(Input)
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end


local function MouseMovementTrack(_, Input, Object)
	if Input == Enum.UserInputState.Change then
		CameraModes.OverTheShoulder(nil, CameraModes.CameraAngleX-Object.Delta.X, math.clamp(CameraModes.CameraAngleY-Object.Delta.Y*0.4, -75, 75))
	end
end
local function TrackPrimaryPart(primaryPart)
	if primaryPart then
		local cameraOffset = CFrame.new(0, 10, 20) -- Adjust the offset as needed
		local targetCFrame = primaryPart.CFrame * cameraOffset * CFrame.Angles(math.rad(-10), 0, 0) -- Look slightly downward
		targetCFrame = CFrame.lookAt(targetCFrame.Position, primaryPart.Position)

		local tweenInfo = TweenInfo.new(
			0.15, -- Time
			Enum.EasingStyle.Linear, -- EasingStyle
			Enum.EasingDirection.Out, -- EasingDirection
			0, -- RepeatCount (0 = no repeat)
			false, -- Reverses (tween does not reverse back)
			0 -- DelayTime
		)

		local tween = TweenService:Create(Camera, tweenInfo, {CFrame = targetCFrame})
		tween:Play()
	end
end


--------------------------------------------------------------------
-------------------------  Functions  ------------------------------
--------------------------------------------------------------------

---------------------------
----    Shift Lock     ----
---------------------------

function Module.TrackPrimaryPartCamera(primaryPart)
	if Module.Connections.LockCenter then
		Module.Connections.LockCenter:Disconnect()
		Module.Connections.LockCenter = nil
	end
	--ContextActionService:UnbindAction("MouseMovementTrack")
	--RunService:UnbindFromRenderStep("ShiftLock")
	RunService:BindToRenderStep("TrackPrimaryPart", Enum.RenderPriority.Camera.Value, function()
		TrackPrimaryPart(primaryPart)
	end)
end


function Module.EnableShiftLockCamera()
	Module.Connections.LockCenter = UserInputService.InputBegan:Connect(LockCenter)
--	ContextActionService:BindAction("MouseMovementTrack", MouseMovementTrack, false, Enum.UserInputType.MouseMovement, Enum.UserInputType.Touch)
	RunService:BindToRenderStep("ShiftLock", Enum.RenderPriority.Camera.Value, CameraModes.OverTheShoulder)
end

function Module.DisableShiftLockCamera()
	if not Module.Connections.LockCenter and not Module.Connections.MouseMovementTrack then return end

	Module.Connections.LockCenter:Disconnect()
	ContextActionService:UnbindAction("MouseMovementTrack")
	RunService:UnbindFromRenderStep("ShiftLock")
end

---------------------------
---- Isometric Camera  ----
---------------------------

function Module.EnableIsometricCamera()
	RunService:BindToRenderStep("IsometricCamera", Enum.RenderPriority.Camera.Value, CameraModes.IsometricCamera)

end

function Module.DisableIsometricCamera()
	RunService:UnbindFromRenderStep("IsometricCamera")
end

---------------------------
----  Top Down Camera  ----
---------------------------

function Module.EnableTopDownCamera()
	RunService:BindToRenderStep("TopDown", Enum.RenderPriority.Camera.Value, CameraModes.TopDownCamera)

end 

function Module.DisableTopDownCamera()
	RunService:UnbindFromRenderStep("TopDown")

end

---------------------------
---- SideScrollCamera  ----
---------------------------

function Module.EnableSideScrollingCamera()
	RunService:BindToRenderStep("SideScroll", Enum.RenderPriority.Camera.Value, CameraModes.SideScrollingCamera)
end

function Module.DisableSideScrollingCamera()
	RunService:UnbindFromRenderStep("SideScroll")

end

---------------------------
----   Follow Mouse    ----
---------------------------

function Module.FollowMouse()
	Module.DisableShiftLockCamera()
	RunService:BindToRenderStep("FollowMouse", Enum.RenderPriority.Camera.Value, CameraModes.FollowMouse)
end

function Module.StopFollowingMouse()
	RunService:UnbindFromRenderStep("FollowMouse")
end

---------------------------
----    Face Mouse     ----
---------------------------

function Module.FaceCharacterToMouse()
	RunService:BindToRenderStep("FaceCharacterToMouse", Enum.RenderPriority.Character.Value, CameraModes.FaceCharacterToMouse)
end

function Module.StopFacingMouse()
	RunService:UnbindFromRenderStep("FaceCharacterToMouse")
end

---------------------------
---- Head Follow Mouse ----
---   (Experimental)   ----
---------------------------

function Module.HeadFollowCamera()
	RunService:BindToRenderStep("HeadFollowCamera", Enum.RenderPriority.Character.Value, CameraModes.HeadFollowCamera)
end

function Module.StopHeadFollowCamera()
	RunService:UnbindFromRenderStep("HeadFollowCamera")
end



return Module
