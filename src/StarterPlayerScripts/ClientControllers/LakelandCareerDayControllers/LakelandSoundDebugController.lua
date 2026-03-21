local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Iris = require(Packages.iris)

local LakelandSoundDebugController = Knit.CreateController({ Name = "LakelandSoundDebugController" })

local function getAllSounds(parent)
	local sounds = {}
	for _, child in ipairs(parent:GetDescendants()) do
		if child:IsA("Sound") then
			table.insert(sounds, child)
		end
	end
	return sounds
end

local ENABLED = false

function LakelandSoundDebugController:KnitInit()
	if not ENABLED then return end
	Iris.Init()
end

function LakelandSoundDebugController:KnitStart()
	if not ENABLED then return end
	local groups = {}
	local originals = {}

	for _, child in ipairs(SoundService:GetChildren()) do
		if child:IsA("Folder") or child:IsA("SoundGroup") then
			table.insert(groups, child)
			for _, snd in ipairs(getAllSounds(child)) do
				originals[snd] = snd.Volume
			end
		end
	end

	table.sort(groups, function(a, b)
		return a.Name < b.Name
	end)

	local gameController = Knit.GetController("LakelandGameController")

	Iris:Connect(function()
		local window = Iris.Window({ "Sound Volume Mixer", [Iris.Args.Window.NoClose] = true })

		if window.state.isOpened.value and window.state.isUncollapsed.value then

			Iris.SeparatorText({ "BGM" })

			local bgmSlider = Iris.SliderNum({ "BGM Volume", 0.01, 0, 1, "%.2f" })
			if bgmSlider.numberChanged() then
				local vol = bgmSlider.state.number.value
				if gameController and gameController._bgmCurrent then
					gameController._bgmCurrent.Volume = vol
				end
			end

			Iris.Separator()
			Iris.SeparatorText({ "SFX Groups" })

			for _, group in ipairs(groups) do
				local slider = Iris.SliderNum({ group.Name, 0.01, 0, 3, "%.2f" }, { number = Iris.State(1) })

				if slider.numberChanged() then
					local multiplier = slider.state.number.value
					for _, snd in ipairs(getAllSounds(group)) do
						local orig = originals[snd]
						if orig then
							snd.Volume = orig * multiplier
						end
					end
					if group:IsA("SoundGroup") then
						group.Volume = multiplier
					end
				end
			end

			Iris.Separator()

			if Iris.Button({ "Print Current Values" }).clicked() then
				print("=== SOUND VOLUME VALUES ===")
				local bgmVol = bgmSlider.state.number.value
				print(string.format("  BGM Volume: %.2f", bgmVol))
				for _, group in ipairs(groups) do
					local sounds = getAllSounds(group)
					print(string.format("  [%s] (%d sounds):", group.Name, #sounds))
					for _, snd in ipairs(sounds) do
						print(string.format("    %s = %.3f (original: %.3f)", snd.Name, snd.Volume, originals[snd] or 0))
					end
				end
				print("===========================")
			end
		end

		Iris.End()
	end)
end

return LakelandSoundDebugController
