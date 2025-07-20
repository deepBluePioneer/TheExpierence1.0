-- Get ReplicatedStorage and require Knit
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Load the iris module
local Packages = ReplicatedStorage.Packages
local Iris = require(Packages.iris)

-- Create the irisInitController
local irisInitController = Knit.CreateController { Name = "irisInitController" }

-- Initialize Iris in the KnitInit phase
function irisInitController:KnitInit()
    Iris.Init()
    
    self.Iris = Iris  -- Store a reference to Iris in the controller
end

-- Provide a getter method for other scripts to access Iris
function irisInitController:GetIris()
    return self.Iris
end

-- Optional: implement functionality in KnitStart if needed
function irisInitController:KnitStart()
end

-- Return the controller
return irisInitController
