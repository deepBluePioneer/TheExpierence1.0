local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)

local PacManDataService = Knit.CreateService({
	Name = "PacManDataService",
	Client = {},

	_trove = nil,

	DataLoaded = Signal.new(),
})

function PacManDataService:KnitInit()
	self._trove = Trove.new()
end

function PacManDataService:KnitStart()
	print("[PacManDataService] Started")
end

return PacManDataService
