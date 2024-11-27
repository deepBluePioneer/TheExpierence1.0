local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local SawBladeSpinnerController = Knit.CreateController { Name = "SawBladeSpinnerController" }

local function  init()
     -- Find the Saw model in the Workspace
     local sawModel = Workspace:FindFirstChild("Saw")
  
     -- Rotation speed in radians per frame (adjust as needed)
     local rotationSpeed = math.rad(10000) -- Rotate 1 degree per frame
 
     -- Use RenderStepped to spin the Saw model
     RunService.RenderStepped:Connect(function(deltaTime)
         local primaryPart = sawModel.PrimaryPart
 
         -- Rotate the entire model around its PrimaryPart
         sawModel:SetPrimaryPartCFrame(primaryPart.CFrame * CFrame.fromEulerAnglesXYZ(0, 0, rotationSpeed))
     end)
end

function SawBladeSpinnerController:KnitStart()
   
end

function SawBladeSpinnerController:KnitInit()
    -- Add controller initialization logic here
end

return SawBladeSpinnerController
