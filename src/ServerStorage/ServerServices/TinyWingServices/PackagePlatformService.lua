local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

-- Timer and Replica modules
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaService = require(Replica.ReplicaService)
local Timer = require(Packages:WaitForChild("timer"))

local PackagePlatformService = Knit.CreateService {
	Name = "PackagePlatformService",
	Client = {},
	packages = {},
	playerHeldPackages = {}, -- Track stacks of packages per player: { [userId] = { package1, package2, ... } }
	playerFatigue = {},      -- Track fatigue per player: { [userId] = { value, replica, timer } }
}

-- Fatigue Replica class token
local FatigueClassToken = ReplicaService.NewClassToken("PlayerFatigue")

-- === CONFIG ===
local PLATFORM_TAG = "packagePlatform"
local PACKAGES_FOLDER_NAME = "SpawnedPackages"

local PACKAGE_CONFIG = {
	-- Cube size range
	SizeMin = Vector3.new(2, 2, 2),
	SizeMax = Vector3.new(4, 4, 4),
	
	-- Number of packages per platform
	PackagesPerPlatform = { Min = 3, Max = 6 },
	
	-- Spawn height above platform
	SpawnHeightAbove = 2,
	
	-- Spread radius on platform
	SpreadRadius = 4,
	
	-- Physics properties
	Anchored = false,
	CanCollide = true,
	
	-- Visual properties
	Material = Enum.Material.SmoothPlastic,
	Colors = {
		Color3.fromRGB(139, 90, 43),   -- Brown cardboard
		Color3.fromRGB(194, 178, 128), -- Tan
		Color3.fromRGB(160, 120, 80),  -- Light brown
		Color3.fromRGB(120, 80, 50),   -- Dark brown
		Color3.fromRGB(180, 140, 100), -- Beige
	},
	
	-- Proximity Prompt settings
	PromptActionText = "Pick Up",
	PromptObjectText = "Package",
	PromptHoldDuration = 0,
	PromptMaxDistance = 8,
	PromptKeyboardKey = Enum.KeyCode.E,
	
	-- Held position (above head)
	HeldHeightAboveHead = 1.5,
	
	-- Physics sway settings (lower values = more sway)
	Sway = {
		-- How many levels from bottom should wobble (rest are welded rigid)
		WobbleLevels = 0,  -- 0 = All packages welded, no wobble
		
		-- Values below only used if WobbleLevels > 0
		BaseMaxForce = 80000,
		BaseMaxTorque = 100000,
		BaseResponsiveness = 60,
		BaseMaxVelocity = 40,
		BaseMaxAngularVelocity = 8,
	},
	
	-- Fatigue system settings
	Fatigue = {
		MaxFatigue = 100,                -- Maximum fatigue value
		BaseDrainRate = 0.2,             -- Base drain per second (no packages) - VERY SLOW
		DrainPerPackage = 0.3,           -- Additional drain per package held - VERY SLOW
		RecoveryRate = 2,                -- Recovery per second when not holding packages
		TickInterval = 0.1,              -- How often to update fatigue (seconds)
		Enabled = true,                  -- Enable/disable fatigue system
	},
}

-- === HELPERS ===

local function getPackagesFolder()
	local folder = Workspace:FindFirstChild(PACKAGES_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PACKAGES_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

local function clearPackages()
	local folder = Workspace:FindFirstChild(PACKAGES_FOLDER_NAME)
	if folder then
		folder:ClearAllChildren()
	end
end

local function randomRange(min, max)
	return min + math.random() * (max - min)
end

local function pickColor()
	return PACKAGE_CONFIG.Colors[math.random(1, #PACKAGE_CONFIG.Colors)]
end

local function createPackageCube(position, size)
	local model = Instance.new("Model")
	model.Name = "Package_" .. math.random(1000, 9999)
	
	-- Create the cube part
	local part = Instance.new("Part")
	part.Name = "PackagePart"
	part.Shape = Enum.PartType.Block
	part.Size = size
	part.Position = position
	part.Color = pickColor()
	part.Material = PACKAGE_CONFIG.Material
	part.Anchored = PACKAGE_CONFIG.Anchored
	part.CanCollide = PACKAGE_CONFIG.CanCollide
	part.Parent = model
	
	-- Set as primary part
	model.PrimaryPart = part
	
	-- Create ProximityPrompt for pickup
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = PACKAGE_CONFIG.PromptActionText
	prompt.ObjectText = PACKAGE_CONFIG.PromptObjectText
	prompt.HoldDuration = PACKAGE_CONFIG.PromptHoldDuration
	prompt.MaxActivationDistance = PACKAGE_CONFIG.PromptMaxDistance
	prompt.KeyboardKeyCode = PACKAGE_CONFIG.PromptKeyboardKey
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	
	-- Add tag to package
	CollectionService:AddTag(model, "spawnedPackage")
	
	return model
end

local function getPlatformTopPosition(platformModel)
	-- Get the bounding box of the platform model
	local cf, size = platformModel:GetBoundingBox()
	
	-- Calculate the top center position
	local topY = cf.Position.Y + (size.Y / 2)
	return Vector3.new(cf.Position.X, topY, cf.Position.Z), size
end

local function spawnPackagesOnPlatform(platformModel, folder)
	local topPos, platformSize = getPlatformTopPosition(platformModel)
	
	-- Determine how many packages to spawn
	local packageCount = math.random(PACKAGE_CONFIG.PackagesPerPlatform.Min, PACKAGE_CONFIG.PackagesPerPlatform.Max)
	
	-- Calculate spread area based on platform size
	local spreadX = math.min(PACKAGE_CONFIG.SpreadRadius, platformSize.X / 2 - 1)
	local spreadZ = math.min(PACKAGE_CONFIG.SpreadRadius, platformSize.Z / 2 - 1)
	
	local spawnedPackages = {}
	
	for i = 1, packageCount do
		-- Random size for this cube
		local cubeSize = Vector3.new(
			randomRange(PACKAGE_CONFIG.SizeMin.X, PACKAGE_CONFIG.SizeMax.X),
			randomRange(PACKAGE_CONFIG.SizeMin.Y, PACKAGE_CONFIG.SizeMax.Y),
			randomRange(PACKAGE_CONFIG.SizeMin.Z, PACKAGE_CONFIG.SizeMax.Z)
		)
		
		-- Random position on top of platform with some spread
		local offsetX = randomRange(-spreadX, spreadX)
		local offsetZ = randomRange(-spreadZ, spreadZ)
		
		local spawnPosition = Vector3.new(
			topPos.X + offsetX,
			topPos.Y + PACKAGE_CONFIG.SpawnHeightAbove + (cubeSize.Y / 2),
			topPos.Z + offsetZ
		)
		
		local package = createPackageCube(spawnPosition, cubeSize)
		package.Parent = folder
		
		table.insert(spawnedPackages, package)
	end
	
	return spawnedPackages
end

-- === PICKUP / DROP SYSTEM ===

local function getPlayerStack(service, player)
	if not service.playerHeldPackages[player.UserId] then
		service.playerHeldPackages[player.UserId] = {}
	end
	return service.playerHeldPackages[player.UserId]
end

local function getTopOfStack(service, player)
	local stack = getPlayerStack(service, player)
	if #stack > 0 then
		return stack[#stack]
	end
	return nil
end

-- Calculate total kudos value of all held packages
local function calculateTotalKudos(stack)
	local total = 0
	for _, packageModel in ipairs(stack) do
		local kudosValue = packageModel:GetAttribute("KudosValue") or 0
		total = total + kudosValue
	end
	return total
end

-- Update the total kudos billboard on the top package
local function updateTotalKudosBillboard(service, player)
	local stack = getPlayerStack(service, player)
	
	-- Remove existing total billboard from all packages in stack
	for _, packageModel in ipairs(stack) do
		local packagePart = packageModel.PrimaryPart
		if packagePart then
			local existingBillboard = packagePart:FindFirstChild("TotalKudosBillboard")
			if existingBillboard then
				existingBillboard:Destroy()
			end
		end
	end
	
	-- If no packages, nothing to display
	if #stack == 0 then
		return
	end
	
	-- Get the top package
	local topPackage = stack[#stack]
	local topPart = topPackage.PrimaryPart
	if not topPart then return end
	
	-- Calculate total kudos
	local totalKudos = calculateTotalKudos(stack)
	local packageCount = #stack
	
	-- Create BillboardGui for total
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TotalKudosBillboard"
	billboard.Size = UDim2.new(0, 120, 0, 50)
	billboard.StudsOffset = Vector3.new(0, topPart.Size.Y / 2 + 3, 0)  -- Float above top package
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Parent = topPart
	
	-- Background frame
	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "Background"
	bgFrame.Size = UDim2.new(1, 0, 1, 0)
	bgFrame.BackgroundColor3 = Color3.fromRGB(20, 60, 40)  -- Dark green
	bgFrame.BackgroundTransparency = 0.2
	bgFrame.BorderSizePixel = 0
	bgFrame.Parent = billboard
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.15, 0)
	corner.Parent = bgFrame
	
	-- Border glow
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 255, 150)  -- Green glow
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = bgFrame
	
	-- Total kudos label
	local totalLabel = Instance.new("TextLabel")
	totalLabel.Name = "TotalLabel"
	totalLabel.Size = UDim2.new(1, 0, 0.6, 0)
	totalLabel.Position = UDim2.new(0, 0, 0, 0)
	totalLabel.BackgroundTransparency = 1
	totalLabel.Text = "⭐ " .. totalKudos .. " Total"
	totalLabel.TextColor3 = Color3.fromRGB(255, 230, 100)  -- Gold
	totalLabel.TextScaled = true
	totalLabel.Font = Enum.Font.GothamBold
	totalLabel.Parent = bgFrame
	
	local totalStroke = Instance.new("UIStroke")
	totalStroke.Color = Color3.fromRGB(0, 0, 0)
	totalStroke.Thickness = 2
	totalStroke.Parent = totalLabel
	
	-- Package count label
	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "CountLabel"
	countLabel.Size = UDim2.new(1, 0, 0.4, 0)
	countLabel.Position = UDim2.new(0, 0, 0.6, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "📦 " .. packageCount .. " Package" .. (packageCount > 1 and "s" or "")
	countLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	countLabel.TextScaled = true
	countLabel.Font = Enum.Font.Gotham
	countLabel.Parent = bgFrame
end

local function attachPackageToPlayer(packageModel, player, service)
	local character = player.Character
	if not character then return false end
	
	local head = character:FindFirstChild("Head")
	if not head then return false end
	
	local packagePart = packageModel.PrimaryPart
	if not packagePart then return false end
	
	-- Unanchor the package so it can be picked up (it may have been anchored after settling)
	packagePart.Anchored = false
	local tapePart = packageModel:FindFirstChild("Tape")
	if tapePart then
		tapePart.Anchored = false
	end
	
	-- Disable the pickup prompt while held
	local prompt = packagePart:FindFirstChild("PickupPrompt")
	if prompt then
		prompt.Enabled = false
	end
	
	-- Hide the individual kudos billboard (we'll show total on top package)
	local kudosBillboard = packagePart:FindFirstChild("KudosBillboard")
	if kudosBillboard then
		kudosBillboard.Enabled = false
	end
	
	local stack = getPlayerStack(service, player)
	local topPackage = getTopOfStack(service, player)
	
	local attachToParent  -- The part we attach to (head or top package)
	local attachmentHeight  -- Height offset for attachment
	local packageHalfHeight = packagePart.Size.Y / 2
	
	if topPackage and topPackage.PrimaryPart then
		-- Stack on top of existing package (no gap!)
		local topPart = topPackage.PrimaryPart
		local topPartHalfHeight = topPart.Size.Y / 2
		
		attachToParent = topPart
		attachmentHeight = topPartHalfHeight + packageHalfHeight
		
		-- Position the package directly on top (flush)
		local topPosition = topPart.Position
		packagePart.CFrame = CFrame.new(topPosition.X, topPosition.Y + attachmentHeight, topPosition.Z)
		
		-- Create attachment at the TOP of the lower package
		local parentAttachment = Instance.new("Attachment")
		parentAttachment.Name = "StackAttachment_" .. packageModel.Name
		parentAttachment.Position = Vector3.new(0, topPartHalfHeight, 0)  -- Top surface of parent
		parentAttachment.Parent = topPart
	else
		-- First package - attach to head
		attachToParent = head
		local headTop = head.Size.Y / 2
		attachmentHeight = headTop + PACKAGE_CONFIG.HeldHeightAboveHead + packageHalfHeight
		
		-- Position the package above the head
		packagePart.CFrame = CFrame.new(head.Position.X, head.Position.Y + attachmentHeight, head.Position.Z)
		
		-- Create attachment on head (at top of head + offset)
		local headAttachment = Instance.new("Attachment")
		headAttachment.Name = "PackageAttachment"
		headAttachment.Position = Vector3.new(0, headTop + PACKAGE_CONFIG.HeldHeightAboveHead, 0)  -- Top of head + small gap
		headAttachment.Parent = head
	end
	
	-- Create attachment at the BOTTOM of the new package
	local packageAttachment = Instance.new("Attachment")
	packageAttachment.Name = "HeldAttachment"
	packageAttachment.Position = Vector3.new(0, -packageHalfHeight, 0)  -- Bottom surface of package
	packageAttachment.Parent = packagePart
	
	-- Find the parent attachment
	local parentAttachment
	if topPackage and topPackage.PrimaryPart then
		parentAttachment = topPackage.PrimaryPart:FindFirstChild("StackAttachment_" .. packageModel.Name)
	else
		parentAttachment = head:FindFirstChild("PackageAttachment")
	end
	
	-- Determine if this level should wobble or be welded
	local stackLevel = #stack + 1
	local sway = PACKAGE_CONFIG.Sway
	local shouldWobble = stackLevel <= sway.WobbleLevels
	
	if shouldWobble then
		-- Use AlignPosition/AlignOrientation for wobble effect
		local alignPosition = Instance.new("AlignPosition")
		alignPosition.Name = "PackageAlignPosition"
		alignPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment
		alignPosition.Attachment0 = packageAttachment
		alignPosition.Attachment1 = parentAttachment
		alignPosition.MaxForce = sway.BaseMaxForce
		alignPosition.MaxVelocity = sway.BaseMaxVelocity
		alignPosition.Responsiveness = sway.BaseResponsiveness
		alignPosition.Parent = packagePart
		
		local alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "PackageAlignOrientation"
		alignOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		alignOrientation.Attachment0 = packageAttachment
		alignOrientation.Attachment1 = parentAttachment
		alignOrientation.MaxTorque = sway.BaseMaxTorque
		alignOrientation.MaxAngularVelocity = sway.BaseMaxAngularVelocity
		alignOrientation.Responsiveness = sway.BaseResponsiveness
		alignOrientation.Parent = packagePart
	else
		-- Use WeldConstraint for rigid connection (no wobble)
		local weld = Instance.new("WeldConstraint")
		weld.Name = "PackageWeld"
		weld.Part0 = attachToParent
		weld.Part1 = packagePart
		weld.Parent = packagePart
	end
	
	-- Disable collision with character while held
	packagePart.CanCollide = false
	
	-- Give the player network ownership for smooth physics
	packagePart:SetNetworkOwner(player)
	
	-- Store reference
	packageModel:SetAttribute("HeldByPlayer", player.UserId)
	packageModel:SetAttribute("StackIndex", #stack + 1)
	
	-- Add to stack
	table.insert(stack, packageModel)
	
	-- Update the total kudos billboard on the top package
	updateTotalKudosBillboard(service, player)
	
	-- Drop functionality disabled - packages cannot be dropped
	
	return true
end

local function detachPackageFromPlayer(packageModel, player, service)
	local character = player.Character
	local packagePart = packageModel.PrimaryPart
	if not packagePart then return false end
	
	-- Remove constraints and attachments
	local alignPosition = packagePart:FindFirstChild("PackageAlignPosition")
	if alignPosition then alignPosition:Destroy() end
	
	local alignOrientation = packagePart:FindFirstChild("PackageAlignOrientation")
	if alignOrientation then alignOrientation:Destroy() end
	
	local packageWeld = packagePart:FindFirstChild("PackageWeld")
	if packageWeld then packageWeld:Destroy() end
	
	local packageAttachment = packagePart:FindFirstChild("HeldAttachment")
	if packageAttachment then packageAttachment:Destroy() end
	
	-- Remove stack attachment from this package (for packages above, if any)
	for _, child in ipairs(packagePart:GetChildren()) do
		if child:IsA("Attachment") and child.Name:match("^StackAttachment_") then
			child:Destroy()
		end
	end
	
	-- Get the stack and find this package's index
	local stack = getPlayerStack(service, player)
	local stackIndex = packageModel:GetAttribute("StackIndex") or 1
	
	-- If this is the bottom package (index 1), remove head attachment
	if stackIndex == 1 and character then
		local head = character:FindFirstChild("Head")
		if head then
			local headAttachment = head:FindFirstChild("PackageAttachment")
			if headAttachment then headAttachment:Destroy() end
		end
	end
	
	-- Find and remove stack attachment from the package below (if exists)
	if stackIndex > 1 then
		local packageBelow = stack[stackIndex - 1]
		if packageBelow and packageBelow.PrimaryPart then
			local stackAttachment = packageBelow.PrimaryPart:FindFirstChild("StackAttachment_" .. packageModel.Name)
			if stackAttachment then stackAttachment:Destroy() end
		end
	end
	
	-- Remove drop prompt
	local dropPrompt = packagePart:FindFirstChild("DropPrompt")
	if dropPrompt then dropPrompt:Destroy() end
	
	-- Re-enable collision
	packagePart.CanCollide = true
	
	-- Reset network ownership to server (auto-assign)
	packagePart:SetNetworkOwner(nil)
	
	-- Re-enable pickup prompt
	local pickupPrompt = packagePart:FindFirstChild("PickupPrompt")
	if pickupPrompt then
		pickupPrompt.Enabled = true
	end
	
	-- Re-enable individual kudos billboard
	local kudosBillboard = packagePart:FindFirstChild("KudosBillboard")
	if kudosBillboard then
		kudosBillboard.Enabled = true
	end
	
	-- Remove total kudos billboard (it was on this package if it was the top)
	local totalBillboard = packagePart:FindFirstChild("TotalKudosBillboard")
	if totalBillboard then
		totalBillboard:Destroy()
	end
	
	-- Clear attributes
	packageModel:SetAttribute("HeldByPlayer", nil)
	packageModel:SetAttribute("StackIndex", nil)
	
	return true
end

local function setupPromptHandler(packageModel, service)
	local packagePart = packageModel.PrimaryPart
	if not packagePart then return end
	
	local pickupPrompt = packagePart:FindFirstChild("PickupPrompt")
	if not pickupPrompt then return end
	
	pickupPrompt.Triggered:Connect(function(player)
		-- Check if this package is already held by someone
		local heldBy = packageModel:GetAttribute("HeldByPlayer")
		if heldBy then
			print("[PackagePlatformService] Package already held by another player")
			return
		end
		
		-- Pick up the package (will stack if already holding)
		if attachPackageToPlayer(packageModel, player, service) then
			local stack = getPlayerStack(service, player)
			print("[PackagePlatformService] " .. player.Name .. " picked up " .. packageModel.Name .. " (stack: " .. #stack .. ")")
			-- Drop functionality disabled
		end
	end)
end

-- === KNIT LIFECYCLE ===

function PackagePlatformService:KnitInit()
	print("[PackagePlatformService] Initializing...")
end

function PackagePlatformService:KnitStart()
	print("[PackagePlatformService] Starting...")
	
	-- Get all tagged platforms and spawn packages on them
	self:SpawnAllPackages()
	
	-- Listen for new platforms being tagged
	CollectionService:GetInstanceAddedSignal(PLATFORM_TAG):Connect(function(platform)
		if platform:IsA("Model") then
			print("[PackagePlatformService] New platform tagged: " .. platform.Name)
			local folder = getPackagesFolder()
			local packages = spawnPackagesOnPlatform(platform, folder)
			for _, pkg in ipairs(packages) do
				table.insert(self.packages, pkg)
				setupPromptHandler(pkg, self)
			end
		end
	end)
	
	-- Listen for new packages being tagged (e.g., from conveyor belts)
	CollectionService:GetInstanceAddedSignal("spawnedPackage"):Connect(function(package)
		if package:IsA("Model") and package.PrimaryPart then
			-- Check if we already track this package
			local alreadyTracked = false
			for _, pkg in ipairs(self.packages) do
				if pkg == package then
					alreadyTracked = true
					break
				end
			end
			
			if not alreadyTracked then
				print("[PackagePlatformService] New package detected: " .. package.Name)
				table.insert(self.packages, package)
				setupPromptHandler(package, self)
			end
		end
	end)
	
	-- Handle player leaving (drop all their packages and cleanup fatigue)
	Players.PlayerRemoving:Connect(function(player)
		self:DropAllPackages(player)
		self:CleanupPlayerFatigue(player)
	end)
	
	-- Handle player added (initialize fatigue)
	Players.PlayerAdded:Connect(function(player)
		-- Initialize fatigue when player spawns
		player.CharacterAdded:Connect(function()
			self:InitPlayerFatigue(player)
		end)
		
		-- Cleanup on character removing
		player.CharacterRemoving:Connect(function()
			self:DropAllPackages(player)
		end)
	end)
	
	-- Setup handlers for existing players (in case they joined before this)
	for _, player in ipairs(Players:GetPlayers()) do
		-- Initialize fatigue for existing players with characters
		if player.Character then
			self:InitPlayerFatigue(player)
		end
		
		player.CharacterAdded:Connect(function()
			self:InitPlayerFatigue(player)
		end)
		
		player.CharacterRemoving:Connect(function()
			self:DropAllPackages(player)
		end)
	end
	
	print("[PackagePlatformService] Started!")
end

-- === PUBLIC METHODS ===

function PackagePlatformService:SpawnAllPackages()
	clearPackages()
	self.packages = {}
	self.playerHeldPackages = {}
	
	local folder = getPackagesFolder()
	local platforms = CollectionService:GetTagged(PLATFORM_TAG)
	
	print(string.format("[PackagePlatformService] Found %d platforms with '%s' tag", #platforms, PLATFORM_TAG))
	
	for _, platform in ipairs(platforms) do
		if platform:IsA("Model") then
			local packages = spawnPackagesOnPlatform(platform, folder)
			for _, pkg in ipairs(packages) do
				table.insert(self.packages, pkg)
				setupPromptHandler(pkg, self)
			end
			print(string.format("  - Spawned %d packages on: %s", #packages, platform.Name))
		else
			warn(string.format("[PackagePlatformService] Tagged instance '%s' is not a Model", platform.Name))
		end
	end
	
	print(string.format("[PackagePlatformService] Total packages spawned: %d", #self.packages))
end

function PackagePlatformService:ClearPackages()
	self.packages = {}
	self.playerHeldPackages = {}
	clearPackages()
end

-- Drop the top package from the stack (used internally for death/leave cleanup)
function PackagePlatformService:DropTopPackage(player)
	local stack = self.playerHeldPackages[player.UserId]
	if not stack or #stack == 0 then
		return false
	end
	
	-- Get the top package
	local topPackage = stack[#stack]
	
	if detachPackageFromPlayer(topPackage, player, self) then
		-- Remove from stack
		table.remove(stack, #stack)
		print("[PackagePlatformService] " .. player.Name .. " dropped " .. topPackage.Name .. " (remaining: " .. #stack .. ")")
		
		-- Stack is empty, clean up
		if #stack == 0 then
			self.playerHeldPackages[player.UserId] = nil
		else
			-- Update the billboard on the new top package
			updateTotalKudosBillboard(self, player)
		end
		
		return true
	end
	
	return false
end

-- Drop all packages from the stack
function PackagePlatformService:DropAllPackages(player)
	local stack = self.playerHeldPackages[player.UserId]
	if not stack or #stack == 0 then
		return false
	end
	
	local count = #stack
	
	-- Drop from top to bottom
	for i = #stack, 1, -1 do
		local packageModel = stack[i]
		detachPackageFromPlayer(packageModel, player, self)
	end
	
	self.playerHeldPackages[player.UserId] = nil
	print("[PackagePlatformService] " .. player.Name .. " dropped all " .. count .. " packages")
	
	return true
end

-- Alias for backwards compatibility (drops all)
function PackagePlatformService:DropPackage(player)
	return self:DropAllPackages(player)
end

function PackagePlatformService:GetHeldPackages(player)
	return self.playerHeldPackages[player.UserId] or {}
end

function PackagePlatformService:GetTopPackage(player)
	local stack = self.playerHeldPackages[player.UserId]
	if stack and #stack > 0 then
		return stack[#stack]
	end
	return nil
end

function PackagePlatformService:GetStackCount(player)
	local stack = self.playerHeldPackages[player.UserId]
	return stack and #stack or 0
end

function PackagePlatformService:IsPlayerHoldingPackage(player)
	local stack = self.playerHeldPackages[player.UserId]
	return stack ~= nil and #stack > 0
end

function PackagePlatformService:GetAllPackages()
	return self.packages
end

function PackagePlatformService:SpawnPackageAt(position, size)
	local folder = getPackagesFolder()
	size = size or Vector3.new(
		randomRange(PACKAGE_CONFIG.SizeMin.X, PACKAGE_CONFIG.SizeMax.X),
		randomRange(PACKAGE_CONFIG.SizeMin.Y, PACKAGE_CONFIG.SizeMax.Y),
		randomRange(PACKAGE_CONFIG.SizeMin.Z, PACKAGE_CONFIG.SizeMax.Z)
	)
	
	local package = createPackageCube(position, size)
	package.Parent = folder
	table.insert(self.packages, package)
	setupPromptHandler(package, self)
	
	return package
end

function PackagePlatformService:RegeneratePackages()
	self:SpawnAllPackages()
end

function PackagePlatformService:SetPackageCount(min, max)
	PACKAGE_CONFIG.PackagesPerPlatform.Min = math.clamp(min, 1, 20)
	PACKAGE_CONFIG.PackagesPerPlatform.Max = math.clamp(max, min, 50)
end

function PackagePlatformService:SetPackageSize(sizeMin, sizeMax)
	PACKAGE_CONFIG.SizeMin = sizeMin
	PACKAGE_CONFIG.SizeMax = sizeMax
end

-- === FATIGUE SYSTEM ===

function PackagePlatformService:InitPlayerFatigue(player)
	if not PACKAGE_CONFIG.Fatigue.Enabled then return end
	if self.playerFatigue[player.UserId] then return end  -- Already initialized
	
	local fatigueConfig = PACKAGE_CONFIG.Fatigue
	
	-- Create fatigue data
	local fatigueData = {
		value = fatigueConfig.MaxFatigue,
		replica = nil,
		timer = nil,
	}
	
	-- Create a replica for this player's fatigue
	fatigueData.replica = ReplicaService.NewReplica({
		ClassToken = FatigueClassToken,
		Data = {
			Fatigue = fatigueConfig.MaxFatigue,
			MaxFatigue = fatigueConfig.MaxFatigue,
			StackCount = 0,
		},
		Replication = player,  -- Only replicate to this player
	})
	
	-- Create timer to update fatigue
	fatigueData.timer = Timer.new(fatigueConfig.TickInterval)
	fatigueData.timer:Start()
	
	fatigueData.timer.Tick:Connect(function()
		self:UpdatePlayerFatigue(player)
	end)
	
	self.playerFatigue[player.UserId] = fatigueData
	print("[PackagePlatformService] Fatigue system initialized for " .. player.Name)
end

function PackagePlatformService:UpdatePlayerFatigue(player)
	local fatigueData = self.playerFatigue[player.UserId]
	if not fatigueData then return end
	
	local fatigueConfig = PACKAGE_CONFIG.Fatigue
	local stackCount = self:GetStackCount(player)
	local dt = fatigueConfig.TickInterval
	
	local newFatigue = fatigueData.value
	
	if stackCount > 0 then
		-- Drain fatigue based on number of packages
		local drainRate = fatigueConfig.BaseDrainRate + (stackCount * fatigueConfig.DrainPerPackage)
		newFatigue = newFatigue - (drainRate * dt)
	else
		-- Recover fatigue when not holding packages
		newFatigue = newFatigue + (fatigueConfig.RecoveryRate * dt)
	end
	
	-- Clamp fatigue
	newFatigue = math.clamp(newFatigue, 0, fatigueConfig.MaxFatigue)
	
	-- Update if changed
	if newFatigue ~= fatigueData.value then
		fatigueData.value = newFatigue
		
		-- Update replica
		if fatigueData.replica then
			fatigueData.replica:SetValue({"Fatigue"}, newFatigue)
			fatigueData.replica:SetValue({"StackCount"}, stackCount)
		end
	end
	
	-- Check if exhausted (fatigue depleted)
	if newFatigue <= 0 and stackCount > 0 then
		-- Drop all packages when exhausted
		print("[PackagePlatformService] " .. player.Name .. " is exhausted! Dropping all packages.")
		self:DropAllPackages(player)
	end
end

function PackagePlatformService:CleanupPlayerFatigue(player)
	local fatigueData = self.playerFatigue[player.UserId]
	if not fatigueData then return end
	
	-- Stop and destroy timer
	if fatigueData.timer then
		fatigueData.timer:Stop()
		fatigueData.timer:Destroy()
	end
	
	-- Destroy replica
	if fatigueData.replica then
		fatigueData.replica:Destroy()
	end
	
	self.playerFatigue[player.UserId] = nil
	print("[PackagePlatformService] Fatigue system cleaned up for " .. player.Name)
end

function PackagePlatformService:GetPlayerFatigue(player)
	local fatigueData = self.playerFatigue[player.UserId]
	if fatigueData then
		return fatigueData.value
	end
	return PACKAGE_CONFIG.Fatigue.MaxFatigue
end

function PackagePlatformService:SetPlayerFatigue(player, value)
	local fatigueData = self.playerFatigue[player.UserId]
	if fatigueData then
		fatigueData.value = math.clamp(value, 0, PACKAGE_CONFIG.Fatigue.MaxFatigue)
		if fatigueData.replica then
			fatigueData.replica:SetValue({"Fatigue"}, fatigueData.value)
		end
	end
end

return PackagePlatformService

