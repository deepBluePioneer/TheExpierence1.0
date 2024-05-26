local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Knit = require(Packages:WaitForChild("Knit"))

local vizController = Knit.CreateController { Name = "vizController" }

-- Store the initial sizes and positions of the visuals
local initialSizes = {}
local initialPositions = {}

-- Custom scale factor range
local maxLoudness = 0.1  -- Adjust this based on typical loudness range
local scaleFactor = 100  -- Increase the scaling factor for more noticeable changes

-- Frequency range selection
local minFrequency = 8000  -- Minimum frequency for mid to high-end range (in Hz)
local maxFrequency = 24000 -- Maximum frequency for mid to high-end range (in Hz)

function vizController:visuals()
    return CollectionService:GetTagged("viz")
end

function vizController:AdjustVisualsBasedOnSpectrum(analyzer)
    local visuals = self:visuals()

    -- Store initial sizes and positions if not already stored
    if not next(initialSizes) then
        for _, visual in ipairs(visuals) do
            initialSizes[visual] = visual.Size
            initialPositions[visual] = visual.Position
        end
    end

    -- Determine the frequency range in the spectrum that corresponds to the desired frequency range
    local spectrumLength = 24000  -- AudioAnalyzer spectrum covers 0 Hz to 24,000 Hz
    local spectrum = analyzer:GetSpectrum()
    local totalBins = #spectrum
    local minBin = math.floor((minFrequency / spectrumLength) * totalBins) + 1
    local maxBin = math.floor((maxFrequency / spectrumLength) * totalBins)

    -- Determine the number of frequency ranges based on the number of visuals
    local numVisuals = #visuals
    local rangeSize = math.floor((maxBin - minBin + 1) / numVisuals)

    spawn(function()
        while true do
            local spectrum = analyzer:GetSpectrum()
            if not spectrum or #spectrum == 0 then
                warn("GetSpectrum returned nil or empty.")
                wait(0.1)
                continue
            end

            -- Normalize the spectrum values to a 0-1 range based on maxLoudness
            local normalizedSpectrum = {}
            for i = minBin, maxBin do
                normalizedSpectrum[i - minBin + 1] = math.clamp(spectrum[i] / maxLoudness, 0, 1)
            end

            -- Adjust visuals based on the averaged spectrum values within their range
            for i, visual in ipairs(visuals) do
                local startIdx = (i - 1) * rangeSize + 1
                local endIdx = math.min(i * rangeSize, maxBin - minBin + 1)
                local sampleValue = 0

                -- Average the spectrum values within the range
                for j = startIdx, endIdx do
                    sampleValue = sampleValue + (normalizedSpectrum[j] or 0)
                end
                sampleValue = sampleValue / (endIdx - startIdx + 1)

                -- Safeguard against negative zero
                if sampleValue < 0 then
                    sampleValue = 0
                end

                local initialSize = initialSizes[visual]
                local initialPosition = initialPositions[visual]
                local newSize = Vector3.new(
                    initialSize.X, 
                    initialSize.Y * (1 + sampleValue * scaleFactor), 
                    initialSize.Z
                )

                local goal = {
                    Size = newSize,
                    Position = initialPosition + Vector3.new(0, (newSize.Y - initialSize.Y) / 2, 0)
                }

                local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
                local tween = TweenService:Create(visual, tweenInfo, goal)
                tween:Play()
            end

            wait(0.05)  -- Adjust the frequency of updates as needed
        end
    end)
end

function vizController:KnitStart()
    -- Create the AudioPlayer, AudioAnalyzer, and Wire instances
    local audioPlayer = Instance.new("AudioPlayer")
    local audioAnalyzer = Instance.new("AudioAnalyzer")
    local wire = Instance.new("Wire")
    local deviceOutput = Instance.new("AudioDeviceOutput")

    -- Set the asset ID for the AudioPlayer
    audioPlayer.AssetId = "rbxassetid://7028518546"  -- Example sound ID

    -- Connect the Wire
    wire.SourceInstance = audioPlayer
    wire.TargetInstance = audioAnalyzer

    -- Parent the instances
    audioPlayer.Parent = workspace
    audioAnalyzer.Parent = workspace
    wire.Parent = workspace
    deviceOutput.Parent = workspace

    -- Connect the AudioPlayer to the AudioDeviceOutput
    local outputWire = Instance.new("Wire")
    outputWire.SourceInstance = audioPlayer
    outputWire.TargetInstance = deviceOutput
    outputWire.Parent = workspace

    -- Play the audio
    audioPlayer:Play()

    -- Wait for the AudioPlayer to be ready
    while not audioPlayer.IsReady do
        wait(0.1)
    end

    -- Debug to check if the AudioAnalyzer is correctly attached
    print("AudioAnalyzer created for AudioPlayer:", audioPlayer.Name)

    -- Monitor and adjust visual elements based on the frequency spectrum
    self:AdjustVisualsBasedOnSpectrum(audioAnalyzer)
end

function vizController:KnitInit()
    -- Add controller initialization logic here
end

return vizController
