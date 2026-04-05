local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local TOOL_TAG = "tool"

local GraviBowToolService = Knit.CreateService({
	Name = "GraviBowToolService",
	Client = {
		ToolPickedUp = Knit.CreateSignal(),
	},

	_playerInventory = {},
})

function GraviBowToolService:KnitInit()
end

function GraviBowToolService:KnitStart()
	self:_setupToolPickups()
end

function GraviBowToolService:GetPlayerInventory(player)
	return self._playerInventory[player] or {}
end

function GraviBowToolService:ClearPlayerInventory(player)
	self._playerInventory[player] = nil
end

function GraviBowToolService:SetBowEnabled(_player, _enabled)
end

function GraviBowToolService:_buildJetpackStructure(tool)
	local visual = tool:FindFirstChild("jetPackVisual")
	if not visual then
		warn("[GraviBowToolService] Jetpack tool missing 'jetPackVisual' child")
		return
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = visual.CFrame
	handle.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = visual
	weld.Parent = handle

	local accessory = Instance.new("Accessory")
	accessory.Name = "JetpackAccessory"
	accessory.AccessoryType = Enum.AccessoryType.Back

	local accHandle = visual:Clone()
	accHandle.Name = "Handle"
	accHandle.Anchored = false
	accHandle.CanCollide = false

	local attachment = Instance.new("Attachment")
	attachment.Name = "BodyBackAttachment"
	attachment.Parent = accHandle

	accHandle.Parent = accessory
	accessory.Parent = tool

	print("[GraviBowToolService] Built jetpack structure for:", tool:GetFullName())
end

function GraviBowToolService:_setupToolPickups()
	local function setupPrompt(tool)
		if not tool:IsA("Tool") then return end

		if tool.Name:lower() == "jetpack" then
			self:_buildJetpackStructure(tool)
		end

		local handle = tool:WaitForChild("Handle", 5)
		if not handle then
			warn("[GraviBowToolService] Tool", tool.Name, "has no Handle, skipping prompt")
			return
		end

		handle.CanTouch = false

		local toolName = tool.Name:lower()

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Pick Up"
		prompt.ObjectText = tool.Name
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = handle

		prompt.Triggered:Connect(function(player)
			if not self._playerInventory[player] then
				self._playerInventory[player] = {}
			end

			for _, existing in ipairs(self._playerInventory[player]) do
				if existing == toolName then
					return
				end
			end

			local backpack = player:FindFirstChild("Backpack")
			if not backpack then return end

			local clone = tool:Clone()
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("ProximityPrompt") then
					desc:Destroy()
				end
			end
			clone.Parent = backpack

			table.insert(self._playerInventory[player], toolName)
			self.Client.ToolPickedUp:Fire(player, toolName)

			tool:Destroy()

			for _, otherTool in ipairs(CollectionService:GetTagged(TOOL_TAG)) do
				if otherTool:IsA("Tool") and otherTool.Name:lower() == toolName then
					local otherHandle = otherTool:FindFirstChild("Handle")
					if otherHandle then
						local otherPrompt = otherHandle:FindFirstChildOfClass("ProximityPrompt")
						if otherPrompt then
							otherPrompt.Enabled = false
						end
					end
				end
			end

			print("[GraviBowToolService] Player", player.Name, "picked up:", toolName)
		end)
	end

	for _, instance in ipairs(CollectionService:GetTagged(TOOL_TAG)) do
		setupPrompt(instance)
	end

	CollectionService:GetInstanceAddedSignal(TOOL_TAG):Connect(function(instance)
		setupPrompt(instance)
	end)
end

return GraviBowToolService
