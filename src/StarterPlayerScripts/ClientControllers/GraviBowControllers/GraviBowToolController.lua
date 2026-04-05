local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local TOOL_TAG = "tool"
local LocalPlayer = Players.LocalPlayer

local SLOT_KEYCODES = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
}

local GraviBowToolController = Knit.CreateController({
	Name = "GraviBowToolController",

	_trove = nil,
	_inventory = {},
	_activeSlot = 0,
	_viewmodelController = nil,
})

function GraviBowToolController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowToolController:KnitStart()
	self._viewmodelController = Knit.GetController("GraviBowViewmodelController")
	self._soundController = Knit.GetController("GraviBowSoundController")
	self._scannerController = Knit.GetController("GraviBowScannerController")
	self._miningController = Knit.GetController("GraviBowMiningController")
	self._radialMenuController = Knit.GetController("GraviBowRadialMenuController")
	self._harvesterController = Knit.GetController("GraviBowHarvesterController")
	self._buildController = Knit.GetController("GraviBowBuildController")
	self._jetpackController = Knit.GetController("GraviBowJetpackController")
	self._toolService = Knit.GetService("GraviBowToolService")

	self._toolService.ToolPickedUp:Connect(function(toolName)
		self:_onToolPickedUp(toolName)
	end)

	self._trove:Add(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if self._buildController:IsPlacing() then
				self._buildController:ConfirmPlacement()
				return
			end
			if self._harvesterController:IsHolding() then
				self._harvesterController:DropHeldObject()
				return
			end
			self._miningController:SetLmbHeld(true)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self._buildController:IsPlacing() then
				self._buildController:CancelPlacement()
				return
			end
			if self:GetActiveTool() == "scanner" then
				self._radialMenuController:Show()
			end
		end
		for slot, keyCode in ipairs(SLOT_KEYCODES) do
			if input.KeyCode == keyCode then
				self:_switchToSlot(slot)
				break
			end
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self._miningController:SetLmbHeld(false)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self._radialMenuController:IsRadialOpen() then
				self._radialMenuController:Hide()
			end
		end
	end), "Disconnect")

	self._trove:Add(UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local dir = input.Position.Z > 0 and -1 or 1
			if self._buildController:IsPlacing() then
				self._buildController:Rotate(dir)
				return
			end
			if self._radialMenuController:IsRadialOpen() then
				self._radialMenuController:ScrollSelection(dir)
			end
		end
	end), "Disconnect")

	self._trove:Add(LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.5)
		self:_reequipActiveTool()
	end), "Disconnect")
end

function GraviBowToolController:_onToolPickedUp(toolName)
	for _, existing in ipairs(self._inventory) do
		if existing == toolName then
			return
		end
	end

	table.insert(self._inventory, toolName)
	self:_disableWorldPromptsForTool(toolName)

	self._soundController:PlayGlobal("ToolPickup")

	print("[GraviBowToolController] Picked up:", toolName, "- slot", #self._inventory)

	self:_switchToSlot(#self._inventory)
end

function GraviBowToolController:_switchToSlot(slot)
	if slot < 1 or slot > #self._inventory then return end
	if slot == self._activeSlot then return end

	self:_unequipCurrentTool()

	self._activeSlot = slot
	local toolName = self._inventory[slot]

	print("[GraviBowToolController] Switched to slot", slot, ":", toolName)

	if toolName == "bow" then
		self._scannerController:Hide()
		local bowTool = self:FindToolInBackpack("bow")
		if bowTool then
			self:_equipTool(bowTool)
		end
		self._viewmodelController:ShowBow(bowTool)
	elseif toolName == "scanner" then
		self._viewmodelController:HideBow()
		local scannerTool = self:FindToolInBackpack("scanner")
		if scannerTool then
			self:_equipTool(scannerTool)
		end
		self._scannerController:Show()
	elseif toolName == "jetpack" then
		self._viewmodelController:HideBow()
		self._scannerController:Hide()
		self._jetpackController:Activate()
	else
		self._viewmodelController:HideBow()
		self._scannerController:Hide()
	end
end

function GraviBowToolController:_equipTool(tool)
	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid:EquipTool(tool)
end

function GraviBowToolController:_unequipCurrentTool()
	self._jetpackController:Deactivate()

	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid:UnequipTools()
end

function GraviBowToolController:_reequipActiveTool()
	if self._activeSlot < 1 or self._activeSlot > #self._inventory then return end

	local savedSlot = self._activeSlot
	self._activeSlot = 0
	self:_switchToSlot(savedSlot)
end

function GraviBowToolController:_disableWorldPromptsForTool(toolName)
	for _, instance in ipairs(CollectionService:GetTagged(TOOL_TAG)) do
		if instance:IsA("Tool") and instance.Name:lower() == toolName then
			local handle = instance:FindFirstChild("Handle")
			if handle then
				local prompt = handle:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					prompt.Enabled = false
				end
			end
		end
	end
end

function GraviBowToolController:FindToolInBackpack(toolName)
	local character = LocalPlayer.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child.Name:lower() == toolName then
				return child
			end
		end
	end
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child.Name:lower() == toolName then
				return child
			end
		end
	end
	return nil
end

function GraviBowToolController:GetActiveTool()
	if self._activeSlot < 1 or self._activeSlot > #self._inventory then
		return nil
	end
	return self._inventory[self._activeSlot]
end

function GraviBowToolController:IsRadialOpen()
	return self._radialMenuController:IsRadialOpen()
end

function GraviBowToolController:HasTool(toolName)
	for _, name in ipairs(self._inventory) do
		if name == toolName then
			return true
		end
	end
	return false
end

return GraviBowToolController
