--[[
	SkillTreeController
	
	Fusion-based skill tree UI for unlocking player abilities.
	Skills are organized in categories with tree dependencies.
	Each skill costs "Kudos" to unlock.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)

-- Fusion
local FusionRoot = CustomPackages:WaitForChild("FusionRoot")
local Fusion = require(FusionRoot.Fusion)

local New = Fusion.New
local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Value = Fusion.Value
local Computed = Fusion.Computed
local Spring = Fusion.Spring
local ForPairs = Fusion.ForPairs

-- Replica Module
local Replica = CustomPackages:WaitForChild("Replica")
local ReplicaController = require(Replica.ReplicaController)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SKILL DATA                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local SKILL_CATEGORIES = {
	{
		id = "traversal",
		name = "🏃 TRAVERSAL & SPEED",
		icon = "🏃",
		color = Color3.fromRGB(100, 200, 255),
		skills = {
			{ id = "sprint_start", name = "Sprint Start", desc = "Gain +25% move speed for 3s when leaving the pickup zone.", cost = 50 },
			{ id = "momentum_keeper", name = "Momentum Keeper", desc = "Speed loss from stopping or turning reduced by 40%.", cost = 100 },
			{ id = "straight_line", name = "Straight Line", desc = "Running without changing direction for 2s grants +15% speed.", cost = 150 },
			{ id = "edge_confidence", name = "Edge Confidence", desc = "No speed reduction when within 2 studs of bridge edges.", cost = 200 },
			{ id = "flow_state", name = "Flow State", desc = "Maintain max speed for 1.5s after any slowdown event.", cost = 300 },
			{ id = "perfect_line", name = "Perfect Line", desc = "Stay within 1 stud of center → +20% speed.", cost = 400 },
			{ id = "endurance_runner", name = "Endurance Runner", desc = "Sprint duration increased by +50%.", cost = 500 },
			{ id = "express_hauler", name = "Express Hauler", desc = "Permanent +10% movement speed while on bridges.", cost = 750 },
		}
	},
	{
		id = "carry",
		name = "📦 CARRY CAPACITY",
		icon = "📦",
		color = Color3.fromRGB(200, 150, 100),
		skills = {
			{ id = "extra_slot_1", name = "Extra Slot I", desc = "Max box capacity +1.", cost = 75 },
			{ id = "extra_slot_2", name = "Extra Slot II", desc = "Max box capacity +2.", cost = 150 },
			{ id = "vertical_logistics", name = "Vertical Logistics", desc = "Max stack height increased by +30%.", cost = 200 },
			{ id = "stable_carry", name = "Stable Carry", desc = "Stack size does not reduce movement speed.", cost = 300 },
			{ id = "quick_grab", name = "Quick Grab", desc = "Pickup interaction time reduced by 50%.", cost = 400 },
			{ id = "instant_stack", name = "Instant Stack", desc = "Boxes auto-stack with no pickup pause.", cost = 500 },
			{ id = "bulk_training", name = "Bulk Training", desc = "Acceleration unaffected by stack size.", cost = 600 },
			{ id = "overload_mode", name = "Overload Mode", desc = "Can exceed max capacity by +2 boxes for 10s (60s CD).", cost = 800 },
		}
	},
	{
		id = "profit",
		name = "💰 PROFIT & MULTIPLIERS",
		icon = "💰",
		color = Color3.fromRGB(255, 200, 50),
		skills = {
			{ id = "flat_rate", name = "Flat Rate", desc = "All deliveries grant +10% Kudos.", cost = 100 },
			{ id = "clean_run", name = "Clean Run Bonus", desc = "Deliver without stopping → +15% payout.", cost = 175 },
			{ id = "long_haul", name = "Long Haul", desc = "Full bridge crossings grant +20% payout.", cost = 250 },
			{ id = "stack_multiplier", name = "Stack Multiplier", desc = "Each carried box adds +5% payout.", cost = 350 },
			{ id = "combo_chain", name = "Combo Chain", desc = "Consecutive deliveries grant +3% stacking bonus.", cost = 450 },
			{ id = "priority_cargo", name = "Priority Cargo", desc = "1 in 5 boxes are worth +50%.", cost = 550 },
			{ id = "golden_route", name = "Golden Route", desc = "First run per session grants ×2 payout.", cost = 700 },
			{ id = "compound_returns", name = "Compound Returns", desc = "Every delivery increases all future payouts by +1%.", cost = 1000 },
		}
	},
	{
		id = "time",
		name = "⏱️ TIME & AUTOMATION",
		icon = "⏱️",
		color = Color3.fromRGB(150, 100, 255),
		skills = {
			{ id = "instant_deposit", name = "Instant Deposit", desc = "Deposit interaction is instant.", cost = 100 },
			{ id = "quick_turnaround", name = "Quick Turnaround", desc = "Return to pickup zone 40% faster.", cost = 175 },
			{ id = "auto_pickup", name = "Auto Pickup", desc = "Boxes within 3 studs auto-attach to stack.", cost = 275 },
			{ id = "cooldown_reduction", name = "Cooldown Reduction", desc = "All ability cooldowns reduced by 20%.", cost = 400 },
			{ id = "run_recall", name = "Run Recall", desc = "After deposit, teleport to pickup zone after 2s.", cost = 550 },
			{ id = "phantom_carry", name = "Phantom Carry", desc = "Dropped boxes persist for 5s before despawning.", cost = 650 },
			{ id = "time_compression", name = "Time Compression", desc = "Activate +30% global speed for 5s (90s CD).", cost = 800 },
			{ id = "zero_downtime", name = "Zero Downtime", desc = "No delays between pickups, deposits, or teleports.", cost = 1200 },
		}
	},
	{
		id = "route",
		name = "🎯 ROUTE MASTERY",
		icon = "🎯",
		color = Color3.fromRGB(255, 100, 100),
		skills = {
			{ id = "line_bonus", name = "Line Bonus", desc = "Staying on optimal path grants +10% speed.", cost = 125 },
			{ id = "checkpoint_memory", name = "Checkpoint Memory", desc = "Passing a checkpoint increases speed by +5% (stacking).", cost = 200 },
			{ id = "perfect_delivery", name = "Perfect Delivery", desc = "Deposit within 0.25s window → +25% payout.", cost = 300 },
			{ id = "risk_route", name = "Risk Route", desc = "Optional shortcut grants +40% payout.", cost = 425 },
			{ id = "split_path", name = "Split Path Awareness", desc = "UI highlights the most efficient route.", cost = 500 },
			{ id = "speedrun_bonus", name = "Speedrun Bonus", desc = "Finish under target time → +30% payout.", cost = 625 },
			{ id = "master_route", name = "Master Route", desc = "After 25 flawless runs, gain permanent +10% payout.", cost = 850 },
			{ id = "flawless_run", name = "Flawless Run", desc = "No stops or turns → ×1.5 payout multiplier.", cost = 1100 },
		}
	},
	{
		id = "social",
		name = "🤝 SOCIAL & META",
		icon = "🤝",
		color = Color3.fromRGB(100, 255, 150),
		skills = {
			{ id = "nearby_boost", name = "Nearby Boost", desc = "Within 5 studs of another player → +10% speed.", cost = 100 },
			{ id = "shared_deposit", name = "Shared Deposit", desc = "Depositing within 3s of another player grants +15% payout.", cost = 200 },
			{ id = "assist_credit", name = "Assist Credit", desc = "Helping another player grants +20% of their delivery payout.", cost = 325 },
			{ id = "convoy_mode", name = "Convoy Mode", desc = "3+ players together → +25% speed.", cost = 450 },
			{ id = "leader_aura", name = "Leader Aura", desc = "Party leader grants +10% payout to party members.", cost = 575 },
			{ id = "relay_carry", name = "Relay Carry", desc = "Transfer boxes to another player instantly.", cost = 700 },
			{ id = "union_contract", name = "Union Contract", desc = "Server-wide goal → everyone gets +50% payout for 5 mins.", cost = 900 },
			{ id = "bridge_authority", name = "Bridge Authority", desc = "Activate server buff: +20% speed & payout for 60s.", cost = 1500 },
		}
	},
	{
		id = "specialization",
		name = "🌟 SPECIALIZATIONS",
		icon = "🌟",
		color = Color3.fromRGB(255, 215, 0),
		skills = {
			{ id = "the_sprinter", name = "The Sprinter", desc = "+40% speed, −2 max boxes. [LOCK-IN]", cost = 2000, isSpecialization = true },
			{ id = "the_hauler", name = "The Hauler", desc = "+5 max boxes, −20% speed. [LOCK-IN]", cost = 2000, isSpecialization = true },
			{ id = "the_tycoon", name = "The Tycoon", desc = "All payout bonuses increased by +50%. [LOCK-IN]", cost = 2000, isSpecialization = true },
			{ id = "the_operator", name = "The Operator", desc = "Cooldowns reduced by 50%, automation doubled. [LOCK-IN]", cost = 2000, isSpecialization = true },
		}
	},
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONFIG                                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local CONFIG = {
	-- Button
	ButtonPosition = UDim2.new(0, 20, 0, 130),
	ButtonSize = UDim2.new(0, 180, 0, 42),
	
	-- Window (larger)
	WindowSize = UDim2.new(0, 1250, 0, 750),
	
	-- Colors - Cyberpunk/Industrial Theme
	BackgroundColor = Color3.fromRGB(15, 17, 22),
	PanelColor = Color3.fromRGB(22, 25, 32),
	CardColor = Color3.fromRGB(30, 34, 42),
	AccentColor = Color3.fromRGB(255, 180, 50),
	TextColor = Color3.fromRGB(255, 255, 255),
	SubtextColor = Color3.fromRGB(140, 140, 150),
	LockedColor = Color3.fromRGB(60, 62, 70),
	UnlockedColor = Color3.fromRGB(80, 200, 120),
	AvailableColor = Color3.fromRGB(100, 180, 255),
	DisabledTextColor = Color3.fromRGB(80, 80, 90),
}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         CONTROLLER                                          ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local SkillTreeController = Knit.CreateController {
	Name = "SkillTreeController",
}

-- State
local isWindowOpen = Value(false)
local selectedCategory = Value(1)
local playerKudos = Value(0)
local unlockedSkills = Value({})
local hoveredSkill = Value(nil)

-- References
local screenGui = nil
local skillTreeService = nil

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         HELPER FUNCTIONS                                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function formatNumber(num)
	if num >= 1000000 then
		return string.format("%.1fM", num / 1000000)
	elseif num >= 1000 then
		return string.format("%.1fK", num / 1000)
	end
	return tostring(num)
end

local function isSkillUnlocked(skillId)
	local unlocked = unlockedSkills:get()
	return unlocked[skillId] == true
end

local function canUnlockSkill(categoryIndex, skillIndex)
	-- First skill in category is always available
	if skillIndex == 1 then
		return true
	end
	
	-- Otherwise, need previous skill unlocked
	local category = SKILL_CATEGORIES[categoryIndex]
	if not category then return false end
	
	local prevSkill = category.skills[skillIndex - 1]
	if not prevSkill then return false end
	
	return isSkillUnlocked(prevSkill.id)
end

local function getSkillState(categoryIndex, skillIndex)
	local category = SKILL_CATEGORIES[categoryIndex]
	if not category then return "locked" end
	
	local skill = category.skills[skillIndex]
	if not skill then return "locked" end
	
	if isSkillUnlocked(skill.id) then
		return "unlocked"
	elseif canUnlockSkill(categoryIndex, skillIndex) then
		return "available"
	else
		return "locked"
	end
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         UI COMPONENTS                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

local function CreateSkillNode(categoryIndex, skillIndex, skill, yPosition)
	local state = Computed(function()
		unlockedSkills:get() -- Subscribe to changes
		return getSkillState(categoryIndex, skillIndex)
	end)
	
	local backgroundColor = Computed(function()
		local s = state:get()
		if s == "unlocked" then
			return CONFIG.UnlockedColor
		elseif s == "available" then
			return CONFIG.AvailableColor
		else
			return CONFIG.LockedColor
		end
	end)
	
	local textColor = Computed(function()
		local s = state:get()
		if s == "locked" then
			return CONFIG.DisabledTextColor
		else
			return CONFIG.TextColor
		end
	end)
	
	local canAfford = Computed(function()
		return playerKudos:get() >= skill.cost
	end)
	
	local isHovered = Computed(function()
		return hoveredSkill:get() == skill.id
	end)
	
	local scale = Spring(Computed(function()
		return isHovered:get() and 1.02 or 1
	end), 40, 0.8)
	
	return New "Frame" {
		Name = "Skill_" .. skill.id,
		Size = UDim2.new(1, -20, 0, 110),
		Position = UDim2.new(0, 10, 0, yPosition),
		BackgroundColor3 = Spring(backgroundColor, 25),
		
		[Children] = {
			New "UICorner" {
				CornerRadius = UDim.new(0, 10),
			},
			
			New "UIStroke" {
				Color = Computed(function()
					local s = state:get()
					if s == "unlocked" then
						return Color3.fromRGB(100, 255, 150)
					elseif s == "available" and canAfford:get() then
						return Color3.fromRGB(100, 200, 255)
					elseif s == "available" then
						return Color3.fromRGB(150, 100, 100)
					else
						return Color3.fromRGB(50, 52, 58)
					end
				end),
				Thickness = Computed(function()
					return isHovered:get() and 2.5 or 1.5
				end),
			},
			
			New "UIScale" {
				Scale = scale,
			},
			
			-- Skill number badge
			New "Frame" {
				Size = UDim2.new(0, 44, 0, 44),
				Position = UDim2.new(0, 14, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Computed(function()
					local s = state:get()
					if s == "unlocked" then
						return Color3.fromRGB(60, 180, 100)
					elseif s == "available" then
						return Color3.fromRGB(70, 140, 200)
					else
						return Color3.fromRGB(45, 48, 55)
					end
				end),
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(1, 0),
					},
					
					New "TextLabel" {
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Text = Computed(function()
							local s = state:get()
							if s == "unlocked" then
								return "✓"
							else
								return tostring(skillIndex)
							end
						end),
						TextColor3 = CONFIG.TextColor,
						TextSize = 22,
						Font = Enum.Font.GothamBold,
					}
				}
			},
			
			-- Skill name
			New "TextLabel" {
				Size = UDim2.new(1, -220, 0, 32),
				Position = UDim2.new(0, 70, 0, 12),
				BackgroundTransparency = 1,
				Text = skill.name,
				TextColor3 = textColor,
				TextSize = 22,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
			
			-- Skill description
			New "TextLabel" {
				Size = UDim2.new(1, -220, 0, 55),
				Position = UDim2.new(0, 70, 0, 44),
				BackgroundTransparency = 1,
				Text = skill.desc,
				TextColor3 = CONFIG.SubtextColor,
				TextSize = 18,
				Font = Enum.Font.Gotham,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
			},
			
			-- Cost / Status badge
			New "Frame" {
				Size = UDim2.new(0, 130, 0, 48),
				Position = UDim2.new(1, -145, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Computed(function()
					local s = state:get()
					if s == "unlocked" then
						return Color3.fromRGB(50, 150, 80)
					elseif s == "available" and canAfford:get() then
						return Color3.fromRGB(50, 120, 180)
					elseif s == "available" then
						return Color3.fromRGB(120, 60, 60)
					else
						return Color3.fromRGB(35, 38, 45)
					end
				end),
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0, 10),
					},
					
					New "TextLabel" {
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Text = Computed(function()
							local s = state:get()
							if s == "unlocked" then
								return "✓ OWNED"
							else
								return "⭐ " .. formatNumber(skill.cost)
							end
						end),
						TextColor3 = CONFIG.TextColor,
						TextSize = 18,
						Font = Enum.Font.GothamBold,
					}
				}
			},
			
			-- Clickable overlay
			New "TextButton" {
				Size = UDim2.new(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = "",
				
				[OnEvent "MouseEnter"] = function()
					hoveredSkill:set(skill.id)
				end,
				
				[OnEvent "MouseLeave"] = function()
					if hoveredSkill:get() == skill.id then
						hoveredSkill:set(nil)
					end
				end,
				
				[OnEvent "MouseButton1Click"] = function()
					local s = getSkillState(categoryIndex, skillIndex)
					if s == "available" and playerKudos:get() >= skill.cost then
						SkillTreeController:TryUnlockSkill(skill.id, skill.cost)
					elseif s == "available" then
						SkillTreeController:ShowMessage("Not enough Kudos!", Color3.fromRGB(255, 100, 100))
					elseif s == "locked" then
						SkillTreeController:ShowMessage("Unlock previous skills first!", Color3.fromRGB(255, 180, 50))
					end
				end,
			},
			
			-- Connector line to next skill (only show if not last skill)
			skillIndex < #SKILL_CATEGORIES[categoryIndex].skills and New "Frame" {
				Size = UDim2.new(0, 4, 0, 22),
				Position = UDim2.new(0, 34, 1, 0),
				BackgroundColor3 = Computed(function()
					local s = state:get()
					if s == "unlocked" then
						return Color3.fromRGB(80, 200, 120)
					else
						return Color3.fromRGB(50, 55, 65)
					end
				end),
				BorderSizePixel = 0,
			} or nil,
		}
	}
end

local function CreateCategoryTab(index, category)
	local isSelected = Computed(function()
		return selectedCategory:get() == index
	end)
	
	local backgroundColor = Spring(Computed(function()
		if isSelected:get() then
			return category.color
		else
			return CONFIG.CardColor
		end
	end), 30)
	
	return New "TextButton" {
		Name = "Tab_" .. category.id,
		Size = UDim2.new(1, -10, 0, 52),
		BackgroundColor3 = backgroundColor,
		Text = "",
		AutoButtonColor = false,
		
		[OnEvent "MouseButton1Click"] = function()
			selectedCategory:set(index)
		end,
		
		[Children] = {
			New "UICorner" {
				CornerRadius = UDim.new(0, 10),
			},
			
			New "UIStroke" {
				Color = Computed(function()
					return isSelected:get() and category.color or Color3.fromRGB(50, 55, 65)
				end),
				Thickness = 2,
				Transparency = Computed(function()
					return isSelected:get() and 0 or 0.5
				end),
			},
			
			-- Icon
			New "TextLabel" {
				Size = UDim2.new(0, 36, 1, 0),
				Position = UDim2.new(0, 10, 0, 0),
				BackgroundTransparency = 1,
				Text = category.icon,
				TextSize = 22,
			},
			
			-- Category name
			New "TextLabel" {
				Size = UDim2.new(1, -80, 1, 0),
				Position = UDim2.new(0, 46, 0, 0),
				BackgroundTransparency = 1,
				Text = category.name:gsub("^[^%s]+%s+", ""), -- Remove emoji prefix
				TextColor3 = Computed(function()
					return isSelected:get() and Color3.fromRGB(30, 30, 35) or CONFIG.TextColor
				end),
				TextSize = 15,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			},
			
			-- Unlock progress badge
			New "Frame" {
				Size = UDim2.new(0, 30, 0, 24),
				Position = UDim2.new(1, -38, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Computed(function()
					return isSelected:get() and Color3.fromRGB(30, 30, 35) or Color3.fromRGB(50, 55, 65)
				end),
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0, 6),
					},
					
					New "TextLabel" {
						Size = UDim2.new(1, 0, 1, 0),
						BackgroundTransparency = 1,
						Text = Computed(function()
							unlockedSkills:get()
							local count = 0
							for _, skill in ipairs(category.skills) do
								if isSkillUnlocked(skill.id) then
									count = count + 1
								end
							end
							return tostring(count)
						end),
						TextColor3 = Computed(function()
							return isSelected:get() and category.color or CONFIG.SubtextColor
						end),
						TextSize = 12,
						Font = Enum.Font.GothamBold,
					}
				}
			}
		}
	}
end

local function CreateSkillsPanel()
	return New "ScrollingFrame" {
		Name = "SkillsPanel",
		Size = UDim2.new(1, -280, 1, -80),
		Position = UDim2.new(0, 270, 0, 70),
		BackgroundColor3 = CONFIG.PanelColor,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = CONFIG.AccentColor,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		
		[Children] = {
			New "UICorner" {
				CornerRadius = UDim.new(0, 12),
			},
			
			New "UIPadding" {
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
			},
			
			-- Category header
			Computed(function()
				local catIndex = selectedCategory:get()
				local category = SKILL_CATEGORIES[catIndex]
				if not category then return nil end
				
				return New "Frame" {
					Size = UDim2.new(1, -20, 0, 60),
					Position = UDim2.new(0, 10, 0, 0),
					BackgroundColor3 = category.color,
					
					[Children] = {
						New "UICorner" {
							CornerRadius = UDim.new(0, 10),
						},
						
						New "TextLabel" {
							Size = UDim2.new(1, -20, 1, 0),
							Position = UDim2.new(0, 16, 0, 0),
							BackgroundTransparency = 1,
							Text = category.name,
							TextColor3 = Color3.fromRGB(20, 22, 28),
							TextSize = 26,
							Font = Enum.Font.GothamBold,
							TextXAlignment = Enum.TextXAlignment.Left,
						},
						
						-- Progress text
						New "TextLabel" {
							Size = UDim2.new(0, 120, 1, 0),
							Position = UDim2.new(1, -130, 0, 0),
							BackgroundTransparency = 1,
							Text = Computed(function()
								unlockedSkills:get()
								local count = 0
								for _, skill in ipairs(category.skills) do
									if isSkillUnlocked(skill.id) then
										count = count + 1
									end
								end
								return string.format("%d/%d", count, #category.skills)
							end),
							TextColor3 = Color3.fromRGB(20, 22, 28),
							TextSize = 22,
							Font = Enum.Font.GothamBold,
							TextXAlignment = Enum.TextXAlignment.Right,
						},
					}
				}
			end, Fusion.cleanup),
			
			-- Skills list
			Computed(function()
				local catIndex = selectedCategory:get()
				local category = SKILL_CATEGORIES[catIndex]
				if not category then return nil end
				
				local children = {}
				for i, skill in ipairs(category.skills) do
					local yPos = 75 + (i - 1) * 128
					table.insert(children, CreateSkillNode(catIndex, i, skill, yPos))
				end
				
				return New "Frame" {
					Name = "SkillsList",
					Size = UDim2.new(1, 0, 0, 75 + #category.skills * 128),
					BackgroundTransparency = 1,
					
					[Children] = children
				}
			end, Fusion.cleanup),
		}
	}
end

local function CreateMainWindow()
	local windowVisible = Spring(Computed(function()
		return isWindowOpen:get() and 1 or 0
	end), 35, 0.9)
	
	local windowScale = Spring(Computed(function()
		return isWindowOpen:get() and 1 or 0.9
	end), 40, 0.8)
	
	return New "Frame" {
		Name = "SkillTreeWindow",
		Size = CONFIG.WindowSize,
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.BackgroundColor,
		Visible = Computed(function()
			return windowVisible:get() > 0.01
		end),
		BackgroundTransparency = Computed(function()
			return 1 - windowVisible:get()
		end),
		
		[Children] = {
			New "UICorner" {
				CornerRadius = UDim.new(0, 14),
			},
			
			New "UIStroke" {
				Color = CONFIG.AccentColor,
				Thickness = 2,
				Transparency = Computed(function()
					return 1 - windowVisible:get()
				end),
			},
			
			New "UIScale" {
				Scale = windowScale,
			},
			
			-- Header
			New "Frame" {
				Name = "Header",
				Size = UDim2.new(1, 0, 0, 60),
				BackgroundColor3 = Color3.fromRGB(25, 28, 35),
				BorderSizePixel = 0,
				
				[Children] = {
					New "UICorner" {
						CornerRadius = UDim.new(0, 14),
					},
					
					-- Bottom corner fix
					New "Frame" {
						Size = UDim2.new(1, 0, 0, 15),
						Position = UDim2.new(0, 0, 1, -15),
						BackgroundColor3 = Color3.fromRGB(25, 28, 35),
						BorderSizePixel = 0,
					},
					
					-- Title
					New "TextLabel" {
						Size = UDim2.new(1, -200, 1, 0),
						Position = UDim2.new(0, 24, 0, 0),
						BackgroundTransparency = 1,
						Text = "🌟 SKILL TREE",
						TextColor3 = CONFIG.AccentColor,
						TextSize = 28,
						Font = Enum.Font.GothamBold,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					
					-- Kudos display
					New "Frame" {
						Size = UDim2.new(0, 150, 0, 40),
						Position = UDim2.new(1, -210, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = Color3.fromRGB(35, 38, 45),
						
						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0, 10),
							},
							
							New "TextLabel" {
								Size = UDim2.new(1, 0, 1, 0),
								BackgroundTransparency = 1,
								Text = Computed(function()
									return "⭐ " .. formatNumber(playerKudos:get())
								end),
								TextColor3 = CONFIG.AccentColor,
								TextSize = 18,
								Font = Enum.Font.GothamBold,
							}
						}
					},
					
					-- Close button
					New "TextButton" {
						Name = "CloseButton",
						Size = UDim2.new(0, 44, 0, 44),
						Position = UDim2.new(1, -54, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = Color3.fromRGB(180, 60, 60),
						Text = "✕",
						TextColor3 = Color3.new(1, 1, 1),
						TextSize = 22,
						Font = Enum.Font.GothamBold,
						AutoButtonColor = false,
						
						[OnEvent "MouseButton1Click"] = function()
							isWindowOpen:set(false)
						end,
						
						[Children] = {
							New "UICorner" {
								CornerRadius = UDim.new(0, 10),
							}
						}
					}
				}
			},
			
			-- Category tabs sidebar
			New "Frame" {
				Name = "CategorySidebar",
				Size = UDim2.new(0, 260, 1, -70),
				Position = UDim2.new(0, 5, 0, 65),
				BackgroundTransparency = 1,
				
				[Children] = {
					New "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 8),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
					},
					
					ForPairs(SKILL_CATEGORIES, function(index, category)
						return index, CreateCategoryTab(index, category)
					end, Fusion.cleanup)
				}
			},
			
			-- Skills panel
			CreateSkillsPanel(),
		}
	}
end

local function CreateOpenButton()
	local isHovered = Value(false)
	
	local backgroundColor = Spring(Computed(function()
		return isHovered:get() and Color3.fromRGB(255, 200, 80) or CONFIG.AccentColor
	end), 35)
	
	return New "TextButton" {
		Name = "SkillTreeButton",
		Size = CONFIG.ButtonSize,
		Position = CONFIG.ButtonPosition,
		AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = backgroundColor,
		Text = "🌟 SKILLS",
		TextColor3 = Color3.fromRGB(30, 30, 30),
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		
		[OnEvent "MouseEnter"] = function()
			isHovered:set(true)
		end,
		
		[OnEvent "MouseLeave"] = function()
			isHovered:set(false)
		end,
		
		[OnEvent "MouseButton1Click"] = function()
			isWindowOpen:set(not isWindowOpen:get())
		end,
		
		[Children] = {
			New "UICorner" {
				CornerRadius = UDim.new(0, 8),
			},
			
			New "UIStroke" {
				Color = Color3.fromRGB(200, 140, 0),
				Thickness = 2,
			}
		}
	}
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         MAIN UI                                             ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeController:CreateUI()
	screenGui = New "ScreenGui" {
		Name = "SkillTreeGui",
		Parent = PlayerGui,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		
		[Children] = {
			CreateOpenButton(),
			CreateMainWindow(),
		}
	}
	
	-- Close on escape
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Escape and isWindowOpen:get() then
			isWindowOpen:set(false)
		end
	end)
	
	print("[SkillTreeController] UI created")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         SKILL FUNCTIONS                                     ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeController:TryUnlockSkill(skillId, cost)
	if not skillTreeService then
		warn("[SkillTreeController] SkillTreeService not available")
		return
	end
	
	print(string.format("[SkillTreeController] Attempting to unlock: %s for %d kudos", skillId, cost))
	
	local success, message = skillTreeService:UnlockSkill(skillId):await()
	
	if success then
		print("[SkillTreeController] Skill unlocked: " .. skillId)
		self:PlayUnlockEffect(skillId)
		self:ShowMessage("Skill Unlocked! ✓", CONFIG.UnlockedColor)
	else
		warn("[SkillTreeController] Failed to unlock: " .. tostring(message))
		self:ShowMessage(message or "Failed to unlock!", Color3.fromRGB(255, 100, 100))
	end
end

function SkillTreeController:PlayUnlockEffect(skillId)
	-- Flash effect on the skill node
	if not screenGui then return end
	
	-- Create particle burst at center
	local burst = Instance.new("Frame")
	burst.Name = "UnlockBurst"
	burst.Size = UDim2.new(0, 0, 0, 0)
	burst.Position = UDim2.new(0.5, 0, 0.5, 0)
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.BackgroundColor3 = CONFIG.AccentColor
	burst.Parent = screenGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = burst
	
	TweenService:Create(burst, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 200, 0, 200),
		BackgroundTransparency = 1,
	}):Play()
	
	task.delay(0.5, function()
		burst:Destroy()
	end)
end

function SkillTreeController:ShowMessage(text, color)
	if not screenGui then return end
	
	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.Size = UDim2.new(0, 380, 0, 55)
	message.Position = UDim2.new(0.5, 0, 0.2, 0)
	message.AnchorPoint = Vector2.new(0.5, 0.5)
	message.BackgroundColor3 = color or CONFIG.AccentColor
	message.BackgroundTransparency = 0.1
	message.Text = text
	message.TextColor3 = Color3.new(1, 1, 1)
	message.TextSize = 20
	message.Font = Enum.Font.GothamBold
	message.Parent = screenGui
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = message
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or CONFIG.AccentColor
	stroke.Thickness = 2
	stroke.Parent = message
	
	-- Animate in
	message.Position = UDim2.new(0.5, 0, 0.15, 0)
	message.BackgroundTransparency = 1
	message.TextTransparency = 1
	
	TweenService:Create(message, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.2, 0),
		BackgroundTransparency = 0.1,
		TextTransparency = 0,
	}):Play()
	
	-- Animate out
	task.delay(1.5, function()
		if message and message.Parent then
			TweenService:Create(message, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, 0, 0.15, 0),
				BackgroundTransparency = 1,
				TextTransparency = 1,
			}):Play()
			
			task.delay(0.3, function()
				if message and message.Parent then
					message:Destroy()
				end
			end)
		end
	end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         REPLICA SETUP                                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeController:SetupReplicaListeners()
	-- Listen for Kudos replica
	ReplicaController.ReplicaOfClassCreated("PlayerKudos_" .. Player.UserId, function(replica)
		print("[SkillTreeController] Kudos replica connected")
		
		playerKudos:set(replica.Data.Kudos or 0)
		
		replica:ListenToChange({"Kudos"}, function(newValue)
			playerKudos:set(newValue)
		end)
	end)
	
	-- Listen for Skills replica
	ReplicaController.ReplicaOfClassCreated("PlayerSkills_" .. Player.UserId, function(replica)
		print("[SkillTreeController] Skills replica connected")
		
		-- Initialize unlocked skills
		local skills = replica.Data.UnlockedSkills or {}
		local skillMap = {}
		for _, skillId in ipairs(skills) do
			skillMap[skillId] = true
		end
		unlockedSkills:set(skillMap)
		
		-- Listen for skill unlocks
		replica:ListenToChange({"UnlockedSkills"}, function(newValue)
			local skillMap = {}
			for _, skillId in ipairs(newValue or {}) do
				skillMap[skillId] = true
			end
			unlockedSkills:set(skillMap)
		end)
	end)
	
	print("[SkillTreeController] Replica listeners setup")
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║                         KNIT LIFECYCLE                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

function SkillTreeController:KnitInit()
	print("[SkillTreeController] Initializing...")
end

function SkillTreeController:KnitStart()
	print("[SkillTreeController] Starting...")
	
	-- Request replica data
	ReplicaController.RequestData()
	
	-- Setup replica listeners
	self:SetupReplicaListeners()
	
	-- Get service reference (may not exist yet)
	task.spawn(function()
		local success, service = pcall(function()
			return Knit.GetService("SkillTreeService")
		end)
		
		if success and service then
			skillTreeService = service
			print("[SkillTreeController] SkillTreeService connected")
		else
			warn("[SkillTreeController] SkillTreeService not available - skills will be visual only")
		end
	end)
	
	-- Create UI
	self:CreateUI()
	
	print("[SkillTreeController] Started!")
end

return SkillTreeController

