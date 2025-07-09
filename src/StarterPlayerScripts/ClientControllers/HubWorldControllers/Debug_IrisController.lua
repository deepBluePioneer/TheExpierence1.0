local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)

local Debug_IrisController = Knit.CreateController { Name = "Debug_IrisController" }

local function init()
	local irisInitController = Knit.GetController("irisInitController")
	local Iris = irisInitController:GetIris()

	Iris.UpdateGlobalConfig(Iris.TemplateConfig.colorDark)
	Iris.UpdateGlobalConfig(Iris.TemplateConfig.sizeClear)

	local machineProfiles = {
		{ name = "Warp Star",    stats = { TopSpeed = 62.3, Acceleration = 81.4, Handling = 75.2, Weight = 53.1, Boost = 67.0 } },
		{ name = "Shadow Star",  stats = { TopSpeed = 73.2, Acceleration = 70.0, Handling = 66.6, Weight = 44.8, Boost = 58.5 } },
		{ name = "Formula Star", stats = { TopSpeed = 100.0, Acceleration = 32.0, Handling = 51.0, Weight = 62.4, Boost = 74.2 } },
		{ name = "Winged Star",  stats = { TopSpeed = 56.6, Acceleration = 68.9, Handling = 90.0, Weight = 33.5, Boost = 47.7 } },
		{ name = "Rocket Star",  stats = { TopSpeed = 80.0, Acceleration = 45.2, Handling = 63.3, Weight = 59.0, Boost = 82.4 } },
		{ name = "Bulk Star",    stats = { TopSpeed = 42.1, Acceleration = 21.0, Handling = 35.4, Weight = 100.0, Boost = 49.0 } },
		{ name = "Slick Star",   stats = { TopSpeed = 64.0, Acceleration = 54.0, Handling = 80.0, Weight = 40.0, Boost = 60.0 } },
		{ name = "Turbo Star",   stats = { TopSpeed = 85.0, Acceleration = 60.0, Handling = 70.0, Weight = 55.0, Boost = 90.0 } },
		{ name = "Jet Star",     stats = { TopSpeed = 90.0, Acceleration = 70.0, Handling = 68.0, Weight = 45.0, Boost = 95.0 } },
		{ name = "Wagon Star",   stats = { TopSpeed = 30.0, Acceleration = 20.0, Handling = 20.0, Weight = 90.0, Boost = 20.0 } },
		{ name = "Swerve Star",  stats = { TopSpeed = 60.0, Acceleration = 80.0, Handling = 100.0, Weight = 25.0, Boost = 50.0 } },
		{ name = "Wheelie Bike", stats = { TopSpeed = 75.0, Acceleration = 85.0, Handling = 90.0, Weight = 30.0, Boost = 70.0 } },
	}

	local machinesFolder = ReplicatedStorage:FindFirstChild("Machines") or Instance.new("Folder")
	machinesFolder.Name = "Machines"
	machinesFolder.Parent = ReplicatedStorage

	-- Initialize stat folders + values
	for _, profile in ipairs(machineProfiles) do
		local folder = machinesFolder:FindFirstChild(profile.name) or Instance.new("Folder")
		folder.Name = profile.name
		folder.Parent = machinesFolder

		for statName, defaultValue in pairs(profile.stats) do
			local stat = folder:FindFirstChild(statName) or Instance.new("NumberValue")
			stat.Name = statName
			if stat.Value == 0 then
				stat.Value = defaultValue
			end
			stat.Parent = folder
		end
	end

	local machineNames = {}
	for _, profile in ipairs(machineProfiles) do
		table.insert(machineNames, profile.name)
	end

	local selectedMachine = Iris.State(machineNames[1])
	local cachedStates = {}

	local function getOrCreateStatStates(machineName)
		if cachedStates[machineName] then
			return cachedStates[machineName]
		end

		local folder = machinesFolder:FindFirstChild(machineName)
		local stateMap = {}

		for _, stat in ipairs(folder:GetChildren()) do
			local state = Iris.State(stat.Value)

			-- Bind slider → stat
			state:onChange(function(newVal)
				if stat.Value ~= newVal then
					stat.Value = newVal
				end
			end)

			-- Bind stat → slider
			stat:GetPropertyChangedSignal("Value"):Connect(function()
				local val = stat.Value
				if state:get() ~= val then
					state:set(val)
				end
			end)

			stateMap[stat.Name] = state
		end

		cachedStates[machineName] = stateMap
		return stateMap
	end

	Iris:Connect(function()
		Iris.Window({ "Machine Stats Editor" }, { size = Iris.State(Vector2.new(460, 500)) })

		Iris.ComboArray({ "Select Machine" }, { index = selectedMachine }, machineNames)
		Iris.Text({ "Editing: " .. selectedMachine:get() })

		Iris.SeparatorText({ "Stats (0.00 - 100.00)" })

		local currentMachine = selectedMachine:get()
		local stateMap = getOrCreateStatStates(currentMachine)

		Iris.PushConfig({ ContentWidth = UDim.new(1, -80) })
		for statName, state in pairs(stateMap) do
			Iris.SliderNum({
				statName,
				0.1,
				0,
				100,
				"%.2f"
			}, {
				number = state
			})
		end
		Iris.PopConfig()

		Iris.End()
	end)
end

function Debug_IrisController:KnitStart()
	init()
end

function Debug_IrisController:KnitInit() end

return Debug_IrisController
