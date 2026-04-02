local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Signal = require(Packages.Signal)
local Trove = require(Packages.Trove)

local CavesDataService = Knit.CreateService({
	Name = "CavesDataService",
	Client = {},

	_trove = nil,

	DataLoaded = Signal.new(),
})

function CavesDataService:KnitInit()
	self._trove = Trove.new()
end

function CavesDataService:KnitStart()
	print("[CavesDataService] Started")
end

return CavesDataService
