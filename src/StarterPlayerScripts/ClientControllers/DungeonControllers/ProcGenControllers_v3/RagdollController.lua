local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local PlayerAddedController = CustomPackages.PlayerAddedController
local PlayerAddedFunctions = PlayerAddedController.PlayerAddedFunctions

local Ragdoll = require(script.Parent.Ragdoll)

local RagdollController = Knit.CreateController {
    Name = "RagdollController",
    Client = {},
}


function RagdollController:KnitStart()
    local CharactersFolder = workspace:WaitForChild("CharactersFolder")

    -- Iterate over all children in the CharactersFolder
    for _, characterModel in pairs(CharactersFolder:GetChildren()) do
        -- Check if the child is a Model and has a Humanoid
        if characterModel:IsA("Model") and characterModel:FindFirstChildOfClass("Humanoid") then
            -- Apply rigging and ragdoll to each character model containing a humanoid
            Ragdoll:RigPlayer(characterModel)
            Ragdoll:Ragdoll(characterModel)
        end
    end

    -- Handling the core part with a VectorForce constraint
  --  local Core = workspace:WaitForChild("Core")
  

end

function RagdollController:KnitInit()
    -- Add service initialization logic here
end

return RagdollController
