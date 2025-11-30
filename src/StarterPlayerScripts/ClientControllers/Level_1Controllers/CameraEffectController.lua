--[[
	CameraEffectController
	Coordinator controller that provides unified access to camera systems.
	
	The actual functionality is split into:
	- CameraController: Core camera mechanics, mouse look, shake
	- CameraUIController: Visual overlay UI elements
	- PhotoTargetController: Target detection, crosshair, gaze progress
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local CameraEffectController = Knit.CreateController {
	Name = "CameraEffectController",
}

-- === KNIT LIFECYCLE ===

function CameraEffectController:KnitInit()
	-- Controllers are initialized automatically by Knit
end

function CameraEffectController:KnitStart()
	print("[CameraEffectController] Camera system initialized (coordinator)")
end

-- === PUBLIC METHODS (delegates to sub-controllers) ===

function CameraEffectController:GetCameraController()
	return Knit.GetController("CameraController")
end

function CameraEffectController:GetCameraUIController()
	return Knit.GetController("CameraUIController")
end

function CameraEffectController:GetPhotoTargetController()
	return Knit.GetController("PhotoTargetController")
end

-- Convenience methods that delegate to sub-controllers

function CameraEffectController:Show()
	local ui = self:GetCameraUIController()
	if ui then ui:Show() end
end

function CameraEffectController:Hide()
	local ui = self:GetCameraUIController()
	if ui then ui:Hide() end
end

function CameraEffectController:Toggle()
	local ui = self:GetCameraUIController()
	if ui then ui:Toggle() end
end

function CameraEffectController:IsVisible()
	local ui = self:GetCameraUIController()
	return ui and ui:IsVisible() or false
end

function CameraEffectController:ToggleNightVision()
	local ui = self:GetCameraUIController()
	return ui and ui:ToggleNightVision() or false
end

function CameraEffectController:EnableNightVision()
	local ui = self:GetCameraUIController()
	if ui then ui:EnableNightVision() end
end

function CameraEffectController:DisableNightVision()
	local ui = self:GetCameraUIController()
	if ui then ui:DisableNightVision() end
end

function CameraEffectController:IsNightVisionEnabled()
	local ui = self:GetCameraUIController()
	return ui and ui:IsNightVisionEnabled() or false
end

function CameraEffectController:GetZoomLevel()
	local cam = self:GetCameraController()
	return cam and cam:GetZoomLevel() or 1
end

function CameraEffectController:SetZoomLevel(zoom)
	local cam = self:GetCameraController()
	if cam then cam:SetZoomLevel(zoom) end
end

function CameraEffectController:LockCursor()
	local cam = self:GetCameraController()
	if cam then cam:LockCursor() end
end

function CameraEffectController:UnlockCursor()
	local cam = self:GetCameraController()
	if cam then cam:UnlockCursor() end
end

function CameraEffectController:EnableDebugGizmos()
	local target = self:GetPhotoTargetController()
	if target then target:EnableDebugGizmos() end
end

function CameraEffectController:DisableDebugGizmos()
	local target = self:GetPhotoTargetController()
	if target then target:DisableDebugGizmos() end
end

function CameraEffectController:ToggleDebugGizmos()
	local target = self:GetPhotoTargetController()
	return target and target:ToggleDebugGizmos() or false
end

function CameraEffectController:IsLookingAtTarget()
	local target = self:GetPhotoTargetController()
	return target and target:IsLookingAtTarget() or false
end

function CameraEffectController:GetGazeProgress()
	local target = self:GetPhotoTargetController()
	return target and target:GetGazeProgress() or 0
end

return CameraEffectController
