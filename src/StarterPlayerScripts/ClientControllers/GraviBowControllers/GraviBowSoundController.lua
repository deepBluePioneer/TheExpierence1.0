local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Trove = require(Packages.Trove)

local ROLLOFF_MAX = 150
local ROLLOFF_MIN = 10

local GraviBowSoundController = Knit.CreateController({
	Name = "GraviBowSoundController",
	_trove = nil,
	_groups = {},
	_ambienceSound = nil,
})

function GraviBowSoundController:KnitInit()
	self._trove = Trove.new()
end

function GraviBowSoundController:KnitStart()
	local groupNames = {
		"ArrowFlyby",
		"ArrowImpctGround",
		"ArrowImpactPlayer",
		"ArrowRelease",
		"Ambience",
		"StringPullBack",
	}

	for _, name in ipairs(groupNames) do
		local folder = SoundService:FindFirstChild(name)
		if folder then
			self._groups[name] = folder
		else
			warn("[GraviBowSoundController] Missing sound group: " .. name)
		end
	end

	self:_startAmbience()

end

function GraviBowSoundController:_getRandomSound(groupName)
	local folder = self._groups[groupName]
	if not folder then return nil end

	local sounds = folder:GetChildren()
	if #sounds == 0 then return nil end

	return sounds[math.random(1, #sounds)]
end

function GraviBowSoundController:PlayAtPosition(groupName, position)
	local template = self:_getRandomSound(groupName)
	if not template then return nil end

	local part = Instance.new("Part")
	part.Name = "SoundEmitter"
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Position = position
	part.Parent = Workspace

	local sound = template:Clone()
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = ROLLOFF_MIN
	sound.RollOffMaxDistance = ROLLOFF_MAX
	sound.Looped = false
	sound.Parent = part

	sound:Play()

	sound.Ended:Once(function()
		part:Destroy()
	end)

	return sound, part
end

function GraviBowSoundController:PlayOnPart(groupName, targetPart)
	local template = self:_getRandomSound(groupName)
	if not template then return nil end

	local sound = template:Clone()
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = ROLLOFF_MIN
	sound.RollOffMaxDistance = ROLLOFF_MAX
	sound.Looped = false
	sound.Parent = targetPart

	sound:Play()

	sound.Ended:Once(function()
		sound:Destroy()
	end)

	return sound
end

function GraviBowSoundController:PlayGlobal(groupName)
	local template = self:_getRandomSound(groupName)
	if not template then return nil end

	local sound = template:Clone()
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 0
	sound.RollOffMaxDistance = 0
	sound.Looped = false
	sound.Parent = SoundService

	sound:Play()

	sound.Ended:Once(function()
		sound:Destroy()
	end)

	return sound
end

function GraviBowSoundController:PlayLoopOnPart(groupName, targetPart)
	local template = self:_getRandomSound(groupName)
	if not template then return nil end

	local sound = template:Clone()
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = ROLLOFF_MIN
	sound.RollOffMaxDistance = ROLLOFF_MAX
	sound.Looped = true
	sound.Parent = targetPart

	sound:Play()

	return sound
end

function GraviBowSoundController:_startAmbience()
	local template = self:_getRandomSound("Ambience")
	if not template then return end

	local sound = template:Clone()
	sound.Looped = true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 0
	sound.RollOffMaxDistance = 0
	sound.Parent = SoundService

	sound:Play()

	self._trove:Add(sound)
	self._ambienceSound = sound
end

return GraviBowSoundController
