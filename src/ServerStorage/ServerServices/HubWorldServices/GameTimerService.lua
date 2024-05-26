local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Timer = require(Packages.timer)
local Signal = require(Packages.Signal)



local GameTimerService = Knit.CreateService {
    Name = "GameTimerService",
    Client = {},
    TimeUpSignal = Signal.new()

}


-- Function to handle what happens on each tick
local function onTick(timer, counter, totalDuration, timeUpSignal)
    local remainingTime = totalDuration - counter.value
    print("Time remaining: " .. remainingTime .. " seconds")
    counter.value = counter.value + 1
    if counter.value >= totalDuration then
        timer:Stop()
        print("Timer stopped after 10 seconds.")
        timeUpSignal:Fire()
    end
end

function init()

     -- Create a timer instance with a duration of 1 second
     local timer = Timer.new(1)
    
     -- Create a counter to track the number of ticks
     local counter = { value = 0 }
     
     -- Set the total duration for the timer
     local totalDuration = 10
     
     -- Create a signal to be fired when the timer stops
     
     -- Connect the Tick event to the onTick function with the timer, counter, total duration, and signal
     timer.Tick:Connect(function()
         onTick(timer, counter, totalDuration, self.TimeUpSignal)
     end)
     
     -- Start the timer
     timer:Start()
    
end

function GameTimerService:KnitStart()
   
end

function GameTimerService:KnitInit()
    -- Add service initialization logic here
end

-- Expose the TimeUpSignal for other services
function GameTimerService:GetTimeUpSignal()
    return self.TimeUpSignal
end

return GameTimerService
