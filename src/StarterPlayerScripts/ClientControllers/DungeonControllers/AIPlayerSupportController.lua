local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CustomPackages = ReplicatedStorage.CustomPackages

local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local partcache = require(Packages.partcache)
local FastCast = require(CustomPackages.FastCastFolder.FastCastRedux)
local AIPlayerSupportController = Knit.CreateController { Name = "AIPlayerSupportController" }

local orbitPart = nil
local weld = nil
local orbitRadius = 2
local orbitHeight = 2.5
local orbitSpeed = 2
local angle = 0

function init()
	warn("AIPlayerSupportController Started")

	local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
	local head = character:WaitForChild("Head")

	-- Create the orbiting sphere
	orbitPart = Instance.new("Part")
	orbitPart.Shape = Enum.PartType.Ball
	orbitPart.Size = Vector3.new(0.5, 0.5, 0.5)
	orbitPart.Material = Enum.Material.Neon
	orbitPart.Color = Color3.fromRGB(0, 255, 255)
	orbitPart.Anchored = false
	orbitPart.CanCollide = false
	orbitPart.Massless = true
	orbitPart.Name = "OrbitingSupport"
	orbitPart.Position = head.Position + Vector3.new(orbitRadius, orbitHeight, 0)
	orbitPart.Parent = workspace

	-- Weld it to the head
	weld = Instance.new("Weld")
	weld.Part0 = head
	weld.Part1 = orbitPart
	weld.C0 = CFrame.new(orbitRadius, orbitHeight, 0)
	weld.Parent = orbitPart

	-- Orbit logic using Weld.C0
	RunService:BindToRenderStep("OrbitSupport", Enum.RenderPriority.Character.Value + 1, function(dt)
		if not character or not head or not orbitPart or not weld then return end

		angle += orbitSpeed * dt

		local offset = CFrame.new(
			math.cos(angle) * orbitRadius,
			orbitHeight,
			math.sin(angle) * orbitRadius
		)

		weld.C0 = offset
	end)
end

function AIPlayerSupportController:KnitStart()
	
end

function AIPlayerSupportController:KnitInit()
	-- Optional initialization
end

return AIPlayerSupportController
