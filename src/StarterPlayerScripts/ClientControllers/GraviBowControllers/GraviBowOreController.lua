local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage.Packages
local CustomPackages = ReplicatedStorage:WaitForChild("CustomPackages")
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)
local ReplicaController = require(CustomPackages.Replica.ReplicaController)

local LocalPlayer = Players.LocalPlayer

local ORE_COLOR = Color3.fromRGB(255, 200, 50)
local BG_COLOR = Color3.fromRGB(15, 15, 25)
local TEXT_COLOR = Color3.fromRGB(240, 240, 255)
local BUMP_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local GraviBowOreController = Knit.CreateController({
	Name = "GraviBowOreController",
	_trove = nil,
	_oreLabel = nil,
	_iconLabel = nil,
	_container = nil,
	_lastOre = 0,
})

function GraviBowOreController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowOreController:KnitStart()
	self:_createUI()

	ReplicaController.ReplicaOfClassCreated("GraviBowOreState", function(replica)
		self._replica = replica
		self:_updateFromData(replica.Data)

		replica:ListenToRaw(function()
			self:_updateFromData(replica.Data)
		end)
	end)
end

function GraviBowOreController:_updateFromData(data)
	local ore = data.ore or 0

	if ore ~= self._lastOre then
		self._lastOre = ore
		self:_setOreDisplay(ore)
		if ore > 0 then
			self:_bump()
		end
	end
end

function GraviBowOreController:_setOreDisplay(amount)
	if self._oreLabel then
		self._oreLabel.Text = tostring(amount)
	end
end

function GraviBowOreController:_bump()
	if not self._container then return end
	self._container.Size = UDim2.fromOffset(160, 44)
	TweenService:Create(self._container, BUMP_INFO, {
		Size = UDim2.fromOffset(148, 40),
	}):Play()
end

function GraviBowOreController:_createUI()
end

return GraviBowOreController
