local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local GraviBowRingController = Knit.CreateController({
	Name = "GraviBowRingController",
	_trove = nil,
})

function GraviBowRingController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowRingController:KnitStart()
	-- Ring particle visuals removed.
end

return GraviBowRingController
