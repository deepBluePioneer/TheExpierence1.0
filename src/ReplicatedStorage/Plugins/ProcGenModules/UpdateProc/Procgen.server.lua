
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local toolbar = plugin:CreateToolbar("Room Tools V2")
local generateRoomButton = toolbar:CreateButton("Generate Room V2", "Generate a room structure", "rbxassetid://1234567890")

generateRoomButton.ClickableWhenViewportHidden = true

local Source = ReplicatedStorage.Source
local Plugins = Source.Plugins
local ProcGenModules = Plugins.ProcGenModules

local RoomModule = require(ProcGenModules.UpdateProc.RoomModule)

local function onGenerateRoomButtonClicked()
	ChangeHistoryService:SetWaypoint("Before Generating Room Grid")


     -- Define variables for each parameter
      local roomName = "Conference Room"
      local roomSize = Vector3.new(30, 12, 30)  -- Dimensions: width, height, depth
      local roomColor = Color3.fromRGB(200, 160, 120)  -- A pleasant pastel brown


      -- Create a new room using the defined variables
      local myRoom = RoomModule.new(roomName, roomSize, roomColor)
      myRoom:generate()  -- Generate the physical structure of the room


	ChangeHistoryService:SetWaypoint("After Generating Room Grid")
end

generateRoomButton.Click:Connect(onGenerateRoomButtonClicked)
