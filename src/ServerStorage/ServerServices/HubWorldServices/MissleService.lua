local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions
local RunService = game:GetService("RunService")

local MissleService = Knit.CreateService {
    Name = "MissleService",
    Client = {},
}


local function init()

      -- Locate the saw model and missile part
      local sawModel = workspace:FindFirstChild("Saw")
      if not sawModel then
          warn("Saw model not found!")
          return
      end
  
      local missile = sawModel:FindFirstChild("SawBlade")
      if not missile then
          warn("Missile part not found in Saw model!")
          return
      end
  
    
  
      require(PlayerAddedFunctions)(
          function(JoiningPlayer)
              -- Player added logic (optional)
          end,
          function(LeavingPlayer)
              -- Player leaving logic (optional)
          end,
          function(Player, Character)
              -- Ensure Character and missile exist
              if not Character or not missile then return end
  
              -- Set network ownership of the missile
              missile:SetNetworkOwner(Player)
              print("Network ownership of the missile set to character:", Character.Name)
  
          end
      )
    
end

function MissleService:KnitStart()

    init()
  
end

function MissleService:KnitInit()
    -- Add service initialization logic here
end

return MissleService
