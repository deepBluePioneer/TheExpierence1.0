local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local TweenService = game:GetService("TweenService")  -- Required for creating tweens

-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

local ScareZones

local ScareZoneService = Knit.CreateService {
    Name = "ScareZoneService",
    Client = {},
}

function  Start()

      -- Initialize each zone
      local zone = Zone.new(ScareZones.zone_1)
    
      local headLocStart = ScareZones.zone_1.headLocStart
      local headLocEnd =  ScareZones.zone_1.headLocEnd
      local head = ScareZones.zone_1.head
  
      -- Position the head at the start location initially
      head.Position = headLocStart.Position
  
      -- Set up the tween info and the tween
      local tweenInfo = TweenInfo.new(
          .15,  -- Duration in seconds
          Enum.EasingStyle.Linear,  -- Easing style
          Enum.EasingDirection.Out,  -- Easing direction
          0,  -- Number of times to repeat
          false,  -- Reverses the tween
          0  -- Delay time
      )
      local tweenGoal = {Position = headLocEnd.Position}
      local headTween = TweenService:Create(head, tweenInfo, tweenGoal)
  
      -- Connect events for the zone
      zone.playerEntered:Connect(function(player)
          warn("SCARE")
          headTween:Play()  -- Play the tween when a player enters the zone
      end)
      
      zone.playerExited:Connect(function(player)
          -- Optionally, you could reset the head's position here or do other actions
      end)
    
end

function ScareZoneService:KnitStart()
  
end

function ScareZoneService:KnitInit()
    -- Initialization logic
   -- ScareZones = workspace:WaitForChild("ScareZones")
end

return ScareZoneService
