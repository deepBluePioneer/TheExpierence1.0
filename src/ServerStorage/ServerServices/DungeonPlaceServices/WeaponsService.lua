local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local CustomPackages = ReplicatedStorage.CustomPackages
local Players = game:GetService("Players")
local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions =  PlayerAddedController.PlayerAddedFunctions

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local FastCastFolder = CustomPackages.FastCastFolder
local FastCast = require(FastCastFolder.FastCastRedux)

local WeaponsService = Knit.CreateService {
    Name = "WeaponsService",
    Client = {},
}

local castParams
local castBehavior
local caster

local function OnRayHit(cast, result, velocity, bullet)
   
    local hit = result.Instance
    -- Check if the hit object is tagged with "boil"
    if CollectionService:HasTag(hit, "boil") then
        print(hit.Name .. " is tagged with 'boil'")
    
    end
end
function WeaponsService:KnitInit()
    -- Add service initialization logic here

    FastCast.VisualizeCasts = true
    caster = FastCast.new()

    -- Configure FastCast behavior to interact with tagged items
    castParams = RaycastParams.new()
    castParams.FilterType = Enum.RaycastFilterType.Exclude
    castParams.IgnoreWater = true

    castBehavior = FastCast.newBehavior()
    castBehavior.RaycastParams = castParams
    castBehavior.AutoIgnoreContainer = false
    
    caster.RayHit:Connect(OnRayHit)
end

function WeaponsService:KnitStart()

 
    require(PlayerAddedFunctions)(
        function(JoiningPlayer)

        end,
        function(LeavingPlayer)

        end,
        function(Player, Character)
            castParams.FilterDescendantsInstances = {Character}
        end
    )


end




function WeaponsService.Client:SendRay(player, ray)

    local character = player.Character

    if character then

        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local origin = ray.Origin
            local direction = ray.Direction -- Adjust the length as needed
            caster:Fire(origin, direction, 500, castBehavior)
        end
    end
end


return WeaponsService
