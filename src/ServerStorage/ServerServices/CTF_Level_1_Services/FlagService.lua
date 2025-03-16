local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

local Teams = game:GetService("Teams")
local Players = game:GetService("Players")

local FLAG_PREFAB_TAG = "Flag"
local PREFAB_FOLDER = ReplicatedStorage:WaitForChild("Prefabs")

local FlagService = Knit.CreateService {
    Name = "FlagService",
    Client = {},
}

function FlagService:KnitInit()
    self.SpawnsByTeam = {}
end

function FlagService:RegisterSpawn(team, cframe)
    self.SpawnsByTeam[team] = cframe
    print("Registered spawn for team:", team)
end

function FlagService:UnregisterSpawn(team, cframe)
    if self.SpawnsByTeam[team] == cframe then
        self.SpawnsByTeam[team] = nil
        print("Unregistered spawn for team:", team)
    end
end

function FlagService:HandleFlagPickup(player, flag)
    if not (player.Character and player.Character:FindFirstChild("Humanoid")) then return end

    local playerTeam = player.Team and player.Team.Name or "None"
    local flagTeam = flag:GetAttribute("FlagColor")

    -- ✅ Prevent players from picking up their own team's flag
    if playerTeam == flagTeam then
        warn(player.Name .. " tried to pick up their own team's flag!")
        return
    end

    local primaryPart = flag.PrimaryPart
    assert(primaryPart, "Flag must have a PrimaryPart.")

    -- Disable existing AlignOrientation when picked up (if it exists)
    local alignOrientation = primaryPart:FindFirstChild("FlagAlignOrientation")
    if alignOrientation then
        alignOrientation.Enabled = false
    end

    -- Unanchor all parts for picking up
    for _, part in ipairs(flag:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
        end
    end

    -- Equip flag as Tool
    flag:SetAttribute("isBeingDestroyed", false) -- ✅ Track if flag is being destroyed
    flag.Parent = player.Backpack
    player.Character.Humanoid:EquipTool(flag)
    flag.PromptLoc.ProximityPrompt.Enabled = false

    player:SetAttribute("HasFlag", true)
    print(player.Name .. " picked up and equipped the enemy flag!")

    local function handleFlagDrop()
        -- ✅ Check if the flag is being destroyed before dropping it
        if flag:GetAttribute("isBeingDestroyed") then
            return
        end

        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local hrp = char.HumanoidRootPart

            -- Position flag slightly in front and above player
            local dropCFrame = hrp.CFrame * CFrame.new(0, 2, -4)
            flag.Parent = workspace
            flag:PivotTo(dropCFrame)

            -- Apply impulse clearly to PrimaryPart
            primaryPart.AssemblyLinearVelocity = hrp.CFrame.LookVector * 30 + Vector3.new(0, 10, 0)

            -- Create AlignOrientation once if it doesn't exist, else enable
            alignOrientation = primaryPart:FindFirstChild("FlagAlignOrientation")
            if not alignOrientation then
                alignOrientation = Instance.new("AlignOrientation")
                alignOrientation.Name = "FlagAlignOrientation"
                alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
                alignOrientation.RigidityEnabled = true
                alignOrientation.Attachment0 = Instance.new("Attachment", primaryPart)
                alignOrientation.CFrame = CFrame.new()
                alignOrientation.Parent = primaryPart
            end
            alignOrientation.Enabled = true

            flag.PromptLoc.ProximityPrompt.Enabled = true
            player:SetAttribute("HasFlag", false)

            print(player.Name .. " dropped the flag.")
        end
    end

    -- ✅ Connect Unequipped event
    local unequippedConnection
    unequippedConnection = flag.Unequipped:Connect(function()
        -- ✅ Check if the flag is being destroyed before handling unequip
        if flag:GetAttribute("isBeingDestroyed") then
            return
        end

        unequippedConnection:Disconnect()
        print("Unequipped")
        handleFlagDrop()
    end)
end


function FlagService:SpawnFlags()
    local prefab = nil
    for _, obj in ipairs(CollectionService:GetTagged(FLAG_PREFAB_TAG)) do
        if obj:IsDescendantOf(PREFAB_FOLDER) then
            prefab = obj
            break
        end
    end
    assert(prefab and prefab.PrimaryPart, "Flag prefab needs PrimaryPart and 'Flag' tag.")

    for team, spawnCFrame in pairs(self.SpawnsByTeam) do
        local flagClone = prefab:Clone()
        flagClone:SetAttribute("FlagColor", team) -- Store team name in flag attribute
        flagClone:PivotTo(spawnCFrame)

        local promptLoc = flagClone:FindFirstChild("PromptLoc")
        if promptLoc then
            local proximityPrompt = promptLoc:FindFirstChildOfClass("ProximityPrompt")
            if proximityPrompt then
                proximityPrompt.Triggered:Connect(function(player)
                    self:HandleFlagPickup(player, flagClone)
                end)
            else
                warn("ProximityPrompt missing inside PromptLoc.")
            end
        else
            warn("PromptLoc part missing in Flag prefab.")
        end

        flagClone.Parent = workspace
        print("Spawned flag for team:", team)
    end
end

function FlagService:ClearFlags()
    for _, flag in ipairs(CollectionService:GetTagged(FLAG_PREFAB_TAG)) do
        if flag.Parent == workspace then
            flag:Destroy()
        end
    end
end

function FlagService:KnitStart()
    task.delay(1, function()
        self:ClearFlags()
        self:SpawnFlags()
        print("Flags spawned successfully after delay.")
    end)
end
function FlagService:ResetFlag(teamColor)
    if not self.SpawnsByTeam[teamColor] then
        warn("No spawn location found for team:", teamColor)
        return
    end

    -- ✅ Remove any existing flag of this color from the workspace
    for _, flag in ipairs(CollectionService:GetTagged(FLAG_PREFAB_TAG)) do
        if flag:GetAttribute("FlagColor") == teamColor then
            if flag.Parent then
                flag:SetAttribute("isBeingDestroyed", true) -- ✅ Prevent accidental unequip handling
                flag:Destroy()
                print("Removed old flag for team:", teamColor)
            end
        end
    end

    -- ✅ Add a slight delay to allow cleanup before respawning
    task.delay(0.5, function()
        local spawnCFrame = self.SpawnsByTeam[teamColor]
        local prefab = nil

        -- ✅ Find the flag prefab in ReplicatedStorage
        for _, obj in ipairs(CollectionService:GetTagged(FLAG_PREFAB_TAG)) do
            if obj:IsDescendantOf(PREFAB_FOLDER) then
                prefab = obj
                break
            end
        end

        assert(prefab and prefab.PrimaryPart, "Flag prefab needs PrimaryPart and 'Flag' tag.")

        -- ✅ Clone the flag and reconfigure it
        local flagClone = prefab:Clone()
        flagClone:SetAttribute("FlagColor", teamColor)
        flagClone:SetAttribute("isBeingDestroyed", false) -- ✅ Ensure it is not being destroyed
        flagClone:PivotTo(spawnCFrame)
        flagClone.Parent = workspace

        -- ✅ Re-register flag with CollectionService
        CollectionService:AddTag(flagClone, FLAG_PREFAB_TAG)

        -- ✅ Anchor all parts inside the flag tool
        for _, part in ipairs(flagClone:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = true
            end
        end

        -- ✅ Re-enable ProximityPrompt
        local promptLoc = flagClone:FindFirstChild("PromptLoc")
        if promptLoc then
            local proximityPrompt = promptLoc:FindFirstChildOfClass("ProximityPrompt")
            if proximityPrompt then
                proximityPrompt.Enabled = true -- Ensure prompt is re-enabled
                proximityPrompt.Triggered:Connect(function(player)
                    self:HandleFlagPickup(player, flagClone)
                end)
            else
                warn("ProximityPrompt missing inside PromptLoc.")
            end
        else
            warn("PromptLoc part missing in Flag prefab.")
        end

        print("Respawned flag for team:", teamColor, "with all parts anchored.")
    end)
end






return FlagService
