local PlayersService = game:GetService("Players")

local function ApplyFunctionToAll(Function)
	for _,Player in pairs(PlayersService:GetPlayers()) do
		coroutine.wrap(Function)(Player)
		-- If the function has a yield, we don't want every player to have to wait in line for their function call. coroutine.wrap fixes this.
	end
end

return function(PlayerAddedFunction, PlayerRemovingFunction, CharacterAddedFunction)
	-- PlayerAddedFunction = function that we want to run on all joining or existing players
		-- function(Player)
	-- PlayerRemovingFunction = function that want to run on all leaving players
		-- function(Player)
	-- CharacterAddedFunction = function we want to run on all spawning or existing characters
		-- function(Player, Character)

	local AddConnection, RemoveConnection, CharacterConnections
	-- We also want to return 3 things (even though they will likely never need to be used)
		-- 1. RBXScriptConnection
			-- For the PlayerAdded event
		-- 2. RBXScriptConnection
			-- For the PlayerRemoving event/game::BindToClose function
		-- 3. Table of RBXScriptConnections
			-- For each player's CharacterAdded event
			--[[
			{
				[game.Players.GFink] = game.Players.GFink.CharacterAdded:Connect(etc)
				[game.Players.tyzone] = game.Players.tyzone.CharacterAdded:Connect(etc)
			}
			]]

	if PlayerAddedFunction then
		AddConnection = PlayersService.PlayerAdded:Connect(PlayerAddedFunction) -- Joining players
		ApplyFunctionToAll(PlayerAddedFunction) -- Existing players
	end
	
	if PlayerRemovingFunction then
		local Left = {}
		-- The "Left" table represents the table of Player instances who have already left.
		-- This is to make sure that only a single instance of the PlayerRemovingFunction is run, rather than being run by both the PlayerRemoving event and the game::BindToClose function
		local function RunCheck(Player)
			--[[
				We check if this player's PlayerRemovingFunction has already been run by either PlayerRemoving or ApplyFunctionToAll.
				Again, this prevents the PlayerRemovingFunction from being run twice when the last player leaves, or if the server crashes.
				Note that before making this checker function, I never actually ran into this issue while testing using data stores
				(can't test with basic print statements because the output cannot be read while the game is being closed). It's just here 
				to make absolute sure the issue never pops up, and it would also annoy me if it wasn't here. ]]
			if not Left[Player] then -- We use the player's instance rather than their UserId so rejoining doesn't break things
				Left[Player] = true
				PlayerRemovingFunction(Player)
			end
		end
		RemoveConnection = PlayersService.PlayerRemoving:Connect(RunCheck)
		if game:GetService("RunService"):IsServer() then -- If you're requiring the module from the ID, this will never be false.
			-- The module could technically have been required by the client if the module itself was reparented somehow(?)
			-- Hopefully Roblox adds this functionality somehow. See the forum post I made about NOT being able to do this: https://devforum.roblox.com/t/note-to-myself/835748
			game:BindToClose(
				function()
					if RemoveConnection.Connected == true then 
						-- Can't "UnbindFromClose", so this is the next-best thing
						-- Why would anyone disconnect that connection on the server anyway? 
						-- Again, it would just annoy me if this wasn't here.
						ApplyFunctionToAll(RunCheck)
					end
				end
			)
		end
	end
	
	if CharacterAddedFunction then 
		--[[ 
			Optional third argument per a friend's request. Personally I don't have a use for it because I'm either yielding for 
			information gathered from within the PlayerAddedFunction, or I'm using the CharacterAppearanceLoaded listener instead. ]]
		CharacterConnections = {}
		local function DefaultPlayerAdded(Player)
			CharacterConnections[Player] = Player.CharacterAdded:Connect(
				function(Character)
					CharacterAddedFunction(Player, Character)
				end
			)
			-- Don't have to worry about disconnecting prior connections that may exist at this Player index from prior joins to the same server, because
				-- 1. Previous player instances are completely separate instances from new player instances, even if it's the same user, so it would not occupy the same index anyway.
					-- Using something like Player.UserId or Player.Name would be a different story.
				-- 2. Connections to players who have left are automatically disconnected anyway since the player instance gets destroyed automatically when the user leaves.
					-- RBXScriptConnections are disconnected when the instance it's listening on is destroyed
			local ExistingCharacter = Player.Character
			if ExistingCharacter then -- Only run the CharacterAddedFunction on the existing character IF that character exists
				CharacterAddedFunction(Player, ExistingCharacter)
			end
		end
		PlayersService.PlayerAdded:Connect(DefaultPlayerAdded)
		ApplyFunctionToAll(DefaultPlayerAdded)
	end
	return AddConnection, RemoveConnection, CharacterConnections
	-- If you decide to disconnect all CharacterConnections, this still leaves the door open for players who haven't joined yet to have active CharacterAdded connections.
	-- To solve this, consider a bool value "ListenForCharacterAdded" you make false when you intend to disconnect all CharacterAdded functions. Using this module, you would write your code like this:
	--[[
		local CharacterConnections
		
		function OnCharacterAdded(Player, Character)
			if ListenForCharacterAdded == false then
				return CharacterConnections[Player]:Disconnect()
				-- Ends the OnCharacterAdded function right here while also disconnecting the CharacterAdded connection from running it in the future
			end
			-- Here would be all your code that usually runs when a character is added
		end
		
		_, _, CharacterConnections = require(ThisModule)(
			nil, -- PlayerAddedFunction
			nil, -- PlayerRemovingFunction
			OnCharacterAdded
		)
	]]
	-- Again I'm not really sure what the use of this would be, but it's there nonetheless.
end