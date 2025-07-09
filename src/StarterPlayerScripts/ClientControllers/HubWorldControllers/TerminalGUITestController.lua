local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)

local TerminalGUITestController = Knit.CreateController { Name = "TerminalGUITestController" }

local Packages = ReplicatedStorage.Packages
local Keyboard = require(Packages.Input).Keyboard


local function init()
    -- Create a new instance of Keyboard to capture keyboard inputs
    local keyboard = Keyboard.new()
        -- Connect to the KeyDown event to check when any key is pressed
    keyboard.KeyDown:Connect(function(key)
        -- Check if the key pressed is the Enter key
        if key == Enum.KeyCode.Return then
            print("Enter key was pressed")
        end
    end)
    local Iris = Knit.GetController("irisInitController"):GetIris()

    -- Assuming you have a specific section in your TemplateConfig for terminal aesthetics
    local terminalConfig = {
        TextColor = Color3.fromRGB(75, 255, 55), -- Green text
        BackgroundColor = Color3.fromRGB(48, 10, 36), -- Black background
        TextSize = 25, -- Slightly larger text for better readability
        BorderColor = Color3.fromRGB(58, 58, 58), -- Dark gray border
        BorderTransparency = 1,
        WindowBgTransparency = 1,
        TitleBgActiveColor = Color3.fromRGB(255, 0, 0), -- Darker shade for title background -inactive window
        FrameBgColor =  Color3.fromRGB(48, 10, 36), -- Black background
    }

    Iris:Connect(function()
        local windowSize = Iris.State(Vector2.new(500, 500))

        --warn(windowSize)
        -- Define a variable to store user input
        local userInput = Iris.State("")  -- Initialize with empty string
        -- Temporarily apply specific settings
        local originalColors = {
            BgColor = Iris._config.WindowBgColor,
            TextColor = Iris._config.TextColor,
            BorderColor = Iris._config.BorderColor,
            TextSize = Iris._config.TextSize,
            TitleBgActiveColor = Iris._config.TitleBgActiveColor,  -- Ensure this property exists
        }
    
        -- Apply new settings for a terminal-like appearance
        Iris._config.WindowBgColor = terminalConfig.BackgroundColor
        Iris._config.TextColor = terminalConfig.TextColor
        Iris._config.BorderColor = terminalConfig.BorderColor
        Iris._config.TextSize = terminalConfig.TextSize
        Iris._config.TitleBgActiveColor = terminalConfig.TitleBgActiveColor
        Iris._config.FrameBgColor = terminalConfig.FrameBgColor

        Iris._config.TextFont = Font.fromEnum(Enum.Font.Ubuntu)
 
          -- Get the system's username and hostname (static for this example)
       -- Then, get the local player instance
       local player = Players.LocalPlayer

       -- Set the local username variable to the player's name
       local username = player.Name
       local hostname = "linux-roblox:~$"
      
        Iris.Window({"Terminal"}, {size = windowSize})

        Iris.InputText({username .. "@".. hostname, "Input"})
    
    
        Iris:End()  -- End the first window
    
        -- Restore original settings
        Iris._config.WindowBgColor = originalColors.BgColor
        Iris._config.TextColor = originalColors.TextColor
        Iris._config.BorderColor = originalColors.BorderColor
        Iris._config.TextSize = originalColors.TextSize
        Iris._config.TitleBgActiveColor = originalColors.TitleBgActiveColor
     
    end)
end

function TerminalGUITestController:KnitInit()


end
function TerminalGUITestController:KnitStart()

    
    
    
    
end






return TerminalGUITestController
