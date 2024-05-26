local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local CustomPackages = ReplicatedStorage.CustomPackages

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages.Knit)


-- Zone Modules
local ZoneRoot = CustomPackages.ZoneRoot
local Zone = require(ZoneRoot.Zone)

-- TeleportQueue Modules
local TeleportQueueFolder = CustomPackages.TeleportQueue
local TeleportQueueService = require(TeleportQueueFolder.TeleportQueueService)

-- Replica Modules
local Replica = CustomPackages.Replica
local ReplicaService = require(Replica.ReplicaService)
local TestWriteLib = Replica.TestWriteLib

local Signal = require(Packages.Signal)
local Timer = require(Packages.timer)

local DungeonPlaceID = 17282492093  -- Corrected to be a number

local TeleporterService = Knit.CreateService {
    Name = "TeleporterService",
    Client = {},
    teleporters = {},
    TimeUpSignal = Signal.new()
}

function TeleporterService:InitReplicas()
    self.TimerReplica = ReplicaService.NewReplica({
        ClassToken = ReplicaService.NewClassToken("TimerReplica"),
        Data = {
            TimeRemaining = 16,
        },
        Replication = "All",
        WriteLib = TestWriteLib,
    })
end

function TeleporterService:KnitInit()
    self:InitReplicas()

    local teleporterObjects = CollectionService:GetTagged("teleporter")

    -- Iterate through the list of teleporter objects
    for _, teleporter in ipairs(teleporterObjects) do
        local teleportZone = teleporter:FindFirstChild("TeleportZone")
        if teleportZone then
            -- Create a unique teleport queue for each teleporter
            local teleportQueue = TeleportQueueService.new({
                PlaceId = DungeonPlaceID,
                Id = game:GetService("HttpService"):GenerateGUID(),
                MaxPlayers = 3,
            })

            -- Create and store a zone for each teleporter along with its teleport queue
            local zone = Zone.new(teleportZone)
          
            self.teleporters[teleporter] = {
                zone = zone,
                queue = teleportQueue,
                zoneCounter = 0,
                timer = nil,
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
        print("Player " .. player.Name .. " successfully added to the queue of " .. teleporterName .. " : " .. teleportData.zoneCounter)
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

    print(player.Name .. " has exited the zone of " .. teleporter.Name .. " : " .. teleportData.zoneCounter)

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
        --print(teleporter.Name .. " Timer: " .. teleportData.currentTime .. " seconds remaining")

        -- Update the TimeRemaining in the replica
        self.TimerReplica:SetValue({"TimeRemaining"}, teleportData.currentTime)

        if teleportData.currentTime <= 0 then
            self.TimeUpSignal:Fire()
            self:executeTeleport(teleportData, teleporter)
        end
    end
end

function TeleporterService:TeleportToPlace(teleportQueue)
    local flushResult, teleportResult = teleportQueue:Flush()
    if flushResult == TeleportQueueService.FlushResult.Success then
        print("Here's the TeleportAsyncResult:", teleportResult)
    end
end

function TeleporterService:Teleport(teleportQueue, spawnLocations)
    local players = teleportQueue:GetPlayers() -- Get players in the queue

    local shuffledLocations = table.clone(spawnLocations)
    
    -- Shuffle the spawn locations to randomize
    local function shuffle(tbl)
        for i = #tbl, 2, -1 do
            local j = math.random(i)
            tbl[i], tbl[j] = tbl[j], tbl[i]
        end
    end

    shuffle(shuffledLocations)

    for i, player in ipairs(players) do
        local character = player.Character
        if character and shuffledLocations[i] then
            local spawnLocation = shuffledLocations[i]
            local primaryPart = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
            if primaryPart then
                character:PivotTo(spawnLocation.CFrame)
            else
                warn("Player " .. player.Name .. " does not have a primary part to move.")
            end
        else
            warn("Not enough spawn locations for all players or player character not found")
        end
    end
end



function TeleporterService:executeTeleport(teleportData, teleporter)
    if not RunService:IsStudio() then
        warn("Teleporting...")
        local spawnLocations = CollectionService:GetTagged("spawnLoc")

        self:Teleport(teleportData.queue, spawnLocations)

       -- TeleporterService:Teleport(teleportData.queue)
    else
        local spawnLocations = CollectionService:GetTagged("spawnLoc")

        self:Teleport(teleportData.queue, spawnLocations)

        warn("Skipping teleportation because we are in Roblox Studio.")
    end
    teleportData.timer:Stop()
    teleportData.currentTime = 16  -- Reset countdown time
end

function TeleporterService:KnitStart()
    -- Expose the TimeUpSignal for other services
    function TeleporterService:GetTimeUpSignal()
        return self.TimeUpSignal
    end
end

return TeleporterService
