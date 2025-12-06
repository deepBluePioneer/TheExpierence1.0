--[[
	DebugVisualsController
	Uses Iris GUI to toggle and configure debug visualizations in other controllers.
	
	Controls debug settings for:
	- OctoEntityController (vision spheres, rays, hit points)
	- SplinePathController (path lines, control points)
	- PhotoTargetController (raycasts, hit spheres)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Iris = require(Packages.iris)

local DebugVisualsController = Knit.CreateController {
	Name = "DebugVisualsController",
}

-- Controller references (set in KnitStart)
local OctoEntityController = nil
local SplinePathController = nil
local PhotoTargetController = nil
local StreamingCullingController = nil

-- Iris States
local IrisStates = {}

--=============================================
-- PRIVATE METHODS
--=============================================

local function log(...)
	print("[DebugVisualsController]", ...)
end

-- Safe getter for controller configs
local function getConfig(controller, configName)
	if controller and controller[configName] then
		return controller[configName]
	end
	return nil
end

--=============================================
-- IRIS UI
--=============================================

function DebugVisualsController:InitializeIris()
	-- DISABLED: Iris windows disabled
	-- Disable Iris completely
	Iris.Disabled = true
	
	-- Get controller references (keep these for potential future use)
	OctoEntityController = Knit.GetController("OctoEntityController")
	SplinePathController = Knit.GetController("SplinePathController")
	PhotoTargetController = Knit.GetController("PhotoTargetController")
	
	-- Try to get StreamingCullingController (may not exist)
	pcall(function()
		StreamingCullingController = Knit.GetController("StreamingCullingController")
	end)
	
	-- Initialize states from actual controller configs
	-- self:InitializeStatesFromControllers()
	
	-- Connect UI drawing
	-- Iris:Connect(function()
	-- 	self:DrawDebugVisualsWindow()
	-- end)
	
	log("Iris GUI disabled - debug visuals panel not available")
end

function DebugVisualsController:InitializeStatesFromControllers()
	-- OctoEntity debug states
	IrisStates.OctoDebugVision = Iris.State(true)
	IrisStates.OctoVisionRadius = Iris.State(15)
	IrisStates.OctoDebugSphereColor = Iris.State(Color3.fromRGB(50, 255, 50))
	IrisStates.OctoDebugHitColor = Iris.State(Color3.fromRGB(255, 50, 50))
	IrisStates.OctoDebugForceColor = Iris.State(Color3.fromRGB(255, 255, 0))
	IrisStates.OctoDebugPlayerColor = Iris.State(Color3.fromRGB(0, 150, 255))
	
	-- SplinePath debug states
	IrisStates.SplineDebugEnabled = Iris.State(true)
	IrisStates.SplinePathColor = Iris.State(Color3.fromRGB(255, 150, 0))
	IrisStates.SplinePointColor = Iris.State(Color3.fromRGB(255, 255, 0))
	IrisStates.SplinePointRadius = Iris.State(1)
	
	-- PhotoTarget debug states
	IrisStates.PhotoDebugEnabled = Iris.State(true)
	IrisStates.PhotoDebugOnClick = Iris.State(true)
	IrisStates.PhotoDebugLineColor = Iris.State(Color3.fromRGB(0, 255, 0))
	IrisStates.PhotoDebugMissColor = Iris.State(Color3.fromRGB(255, 0, 0))
	IrisStates.PhotoDebugNoTagColor = Iris.State(Color3.fromRGB(255, 255, 0))
	IrisStates.PhotoDebugHitPointSize = Iris.State(0.5)
	
	-- StreamingCulling states
	IrisStates.CullingSyncWithFog = Iris.State(true)
	IrisStates.CullingTargetRadius = Iris.State(180)
	IrisStates.CullingMinRadius = Iris.State(32)
	IrisStates.CullingFadeEnabled = Iris.State(false)
	IrisStates.CullingAggressiveMode = Iris.State(true)
	IrisStates.CullingDebugEnabled = Iris.State(false)
end

function DebugVisualsController:DrawDebugVisualsWindow()
	local window = Iris.Window({"🔧 Debug Visuals"})
	
	if window.state.isOpened.value and window.state.isUncollapsed.value then
		-- === OCTO ENTITY DEBUG ===
		local octoHeader = Iris.CollapsingHeader({"🐙 OctoEntity Debug"})
		if octoHeader.state.isUncollapsed.value then
			
			if Iris.Checkbox({"Vision Debug Enabled"}, {isChecked = IrisStates.OctoDebugVision}).state.isChecked.value then
				self:ApplyOctoConfig("DebugVisionEnabled", IrisStates.OctoDebugVision:get())
			end
			
			Iris.SliderNum({"Vision Radius", 1, 5, 50}, {number = IrisStates.OctoVisionRadius})
			if IrisStates.OctoVisionRadius:get() then
				self:ApplyOctoConfig("VisionRadius", IrisStates.OctoVisionRadius:get())
			end
			
			Iris.Separator()
			Iris.Text({"Debug Colors:"})
			
			Iris.InputColor3({"Sphere Color"}, {color = IrisStates.OctoDebugSphereColor})
			self:ApplyOctoConfig("DebugSphereColor", IrisStates.OctoDebugSphereColor:get())
			
			Iris.InputColor3({"Hit Color"}, {color = IrisStates.OctoDebugHitColor})
			self:ApplyOctoConfig("DebugHitColor", IrisStates.OctoDebugHitColor:get())
			
			Iris.InputColor3({"Force Color"}, {color = IrisStates.OctoDebugForceColor})
			self:ApplyOctoConfig("DebugForceColor", IrisStates.OctoDebugForceColor:get())
			
			Iris.InputColor3({"Player Line Color"}, {color = IrisStates.OctoDebugPlayerColor})
			self:ApplyOctoConfig("DebugPlayerColor", IrisStates.OctoDebugPlayerColor:get())
		end
		Iris.End() -- End CollapsingHeader
		
		Iris.Separator()
		
		-- === SPLINE PATH DEBUG ===
		local splineHeader = Iris.CollapsingHeader({"🛤️ SplinePath Debug"})
		if splineHeader.state.isUncollapsed.value then
			
			if Iris.Checkbox({"Path Debug Enabled"}, {isChecked = IrisStates.SplineDebugEnabled}).state.isChecked.value then
				self:ApplySplineConfig("DebugEnabled", IrisStates.SplineDebugEnabled:get())
			end
			
			Iris.Separator()
			Iris.Text({"Path Visualization:"})
			
			Iris.InputColor3({"Path Color"}, {color = IrisStates.SplinePathColor})
			self:ApplySplineConfig("PathColor", IrisStates.SplinePathColor:get())
			
			Iris.InputColor3({"Point Color"}, {color = IrisStates.SplinePointColor})
			self:ApplySplineConfig("PointColor", IrisStates.SplinePointColor:get())
			
			Iris.SliderNum({"Point Radius", 0.1, 0.1, 5}, {number = IrisStates.SplinePointRadius})
			self:ApplySplineConfig("PointRadius", IrisStates.SplinePointRadius:get())
		end
		Iris.End() -- End CollapsingHeader
		
		Iris.Separator()
		
		-- === PHOTO TARGET DEBUG ===
		local photoHeader = Iris.CollapsingHeader({"📷 PhotoTarget Debug"})
		if photoHeader.state.isUncollapsed.value then
			
			if Iris.Checkbox({"Gizmos Enabled"}, {isChecked = IrisStates.PhotoDebugEnabled}).state.isChecked.value then
				self:ApplyPhotoConfig("DebugGizmosEnabled", IrisStates.PhotoDebugEnabled:get())
			end
			
			if Iris.Checkbox({"Only Show On Click"}, {isChecked = IrisStates.PhotoDebugOnClick}).state.isChecked.value then
				self:ApplyPhotoConfig("DebugGizmosOnClick", IrisStates.PhotoDebugOnClick:get())
			end
			
			Iris.Separator()
			Iris.Text({"Debug Colors:"})
			
			Iris.InputColor3({"Hit Line Color"}, {color = IrisStates.PhotoDebugLineColor})
			self:ApplyPhotoConfig("DebugLineColor", IrisStates.PhotoDebugLineColor:get())
			
			Iris.InputColor3({"Miss Line Color"}, {color = IrisStates.PhotoDebugMissColor})
			self:ApplyPhotoConfig("DebugLineMissColor", IrisStates.PhotoDebugMissColor:get())
			
			Iris.InputColor3({"No Tag Color"}, {color = IrisStates.PhotoDebugNoTagColor})
			self:ApplyPhotoConfig("DebugLineNoTagColor", IrisStates.PhotoDebugNoTagColor:get())
			
			Iris.SliderNum({"Hit Point Size", 0.1, 0.1, 3}, {number = IrisStates.PhotoDebugHitPointSize})
			self:ApplyPhotoConfig("DebugHitPointSize", IrisStates.PhotoDebugHitPointSize:get())
		end
		Iris.End() -- End CollapsingHeader
		
		Iris.Separator()
		
		-- === STREAMING CULLING ===
		local cullingHeader = Iris.CollapsingHeader({"🌫️ Streaming Culling"})
		if cullingHeader.state.isUncollapsed.value then
			
			if StreamingCullingController then
				-- Show current stats
				local trackedCount = StreamingCullingController:GetTrackedCount()
				local cullingRadius = StreamingCullingController:GetCullingRadius()
				Iris.Text({string.format("Tracked Entities: %d", trackedCount)})
				Iris.Text({string.format("Current Culling Radius: %.0f studs", cullingRadius)})
				
				Iris.Separator()
				
				if Iris.Checkbox({"Sync With Fog"}, {isChecked = IrisStates.CullingSyncWithFog}).state.isChecked.value then
					self:ApplyCullingConfig("SyncWithFog", IrisStates.CullingSyncWithFog:get())
				end
				
				if not IrisStates.CullingSyncWithFog:get() then
					Iris.SliderNum({"Target Radius", 10, 64, 1000}, {number = IrisStates.CullingTargetRadius})
					if IrisStates.CullingTargetRadius:get() then
						StreamingCullingController:SetCullingRadius(IrisStates.CullingTargetRadius:get())
					end
				end
				
				Iris.SliderNum({"Min Radius (Always Visible)", 10, 16, 256}, {number = IrisStates.CullingMinRadius})
				if IrisStates.CullingMinRadius:get() then
					StreamingCullingController:SetMinRadius(IrisStates.CullingMinRadius:get())
				end
				
				Iris.Separator()
				
				if Iris.Checkbox({"Aggressive Mode (Instant Cull)"}, {isChecked = IrisStates.CullingAggressiveMode}).state.isChecked.value then
					self:ApplyCullingConfig("AggressiveMode", IrisStates.CullingAggressiveMode:get())
				end
				
				if Iris.Checkbox({"Smooth Fade (slower)"}, {isChecked = IrisStates.CullingFadeEnabled}).state.isChecked.value then
					self:ApplyCullingConfig("EnableFade", IrisStates.CullingFadeEnabled:get())
				end
				
				if Iris.Checkbox({"Debug Logging"}, {isChecked = IrisStates.CullingDebugEnabled}).state.isChecked.value then
					StreamingCullingController:SetDebugEnabled(IrisStates.CullingDebugEnabled:get())
				end
				
				Iris.Separator()
				
				-- Manual rescan button
				if Iris.Button({"🔄 Rescan Workspace Folders"}).clicked() then
					StreamingCullingController:ScanWorkspaceFolders()
					log("Rescanned workspace folders")
				end
			else
				Iris.Text({"StreamingCullingController not found"})
			end
		end
		Iris.End() -- End CollapsingHeader
		
		Iris.Separator()
		
		-- === QUICK ACTIONS ===
		Iris.SeparatorText({"Quick Actions"})
		
		if Iris.Button({"Enable All Debug"}).clicked() then
			IrisStates.OctoDebugVision:set(true)
			IrisStates.SplineDebugEnabled:set(true)
			IrisStates.PhotoDebugEnabled:set(true)
			self:ApplyAllConfigs()
			log("All debug visuals enabled")
		end
		
		Iris.SameLine()
		if Iris.Button({"Disable All Debug"}).clicked() then
			IrisStates.OctoDebugVision:set(false)
			IrisStates.SplineDebugEnabled:set(false)
			IrisStates.PhotoDebugEnabled:set(false)
			self:ApplyAllConfigs()
			log("All debug visuals disabled")
		end
		Iris.End() -- End SameLine
		
		if Iris.Button({"Reset Colors to Default"}).clicked() then
			-- Octo defaults
			IrisStates.OctoDebugSphereColor:set(Color3.fromRGB(50, 255, 50))
			IrisStates.OctoDebugHitColor:set(Color3.fromRGB(255, 50, 50))
			IrisStates.OctoDebugForceColor:set(Color3.fromRGB(255, 255, 0))
			IrisStates.OctoDebugPlayerColor:set(Color3.fromRGB(0, 150, 255))
			-- Spline defaults
			IrisStates.SplinePathColor:set(Color3.fromRGB(255, 150, 0))
			IrisStates.SplinePointColor:set(Color3.fromRGB(255, 255, 0))
			-- Photo defaults
			IrisStates.PhotoDebugLineColor:set(Color3.fromRGB(0, 255, 0))
			IrisStates.PhotoDebugMissColor:set(Color3.fromRGB(255, 0, 0))
			IrisStates.PhotoDebugNoTagColor:set(Color3.fromRGB(255, 255, 0))
			
			self:ApplyAllConfigs()
			log("Colors reset to defaults")
		end
	end
	
	Iris.End()
end

--=============================================
-- CONFIG APPLICATION
--=============================================

function DebugVisualsController:ApplyOctoConfig(key, value)
	if OctoEntityController and OctoEntityController.OCTO_CONFIG then
		OctoEntityController.OCTO_CONFIG[key] = value
	end
end

function DebugVisualsController:ApplySplineConfig(key, value)
	if SplinePathController and SplinePathController.PATH_CONFIG then
		SplinePathController.PATH_CONFIG[key] = value
	end
end

function DebugVisualsController:ApplyPhotoConfig(key, value)
	if PhotoTargetController and PhotoTargetController.TARGET_CONFIG then
		PhotoTargetController.TARGET_CONFIG[key] = value
	end
end

function DebugVisualsController:ApplyCullingConfig(key, value)
	if StreamingCullingController and StreamingCullingController.CULLING_CONFIG then
		StreamingCullingController.CULLING_CONFIG[key] = value
	end
end

function DebugVisualsController:ApplyAllConfigs()
	-- Octo
	self:ApplyOctoConfig("DebugVisionEnabled", IrisStates.OctoDebugVision:get())
	self:ApplyOctoConfig("VisionRadius", IrisStates.OctoVisionRadius:get())
	self:ApplyOctoConfig("DebugSphereColor", IrisStates.OctoDebugSphereColor:get())
	self:ApplyOctoConfig("DebugHitColor", IrisStates.OctoDebugHitColor:get())
	self:ApplyOctoConfig("DebugForceColor", IrisStates.OctoDebugForceColor:get())
	self:ApplyOctoConfig("DebugPlayerColor", IrisStates.OctoDebugPlayerColor:get())
	
	-- Spline
	self:ApplySplineConfig("DebugEnabled", IrisStates.SplineDebugEnabled:get())
	self:ApplySplineConfig("PathColor", IrisStates.SplinePathColor:get())
	self:ApplySplineConfig("PointColor", IrisStates.SplinePointColor:get())
	self:ApplySplineConfig("PointRadius", IrisStates.SplinePointRadius:get())
	
	-- Photo
	self:ApplyPhotoConfig("DebugGizmosEnabled", IrisStates.PhotoDebugEnabled:get())
	self:ApplyPhotoConfig("DebugGizmosOnClick", IrisStates.PhotoDebugOnClick:get())
	self:ApplyPhotoConfig("DebugLineColor", IrisStates.PhotoDebugLineColor:get())
	self:ApplyPhotoConfig("DebugLineMissColor", IrisStates.PhotoDebugMissColor:get())
	self:ApplyPhotoConfig("DebugLineNoTagColor", IrisStates.PhotoDebugNoTagColor:get())
	self:ApplyPhotoConfig("DebugHitPointSize", IrisStates.PhotoDebugHitPointSize:get())
end

--=============================================
-- KNIT LIFECYCLE
--=============================================

function DebugVisualsController:KnitInit()
	log("Initializing...")
end

function DebugVisualsController:KnitStart()
	log("Starting...")
	
	-- Initialize Iris and connect to other controllers
	self:InitializeIris()
	
	log("Ready! Debug visuals panel available")
end

return DebugVisualsController
