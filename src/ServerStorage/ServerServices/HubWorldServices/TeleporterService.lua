local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages

-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

-- TeleportQueue Modules
local TeleportQueueFolder = CustomPackages.TeleportQueue
local TeleportQueueService = require(TeleportQueueFolder.TeleportQueueService)

 ----- Replica Modules -----
 local Replica = CustomPackages.Replica
 local ReplicaService = require(Replica.ReplicaService)
 local TestWriteLib = Replica.TestWriteLib

 local Timer = require(Packages.timer)

local DungeonPlaceID = 17282492093  -- Corrected to be a number

local TeleporterService = Knit.CreateService {
    Name = "TeleporterService",
    Client = {},
    teleporters = {}
}

function TeleporterService:InitReplicas()
    local InstantiatedClassToken = ReplicaService.NewClassToken("InstantiatedReplica")
    local InstantiatedReplicas = {} 
  -- Assume TestReplicaOne is a list of messages we want to broadcast
    local TestReplicaOne = ReplicaService.NewReplica({
    ClassToken = ReplicaService.NewClassToken("ReplicaOne"), -- Create the token in reference for singleton replicas
    Data = {
        Messages = {}, -- {[message_name] = text, ...}
    },
    Replication = "All",
    -- Be aware that if you accidentally pass nil, the replica will be created without a WriteLib
    WriteLib = TestWriteLib,
    })


    for i = 1, 3 do
        local replica = ReplicaService.NewReplica({
            ClassToken = InstantiatedClassToken,
            -- Optional params:
            Tags = {Index = i}, -- "Tags" is a static table that can't be changed during the lifespan of a replica;
            -- Use tags for identifying replicas with players (Tags = {Player = player}) or other parameters
            Data = {
                TestValue = 0,
                TestTable = {
                    NestedValue = "-",
                },
            },
            Parent = TestReplicaOne,
        })
        InstantiatedReplicas[i] = replica
    end
   
    -- Create a variable to hold the TestValue
    local random_replica
    -- Function to update the value in the replica
    local function updateReplicaValue()
        --random_replica = InstantiatedReplicas[1]  -- Assuming this is correctly populated and available
        --random_replica:SetValue({"TestValue"}, zoneCounter)
    end
end

function TeleporterService:KnitInit()

  -- Initialize replicas
    self:InitReplicas()

    local teleporterObjects = CollectionService:GetTagged("teleporter")

     -- Iterate through the list of teleporter objects
    for _, teleporter in ipairs(teleporterObjects) do
        local teleportZone = teleporter:FindFirstChild("TeleportZone")
        if teleportZone then
            print(teleporter.Name .. " has a TeleportZone")
            
          
           -- Create a unique teleport queue for each teleporter
            local teleportQueue = TeleportQueueService.new({
                PlaceId = DungeonPlaceID,
                Id = game:GetService("HttpService"):GenerateGUID(), -- Unique identifier for the queue
                MaxPlayers = 3, -- Optional maximum players that can be in the queue at once
            })

            -- Create and store a zone for each teleporter along with its teleport queue
            local zone = Zone.new(teleportZone)
          
            self.teleporters[teleporter] = {
                zone = zone,
                queue = teleportQueue,
                zoneCounter = 0 , -- Initialize the zoneCounter for this teleporter
                timer = nil,  -- Timer not started yet
                currentTime = 16
            }
            zone.playerEntered:Connect(function(player)
                self:HandlePlayerEntered(teleporter, player)
            end)
            
            zone.playerExited:Connect(function(player)
               self:HandlePlayerExited(teleporter, player)
                
             
            end)
        else
            print(teleporter.Name .. " does not have a TeleportZone")
        end
    end
    

end

function TeleporterService:HandlePlayerEntered(teleporter, player)
    local result = self.teleporters[teleporter].queue:Add(player)
    self:HandleQueueResult(teleporter, player, result)
end

function TeleporterService:HandleQueueResult(teleporter, player, result)
    local teleportData = self.teleporters[teleporter]
    local teleporterName = teleporter.Name
    teleportData.zoneCounter = teleportData.zoneCounter + 1

    if result == "Successfully added" then
      
        print("Player " .. player.Name .. " successfully added to the queue of " .. teleporterName.." : ".. teleportData.zoneCounter)

        self:startTimer(teleporter)

    else
        self:handleUnsuccessfulAdd(result, player, teleporterName)
    end
end

function TeleporterService:handleUnsuccessfulAdd(result, player, teleporterName)
    if result == "TeleportQueue is full" then
        warn(teleporterName .. " queue is full. Player " .. player.Name .. " could not be added.")
    end
end

function TeleporterService:HandlePlayerExited(teleporter, player)
    local teleportData = self.teleporters[teleporter]
    teleportData.queue:Remove(player)
    teleportData.zoneCounter = teleportData.zoneCounter - 1

    print(player.Name .. " has exited the zone of " .. teleporter.Name.." : "..teleportData.zoneCounter)

  -- Check if zoneCounter is zero or negative
    if teleportData.zoneCounter <= 0 then
        if teleportData.zoneCounter == 0 then
            teleportData.currentTime = 16  -- Starting countdown time
        end
        teleportData.zoneCounter = 0  -- Ensure zoneCounter does not go negative
    end

   
end

function TeleporterService:startTimer(teleporter)
    local teleportData = self.teleporters[teleporter]
    if not teleportData.timer then
        self:setupNewTimer(teleportData, teleporter)
    end
    if not teleportData.timer:IsRunning() and teleportData.zoneCounter > 0 then
        teleportData.timer:Start()
    end
end

function TeleporterService:setupNewTimer(teleportData, teleporter)
    teleportData.timer = Timer.new(1) -- 1 second interval
    teleportData.currentTime = 16  -- Starting countdown time

    teleportData.timer.Tick:Connect(function()
        self:timerTick(teleportData, teleporter)
    end)
end

function TeleporterService:timerTick(teleportData, teleporter)
    if teleportData.zoneCounter > 0 then

        teleportData.currentTime = teleportData.currentTime - 1
        print(teleporter.Name .. " Timer: " .. teleportData.currentTime .. " seconds remaining")

        if teleportData.currentTime <= 0 then
            self:executeTeleport(teleportData, teleporter)
        end
       
    end
end

function TeleporterService:Teleport(teleportQueue)
    local flushResult, teleportResult = teleportQueue:Flush()
    if flushResult == TeleportQueueService.FlushResult.Success then
        print("Here's the TeleportAsyncResult:", teleportResult)
    end
end

function TeleporterService:executeTeleport(teleportData, teleporter)
    if not RunService:IsStudio() then
        warn("Teleporting...")
        TeleporterService:Teleport(teleportData.queue)
    else
        warn("Skipping teleportation because we are in Roblox Studio.")
    end
    teleportData.timer:Stop()
    teleportData.currentTime = 16  -- Reset countdown time
end

function TeleporterService:KnitStart()
  
  
      
    
    
end

return TeleporterService
