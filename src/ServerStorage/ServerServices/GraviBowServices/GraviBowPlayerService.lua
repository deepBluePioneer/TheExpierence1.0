local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local RESPAWN_TIME = 3

local GraviBowPlayerService = Knit.CreateService({
	Name = "GraviBowPlayerService",
	Client = {
		ArrowHit = Knit.CreateSignal(),
	},

	_playerTroves = {},
})

function GraviBowPlayerService:KnitInit()
	self._trove = Trove.new()
end

function GraviBowPlayerService:KnitStart()
	Workspace.Gravity = 0

	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	self:_setupLighting()

	self._trove:Add(Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end), "Disconnect")

	self._trove:Add(Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end), "Disconnect")

	self.Client.ArrowHit:Connect(function(shooter, victimPlayer)
		self:_onArrowHit(shooter, victimPlayer)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_onPlayerAdded(player)
	end

	print("[GraviBowPlayerService] Started -- Workspace.Gravity = 0")
end

function GraviBowPlayerService:_onArrowHit(shooter, victimPlayer)
	if not victimPlayer or not victimPlayer:IsA("Player") then return end
	if victimPlayer == shooter then return end

	local character = victimPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	humanoid.Health = 0

	print(string.format("[GraviBowPlayerService] %s killed %s with an arrow", shooter.Name, victimPlayer.Name))
end

function GraviBowPlayerService:_onPlayerAdded(player)
	local function onCharacterAdded(character)
		self:_setupCharacter(player, character)
	end

	local charConn = player.CharacterAdded:Connect(onCharacterAdded)

	if not self._playerTroves[player] then
		self._playerTroves[player] = Trove.new()
	end
	self._playerTroves[player]:Add(charConn, "Disconnect")

	if player.Character then
		onCharacterAdded(player.Character)
	end
end

function GraviBowPlayerService:_onPlayerDied(player)
	print(string.format("[GraviBowPlayerService] %s died, respawning in %ds", player.Name, RESPAWN_TIME))
	task.delay(RESPAWN_TIME, function()
		if player.Parent then
			player:LoadCharacter()
		end
	end)
end

function GraviBowPlayerService:_setupLighting()
	Lighting.ClockTime = 14
	Lighting.GeographicLatitude = 0
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(40, 40, 50)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 70, 90)
	Lighting.ColorShift_Top = Color3.fromRGB(230, 220, 255)
	Lighting.ColorShift_Bottom = Color3.fromRGB(30, 30, 50)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.ExposureCompensation = 0.3
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("BloomEffect")
			or child:IsA("ColorCorrectionEffect") or child:IsA("SunRaysEffect") then
			child:Destroy()
		end
	end

	local sky = Instance.new("Sky")
	sky.SkyboxBk = "rbxassetid://1012890"
	sky.SkyboxDn = "rbxassetid://1012891"
	sky.SkyboxFt = "rbxassetid://1012887"
	sky.SkyboxLf = "rbxassetid://1012889"
	sky.SkyboxRt = "rbxassetid://1012888"
	sky.SkyboxUp = "rbxassetid://1014449"
	sky.StarCount = 5000
	sky.MoonAngularSize = 8
	sky.SunAngularSize = 15
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.05
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(20, 20, 35)
	atmosphere.Decay = Color3.fromRGB(30, 30, 50)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 0.5
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.5
	bloom.Size = 30
	bloom.Threshold = 1.5
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.05
	cc.Contrast = 0.15
	cc.Saturation = 0.1
	cc.TintColor = Color3.fromRGB(245, 240, 255)
	cc.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Intensity = 0.15
	sunRays.Spread = 0.8
	sunRays.Parent = Lighting

	print("[GraviBowPlayerService] Space lighting profile applied")
end

function GraviBowPlayerService:_onPlayerRemoving(player)
	local trove = self._playerTroves[player]
	if trove then
		trove:Clean()
		self._playerTroves[player] = nil
	end
end

function GraviBowPlayerService:_setupCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not hrp then return end

	self:_stripDefaultScripts(character)
	self:_muteCharacterSounds(character)

	for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
		if state ~= Enum.HumanoidStateType.None then
			pcall(function()
				humanoid:SetStateEnabled(state, false)
			end)
		end
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	humanoid.Died:Once(function()
		self:_onPlayerDied(player)
	end)

	local rootJoint = hrp:FindFirstChild("RootJoint")
		or hrp:FindFirstChildOfClass("Motor6D")
	if rootJoint then
		rootJoint.Enabled = true
	end

	local attachment = hrp:FindFirstChild("GravityAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "GravityAttachment"
		attachment.Parent = hrp
	end

	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = "GravityForce"
	vectorForce.Attachment0 = attachment
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.Force = Vector3.zero
	vectorForce.Parent = hrp

	self:_setupLeftHandGrip(character)
	self:_autoEquipBow(player, character, humanoid)

	print("[GraviBowPlayerService] Setup character constraints for " .. player.Name)
end

function GraviBowPlayerService:_autoEquipBow(player, character, humanoid)
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack then return end

	local tool = backpack:FindFirstChildOfClass("Tool")
	if not tool then
		tool = character:FindFirstChildOfClass("Tool")
	end

	if tool then
		humanoid:EquipTool(tool)
	end

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and humanoid.Health > 0 then
			task.defer(function()
				if child.Parent == backpack then
					humanoid:EquipTool(child)
				end
			end)
		end
	end)
end

function GraviBowPlayerService:_setupLeftHandGrip(character)
	local leftHand = character:FindFirstChild("LeftHand", true)
	local rightHand = character:FindFirstChild("RightHand", true)
	if not leftHand or not rightHand then return end

	local function killRightGrip(child)
		if child:IsA("Motor6D") and child.Name == "RightGrip" then
			child:Destroy()
		end
	end

	rightHand.ChildAdded:Connect(killRightGrip)
	for _, child in ipairs(rightHand:GetChildren()) do
		killRightGrip(child)
	end

	local function attachTool(tool)
		if not tool:IsA("Tool") then return end

		local handle = tool:FindFirstChild("Handle")
		if not handle then return end

		task.defer(function()
			local rg = rightHand:FindFirstChild("RightGrip")
			if rg then rg:Destroy() end

			local existing = leftHand:FindFirstChild("LeftGrip")
			if existing then existing:Destroy() end

			handle.Anchored = false
			handle.CanCollide = false
			handle.Massless = true

			local weld = Instance.new("Weld")
			weld.Name = "LeftGrip"
			weld.Part0 = leftHand
			weld.Part1 = handle
		weld.C0 = CFrame.Angles(0, math.rad(90), math.rad(-90)) * CFrame.Angles(0, 0, math.rad(20))
		weld.C1 = tool.Grip
			weld.Parent = leftHand

			print("[GraviBowPlayerService] Attached tool '" .. tool.Name .. "' to left hand")
		end)
	end

	local function detachTool(tool)
		if not tool:IsA("Tool") then return end
		local grip = leftHand:FindFirstChild("LeftGrip")
		if grip then grip:Destroy() end
	end

	for _, child in ipairs(character:GetChildren()) do
		attachTool(child)
	end

	character.ChildAdded:Connect(attachTool)
	character.ChildRemoved:Connect(detachTool)
end

function GraviBowPlayerService:_muteCharacterSounds(character)
	local function removeSounds(parent)
		for _, child in ipairs(parent:GetDescendants()) do
			if child:IsA("Sound") then
				child.Volume = 0
				child:Stop()
				child:Destroy()
			end
		end
	end

	removeSounds(character)

	character.DescendantAdded:Connect(function(desc)
		if desc:IsA("Sound") then
			desc.Volume = 0
			desc:Stop()
			task.defer(function()
				if desc.Parent then
					desc:Destroy()
				end
			end)
		end
	end)
end

local DEFAULT_SCRIPTS = {
	"Animate",
	"Health",
	"ChatScript",
	"BubbleChat",
	"ChatServiceRunner",
}

function GraviBowPlayerService:_stripDefaultScripts(character)
	local removed = {}
	for _, scriptName in ipairs(DEFAULT_SCRIPTS) do
		local child = character:FindFirstChild(scriptName)
		if child then
			child:Destroy()
			table.insert(removed, scriptName)
		end
	end

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("LocalScript") or desc:IsA("Script") then
			local name = desc.Name
			local dominated = false
			for _, s in ipairs(DEFAULT_SCRIPTS) do
				if name == s then dominated = true; break end
			end
			if not dominated and desc.Parent == character then
				desc:Destroy()
				table.insert(removed, name)
			end
		end
	end

	if #removed > 0 then
		print("[GraviBowPlayerService] Stripped default scripts: " .. table.concat(removed, ", "))
	end
end

return GraviBowPlayerService
