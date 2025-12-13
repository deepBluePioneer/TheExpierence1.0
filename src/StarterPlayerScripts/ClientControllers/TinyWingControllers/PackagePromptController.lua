--[[
	PackagePromptController
	
	Controls ProximityPrompt visibility for packages on the client.
	Can hide prompts when player is holding max packages, etc.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local PackagePromptController = Knit.CreateController {
	Name = "PackagePromptController",
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIGURATION                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	MaxStackSize = 10,           -- Max packages a player can hold
	HidePromptsWhenHolding = false,  -- Hide all package prompts when holding any
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         STATE                                               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local player = Players.LocalPlayer
local hiddenPrompts = {}  -- Track prompts we've hidden
local isHoldingPackage = false
local currentStackCount = 0

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PROMPT FILTERING                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Check if a prompt should be hidden for this player
local function shouldHidePrompt(prompt)
	-- Only filter package pickup prompts
	if prompt.Name ~= "PickupPrompt" then
		return false
	end
	
	-- Hide if at max stack
	if currentStackCount >= CONFIG.MaxStackSize then
		return true
	end
	
	-- Hide all package prompts while holding (optional)
	if CONFIG.HidePromptsWhenHolding and isHoldingPackage then
		return true
	end
	
	return false
end

-- Hide a prompt locally (doesn't affect other players)
local function hidePromptLocally(prompt)
	if not hiddenPrompts[prompt] then
		hiddenPrompts[prompt] = prompt.Enabled
		prompt.Enabled = false
	end
end

-- Restore a hidden prompt
local function restorePrompt(prompt)
	if hiddenPrompts[prompt] ~= nil then
		prompt.Enabled = hiddenPrompts[prompt]
		hiddenPrompts[prompt] = nil
	end
end

-- Restore all hidden prompts
local function restoreAllPrompts()
	for prompt, originalState in pairs(hiddenPrompts) do
		if prompt and prompt.Parent then
			prompt.Enabled = originalState
		end
	end
	hiddenPrompts = {}
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         PUBLIC API                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

-- Call this to update the player's holding state
function PackagePromptController:SetHoldingState(holding, stackCount)
	isHoldingPackage = holding
	currentStackCount = stackCount or 0
	
	-- If no longer holding or under max, restore prompts
	if not holding or stackCount < CONFIG.MaxStackSize then
		restoreAllPrompts()
	end
end

-- Manually hide a specific prompt for this player
function PackagePromptController:HidePrompt(prompt)
	hidePromptLocally(prompt)
end

-- Manually show a specific prompt for this player
function PackagePromptController:ShowPrompt(prompt)
	restorePrompt(prompt)
end

-- Set max stack size
function PackagePromptController:SetMaxStackSize(max)
	CONFIG.MaxStackSize = max
end

-- Toggle hiding prompts while holding
function PackagePromptController:SetHideWhileHolding(hide)
	CONFIG.HidePromptsWhenHolding = hide
	if not hide then
		restoreAllPrompts()
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function PackagePromptController:KnitInit()
	-- Nothing needed
end

function PackagePromptController:KnitStart()
	-- Listen for prompts being shown
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if shouldHidePrompt(prompt) then
			hidePromptLocally(prompt)
		end
	end)
	
	-- Listen for prompts being hidden (cleanup)
	ProximityPromptService.PromptHidden:Connect(function(prompt, inputType)
		-- Remove from our tracking if it was hidden
		hiddenPrompts[prompt] = nil
	end)
	
	-- Watch for character changes to reset state
	player.CharacterAdded:Connect(function()
		isHoldingPackage = false
		currentStackCount = 0
		restoreAllPrompts()
	end)
	
	print("[PackagePromptController] Ready - filtering package prompts")
end

return PackagePromptController

