local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))
local CollectionService = game:GetService("CollectionService")

local ProtostarTimings = require(script.Parent.Protostar)
local ProtostartID = 7028518546

local MidiControllerService = Knit.CreateService {
    Name = "MidiControllerService",
    Client = {},
}

-- Define the colors to alternate between
local colors = {BrickColor.new("Bright red"), BrickColor.new("Bright green"), BrickColor.new("Bright blue"), BrickColor.new("Bright yellow")}



function MidiControllerService:PlayTimings()
    local timings = ProtostarTimings["Protostar"]
    local currentTime = tick()
    local colorIndex = 1

    for _, timing in ipairs(timings) do
        local waitTime = (timing / 1000) - (tick() - currentTime)
        if waitTime > 0 then
            task.defer(function()
                task.wait(waitTime)
                -- Get all parts tagged with "musicElement"
                local musicElements = CollectionService:GetTagged("musicElement")
        
                -- Perform some action on each music element
                for _, element in ipairs(musicElements) do
                    -- Set the element's color to the current color in the cycle
                    element.BrickColor = colors[colorIndex]
                end
        
                -- Update the color index to cycle through the colors
                colorIndex = colorIndex % #colors + 1
            end)
        end
    end
end

function MidiControllerService:PlaySound()
    -- Create and play the sound
    local sound = Instance.new("Sound", SoundService)
    sound.SoundId = "rbxassetid://" .. ProtostartID
    sound.Name = "ProtostarSound"
    
    sound.Volume = 1  -- Adjust volume
    sound.Looped = false  -- Set to true if you want the sound to loop

    -- Play the sound
  --  sound:Play()


end



function MidiControllerService:KnitStart()
    -- Use coroutines to run PlaySound and PlayTimings in parallel
   -- spawn(function()
       -- self:PlaySound()
   -- end)
    
   -- spawn(function()
     --   self:PlayTimings()
   -- end)
end

function MidiControllerService:KnitInit()
    -- Add service initialization logic here
end

return MidiControllerService
