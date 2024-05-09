local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CustomPackages = ReplicatedStorage.CustomPackages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local TweenService = game:GetService("TweenService")

local IntroSequenceController = Knit.CreateController { Name = "IntroSequenceController" }

local FusionRoot = CustomPackages:WaitForChild("FusionRoot")
local Fusion = require(FusionRoot:WaitForChild("Fusion"))
local New = Fusion.New
local OnEvent = Fusion.OnEvent
local Value = Fusion.Value
local Computed = Fusion.Computed

function IntroSequenceController:KnitStart()
   -- self:CreateIntroUI()
    warn("Intro UI Started")
end

function IntroSequenceController:KnitInit()
    -- Initialization logic for the controller
end

function IntroSequenceController:CreateIntroUI()
    local introText = "GlobalEx Research is a prominent multinational corporation recognized for its expertise in scientific research and innovation. Committed to enhancing human understanding and addressing worldwide challenges, the company leads a variety of initiatives in diverse fields such as environmental science, biotechnology, and renewable energy."
    local displayedText = Value("") -- Fusion state to manage displayed text

    local screenGui = New "ScreenGui" {
        Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui"),
        Name = "IntroScreenGui",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
    }

    local background = New "Frame" {
        Parent = screenGui,
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0) -- Full screen
    }

    local textLabel = New "TextLabel" {
        Parent = background,
        Size = UDim2.new(0.8, 0, 0.6, 0),
        Position = UDim2.new(0.1, 0, 0.2, 0),
        BackgroundTransparency = 1,
        Text = Computed(function()
            return displayedText:get()
        end),
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextWrapped = true,
        TextSize = 75,
        Font = Enum.Font.SourceSans,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        RichText = true
    }

    local continueButton = New "TextButton" {
        Parent = background,
        Text = "Continue",
        Size = UDim2.new(0.2, 0, 0.1, 0),
        Position = UDim2.new(0.4, 0, 0.85, 0),  -- Bottom center
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        TextColor3 = Color3.fromRGB(0, 0, 0),
        TextSize = 24,
        Font = Enum.Font.SourceSans,
        BackgroundTransparency = 1,  -- Initially invisible
        Visible = false
    }

    local fadeInTween = TweenService:Create(continueButton, TweenInfo.new(0.5), {BackgroundTransparency = 0})
    local moveUpTween = TweenService:Create(textLabel, TweenInfo.new(35, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {Position = UDim2.new(0.1, 0, -1, 0)})

    -- Function to gradually display text like a typewriter
    local function typeWriterEffect()
        local triggerIndex = introText:find(" in ")
        for i = 1, #introText do
            displayedText:set(string.sub(introText, 1, i))
            if i == triggerIndex + 3 then -- Start moving after " in "
                moveUpTween:Play()
            end
            if i == math.floor(#introText / 2) then
                continueButton.Visible = true
                fadeInTween:Play()
            end
            task.wait(0.05)
            if not continueButton.Parent then
                break  -- Stop the loop if the GUI has been removed
            end
        end
    end

    -- Skip the dialogue and remove the GUI when the button is clicked
    continueButton.MouseButton1Click:Connect(function()
        screenGui:Destroy()  -- Unparents the GUI, effectively removing it from the player's screen
    end)

    -- Start the typewriter effect
    spawn(typeWriterEffect)
end

return IntroSequenceController
