local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Component = require(Packages.Component)

-- Zone Detection
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)
local CollectionService = game:GetService("CollectionService")
local Knit = require(Packages.Knit)

-- Get other services
local FlagService
local TeamComponent = require(Packages.Component).Get("Team")

local CAPTURE_ZONE_TAG = "FlagReturnZone"

local CaptureZoneComponent = Component.new {
    Tag = CAPTURE_ZONE_TAG,
}

-- ✅ Constructor: Initialize the zone & flag return logic
function CaptureZoneComponent:Construct()
    self.ZonePart = self.Instance
    self.TeamColor = self.ZonePart:GetAttribute("TeamColor") -- "Red" or "Blue"

    -- Ensure FlagService is loaded
    if not FlagService then
        FlagService = Knit.GetService("FlagService")
    end

    -- Create a Zone instance for this return zone
    self.Zone = Zone.new(self.ZonePart)

    -- ✅ Connect player entry/exit events
    self.Zone.playerEntered:Connect(function(player)
        self:OnPlayerEnter(player)
    end)

    self.Zone.playerExited:Connect(function(player)
        self:OnPlayerExit(player)
    end)

    print("Capture Zone Initialized for team:", self.TeamColor)
end

-- ✅ Handle player entering the zone
function CaptureZoneComponent:OnPlayerEnter(player)
    if not player then return end

    local playerTeam = player.Team and player.Team.Name or "None"
    local hasFlag = player:GetAttribute("HasFlag")

    -- ✅ Only proceed if the player has a flag
    if hasFlag then
        -- ✅ Ensure the player is in **their own team's zone** and holding the **enemy flag**
        if playerTeam == self.TeamColor then
            print(player.Name .. " successfully returned the enemy flag!")

            -- ✅ Update team score
            local teamComp = TeamComponent:GetFromInstance(player.Team)
            if teamComp then
                teamComp:AddScore(1) -- Add score to the capturing team
            end

            -- ✅ Reset player's flag status
            player:SetAttribute("HasFlag", false)

            -- ✅ Respawn the flag (opposite team)
            FlagService:ResetFlag(playerTeam == "Red" and "Blue" or "Red") 

            -- ✅ TODO: Notify players (broadcast event, UI update, etc.)
        else
            print(player.Name .. " entered a capture zone but does not have the correct flag.")
        end
    end
end

-- ✅ Handle player exiting the zone
function CaptureZoneComponent:OnPlayerExit(player)
    print(player.Name .. " left the flag return zone.")
end

return CaptureZoneComponent
