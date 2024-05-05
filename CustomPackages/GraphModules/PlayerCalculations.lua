game.Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid")
        
        -- Wait until character components are properly loaded
        humanoid.JumpPower = humanoid.JumpPower
        humanoid.WalkSpeed = humanoid.WalkSpeed

        local gravity = workspace.Gravity -- Gets the current gravity of the Workspace.
        
        -- Time spent in the air derived from the JumpPower and Gravity
        local timeInAir = (2 * humanoid.JumpPower) / gravity

        -- Maximum horizontal jump distance in studs
        local maxJumpDistanceStuds = humanoid.WalkSpeed * timeInAir

        -- Conversion factor from studs to meters (1 stud is roughly 0.28 meters)
        local studsToMeters = 0.28

        -- Maximum horizontal jump distance in meters
        local maxJumpDistanceMeters = maxJumpDistanceStuds * studsToMeters

        print("Max jump distance: " .. maxJumpDistanceMeters .. " meters")
    end)
end)
