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

local initLobbyTime = 10
local initGameCountdownTime = 5
local initReturnTime = 60  -- Duration before returning players

local TeleporterService = Knit.CreateService {
    Name = "TeleporterService",
    Client = {},
    teleporters = {},
    OnLobbyTimerEnd = Signal.new(),
    OnGameTimerEnd = Signal.new(),
    OnReturnTimerEnd = Signal.new()
}

function TeleporterService:InitReplicas()
    self.TimerReplica = ReplicaService.NewReplica({
        ClassToken = ReplicaService.NewClassToken("TimerReplica"),
        Data = {
            TimeRemaining = initLobbyTime,
            GameTimeRemaining = initGameCountdownTime,  -- Example game countdown duration
            ReturnTimeRemaining = initReturnTime,      -- Example return countdown duration
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
                currentTime = initLobbyTime,
                currentGameTime = initGameCountdownTime, -- Example game countdown duration
                currentReturnTime = initReturnTime,      -- Example return countdown duration
                originalPositions = {},                  -- Store original positions of players
                gameInSession = false,                   -- Track if a game is in session
                waitingPlayers = {}                      -- List of players who enter during a game
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
    local teleportData = self.teleporters[teleporter]
    if teleportData.gameInSession then
        print("Game in session, player " .. player.Name .. " added to waiting list.")
        table.insert(teleportData.waitingPlayers, player)
    else
        local result = teleportData.queue:Add(player)
        self:HandleQueueResult(teleporter, player, result)
    end
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
            teleportData.currentTime = initLobbyTime  -- Starting countdown time
        end
        teleportData.zoneCounter = 0  -- Ensure zoneCounter does not go negative
    end
end

function TeleporterService:startTimer(teleporter)
    local teleportData = self.teleporters[teleporter]
    if teleportData.gameInSession then
        print("Game in session, lobby timer will not start.")
        return
    end
    
    if not teleportData.timer then
        self:setupNewTimer(teleportData, teleporter)
    end
    if not teleportData.timer:IsRunning() and teleportData.zoneCounter > 0 then
        teleportData.timer:Start()
    end
end

function TeleporterService:setupNewTimer(teleportData, teleporter)
    teleportData.timer = Timer.new(1) -- 1 second interval
    teleportData.currentTime = initLobbyTime  -- Starting countdown time

    teleportData.timer.Tick:Connect(function()
        self:timerTick(teleportData, teleporter)
    end)
end

function TeleporterService:timerTick(teleportData, teleporter)
    if teleportData.zoneCounter > 0 then
        teleportData.currentTime = teleportData.currentTime - 1
       -- print(teleporter.Name .. " Timer: " .. teleportData.currentTime .. " seconds remaining")

        -- Update the TimeRemaining in the replica
        self.TimerReplica:SetValue({"TimeRemaining"}, teleportData.currentTime)

        if teleportData.currentTime <= 0 then
            self.OnLobbyTimerEnd:Fire()
            self:executeTeleport(teleportData, teleporter)
        end
    end
end

function TeleporterService:startGameTimer(teleportData, teleporter)
    if not teleportData.gameTimer then
        self:setupNewGameTimer(teleportData, teleporter)
    end
    if not teleportData.gameTimer:IsRunning() then
        teleportData.gameTimer:Start()
    end
end

function TeleporterService:setupNewGameTimer(teleportData, teleporter)
    teleportData.gameTimer = Timer.new(1) -- 1 second interval
    teleportData.currentGameTime = initGameCountdownTime  -- Starting game countdown time

    teleportData.gameTimer.Tick:Connect(function()
        self:timerGameTick(teleportData, teleporter)
    end)
end

function TeleporterService:timerGameTick(teleportData, teleporter)
    teleportData.currentGameTime = teleportData.currentGameTime - 1
  --  print(teleporter.Name .. " Timer: " .. teleportData.currentGameTime .. " seconds remaining")

    -- Update the GameTimeRemaining in the replica
    self.TimerReplica:SetValue({"GameTimeRemaining"}, teleportData.currentGameTime)

    if teleportData.currentGameTime <= 0 then
        self.OnGameTimerEnd:Fire()
        teleportData.gameTimer:Stop()  -- Stop the game timer
        teleportData.currentGameTime = initGameCountdownTime  -- Reset game countdown time

        -- Start the return timer
        self:startReturnTimer(teleportData, teleporter)
    end
end

function TeleporterService:startReturnTimer(teleportData, teleporter)
    if not teleportData.returnTimer then
        self:setupNewReturnTimer(teleportData, teleporter)
    end
    if not teleportData.returnTimer:IsRunning() then
        teleportData.returnTimer:Start()
    end
end

local function formatTime(totalMilliseconds)
    local totalSeconds = math.floor(totalMilliseconds / 1000)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    local milliseconds = totalMilliseconds % 1000
    return string.format("%02d:%02d.%02d", minutes, seconds, milliseconds)
end


function TeleporterService:setupNewReturnTimer(teleportData, teleporter)
    teleportData.returnTimer = Timer.new(0.01) -- 100 millisecond interval
    teleportData.currentReturnTime = initReturnTime * 1000  -- Starting return countdown time in milliseconds

    teleportData.returnTimer.Tick:Connect(function()
        self:timerReturnTick(teleportData, teleporter)
    end)
end

function TeleporterService:timerReturnTick(teleportData, teleporter)
    teleportData.currentReturnTime = teleportData.currentReturnTime - 10

    -- Format the time and update the ReturnTimeRemaining in the replica
    local formattedTime = formatTime(teleportData.currentReturnTime)
    self.TimerReplica:SetValue({"ReturnTimeRemaining"}, formattedTime)

    if teleportData.currentReturnTime <= 0 then
        self.OnReturnTimerEnd:Fire()
        teleportData.returnTimer:Stop()  -- Stop the return timer
        teleportData.currentReturnTime = initReturnTime * 1000  -- Reset return countdown time

        -- Teleport players back to their original locations
        self:returnPlayersToOriginalLocations(teleporter)

        -- Process waiting players
        self:processWaitingPlayers(teleporter)
    end
end

function TeleporterService:returnPlayersToOriginalLocations(teleporter)
    local teleportData = self.teleporters[teleporter]
    for player, originalPosition in pairs(teleportData.originalPositions) do
        if player.Character then
            player.Character:PivotTo(originalPosition)
        end
    end
    teleportData.gameInSession = false -- Mark the game as not in session
end

function TeleporterService:processWaitingPlayers(teleporter)
    local teleportData = self.teleporters[teleporter]
    for _, player in ipairs(teleportData.waitingPlayers) do
        local result = teleportData.queue:Add(player)
        self:HandleQueueResult(teleporter, player, result)
    end
    teleportData.waitingPlayers = {}  -- Clear the waiting players list
end

function TeleporterService:TeleportToPlace(teleportQueue, teleportData)
    local flushResult, teleportResult = teleportQueue:Flush()
    if flushResult == TeleportQueueService.FlushResult.Success then
        print("Here's the TeleportAsyncResult:", teleportResult)
        
    end
end

function TeleporterService:Teleport(teleportQueue, spawnLocations, teleportData)
    local players = teleportQueue:GetPlayers() -- Get players in the queue

    -- Store the original positions of the players
    for _, player in ipairs(players) do
        if player.Character then
            teleportData.originalPositions[player] = player.Character:GetPivot()
        end
    end

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
        self:Teleport(teleportData.queue, spawnLocations, teleportData)
    else
        local spawnLocations = CollectionService:GetTagged("spawnLoc")
        self:Teleport(teleportData.queue, spawnLocations, teleportData)
        warn("Skipping teleportation because we are in Roblox Studio.")
    end

    teleportData.timer:Stop()
    teleportData.currentTime = initLobbyTime  -- Reset countdown time

    -- Start the game timer after teleportation
    teleportData.gameInSession = true -- Mark the game as in session
    self:startGameTimer(teleportData, teleporter)
end

function TeleporterService:KnitStart()
    -- Expose the TimeUpSignal for other services
    function TeleporterService:GetTimeUpSignal()
        return self.OnLobbyTimerEnd
    end

    function TeleporterService:GetOnGameTimerEnd()
        return self.OnGameTimerEnd
    end

    function TeleporterService:GetOnReturnTimerEnd()
        return self.OnReturnTimerEnd
    end
end

return TeleporterService
