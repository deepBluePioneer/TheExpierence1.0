-- Server/Services/BedService.lua

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local Signal = require(Packages.Signal)

local BedService = Knit.CreateService {
    Name = "BedService",
    Client = {
        EnterBed = Knit.CreateSignal(),
        ExitBed =Knit.CreateSignal()
    },
}

local playingTracks = {}         -- [Player] = AnimationTrack
local originalPositions = {}     -- [Player] = CFrame

-- ==== Private Helpers ====

function BedService:_scanBeds()
    local beds = {}
    for _, inst in ipairs(CollectionService:GetTagged("bed")) do
        if inst:IsA("Model") and inst.PrimaryPart and inst:IsDescendantOf(Workspace) then
            table.insert(beds, inst)
        end
    end
    return beds
end

function BedService:_connectPrompt(bed: Model)
    local primaryPart = bed.PrimaryPart
    if not primaryPart then return end

    local prompt = primaryPart:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        warn(`[BedService] No ProximityPrompt on PrimaryPart of {bed:GetFullName()}`)
        return
    end

    prompt.Triggered:Connect(function(player)
        print(`[BedService] {player.Name} used bed: {bed.Name}`)

        local character = player.Character
        if not character or not character:IsDescendantOf(Workspace) then return end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not hrp or not humanoid then return end

        -- Save position and disable movement
        originalPositions[player] = hrp.CFrame
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
        humanoid.PlatformStand = true

        -- Move to bed
        local bedCFrame = primaryPart.CFrame
        local offset = CFrame.new(0, 1, 0)
        local rotation = CFrame.Angles(0, math.rad(180), 0)
        hrp.CFrame = bedCFrame * offset * rotation
        hrp.Anchored = true

        -- Fire client signal to switch to third person
        self.Client.EnterBed:Fire(player, bedCFrame)

        -- Play sleep animation
        if humanoid.RigType == Enum.HumanoidRigType.R15 then
            local animator = humanoid:FindFirstChildOfClass("Animator")
            if animator then
                local layAnim = Instance.new("Animation")
                layAnim.AnimationId = "rbxassetid://78434022144860"
                local track = animator:LoadAnimation(layAnim)
                track.Priority = Enum.AnimationPriority.Action
                track:Play()
                playingTracks[player] = track
            end
        end

        -- Wake up after delay
        task.delay(5, function()
            if humanoid and humanoid.Parent and hrp then
                local track = playingTracks[player]
                if track then
                    track:Stop()
                    playingTracks[player] = nil
                end

                hrp.Anchored = false
                humanoid.PlatformStand = false
                humanoid:ChangeState(Enum.HumanoidStateType.Running)

                -- Restore position
                local lastCFrame = originalPositions[player]
                if lastCFrame then
                    hrp.CFrame = lastCFrame
                    originalPositions[player] = nil
                end

                -- Fire client signal to return to first person
                self.Client.ExitBed:Fire(player)

                print(`[BedService] {player.Name} got up from bed.`)
            end
        end)
    end)
end

function BedService:_initAllBedPrompts()
    for _, bed in ipairs(self:_scanBeds()) do
        self:_connectPrompt(bed)
    end
end

function BedService:GetFirstBed()
    local beds = self:_scanBeds()
    return beds[1]
end

function BedService.Client:GetBedNames(player)
    local beds = self:_scanBeds()
    return table.move(beds, 1, #beds, 1, {}) :: { [number]: string }
end

function BedService:KnitInit() end

function BedService:KnitStart()
    self:_initAllBedPrompts()
    warn("[BedService] Started and connected to all bed prompts.")
end

return BedService
