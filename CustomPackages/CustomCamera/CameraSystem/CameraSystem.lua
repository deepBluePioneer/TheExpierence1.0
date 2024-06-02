

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
local Config = require(script.Parent.Configurations)
--------------------------------------------------------------------
--------------------------  Privates  ------------------------------
--------------------------------------------------------------------

local function LockCenter(Input)
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end




--------------------------------------------------------------------
-------------------------  Functions  ------------------------------
--------------------------------------------------------------------

---------------------------
----    Shift Lock     ----
---------------------------
-- Function to update the camera based on the target object's position
-- Function to update the camera based on the target object's position
local function UpdateCamera(TargetObject)
	local camera = workspace.CurrentCamera
	local targetPosition = TargetObject.Position
	local targetOrientation = TargetObject.Orientation
	
	-- Define the desired camera position relative to the target object
	--local cameraOffset = Vector3.new(0, 5, 10) -- This offset can be adjusted based on your needs
	local cameraOffset = Config.CamLockOffset
	-- Calculate the camera's position based on the target's position and rotation
	local cameraPosition = (CFrame.new(targetPosition) * CFrame.Angles(math.rad(targetOrientation.X), math.rad(targetOrientation.Y), math.rad(targetOrientation.Z))):PointToWorldSpace(cameraOffset)
	
	-- Set the camera's position and orientation
--	camera.CFrame = CFrame.new(cameraPosition, targetPosition)
	--CameraModes.OverTheShoulder(nil, cameraPosition.X-cameraPosition.X, math.clamp(cameraPosition.Y-cameraPosition.Y*0.4, -75, 75))


end
-- Function to enable the camera tracking
function Module.EnableCameraTracking(TargetObject)
	RunService:BindToRenderStep("TrackTargetObject", Enum.RenderPriority.Camera.Value, function()
		UpdateCamera(TargetObject)
	end)
end



local function MouseMovementTrack(_, Input, Object)
	if Input == Enum.UserInputState.Change then
		CameraModes.OverTheShoulder(nil, CameraModes.CameraAngleX-Object.Delta.X, math.clamp(CameraModes.CameraAngleY-Object.Delta.Y*0.4, -75, 75))
	end
end




function Module.EnableShiftLockCamera()
	Module.Connections.LockCenter = UserInputService.InputBegan:Connect(LockCenter)
	ContextActionService:BindAction("MouseMovementTrack", MouseMovementTrack, false, Enum.UserInputType.MouseMovement, Enum.UserInputType.Touch)
	RunService:BindToRenderStep("ShiftLock", Enum.RenderPriority.Camera.Value, CameraModes.OverTheShoulder)
end

function Module.DisableShiftLockCamera()
	if not Module.Connections.LockCenter and not Module.Connections.MouseMovementTrack then return end

	Module.Connections.LockCenter:Disconnect()
	ContextActionService:UnbindAction("MouseMovementTrack")
	RunService:UnbindFromRenderStep("ShiftLock")
end





---------------------------
----   Follow Mouse    ----
---------------------------

function Module.FollowMouse()
	Module.DisableShiftLockCamera()
	RunService:BindToRenderStep("FollowMouse", Enum.RenderPriority.Camera.Value, CameraModes.FollowMouse)
	
	--RunService:Heartbeat(CameraModes.FollowMouse)
	--RunService.Heartbeat:Connect(CameraModes.FollowMouse)
	
end

function Module.StopFollowingMouse()
	RunService:UnbindFromRenderStep("FollowMouse")
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
