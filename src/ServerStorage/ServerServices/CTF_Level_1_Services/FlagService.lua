local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)

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
    flag.Parent = player.Backpack
    player.Character.Humanoid:EquipTool(flag)
    flag.PromptLoc.ProximityPrompt.Enabled = false

    local function handleFlagDrop()
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local hrp = char.HumanoidRootPart

            -- Position flag slightly in front and above player
            local dropCFrame = hrp.CFrame * CFrame.new(0, 2, -4)
            flag.Parent = workspace
            flag:PivotTo(dropCFrame)

            -- Apply impulse clearly to PrimaryPart
            primaryPart.AssemblyLinearVelocity = hrp.CFrame.LookVector * 30 + Vector3.new(0, 10, 0)

            -- Create AlignOrientation once if doesn't exist, else enable
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
            print(player.Name .. " dropped the flag.")
        end
    end

    -- Connect Unequipped event
    local unequippedConnection
    unequippedConnection = flag.Unequipped:Connect(function()
        unequippedConnection:Disconnect()
        handleFlagDrop()
    end)

    print(player.Name .. " picked up and equipped the flag!")
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
        flagClone:SetAttribute("FlagColor", team)
        flagClone = flagClone
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

return FlagService
