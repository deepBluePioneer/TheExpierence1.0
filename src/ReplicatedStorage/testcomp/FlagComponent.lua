local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Component = require(Packages.Component)
local Knit = require(Packages.Knit)

local FlagService
local FLAG_TAG = "Flag"

local FlagComponent = Component.new {
    Tag = FLAG_TAG,
}

-- ✅ Constructor: Initialize flag behavior
function FlagComponent:Construct()
    self.Flag = self.Instance
    self.TeamColor = self.Flag:GetAttribute("FlagColor") -- "Red" or "Blue"
    self.Flag.PrimaryPart = self.Flag.PrimaryPart or self.Flag:FindFirstChildWhichIsA("BasePart")
    self.Flag:SetAttribute("isBeingDestroyed", false)

    -- Ensure FlagService is loaded
    if not FlagService then
        FlagService = Knit.GetService("FlagService")
    end

    -- ✅ Setup interactions
    self:SetupProximityPrompt()
end

-- ✅ Setup the proximity prompt for pickup
function FlagComponent:SetupProximityPrompt()
    local promptLoc = self.Flag:FindFirstChild("PromptLoc")
    if promptLoc then
        local proximityPrompt = promptLoc:FindFirstChildOfClass("ProximityPrompt")
        if proximityPrompt then
            proximityPrompt.Triggered:Connect(function(player)
                self:OnPickup(player)
            end)
        end
    end
end

-- ✅ Handle flag pickup by a player
function FlagComponent:OnPickup(player)
    if not player or not player.Character then return end

    -- Prevent picking up own flag
    if player.Team and player.Team.Name == self.TeamColor then
        warn(player.Name .. " tried to pick up their own flag!")
        return
    end

    -- ✅ Transfer flag to player
    self.Flag:SetAttribute("isBeingDestroyed", false)
    self.Flag.Parent = player.Backpack
    player:SetAttribute("HasFlag", true)
    print(player.Name .. " picked up the enemy flag!")

    -- ✅ Disable proximity prompt
    local promptLoc = self.Flag:FindFirstChild("PromptLoc")
    if promptLoc then
        local proximityPrompt = promptLoc:FindFirstChildOfClass("ProximityPrompt")
        if proximityPrompt then
            proximityPrompt.Enabled = false
        end
    end

    -- ✅ Handle when the player drops the flag
    self.UnequippedConnection = self.Flag.Unequipped:Connect(function()
        self:OnDrop(player)
    end)

    -- ✅ Ensure flag drops if the player dies or leaves
    local char = player.Character
    if char then
        self.DiedConnection = char:FindFirstChildOfClass("Humanoid").Died:Connect(function()
            self:OnDrop(player, true)
        end)

        self.RemovingConnection = player.CharacterRemoving:Connect(function()
            self:OnDrop(player, true)
        end)
    end
end

-- ✅ Handle flag drop logic
function FlagComponent:OnDrop(player, forceDrop)
    if self.Flag:GetAttribute("isBeingDestroyed") then return end

    -- Remove connections
    if self.UnequippedConnection then
        self.UnequippedConnection:Disconnect()
        self.UnequippedConnection = nil
    end

    if self.DiedConnection then
        self.DiedConnection:Disconnect()
        self.DiedConnection = nil
    end

    if self.RemovingConnection then
        self.RemovingConnection:Disconnect()
        self.RemovingConnection = nil
    end

    -- ✅ Drop the flag at the player's location
    local char = player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local hrp = char.HumanoidRootPart
        self.Flag.Parent = workspace
        self.Flag:PivotTo(hrp.CFrame * CFrame.new(0, 2, -4))

        -- Apply impulse
        local primaryPart = self.Flag.PrimaryPart
        if primaryPart then
            primaryPart.AssemblyLinearVelocity = hrp.CFrame.LookVector * 30 + Vector3.new(0, 10, 0)
        end
    end

    -- ✅ Reset player's flag status
    player:SetAttribute("HasFlag", false)
    print(player.Name .. " dropped the flag.")

    -- ✅ Enable the proximity prompt again
    local promptLoc = self.Flag:FindFirstChild("PromptLoc")
    if promptLoc then
        local proximityPrompt = promptLoc:FindFirstChildOfClass("ProximityPrompt")
        if proximityPrompt then
            proximityPrompt.Enabled = true
        end
    end

    -- ✅ If force-dropped (player left/died), reset flag
    if forceDrop then
        self.Flag:SetAttribute("isBeingDestroyed", true)
        task.wait(1) -- Avoid duplicate respawns
        FlagService:ResetFlag(self.TeamColor)
    end
end

return FlagComponent
